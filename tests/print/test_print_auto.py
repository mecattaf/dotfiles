from __future__ import annotations

import importlib.util
import json
import os
import sys
import tempfile
import unittest
from contextlib import contextmanager
from datetime import datetime
from pathlib import Path


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


@contextmanager
def working_directory(path: Path):
    previous = Path.cwd()
    os.chdir(path)
    try:
        yield
    finally:
        os.chdir(previous)


class QuietHoursSpoolTests(unittest.TestCase):
    def test_relative_scratch_job_is_recorded_with_absolute_paths(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            with working_directory(root):
                jobdir = Path("print2")
                jobdir.mkdir()
                pdf = jobdir / "ruling-sheet.pdf"
                pdf.write_bytes(b"%PDF fixture\n")

                manifest = print_auto.spool_print(
                    pdf,
                    jobdir,
                    "long-edge",
                    outbox=Path("outbox"),
                    now=datetime(2026, 9, 6, 1, 19, 32),
                )
                resolved_pdf = pdf.resolve()
                resolved_jobdir = jobdir.resolve()

            row = json.loads(manifest.read_text())
            self.assertTrue(Path(row["pdf"]).is_absolute())
            self.assertTrue(Path(row["job_dir"]).is_absolute())
            self.assertEqual(Path(row["pdf"]), resolved_pdf)
            self.assertEqual(Path(row["job_dir"]), resolved_jobdir)
            self.assertEqual(row["sides"], "two-sided-long-edge")
            self.assertEqual(row["queued_at"], "2026-09-06T01:19:32")

    def test_one_sided_spelling_matches_cups(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            jobdir = root / "job"
            jobdir.mkdir()
            pdf = jobdir / "form.pdf"
            pdf.write_bytes(b"%PDF fixture\n")

            manifest = print_auto.spool_print(
                pdf, jobdir, "one-sided", outbox=root / "outbox"
            )

            self.assertEqual(
                json.loads(manifest.read_text())["sides"], "one-sided"
            )


if __name__ == "__main__":
    unittest.main()
