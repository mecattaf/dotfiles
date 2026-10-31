"""Real PDF qualification: no model, browser, CUPS or network access needed."""
from pathlib import Path
import os
import re
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(os.environ["PRINT_PAPER_SCRIPT"])
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
    def render(self, root, text, profile="source-serif"):
        source = root / "source.md"
        source.write_text(text)
        pdf = root / f"{profile}.pdf"
        subprocess.run([sys.executable, str(SCRIPT), str(source), "--profile", profile,
                        "--output", str(pdf), "--force"], check=True, capture_output=True)
        self.assertEqual(source.read_text(), text)
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


if __name__ == "__main__":
    unittest.main()
