from __future__ import annotations

import contextlib
import importlib.util
import io
import os
import re
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
README = Path(
    os.environ.get(
        "PRINT_SCRIPTS_README",
        REPO_ROOT / "home/dot_claude/skills/print/scripts/README.md",
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
    def test_underscores_inside_identifiers_are_literal(self) -> None:
        body = self.render("SOURCE_LAST_TOKEN foo__bar__baz _italic_ __bold__\n")
        self.assertIn("SOURCE_LAST_TOKEN", body)
        self.assertIn("foo__bar__baz", body)
        self.assertIn("<em>italic</em>", body)
        self.assertIn("<strong>bold</strong>", body)

    def render(self, source: str) -> str:
        body, _ = print_paper.markdown_to_html(source)
        return body

    def test_local_image_examples_in_code_do_not_require_assets(self) -> None:
        source = "Inline `![example](../private/example.png)`.\n\n```markdown\n![example](../private/example.png)\n```\n"
        self.assertEqual(print_paper.external_image_sources(self.render(source)), [])

    def test_local_and_network_images_require_assets_but_embedded_images_do_not(self) -> None:
        source = "![local](../private/photo.png)\n\n![remote](https://example.com/photo.png)\n\n![embedded](data:image/png;base64,abcd)\n"
        self.assertEqual(print_paper.external_image_sources(self.render(source)),
                         ["../private/photo.png", "https://example.com/photo.png"])

    def test_asset_preflight_needs_no_browser_or_printer(self) -> None:
        with (mock.patch.object(sys, "argv", ["print-paper.py", "-", "--check-assets"]),
              mock.patch.object(sys, "stdin", io.StringIO("`![example](local.png)`\n")),
              mock.patch.object(print_paper, "find_renderer") as renderer,
              mock.patch.object(print_paper, "submit_print") as submit):
            print_paper.main()
            renderer.assert_not_called()
            submit.assert_not_called()

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


class LayoutGateTests(unittest.TestCase):
    """#673: deterministic page checks over synthetic PDF text geometry."""

    W, H = 595.28, 841.89
    GEO = print_paper.LAYOUTS["standard"]
    LEFT = GEO.side_mm * print_paper.MM
    TOP = GEO.top_mm * print_paper.MM

    def line(self, text, y, x=None, width=300.0, height=12.0):
        x = self.LEFT if x is None else x
        return print_paper.TextLine(x, y, x + width, y + height, text.split())

    def page(self, *lines, folio=None):
        lines = list(lines)
        if folio is not None:
            lines.append(self.line(str(folio), self.H - 30, x=self.W - 60, width=5))
        return print_paper.PageText(self.W, self.H, lines)

    def body_lines(self, prefix, count, start=None):
        start = self.TOP if start is None else start
        return [self.line(f"{prefix} line {i} words", start + i * 15) for i in range(count)]

    def assess(self, pages, body):
        facts = print_paper.source_facts(body)
        return print_paper.assess_layout(pages, facts, self.GEO, body_pt=11.25, table_pt=10.125)

    def kinds(self, report, severity="hard"):
        return [d["kind"] for d in report["defects"] if d["severity"] == severity]

    def body_for(self, pages):
        html = []
        for page in pages:
            for line in page.lines:
                if line.text.isdigit():
                    continue
                if line.text.startswith("Section"):
                    html.append(f"<h2>{line.text}</h2>")
                else:
                    html.append(f"<p>{line.text}</p>")
        return "\n".join(html)

    def test_clean_multipage_document_has_no_defects(self):
        pages = [self.page(*self.body_lines("alpha", 45), folio=1),
                 self.page(*self.body_lines("beta", 30), folio=2)]
        report = self.assess(pages, self.body_for(pages))
        self.assertEqual(report["defects"], [])
        self.assertEqual(report["page_facts"][0]["lines"], 45)  # folio excluded

    def test_heading_only_page_is_hard(self):
        pages = [self.page(*self.body_lines("alpha", 45), folio=1),
                 self.page(self.line("Section Ledger", self.TOP), folio=2),
                 self.page(*self.body_lines("beta", 40), folio=3)]
        report = self.assess(pages, self.body_for(pages))
        self.assertIn("heading_only_page", self.kinds(report))
        self.assertEqual(report["defects"][0]["page"], 2)

    def test_heading_at_the_foot_of_a_page_is_hard(self):
        lines = self.body_lines("alpha", 44) + [self.line("Section Next", self.TOP + 44 * 15)]
        pages = [self.page(*lines, folio=1), self.page(*self.body_lines("beta", 30), folio=2)]
        self.assertIn("heading_at_page_foot", self.kinds(self.assess(pages, self.body_for(pages))))

    def test_near_empty_page_before_a_break_is_hard(self):
        pages = [self.page(*self.body_lines("alpha", 3), folio=1),
                 self.page(*self.body_lines("beta", 45), folio=2)]
        self.assertIn("near_empty_page", self.kinds(self.assess(pages, self.body_for(pages))))

    def test_short_final_page_is_soft_and_one_page_sparse_form_is_valid(self):
        pages = [self.page(*self.body_lines("alpha", 45), folio=1),
                 self.page(*self.body_lines("tail", 2), folio=2)]
        report = self.assess(pages, self.body_for(pages))
        self.assertEqual(self.kinds(report), [])
        self.assertEqual(self.kinds(report, "soft"), ["short_tail"])
        form = [self.page(self.line("Section Form", self.TOP),
                          self.line("Name ____", self.TOP + 300), folio=1)]
        self.assertEqual(self.assess(form, self.body_for(form))["defects"], [])

    def test_ordinary_partly_filled_final_page_is_valid(self):
        pages = [self.page(*self.body_lines("alpha", 45), folio=1),
                 self.page(*self.body_lines("beta", 12), folio=2)]
        self.assertEqual(self.assess(pages, self.body_for(pages))["defects"], [])

    def test_clipped_and_overlapping_text_is_hard(self):
        clipped = [self.page(self.line("wide words", self.TOP, width=self.W))]
        self.assertIn("overflow", self.kinds(self.assess(clipped, "<p>wide words</p>")))
        overlap = [self.page(self.line("first words", self.TOP), self.line("second words", self.TOP + 2))]
        self.assertIn("overlap", self.kinds(
            self.assess(overlap, "<p>first words</p><p>second words</p>")))

    def test_lost_source_text_is_hard(self):
        pages = [self.page(*self.body_lines("alpha", 5), folio=1)]
        body = self.body_for(pages) + "<table><tr><td>DROPPED_ROW_TOKEN</td></tr></table>"
        self.assertIn("content_missing", self.kinds(self.assess(pages, body)))

    def test_hyphenated_and_cell_broken_words_still_count_as_present(self):
        pages = [self.page(self.line("pagi-", self.TOP, width=40),
                           self.line("other cell", self.TOP, x=self.LEFT + 200, width=60),
                           self.line("nation", self.TOP + 15, width=40), folio=1)]
        report = self.assess(pages, "<table><tr><td>pagination</td><td>other cell</td></tr></table>")
        self.assertEqual(self.kinds(report), [])

    def test_reading_order_is_checked(self):
        pages = [self.page(self.line("second paragraph", self.TOP),
                           self.line("first paragraph", self.TOP + 15))]
        report = self.assess(pages, "<p>first paragraph</p><p>second paragraph</p>")
        self.assertIn("reading_order", self.kinds(report))

    def test_repeated_table_headers_are_not_lost_content(self):
        pages = [self.page(self.line("Step Outcome", self.TOP), *self.body_lines("row", 40, self.TOP + 15), folio=1),
                 self.page(self.line("Step Outcome", self.TOP), self.line("row tail words", self.TOP + 15), folio=2)]
        body = ("<table><thead><tr><th>Step</th><th>Outcome</th></tr></thead><tbody>"
                + "".join(f"<tr><td>row line {i} words</td></tr>" for i in range(40))
                + "<tr><td>row tail words</td></tr></tbody></table>")
        report = self.assess(pages, body)
        self.assertEqual(self.kinds(report), [])

    def test_giant_tables_are_advised_against_but_printed_as_submitted(self):
        rows = "".join(f"<tr><td>r{i}</td></tr>" for i in range(40))
        report = self.assess([self.page(self.line("r0", self.TOP))], f"<table>{rows}</table>")
        self.assertEqual(report["advisories"][0]["kind"], "giant_table")

    def test_type_floor_is_enforced_for_body_and_tables(self):
        for layout in print_paper.LAYOUTS:
            for profile in print_paper.PROFILES.values():
                fitted = print_paper.fitted_profile(profile, layout)
                self.assertGreaterEqual(fitted.size_pt, print_paper.BODY_FLOOR_PT)
                css = print_paper.print_css(fitted, layout=layout)
                table_pt = float(re.search(r"table \{\{?[^}]*font-size: ([0-9.]+)pt", css)[1])
                self.assertGreaterEqual(table_pt, print_paper.TABLE_FLOOR_PT)
        report = print_paper.assess_layout([], print_paper.SourceFacts(), self.GEO,
                                           body_pt=9.0, table_pt=8.0)
        self.assertIn("unreadable_type", self.kinds(report))

    def test_snug_keeps_the_profile_type_size(self):
        for profile in print_paper.PROFILES.values():
            self.assertEqual(print_paper.fitted_profile(profile, "snug").size_pt, profile.size_pt)

    def test_tables_flow_with_repeated_headers_and_unhyphenated_column_labels(self):
        css = print_paper.print_css(print_paper.PROFILES["source-serif"])
        table = css[css.index("\ntable {"):css.index("th, td")]
        self.assertNotIn("avoid-page", table)
        self.assertIn("display: table-header-group", css)
        self.assertIn("tr { break-inside: avoid; }", css)
        self.assertIn("hyphens: manual", css[css.index("\nth {"):])

    def test_bbox_xhtml_is_parsed(self):
        xhtml = ('<html xmlns="http://www.w3.org/1999/xhtml"><body><doc>'
                 '<page width="595.28" height="841.89"><flow><block>'
                 '<line xMin="85" yMin="57" xMax="200" yMax="70">'
                 '<word xMin="85" yMin="57" xMax="120" yMax="70">Caf&#233;</word>'
                 '<word xMin="125" yMin="57" xMax="200" yMax="70">text</word></line>'
                 '</block></flow></page></doc></body></html>')
        pages = print_paper.parse_bbox(xhtml)
        self.assertEqual(len(pages), 1)
        self.assertEqual(pages[0].lines[0].text, "Café text")
        self.assertEqual(pages[0].lines[0].x_min, 85.0)


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
    """/print is one file write (#384). The skill says where to drop and
    where outcomes appear; rendering and submission are the daemon's."""

    def test_skill_is_the_drop_contract_only(self) -> None:
        text = SKILL.read_text(encoding="utf-8")
        self.assertIn("utility-path paper", text)
        self.assertIn("${paper_root}/intake/", text)
        self.assertIn("target_pages", text)
        self.assertIn("receipt.json", text)
        for agent_side_cups in ("--print", "--submit-only", "print-auto.py ", "lp -d", "lpstat"):
            self.assertNotIn(agent_side_cups, text)
        # inbox/ is the Huion's (DECISIONS 2026-09-13), never a print drop:
        # it may be named only as the thing this skill is not.
        self.assertNotIn("${paper_root}/inbox/.<slug>", text)
        self.assertNotIn("${paper_root}/inbox/<slug>", text)
        self.assertIn("`${paper_root}/inbox/` is the Huion notepad's, not a print drop", text)

    def test_manual_renderer_documents_the_duplex_default(self) -> None:
        text = README.read_text(encoding="utf-8")
        self.assertIn("long-edge", text)
        self.assertNotIn("Default to one-sided output", text)


if __name__ == "__main__":
    unittest.main()
