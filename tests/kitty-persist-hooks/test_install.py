"""home/kitty-persist-hooks.py around the real `kitty-persist harness install`, on copies in a temp HOME.

KP_PROGRAM names the kitty-persist program (checks.kitty-persist-hooks passes
the flake input's package). The layout is the fleet's: two Claude seats whose
settings.json are links to ~/.local/state/claude/settings.json, and a mutable
~/.codex/config.toml with comments and project tables. The guard tests run
the real program and then spoil its result the way a faulty install could
(./spoil.py), to show what the wrapper refuses and puts back. Nothing here
reads a real home.
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
import tomllib
import unittest

here = Path(__file__).resolve().parent
module = Path(os.environ.get("KITTY_PERSIST_HOOKS_MODULE", here.parents[1] / "home/kitty-persist-hooks.py"))
spec = importlib.util.spec_from_file_location("kphooks", module)
kphooks = importlib.util.module_from_spec(spec)
spec.loader.exec_module(kphooks)
PROGRAM = os.environ["KP_PROGRAM"]

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
CLAUDE_EVENTS = 9  # the shipped claude definition's events (S22.11)


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
        (self.root / ".config").mkdir()

    def program(self, spoil=None):
        if spoil is None:
            return PROGRAM
        path = self.root / f"bin-{spoil}/kitty-persist"
        path.parent.mkdir(exist_ok=True)
        path.write_text(f"#!/bin/sh\nexec {sys.executable} -I {here / 'spoil.py'} {spoil} {PROGRAM} \"$@\"\n")
        os.chmod(path, 0o755)
        return str(path)

    def args(self, verb="install", *extra, spoil=None):
        argv = [verb, "--program", self.program(spoil), "--home", str(self.root), "--codex-home", str(self.codex)]
        for seat in self.seats:
            argv += ["--claude-seat", str(seat)]
        return argv + list(extra)

    def snapshot(self):
        hooks = self.codex / "hooks.json"
        return (self.target.read_bytes(), (self.codex / "config.toml").read_bytes(),
                hooks.read_bytes() if hooks.exists() else None)


def run(home, *argv, spoil=None):
    out = io.StringIO()
    saved = dict(os.environ)
    os.environ.update(HOME=str(home.root), XDG_CONFIG_HOME=str(home.root / ".config"))
    try:
        with contextlib.redirect_stdout(out):
            rc = kphooks.main(home.args(*argv, spoil=spoil))
    finally:
        os.environ.clear()
        os.environ.update(saved)
    return rc, out.getvalue()


def commands(value):
    return list(kphooks.commands(value))


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
        mine = commands(settings["hooks"])
        self.assertEqual(len(mine), CLAUDE_EVENTS, mine)
        # Bare program name in every entry.
        self.assertTrue(all(c.startswith("kitty-persist hook claude ") for c in mine), mine)
        self.assertIn("kitty-persist hook claude Stop", mine)
        # Both seats read the same file, so the second seat's install changed nothing.
        self.assertEqual(json.loads((self.home.seats[1] / "settings.json").read_text()), settings)
        self.assertRegex(out, r"claude: \S+/\.claude-work.*\n(.*\n)*")
        config = (self.home.codex / "config.toml").read_text()
        for comment in ("# top comment", "# dated comment, keep me"):
            self.assertIn(comment, config)
        hooks = json.loads((self.home.codex / "hooks.json").read_text())
        codex = commands(hooks)
        self.assertTrue(codex and all(c.startswith("kitty-persist hook codex ") for c in codex), codex)
        state = tomllib.loads(config)["hooks"]["state"]
        self.assertEqual(len(state), len(codex))
        self.assertTrue(all(v["trusted_hash"].startswith("sha256:") for v in state.values()))
        self.assertTrue(all(k.startswith(str(self.home.codex) + "/hooks.json:") for k in state), list(state))
        self.assertEqual(stat.S_IMODE((self.home.codex / "config.toml").stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(self.home.target.stat().st_mode), 0o600)
        once = self.home.snapshot()
        rc, out = run(self.home, "install")
        self.assertEqual(rc, 0, out)
        self.assertEqual(self.home.snapshot(), once)
        self.assertIn(f"claude: {self.home.target} unchanged", out)
        self.assertIn(f"codex: {self.home.codex / 'config.toml'} unchanged", out)
        rc, out = run(self.home, "uninstall")
        self.assertEqual(rc, 0, out)
        self.assertEqual(self.home.snapshot(), original)
        self.seats_intact()

    def test_lost_comments_are_put_back(self):
        original = self.home.snapshot()
        rc, out = run(self.home, "install", spoil="drop-comments")
        self.assertEqual(rc, 1)
        self.assertIn("comment line(s) were dropped", out)
        # Only Codex was spoiled: its two files are back, the Claude install stands.
        self.assertEqual(self.home.snapshot()[1:], original[1:])
        self.assertIn("kitty-persist hook claude Stop", self.home.target.read_text())

    def test_a_notification_override_is_refused(self):
        original = self.home.snapshot()
        rc, out = run(self.home, "install", spoil="notify")
        self.assertEqual(rc, 1)
        self.assertIn("claude: FAILED: a notification override was added: preferredNotifChannel", out)
        self.assertIn("codex: FAILED: a notification override was added: notify", out)
        self.assertEqual(self.home.snapshot(), original)
        self.seats_intact()

    def test_other_settings_must_survive(self):
        original = self.home.snapshot()
        rc, out = run(self.home, "install", spoil="clobber")
        self.assertEqual(rc, 1)
        self.assertIn("settings outside `hooks` changed: model", out)
        self.assertEqual(self.home.snapshot()[0], original[0])

    def test_an_entry_with_a_store_path_is_refused(self):
        original = self.home.snapshot()
        rc, out = run(self.home, "install", spoil="store-path")
        self.assertEqual(rc, 1)
        self.assertIn("does not run the bare program name", out)
        self.assertEqual(self.home.snapshot(), original)

    def test_a_replaced_seat_link_is_refused_and_put_back(self):
        original = self.home.snapshot()
        rc, out = run(self.home, "install", spoil="unlink-seat")
        self.assertEqual(rc, 1)
        self.assertIn("is no longer the link to", out)
        self.assertEqual(self.home.snapshot()[0], original[0])

    def test_broken_json_is_left_untouched(self):
        self.home.target.write_text('{"model": "opus",\n')
        before = self.home.target.read_bytes()
        rc, out = run(self.home, "install")
        self.assertEqual(rc, 1)
        self.assertIn("exited 78", out)
        self.assertEqual(self.home.target.read_bytes(), before)
        self.seats_intact()

    def test_a_failing_program_changes_nothing(self):
        original = self.home.snapshot()
        rc, out = run(self.home, "install", spoil="fail")
        self.assertEqual(rc, 1)
        self.assertIn("exited 3", out)
        self.assertEqual(self.home.snapshot(), original)

    def test_dry_run_touches_nothing_and_shows_the_change(self):
        original = self.home.snapshot()
        rc, out = run(self.home, "install", "--dry-run")
        self.assertEqual(rc, 0, out)
        self.assertEqual(self.home.snapshot(), original)
        self.assertRegex(out, r'\n\+.*"command": "kitty-persist hook claude SessionStart"')
        self.assertRegex(out, r'\n\+.*kitty-persist hook codex SessionStart')
        self.assertRegex(out, r'\n\+\[hooks\.state\.')
        self.seats_intact()

    def test_existing_foreign_hooks_survive(self):
        settings = dict(CLAUDE, hooks={"Stop": [{"hooks": [{"type": "command", "command": "mine"}]}]})
        self.home.target.write_text(json.dumps(settings, indent=2) + "\n")
        foreign = {"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "theirs", "timeout": 5}]}]}}
        (self.home.codex / "hooks.json").write_text(json.dumps(foreign, indent=2) + "\n")
        before = self.home.snapshot()
        rc, out = run(self.home, "install")
        self.assertEqual(rc, 0, out)
        stop = json.loads(self.home.target.read_text())["hooks"]["Stop"]
        self.assertEqual(stop[0], {"hooks": [{"type": "command", "command": "mine"}]})
        self.assertEqual(json.loads((self.home.codex / "hooks.json").read_text())["hooks"]["Stop"][0],
                         foreign["hooks"]["Stop"][0])
        rc, out = run(self.home, "uninstall")
        self.assertEqual(rc, 0, out)
        self.assertEqual(self.home.snapshot(), before)


if __name__ == "__main__":
    unittest.main(verbosity=2)
