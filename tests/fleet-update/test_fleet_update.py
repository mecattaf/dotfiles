from __future__ import annotations
import argparse
import importlib.machinery
import importlib.util
import io
import json
import os
import re
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(os.environ.get("FLEET_UPDATE_SCRIPT", Path(__file__).resolve().parents[2] / "home/dot_local/bin/fleet-update"))
loader = importlib.machinery.SourceFileLoader("fleet_update", str(SCRIPT))
spec = importlib.util.spec_from_loader("fleet_update", loader)
fu = importlib.util.module_from_spec(spec)
loader.exec_module(fu)
REV = "a" * 40


def args(**overrides):
    return argparse.Namespace(retry_failed=False, prepare_only=False, **overrides)


class Admission(unittest.TestCase):
    def test_gufo_requires_both_empty_queues(self):
        self.assertEqual(fu.inference_busy("llamacpp:requests_processing 0\nllamacpp:requests_deferred 0\n"), [])
        for metrics in ["", "llamacpp:requests_processing 0\n", "llamacpp:requests_processing 1\nllamacpp:requests_deferred 0\n",
                        "llamacpp:requests_processing 0\nllamacpp:requests_deferred 1\n",
                        "llamacpp:requests_processing NaN\nllamacpp:requests_deferred 0\n",
                        "llamacpp:requests_processing -1\nllamacpp:requests_deferred 0\n"]:
            self.assertTrue(fu.inference_busy(metrics), metrics)

    def test_labels_do_not_hide_a_busy_slot(self):
        self.assertTrue(fu.inference_busy('llamacpp:requests_processing{slot="0"} 0\nllamacpp:requests_processing{slot="1"} 1\nllamacpp:requests_deferred 0\n'))

    def test_compute_admission_covers_alternate_text_and_user_tts_units(self):
        def run(argv, **kwargs):
            if "list-units" in argv:
                return subprocess.CompletedProcess(argv, 0, "gufo-llm-27b.service loaded active running\n", "")
            if "--user" in argv:
                return subprocess.CompletedProcess(argv, 0, "active\n", "")
            return subprocess.CompletedProcess(argv, 3, "inactive\n", "")
        with patch.object(fu.socket, "gethostname", return_value="strix-coordinator"), \
             patch.object(fu, "resources_busy", return_value=[]), patch.object(fu, "run", run), \
             patch.object(fu.urllib.request, "urlopen", return_value=io.BytesIO(b"llamacpp:requests_processing 0\nllamacpp:requests_deferred 1\n")):
            reasons = fu.target_probe()["reasons"]
        self.assertTrue(any("qwen-tts" in reason for reason in reasons))
        self.assertTrue(any("Gufo has work" in reason for reason in reasons))

    def test_pid_identity_checks_boot_and_start_time(self):
        current = fu.process_identity()
        self.assertTrue(fu.owner_alive(current))
        self.assertFalse(fu.owner_alive({**current, "boot": "previous-boot"}))
        self.assertFalse(fu.owner_alive({**current, "start": "pid-reused"}))
        self.assertFalse(fu.owner_alive({**current, "host": "different-host"}))

    def test_low_disk_defers_before_build(self):
        calls = []
        def run(argv, **kw):
            calls.append(argv)
            return subprocess.CompletedProcess(argv, 0, "Filesystem human-readable\n" if argv[1] == "-h" else "Avail\n1000000000\n", "")
        with patch.object(fu, "run", run), self.assertRaises(fu.Pending):
            fu.disk_gate()
        self.assertEqual(calls, [["df", "-h", "/"], ["df", "-B1", "--output=avail", "/"]])

    def test_resume_refuses_path_traversal(self):
        self.assertEqual(fu.main(["--status", "--resume", "../../other"]), 1)


class Effects(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.old, self.new = root / "old", root / "new"
        for path in (self.old, self.new):
            (path / "hm/home-files/.config/systemd/user").mkdir(parents=True)
            (path / "bin").mkdir()
            (path / "bin/switch-to-configuration").write_text("echo stable switch tool\n")
            (path / "activate").write_text("echo stable root activation\n")
            (path / "dry-activate").write_text("echo stable dry activation\n")
            (path / "hm/activate").write_text("echo stable home activation\n")
        self.patcher = patch.object(fu, "user_generation", lambda path: path / "hm")
        self.patcher.start()
        self.addCleanup(self.patcher.stop)

    def effects(self, dry="", active=()):
        return fu.effect_reasons(self.old, self.new, dry, active)

    def test_package_store_roots_change_without_changing_activation_code(self):
        root = Path(self.temp.name) / "store"
        for path, value in [(self.old, "0"), (self.new, "1")]:
            helper = root / (value * 32 + "-helper")
            helper.parent.mkdir(exist_ok=True)
            helper.write_text("echo same inspected helper\n")
            (path / "activate").write_text(f"source {helper}\n")
        prefix = re.escape(str(root))
        with patch.object(fu, "STORE", re.compile(prefix + r"/[0-9a-z]{32}-[^/\s'\";:)]+")), \
             patch.object(fu, "STORE_FILE", re.compile(prefix + r"/[0-9a-z]{32}-[^\s'\";:)$`{}<>\\]+")):
            self.assertEqual(self.effects(), [])
            (root / ("1" * 32 + "-helper")).write_text("systemctl --user restart herdr\n")
            self.assertTrue(self.effects(), "normalized-equal callers must not hide changed helper code")

    def test_changed_activation_argument_is_unknown(self):
        (self.new / "activate").write_text("rm -rf /important\n")
        self.assertTrue(self.effects())

    def test_home_activation_code_is_checked_beyond_dry_run(self):
        (self.new / "hm/activate").write_text("systemctl --user restart herdr\n")
        self.assertTrue(self.effects())

    def test_tailscale_transport_is_deferred_while_cli_only_is_safe(self):
        self.assertEqual(self.effects("would restart the following units: home-manager-tom.service\n"), [])
        self.assertTrue(self.effects("would restart the following units: tailscaled.service\n"))
        self.assertTrue(self.effects("would stop the following units: user@1000.service\n"))
        self.assertTrue(self.effects("would restart systemd\n"))
        self.assertTrue(self.effects("would start the following units: gufo-llm.service\n"))

    def test_changed_privileged_switch_entrypoint_is_unknown(self):
        (self.new / "bin/switch-to-configuration").write_text("systemctl restart user@1000.service\n")
        self.assertTrue(self.effects())

    def test_user_service_changes_respect_native_keep_old_only(self):
        for path in (self.old, self.new):
            (path / "hm/home-files/.config/systemd/user/herdr.service").write_text("[Unit]\nX-SwitchMethod=keep-old\n")
        (self.new / "hm/home-files/.config/systemd/user/herdr.service").write_text("[Unit]\nX-SwitchMethod=keep-old\n# new package\n")
        self.assertEqual(self.effects(active=["herdr.service"]), [])
        self.assertTrue(self.effects(active=["other-active.service"]))

    def test_unchanged_global_user_units_are_not_false_changes(self):
        for system in (self.old, self.new):
            units = system / "etc/systemd/user"
            units.mkdir(parents=True)
            for name in ("dbus-broker.service", "nixos-activation.service", "herdr-web-ui.service"):
                (units / name).write_text("[Service]\nExecStart=/stable/executable\n")
        active = ["dbus-broker.service", "nixos-activation.service", "herdr-web-ui.service"]
        self.assertEqual(self.effects(active=active), [])
        (self.new / "etc/systemd/user/dbus-broker.service").write_text("[Unit]\nX-SwitchMethod=keep-old\n[Service]\nExecStart=/changed/daemon\n")
        self.assertTrue(self.effects(active=active), "global units cannot borrow HM's keep-old contract")

    def test_changed_or_missing_user_unit_origin_fails_closed(self):
        for system in (self.old, self.new):
            units = system / "etc/systemd/user"
            units.mkdir(parents=True)
            (units / "dbus-broker.service").write_text("identical unit bytes\n")
        (self.new / "hm/home-files/.config/systemd/user/dbus-broker.service").write_text("identical unit bytes\n")
        self.assertTrue(self.effects(active=["dbus-broker.service"]))
        (self.new / "hm/home-files/.config/systemd/user/dbus-broker.service").unlink()
        (self.new / "etc/systemd/user/dbus-broker.service").unlink()
        self.assertTrue(self.effects(active=["dbus-broker.service"]))

    def test_unmanaged_user_unit_requires_a_readable_actual_fragment(self):
        fragment = Path(self.temp.name) / "manual.service"
        fragment.write_text("[Service]\nExecStart=/unchanged/manually-started-tool\n")
        self.assertTrue(self.effects(active=["manual.service"]))
        self.assertEqual(fu.effect_reasons(self.old, self.new, "", ["manual.service"],
                                         {"manual.service": str(fragment)}), [])
        fragment.unlink()
        self.assertTrue(fu.effect_reasons(self.old, self.new, "", ["manual.service"],
                                       {"manual.service": str(fragment)}))

    def test_active_user_drop_ins_are_compared_across_all_managed_origins(self):
        for system in (self.old, self.new):
            (system / "hm/home-files/.config/systemd/user/herdr.service").write_text(
                "[Unit]\nX-SwitchMethod=keep-old\n[Service]\nExecStart=/stable/herdr\n")
            directory = system / "sw/lib/systemd/user/herdr.service.d"
            directory.mkdir(parents=True)
            (directory / "override.conf").write_text("[Service]\nEnvironment=MODE=stable\n")
        self.assertEqual(self.effects(active=["herdr.service"]), [])
        override = self.new / "sw/lib/systemd/user/herdr.service.d/override.conf"
        override.write_text("[Service]\nExecStart=\nExecStart=/changed/helper\n")
        self.assertTrue(self.effects(active=["herdr.service"]), "keep-old does not bypass override changes")
        override.unlink()
        self.assertTrue(self.effects(active=["herdr.service"]), "removed drop-ins remain changes")

    def test_new_type_prefix_and_template_drop_ins_fail_closed(self):
        unit = "work-agent@session.service"
        for system in (self.old, self.new):
            (system / "hm/home-files/.config/systemd/user" / unit).write_text("stable unit\n")
        for name in ("service.d", "work-.service.d", "work-agent@.service.d", unit + ".d"):
            directory = self.new / "hm/home-files/.local/share/systemd/user" / name
            directory.mkdir(parents=True)
            (directory / "new.conf").write_text("[Service]\nExecStartPost=/new/helper\n")
            self.assertTrue(self.effects(active=[unit]), name)
            (directory / "new.conf").unlink()
        self.assertEqual(self.effects(active=[unit]), [])

    def test_active_user_alias_drop_ins_are_inspected(self):
        for system in (self.old, self.new):
            directory = system / "hm/home-files/.config/systemd/user"
            (directory / "primary.service").write_text("stable unit\n")
            (directory / "alias.service").symlink_to("primary.service")
        self.assertEqual(self.effects(active=["primary.service"]), [])
        override = self.new / "etc/systemd/user/alias.service.d"
        override.mkdir(parents=True)
        (override / "new.conf").write_text("[Service]\nExecStartPost=/new/helper\n")
        self.assertTrue(self.effects(active=["primary.service"]))

    def bus_fixture(self):
        store = Path(self.temp.name) / "store"
        for system, number in ((self.old, "0"), (self.new, "1")):
            data = store / (number * 32 + "-system-path") / "share/dbus-1/services"
            data.mkdir(parents=True)
            (data / "same.service").write_text("[D-BUS Service]\nName=org.example.Stable\nExec=/stable/service\n")
            bus = system / "etc/dbus-1"
            bus.mkdir(parents=True)
            for name in ("session.conf", "system.conf"):
                (bus / name).write_text(f'<busconfig><servicedir>{data}</servicedir><policy context="default"/></busconfig>')
            trigger = store / (number * 32 + "-X-Restart-Triggers-dbus-broker")
            trigger.write_text(str(bus.resolve()))
            for scope in ("system", "user"):
                units = system / "etc/systemd" / scope
                units.mkdir(parents=True)
                (units / "dbus-broker.service").write_text(
                    "[Service]\nType=notify-reload\nExecStart=/nix/store/" + "a" * 32 +
                    "-dbus-broker-37/bin/dbus-broker-launch --scope " + scope + (" --audit" if scope == "system" else "") + "\n")
                drop = units / "dbus-broker.service.d"
                drop.mkdir()
                (drop / "overrides.conf").write_text(f"[Unit]\nX-Restart-Triggers={trigger}\n[Service]\nX-ReloadIfChanged=true\n")
        # Production accepts only immutable /nix/store refs. Fixtures use the
        # same rooted shape inside their private temporary tree.
        return patch.object(fu, "STORE_FILE", re.compile(re.escape(str(store)) + r"/[0-9a-z]{32}-[^\s'\";:)$`{}<>\\]+"))

    def test_dbus_reload_requires_identical_effective_policy_and_native_code(self):
        with self.bus_fixture():
            self.assertTrue(fu.dbus_reload_safe(self.old / "etc", self.new / "etc"))
            self.assertEqual(self.effects("would reload the following units: dbus-broker.service\n",
                                          ["dbus-broker.service"]), [])
            self.assertTrue(self.effects("would restart the following units: dbus-broker.service\n"))
            self.assertTrue(self.effects("would start the following units: dbus-broker.service\n"))
            self.assertTrue(self.effects("would restart the following user units: dbus-broker.service\n"))
            data = next((Path(self.temp.name) / "store").glob("1*-system-path"))
            (data / "share/dbus-1/services/same.service").write_text("changed service activation\n")
            self.assertFalse(fu.dbus_reload_safe(self.old / "etc", self.new / "etc"))
            self.assertTrue(self.effects("would reload the following units: dbus-broker.service\n"))

    def test_dbus_runtime_overrides_must_match_the_audited_generation(self):
        with self.bus_fixture():
            def run(argv, **kwargs):
                scope = "user" if "--user" in argv else "system"
                field = next(arg.partition("=")[2] for arg in argv if arg.startswith("--property="))
                value = {"Type": "notify-reload", "ExecReload": "", "ReloadSignal": "1",
                         "FragmentPath": str(self.old / "etc/systemd" / scope / "dbus-broker.service"),
                         "DropInPaths": str(self.old / "etc/systemd" / scope / "dbus-broker.service.d/overrides.conf")}[field]
                return subprocess.CompletedProcess(argv, 0, value, "")
            with patch.object(fu, "run", run):
                self.assertEqual(fu.dbus_runtime_reload_reasons(self.old), [])
            def unexpected(argv, **kwargs):
                result = run(argv, **kwargs)
                if "--property=DropInPaths" in argv:
                    result.stdout += " /run/user/1000/systemd/user/dbus.service.d/custom.conf"
                return result
            with patch.object(fu, "run", unexpected):
                self.assertTrue(fu.dbus_runtime_reload_reasons(self.old))

    def test_dbus_reload_rejects_unchanged_non_native_type_and_alias_overrides(self):
        with self.bus_fixture():
            for name in ("service.d", "dbus-.service.d", "dbus.service.d"):
                for system in (self.old, self.new):
                    path = system / "etc/systemd/system" / name
                    path.mkdir()
                    (path / "custom.conf").write_text("[Service]\nExecReload=/unknown/helper\n")
                self.assertFalse(fu.dbus_reload_safe(self.old / "etc", self.new / "etc"), name)
                for system in (self.old, self.new):
                    (system / "etc/systemd/system" / name / "custom.conf").unlink()
            for system in (self.old, self.new):
                path = system / "hm/home-files/.config/systemd/user/service.d"
                path.mkdir()
                (path / "custom.conf").write_text("[Service]\nReloadSignal=SIGKILL\n")
            self.assertTrue(self.effects("would reload the following units: dbus-broker.service\n"))

    def test_etc_profile_pointer_changes_are_bounded_to_the_managed_profile(self):
        for root, name in ((self.old, "old-tool"), (self.new, "new-tool")):
            profile = root / "etc/profiles/per-user/tom"
            profile.mkdir(parents=True)
            (profile / name).write_text("packaged CLI\n")
            (root / "etc/sudoers").write_text("unchanged policy\n")
        self.assertEqual(fu.etc_tree_reasons(self.old / "etc", self.new / "etc"), [])
        (self.new / "etc/sudoers").write_text("changed privilege policy\n")
        self.assertTrue(fu.etc_tree_reasons(self.old / "etc", self.new / "etc"))

    def test_real_etc_directory_reference_is_inspected_instead_of_ignored(self):
        store = Path(self.temp.name) / "store"
        for system, number in ((self.old, "0"), (self.new, "1")):
            etc = store / (number * 32 + "-etc") / "etc"
            profile = etc / "profiles/per-user/tom"
            profile.mkdir(parents=True)
            (profile / ("tool-" + number)).write_text("CLI\n")
            (etc / "sudoers").write_text("stable policy\n")
            (system / "activate").write_text(f"new_etc={etc}\n")
        prefix = re.escape(str(store))
        with patch.object(fu, "STORE", re.compile(prefix + r"/[0-9a-z]{32}-[^/\s'\";:)]+")), \
             patch.object(fu, "STORE_FILE", re.compile(prefix + r"/[0-9a-z]{32}-[^\s'\";:)$`{}<>\\]+")):
            self.assertEqual(self.effects(), [])
            (store / ("1" * 32 + "-etc") / "etc/sudoers").write_text("unknown new policy\n")
            self.assertTrue(self.effects())


class DurableTransaction(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.patcher = patch.multiple(fu, STATE=Path(self.temp.name), LOG=None)
        self.patcher.start()
        self.addCleanup(self.patcher.stop)
        self.state = {"schema": 1, "night": "2026-10-28", "stages": {}}
        self.tx = fu.Transaction(self.state, args())

    def test_pending_nas_does_not_prevent_coordinator_and_resume_does_not_rebuild(self):
        events, busy = [], {"nas": True}
        def stage(name):
            def work():
                events.append(name)
                return {"candidate": REV}
            return work
        def install(host):
            events.append("install:" + host)
            if busy.get(host):
                raise fu.Pending("busy host")
            return {"status": "installed"}
        for name in ("prepare", "seed", "build", "adopt"):
            setattr(self.tx, name, stage(name))
        self.tx.install = install
        with self.assertRaises(fu.Pending):
            self.tx.execute()
        self.assertEqual(self.state["stages"]["install:strix-coordinator"]["status"], "complete")
        self.assertEqual(self.state["stages"]["install:nas"]["status"], "pending")
        busy["nas"] = False
        self.tx.execute()
        self.assertEqual(events, ["prepare", "seed", "build", "adopt", "install:nas", "install:strix-coordinator", "install:nas"])

    def test_failure_and_interruption_are_not_an_automatic_expensive_retry(self):
        for status in ("running", "failed"):
            self.state["stages"]["build"] = {"status": status}
            with self.assertRaises(fu.Failure):
                self.tx.stage("build", lambda: self.fail("unexpected repeated build"))

    def test_stage_ownership_persisted_before_side_effect(self):
        def effect():
            stored = fu.read_json(self.tx.path)["stages"]["copy"]
            self.assertEqual(stored["status"], "running")
            self.assertTrue(fu.owner_alive(stored["owner"]))
            return "exact-path"
        self.assertEqual(self.tx.stage("copy", effect), "exact-path")
        self.assertEqual(fu.read_json(self.tx.path)["stages"]["copy"]["status"], "complete")

    def test_worker_resumes_without_another_model_turn_or_timer(self):
        events = []
        def execute():
            events.append("execute")
            if len(events) == 1:
                raise fu.Pending("busy")
        self.tx.execute = execute
        with patch.object(fu.time, "sleep", lambda seconds: self.assertEqual(seconds, 60)):
            self.assertEqual(fu.execute_transaction(self.tx, worker=True), 0)
        self.assertEqual(events, ["execute", "execute"])
        self.assertTrue((fu.STATE / "completions/2026-10-28.json").exists())

    def test_worker_stops_after_failed_build(self):
        def execute():
            raise fu.Failure("bad derivation")
        self.tx.execute = execute
        with patch.object(fu.time, "sleep", side_effect=AssertionError("must not retry failure")):
            self.assertEqual(fu.execute_transaction(self.tx, worker=True), 1)

    def test_programs_phase_precedes_full_base_using_same_pipeline(self):
        self.state["programs_first"] = True
        calls = []
        def pipeline(tx):
            calls.append(tx.state.get("lane", "full"))
        with patch.object(fu.Transaction, "execute_pipeline", pipeline):
            self.tx.execute()
            self.tx.execute()
        self.assertEqual(calls, ["programs", "full", "full"])
        self.assertEqual(self.state["programs_job"]["status"], "complete")

    def test_lock_only_fast_forward_preserves_untracked_work_but_defers_tracked_edits(self):
        source, origin = fu.STATE / "checkout", fu.STATE / "origin.git"
        def git(*argv, **kwargs):
            return subprocess.run(["git", *argv], check=True, text=True, capture_output=True, **kwargs)
        git("init", "--bare", str(origin))
        git("init", "--initial-branch=main", str(source))
        git("-C", str(source), "config", "user.name", "Fixture")
        git("-C", str(source), "config", "user.email", "fixture@localhost")
        lock = source / "flake.lock"
        lock.write_text("old pin\n")
        git("-C", str(source), "add", "flake.lock")
        git("-C", str(source), "commit", "-m", "baseline")
        base = git("-C", str(source), "rev-parse", "HEAD").stdout.strip()
        lock.write_text("new pin\n")
        git("-C", str(source), "commit", "-am", "lock-only candidate")
        candidate = git("-C", str(source), "rev-parse", "HEAD").stdout.strip()
        git("-C", str(source), "remote", "add", "origin", str(origin))
        git("-C", str(source), "push", "origin", "main")
        git("-C", str(source), "reset", "--hard", base)
        private = source / "notify-send"
        private.write_text("private user-owned helper\n")
        self.state.update(candidate=candidate, paths={"nas": "/candidate"})
        self.tx.assess = lambda host: {"generation": "/old"}
        def ssh(host, argv, **kw):
            if argv[:2] == ["git", "-C"]:
                return subprocess.run(["git", "-C", str(source), *argv[3:]], text=True,
                                      capture_output=True, check=kw.get("check", True))
            return subprocess.CompletedProcess(argv, 0, '{"status":"installed"}', "")
        with patch.object(fu, "ssh", ssh):
            self.assertEqual(self.tx.install("nas")["status"], "installed")
            self.assertEqual(private.read_text(), "private user-owned helper\n")
            self.assertEqual(git("-C", str(source), "rev-parse", "HEAD").stdout.strip(), candidate)
            lock.write_text("uncommitted tracked change\n")
            with self.assertRaises(fu.Pending):
                self.tx.install("nas")
            git("-C", str(source), "add", "flake.lock")
            with self.assertRaises(fu.Pending):
                self.tx.install("nas")

    def test_new_cf_request_coalesces_unadopted_pending_base(self):
        self.state["status"] = "pending"
        fu.atomic_json(fu.STATE / "requested.json", {"night": "2026-10-29"})
        with patch.object(fu.Transaction, "execute", lambda tx: None):
            self.assertEqual(fu.execute_transaction(self.tx, worker=True), 0)
        old = fu.read_json(fu.STATE / "jobs/2026-10-28.json")
        self.assertEqual(old["status"], "superseded")
        self.assertEqual(old["superseded_by"], "2026-10-29")
        self.assertEqual(fu.read_json(fu.STATE / "completions/2026-10-29.json")["status"], "complete")

    def test_new_cf_request_does_not_starve_online_hosts_when_an_adopted_host_is_offline(self):
        self.state.update(status="pending", stages={"adopt": {"status": "complete"},
                                                    "install:nas": {"status": "pending", "reason": "offline"}})
        fu.atomic_json(fu.STATE / "requested.json", {"night": "2026-10-29"})
        with patch.object(fu.Transaction, "execute", lambda tx: None):
            self.assertEqual(fu.execute_transaction(self.tx, worker=True), 0)
        self.assertEqual(fu.read_json(fu.STATE / "jobs/2026-10-28.json")["superseded_by"], "2026-10-29")

    def test_full_base_is_assessed_before_adoption(self):
        self.state.update(programs_first=True, programs_job={"status": "complete"})
        for name in ("prepare", "seed", "build"):
            setattr(self.tx, name, lambda: {})
        calls = []
        self.tx.assess = lambda host: (_ for _ in ()).throw(fu.Pending("tailscaled restart"))
        self.tx.adopt = lambda: calls.append("adopt")
        with self.assertRaises(fu.Pending):
            self.tx.execute()
        self.assertEqual(calls, [], "unsafe full pins must not enter tomorrow's program baseline")

    def test_detached_worker_retains_lock_after_launcher_exits(self):
        import fcntl
        worker = fu.STATE / "worker.py"
        worker.write_text('import os,time\nfd=int(os.environ["FLEET_UPDATE_LOCK_FD"])\ntime.sleep(0.4)\nos.close(fd)\n')
        processes = []
        real_popen = subprocess.Popen
        def popen(*a, **kw):
            process = real_popen(*a, **kw)
            processes.append(process)
            return process
        with (fu.STATE / "lock").open("w") as held:
            fcntl.flock(held, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with patch.object(fu, "__file__", str(worker)), patch.object(fu.subprocess, "Popen", popen):
                receipt = fu.background(self.tx.args, self.state, held)
        self.assertEqual(receipt["status"], "launched")
        self.assertFalse(receipt["ok"])
        with (fu.STATE / "lock").open("w") as other:
            with self.assertRaises(BlockingIOError):
                fcntl.flock(other, fcntl.LOCK_EX | fcntl.LOCK_NB)
        processes[0].wait(timeout=5)
        with (fu.STATE / "lock").open("w") as other:
            fcntl.flock(other, fcntl.LOCK_EX | fcntl.LOCK_NB)

    def test_compute_busy_maps_exit_75_to_pending(self):
        self.state["remote"] = "/remote/checkout"
        with patch.object(fu, "run", return_value=subprocess.CompletedProcess([], 75, "", "compute busy")):
            with self.assertRaises(fu.Pending):
                self.tx.compute(["build-preflight"])

    def test_two_host_build_results_do_not_depend_on_nix_output_order(self):
        self.state.update(remote="/remote", candidate=REV, config={"checks": [".#check"]})
        nas = "/nix/store/" + "a" * 32 + "-nixos-system-nas-26.05"
        coord = "/nix/store/" + "b" * 32 + "-nixos-system-strix-coordinator-26.05"
        output = json.dumps([{"outputs": {"out": coord}}, {"outputs": {"out": "/nix/store/check"}}, {"outputs": {"out": nas}}])
        calls = []
        def compute(argv, **kw):
            calls.append(argv)
            return subprocess.CompletedProcess([], 0, output if argv[:2] == ["nix", "build"] else "", "")
        self.tx.compute = compute
        self.tx.build()
        self.assertEqual(self.state["paths"], {"nas": nas, "strix-coordinator": coord})
        build = next(argv for argv in calls if argv[:2] == ["nix", "build"])
        self.assertNotIn("--max-jobs", build)
        self.assertNotIn("strix-worker", " ".join(build))
        build_index = calls.index(build)
        self.assertIn("--disk-preflight", calls[build_index - 1])


class TargetSwitch(unittest.TestCase):
    def test_safe_switch_retains_session_pid_and_old_generation_with_final_busy_recheck(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            old, candidate, current = root / "old", root / "candidate", root / "current"
            old.mkdir()
            candidate.mkdir()
            current.symlink_to(old)
            session = subprocess.Popen(["sleep", "60"])
            self.addCleanup(session.wait)
            self.addCleanup(session.terminate)
            calls = []
            def run(argv, **kwargs):
                calls.append(argv)
                if "rev-parse" in argv:
                    stdout = REV
                elif "status" in argv:
                    stdout = ""
                elif "fleet-update-probe" in str(argv[-1]):
                    stdout = json.dumps({"reasons": []})
                else:
                    stdout = ""
                if argv[-1] == "switch":
                    current.unlink()
                    current.symlink_to(candidate)
                return subprocess.CompletedProcess(argv, 0, stdout, "")
            with patch.multiple(fu, CURRENT=current, TARGET_LOCK=root / "lock", ROOTS=root / "roots"), \
                 patch.object(fu.os, "geteuid", return_value=0), patch.object(fu, "validate_candidate"), \
                 patch.object(fu, "run", run), patch.object(fu, "effect_reasons", return_value=[]), \
                 patch.object(fu, "protected_pids", return_value={"herdr.service": str(session.pid)}):
                result = fu.target_activate(candidate, REV, str(old))
            self.assertEqual(result["status"], "installed")
            self.assertIsNone(session.poll())
            self.assertEqual((root / "roots/previous").resolve(), old)
            self.assertEqual(sum("fleet-update-probe" in str(call[-1]) for call in calls), 2)
            self.assertEqual(calls[-1][-1], "switch")

    def test_forged_generation_or_cross_host_path_is_rejected(self):
        for path, revision in [(Path("/tmp/system"), REV),
                               (Path("/nix/store/" + "a" * 32 + "-nixos-system-strix-worker-26.05"), REV),
                               (Path("/nix/store/" + "a" * 32 + "-nixos-system-nas-26.05"), "main")]:
            with self.assertRaises(fu.Failure):
                fu.validate_candidate(path, revision, host="nas")


class VerifyVersions(unittest.TestCase):
    def test_candidate_uses_its_managed_profile_and_exact_version_tokens(self):
        with tempfile.TemporaryDirectory() as directory:
            candidate = Path(directory)
            executable = candidate / "etc/profiles/per-user/tom/bin/codex"
            executable.parent.mkdir(parents=True)
            import sys
            executable.write_text(f"#!{sys.executable}\nprint('codex-cli 0.165.0')\n")
            executable.chmod(0o755)
            metadata = candidate / "fleet-update-versions.json"
            metadata.write_text(json.dumps({"codex": "0.165.0"}))
            with patch.object(fu, "validate_candidate"), patch.object(fu, "LOG", None):
                self.assertEqual(fu.verify(candidate, REV, candidate_only=True)["versions"]["codex"]["reported"],
                                 "codex-cli 0.165.0")
                metadata.write_text(json.dumps({"codex": "0.16"}))
                with self.assertRaises(fu.Failure):
                    fu.verify(candidate, REV, candidate_only=True)
                metadata.write_text(json.dumps({"missing-keeper": "1.0"}))
                with self.assertRaises(fu.Failure):
                    fu.verify(candidate, REV, candidate_only=True)


if __name__ == "__main__":
    unittest.main()
