"""Only dry-runs, with real local rsync and fake read-only disk metadata.

No shell fragments are sourced, no runtime directories are cleaned, and no
privileged/device operations run. The same file runs locally and in the check.
"""

import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile
import unittest


SOURCE = Path(os.environ.get("MIGRATE_SOURCE", Path(__file__).resolve().parents[2] / "pkgs/nas-home-migrate"))
SERIAL = "260538801482"
DISK = f"/dev/disk/by-id/nvme-WD_BLACK_SN7100_500GB_{SERIAL}"
HDD_UUID = "2345893a-8769-492c-90cb-23b79984a559"

# Fakes answer only these read-only queries. The actual rsync runs locally;
# any secret reader, remote connection or mutator is a test failure.
LSBLK = """#!/usr/bin/env bash
set -eu
case "$*" in
  *'--inverse '*) printf '%s\\n' "${TEST_ANCESTRY_SERIAL:-260538801482}" ;;
  *'--output SERIAL '*) printf '%s\\n' "${TEST_SERIAL:-260538801482}" ;;
  *'--output PARTLABEL '*) printf '%s\\n' "${TEST_LABEL:-disk-primary-home}" ;;
  *'--output MAJ:MIN '*) printf '259:42\\n' ;;
  *) echo 'unexpected lsblk query' >&2; exit 99 ;;
esac
"""
FINDMNT = """#!/usr/bin/env bash
set -eu
case "$*" in
  *'--output FSTYPE') printf '%s\\n' "${TEST_FSTYPE:-btrfs}" ;;
  *'--output FSROOT') printf '%s\\n' "${TEST_FSROOT:-/@home}" ;;
  *'--output MAJ:MIN') printf '%s\\n' "${TEST_DEVICE:-259:42}" ;;
  *'--output OPTIONS') printf '%s\\n' "${TEST_OPTIONS:-rw,noatime}" ;;
  *'--output UUID') printf '%s\\n' "${TEST_HDD_UUID:-2345893a-8769-492c-90cb-23b79984a559}" ;;
  *) echo 'unexpected findmnt query' >&2; exit 99 ;;
esac
"""


class DryRun(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="nas-home-disk-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.home = self.root / "source"
        self.target = self.root / "mounted-home"
        self.home.mkdir()
        (self.target / "tom").mkdir(parents=True)
        text = (SOURCE / "migrate.sh").read_text()
        for token, value in {
            "expectedDisk": DISK, "expectedSerial": SERIAL,
            "hddUuid": HDD_UUID, "excludes": str(SOURCE / "home-excludes"),
        }.items():
            text = text.replace(f"@{token}@", shlex.quote(value))
        self.script = self.root / "nas-home-migrate"
        self.script.write_text(text)
        for name, body in {"lsblk": LSBLK, "findmnt": FINDMNT}.items():
            self.command(name, body)
        for name in ("pg_dumpall", "sqlite3", "tar", "ssh", "runuser", "mount", "systemctl"):
            self.command(name, f"#!/usr/bin/env bash\necho 'UNEXPECTED {name}' >&2\nexit 99\n")
        # Record the real rsync argv, then execute it; reject any invocation
        # without --dry-run, including a regression in the default.
        self.command("rsync", "#!/usr/bin/env bash\nset -eu\n"
                     "printf '%s\\n' \"$@\" > \"$TEST_RSYNC_ARGS\"\n"
                     "case \" $* \" in *' --dry-run '*) ;; *) exit 99 ;; esac\n"
                     f"exec {shlex.quote(shutil.which('rsync'))} \"$@\"\n")
        self.env = dict(os.environ, PATH=f"{self.bin}:{os.environ['PATH']}",
                        TEST_RSYNC_ARGS=str(self.root / "rsync-args"))

    def command(self, name, body):
        path = self.bin / name
        # /usr/bin/env does not exist inside the Nix build sandbox.
        path.write_text(body.replace("#!/usr/bin/env bash", f"#!{shutil.which('bash')}"))
        path.chmod(0o755)

    def file(self, name, content="fixture\n", target=False):
        path = (self.target / "tom" if target else self.home) / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        return path

    def run_home(self, *args, **env):
        return subprocess.run(
            ["bash", str(self.script), "home", "--source", f"{self.home}/",
             "--target", str(self.target), *args],
            env=dict(self.env, **env), text=True, capture_output=True,
        )

    def test_exclusions_and_no_writes(self):
        keep = ["notes/KEEP-NOTES.md", ".codex/sessions/KEEP-SESSION.jsonl",
                ".claude/KEEP-CLAUDE", ".claude-work/KEEP-CC2",
                ".config/herdr/config.toml", ".cargo/config.toml",
                ".local/share/atuin/key", ".local/share/pnpm/project-cli/KEEP-BUNDLE",
                "mecattaf/repo/.git/worktrees/w1/KEEP-GIT", ".wt/repo/KEEP-WORKTREE"]
        excluded = [".cache/EXCLUDED-CACHE", "repo/node_modules/EXCLUDED-NODE",
                    "repo/target/EXCLUDED-BUILD", "repo/.venv/EXCLUDED-VENV",
                    "Downloads/EXCLUDED-DOWNLOAD", ".cargo/registry/EXCLUDED-CARGO",
                    ".bun/install/cache/EXCLUDED-BUN", ".npm/EXCLUDED-NPM",
                    ".local/share/voxtype/EXCLUDED-VOXTYPE",
                    ".local/share/Trash/EXCLUDED-TRASH",
                    ".local/share/pnpm/store/EXCLUDED-PNPM",
                    ".wt/mail/t4/.wrangler/prove-import/EXCLUDED-MAIL",
                    ".config/herdr/session.json", ".config/herdr/session-snapshots/EXCLUDED-SNAPSHOT",
                    ".config/herdr/herdr.sock", ".config/herdr/herdr-client.sock",
                    ".config/herdr/herdr-server.log", ".config/herdr/ssh/EXCLUDED-SSH",
                    ".local/state/herdr/EXCLUDED-STATE"]
        for name in keep + excluded:
            self.file(name)
        before = {name: (self.home / name).read_bytes() for name in keep + excluded}
        self.file("DESTINATION-MARKER", "unchanged", target=True)
        result = self.run_home()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("DRY RUN", result.stdout)
        self.assertIn("--dry-run", result.stdout)
        self.assertNotIn("--delete", (self.root / "rsync-args").read_text())
        for name in keep:
            self.assertIn(name, result.stdout)
        for name in excluded:
            self.assertNotIn(name, result.stdout)
        self.assertEqual(list((self.target / "tom").iterdir()), [self.target / "tom/DESTINATION-MARKER"])
        self.assertEqual(before, {name: (self.home / name).read_bytes() for name in before})
        print("\nRepresentative helper output:\n" + result.stdout)

    def test_final_finds_same_size_same_mtime_change(self):
        source = self.file("CHANGED", "new text\n")
        target = self.file("CHANGED", "old text\n", target=True)
        os.utime(target, ns=(source.stat().st_atime_ns, source.stat().st_mtime_ns))
        result = self.run_home("--final")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("--checksum", result.stdout)
        self.assertIn(">fc", result.stdout)
        self.assertIn("CHANGED", result.stdout)
        self.assertEqual(target.read_text(), "old text\n")

    def test_wrong_targets_refused_before_rsync(self):
        for env in ({"TEST_SERIAL": "WRONG"}, {"TEST_ANCESTRY_SERIAL": "WRONG"}, {"TEST_LABEL": "wrong"},
                    {"TEST_FSTYPE": "ext4"}, {"TEST_FSROOT": "/"},
                    {"TEST_DEVICE": "259:99"}, {"TEST_OPTIONS": "ro,noatime"}):
            with self.subTest(env=env):
                result = self.run_home(**env)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse((self.root / "rsync-args").exists())
        self.command("findmnt", "#!/usr/bin/env bash\nexit 1\n")
        self.assertNotEqual(self.run_home().returncode, 0)
        self.assertFalse((self.root / "rsync-args").exists())

    def test_destination_symlink_refused(self):
        (self.target / "tom").rmdir()
        (self.target / "tom").symlink_to(self.home)
        self.assertNotEqual(self.run_home().returncode, 0)
        self.assertFalse((self.root / "rsync-args").exists())

    def test_escrow_plans_without_reading_secrets(self):
        result = subprocess.run(["bash", str(self.script), "escrow"], env=self.env,
                                text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        for text in ("DRY RUN", "0700", "pg_dumpall", ".backup", "identity.tar"):
            self.assertIn(text, result.stdout)
        self.assertNotIn("UNEXPECTED", result.stderr)
        result = subprocess.run(["bash", str(self.script), "escrow"],
                                env=dict(self.env, TEST_HDD_UUID="wrong"),
                                text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
