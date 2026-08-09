from __future__ import annotations

import tempfile
import unittest
import wave
from pathlib import Path
from unittest import mock

from call_diarize.asr import map_legacy_key
from call_diarize.cleanup import (
    extract_json_object,
    reduce_consensus,
    run_model_shard,
    validate_decisions,
)
from call_diarize.pipeline import (
    Window,
    candidate_shards,
    decoder_loop_reason,
    lexical_duplicate_target,
    load_json,
    normalize_asr_segments,
    segment_track,
    slice_track,
    unavailable_row,
    validate_asr_result,
)


def window(seconds: float = 30.0) -> Window:
    return Window("near", 0.0, 30, seconds, Path("unused.wav"))


def support(value: float = 0.8):
    return lambda _track, _start, _end: {"near": value, "far": 0.0, "selected": value}


def row(source_id: str, text: str, start: float, end: float) -> dict:
    return {
        "source_id": source_id,
        "track": "near",
        "speaker": "Thomas",
        "start": start,
        "end": end,
        "text": text,
        "kind": "speech",
    }


class SegmentExtractionTests(unittest.TestCase):
    def test_initial_and_retry_extraction_replace_interrupted_outputs(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "mix.wav"
            with wave.open(str(source), "wb") as handle:
                handle.setnchannels(1)
                handle.setsampwidth(2)
                handle.setframerate(48_000)
                handle.writeframes(b"\0\0" * 48_000)

            first_segments = segment_track(source, "mix", 1, root)
            stale_segment = first_segments[0].audio_path.with_name("mix-999999.wav")
            stale_segment.write_bytes(first_segments[0].audio_path.read_bytes())
            first_segments[0].audio_path.write_bytes(b"interrupted initial extraction")
            second_segments = segment_track(source, "mix", 1, root)
            self.assertEqual(
                [window.audio_path for window in second_segments],
                [window.audio_path for window in first_segments],
            )
            self.assertFalse(stale_segment.exists())
            self.assertAlmostEqual(second_segments[0].actual_seconds, 1.0)

            first_retry = slice_track(source, "mix", 0.0, 1, root)
            first_retry.audio_path.write_bytes(b"interrupted retry extraction")
            second_retry = slice_track(source, "mix", 0.0, 1, root)
            self.assertEqual(second_retry.audio_path, first_retry.audio_path)
            self.assertAlmostEqual(second_retry.actual_seconds, 1.0)


class StructuralValidationTests(unittest.TestCase):
    def test_official_checkpoint_mapping_chains_rewrites(self) -> None:
        old_key = (
            "model.acoustic_tokenizer.encoder.stages.3.0.mixer.conv.conv.conv.weight"
        )
        self.assertEqual(
            map_legacy_key(old_key),
            "acoustic_tokenizer_encoder.conv_layers.2.stage.0.mixer.conv.weight",
        )
        self.assertEqual(
            map_legacy_key(
                "model.semantic_tokenizer.encoder."
                "downsample_layers.1.0.conv.conv.weight"
            ),
            "semantic_tokenizer_encoder.conv_layers.0.conv.conv.weight",
        )

    def test_accepts_strict_supported_segments(self) -> None:
        result = {
            "segments": [
                {
                    "start_time": 0.0,
                    "end_time": 2.0,
                    "speaker_id": 7,
                    "text": "Hello there.",
                },
                {"start_time": 2.0, "end_time": 30.0, "text": "[Silence]"},
            ]
        }
        validation = validate_asr_result(result, window(), support())
        self.assertTrue(validation.accepted)
        self.assertEqual(validation.reasons, ())

    def test_normalizes_transformers_v5_segment_shape(self) -> None:
        value = [{"Start": 0.0, "End": 2.0, "Speaker": 4, "Content": "Hello."}]
        self.assertEqual(
            normalize_asr_segments(value),
            [{"start_time": 0.0, "end_time": 2.0, "speaker_id": 4, "text": "Hello."}],
        )
        validation = validate_asr_result({"segments": value}, window(), support())
        self.assertTrue(validation.accepted)

    def test_rejects_timestamp_outside_actual_tail(self) -> None:
        result = {"segments": [{"start_time": 0.0, "end_time": 6.1, "text": "Hello."}]}
        validation = validate_asr_result(result, window(6.0), support())
        self.assertFalse(validation.accepted)
        self.assertIn("violates", validation.reasons[0])

    def test_malformed_segment_is_rejected_without_activity_probe(self) -> None:
        def unexpected_support(_track: str, _start: float, _end: float) -> dict:
            raise AssertionError("structurally invalid rows have no valid activity span")

        bad_text = validate_asr_result(
            {"segments": [{"start_time": 0.0, "end_time": 1.0, "text": 7}]},
            window(),
            unexpected_support,
        )
        self.assertFalse(bad_text.accepted)
        self.assertIn("non-string text", bad_text.reasons[0])

        bad_time = validate_asr_result(
            {"segments": [{"start_time": 0.0, "end_time": 31.0, "text": "Hello."}]},
            window(),
            unexpected_support,
        )
        self.assertFalse(bad_time.accepted)
        self.assertIn("violates", bad_time.reasons[0])

    def test_rejects_decoder_loop(self) -> None:
        text = "where " * 12
        self.assertIsNotNone(decoder_loop_reason(text))
        validation = validate_asr_result(
            {"segments": [{"start_time": 0.0, "end_time": 2.0, "text": text}]},
            window(),
            support(),
        )
        self.assertFalse(validation.accepted)
        self.assertTrue(any("decoder loop" in reason for reason in validation.reasons))

    def test_rejects_seven_token_decoder_cycle(self) -> None:
        phrase = "alpha bravo charlie delta echo foxtrot golf"
        text = " ".join([phrase] * 8)
        self.assertIsNotNone(decoder_loop_reason(text))

    def test_mixed_unavailable_span_is_not_attributed_to_remote(self) -> None:
        mixed = Window("mix", 30.0, 15, 15.0, Path("unused.wav"))
        item = unavailable_row(mixed, "mix/15s/000030000.json", ["bad JSON"])
        self.assertEqual(item["speaker"], "Mixed")

    def test_rejects_low_channel_support(self) -> None:
        result = {
            "segments": [{"start_time": 0.0, "end_time": 2.0, "text": "Real words."}]
        }
        validation = validate_asr_result(result, window(), support(0.05))
        self.assertFalse(validation.accepted)
        self.assertEqual(len(validation.low_support_rows), 1)


class CleanupContractTests(unittest.TestCase):
    def test_shards_never_exceed_ten(self) -> None:
        rows = [row(f"s{index}", "words", index, index + 1) for index in range(23)]
        shards = candidate_shards(rows)
        self.assertEqual([item["candidate_count"] for item in shards], [10, 10, 3])

    def test_extracts_object_with_best_source_accounting(self) -> None:
        text = (
            'example {"shard_id":"000","decisions":[]}\n'
            'answer {"shard_id":"000","decisions":['
            '{"source_id":"a","action":"keep","duplicate_of":null},'
            '{"source_id":"b","action":"keep","duplicate_of":null}]}'
        )
        value = extract_json_object(text, {"a", "b"})
        self.assertEqual(len(value["decisions"]), 2)

    def test_failed_cleanup_invocation_can_resume_without_attempt_collision(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            call_dir = Path(temporary) / "call"
            raw_root = call_dir / "asr-raw"
            shard = {
                "shard_id": "000",
                "candidate_count": 1,
                "candidates": [row("a", "Real speech.", 0, 1)],
            }
            response = {
                "choices": [
                    {
                        "message": {
                            "content": (
                                '{"shard_id":"000","decisions":['
                                '{"source_id":"a","action":"keep",'
                                '"duplicate_of":null,"reason":""}]}'
                            )
                        }
                    }
                ]
            }

            with mock.patch(
                "call_diarize.cleanup._http_json",
                side_effect=RuntimeError("interrupted cleanup"),
            ):
                with self.assertRaisesRegex(RuntimeError, "interrupted cleanup"):
                    run_model_shard(
                        "gemma",
                        "test-model",
                        shard,
                        raw_root,
                        "http://unused.invalid/v1/chat/completions",
                        {"a": 0},
                        timeout=1,
                        retries=1,
                    )

            first_attempt = raw_root / "cleanup/gemma/shard-000.attempt-01.json"
            self.assertTrue(first_attempt.is_file())
            first_evidence = load_json(first_attempt)
            self.assertEqual(first_evidence["error"], "interrupted cleanup")
            self.assertFalse((call_dir / "transcript.md").exists())

            with mock.patch(
                "call_diarize.cleanup._http_json",
                return_value=response,
            ):
                decisions = run_model_shard(
                    "gemma",
                    "test-model",
                    shard,
                    raw_root,
                    "http://unused.invalid/v1/chat/completions",
                    {"a": 0},
                    timeout=1,
                    retries=1,
                )

            self.assertEqual(decisions[0]["action"], "keep")
            final = load_json(raw_root / "cleanup/gemma/shard-000.json")
            self.assertEqual(final["attempt"], 2)
            self.assertEqual(load_json(first_attempt), first_evidence)

    def test_decisions_are_exact_and_non_mergeable(self) -> None:
        shard = {
            "shard_id": "000",
            "candidates": [row("a", "one", 0, 1), row("b", "two", 1, 2)],
        }
        value = {
            "shard_id": "000",
            "decisions": [
                {"source_id": "a", "action": "keep", "duplicate_of": None},
                {"source_id": "b", "action": "duplicate", "duplicate_of": "a"},
            ],
        }
        normalized = validate_decisions(value, shard, {"a": 0, "b": 1})
        self.assertEqual([item["source_id"] for item in normalized], ["a", "b"])

    def test_drop_requires_both_models_and_lexical_match(self) -> None:
        first = row("a", "This is an unmistakable repeated sentence.", 0, 3)
        second = row("b", "This is an unmistakable repeated sentence.", 3, 6)
        keep = {"source_id": "a", "action": "keep", "duplicate_of": None, "reason": ""}
        duplicate = {
            "source_id": "b",
            "action": "duplicate",
            "duplicate_of": "a",
            "reason": "",
        }
        decisions = {
            "gemma": {"a": keep, "b": duplicate},
            "qwen": {"a": keep, "b": duplicate},
        }
        kept, dropped, _ = reduce_consensus([first, second], decisions)
        self.assertEqual([item["source_id"] for item in kept], ["a"])
        self.assertEqual([item["source_id"] for item in dropped], ["b"])

        decisions["qwen"]["b"] = {
            "source_id": "b",
            "action": "keep",
            "duplicate_of": None,
            "reason": "",
        }
        kept, dropped, disagreements = reduce_consensus([first, second], decisions)
        self.assertEqual(len(kept), 2)
        self.assertEqual(dropped, [])
        self.assertEqual(len(disagreements), 1)

    def test_lexical_match_is_same_channel_and_nearby(self) -> None:
        prior = row("a", "This is an unmistakable repeated sentence.", 0, 3)
        current = row("b", "This is an unmistakable repeated sentence.", 3, 6)
        self.assertEqual(lexical_duplicate_target(current, [prior]), "a")
        current["track"] = "far"
        self.assertIsNone(lexical_duplicate_target(current, [prior]))


if __name__ == "__main__":
    unittest.main()
