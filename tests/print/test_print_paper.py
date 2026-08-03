from __future__ import annotations

import contextlib
import importlib.util
import io
import os
import sys
import unittest
from pathlib import Path
from unittest import mock


REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = Path(
    os.environ.get(
        "PRINT_PAPER_SCRIPT",
        REPO_ROOT / "home/dot_claude/skills/print/scripts/print-paper.py",
    )
)
SCRIPT_SPEC = importlib.util.spec_from_file_location("print_paper", SCRIPT)
if SCRIPT_SPEC is None or SCRIPT_SPEC.loader is None:
    raise RuntimeError(f"could not load print-paper from {SCRIPT}")
print_paper = importlib.util.module_from_spec(SCRIPT_SPEC)
sys.modules["print_paper"] = print_paper
SCRIPT_SPEC.loader.exec_module(print_paper)

SKILL = Path(
    os.environ.get(
        "PRINT_PAPER_SKILL",
        REPO_ROOT / "home/dot_claude/skills/print/SKILL.md",
    )
)

# The house 80-column style hard-wraps list items. GitHub keeps each wrap in
# its own item; so must the print pipeline (issue #137).
WRAPPED_LISTS = """\
# Wrapped fixture

1. The first ordered item runs past the eightieth column and therefore
   continues on a hard-wrapped line that belongs to the same item.
2. The second ordered item also wraps, which used to close the list and
   restart the numbering at one on the following marker.
3. The third ordered item stays plain.

- The first bullet wraps onto a continuation line that must not become a
  sibling paragraph.
- The second bullet is lazily continued by a line that carries no
indentation at all, which CommonMark still folds into this item.
"""


class ListParsingTests(unittest.TestCase):
    def render(self, source: str) -> str:
        body, _ = print_paper.markdown_to_html(source)
        return body

    def test_wrapped_ordered_list_keeps_one_item_per_marker(self) -> None:
        body = self.render(WRAPPED_LISTS)
        self.assertEqual(body.count("<ol>"), 1)
        self.assertEqual(body.count("<ul>"), 1)
        self.assertEqual(body.count("<li>"), 5)
        self.assertNotIn("<ol start=", body)
        self.assertIn(
            "<li>The first ordered item runs past the eightieth column and therefore "
            "continues on a hard-wrapped line that belongs to the same item.</li>",
            body,
        )
        self.assertIn(
            "<li>The second bullet is lazily continued by a line that carries no "
            "indentation at all, which CommonMark still folds into this item.</li>",
            body,
        )

    def test_continuations_do_not_become_paragraphs(self) -> None:
        body = self.render(WRAPPED_LISTS)
        self.assertNotIn("<p>continues on a hard-wrapped line", body)
        self.assertNotIn("<p>sibling paragraph.</p>", body)

    def test_ordered_list_numbering_is_not_restarted(self) -> None:
        # One <ol> with three items is what makes Chrome print 1, 2, 3.
        body = self.render(WRAPPED_LISTS)
        ordered = body[body.index("<ol>") : body.index("</ol>")]
        self.assertEqual(ordered.count("<li>"), 3)

    def test_explicit_start_is_preserved(self) -> None:
        body = self.render("4. fourth\n5. fifth\n")
        self.assertIn('<ol start="4">', body)

    def test_nested_list_stays_inside_its_parent_item(self) -> None:
        body = self.render(
            "- parent item that wraps\n"
            "  onto a second line\n"
            "  - child item\n"
            "- second parent\n"
        )
        self.assertEqual(body.count("<ul>"), 2)
        self.assertIn("<li>parent item that wraps onto a second line\n<ul>", body)
        self.assertIn("<li>child item</li>", body)

    def test_loose_list_items_keep_paragraphs(self) -> None:
        body = self.render("- first item\n\n- second item\n")
        self.assertEqual(body.count("<ul>"), 1)
        self.assertIn("<li><p>first item</p></li>", body)

    def test_marker_change_starts_a_new_list(self) -> None:
        body = self.render("- dash item\n* star item\n")
        self.assertEqual(body.count("<ul>"), 2)

    def test_thematic_break_is_not_a_list_item(self) -> None:
        body = self.render("text\n\n---\n\nmore text\n")
        self.assertIn("<hr>", body)
        self.assertNotIn("<li>", body)

    def test_paragraph_wrapping_is_unchanged(self) -> None:
        body = self.render("a paragraph that is\nhard wrapped\n")
        self.assertIn("<p>a paragraph that is hard wrapped</p>", body)

    def test_heading_still_yields_the_title(self) -> None:
        _, title = print_paper.markdown_to_html(WRAPPED_LISTS)
        self.assertEqual(title, "Wrapped fixture")


class PageNumberCssTests(unittest.TestCase):
    def css(self, *, label: bool = False) -> str:
        return print_paper.print_css(print_paper.PROFILES["source-serif"], label=label)

    def test_margin_box_emits_the_page_counter(self) -> None:
        css = self.css()
        self.assertIn("@bottom-right", css)
        self.assertIn("content: counter(page);", css)
        self.assertIn("font-size: 7pt;", css)

    def test_page_geometry_is_unchanged(self) -> None:
        self.assertIn("margin: 20mm 30mm 21mm;", self.css())

    def test_folio_is_present_without_the_label(self) -> None:
        css = self.css()
        self.assertNotIn("@bottom-center", css)
        self.assertIn("@bottom-right", css)

    def test_profile_label_occupies_a_separate_margin_box(self) -> None:
        css = self.css(label=True)
        self.assertIn("@bottom-center", css)
        self.assertIn('content: "Source Serif 4 · 11.25 pt · 1.42 line height";', css)
        # The caption is furniture, not flowed content: it can no longer
        # overprint the last line of the page.
        self.assertNotIn("print-profile-label", css)

    def test_label_reaches_html_and_markdown_documents_alike(self) -> None:
        profile = print_paper.PROFILES["source-serif"]
        rendered = print_paper.document_html(
            "<p>x</p>", title="t", base_uri="file:///tmp/", profile=profile, label=True
        )
        wrapped = print_paper.html_input_document(
            "<html><head></head><body><p>x</p></body></html>",
            title="t",
            base_uri="file:///tmp/",
            profile=profile,
            label=True,
        )
        for page in (rendered, wrapped):
            self.assertIn("@bottom-center", page)
            self.assertIn("content: counter(page);", page)
            self.assertNotIn("<footer", page)


class CupsCommandTests(unittest.TestCase):
    def submit(self, sides: str) -> list[str]:
        commands: list[list[str]] = []

        def fake_run(command, *, check=True):
            commands.append(command)
            return mock.Mock(returncode=0, stdout="request id is test-1 (1 file(s))", stderr="")

        with (
            mock.patch.object(print_paper.shutil, "which", side_effect=lambda name: f"/usr/bin/{name}"),
            mock.patch.object(print_paper, "run", side_effect=fake_run),
            contextlib.redirect_stdout(io.StringIO()),
        ):
            print_paper.submit_print(
                Path("/tmp/example.pdf"), printer="Brother_HL_L2445DW", copies=1, sides=sides
            )
        return commands[-1]

    def test_default_sides_is_duplex_long_edge(self) -> None:
        with mock.patch.object(sys, "argv", ["print-paper.py", "input.md"]):
            args = print_paper.parse_args()
        self.assertEqual(args.sides, "long-edge")
        self.assertIn("sides=two-sided-long-edge", self.submit(args.sides))

    def test_one_sided_override_still_works(self) -> None:
        with mock.patch.object(sys, "argv", ["print-paper.py", "input.md", "--sides", "one-sided"]):
            args = print_paper.parse_args()
        self.assertEqual(args.sides, "one-sided")
        self.assertIn("sides=one-sided", self.submit(args.sides))

    def test_short_edge_override_still_works(self) -> None:
        self.assertIn("sides=two-sided-short-edge", self.submit("short-edge"))

    def test_media_stays_a4(self) -> None:
        self.assertIn("media=A4", self.submit("long-edge"))


class SkillDocumentationTests(unittest.TestCase):
    def test_skill_documents_the_duplex_default(self) -> None:
        text = SKILL.read_text(encoding="utf-8")
        self.assertIn("long-edge", text)
        self.assertNotIn("Default to one-sided output", text)


if __name__ == "__main__":
    unittest.main()
