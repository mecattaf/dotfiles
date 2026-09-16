"""checks.land — the copy-then-verify landing tool (CNA-M07).

Hermetic: every lane is built in a temp directory by the test itself, because
the tool's whole claim is about bytes it copied a second ago. The fixture lane
carries the five cases that have actually cost time on a real sweep — a nested
`.git`, a symlink, a tiny file, an excluded glob and a file over the per-file
ceiling — plus the two guards that must abort before anything is written.
"""

from __future__ import annotations

import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = Path(os.environ.get("LAND_PY", REPO_ROOT / "pkgs/land/land.py"))

spec = importlib.util.spec_from_file_location("land", SCRIPT)
land = importlib.util.module_from_spec(spec)
spec.loader.exec_module(land)

BIG_BYTES = 100 * 1024 * 1024  # over the 95 MiB ceiling; sparse, costs no disk


def run(*argv: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(SCRIPT), *argv],
        capture_output=True,
        text=True,
        check=False,
    )


def build_lane(root: Path) -> Path:
    """The fixture lane. Returns its path."""
    lane = root / "lane"
    (lane / "repo" / ".git").mkdir(parents=True)
    (lane / "scratch").mkdir(parents=True)
    (lane / "notes.md").write_text("abc")  # the 3-byte file
    (lane / "repo" / "README.md").write_text("a nested repository\n")
    (lane / "repo" / ".git" / "config").write_text("[core]\n\trepositoryformatversion = 0\n")
    (lane / "repo" / ".git" / "HEAD").write_text("ref: refs/heads/main\n")
    (lane / "scratch" / "noise.log").write_text("excluded by glob\n")
    os.symlink("notes.md", lane / "link.md")
    with open(lane / "big.bin", "wb") as handle:
        handle.truncate(BIG_BYTES)
    return lane


def manifest_of(packet: Path) -> dict:
    return json.loads(land.find_manifest(packet).read_text())


def tree_digest(root: Path) -> list[tuple[str, int, float, str]]:
    """lstat-visible fingerprint of a tree: proof the sources were not touched."""
    out = []
    for path in sorted(root.rglob("*")):
        stat_result = path.lstat()
        kind = "link" if path.is_symlink() else ("dir" if path.is_dir() else "file")
        out.append((str(path.relative_to(root)), stat_result.st_size, stat_result.st_mtime, kind))
    return out


class LandFixtureLane(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.lane = build_lane(self.root)
        self.packet = self.root / "packet"
        self.before = tree_digest(self.lane)
        self.copy = run(
            "copy",
            str(self.lane),
            "--dest",
            str(self.packet),
            "--exclude",
            "*.log",
            "--source-session",
            "test-session-1",
            "--readme-title",
            "Fixture lane",
        )

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def test_copy_succeeds(self) -> None:
        self.assertEqual(self.copy.returncode, 0, self.copy.stderr)
        self.assertIn("land copy OK", self.copy.stdout)

    def test_manifest_row_count_equals_find_type_f(self) -> None:
        manifest = manifest_of(self.packet)
        files = [row for row in manifest["files"] if row.get("kind") != "symlink"]
        found = [
            path
            for path in self.packet.rglob("*")
            if path.is_file() and not path.is_symlink() and path.parent != self.packet
        ]
        found += [
            path
            for path in self.packet.iterdir()
            if path.is_file()
            and not path.is_symlink()
            and path.name != "README.md"
            and not path.name.startswith("preservation-")
        ]
        self.assertEqual(manifest["file_count"], len(files))
        self.assertEqual(manifest["file_count"], len(found))
        # notes.md, repo/README.md, repo/dot-git/{config,HEAD}
        self.assertEqual(manifest["file_count"], 4)

    def test_dot_git_rename_recorded(self) -> None:
        manifest = manifest_of(self.packet)
        renamed = [row for row in manifest["files"] if row.get("renamed_from")]
        self.assertEqual(len(renamed), 2)
        self.assertTrue((self.packet / "lane/repo/dot-git/config").is_file())
        self.assertFalse((self.packet / "lane/repo/.git").exists())
        for row in renamed:
            self.assertIn("dot-git", row["preserved"])
            self.assertIn(".git", row["renamed_from"])
        # the source keeps its own name
        self.assertTrue((self.lane / "repo" / ".git" / "config").is_file())

    def test_symlink_row_not_followed(self) -> None:
        manifest = manifest_of(self.packet)
        links = [row for row in manifest["files"] if row.get("kind") == "symlink"]
        self.assertEqual(len(links), 1)
        self.assertEqual(links[0]["target"], "notes.md")
        self.assertTrue(os.path.islink(self.packet / "lane/link.md"))
        self.assertEqual(manifest["symlink_count"], 1)

    def test_three_byte_file_lands_with_mode_and_mtime(self) -> None:
        manifest = manifest_of(self.packet)
        row = next(r for r in manifest["files"] if r["source"].endswith("notes.md"))
        self.assertEqual(row["bytes"], 3)
        self.assertEqual(row["source_session"], "test-session-1")
        self.assertIn("mtime", row)
        source = self.lane / "notes.md"
        preserved = self.packet / "lane/notes.md"
        self.assertEqual(int(source.stat().st_mtime), int(preserved.stat().st_mtime))
        self.assertEqual(source.stat().st_mode, preserved.stat().st_mode)

    def test_exclusions_carry_reasons(self) -> None:
        manifest = manifest_of(self.packet)
        reasons = {entry["path"]: entry["reason"] for entry in manifest["excluded"]}
        log = str(self.lane / "scratch/noise.log")
        big = str(self.lane / "big.bin")
        self.assertIn(log, reasons)
        self.assertIn("--exclude *.log", reasons[log])
        self.assertIn(big, reasons)
        self.assertIn("ceiling", reasons[big])
        self.assertFalse((self.packet / "lane/big.bin").exists())

    def test_readme_states_counts_exclusions_and_verification(self) -> None:
        readme = (self.packet / "README.md").read_text()
        self.assertIn("# Fixture lane", readme)
        self.assertIn("big.bin", readme)
        self.assertIn("## Verification", readme)
        self.assertIn("manifest rows == find -type f count", readme)
        self.assertIn("4 == 4", readme)
        self.assertIn("dot-git", readme)

    def test_verify_and_diff_exit_zero(self) -> None:
        verify = run("verify", str(self.packet))
        self.assertEqual(verify.returncode, 0, verify.stderr)
        self.assertIn("land verify OK", verify.stdout)
        diff = run("diff", str(self.lane), str(self.packet))
        self.assertEqual(diff.returncode, 0, diff.stderr)
        self.assertIn("no differences", diff.stdout)

    def test_sources_were_not_touched(self) -> None:
        self.assertEqual(self.before, tree_digest(self.lane))

    def test_verify_fails_on_a_flipped_byte(self) -> None:
        target = self.packet / "lane/notes.md"
        target.write_text("abd")
        verify = run("verify", str(self.packet))
        self.assertEqual(verify.returncode, 1)
        self.assertIn("sha256 does not match", verify.stderr)
        self.assertIn("sha256 MISMATCH", verify.stdout)

    def test_verify_fails_on_a_stray_file(self) -> None:
        (self.packet / "lane" / "stray.md").write_text("not in the manifest\n")
        verify = run("verify", str(self.packet))
        self.assertEqual(verify.returncode, 1)
        self.assertIn("count mismatch", verify.stderr)
        # every hash still matched: the receipt must not blame sha256 for a count
        self.assertIn("sha256 all match", verify.stdout)
        self.assertIn("land verify FAILED", verify.stdout)

    def test_verify_fails_on_a_missing_file(self) -> None:
        (self.packet / "lane/notes.md").unlink()
        verify = run("verify", str(self.packet))
        self.assertEqual(verify.returncode, 1)
        self.assertIn("missing from the packet", verify.stderr)

    def test_diff_fails_when_the_source_drifts(self) -> None:
        (self.lane / "notes.md").write_text("abcd")
        diff = run("diff", str(self.lane), str(self.packet))
        self.assertEqual(diff.returncode, 1)
        self.assertIn("source bytes differ", diff.stderr)

    def test_diff_fails_on_a_source_file_absent_from_the_packet(self) -> None:
        (self.lane / "late.md").write_text("written after the copy\n")
        diff = run("diff", str(self.lane), str(self.packet))
        self.assertEqual(diff.returncode, 1)
        self.assertIn("absent from the packet", diff.stderr)

    def test_verify_survives_a_moved_packet(self) -> None:
        moved = self.root / "moved-packet"
        os.rename(self.packet, moved)
        verify = run("verify", str(moved))
        self.assertEqual(verify.returncode, 0, verify.stderr)


class LandGuards(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.lane = self.root / "lane"
        self.lane.mkdir()
        (self.lane / "keep.md").write_text("ordinary prose\n")
        self.packet = self.root / "packet"

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def test_secret_name_aborts_before_writing(self) -> None:
        (self.lane / "deploy.env").write_text("PORT=8080\n")
        result = run("copy", str(self.lane), "--dest", str(self.packet))
        self.assertEqual(result.returncode, 2)
        self.assertIn("deploy.env", result.stderr)
        self.assertIn("*.env", result.stderr)
        self.assertFalse(self.packet.exists())

    def test_allow_secret_names_lets_a_name_through(self) -> None:
        (self.lane / "deploy.env").write_text("PORT=8080\n")
        result = run(
            "copy", str(self.lane), "--dest", str(self.packet), "--allow-secret-names"
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.packet / "lane/deploy.env").is_file())

    def test_secret_content_aborts_and_never_prints_the_value(self) -> None:
        value = "ghp_" + "A1b2C3d4E5f6G7h8I9j0KL"
        (self.lane / "runbook.md").write_text(f"export GH_TOKEN={value}\n")
        result = run(
            "copy", str(self.lane), "--dest", str(self.packet), "--allow-secret-names"
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("runbook.md", result.stderr)
        self.assertIn("GitHub personal access token", result.stderr)
        self.assertNotIn(value, result.stderr + result.stdout)
        self.assertFalse(self.packet.exists())

    def test_private_key_block_aborts(self) -> None:
        (self.lane / "notes.md").write_text("-----BEGIN OPENSSH PRIVATE KEY-----\n")
        result = run("copy", str(self.lane), "--dest", str(self.packet))
        self.assertEqual(result.returncode, 2)
        self.assertIn("PEM private key block", result.stderr)

    def test_binary_file_is_not_content_scanned(self) -> None:
        (self.lane / "image.bin").write_bytes(b"\0\0ghp_" + b"A" * 30)
        result = run("copy", str(self.lane), "--dest", str(self.packet))
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_gitfile_is_renamed_like_a_git_directory(self) -> None:
        (self.lane / "submodule").mkdir()
        (self.lane / "submodule" / ".git").write_text("gitdir: ../.git/modules/x\n")
        result = run("copy", str(self.lane), "--dest", str(self.packet))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.packet / "lane/submodule/dot-git").is_file())
        row = next(
            r
            for r in manifest_of(self.packet)["files"]
            if r["preserved"].endswith("submodule/dot-git")
        )
        self.assertTrue(row["renamed_from"].endswith("submodule/.git"))

    def test_non_empty_destination_is_refused(self) -> None:
        self.packet.mkdir()
        (self.packet / "already-here.md").write_text("prior contents\n")
        result = run("copy", str(self.lane), "--dest", str(self.packet))
        self.assertEqual(result.returncode, 2)
        self.assertIn("is not empty", result.stderr)

    def test_destination_inside_source_is_refused(self) -> None:
        result = run("copy", str(self.lane), "--dest", str(self.lane / "inner"))
        self.assertEqual(result.returncode, 2)
        self.assertIn("sits inside source", result.stderr)


class LandLegacyManifest(unittest.TestCase):
    """A pre-land packet has no mtime and no source_session. Warn, do not fail."""

    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.packet = Path(self.tmp.name) / "nyu-style"
        self.packet.mkdir()
        body = "the delivered deck\n"
        (self.packet / "deck.md").write_text(body)
        manifest = {
            "date": "2026-09-16",
            "source_session": "codex:01a0a46d",
            "files": [
                {
                    "source": "/home/tom/decks/nyu-2026-09-15/deck.md",
                    "preserved": str(self.packet / "deck.md"),
                    "bytes": len(body),
                    "sha256": land.sha256_bytes(body.encode()),
                }
            ],
        }
        (self.packet / "preservation-2026-09-16.json").write_text(json.dumps(manifest, indent=1))

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def test_missing_mtime_warns_and_still_exits_zero(self) -> None:
        result = run("verify", str(self.packet))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("no mtime recorded", result.stderr)
        self.assertIn("no source_session recorded", result.stderr)
        self.assertIn("land verify OK", result.stdout)
        self.assertIn("2 warnings", result.stdout)


class LandCleanLane(unittest.TestCase):
    """No renames, no exclusions: the one shape where rsync can be a second opinion."""

    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.lane = root / "clean"
        (self.lane / "sub").mkdir(parents=True)
        (self.lane / "a.md").write_text("one\n")
        (self.lane / "sub" / "b.md").write_text("two\n")
        self.packet = root / "packet"
        self.copy = run("copy", str(self.lane), "--dest", str(self.packet))

    def tearDown(self) -> None:
        self.tmp.cleanup()

    @unittest.skipUnless(land.rsync_available(), "rsync is not on PATH")
    def test_diff_cross_checks_with_rsync(self) -> None:
        diff = run("diff", str(self.lane), str(self.packet))
        self.assertEqual(diff.returncode, 0, diff.stderr)
        self.assertIn("rsync -rn --checksum (0 transfer lines)", diff.stdout)

    @unittest.skipUnless(land.rsync_available(), "rsync is not on PATH")
    def test_rsync_sees_a_planted_difference(self) -> None:
        (self.packet / "clean/a.md").write_text("one\n")
        os.utime(self.packet / "clean/a.md", (0, 0))
        (self.lane / "sub" / "c.md").write_text("three\n")
        lines = land.rsync_differences(self.lane, self.packet / "clean")
        self.assertTrue(any("c.md" in line for line in lines), lines)

    def test_readme_names_the_ceiling_in_mib(self) -> None:
        self.assertIn("95 MiB", (self.packet / "README.md").read_text())


class LandUnits(unittest.TestCase):
    def test_secret_name_globs(self) -> None:
        self.assertEqual(land.secret_name_hit("deploy.env"), "*.env")
        self.assertEqual(land.secret_name_hit("GITHUB_TOKEN.md"), "*token*")
        self.assertEqual(land.secret_name_hit("id_ed25519.pub"), "id_ed25519*")
        self.assertEqual(land.secret_name_hit("backup.age"), "*.age")
        self.assertIsNone(land.secret_name_hit("README.md"))

    def test_mtime_is_iso_with_offset(self) -> None:
        stamp = land.iso_mtime(1758016000.0)
        self.assertRegex(stamp, r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2}$")

    def test_ceiling_is_95_mib(self) -> None:
        self.assertEqual(land.MAX_FILE_BYTES, 95 * 1024 * 1024)


if __name__ == "__main__":
    unittest.main(verbosity=2)
