"""paper-daemon driven for real against stub CUPS and a stub printer (#384).

Nothing here can print: lp, lpstat, lpoptions, ipptool, sudo, ssh, cancel and
journalctl are generated stubs placed FIRST on PATH, the renderer is a fake
print-auto, and ~/Paper is a temporary directory. The stubs keep one JSON
state file (the queue, the PPD, the printer) and log every call, so each test
asserts both the outcome directory and what was — or was not — sent.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
DAEMON = Path(os.environ.get("PAPER_DAEMON_SCRIPT", REPO_ROOT / "pkgs/paper-daemon/paper-daemon.py"))
JOBS_TEST = Path(os.environ.get("PAPER_JOBS_TEST_FILE", REPO_ROOT / "pkgs/paper-daemon/get-jobs.test"))
PRINTER_TEST = Path(os.environ.get("PAPER_PRINTER_TEST_FILE", REPO_ROOT / "pkgs/paper-daemon/printer-state.test"))
PINNED = "ipp://10.42.0.4:631/ipp/print"
QUEUE = "Brother_HL_L2445DW"
URF_PPD = '*PPD-Adobe: "4.3"\n*cupsFilter2: "image/urf image/urf 100 -"\n'

FAKE_CUPS = r'''
import json, os, sys
from pathlib import Path

STATE = Path(os.environ["FAKE_STATE"])
QUEUE = "Brother_HL_L2445DW"
PINNED = "ipp://10.42.0.4:631/ipp/print"
URF_PPD = '*PPD-Adobe: "4.3"\n*cupsFilter2: "image/urf image/urf 100 -"\n'

def load():
    return json.loads(STATE.read_text())

def save(state):
    STATE.write_text(json.dumps(state))

def emit_ipp(groups, status="successful-ok"):
    print(json.dumps(groups, indent=4))
    print(status)

def main(name):
    args = sys.argv[1:]
    state = load()
    state["calls"].append([name, *args])
    save(state)

    if name == "lp":
        title = args[args.index("-t") + 1]
        pdf = Path(args[-1])
        pages = int(pdf.read_text().split("PAGES=")[1].split()[0])
        state["next_id"] += 1
        job = {"id": state["next_id"], "title": title, "pages": pages, "args": args}
        state["jobs"].append(job)
        if state.get("disable_on_lp"):
            state["queue_enabled"] = False
        save(state)
        print(f"request id is {QUEUE}-{job['id']} (1 file(s))")
        return 0
    if name == "lpstat":
        if args[:1] == ["-v"]:
            print(f"device for {QUEUE}: {state['device_uri']}")
            return 0
        if args[:1] == ["-p"]:
            word = "enabled" if state["queue_enabled"] else "disabled"
            print(f"printer {QUEUE} is idle.  {word} since Sun 13 Sep 2026")
            return 0
        print("fake lpstat -l -o")
        return 0
    if name == "lpoptions":
        # The real one resolves the queue through Avahi first; with the
        # Brother in Deep Sleep it says this about a healthy queue (2026-09-15).
        print(f"lpoptions: Unable to get PPD file for {QUEUE}: No such file or directory",
              file=sys.stderr)
        return 0
    if name == "sudo":
        rest = args[1:] if args[:1] == ["-n"] else args
        if rest == ["systemctl", "restart", "ensure-printers.service"]:
            if state["repair_fixes"]:
                state.update(device_uri=PINNED, queue_enabled=True)
                Path(os.environ["PAPER_PPD"]).write_text(URF_PPD)
                save(state)
            return 0
        if rest[:1] == ["cat"]:
            if state.get("sudo_denied"):
                print("sudo: a password is required", file=sys.stderr)
                return 1
            path = Path(rest[1])
            if not path.exists():
                print(f"cat: {path}: No such file or directory", file=sys.stderr)
                return 1
            os.chmod(path, 0o600)
            sys.stdout.write(path.read_text())
            os.chmod(path, 0)
            return 0
        print(f"fake sudo: unexpected {rest}", file=sys.stderr)
        return 1
    if name == "ipptool":
        test = args[-1]
        which = next((a.split("=", 1)[1] for a in args if a.startswith("which=")), None)
        if test.endswith("get-printer-attributes.test"):
            # The stock test's dump is invalid JSON on the real Brother
            # (trailing comma); model that, so the daemon must not use it.
            print('[{"group-tag": "printer-attributes-tag", "printer-state": 3, "r": [1,],}]')
            return 0
        if test.endswith("printer-state.test"):
            if state.get("asleep_probes", 0) > 0:
                state["asleep_probes"] -= 1
                save(state)
                print("ipptool: Unable to connect to 10.42.0.4 on port 631", file=sys.stderr)
                return 1
            if state["printer_state"] is None:
                print("ipptool: Unable to connect to 10.42.0.4 on port 631", file=sys.stderr)
                return 1
            emit_ipp([{"group-tag": "operation-attributes-tag"},
                      {"group-tag": "printer-attributes-tag",
                       "printer-state": state["printer_state"],
                       "printer-state-reasons": "none"}])
            return 0
        if which == "all":
            emit_ipp([{"group-tag": "unsupported-attributes-tag", "which-jobs": "all"}],
                     "client-error-attributes-or-values-not-supported")
            return 1
        state["polls"] += 1
        save(state)
        groups = [{"group-tag": "operation-attributes-tag"}]
        mode = state["printer_mode"]
        visible = state["polls"] > state["polls_hidden"] * 2
        for job in state["jobs"]:
            if mode == "never" or not visible:
                continue
            impressions = state["impressions"] if state["impressions"] is not None else job["pages"]
            if mode == "complete" and which == "completed":
                groups.append({"group-tag": "job-attributes-tag", "job-id": 400 + job["id"],
                               "job-name": job["title"], "job-state": 9,
                               "job-state-reasons": "job-completed-successfully",
                               "job-impressions-completed": impressions})
            elif mode == "aborted" and which == "completed":
                groups.append({"group-tag": "job-attributes-tag", "job-id": 400 + job["id"],
                               "job-name": job["title"], "job-state": 8,
                               "job-state-reasons": "aborted-by-system",
                               "job-impressions-completed": 0})
            elif mode == "processing" and which == "not-completed":
                groups.append({"group-tag": "job-attributes-tag", "job-id": 400 + job["id"],
                               "job-name": job["title"], "job-state": 5,
                               "job-state-reasons": "job-printing",
                               "job-impressions-completed": 1})
        if state.get("glued") and which == "completed":
            # ipptool -j as the real Brother answers two finished jobs: the
            # second job's attributes continue the first job's object with no
            # separator (2026-09-14, jobs 299 and 298). Not valid JSON.
            jobs = [g for g in groups if g["group-tag"] == "job-attributes-tag"]
            jobs.append({"group-tag": "job-attributes-tag", "job-id": 298,
                         "job-name": "paper-older-20260914T085707", "job-state": 9,
                         "job-state-reasons": "job-completed-successfully",
                         "job-impressions-completed": 1})
            blocks = [",\n".join(f'        "{k}": {json.dumps(v)}' for k, v in j.items() if k != "group-tag")
                      for j in jobs]
            print('[\n    {\n        "group-tag": "operation-attributes-tag"\n    },\n'
                  '    {\n        "group-tag": "job-attributes-tag",\n' + "\n".join(blocks) + "\n    }\n]")
            print("successful-ok")
            return 0
        emit_ipp(groups)
        return 0
    if name == "journalctl":
        print("fake cups journal")
        return 0
    # ssh, cancel: logged above, succeed.
    return 0
'''

FAKE_PRINT_AUTO = r'''
import argparse, json, os, re, sys
from pathlib import Path

ap = argparse.ArgumentParser()
ap.add_argument("input", type=Path)
ap.add_argument("--output-dir", type=Path, required=True)
ap.add_argument("--target-pages", type=int)
ap.add_argument("--profile")
ap.add_argument("--sides")
args = ap.parse_args()
with open(os.environ["FAKE_RENDER_LOG"], "a") as log:
    log.write(json.dumps(sys.argv[1:]) + "\n")
text = args.input.read_text()
if "<!-- render: crash -->" in text:
    print("Chrome PDF export failed", file=sys.stderr)
    sys.exit(1)
if "<!-- render: no-decision-key -->" in text:
    (args.output_dir / "decision.json").write_text(json.dumps({"pages_rendered": 1}))
    sys.exit(0)
match = re.search(r"<!-- pages: (\d+) -->", text)
pages = int(match.group(1)) if match else 1
decision = {"profile": args.profile or "source-serif", "require_one_page": False,
            "sides": args.sides or "duplex", "filename": "doc.pdf", "title": "Doc"}
(args.output_dir / "doc.pdf").write_text(f"%PDF fake PAGES={pages}\n")
check = ("not_applicable" if args.target_pages is None
         else "pass" if args.target_pages == pages else "fail")
(args.output_dir / "decision.json").write_text(json.dumps({
    "decision": decision, "provenance": "fallback", "overridden": [],
    "pages_rendered": pages, "target_pages": args.target_pages,
    "length_check": check}))
sys.exit(3 if check == "fail" else 0)
'''


class DaemonHarness(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        base = Path(self.tmp.name)
        self.paper = base / "Paper"
        self.intake = self.paper / "intake"
        self.intake.mkdir(parents=True)
        self.ppd = base / "Brother.ppd"
        self.ppd.write_text(URF_PPD)
        self.render_log = base / "render.log"
        self.state_path = base / "state.json"
        self.state = {
            "device_uri": PINNED, "queue_enabled": True,
            "printer_state": 3, "repair_fixes": True,
            "printer_mode": "complete", "polls_hidden": 0, "impressions": None,
            "jobs": [], "next_id": 300, "polls": 0, "calls": [],
        }
        self.save_state()

        stubs = base / "bin"
        stubs.mkdir()
        (stubs / "fakecups.py").write_text(FAKE_CUPS)
        for name in ("lp", "lpstat", "lpoptions", "ipptool", "sudo", "ssh",
                     "cancel", "journalctl"):
            stub = stubs / name
            stub.write_text(
                f"#!{sys.executable}\n"
                f"import sys; sys.path.insert(0, {str(stubs)!r})\n"
                f"import fakecups; sys.exit(fakecups.main({name!r}))\n")
            stub.chmod(0o755)
        self.print_auto = base / "fake-print-auto.py"
        self.print_auto.write_text(FAKE_PRINT_AUTO)

        self.env = {
            **os.environ,
            "PATH": f"{stubs}{os.pathsep}{os.environ.get('PATH', '')}",
            "FAKE_STATE": str(self.state_path),
            "FAKE_RENDER_LOG": str(self.render_log),
            "PAPER_ROOT": str(self.paper),
            "PAPER_PRINT_AUTO": str(self.print_auto),
            "PAPER_JOBS_TEST": str(JOBS_TEST),
            "PAPER_PRINTER_TEST": str(PRINTER_TEST),
            "PAPER_PPD": str(self.ppd),
            "PAPER_NOW": "2026-09-13T22:00:00",
            "PAPER_SETTLE_SECONDS": "0.01",
            "PAPER_SETTLE_MAX": "1",
            "PAPER_RESCAN_GRACE": "0",
            "PAPER_POLL_INTERVAL": "0.01",
            "PAPER_POLL_BASE_SECONDS": "0.6",
            "PAPER_POLL_PER_PAGE": "0",
            "PAPER_WAKE_SECONDS": "0.3",
            "PAPER_WAKE_INTERVAL": "0.01",
            "PYTHONDONTWRITEBYTECODE": "1",
        }

    def tearDown(self) -> None:
        self.tmp.cleanup()

    # helpers
    def save_state(self) -> None:
        self.state_path.write_text(json.dumps(self.state))

    def load_state(self) -> dict:
        return json.loads(self.state_path.read_text())

    def calls(self, name: str) -> list[list[str]]:
        return [c[1:] for c in self.load_state()["calls"] if c[0] == name]

    def drop(self, slug: str, body: str = "# Doc\n", front: str | None = None) -> Path:
        """The agent's whole contract: write a dot-tmp, rename into place."""
        text = (f"---\n{front}\n---\n" if front else "") + body
        tmp = self.intake / f".{slug}.md.tmp"
        tmp.write_text(text)
        final = self.intake / f"{slug}.md"
        tmp.rename(final)
        return final

    def daemon(self, *args: str, now: str | None = None) -> subprocess.CompletedProcess[str]:
        env = dict(self.env)
        if now:
            env["PAPER_NOW"] = now
        return subprocess.run([sys.executable, str(DAEMON), *args], env=env,
                              capture_output=True, text=True, timeout=60)

    def receipt(self, job: str) -> dict:
        return json.loads((self.paper / "printed" / job / "receipt.json").read_text())


class WorkingHoursTests(DaemonHarness):
    def test_daytime_drop_prints_with_a_receipt_from_the_printer(self) -> None:
        self.drop("brief", "# Brief\n<!-- pages: 10 -->\n", "target_pages: 10\nsides: one-sided")
        result = self.daemon("run")
        self.assertEqual(result.returncode, 0, result.stderr)

        receipt = self.receipt("brief")
        self.assertEqual(receipt["pages"], 10)
        self.assertEqual(receipt["impressions_completed"], 10)
        self.assertEqual(receipt["printer_job_state"], "completed")
        self.assertEqual(receipt["printer_job_id"], 701)  # the stub numbers printer jobs 400 + CUPS id
        self.assertEqual(receipt["cups_job_id"], f"{QUEUE}-301")
        self.assertEqual(receipt["sides"], "one-sided")
        self.assertEqual(receipt["repairs"], [])
        self.assertIsNone(receipt["media_sheets_completed"])
        self.assertEqual(len(receipt["source_sha256"]), 64)
        self.assertTrue((self.paper / "printed/brief/source.md").exists())
        self.assertEqual(list(self.intake.iterdir()), [])

        (lp,) = self.calls("lp")
        self.assertEqual(lp[:8], ["-d", QUEUE, "-n", "1", "-o", "media=A4", "-o", "sides=one-sided"])
        self.assertTrue(lp[lp.index("-t") + 1].startswith("paper-brief-20260913T220000"))
        self.assertEqual(self.calls("ssh"), [])
        rendered = json.loads(self.render_log.read_text().splitlines()[0])
        self.assertIn("--target-pages", rendered)
        self.assertEqual(rendered[rendered.index("--sides") + 1], "one-sided")

    def test_two_finished_jobs_in_one_get_jobs_answer_still_give_a_receipt(self) -> None:
        # The first real two-page print after an earlier job failed at the
        # deadline: strict JSON could not read ipptool's glued job list.
        self.state["glued"] = True
        self.save_state()
        self.drop("second")
        result = self.daemon("run")
        self.assertEqual(result.returncode, 0, result.stderr)
        receipt = self.receipt("second")
        self.assertEqual(receipt["printer_job_state"], "completed")
        self.assertFalse((self.paper / "failed").exists() and any((self.paper / "failed").iterdir()))

    def test_receipt_waits_for_the_printer_not_for_lp(self) -> None:
        self.state["polls_hidden"] = 3  # the printer lists the job only later
        self.save_state()
        self.drop("late")
        result = self.daemon("run")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.receipt("late")["impressions_completed"], 1)
        self.assertGreater(self.load_state()["polls"], 6)

    def test_never_asks_the_brother_for_which_jobs_all(self) -> None:
        self.drop("doc")
        self.daemon("run")
        whiches = {a for c in self.calls("ipptool") for a in c if a.startswith("which=")}
        self.assertIn("which=completed", whiches)
        self.assertNotIn("which=all", whiches)

    def test_a_freshly_renamed_drop_is_processed_in_the_same_run(self) -> None:
        path = self.drop("fresh")
        now = time.time()
        os.utime(path, (now, now))
        result = self.daemon("run")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.paper / "printed/fresh/receipt.json").exists())

    def test_a_rename_just_after_an_empty_scan_is_caught_by_the_grace_rescan(self) -> None:
        # The .tmp write starts the run; the rename that follows is merged
        # into that start by systemd and raises no run of its own.
        env = dict(self.env, PAPER_RESCAN_GRACE="2")
        proc = subprocess.Popen([sys.executable, str(DAEMON), "run"], env=env,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        time.sleep(0.7)
        self.drop("late-rename")
        _, err = proc.communicate(timeout=60)
        self.assertEqual(proc.returncode, 0, err)
        self.assertTrue((self.paper / "printed/late-rename/receipt.json").exists())

    def test_dotfiles_tmp_and_subdirectories_are_ignored(self) -> None:
        adopted = self.intake / ".adopted-2026-09-09"
        adopted.mkdir()
        (adopted / "house-computer.md").write_text("# already printed\n")
        (self.intake / ".half.md.tmp").write_text("# still writing\n")
        (self.intake / "notes.txt").write_text("not markdown\n")
        sub = self.intake / "folder"
        sub.mkdir()
        (sub / "inner.md").write_text("# nested\n")
        result = self.daemon("run")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls("lp"), [])
        self.assertFalse(self.render_log.exists())
        self.assertTrue((adopted / "house-computer.md").exists())
        self.assertTrue((self.intake / ".half.md.tmp").exists())

    def test_a_second_drop_with_the_same_name_gets_its_own_job(self) -> None:
        self.drop("same")
        self.daemon("run")
        self.drop("same")
        result = self.daemon("run")
        self.assertEqual(result.returncode, 0, result.stderr)
        printed = sorted(p.name for p in (self.paper / "printed").iterdir())
        self.assertEqual(len(printed), 2)
        self.assertEqual(printed[0], "same")
        self.assertTrue(printed[1].startswith("same-20260913-220000"))


class QuietHoursTests(DaemonHarness):
    def test_night_drop_waits_in_outbox_and_prints_at_the_morning_flush(self) -> None:
        self.drop("overnight", "# Overnight\n", "sides: one-sided")
        result = self.daemon("run", now="2026-09-14T02:00:00")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.paper / "outbox/overnight/doc.pdf").exists())
        self.assertEqual(self.calls("lp"), [])

        # A catch-up flush at 03:00 must not print.
        result = self.daemon("flush", now="2026-09-14T03:00:00")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls("lp"), [])
        # Nor may a sweep inside quiet hours.
        self.daemon("run", now="2026-09-14T05:59:00")
        self.assertEqual(self.calls("lp"), [])

        result = self.daemon("flush", now="2026-09-14T06:05:00")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.paper / "outbox/overnight").exists())
        receipt = self.receipt("overnight")
        self.assertEqual(receipt["impressions_completed"], 1)
        self.assertEqual(receipt["dropped_at"], "2026-09-14T02:00:00")
        self.assertEqual(receipt["submitted_at"], "2026-09-14T06:05:00")

    def test_force_prints_at_night(self) -> None:
        self.drop("urgent", front="force: true")
        result = self.daemon("run", now="2026-09-14T02:00:00")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.paper / "printed/urgent/receipt.json").exists())

    def test_a_daytime_sweep_also_drains_a_leftover_outbox(self) -> None:
        self.drop("leftover")
        self.daemon("run", now="2026-09-14T01:00:00")
        self.assertEqual(self.calls("lp"), [])
        result = self.daemon("run", now="2026-09-14T09:00:00")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.paper / "printed/leftover/receipt.json").exists())


class RejectionTests(DaemonHarness):
    def test_target_mismatch_is_rejected_and_nothing_is_sent(self) -> None:
        self.drop("long", "# Long\n<!-- pages: 2 -->\n", "target_pages: 1")
        result = self.daemon("run")
        self.assertEqual(result.returncode, 0, result.stderr)
        reason = json.loads((self.paper / "rejected/long/reason.json").read_text())
        self.assertEqual(reason["pages_rendered"], 2)
        self.assertEqual(reason["target_pages"], 1)
        self.assertTrue((self.paper / "rejected/long/source.md").exists())
        self.assertEqual(self.calls("lp"), [])

    def test_invalid_front_matter_is_rejected_before_rendering(self) -> None:
        self.drop("bad", front="target_pages: ten")
        result = self.daemon("run")
        self.assertEqual(result.returncode, 0, result.stderr)
        reason = json.loads((self.paper / "rejected/bad/reason.json").read_text())
        self.assertIn("target_pages", reason["reason"])
        self.assertFalse(self.render_log.exists())
        self.assertEqual(self.calls("lp"), [])

    def test_document_metadata_in_front_matter_is_tolerated(self) -> None:
        self.drop("meta", front="title: A brief\ntags:\n  - one\n  - two\nprofile: times")
        result = self.daemon("run")
        self.assertEqual(result.returncode, 0, result.stderr)
        rendered = json.loads(self.render_log.read_text().splitlines()[0])
        self.assertEqual(rendered[rendered.index("--profile") + 1], "times")


class QueueGuardTests(DaemonHarness):
    def test_hijacked_device_uri_is_repaired_then_printed(self) -> None:
        self.state["device_uri"] = "implicitclass://x/"
        self.save_state()
        self.drop("sabotage-uri")
        result = self.daemon("run")
        self.assertEqual(result.returncode, 0, result.stderr)
        receipt = self.receipt("sabotage-uri")
        self.assertEqual(len(receipt["repairs"]), 1)
        self.assertIn("implicitclass://x/", receipt["repairs"][0]["problems"][0])
        self.assertEqual(receipt["repairs"][0]["remaining"], [])
        self.assertEqual(self.calls("sudo"), [["-n", "systemctl", "restart", "ensure-printers.service"]])
        self.assertEqual(len(self.calls("lp")), 1)

    def test_raw_queue_without_ppd_is_repaired_then_printed(self) -> None:
        self.ppd.unlink()
        self.drop("sabotage-ppd")
        result = self.daemon("run")
        self.assertEqual(result.returncode, 0, result.stderr)
        problems = self.receipt("sabotage-ppd")["repairs"][0]["problems"]
        self.assertTrue(any("raw queue" in p for p in problems))
        self.assertTrue(any("missing" in p for p in problems))

    def test_ppd_without_urf_filter_is_a_problem(self) -> None:
        self.ppd.write_text('*PPD-Adobe: "4.3"\n')
        result = self.daemon("check-queue")
        self.assertEqual(result.returncode, 1)
        report = json.loads(result.stdout)
        self.assertTrue(any("image/urf" in p for p in report["problems"]))

    @unittest.skipIf(os.geteuid() == 0, "root reads a 0000 file directly")
    def test_unreadable_ppd_is_read_through_sudo(self) -> None:
        self.ppd.chmod(0)
        result = self.daemon("check-queue")
        self.ppd.chmod(0o600)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(["-n", "cat", str(self.ppd)], self.calls("sudo"))

    def test_failed_repair_fails_loudly_and_sends_nothing(self) -> None:
        self.state.update(device_uri="implicitclass://x/", repair_fixes=False)
        self.save_state()
        self.drop("unrepairable")
        result = self.daemon("run")
        self.assertEqual(result.returncode, 1)
        failure = json.loads((self.paper / "failed/unrepairable/failure.json").read_text())
        self.assertIn("queue unhealthy after one repair", failure["reason"])
        self.assertEqual(len(failure["repairs"]), 1)
        self.assertEqual(self.calls("lp"), [])
        self.assertEqual(self.calls("ssh"), [])

    def test_unreachable_printer_is_unhealthy(self) -> None:
        self.state["printer_state"] = None
        self.save_state()
        result = self.daemon("check-queue")
        self.assertEqual(result.returncode, 1)
        self.assertIn("did not answer", json.loads(result.stdout)["problems"][0])

    def test_check_queue_repair_restores_a_sabotaged_queue(self) -> None:
        self.state["device_uri"] = "implicitclass://x/"
        self.save_state()
        self.ppd.unlink()
        result = self.daemon("check-queue", "--repair")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(json.loads(result.stdout)["healthy"])
        self.assertEqual(self.load_state()["device_uri"], PINNED)
        self.assertIn("image/urf", self.ppd.read_text())

    def test_a_mute_lpoptions_does_not_make_a_healthy_queue_raw(self) -> None:
        # 2026-09-15: lpoptions failed through Avahi while the Brother slept;
        # the PPD was on disk and the printer answered IPP.
        self.drop("deep-sleep")
        result = self.daemon("run")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.receipt("deep-sleep")["repairs"], [])
        self.assertEqual(self.calls("lpoptions"), [])
        self.assertEqual(self.calls("sudo"), [])

    def test_a_printer_waking_from_deep_sleep_is_waited_for_not_repaired(self) -> None:
        self.state["asleep_probes"] = 3
        self.save_state()
        self.drop("waking")
        result = self.daemon("run")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.receipt("waking")["repairs"], [])
        self.assertEqual(self.calls("sudo"), [])

    def test_an_unreachable_printer_fails_without_restarting_cups(self) -> None:
        self.state["printer_state"] = None
        self.save_state()
        self.drop("asleep")
        result = self.daemon("run")
        self.assertEqual(result.returncode, 1)
        failure = json.loads((self.paper / "failed/asleep/failure.json").read_text())
        self.assertTrue(failure["reason"].startswith("printer unhealthy: "), failure["reason"])
        self.assertEqual(failure["repairs"], [])
        self.assertEqual(self.calls("sudo"), [])
        self.assertEqual(self.calls("lp"), [])

    @unittest.skipIf(os.geteuid() == 0, "root reads a 0000 file directly")
    def test_a_ppd_nobody_can_read_is_a_problem_not_a_pass(self) -> None:
        self.state["sudo_denied"] = True
        self.save_state()
        self.ppd.chmod(0)
        result = self.daemon("check-queue")
        self.ppd.chmod(0o600)
        self.assertEqual(result.returncode, 1)
        self.assertTrue(any("unreadable" in p for p in json.loads(result.stdout)["problems"]))


class PrinterTruthTests(DaemonHarness):
    def test_impressions_mismatch_is_a_failure_not_a_receipt(self) -> None:
        self.state["impressions"] = 7
        self.save_state()
        self.drop("short", "# Short\n<!-- pages: 10 -->\n")
        result = self.daemon("run")
        self.assertEqual(result.returncode, 1)
        self.assertFalse((self.paper / "printed/short").exists())
        failed = self.paper / "failed/short"
        failure = json.loads((failed / "failure.json").read_text())
        self.assertIn("7 impressions for 10 rendered pages", failure["reason"])
        self.assertEqual(failure["printer_job"]["job-impressions-completed"], 7)
        self.assertIn("completed", failure["ipp"])
        self.assertTrue((failed / "cups-journal.txt").exists())
        self.assertEqual(self.calls("ssh"), [])

    def test_printer_abort_is_a_failure(self) -> None:
        self.state["printer_mode"] = "aborted"
        self.save_state()
        self.drop("aborted")
        result = self.daemon("run")
        self.assertEqual(result.returncode, 1)
        failure = json.loads((self.paper / "failed/aborted/failure.json").read_text())
        self.assertIn("aborted", failure["reason"])

    def test_cups_completed_but_printer_never_saw_it_fails_and_cancels(self) -> None:
        # Job 303's shape: lp succeeded, nothing reached the Brother.
        self.state["printer_mode"] = "never"
        self.save_state()
        self.drop("ghost")
        result = self.daemon("run")
        self.assertEqual(result.returncode, 1)
        failure = json.loads((self.paper / "failed/ghost/failure.json").read_text())
        self.assertIn("never listed", failure["reason"])
        self.assertEqual(self.calls("cancel"), [[f"{QUEUE}-301"]])

    def test_a_job_still_printing_at_the_deadline_is_not_cancelled(self) -> None:
        self.state["printer_mode"] = "processing"
        self.save_state()
        self.drop("slow")
        result = self.daemon("run")
        self.assertEqual(result.returncode, 1)
        failure = json.loads((self.paper / "failed/slow/failure.json").read_text())
        self.assertIn("still processing", failure["reason"])
        self.assertEqual(self.calls("cancel"), [])

    def test_render_crash_fails_loudly(self) -> None:
        self.drop("crash", "<!-- render: crash -->\n")
        result = self.daemon("run")
        self.assertEqual(result.returncode, 1)
        failure = json.loads((self.paper / "failed/crash/failure.json").read_text())
        self.assertIn("render failed", failure["reason"])
        self.assertIn("Chrome PDF export failed", failure["render_output"])
        self.assertEqual(self.calls("lp"), [])

    def test_one_failure_does_not_block_the_next_drop(self) -> None:
        self.drop("a-crash", "<!-- render: crash -->\n")
        self.drop("b-fine")
        result = self.daemon("run")
        self.assertEqual(result.returncode, 1)
        self.assertTrue((self.paper / "failed/a-crash").exists())
        self.assertTrue((self.paper / "printed/b-fine/receipt.json").exists())

    def test_cups_stopping_the_queue_cancels_a_job_the_printer_never_saw(self) -> None:
        # A stopped queue holds its job, and the next ensure-printers run
        # re-enables the queue: without the cancel it prints unattended.
        self.state.update(printer_mode="never", disable_on_lp=True)
        self.save_state()
        self.drop("stopped")
        result = self.daemon("run")
        self.assertEqual(result.returncode, 1)
        failure = json.loads((self.paper / "failed/stopped/failure.json").read_text())
        self.assertIn("CUPS stopped the queue", failure["reason"])
        self.assertEqual(self.calls("cancel"), [[f"{QUEUE}-301"]])

    def test_an_unexpected_crash_becomes_failed_not_a_stranded_work_dir(self) -> None:
        self.drop("a-malformed", "<!-- render: no-decision-key -->\n")
        self.drop("b-fine")
        result = self.daemon("run")
        self.assertEqual(result.returncode, 1)
        failure = json.loads((self.paper / "failed/a-malformed/failure.json").read_text())
        self.assertIn("crashed", failure["reason"])
        self.assertIn("KeyError", failure["traceback"])
        self.assertEqual(list((self.paper / "work").iterdir()), [])
        self.assertTrue((self.paper / "printed/b-fine/receipt.json").exists())
        self.assertEqual(self.calls("ssh"), [])

    def test_a_broken_outbox_entry_does_not_block_the_morning_flush(self) -> None:
        self.drop("a-broken")
        self.drop("b-good")
        self.daemon("run", now="2026-09-14T02:00:00")
        (self.paper / "outbox/a-broken/decision.json").write_text("{not json")
        result = self.daemon("flush", now="2026-09-14T06:05:00")
        self.assertEqual(result.returncode, 1)
        self.assertTrue((self.paper / "failed/a-broken/failure.json").exists())
        self.assertTrue((self.paper / "printed/b-good/receipt.json").exists())
        self.assertEqual(list((self.paper / "outbox").iterdir()), [])


if __name__ == "__main__":
    unittest.main()
