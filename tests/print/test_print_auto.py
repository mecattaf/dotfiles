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


class RenderHarness(unittest.TestCase):
    def render(self, *flags: str, pages: int = 2, classifier_sides: str = "duplex",
               fitted_pages: list[int] | None = None,
               defects: list[list[dict]] | None = None, measure: bool = True,
               review=None):
        commands: list[list[str]] = []

        def fake_run(command, *args, **kwargs):
            commands.append(command)
            out = Path(command[command.index("-o") + 1])
            index = len(commands) - 1
            measured = fitted_pages[min(index, len(fitted_pages) - 1)] if fitted_pages else pages
            out.write_bytes(b"%PDF\n" + b"/Type /Page\n" * measured)
            if measure:
                found = defects[min(index, len(defects) - 1)] if defects else []
                Path(command[command.index("--measure") + 1]).write_text(json.dumps({
                    "status": "measured", "pages": measured, "defects": found,
                    "page_facts": [], "advisories": [],
                    "type": {"body_pt": 11.25, "table_pt": 10.125}}))
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
                mock.patch.object(print_auto, "review_candidate",
                                  side_effect=review or self.no_model) as reviewer,
                contextlib.redirect_stdout(io.StringIO()),
                contextlib.redirect_stderr(io.StringIO()),
            ):
                rc = print_auto.main()
            receipt = json.loads((jobdir / "decision.json").read_text())
            self.assertTrue((jobdir / "brief.pdf").exists())
        self.reviewer = reviewer
        return rc, commands, receipt

    @staticmethod
    def no_model(pdf, measurement, text, sides):
        return {"status": "unavailable", "verdict": "degraded", "pages": [],
                "failed_pages": [], "reason": "no model in tests"}

    @staticmethod
    def layouts(commands):
        return [c[c.index("--layout") + 1] for c in commands]



class RenderOnlyTests(RenderHarness):
    """print-auto renders and never submits (#384): paper-daemon is the one
    submitter, and it steers the render through --profile/--sides."""

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
        self.assertEqual(commands[1][-3:], ["--layout", "snug", "--force"])
        self.assertEqual(receipt["render_attempts"], [
            {"layout": "standard", "pages": 2}, {"layout": "snug", "pages": 1}])
        self.assertEqual(receipt["layout"], "snug")

    def test_unfittable_source_is_rejected_after_four_layouts(self) -> None:
        rc, commands, receipt = self.render("--target-pages", "1", "--page-slack", "0", pages=8)
        self.assertEqual(rc, 3)
        self.assertEqual(self.layouts(commands), ["standard", "snug", "compact", "dense"])
        self.assertEqual(receipt["layout"], "dense")
        self.assertEqual(receipt["quality_check"], "pass")

    def test_short_source_is_not_padded_or_repeated(self) -> None:
        rc, commands, _ = self.render("--target-pages", "10", pages=1)
        self.assertEqual(rc, 3)
        self.assertEqual(len(commands), 1)



HEADING_ONLY = {"kind": "heading_only_page", "severity": "hard", "page": 4,
                "detail": "the page holds only a section heading"}
SHORT_TAIL = {"kind": "short_tail", "severity": "soft", "page": 12, "detail": "two lines"}


class LayoutGateTests(RenderHarness):
    """#673: page quality is measured on every candidate before one PDF is
    handed to paper-daemon, even when the page count is within tolerance."""

    def test_heading_only_page_within_page_tolerance_is_repaired_by_the_next_layout(self):
        # The 3 November shape: 12 pages passed 10 ± 2, page 4 was a heading.
        rc, commands, receipt = self.render(
            "--target-pages", "10", fitted_pages=[12, 11], defects=[[HEADING_ONLY], []])
        self.assertEqual(rc, 0)
        self.assertEqual(self.layouts(commands), ["standard", "snug"])
        self.assertEqual(receipt["layout"], "snug")
        self.assertEqual(receipt["quality_check"], "pass")
        self.assertEqual(receipt["candidates"][0]["defects"], [HEADING_ONLY])

    def test_unrepairable_defect_is_rejected_and_never_reviewed_as_a_pass(self):
        approve = mock.Mock(return_value={"status": "reviewed", "verdict": "pass",
                                          "pages": [], "failed_pages": []})
        rc, commands, receipt = self.render(pages=5, defects=[[HEADING_ONLY]], review=approve)
        self.assertEqual(rc, 3)
        self.assertEqual(len(commands), 4)  # bounded: each layout once
        self.assertEqual(receipt["quality_check"], "fail")
        self.assertEqual(receipt["quality"]["defects"], [HEADING_ONLY])
        approve.assert_not_called()
        self.assertEqual(receipt["page_review"]["status"], "not_run")

    def test_missing_measurement_fails_closed(self):
        rc, _, receipt = self.render(measure=False)
        self.assertEqual(rc, 3)
        self.assertEqual(receipt["quality_check"], "fail")
        self.assertEqual(receipt["quality"]["defects"][0]["kind"], "unmeasured")

    def test_eleven_duplex_pages_fit_to_ten_and_save_a_sheet(self):
        rc, commands, receipt = self.render(fitted_pages=[11, 10])
        self.assertEqual(rc, 0)
        self.assertEqual(self.layouts(commands), ["standard", "snug"])
        self.assertEqual(receipt["layout"], "snug")
        self.assertEqual(receipt["pages_rendered"], 10)
        self.assertEqual([c["sheets"] for c in receipt["candidates"]], [6, 5])

    def test_twelve_pages_do_not_chase_eleven(self):
        rc, commands, receipt = self.render(fitted_pages=[12, 11])
        self.assertEqual(rc, 0)
        self.assertEqual(self.layouts(commands), ["standard"])

    def test_unsuitable_eleven_stays_eleven_without_padding(self):
        rc, commands, receipt = self.render(fitted_pages=[11, 11])
        self.assertEqual(rc, 0)
        self.assertEqual(receipt["layout"], "standard")
        self.assertEqual(receipt["pages_rendered"], 11)
        self.assertIsNone(receipt["target_pages"])  # no page target invented

    def test_snug_that_breaks_the_layout_is_not_chosen(self):
        rc, _, receipt = self.render(fitted_pages=[11, 10], defects=[[], [HEADING_ONLY]])
        self.assertEqual(rc, 0)
        self.assertEqual(receipt["layout"], "standard")

    def test_one_sided_prints_do_not_try_to_save_a_sheet(self):
        _, commands, _ = self.render("--sides", "one-sided", fitted_pages=[11, 10])
        self.assertEqual(self.layouts(commands), ["standard"])

    def test_short_tail_tries_a_same_size_reflow_only(self):
        rc, commands, receipt = self.render(fitted_pages=[12, 12], defects=[[SHORT_TAIL], [SHORT_TAIL]])
        self.assertEqual(rc, 0)
        self.assertEqual(self.layouts(commands), ["standard", "snug"])
        self.assertEqual(receipt["layout"], "standard")  # partly filled final page stays valid
        self.assertEqual(receipt["quality"]["soft"], [SHORT_TAIL])

    def test_model_concerns_move_to_a_clean_alternative_it_approves(self):
        def review(pdf, measurement, text, sides):
            verdict = "concerns" if pdf.name == "standard.pdf" else "pass"
            return {"status": "reviewed", "verdict": verdict, "pages": [],
                    "failed_pages": [3] if verdict == "concerns" else []}
        rc, _, receipt = self.render(fitted_pages=[11, 11], review=review)
        self.assertEqual(rc, 0)
        self.assertEqual(receipt["layout"], "snug")
        self.assertEqual([r["layout"] for r in receipt["page_reviews"]], ["standard", "snug"])
        self.assertEqual(receipt["page_review"]["verdict"], "pass")

    def test_degraded_review_is_recorded_and_the_gate_still_decides(self):
        rc, _, receipt = self.render()
        self.assertEqual(rc, 0)
        self.assertEqual(receipt["page_review"]["status"], "unavailable")
        self.assertEqual(receipt["quality_check"], "pass")


class PageReviewTests(unittest.TestCase):
    def review(self, answers, pages=3, which="/bin/pdftoppm"):
        def fake_run(command, *args, **kwargs):
            prefix = Path(command[-1])
            for number in range(1, int(command[command.index("-l") + 1]) + 1):
                (prefix.parent / f"page-{number:02d}.png").write_bytes(b"\x89PNG" + b"x" * 10)
            return mock.Mock(returncode=0, stderr=b"")
        with (mock.patch.object(print_auto.shutil, "which", return_value=which),
              mock.patch.object(print_auto.subprocess, "run", side_effect=fake_run),
              mock.patch.object(print_auto, "ask_utility", side_effect=answers) as ask):
            result = print_auto.review_candidate(Path("/tmp/x.pdf"), {"pages": pages}, "# T\n", "duplex")
        return result, ask

    def test_pages_are_sent_as_images_with_measured_facts(self):
        answer = json.dumps({"pages": [{"page": n, "verdict": "pass", "issues": []} for n in (1, 2, 3)]})
        result, ask = self.review([answer])
        self.assertEqual(result["verdict"], "pass")
        content = ask.call_args.args[0]
        self.assertEqual(sum(1 for part in content if part["type"] == "image_url"), 3)
        self.assertIn("Measured layout facts", content[0]["text"])
        self.assertTrue(content[2]["image_url"]["url"].startswith("data:image/png;base64,"))

    def test_batches_are_bounded(self):
        batches = [json.dumps({"pages": [{"page": n, "verdict": "pass"} for n in range(1, 7)]}),
                   json.dumps({"pages": [{"page": n, "verdict": "pass"} for n in range(7, 9)]})]
        result, ask = self.review(batches, pages=8)
        self.assertEqual(ask.call_count, 2)
        self.assertEqual(result["batches"], 2)

    def test_invalid_answers_get_one_retry_then_record_invalid(self):
        result, ask = self.review(["not json", json.dumps({"pages": [{"page": 9, "verdict": "pass"}]})])
        self.assertEqual(ask.call_count, 2)
        self.assertEqual(result["status"], "invalid")
        self.assertEqual(result["verdict"], "degraded")

    def test_unavailable_model_is_degraded_not_fatal(self):
        result, _ = self.review(print_auto.ClassifierUnavailable("utility-model is not installed"))
        self.assertEqual(result["status"], "unavailable")
        self.assertEqual(result["verdict"], "degraded")

    def test_missing_rasterizer_is_degraded(self):
        result, ask = self.review([], which=None)
        self.assertEqual(result["status"], "unavailable")
        ask.assert_not_called()

    def test_failed_pages_are_concerns(self):
        answer = json.dumps({"pages": [{"page": 1, "verdict": "pass"},
                                       {"page": 2, "verdict": "fail", "issues": ["heading only"]},
                                       {"page": 3, "verdict": "pass"}]})
        result, _ = self.review([answer])
        self.assertEqual(result["verdict"], "concerns")
        self.assertEqual(result["failed_pages"], [2])

    def test_digest_carries_the_whole_outline_not_just_the_opening(self):
        text = "# Top\n\n" + "filler\n" * 100 + "## Late section\n\n| a | b |\n|---|---|\n| 1 | 2 |\n"
        digest = print_auto.doc_digest(text, None)
        self.assertIn("## Late section", digest)
        self.assertIn("Tables: 1, body rows [1]", digest)


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
