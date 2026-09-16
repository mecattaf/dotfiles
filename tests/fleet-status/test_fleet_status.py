"""checks.fleet-status — the bounded, partial, honest snapshot (#356).

Hermetic: the fan-out is driven through FLEET_STATUS_SSH with a fake ssh that
plays four nodes (healthy, slow, dead, garbage), and the collector runs inside
the build sandbox where systemctl/journalctl do not exist — which is exactly
the "tried and could not tell" case that must grade unknown, never zero.
"""

from __future__ import annotations

import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import textwrap
import time
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = Path(os.environ.get("FLEET_STATUS_PY", REPO_ROOT / "pkgs/fleet-status/fleet_status.py"))

spec = importlib.util.spec_from_file_location("fleet_status", SCRIPT)
fs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fs)


def healthy_report(profile: str = "strix-inference") -> dict:
    """A valid schema-1 node report built from the module's own fact helpers."""
    m = fs.fact
    s = {
        "identity": {"hostname": m("A", "t"), "profile": m(profile, "t"), "boot_id": m("b00710", "t"), "uptime_s": m(7200, "t")},
        "nix": {
            "current": m("/nix/store/x-sys", "t"),
            "booted": m("/nix/store/x-sys", "t"),
            "generation": m({"number": 12, "link": "system-12-link", "is_current": True}, "t"),
            "version": m("26.11", "t"),
            "revision": fs.unknown("t", "system.configurationRevision not set"),
            "pending_reboot": m({"pending": True, "differs": ["kernel"]}, "t"),
        },
        "updates": {"status": fs.unknown("update-adopt status --json", "update-adopt not enrolled")},
        "systemd": {"system_state": m("degraded", "t"), "failed_units": m(["broken.service"], "t")},
        "user_manager": {"state": m("running", "t"), "failed_units": m([], "t")},
        "failure_markers": {"markers": m([{"name": "coredump", "summary": "1 new coredump", "mtime": 0}], "t")},
        "pressure": {
            "memory": m({"total": 8 << 30, "available": 4 << 30, "swap_total": 0, "swap_used": 0}, "t"),
            "psi": m({"memory_some": {"avg10": 1.5}}, "t"),
            "load": m([0.5, 0.4, 0.3], "t"),
            "top_cgroups": m([{"cgroup": "system.slice/podman-halogen.service", "memory_current": 3 << 30}], "t"),
        },
        "storage": {"mounts": m([{"mountpoint": "/", "mounted": True, "on_demand": False, "use_pct": 42.0}], "t")},
        "timers": {"system": m({"timers": 3, "non_success": []}, "t"), "user": m({"timers": 1, "non_success": []}, "t")},
        "events": {k: m([], "t") for k in ("coredumps", "unit_failures", "oom_kills", "update_adopt")},
        "inference": {
            "halogen_units": m({"podman-halogen.service": "active"}, "t"),
            "health": m({"status": "ok", "model": "halogen-qwen3.8-flash-next", "busy": False, "in_flight": 0, "queued": 0}, "t"),
            "cache": m({"entries": 1}, "t"),
        },
        "runs": {"tally": fs.by_design("profile roles", "no Tally plane")},
        "attention": {"herdr": fs.by_design("profile roles", "no Herdr server")},
    }
    return {"schema": 1, "kind": "node", "observed_at": fs.now_iso(), "hostname": "A", "profile": profile, "collect_ms": 5, "sections": s}


class FanOut(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = Path(tempfile.mkdtemp())
        (cls.tmp / "A.json").write_text(json.dumps(healthy_report()))
        fake = cls.tmp / "ssh"
        fake.write_text(
            textwrap.dedent(
                f"""\
                #!{sys.executable}
                import os, sys, time
                target = [a for a in sys.argv[1:] if a.startswith("root@")][0][5:]
                if target == "A":
                    sys.stdout.write(open({str(cls.tmp / "A.json")!r}).read()); sys.exit(0)
                if target == "B":
                    time.sleep(30); sys.exit(0)
                if target == "D":
                    print("fleet-status-collect: not json {{"); sys.exit(0)
                sys.stderr.write("ssh: connect to host %s port 22: No route to host\\n" % target)
                sys.exit(255)
                """
            )
        )
        fake.chmod(0o755)
        hosts = [{"name": n, "target": f"root@{n}", "profile": "strix-inference", "transport": "ssh"} for n in "ABCD"]
        (cls.tmp / "hosts.json").write_text(json.dumps(hosts))
        cls.env = dict(os.environ, FLEET_STATUS_SSH=str(fake), FLEET_STATUS_HOSTS_FILE=str(cls.tmp / "hosts.json"))
        cls.env.pop("FLEET_STATUS_HOSTS", None)
        started = time.monotonic()
        proc = subprocess.run([sys.executable, str(SCRIPT), "--json"], capture_output=True, text=True, env=cls.env, timeout=60)
        cls.wall = time.monotonic() - started
        assert proc.returncode == 0, proc.stderr
        cls.snap = json.loads(proc.stdout)
        cls.nodes = {n["name"]: n for n in cls.snap["nodes"]}

    def test_bounded_wall_time(self):
        self.assertLess(self.wall, 12.0, "one slow node must not hang the view")

    def test_schema_valid(self):
        self.assertEqual(fs.validate_snapshot(self.snap), [])

    def test_reachability_per_node(self):
        self.assertEqual(self.nodes["A"]["reachability"], "reachable")
        self.assertEqual(self.nodes["B"]["reachability"], "timeout")
        self.assertEqual(self.nodes["C"]["reachability"], "unreachable")
        self.assertIn("No route to host", self.nodes["C"]["error"])
        self.assertEqual(self.nodes["D"]["reachability"], "error")
        for n in "BCD":
            self.assertIsNone(self.nodes[n]["report"])

    def test_absent_nodes_are_unknown_in_joined_planes(self):
        for n in "BCD":
            up = [u for u in self.snap["updates"] if u["node"] == n][0]
            for key in ("status", "current", "pending_reboot"):
                self.assertEqual(up[key]["grade"], "unknown")
            fail = [f for f in self.snap["failures"] if f["node"] == n]
            self.assertEqual([(f["kind"], f["grade"]) for f in fail], [("node", "unknown")])
            inf = [i for i in self.snap["inference"] if i["node"] == n]
            self.assertEqual(inf[0]["grade"], "unknown")

    def test_healthy_node_failures_come_from_units_and_markers(self):
        ids = {(f["kind"], f["id"]) for f in self.snap["failures"] if f["node"] == "A"}
        self.assertEqual(ids, {("unit", "broken.service"), ("marker", "coredump")})

    def test_render_is_loud_and_never_zero(self):
        text = fs.render(self.snap, color=False)
        lines = text.splitlines()
        self.assertIn("NOT ANSWERING: B, C, D", text)
        block = {}
        current = None
        for line in lines:
            if line and not line.startswith(" "):
                current = line.split()[0]
            block.setdefault(current, []).append(line)
        self.assertIn("UNREACHABLE", "\n".join(block["C"]))
        self.assertIn("TIMEOUT", "\n".join(block["B"]))
        self.assertIn("ERROR", "\n".join(block["D"]))
        for n in "BCD":
            body = "\n".join(block[n])
            for zero in ("failed 0", "load 0", "avail", "all last runs succeeded"):
                self.assertNotIn(zero, body, f"{n} rendered a healthy-looking fact")
        a = "\n".join(block["A"])
        self.assertIn("PENDING REBOOT (kernel)", a)
        self.assertIn("failed 1", a)
        self.assertIn("updates   unknown", a)
        self.assertIn("halogen ok", a)

    def test_ad_hoc_host_list_dials_undeclared_names(self):
        env = dict(self.env, FLEET_STATUS_HOSTS="A,ghost", FLEET_STATUS_NODE_DEADLINE="4")
        proc = subprocess.run([sys.executable, str(SCRIPT)], capture_output=True, text=True, env=env, timeout=30)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertRegex(proc.stdout, r"ghost\s+unprofiled\s+UNREACHABLE")


class Collector(unittest.TestCase):
    def run_collect(self, profile: dict) -> dict:
        tmp = Path(tempfile.mkdtemp())
        (tmp / "profile.json").write_text(json.dumps(profile))
        # An empty PATH makes the sandbox's "no systemd here" true on any box
        # the suite runs on, including a live coordinator.
        (tmp / "bin").mkdir()
        env = dict(os.environ, PATH=str(tmp / "bin"), FLEET_STATUS_TOM_BIN_DIR=str(tmp / "bin"), FLEET_STATUS_PROFILE=str(tmp / "profile.json"), FLEET_STATUS_MARKER_DIR=str(tmp / "markers"))
        (tmp / "markers").mkdir()
        (tmp / "markers" / "coredump").write_text("2026-09-10 12:29 — 1 new coredump(s)\n")
        (tmp / "markers" / ".failure-marker-reconcile.lock").write_text("")
        started = time.monotonic()
        proc = subprocess.run([sys.executable, str(SCRIPT), "collect", "--json"], capture_output=True, text=True, env=env, timeout=30)
        self.assertLess(time.monotonic() - started, 8.0)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        rep = json.loads(proc.stdout)
        # A section that crashed or ran out of budget collapses to one
        # `section` fact; none may do so in a sandbox that answers instantly.
        crashed = {k: v["section"].get("reason") for k, v in rep["sections"].items() if "section" in v}
        self.assertEqual(crashed, {})
        return rep

    def test_appliance_profile_is_missing_by_design_not_unknown(self):
        rep = self.run_collect({"name": "appliance", "user_manager": False, "roles": [], "mounts": [{"mountpoint": "/", "on_demand": False}]})
        self.assertEqual(fs.validate_node_report(rep), [])
        s = rep["sections"]
        self.assertEqual(s["user_manager"]["state"]["grade"], "missing-by-design")
        self.assertEqual(s["user_manager"]["failed_units"]["grade"], "missing-by-design")
        self.assertEqual(s["timers"]["user"]["grade"], "missing-by-design")
        self.assertEqual(s["inference"]["server"]["grade"], "missing-by-design")
        self.assertEqual(s["runs"]["tally"]["grade"], "missing-by-design")
        self.assertEqual(s["attention"]["herdr"]["grade"], "missing-by-design")
        self.assertEqual([m["name"] for m in s["failure_markers"]["markers"]["value"]], ["coredump"])

    def test_missing_tools_grade_unknown_never_empty(self):
        rep = self.run_collect({"name": "strix-desk", "user_manager": True, "roles": ["runs", "attention", "halogen"], "halogen_port": 1, "mounts": []})
        self.assertEqual(fs.validate_node_report(rep), [])
        s = rep["sections"]
        # The sandbox has no systemd: every systemd-backed fact must be unknown.
        for sec, name in (("systemd", "failed_units"), ("user_manager", "failed_units"), ("timers", "system"), ("events", "unit_failures"), ("inference", "health"), ("runs", "kernel_unit"), ("attention", "agents")):
            self.assertEqual(s[sec][name]["grade"], "unknown", f"{sec}.{name}: {s[sec][name]}")
            self.assertIsNone(s[sec][name]["value"])
        self.assertEqual(s["updates"]["status"]["grade"], "unknown")
        self.assertIn("#354", s["updates"]["status"]["reason"])
        self.assertEqual(s["pressure"]["memory"]["grade"], "measured")

    def test_validator_rejects_zero_dressed_as_unknown(self):
        bad = healthy_report()
        bad["sections"]["systemd"]["failed_units"] = {"value": [], "source": "x", "observed_at": "now", "grade": "unknown"}
        errs = fs.validate_node_report(bad)
        self.assertTrue(any("non-measured fact carries a value" in e for e in errs), errs)
        self.assertTrue(any("without reason" in e for e in errs), errs)


class RenderAndFolds(unittest.TestCase):
    """Verifier regressions (2026-09-13)."""

    def node(self, report):
        return {"name": "A", "profile": "strix-desk", "target": "root@A", "reachability": "reachable", "latency_ms": 5, "report": report}

    def test_collapsed_section_renders_unknown_instead_of_crashing(self):
        rep = healthy_report()
        for sec in ("events", "timers", "pressure", "systemd", "nix", "inference"):
            rep["sections"][sec] = {"section": fs.unknown(sec, "collector budget 6s exhausted")}
        self.assertEqual(fs.validate_node_report(rep), [])
        text = "\n".join(fs.render_node(self.node(rep), color=False))
        self.assertIn("UNKNOWN   ", text)
        self.assertIn("events (collector budget 6s exhausted)", text)
        self.assertNotIn("all last runs succeeded", text)
        # The collapsed system manager reads unknown; the user manager's own
        # section still answered, so its measured count may appear.
        self.assertIn("systemd   unknown  failed unknown", text)
        self.assertNotIn("coredumps 0", text)
        self.assertIn("load unknown", text)

    def test_lease_release_closes_a_grant(self):
        rows = [
            {"seq": 1, "payload": {"kind": "lease_grant", "lease": "lease:a"}},
            {"seq": 2, "payload": {"kind": "lease_grant", "lease": "lease:b"}},
            {"seq": 3, "payload": {"kind": "lease_debit", "lease": "lease:a"}},
            {"seq": 4, "payload": {"kind": "lease_release", "lease": "lease:a"}},
            {"seq": 5, "payload": {"kind": "admission_transition", "seat": "gpu-worker"}},
        ]
        ids, last = fs.open_leases([json.dumps(r) for r in rows] + ["not json"])
        self.assertEqual((ids, last), (["lease:b"], 5))

    def test_update_adopt_status_shape_renders(self):
        rep = healthy_report()
        status = {
            "state": "pending-reboot",
            "policy": "rolling",
            "candidate": {"store_path": "/nix/store/abcd1234-nixos-system-worker", "revision": "1dc4860e0000", "reboot_required": True},
            "last_known_good": "/nix/store/ffff0000-nixos-system-worker",
            "last_refusal": {"reason": "busy", "detail": "halogen in_flight=1", "at": "t"},
            "last_attempt": "2026-09-13T03:00:00+00:00",
        }
        rep["sections"]["updates"]["status"] = fs.fact(status, "update-adopt status --json")
        text = "\n".join(fs.render_node(self.node(rep), color=False))
        self.assertIn("state pending-reboot", text)
        self.assertIn("candidate 1dc4860e0000", text)
        self.assertIn("lkg ffff0000-nixos-system-wo", text)
        self.assertIn("refused busy", text)


class HerdrAccounting(unittest.TestCase):
    def test_tree_rss_counts_descendants_only_of_the_pane(self):
        table = {1: (0, 100, 0), 10: (1, 5, 0), 11: (10, 7, 0), 12: (11, 11, 0), 20: (1, 1000, 0)}
        self.assertEqual(fs.tree_rss(10, table), (23, 3))
        self.assertEqual(fs.tree_rss(20, table), (1000, 1))


if __name__ == "__main__":
    unittest.main()
