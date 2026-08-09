from __future__ import annotations

import io
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

from call_diarize.cli import _prepare_raw_root, execute, parser
from call_diarize.pipeline import load_json, write_json_exclusive


class EvidenceRerunTests(unittest.TestCase):
    attempt_relative = Path("cleanup/gemma/shard-005.attempt-01.json")

    def test_rerun_quarantines_partial_evidence_and_can_rewrite_attempt(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            call_dir = Path(temporary)
            interrupted_attempt = call_dir / "asr-raw" / self.attempt_relative
            write_json_exclusive(interrupted_attempt, {"error": "interrupted"})

            with redirect_stdout(io.StringIO()):
                raw_root = _prepare_raw_root(call_dir)

            quarantines = list(call_dir.glob("asr-raw.stale-*"))
            self.assertEqual(len(quarantines), 1)
            self.assertEqual(
                load_json(quarantines[0] / self.attempt_relative),
                {"error": "interrupted"},
            )

            rerun_attempt = raw_root / self.attempt_relative
            write_json_exclusive(rerun_attempt, {"result": "fresh rerun"})
            self.assertEqual(load_json(rerun_attempt), {"result": "fresh rerun"})

    def test_completed_transcript_leaves_evidence_protected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            call_dir = Path(temporary)
            transcript = call_dir / "transcript.md"
            transcript.write_text("# Completed transcript\n", encoding="utf-8")
            attempt = call_dir / "asr-raw" / self.attempt_relative
            write_json_exclusive(attempt, {"result": "completed run"})

            args = parser().parse_args([str(call_dir)])
            with redirect_stdout(io.StringIO()):
                status = execute(args)
                protected_raw_root = _prepare_raw_root(call_dir)

            self.assertEqual(status, 0)
            self.assertEqual(protected_raw_root, call_dir / "asr-raw")
            self.assertEqual(load_json(attempt), {"result": "completed run"})
            self.assertEqual(list(call_dir.glob("asr-raw.stale-*")), [])
            with self.assertRaisesRegex(
                RuntimeError, "refusing to overwrite existing evidence"
            ):
                write_json_exclusive(attempt, {"result": "clobbered"})


if __name__ == "__main__":
    unittest.main()
