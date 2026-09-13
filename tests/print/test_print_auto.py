from __future__ import annotations

import contextlib
import importlib.util
import io
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = Path(
    os.environ.get(
        "PRINT_AUTO_SCRIPT",
        REPO_ROOT / "home/dot_claude/skills/print/scripts/print-auto.py",
    )
)
SCRIPT_SPEC = importlib.util.spec_from_file_location("print_auto", SCRIPT)
if SCRIPT_SPEC is None or SCRIPT_SPEC.loader is None:
    raise RuntimeError(f"could not load print-auto from {SCRIPT}")
print_auto = importlib.util.module_from_spec(SCRIPT_SPEC)
sys.modules["print_auto"] = print_auto
SCRIPT_SPEC.loader.exec_module(print_auto)


class RenderOnlyTests(unittest.TestCase):
    """print-auto renders and never submits (#384): paper-daemon is the one
    submitter, and it steers the render through --profile/--sides."""

    def render(self, *flags: str, pages: int = 2, classifier_sides: str = "duplex"):
        commands: list[list[str]] = []

        def fake_run(command, *args, **kwargs):
            commands.append(command)
            out = Path(command[command.index("-o") + 1])
            out.write_bytes(b"%PDF\n" + b"/Type /Page\n" * pages)
            return mock.Mock(returncode=0)

        decision = {
            "profile": "garamond",
            "require_one_page": False,
            "sides": classifier_sides,
            "filename": "brief.pdf",
            "title": "Brief",
        }
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            source = root / "brief.md"
            source.write_text("# Brief\n")
            jobdir = root / "job"
            argv = ["print-auto.py", str(source), "--output-dir", str(jobdir), *flags]
            with (
                mock.patch.object(sys, "argv", argv),
                mock.patch.object(print_auto, "decide", return_value=(decision, "gpu")),
                mock.patch.object(print_auto.shutil, "which", return_value=None),
                mock.patch.object(print_auto.subprocess, "run", side_effect=fake_run),
                contextlib.redirect_stdout(io.StringIO()),
                contextlib.redirect_stderr(io.StringIO()),
            ):
                rc = print_auto.main()
            receipt = json.loads((jobdir / "decision.json").read_text())
        return rc, commands, receipt

    def test_there_is_no_print_flag(self) -> None:
        with (
            mock.patch.object(sys, "argv", ["print-auto.py", "x.md", "--print"]),
            contextlib.redirect_stderr(io.StringIO()),
            self.assertRaises(SystemExit),
        ):
            print_auto.main()
        self.assertFalse(hasattr(print_auto, "spool_print"))

    def test_only_the_renderer_is_invoked(self) -> None:
        rc, commands, receipt = self.render()
        self.assertEqual(rc, 0)
        self.assertEqual(len(commands), 1)
        self.assertNotIn("--submit-only", commands[0])
        self.assertNotIn("--print", commands[0])
        self.assertNotIn("printed", receipt)

    def test_profile_and_sides_overrides_beat_the_classifier(self) -> None:
        rc, commands, receipt = self.render("--profile", "times", "--sides", "one-sided")
        self.assertEqual(rc, 0)
        cmd = commands[0]
        self.assertEqual(cmd[cmd.index("--profile") + 1], "times")
        self.assertEqual(cmd[cmd.index("--sides") + 1], "one-sided")
        self.assertEqual(receipt["decision"]["profile"], "times")
        self.assertEqual(receipt["decision"]["sides"], "one-sided")
        self.assertEqual(sorted(receipt["overridden"]), ["profile", "sides"])

    def test_no_override_keeps_the_classifier_answer(self) -> None:
        _, commands, receipt = self.render()
        self.assertEqual(receipt["decision"]["profile"], "garamond")
        self.assertEqual(receipt["overridden"], [])
        self.assertNotIn("--sides", commands[0])

    def test_target_mismatch_is_recorded_and_exits_3(self) -> None:
        rc, _, receipt = self.render("--target-pages", "1", pages=2)
        self.assertEqual(rc, 3)
        self.assertEqual(receipt["length_check"], "fail")
        self.assertEqual(receipt["pages_rendered"], 2)
        self.assertEqual(receipt["target_pages"], 1)

    def test_target_match_passes(self) -> None:
        rc, _, receipt = self.render("--target-pages", "2", pages=2)
        self.assertEqual(rc, 0)
        self.assertEqual(receipt["length_check"], "pass")


if __name__ == "__main__":
    unittest.main()
