from __future__ import annotations

import io
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest import mock

from call_diarize.cli import _prepare_raw_root, execute, parser
from call_diarize.pipeline import Window, load_json, write_json_exclusive


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

    def test_rerun_resumes_partial_evidence_with_matching_config(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            call_dir = Path(temporary)
            raw_root = call_dir / "asr-raw"
            expected = {"schema": 1, "source": "same recording"}
            write_json_exclusive(raw_root / "run-config.json", expected)
            chunk = raw_root / "near/60s/000000000000.json"
            write_json_exclusive(chunk, {"result": "expensive GPU checkpoint"})

            with redirect_stdout(io.StringIO()) as stdout:
                prepared = _prepare_raw_root(call_dir, expected)

            self.assertEqual(prepared, raw_root)
            self.assertIn("resuming compatible partial evidence", stdout.getvalue())
            self.assertEqual(load_json(chunk), {"result": "expensive GPU checkpoint"})
            self.assertEqual(list(call_dir.glob("asr-raw.stale-*")), [])

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


class CleanupFallbackTests(unittest.TestCase):
    def test_exhausted_cleanup_shard_publishes_marked_raw_transcript(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            call_dir = Path(temporary) / "call"
            call_dir.mkdir()
            for name in ("near.wav", "far.wav", "mix.wav"):
                (call_dir / name).write_bytes(b"test recording placeholder")

            asr_window = Window("near", 0.0, 60, 1.0, call_dir / "near.wav")
            raw_row = {
                "source_id": "near-000000000000-60-s000",
                "track": "near",
                "speaker": "Thomas",
                "start": 0.0,
                "end": 1.0,
                "text": "Unedited raw ASR sentence.",
                "kind": "speech",
                "source_raw": "near/60s/000000000000.json",
            }
            runtime = {
                "device_name": "test GPU",
                "generation_seconds": 1.0,
                "audio_seconds": 1.0,
            }

            def record_asr_leaf(
                initial,
                _levels,
                _source,
                _temp_root,
                _engine,
                _hotwords,
                _raw_root,
                _activity,
                selected,
                _unavailable,
                _rejections,
                runtime_records,
            ):
                selected.append((initial, {"segments": []}, initial.key))
                runtime_records.append(runtime)

            activity_context = mock.MagicMock()
            activity_context.__enter__.return_value = mock.MagicMock()
            activity_context.__exit__.return_value = False
            gpu = {
                "device_name": "test GPU",
                "torch_version": "test Torch",
                "rocm_version": "test ROCm",
            }
            args = parser().parse_args([str(call_dir)])

            with (
                mock.patch(
                    "call_diarize.cli.validate_capture_files",
                    return_value={"near": 1.0, "far": 1.0, "mix": 1.0},
                ),
                mock.patch(
                    "call_diarize.cli._state_root", return_value=call_dir / "state"
                ),
                mock.patch(
                    "call_diarize.cli._support_dir",
                    return_value=call_dir / "support",
                ),
                mock.patch(
                    "call_diarize.cli.ensure_model_layout",
                    return_value=call_dir / "model",
                ),
                mock.patch(
                    "call_diarize.cli.preflight_models",
                    return_value=["gemma4-26b-a4b-it", "qwen3.6-35b-a3b"],
                ),
                mock.patch("call_diarize.cli.gpu_probe", return_value=gpu),
                mock.patch(
                    "call_diarize.cli.segment_track",
                    side_effect=[[asr_window], [], []],
                ),
                mock.patch(
                    "call_diarize.cli.AudioActivity",
                    return_value=activity_context,
                ),
                mock.patch("call_diarize.cli.VibeVoiceASR"),
                mock.patch(
                    "call_diarize.cli._process_tree",
                    side_effect=record_asr_leaf,
                ),
                mock.patch(
                    "call_diarize.cli._rows_from_selected",
                    side_effect=[[raw_row], []],
                ),
                mock.patch(
                    "call_diarize.cleanup._http_json",
                    side_effect=ValueError("forced invalid cleanup response"),
                ) as cleanup_request,
                redirect_stdout(io.StringIO()),
            ):
                status = execute(args)

            self.assertEqual(status, 0)
            self.assertEqual(cleanup_request.call_count, 6)
            transcript = (call_dir / "transcript.md").read_text(encoding="utf-8")
            self.assertIn("Unedited raw ASR sentence.", transcript)
            self.assertIn("<!-- cleanup-failed shard-000 -->", transcript)
            self.assertIn("(raw; cleanup-failed shard-000)", transcript)

            manifest = load_json(call_dir / "asr-raw/manifest.json")
            self.assertEqual(manifest["cleanup_failure_count"], 2)
            self.assertEqual(manifest["raw_fallback_shard_count"], 1)
            self.assertEqual(manifest["raw_fallback_candidate_count"], 1)
            self.assertTrue(
                all(failure["nonfatal"] for failure in manifest["cleanup_failures"])
            )
            for label in ("gemma", "qwen"):
                report = load_json(
                    call_dir
                    / f"asr-raw/cleanup/{label}/shard-000.failed.json"
                )
                self.assertEqual(report["fallback"], "raw-asr")
                self.assertEqual(report["attempt_count"], 3)

            review = (call_dir / "review-queue.md").read_text(encoding="utf-8")
            self.assertIn("Raw-ASR fallback shards: 1", review)


if __name__ == "__main__":
    unittest.main()
