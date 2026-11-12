"""Real PDF qualification: no model, browser, CUPS or network access needed."""
from pathlib import Path
import importlib.util
import json
import os
import re
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(os.environ["PRINT_PAPER_SCRIPT"])
SPEC = importlib.util.spec_from_file_location("print_paper", SCRIPT)
print_paper = importlib.util.module_from_spec(SPEC)
sys.modules["print_paper"] = print_paper
SPEC.loader.exec_module(print_paper)


def long_table_report(rows: int = 70) -> str:
    """Synthetic shape of the 1 and 3 November prints (#673): prose, then a
    section heading followed by a table longer than a page."""
    intro = "\n\n".join(
        f"INTRO_{i:02d}: " + "The report opens with ordinary prose that fills the page. " * 7
        for i in range(5))
    table = ["| Step | Owner | Outcome |", "|---|---|---|"]
    table += [f"| ROW_{i:03d} | Owner {i % 7} | " + "Measured result recorded for review. " * 2 + "|"
              for i in range(rows)]
    return ("# Long table read-up\n\n" + intro + "\n\n## Ledger of measured steps\n\n"
            + "\n".join(table) + "\n\nCLOSING_PARAGRAPH ends the document.\n")
SOURCE = """# Local print qualification

Café, naïve and Ω retain their text. **Bold** and *italic* stay readable.

1. FIRST_ITEM wraps across a line
   without restarting the ordered list.
2. SECOND_ITEM contains a nested list:
   - NESTED_ITEM

| Item | Outcome |
|---|---|
| TABLE_ITEM | Preserved |

```text
CODE_ITEM: literal source, not a command.
```

SOURCE_LAST_TOKEN
"""


class RealRendererTests(unittest.TestCase):
    def render(self, root, text, profile="source-serif", *, suffix=".md", layout="standard"):
        source = root / f"source{suffix}"
        source.write_text(text)
        pdf = root / f"{profile}.pdf"
        subprocess.run([sys.executable, str(SCRIPT), str(source), "--profile", profile,
                        "--output", str(pdf), "--force", "--layout", layout,
                        "--measure", str(root / "measure.json")],
                       check=True, capture_output=True)
        self.assertEqual(source.read_text(), text)
        self.measure = json.loads((root / "measure.json").read_text())
        facts = subprocess.check_output(["pdfinfo", str(pdf)], text=True)
        self.assertRegex(facts, r"Page size:\s+595\.\d+ x 841\.\d+ pts \(A4\)")
        body = subprocess.check_output(["pdftotext", "-layout", str(pdf), "-"], text=True)
        return facts, body

    def test_all_profiles_preserve_content_in_a_real_one_page_pdf(self):
        with tempfile.TemporaryDirectory() as directory:
            for profile in ("garamond", "baskerville", "source-serif", "times"):
                with self.subTest(profile=profile):
                    facts, body = self.render(Path(directory), SOURCE, profile)
                    self.assertRegex(facts, r"Pages:\s+1\b")
                    for token in ("Café", "naïve", "Ω", "FIRST_ITEM", "SECOND_ITEM",
                                  "NESTED_ITEM", "TABLE_ITEM", "CODE_ITEM", "SOURCE_LAST_TOKEN"):
                        self.assertIn(token, body)

    def test_multiple_pages_keep_every_paragraph_and_their_page_numbers(self):
        paragraphs = [f"PARAGRAPH_{i:03d}: " + "Printable source stays complete. " * 12
                      for i in range(45)]
        text = "# Long print qualification\n\n" + "\n\n".join(paragraphs)
        with tempfile.TemporaryDirectory() as directory:
            facts, body = self.render(Path(directory), text)
        count = int(re.search(r"Pages:\s+(\d+)", facts)[1])
        self.assertGreater(count, 1)
        pages = body.split("\f")[:count]
        for number, page in enumerate(pages, 1):
            self.assertEqual(page.strip().splitlines()[-1].strip(), str(number))
        for i in range(45):
            self.assertIn(f"PARAGRAPH_{i:03d}", body)

        self.assertEqual(self.hard(), [])

    def hard(self):
        return [d["kind"] for d in self.measure["defects"] if d["severity"] == "hard"]

    def pages(self, body):
        return body.split("\f")[: self.measure["pages"]]

    def test_long_table_flows_with_repeated_headers_and_no_stranded_heading(self):
        with tempfile.TemporaryDirectory() as directory:
            _, body = self.render(Path(directory), long_table_report())
        self.assertEqual(self.hard(), [], self.measure["defects"])
        pages = self.pages(body)
        spanned = [page for page in pages if re.search(r"ROW_\d{3}", page)]
        self.assertGreater(len(spanned), 1)
        for page in spanned:
            self.assertIn("Outcome", page)  # the column header repeats
        heading_page = next(i for i, page in enumerate(pages) if "Ledger of measured" in page)
        self.assertIn("ROW_000", pages[heading_page])  # heading kept with its rows
        for i in range(70):
            self.assertIn(f"ROW_{i:03d}", body)

    def test_old_whole_table_rule_is_caught_as_a_heading_only_page(self):
        # The pre-#673 CSS, reproduced by an inline style that beats the sheet.
        html, _ = print_paper.markdown_to_html(long_table_report())
        html = html.replace("<table>", '<table style="break-inside: avoid-page">')
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source.html"
            source.write_text(html)
            subprocess.run([sys.executable, str(SCRIPT), str(source), "--output",
                            str(root / "old.pdf"), "--measure", str(root / "m.json")],
                           check=True, capture_output=True)
            measure = json.loads((root / "m.json").read_text())
        kinds = {d["kind"] for d in measure["defects"] if d["severity"] == "hard"}
        self.assertTrue(kinds & {"heading_only_page", "near_empty_page"}, measure["defects"])

    def test_row_taller_than_a_page_breaks_without_clipping(self):
        tall = " ".join(f"TALL_{i:03d} words continue in one cell." for i in range(260))
        text = ("# Oversized row\n\n| Key | Value |\n|---|---|\n| first | short |\n"
                f"| huge | {tall} |\n| last | LAST_ROW |\n")
        with tempfile.TemporaryDirectory() as directory:
            _, body = self.render(Path(directory), text)
        self.assertGreater(self.measure["pages"], 1)
        for i in range(260):
            self.assertIn(f"TALL_{i:03d}", body)
        self.assertIn("LAST_ROW", body)
        self.assertNotIn("overflow", self.hard())

    def test_snug_layout_keeps_type_size_and_saves_pages(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            facts, _ = self.render(root, long_table_report(120))
            standard = self.measure
            self.render(root, long_table_report(120), layout="snug")
            snug = self.measure
        self.assertEqual(snug["type"], standard["type"])
        self.assertLessEqual(snug["pages"], standard["pages"])
        self.assertEqual([d for d in snug["defects"] if d["severity"] == "hard"], [])

    def test_two_line_tail_is_soft_and_a_one_page_sparse_form_is_valid(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.render(root, "# Form\n\nName: ______\n\nDate: ______\n")
            self.assertEqual(self.measure["defects"], [])
            paragraphs = [f"BODY_{i:03d} is one short line." for i in range(120)]
            for count in range(20, 120):
                text = "# Tail\n\n" + "\n\n".join(paragraphs[:count])
                self.render(root, text)
                facts = self.measure["page_facts"]
                if len(facts) == 2 and facts[-1]["lines"] <= 3:
                    break
            else:
                self.fail("no source length produced a short tail page")
        self.assertIn("short_tail", [d["kind"] for d in self.measure["defects"]])
        self.assertEqual(self.hard(), [])


    def test_print_auto_selects_a_clean_candidate_and_records_the_evidence(self):
        scripts = os.environ.get("PRINT_SCRIPTS_DIR")
        if not scripts:
            self.skipTest("PRINT_SCRIPTS_DIR is not set")
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "read-up.md"
            text = long_table_report(90)
            source.write_text(text)
            job = root / "job"
            # No utility-model here: classification falls back, the page
            # review is recorded as unavailable and the gate still decides.
            env = {**os.environ, "PATH": os.environ["PATH"]}
            result = subprocess.run([sys.executable, str(Path(scripts) / "print-auto.py"),
                                     str(source), "--output-dir", str(job),
                                     "--target-pages", "4"], capture_output=True, text=True, env=env)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            decision = json.loads((job / "decision.json").read_text())
            self.assertEqual(source.read_text(), text)
            self.assertEqual(decision["quality_check"], "pass")
            self.assertEqual(decision["quality"]["defects"], [])
            self.assertIn(decision["page_review"]["status"], ("unavailable", "invalid"))
            self.assertTrue(decision["candidates"])
            pdf = job / decision["decision"]["filename"]
            body = subprocess.check_output(["pdftotext", str(pdf), "-"], text=True)
            for i in range(90):
                self.assertIn(f"ROW_{i:03d}", body)


if __name__ == "__main__":
    unittest.main()
