"""home/kitty-persist-hooks.py against a stub kitty-persist, on copies in a temp HOME.

The layout is the fleet's: two Claude seats whose settings.json are symlinks
to ~/.local/state/claude/settings.json, and a mutable ~/.codex/config.toml
with comments and project tables. Nothing here reads a real home.
"""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import stat
import sys
import tempfile
import unittest

here = Path(__file__).resolve().parent
module = Path(os.environ.get("KITTY_PERSIST_HOOKS_MODULE", here.parents[1] / "home/kitty-persist-hooks.py"))
spec = importlib.util.spec_from_file_location("kphooks", module)
kphooks = importlib.util.module_from_spec(spec)
spec.loader.exec_module(kphooks)

CLAUDE = {"model": "opus", "voiceEnabled": True, "env": {"DISABLE_UPDATES": "1"}, "permissions": {"defaultMode": "auto"}}
CODEX = """# top comment
model = "gpt"
approvals_reviewer = "user"

[mcp_servers.docs]
command = "docs"

[projects."/w/a"]
trust_level = "trusted"

[projects."/w/b"]
trust_level = "trusted"

[sandbox_workspace_write]
# dated comment, keep me
network_access = false

[features]
daemon_auto_start = false
"""


class Home:
    def __init__(self, root):
        self.root = Path(root)
        self.shared = self.root / ".local/state/claude"
        self.shared.mkdir(parents=True)
        self.target = self.shared / "settings.json"
        self.target.write_text(json.dumps(CLAUDE, indent=2) + "\n")
        os.chmod(self.target, 0o600)
        self.seats = []
        for name in (".claude", ".claude-work"):
            (self.root / name).mkdir()
            (self.root / name / "settings.json").symlink_to(self.target)
            self.seats.append(self.root / name)
        self.codex = self.root / ".codex"
        self.codex.mkdir()
        (self.codex / "config.toml").write_text(CODEX)
        os.chmod(self.codex / "config.toml", 0o600)
        self.program = self.root / "bin/kitty-persist"
        self.program.parent.mkdir()
        self.program.write_text(f"#!/bin/sh\nexec {sys.executable} -I {here / 'stub_kitty_persist.py'} \"$@\"\n")
        os.chmod(self.program, 0o755)

    def args(self, verb="install", *extra, claude_dir=None):
        argv = [verb, "--program", str(self.program), "--home", str(self.root),
                "--claude-dir", str(claude_dir or self.shared), "--codex-home", str(self.codex)]
        for seat in self.seats:
            argv += ["--claude-seat", str(seat)]
        return argv + list(extra)

    def snapshot(self):
        return (self.target.read_bytes(), (self.codex / "config.toml").read_bytes())


def run(home, *argv, mode="good", claude_dir=None):
    out = io.StringIO()
    os.environ["STUB_MODE"] = mode
    try:
        with contextlib.redirect_stdout(out):
            rc = kphooks.main(home.args(*argv, claude_dir=claude_dir))
    finally:
        os.environ.pop("STUB_MODE", None)
    return rc, out.getvalue()


class InstallTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = Home(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def seats_intact(self):
        for seat in self.home.seats:
            link = seat / "settings.json"
            self.assertTrue(link.is_symlink(), link)
            self.assertEqual(Path(os.path.realpath(link)), self.home.target)

    def test_install_twice_then_uninstall(self):
        original = self.home.snapshot()
        rc, out = run(self.home, "install")
        self.assertEqual(rc, 0, out)
        self.seats_intact()
        settings = json.loads(self.home.target.read_text())
        self.assertEqual({k: v for k, v in settings.items() if k != "hooks"}, CLAUDE)
        self.assertIn("kitty-persist hook claude Stop", json.dumps(settings["hooks"]))
        # Both seats read the same file, so the work seat sees the hooks too.
        self.assertEqual(json.loads((self.home.seats[1] / "settings.json").read_text()), settings)
        config = (self.home.codex / "config.toml").read_text()
        for comment in ("# top comment", "# dated comment, keep me"):
            self.assertIn(comment, config)
        self.assertIn("kitty-persist hook codex SessionStart", config)
        self.assertEqual(stat.S_IMODE((self.home.codex / "config.toml").stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(self.home.target.stat().st_mode), 0o600)
        once = self.home.snapshot()
        rc, out = run(self.home, "install")
        self.assertEqual(rc, 0, out)
        self.assertEqual(self.home.snapshot(), once)
        self.assertIn("claude: unchanged", out)
        self.assertIn("codex: unchanged", out)
        rc, out = run(self.home, "uninstall")
        self.assertEqual(rc, 0, out)
        self.assertEqual(self.home.snapshot(), original)
        self.seats_intact()

    def test_a_seat_link_is_never_the_target(self):
        original = self.home.snapshot()
        rc, out = run(self.home, "install", claude_dir=self.home.seats[0])
        self.assertEqual(rc, 1)
        self.assertIn("is a symlink; refusing", out)
        self.assertEqual(self.home.snapshot()[0], original[0])
        self.seats_intact()

    def test_lost_comments_are_put_back(self):
        original = self.home.snapshot()
        rc, out = run(self.home, "install", mode="drop-comments")
        self.assertEqual(rc, 1)
        self.assertIn("comment line(s) were dropped", out)
        self.assertEqual(self.home.snapshot()[1], original[1])

    def test_a_notification_override_is_refused(self):
        original = self.home.snapshot()
        rc, out = run(self.home, "install", mode="notify")
        self.assertEqual(rc, 1)
        self.assertIn("claude: FAILED: a notification override was added: preferredNotifChannel", out)
        self.assertIn("codex: FAILED: a notification override was added: notify", out)
        self.assertEqual(self.home.snapshot(), original)

    def test_other_settings_must_survive(self):
        original = self.home.snapshot()
        rc, out = run(self.home, "install", mode="clobber")
        self.assertEqual(rc, 1)
        self.assertIn("settings outside `hooks` changed: model", out)
        self.assertEqual(self.home.snapshot()[0], original[0])

    def test_broken_json_is_put_back(self):
        original = self.home.snapshot()
        rc, out = run(self.home, "install", mode="bad-json")
        self.assertEqual(rc, 1)
        self.assertIn("no longer JSON", out)
        self.assertEqual(self.home.snapshot()[0], original[0])
        self.seats_intact()

    def test_a_failing_program_changes_nothing(self):
        original = self.home.snapshot()
        rc, out = run(self.home, "install", mode="fail")
        self.assertEqual(rc, 1)
        self.assertIn("exited 3", out)
        self.assertEqual(self.home.snapshot(), original)

    def test_dry_run_touches_nothing_and_shows_the_change(self):
        original = self.home.snapshot()
        rc, out = run(self.home, "install", "--dry-run")
        self.assertEqual(rc, 0, out)
        self.assertEqual(self.home.snapshot(), original)
        self.assertRegex(out, r'\n\+ +"command": "kitty-persist hook claude SessionStart"')
        self.assertIn("+[[hooks.SessionStart]]", out)

    def test_existing_foreign_hooks_survive(self):
        settings = dict(CLAUDE, hooks={"Stop": [{"hooks": [{"type": "command", "command": "mine"}]}]})
        self.home.target.write_text(json.dumps(settings))
        rc, out = run(self.home, "install")
        self.assertEqual(rc, 0, out)
        stop = json.loads(self.home.target.read_text())["hooks"]["Stop"]
        self.assertEqual(stop[0], {"hooks": [{"type": "command", "command": "mine"}]})
        rc, out = run(self.home, "uninstall")
        self.assertEqual(rc, 0, out)
        self.assertEqual(json.loads(self.home.target.read_text()), settings)


if __name__ == "__main__":
    unittest.main(verbosity=2)
