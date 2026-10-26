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

    def render(self, *flags: str, pages: int = 2, classifier_sides: str = "duplex",
               fitted_pages: list[int] | None = None):
        commands: list[list[str]] = []

        def fake_run(command, *args, **kwargs):
            commands.append(command)
            out = Path(command[command.index("-o") + 1])
            measured = fitted_pages[min(len(commands) - 1, len(fitted_pages) - 1)] if fitted_pages else pages
            out.write_bytes(b"%PDF\n" + b"/Type /Page\n" * measured)
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
        rc, _, receipt = self.render("--target-pages", "1", pages=4)
        self.assertEqual(rc, 3)
        self.assertEqual(receipt["length_check"], "fail")
        self.assertEqual(receipt["pages_rendered"], 4)
        self.assertEqual(receipt["target_pages"], 1)
        self.assertEqual(receipt["page_slack"], 2)

    def test_within_default_slack_passes(self) -> None:
        rc, _, receipt = self.render("--target-pages", "20", pages=22)
        self.assertEqual(rc, 0)
        self.assertEqual(receipt["length_check"], "pass")

    def test_zero_slack_is_exact(self) -> None:
        rc, _, receipt = self.render("--target-pages", "1", "--page-slack", "0", pages=2)
        self.assertEqual(rc, 3)
        self.assertEqual(receipt["length_check"], "fail")

    def test_target_match_passes(self) -> None:
        rc, _, receipt = self.render("--target-pages", "2", pages=2)
        self.assertEqual(rc, 0)
        self.assertEqual(receipt["length_check"], "pass")

    def test_layout_is_measured_and_stops_on_first_fit(self) -> None:
        rc, commands, receipt = self.render("--target-pages", "1", "--page-slack", "0",
                                             fitted_pages=[2, 1])
        self.assertEqual(rc, 0)
        self.assertEqual(len(commands), 2)
        self.assertEqual(commands[1][-3:], ["--layout", "compact", "--force"])
        self.assertEqual(receipt["render_attempts"], [
            {"layout": "standard", "pages": 2}, {"layout": "compact", "pages": 1}])

    def test_unfittable_source_is_rejected_after_three_layouts(self) -> None:
        rc, commands, receipt = self.render("--target-pages", "1", "--page-slack", "0", pages=8)
        self.assertEqual(rc, 3)
        self.assertEqual(len(commands), 3)
        self.assertEqual(receipt["layout"], "dense")

    def test_short_source_is_not_padded_or_repeated(self) -> None:
        rc, commands, _ = self.render("--target-pages", "10", pages=1)
        self.assertEqual(rc, 3)
        self.assertEqual(len(commands), 1)


class ClassifierTests(unittest.TestCase):
    def test_non_objects_and_wrong_field_types_are_invalid_not_crashes(self) -> None:
        good = print_auto.default_decision(Path("brief.md"))
        for data in (None, [], ["x"], True, "text", {**good, "profile": []},
                     {**good, "sides": {}}, {**good, "title": None},
                     {**good, "filename": ["brief.pdf"]}):
            with self.subTest(data=data):
                self.assertIsInstance(print_auto.validate(json.dumps(data)), str)

    def test_two_malformed_gufo_decisions_fall_back(self) -> None:
        with (mock.patch.object(print_auto, "ask_utility", side_effect=["null", "[]"]),
              contextlib.redirect_stderr(io.StringIO())):
            decision, provenance = print_auto.decide("# Brief", None, Path("brief.md"))
        self.assertEqual(provenance, "fallback")
        self.assertEqual(decision["profile"], "source-serif")


if __name__ == "__main__":
    unittest.main()
