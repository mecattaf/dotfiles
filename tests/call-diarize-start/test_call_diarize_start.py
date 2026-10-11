"""Hermetic test for home/dot_local/bin/call-diarize-start.

Runs the REAL script against a temp PATH that carries a fake `systemd-run`
(records its argv to a file, exits 0) and a fake `call-diarize` (so the
"is the diarizer here" check passes). No systemd, no GPU, no live recording.

Why this test exists (handoff 2026-10-10): `call-record stop` used to enqueue
a Tally event, and Tally was removed on 2026-09-30, so diarization silently
stopped happening. The replacement starts the diarizer as a detached user unit
straight from the stop. There is no timer behind it by rule, so the one
command line this script builds IS the whole mechanism, and this test pins it.

What it pins:
  * the systemd-run argv: --user, --no-block, --collect, the unit name derived
    from the dir basename, both output streams appended to <dir>/diarize.log,
    and `call-diarize <absolute dir>` as the payload
  * extra args after the dir ride through to call-diarize, after the dir
  * a dir that already has transcript.md is refused (exit 1) and systemd-run is
    never called; --force overrides that
  * a dir without mix.wav is refused (exit 1)
  * a host without call-diarize on PATH is refused (exit 1) with the hand-off
    hint
  * --dry-run prints the argv one per line and never calls systemd-run
  * call-record no longer mentions the Tally enqueue and does call
    call-diarize-start on both the local and the ssh hand-off path
"""

import os
import pathlib
import shutil
import stat
import subprocess
import tempfile
import unittest

SCRIPT = os.environ.get("CALL_DIARIZE_START_SCRIPT")
CALL_RECORD = os.environ.get("CALL_RECORD_SCRIPT")

# The nix sandbox has no /usr/bin/env, so the fakes take the resolved bash.
BASH = shutil.which("bash") or "/bin/bash"

FAKE_SYSTEMD_RUN = """#!{bash}
printf '%s\\n' "$@" > "$FAKE_SYSTEMD_RUN_LOG"
exit 0
"""

FAKE_CALL_DIARIZE = """#!{bash}
echo "fake call-diarize must never run from call-diarize-start tests" >&2
exit 97
"""


def write_exec(path, body):
    path.write_text(body.format(bash=BASH))
    path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


class CallDiarizeStartTest(unittest.TestCase):
    def setUp(self):
        self.assertTrue(SCRIPT, "CALL_DIARIZE_START_SCRIPT must be set")
        self.tmp = pathlib.Path(tempfile.mkdtemp(prefix="call-diarize-start-"))
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        self.bin = self.tmp / "bin"
        self.bin.mkdir()
        write_exec(self.bin / "systemd-run", FAKE_SYSTEMD_RUN)
        write_exec(self.bin / "call-diarize", FAKE_CALL_DIARIZE)
        self.argv_log = self.tmp / "systemd-run.argv"
        self.call_dir = self.tmp / "calls" / "2026-10-10-test-call"
        self.call_dir.mkdir(parents=True)
        (self.call_dir / "mix.wav").touch()

    def run_script(self, *args, with_diarizer=True):
        env = dict(os.environ)
        if with_diarizer:
            # Real coreutils and bash stay reachable; the fakes come first.
            env["PATH"] = os.pathsep.join([str(self.bin), os.environ.get("PATH", "")])
        else:
            # The strix itself carries the real call-diarize, so the inherited
            # PATH would defeat this case. Build a closed PATH: the fake
            # systemd-run plus symlinks to exactly the tools the script needs.
            alt = self.tmp / "bin-no-diarizer"
            alt.mkdir(exist_ok=True)
            shutil.copy(self.bin / "systemd-run", alt / "systemd-run")
            for tool in ("bash", "realpath", "basename", "tr", "env"):
                real = shutil.which(tool)
                self.assertTrue(real, f"{tool} must be on PATH for the test")
                (alt / tool).symlink_to(real)
            env["PATH"] = str(alt)
        env["FAKE_SYSTEMD_RUN_LOG"] = str(self.argv_log)
        return subprocess.run(["bash", SCRIPT, *args], env=env,
                              capture_output=True, text=True)

    def recorded_argv(self):
        return self.argv_log.read_text().splitlines()

    def test_launches_detached_unit_with_pinned_argv(self):
        result = self.run_script(str(self.call_dir))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(self.argv_log.exists(), "fake systemd-run was not called")
        argv = self.recorded_argv()
        absdir = str(self.call_dir.resolve())
        for flag in ("--user", "--no-block", "--collect"):
            self.assertIn(flag, argv)
        unit_index = argv.index("--unit")
        self.assertEqual(argv[unit_index + 1], "call-diarize-2026-10-10-test-call")
        self.assertIn(f"StandardOutput=append:{absdir}/diarize.log", argv)
        self.assertIn(f"StandardError=append:{absdir}/diarize.log", argv)
        self.assertIn(f"WorkingDirectory={absdir}", argv)
        self.assertEqual(argv[-2:], ["call-diarize", absdir])
        self.assertIn("diarization started: call-diarize-2026-10-10-test-call", result.stdout)
        self.assertIn(f"{absdir}/diarize.log", result.stdout)

    def test_relative_dir_is_made_absolute(self):
        result = subprocess.run(
            ["bash", SCRIPT, "2026-10-10-test-call"],
            cwd=self.call_dir.parent,
            env={**os.environ,
                 "PATH": os.pathsep.join([str(self.bin), os.environ.get("PATH", "")]),
                 "FAKE_SYSTEMD_RUN_LOG": str(self.argv_log)},
            capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.recorded_argv()[-1], str(self.call_dir.resolve()))

    def test_extra_args_follow_the_dir(self):
        result = self.run_script(str(self.call_dir), "--hotwords", "Sodimo,Leger")
        self.assertEqual(result.returncode, 0, result.stderr)
        argv = self.recorded_argv()
        absdir = str(self.call_dir.resolve())
        self.assertEqual(argv[-4:], ["call-diarize", absdir, "--hotwords", "Sodimo,Leger"])

    def test_existing_transcript_refuses_without_force(self):
        (self.call_dir / "transcript.md").write_text("# done\n")
        result = self.run_script(str(self.call_dir))
        self.assertEqual(result.returncode, 1)
        self.assertIn("transcript.md", result.stderr)
        self.assertIn("--force", result.stderr)
        self.assertFalse(self.argv_log.exists(), "systemd-run must not be called")

    def test_force_runs_despite_transcript(self):
        (self.call_dir / "transcript.md").write_text("# done\n")
        result = self.run_script("--force", str(self.call_dir))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(self.argv_log.exists())
        self.assertEqual(self.recorded_argv()[-1], str(self.call_dir.resolve()))

    def test_missing_mix_refuses(self):
        (self.call_dir / "mix.wav").unlink()
        result = self.run_script(str(self.call_dir))
        self.assertEqual(result.returncode, 1)
        self.assertIn("mix.wav", result.stderr)
        self.assertFalse(self.argv_log.exists())

    def test_missing_dir_refuses(self):
        result = self.run_script(str(self.tmp / "nowhere"))
        self.assertEqual(result.returncode, 1)
        self.assertFalse(self.argv_log.exists())

    def test_host_without_diarizer_refuses(self):
        result = self.run_script(str(self.call_dir), with_diarizer=False)
        self.assertEqual(result.returncode, 1)
        self.assertIn("no diarizer", result.stderr)
        self.assertIn("strix", result.stderr)
        self.assertFalse(self.argv_log.exists())

    def test_dry_run_prints_argv_and_runs_nothing(self):
        result = self.run_script("--dry-run", str(self.call_dir), "--hotwords", "x")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.argv_log.exists(), "dry run must not call systemd-run")
        lines = result.stdout.splitlines()
        absdir = str(self.call_dir.resolve())
        self.assertEqual(lines[0], "systemd-run")
        for flag in ("--user", "--no-block", "--collect"):
            self.assertIn(flag, lines)
        self.assertIn("call-diarize-2026-10-10-test-call", lines)
        self.assertEqual(lines[-3:], [absdir, "--hotwords", "x"])
        self.assertEqual(lines[-4], "call-diarize")

    def test_unit_name_is_sanitised(self):
        odd = self.tmp / "calls" / "2026-10-10 odd:name"
        odd.mkdir()
        (odd / "mix.wav").touch()
        result = self.run_script("--dry-run", str(odd))
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = result.stdout.splitlines()
        self.assertEqual(lines[lines.index("--unit") + 1], "call-diarize-2026-10-10_odd_name")


class CallRecordHandsOffToStartTest(unittest.TestCase):
    def test_call_record_uses_call_diarize_start(self):
        self.assertTrue(CALL_RECORD, "CALL_RECORD_SCRIPT must be set")
        text = pathlib.Path(CALL_RECORD).read_text()
        self.assertNotIn("call-diarize-backfill --enqueue", text)
        self.assertNotIn("call-diarize-backfill", text)
        self.assertIn('call-diarize-start "$dir"', text)
        self.assertIn(
            "tar -C ~/Recordings/calls -xf - && call-diarize-start $remote", text)
        self.assertIn("command -v call-diarize >/dev/null", text)


if __name__ == "__main__":
    unittest.main()
