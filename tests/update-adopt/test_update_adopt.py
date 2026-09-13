"""Hermetic tests for modules/update-adopt.py and modules/update-adopt-gates.sh.

Every external command is a fake on PATH except ssh-keygen, which is real so
the signature path is the one production runs. Fake systems are directories
under a temp STORE_DIR carrying fleet-revision.json, kernel/initrd files and a
bin/switch-to-configuration that records its call and re-points
$UPDATE_ADOPT_ROOT/run/current-system the way activation does.
"""

import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
SCRIPT = os.path.join(REPO, "modules", "update-adopt.py")
GATES = os.path.join(REPO, "modules", "update-adopt-gates.sh")

FAKES = {
    "curl": r"""#!/bin/sh
dest=""; url=""
while [ $# -gt 0 ]; do
  case "$1" in -o) dest="$2"; shift 2 ;; -m) shift 2 ;; -*) shift ;; *) url="$1"; shift ;; esac
done
src="$FIXTURE/www/${url#http://nas.test/}"
[ -f "$src" ] || exit 22
if [ -n "$dest" ]; then cp "$src" "$dest"; else cat "$src"; fi
""",
    "nix-store": r"""#!/bin/sh
echo "nix-store $*" >> "$FIXTURE/calls.log"
case "$1" in
  --realise)
    [ -e "$2" ] || exit 1
    mkdir -p "$(dirname "$4")"; ln -sfn "$2" "$4"; echo "$4" ;;
  --check-validity) [ -e "$2" ] ;;
esac
""",
    "nix": r"""#!/bin/sh
echo "nix $*" >> "$FIXTURE/calls.log"
""",
    "nix-env": r"""#!/bin/sh
echo "nix-env $*" >> "$FIXTURE/calls.log"
# nix-env -p PROFILE --set PATH
ln -sfn "$4" "$2"
""",
    "systemd-run": r"""#!/bin/sh
while [ $# -gt 0 ]; do case "$1" in --*) shift ;; *) break ;; esac; done
exec "$@"
""",
    "systemctl": r"""#!/bin/sh
echo "systemctl $*" >> "$FIXTURE/calls.log"
user=""
if [ "$1" = --user ]; then user="${3%@}"; shift 3; fi
case "$1" in
  is-system-running) cat "$FIXTURE/sys/running" 2>/dev/null || echo running ;;
  list-units)
    [ -n "$user" ] && [ -e "$FIXTURE/sys/down-$user" ] && exit 1
    if printf '%s ' "$@" | grep -q -- '--failed'; then
      cat "$FIXTURE/sys/failed-${user:-system}" 2>/dev/null || true
    else
      for last; do :; done
      for f in "$FIXTURE"/sys/active-system/$last; do [ -e "$f" ] && echo "$(basename "$f") loaded active running"; done
      true
    fi ;;
  is-active)
    unit="$3"; [ "$2" = --quiet ] || unit="$2"
    [ -e "$FIXTURE/sys/active-${user:-system}/$unit" ] ;;
  show) echo "/system.slice/tally-kernel.service" ;;
  start) : ;;
esac
""",
    "pgrep": "#!/bin/sh\n[ -e \"$FIXTURE/pgrep-hit\" ] && echo 4242 && exit 0\nexit 1\n",
    "logger": "#!/bin/sh\ncat >/dev/null\n",
    "runuser": "#!/bin/sh\nshift 2; [ \"$1\" = -- ] && shift\nexec \"$@\"\n",
    "herdr": "#!/bin/sh\ncat \"$FIXTURE/herdr.json\"\n",
    "tally": "#!/bin/sh\ncat \"$FIXTURE/pools.json\"\n",
    "tally-kernel": "#!/bin/sh\n[ -e \"$FIXTURE/kernel-silent\" ] && exit 1\ncat \"$FIXTURE/rows.json\"\n",
    "ss": "#!/bin/sh\ncat \"$FIXTURE/ss.txt\" 2>/dev/null || true\n",
}

SWITCH = r"""#!/bin/sh
dir="$(cd "$(dirname "$0")/.." && pwd)"
echo "switch $(basename "$dir") $1" >> "$FIXTURE/calls.log"
if [ "$1" = switch ]; then
  ln -sfn "$dir" "$UPDATE_ADOPT_ROOT/run/current-system"
  if [ -e "$dir/fail-units" ]; then cp "$dir/fail-units" "$FIXTURE/sys/failed-system"; else : > "$FIXTURE/sys/failed-system"; fi
fi
exit "$(cat "$dir/switch-rc" 2>/dev/null || echo 0)"
"""


def write_exec(path, text):
    with open(path, "w") as stream:
        stream.write(text)
    os.chmod(path, os.stat(path).st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)


class Fixture:
    def __init__(self, policy="rolling"):
        self.tmp = tempfile.mkdtemp(prefix="update-adopt-test-")
        self.root = os.path.join(self.tmp, "root")
        self.store = os.path.join(self.tmp, "store")
        self.state_dir = os.path.join(self.tmp, "state")
        self.bin = os.path.join(self.tmp, "bin")
        for d in (self.root + "/run", self.root + "/nix/var/nix/profiles", self.store,
                  self.bin, self.tmp + "/sys/active-system", self.tmp + "/sys/active-tom",
                  self.tmp + "/www/candidates/worker", self.tmp + "/markers"):
            os.makedirs(d, exist_ok=True)
        for name, text in FAKES.items():
            write_exec(os.path.join(self.bin, name), text)
        write_exec(os.path.join(self.tmp, "gate.sh"),
                   '#!/bin/sh\nrc=$(cat "$FIXTURE/gate-rc" 2>/dev/null || echo 0)\n'
                   '[ "$rc" = 0 ] || echo "test gate says busy"\nexit "$rc"\n')
        key = os.path.join(self.tmp, "nas_key")
        subprocess.run(["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", key], check=True)
        self.key = key
        with open(key + ".pub") as stream:
            pub = stream.read().strip()
        self.signers = os.path.join(self.tmp, "allowed_signers")
        with open(self.signers, "w") as stream:
            stream.write(f'nas namespaces="fleet-update" {pub}\n')
        self.config_path = os.path.join(self.tmp, "config.json")
        self.config = {
            "host": "worker",
            "policy": policy,
            "candidate_url": "http://nas.test/candidates",
            "allowed_signers": self.signers,
            "signer_identity": "nas",
            "min_free_gib": 0,
            "psi_avg60_max": 20,
            "settle_sec": 0,
            "probe_window_sec": 0,
            "probe_interval_sec": 0,
            "gates": [{"name": "test-gate", "argv": [os.path.join(self.tmp, "gate.sh")]}],
            "probes": [],
            "critical_units": [{"unit": "sshd.service", "user": None}],
            "user_managers": ["tom"],
            "marker_dir": os.path.join(self.tmp, "markers"),
            "reboot_pending_alert_hours": 72,
        }
        self.save_config()
        self.systems = {}
        self.a = self.system("a", last_modified=1000)
        self.point(self.a)
        open(os.path.join(self.tmp, "sys/active-system/sshd.service"), "w").close()

    def save_config(self):
        with open(self.config_path, "w") as stream:
            json.dump(self.config, stream)

    def system(self, tag, last_modified, dirty=False, kernel="k1", rev=None):
        name = (tag * 32)[:32].replace("e", "f").replace("o", "p").replace("u", "v")
        path = os.path.join(self.store, f"{name}-nixos-system-worker-26.11")
        os.makedirs(path + "/bin", exist_ok=True)
        with open(path + "/fleet-revision.json", "w") as stream:
            json.dump({"rev": rev or f"rev-{tag}", "dirty": dirty, "lastModified": last_modified}, stream)
        for f in ("kernel", "initrd"):
            with open(os.path.join(path, f), "w") as stream:
                stream.write(f"{f}-{kernel}")
        with open(path + "/kernel-params", "w") as stream:
            stream.write("quiet")
        write_exec(path + "/bin/switch-to-configuration", SWITCH)
        return path

    def point(self, path, booted=True):
        for link in ("run/current-system", "nix/var/nix/profiles/system") + (("run/booted-system",) if booted else ()):
            full = os.path.join(self.root, link)
            if os.path.lexists(full):
                os.unlink(full)
            os.symlink(path, full)

    def publish(self, path, host="worker", last_modified=None, tamper=False):
        rev = json.load(open(path + "/fleet-revision.json"))
        manifest = {
            "schema": 1,
            "host": host,
            "rev": "github:mecattaf/dotfiles/" + rev["rev"],
            "last_modified": rev["lastModified"] if last_modified is None else last_modified,
            "store_path": path,
            "built_at": "2026-09-13T01:30:00Z",
            "channel": "rolling",
        }
        target = os.path.join(self.tmp, "www/candidates/worker/manifest.json")
        with open(target, "w") as stream:
            json.dump(manifest, stream)
        if os.path.exists(target + ".sig"):
            os.unlink(target + ".sig")
        subprocess.run(["ssh-keygen", "-q", "-Y", "sign", "-f", self.key, "-n", "fleet-update", target],
                       check=True, capture_output=True)
        if tamper:
            manifest["store_path"] = self.a
            with open(target, "w") as stream:
                json.dump(manifest, stream)

    def env(self):
        env = dict(os.environ)
        env.update({
            "FIXTURE": self.tmp,
            "PATH": self.bin + ":" + os.environ["PATH"],
            "UPDATE_ADOPT_CONFIG": self.config_path,
            "UPDATE_ADOPT_ROOT": self.root,
            "UPDATE_ADOPT_STORE_DIR": self.store,
            "UPDATE_ADOPT_STATE_DIR": self.state_dir,
            "UPDATE_ADOPT_LOCK": os.path.join(self.tmp, "adopt.lock"),
        })
        return env

    def run(self, *args):
        return subprocess.run([sys.executable, SCRIPT, *args], env=self.env(), capture_output=True, text=True)

    def state(self):
        with open(os.path.join(self.state_dir, "state.json")) as stream:
            return json.load(stream)

    def calls(self):
        try:
            with open(os.path.join(self.tmp, "calls.log")) as stream:
                return stream.read()
        except OSError:
            return ""

    def current(self):
        return os.path.realpath(os.path.join(self.root, "run/current-system"))

    def profile(self):
        return os.path.realpath(os.path.join(self.root, "nix/var/nix/profiles/system"))

    def receipts(self):
        d = os.path.join(self.state_dir, "receipts")
        return [json.load(open(os.path.join(d, n))) for n in sorted(os.listdir(d))] if os.path.isdir(d) else []

    def cleanup(self):
        shutil.rmtree(self.tmp, ignore_errors=True)


class AdoptTests(unittest.TestCase):
    def setUp(self):
        self.fx = Fixture()

    def tearDown(self):
        self.fx.cleanup()

    def assertOk(self, result, rc=0):
        self.assertEqual(result.returncode, rc, result.stdout + result.stderr)

    # (0) a candidate identical to the running system is a no-op
    def test_identical_candidate_is_noop(self):
        self.fx.publish(self.fx.a)
        self.assertOk(self.fx.run("stage"))
        self.assertOk(self.fx.run("activate"))
        self.assertEqual(self.fx.state()["state"], "known-good")
        self.assertNotIn("--realise", self.fx.calls())
        self.assertNotIn("switch ", self.fx.calls())
        self.assertNotIn("nix-env", self.fx.calls())
        self.assertEqual(self.fx.current(), self.fx.a)

    # (1) good candidate → staged, switched, probed, known-good
    def test_good_candidate_adopts(self):
        b = self.fx.system("b", last_modified=2000)
        self.fx.publish(b)
        self.assertOk(self.fx.run("stage"))
        self.assertEqual(self.fx.state()["state"], "closure-ready")
        self.assertIn("systemctl start --no-block update-adopt-activate.service", self.fx.calls())
        self.assertOk(self.fx.run("activate"))
        st = self.fx.state()
        self.assertEqual(st["state"], "known-good")
        self.assertEqual(st["last_known_good"], b)
        self.assertEqual(self.fx.current(), b)
        self.assertEqual(self.fx.profile(), b)
        self.assertEqual(os.path.realpath(os.path.join(self.fx.root, "nix/var/nix/gcroots/update-adopt/last-known-good")), b)
        self.assertFalse(os.path.lexists(os.path.join(self.fx.root, "nix/var/nix/gcroots/update-adopt/candidate")))
        self.assertIn(f"switch {os.path.basename(b)} switch", self.fx.calls())
        # Re-running on the adopted candidate changes nothing.
        before = self.fx.calls()
        self.assertOk(self.fx.run("stage"))
        self.assertOk(self.fx.run("activate"))
        self.assertEqual(self.fx.calls().count("switch "), before.count("switch "))

    # (2) busy gate → a receipt, rc 0, switch never called
    def test_busy_gate_defers(self):
        b = self.fx.system("b", last_modified=2000)
        self.fx.publish(b)
        with open(os.path.join(self.fx.tmp, "gate-rc"), "w") as stream:
            stream.write("1")
        self.assertOk(self.fx.run("stage"))
        result = self.fx.run("activate")
        self.assertOk(result)
        st = self.fx.state()
        self.assertEqual(st["state"], "waiting-for-safe-window")
        self.assertIn("test gate says busy", st["last_deferral"]["reason"])
        self.assertNotIn("switch ", self.fx.calls())
        self.assertEqual(self.fx.profile(), self.fx.a)
        self.assertEqual(self.fx.receipts()[-1]["kind"], "deferred")
        # An unknown gate answer also defers.
        with open(os.path.join(self.fx.tmp, "gate-rc"), "w") as stream:
            stream.write("2")
        self.assertOk(self.fx.run("activate"))
        self.assertIn("unknown", self.fx.state()["last_deferral"]["reason"])
        # Clearing the gate lets the retry adopt.
        os.unlink(os.path.join(self.fx.tmp, "gate-rc"))
        self.assertOk(self.fx.run("activate"))
        self.assertEqual(self.fx.current(), b)

    def test_rebuild_running_defers(self):
        b = self.fx.system("b", last_modified=2000)
        self.fx.publish(b)
        self.assertOk(self.fx.run("stage"))
        open(os.path.join(self.fx.tmp, "pgrep-hit"), "w").close()
        self.assertOk(self.fx.run("activate"))
        self.assertIn("rebuild-running", self.fx.state()["last_deferral"]["reason"])
        self.assertNotIn("switch ", self.fx.calls())

    # (3) probe failure → local rollback to the previous generation, rc 1
    def test_probe_failure_rolls_back(self):
        b = self.fx.system("b", last_modified=2000)
        with open(b + "/fail-units", "w") as stream:
            stream.write("broken.service loaded failed failed\n")
        self.fx.publish(b)
        self.assertOk(self.fx.run("stage"))
        self.assertOk(self.fx.run("activate"), rc=1)
        st = self.fx.state()
        self.assertEqual(st["state"], "rolled-back")
        self.assertIn(b, st["rejected"])
        calls = self.fx.calls()
        self.assertLess(calls.index(f"switch {os.path.basename(b)} switch"),
                        calls.index(f"switch {os.path.basename(self.fx.a)} switch"))
        self.assertEqual(self.fx.current(), self.fx.a)
        self.assertEqual(self.fx.profile(), self.fx.a)
        last = self.fx.receipts()[-1]
        self.assertEqual(last["kind"], "rolled-back")
        self.assertIn("broken.service", " ".join(last["failures"]))
        self.assertEqual(last["rollback"]["result"], "rolled-back")
        # The rejected candidate is never realised again.
        realises = calls.count("--realise")
        self.assertOk(self.fx.run("stage"))
        self.assertEqual(self.fx.state()["state"], "rejected")
        self.assertEqual(self.fx.calls().count("--realise"), realises)

    def test_pre_existing_failed_unit_is_not_a_probe_failure(self):
        with open(os.path.join(self.fx.tmp, "sys/failed-tom"), "w") as stream:
            stream.write("old-thing.service loaded failed failed\n")
        b = self.fx.system("b", last_modified=2000)
        self.fx.publish(b)
        self.assertOk(self.fx.run("adopt"))
        self.assertEqual(self.fx.state()["state"], "known-good")

    def test_critical_unit_down_after_switch_rolls_back(self):
        b = self.fx.system("b", last_modified=2000)
        # b's activation stops sshd: emulate by removing the active marker in its switch.
        with open(b + "/bin/switch-to-configuration", "a") as stream:
            pass
        write_exec(b + "/bin/switch-to-configuration",
                   SWITCH.replace('exit "$(cat', 'rm -f "$FIXTURE/sys/active-system/sshd.service"\nexit "$(cat'))
        write_exec(self.fx.a + "/bin/switch-to-configuration",
                   SWITCH.replace('exit "$(cat', 'touch "$FIXTURE/sys/active-system/sshd.service"\nexit "$(cat'))
        self.fx.publish(b)
        self.assertOk(self.fx.run("adopt"), rc=1)
        self.assertEqual(self.fx.state()["state"], "rolled-back")
        self.assertIn("sshd.service", " ".join(self.fx.receipts()[-1]["failures"]))

    def test_switch_nonzero_rolls_back(self):
        b = self.fx.system("b", last_modified=2000)
        with open(b + "/switch-rc", "w") as stream:
            stream.write("4")
        self.fx.publish(b)
        self.assertOk(self.fx.run("adopt"), rc=1)
        self.assertEqual(self.fx.current(), self.fx.a)
        self.assertEqual(self.fx.state()["state"], "rolled-back")

    # Someone else's `nixos-rebuild switch` lands while the probe window is
    # open: never roll THEIR generation back.
    def test_switch_by_someone_else_during_probe_is_not_rolled_back(self):
        b = self.fx.system("b", last_modified=2000)
        theirs = self.fx.system("t", last_modified=3000)
        with open(b + "/fail-units", "w") as stream:
            stream.write("broken.service loaded failed failed\n")
        profile = os.path.join(self.fx.root, "nix/var/nix/profiles/system")
        write_exec(b + "/bin/switch-to-configuration",
                   SWITCH.replace('exit "$(cat', f'ln -sfn {theirs} {profile}\nexit "$(cat'))
        self.fx.publish(b)
        self.assertOk(self.fx.run("adopt"))
        st = self.fx.state()
        self.assertEqual(st["state"], "superseded")
        self.assertEqual(self.fx.profile(), theirs)
        self.assertNotIn(f"switch {os.path.basename(self.fx.a)} switch", self.fx.calls())
        self.assertNotIn(b, st["rejected"])
        self.assertEqual(self.fx.receipts()[-1]["kind"], "superseded")

    # A user manager silent BEFORE the switch is not the candidate's fault.
    def test_user_manager_silent_before_switch_is_not_probed(self):
        open(os.path.join(self.fx.tmp, "sys/down-tom"), "w").close()
        b = self.fx.system("b", last_modified=2000)
        self.fx.publish(b)
        self.assertOk(self.fx.run("adopt"))
        self.assertEqual(self.fx.state()["state"], "known-good")

    # A switch that outlives its wait is never raced by a rollback.
    def test_hung_switch_is_not_rolled_back(self):
        b = self.fx.system("b", last_modified=2000)
        with open(b + "/switch-rc", "w") as stream:
            stream.write("124")
        self.fx.publish(b)
        self.assertOk(self.fx.run("adopt"), rc=1)
        st = self.fx.state()
        self.assertEqual(st["state"], "switch-hung")
        self.assertIn(b, st["rejected"])
        self.assertNotIn(f"switch {os.path.basename(self.fx.a)} switch", self.fx.calls())

    # Stage kicks activation only after it has released the shared lock.
    def test_stage_kicks_activation_after_releasing_lock(self):
        b = self.fx.system("b", last_modified=2000)
        self.fx.publish(b)
        systemctl = os.path.join(self.fx.bin, "systemctl")
        with open(systemctl) as stream:
            text = stream.read()
        lock = os.path.join(self.fx.tmp, "adopt.lock")
        probe = (f'  start) python3 -c "import fcntl,sys; h=open(\'{lock}\',\'a\'); '
                 f'fcntl.flock(h, fcntl.LOCK_EX|fcntl.LOCK_NB)" && echo lock-free >> "$FIXTURE/calls.log" ;;')
        write_exec(systemctl, text.replace("  start) : ;;", probe))
        self.assertOk(self.fx.run("stage"))
        self.assertIn("lock-free", self.fx.calls())

    # (4) kernel differs → boot, pending-reboot, nothing activated now
    def test_kernel_change_installs_for_boot(self):
        b = self.fx.system("b", last_modified=2000, kernel="k2")
        self.fx.publish(b)
        self.assertOk(self.fx.run("stage"))
        self.assertTrue(self.fx.state()["candidate"]["reboot_required"])
        self.assertOk(self.fx.run("activate"))
        st = self.fx.state()
        self.assertEqual(st["state"], "pending-reboot")
        self.assertEqual(st["pending_reboot"]["store_path"], b)
        self.assertIn(f"switch {os.path.basename(b)} boot", self.fx.calls())
        self.assertEqual(self.fx.current(), self.fx.a)
        self.assertEqual(self.fx.profile(), b)
        # A later stage leaves it alone.
        self.assertOk(self.fx.run("stage"))
        self.assertEqual(self.fx.state()["state"], "pending-reboot")
        self.assertEqual(self.fx.calls().count(" boot"), 1)
        marker = os.path.join(self.fx.tmp, "markers/update-adopt-reboot-pending")
        self.assertFalse(os.path.exists(marker))
        # Past the alert threshold a marker appears …
        self.fx.config["reboot_pending_alert_hours"] = 0
        self.fx.save_config()
        self.assertOk(self.fx.run("stage"))
        self.assertTrue(os.path.exists(marker))
        with open(marker) as stream:
            self.assertNotEqual(stream.readline().split()[1], "failed")
        # … and the reboot clears it.
        self.fx.point(b)
        self.assertOk(self.fx.run("stage"))
        self.assertEqual(self.fx.state()["state"], "known-good")
        self.assertFalse(os.path.exists(marker))
        self.assertIsNone(self.fx.state()["pending_reboot"])

    # (5) bad signature / host mismatch → refused, never realised, rc 1
    def test_bad_signature_refused(self):
        b = self.fx.system("b", last_modified=2000)
        self.fx.publish(b, tamper=True)
        result = self.fx.run("stage")
        self.assertOk(result, rc=1)
        self.assertEqual(self.fx.state()["last_refusal"]["reason"], "bad-signature")
        self.assertNotIn("--realise", self.fx.calls())

    def test_host_mismatch_refused(self):
        b = self.fx.system("b", last_modified=2000)
        self.fx.publish(b, host="coordinator")
        self.assertOk(self.fx.run("stage"), rc=1)
        self.assertEqual(self.fx.state()["last_refusal"]["reason"], "host-mismatch")
        self.assertNotIn("--realise", self.fx.calls())

    def test_unreachable_nas_is_not_a_failure(self):
        self.assertOk(self.fx.run("stage"))
        self.assertEqual(self.fx.state()["last_refusal"]["reason"], "fetch-failed")

    # (6) manual policy → never realises
    def test_manual_policy_only_reports(self):
        self.fx.config["policy"] = "manual"
        self.fx.save_config()
        b = self.fx.system("b", last_modified=2000)
        self.fx.publish(b)
        self.assertOk(self.fx.run("stage"))
        self.assertOk(self.fx.run("activate"))
        self.assertEqual(self.fx.state()["state"], "candidate-seen")
        self.assertNotIn("--realise", self.fx.calls())
        self.assertNotIn("switch ", self.fx.calls())
        self.assertNotIn("start --no-block", self.fx.calls())

    def test_stage_only_policy_never_activates(self):
        self.fx.config["policy"] = "stage-only"
        self.fx.save_config()
        b = self.fx.system("b", last_modified=2000)
        self.fx.publish(b)
        self.assertOk(self.fx.run("stage"))
        self.assertEqual(self.fx.state()["state"], "closure-ready")
        self.assertIn("--realise", self.fx.calls())
        self.assertNotIn("start --no-block", self.fx.calls())
        self.assertOk(self.fx.run("activate"))
        self.assertNotIn("switch ", self.fx.calls())
        self.assertEqual(self.fx.current(), self.fx.a)

    # (7) downgrade guard
    def test_current_newer_refuses_before_download(self):
        old = self.fx.system("c", last_modified=500)
        self.fx.publish(old)
        self.assertOk(self.fx.run("stage"))
        self.assertOk(self.fx.run("activate"))
        st = self.fx.state()
        self.assertEqual(st["last_refusal"]["reason"], "local-generation-newer")
        self.assertNotIn("--realise", self.fx.calls())
        self.assertNotIn("switch ", self.fx.calls())
        self.assertEqual(self.fx.current(), self.fx.a)

    def test_manifest_claiming_newer_is_checked_against_the_closure(self):
        old = self.fx.system("c", last_modified=500)
        self.fx.publish(old, last_modified=9999)
        self.assertOk(self.fx.run("stage"))
        st = self.fx.state()
        self.assertEqual(st["last_refusal"]["reason"], "local-generation-newer")
        self.assertNotEqual(st["state"], "closure-ready")
        self.assertFalse(os.path.lexists(os.path.join(self.fx.root, "nix/var/nix/gcroots/update-adopt/candidate")))
        self.assertOk(self.fx.run("activate"))
        self.assertNotIn("switch ", self.fx.calls())

    def test_dirty_or_unknown_current_refuses(self):
        dirty = self.fx.system("d", last_modified=100, dirty=True)
        self.fx.point(dirty)
        b = self.fx.system("b", last_modified=2000)
        self.fx.publish(b)
        self.assertOk(self.fx.run("adopt"))
        self.assertIn("dirty", self.fx.state()["last_refusal"]["detail"])
        os.unlink(dirty + "/fleet-revision.json")
        self.assertOk(self.fx.run("adopt"))
        self.assertIn("no recorded revision", self.fx.state()["last_refusal"]["detail"])
        self.assertNotIn("switch ", self.fx.calls())

    def test_force_overrides_downgrade_guard(self):
        old = self.fx.system("c", last_modified=500)
        self.fx.publish(old)
        self.assertOk(self.fx.run("adopt", "--force"))
        self.assertEqual(self.fx.current(), old)
        self.assertEqual(self.fx.state()["state"], "known-good")

    def test_activation_lock_refuses(self):
        import fcntl
        b = self.fx.system("b", last_modified=2000)
        self.fx.publish(b)
        self.assertOk(self.fx.run("stage"))
        with open(os.path.join(self.fx.tmp, "adopt.lock"), "a") as handle:
            fcntl.flock(handle, fcntl.LOCK_EX)
            self.assertOk(self.fx.run("activate"))
        self.assertEqual(self.fx.state()["last_refusal"]["reason"], "activation-running")
        self.assertNotIn("switch ", self.fx.calls())

    def test_status_reports_freshness(self):
        b = self.fx.system("b", last_modified=2000)
        self.fx.publish(b)
        self.fx.run("stage")
        result = self.fx.run("status", "--json")
        self.assertOk(result)
        out = json.loads(result.stdout)
        for key in ("current", "booted", "candidate", "last_attempt", "last_refusal",
                    "last_known_good", "pending_reboot", "current_revision"):
            self.assertIn(key, out)
        self.assertEqual(out["candidate"]["store_path"], b)
        self.assertEqual(out["current_revision"]["lastModified"], 1000)

    def test_receipts_are_capped(self):
        for _ in range(60):
            self.fx.run("stage")  # fetch-failed receipts
        self.assertLessEqual(len(self.fx.receipts()), 50)


class GateTests(unittest.TestCase):
    def setUp(self):
        self.fx = Fixture()

    def tearDown(self):
        self.fx.cleanup()

    def gate(self, *args):
        return subprocess.run(["bash", GATES, *args], env=self.fx.env(), capture_output=True, text=True)

    def put(self, name, value):
        with open(os.path.join(self.fx.tmp, name), "w") as stream:
            stream.write(value if isinstance(value, str) else json.dumps(value))

    def activate_unit(self, unit, scope="system"):
        open(os.path.join(self.fx.tmp, f"sys/active-{scope}", unit), "w").close()

    def test_halogen_idle(self):
        self.assertEqual(self.gate("halogen-idle").returncode, 0)  # nothing active
        self.activate_unit("podman-halogen.service")
        www = os.path.join(self.fx.tmp, "www/127.0.0.1:8731")
        os.makedirs(www, exist_ok=True)
        with open(www + "/health", "w") as stream:
            json.dump({"status": "ok", "in_flight": 0, "queued": 0, "busy": False}, stream)
        # the fake curl maps http://nas.test/<p>; point it at the health file too
        write_exec(os.path.join(self.fx.bin, "curl"),
                   '#!/bin/sh\nfor a; do u="$a"; done\ncat "$FIXTURE/www/${u#http://}"\n')
        self.assertEqual(self.gate("halogen-idle").returncode, 0)
        self.put("ss.txt", "ESTAB 0 0 10.42.0.5:8731 10.42.0.2:5555\n")
        r = self.gate("halogen-idle")
        self.assertEqual(r.returncode, 1, r.stdout)
        self.assertIn("established", r.stdout)
        os.unlink(os.path.join(self.fx.tmp, "ss.txt"))
        with open(www + "/health", "w") as stream:
            json.dump({"status": "ok", "in_flight": 2, "queued": 1, "busy": True}, stream)
        r = self.gate("halogen-idle")
        self.assertEqual(r.returncode, 1)
        self.assertIn("3 request", r.stdout)
        with open(www + "/health", "w") as stream:
            stream.write("<html>not json</html>")
        r = self.gate("halogen-idle")
        self.assertEqual(r.returncode, 2, r.stdout)
        self.assertIn("not parseable", r.stdout)
        os.unlink(www + "/health")
        self.assertEqual(self.gate("halogen-idle").returncode, 2)

    def test_units_inactive(self):
        self.assertEqual(self.gate("units-inactive", "user:tom", "fara-browser-model.service").returncode, 0)
        self.activate_unit("fara-browser-model.service", "tom")
        r = self.gate("units-inactive", "user:tom", "browser-desktop.service", "fara-browser-model.service")
        self.assertEqual(r.returncode, 1)
        self.assertIn("fara-browser-model", r.stdout)

    def test_herdr_agents(self):
        self.assertEqual(self.gate("herdr-agents-idle", "tom").returncode, 0)  # herdr down
        self.activate_unit("herdr.service", "tom")
        agents = lambda *s: {"result": {"agents": [{"pane_id": f"p{i}", "agent_status": x} for i, x in enumerate(s)]}}
        self.put("herdr.json", agents("idle", "done"))
        self.assertEqual(self.gate("herdr-agents-idle", "tom").returncode, 0)
        self.put("herdr.json", agents("idle", "working"))
        r = self.gate("herdr-agents-idle", "tom")
        self.assertEqual(r.returncode, 1)
        self.assertIn("p1=working", r.stdout)
        self.put("herdr.json", agents("blocked"))
        self.assertEqual(self.gate("herdr-agents-idle", "tom").returncode, 1)
        self.put("herdr.json", "not json")
        self.assertEqual(self.gate("herdr-agents-idle", "tom").returncode, 2)

    def test_tally_kernel(self):
        k = os.path.join(self.fx.bin, "tally-kernel")
        self.assertEqual(self.gate("tally-kernel-idle", k, "/sock", "gpu-worker").returncode, 0)
        self.activate_unit("tally-kernel.service")
        self.put("rows.json", {"reply": "row_state", "body": {"row": "gpu-worker", "holders": 0}})
        self.assertEqual(self.gate("tally-kernel-idle", k, "/sock", "gpu-worker", "mechanical").returncode, 0)
        self.put("rows.json", {"reply": "row_state", "body": {"row": "gpu-worker", "holders": 1}})
        r = self.gate("tally-kernel-idle", k, "/sock", "gpu-worker")
        self.assertEqual(r.returncode, 1)
        self.assertIn("holder", r.stdout)
        self.put("kernel-silent", "")
        self.assertEqual(self.gate("tally-kernel-idle", k, "/sock", "gpu-worker").returncode, 2)

    def test_tally_daemon(self):
        sock = os.path.join(self.fx.tmp, "tally.sock")
        self.assertEqual(self.gate("tally-daemon-idle", "tom", sock).returncode, 0)  # no socket
        import socket as sk
        s = sk.socket(sk.AF_UNIX)
        s.bind(sock)
        try:
            self.put("pools.json", {"schemaVersion": 1, "pools": [{"pool": "cc", "held": 0}]})
            self.assertEqual(self.gate("tally-daemon-idle", "tom", sock).returncode, 0)
            self.put("pools.json", {"schemaVersion": 1, "pools": [{"pool": "cc", "held": 0}, {"pool": "worker-gpu", "held": 1}]})
            r = self.gate("tally-daemon-idle", "tom", sock)
            self.assertEqual(r.returncode, 1)
            self.assertIn("worker-gpu=1", r.stdout)
        finally:
            s.close()


if __name__ == "__main__":
    unittest.main()
