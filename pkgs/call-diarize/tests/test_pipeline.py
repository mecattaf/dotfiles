from __future__ import annotations

import json
import tempfile
import unittest
import wave
from pathlib import Path
from unittest import mock

from call_diarize.asr import verify_checkpoint
from call_diarize.cleanup import (
    chat_completions_url,
    extract_json_object,
    reduce_decisions,
    run_model_shard,
    validate_decisions,
)
from call_diarize.pipeline import (
    CHUNK_SAMPLES,
    CHUNK_SECONDS,
    SAMPLE_RATE,
    SESSION_CHUNKS,
    Window,
    candidate_shards,
    decoder_loop_reason,
    lexical_duplicate_target,
    load_json,
    prepare_track,
    session_rows,
    streaming_groups,
    unavailable_row,
    validate_asr_result,
)


def window(chunks: int = 10, first: int = 0) -> Window:
    return Window(
        "near", first, chunks, (first + chunks) * CHUNK_SAMPLES, Path("unused.wav")
    )


def result(texts: list[str], first: int = 0, tokens: int = 5) -> dict:
    return {
        "chunks": [
            {"index": first + ordinal, "text": text, "decoded_token_count": tokens}
            for ordinal, text in enumerate(texts)
        ]
    }


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


class TrackPreparationTests(unittest.TestCase):
    def test_sessions_cover_every_chunk_of_the_resampled_track(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "near.wav"
            seconds = SESSION_CHUNKS * CHUNK_SECONDS + 1.0
            with wave.open(str(source), "wb") as handle:
                handle.setnchannels(1)
                handle.setsampwidth(2)
                handle.setframerate(48_000)
                handle.writeframes(b"\0\0" * round(seconds * 48_000))

            sessions = prepare_track(source, "near", root)

            self.assertEqual(len(sessions), 2)
            self.assertEqual(sessions[0].chunk_count, SESSION_CHUNKS)
            self.assertEqual(sessions[1].first_chunk, SESSION_CHUNKS)
            self.assertEqual(sessions[1].chunk_count, 1)
            self.assertAlmostEqual(sessions[1].actual_seconds, 1.0, places=2)
            self.assertAlmostEqual(
                sum(item.actual_seconds for item in sessions), seconds, places=2
            )
            with wave.open(str(sessions[0].audio_path), "rb") as handle:
                self.assertEqual(handle.getframerate(), SAMPLE_RATE)
            # A rerun overwrites the interrupted conversion in place.
            sessions[0].audio_path.write_bytes(b"interrupted")
            self.assertEqual(prepare_track(source, "near", root), sessions)


class CheckpointTests(unittest.TestCase):
    def test_refuses_incomplete_loan_and_foreign_frame_geometry(self) -> None:
        from call_diarize.asr import MODEL_FILES

        with tempfile.TemporaryDirectory() as temporary:
            model_dir = Path(temporary)
            with self.assertRaisesRegex(RuntimeError, "incomplete"):
                verify_checkpoint(model_dir)
            for name in MODEL_FILES:
                (model_dir / name).write_text("{}", encoding="utf-8")
            config = {
                "chunk_frames": 22,
                "lookahead_frames": 4,
                "speech_tok_compress_ratio": 3200,
                "target_sample_rate": 24000,
            }
            (model_dir / "preprocessor_config.json").write_text(
                json.dumps(config), encoding="utf-8"
            )
            self.assertEqual(verify_checkpoint(model_dir), config)
            config["chunk_frames"] = 20
            (model_dir / "preprocessor_config.json").write_text(
                json.dumps(config), encoding="utf-8"
            )
            with self.assertRaisesRegex(RuntimeError, "frame geometry"):
                verify_checkpoint(model_dir)


class StreamingParseTests(unittest.TestCase):
    def test_labels_straddling_chunks_map_to_chunk_bounds(self) -> None:
        groups = streaming_groups(
            [" \n Speaker 0:I am listening. The system ", "is running. \n Spea", "ker 1:Hello."],
            first_chunk=100,
        )
        self.assertEqual(
            [(g["speaker"], g["first_chunk"], g["last_chunk"]) for g in groups],
            [("0", 100, 101), ("1", 102, 102)],
        )
        self.assertEqual(
            groups[0]["sentences"], ["I am listening.", "The system is running."]
        )

    def test_silent_chunk_and_row_length_split_rows(self) -> None:
        groups = streaming_groups(["Before a pause.", "", "After it."])
        self.assertEqual(len(groups), 2)
        groups = streaming_groups(
            [
                "[Silence]",
                "[Silence]Speaker 0:Before a pause. [Silence]",
                "[Silence][Noise]",
                "After it.",
            ]
        )
        self.assertEqual(
            [(g["first_chunk"], g["last_chunk"], g["sentences"]) for g in groups],
            [(1, 1, ["Before a pause."]), (3, 3, ["After it."])],
        )
        long_speech = ["Sentence." for _ in range(12)]
        groups = streaming_groups(long_speech)
        self.assertEqual(len(groups), 2)
        self.assertLessEqual(
            (groups[0]["last_chunk"] + 1 - groups[0]["first_chunk"]) * CHUNK_SECONDS,
            30.0,
        )

    def test_rows_have_chunk_resolution_and_fixed_channel_speaker(self) -> None:
        rows, withheld = session_rows(
            result(["", "Speaker 3:Hello there.", "", ""], first=102),
            window(4, first=102),
            "near/session-000102.json",
            support(),
            256,
        )
        self.assertEqual(withheld, [])
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["speaker"], "Thomas")
        self.assertEqual(rows[0]["asr_speaker_id_session_local"], "3")
        self.assertAlmostEqual(rows[0]["start"], 103 * CHUNK_SECONDS, places=3)
        self.assertAlmostEqual(rows[0]["end"], 104 * CHUNK_SECONDS, places=3)
        self.assertEqual(rows[0]["source_id"], "near-c000102-s000")

    def test_final_chunk_is_clamped_to_track_end(self) -> None:
        tail = Window("far", 0, 2, CHUNK_SAMPLES + SAMPLE_RATE, Path("unused.wav"))
        rows, _ = session_rows(
            result(["", "Bye."]), tail, "far/session-000000.json", support(), 256
        )
        self.assertAlmostEqual(rows[0]["end"], CHUNK_SECONDS + 1.0, places=3)
        self.assertEqual(rows[0]["speaker"], "Remote")


class StructuralValidationTests(unittest.TestCase):
    def test_accepts_one_text_per_chunk(self) -> None:
        validation = validate_asr_result(result(["a", "b"]), window(2))
        self.assertTrue(validation.accepted)

    def test_rejects_missing_or_misordered_chunks(self) -> None:
        self.assertFalse(validate_asr_result({}, window(2)).accepted)
        short = validate_asr_result(result(["a"]), window(2))
        self.assertIn("has 1 chunks", short.reasons[0])
        misordered = result(["a", "b"])
        misordered["chunks"].reverse()
        self.assertFalse(validate_asr_result(misordered, window(2)).accepted)
        bad_text = result(["a", "b"])
        bad_text["chunks"][1]["text"] = 7
        self.assertIn("non-string", validate_asr_result(bad_text, window(2)).reasons[0])

    def test_decoder_loop_becomes_unavailable_row(self) -> None:
        text = "where " * 12
        self.assertIsNotNone(decoder_loop_reason(text))
        rows, _ = session_rows(
            result([text]), window(1), "near/session-000000.json", support(), 256
        )
        self.assertEqual(rows[0]["kind"], "unavailable")
        self.assertEqual(rows[0]["asr_text"], text.strip())
        self.assertIn("decoder loop", rows[0]["validation_reasons"][0])

    def test_exhausted_token_budget_becomes_unavailable_row(self) -> None:
        rows, _ = session_rows(
            result(["Words that ran on."], tokens=256),
            window(1),
            "near/session-000000.json",
            support(),
            256,
        )
        self.assertEqual(rows[0]["kind"], "unavailable")
        self.assertIn("exhausted", rows[0]["validation_reasons"][0])

    def test_rejects_seven_token_decoder_cycle(self) -> None:
        phrase = "alpha bravo charlie delta echo foxtrot golf"
        text = " ".join([phrase] * 8)
        self.assertIsNotNone(decoder_loop_reason(text))

    def test_mixed_unavailable_span_is_not_attributed_to_remote(self) -> None:
        mixed = Window("mix", 10, 5, 15 * CHUNK_SAMPLES, Path("unused.wav"))
        item = unavailable_row(mixed, "mix/session-000010.json", ["bad JSON"])
        self.assertEqual(item["speaker"], "Mixed")

    def test_low_channel_support_is_withheld(self) -> None:
        rows, withheld = session_rows(
            result(["Real words."]),
            window(1),
            "near/session-000000.json",
            support(0.05),
            256,
        )
        self.assertEqual(rows, [])
        self.assertEqual(len(withheld), 1)
        self.assertEqual(withheld[0]["channel_activity"]["selected"], 0.05)


class CleanupContractTests(unittest.TestCase):
    def test_endpoint_accepts_base_or_chat_completions_url(self) -> None:
        self.assertEqual(
            chat_completions_url("http://worker:8731"),
            "http://worker:8731/v1/chat/completions",
        )
        self.assertEqual(
            chat_completions_url("http://worker:8731/v1/chat/completions/"),
            "http://worker:8731/v1/chat/completions",
        )

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
                        "halogen",
                        "test-model",
                        shard,
                        raw_root,
                        "http://unused.invalid/v1/chat/completions",
                        {"a": 0},
                        timeout=1,
                        retries=1,
                    )

            first_attempt = raw_root / "cleanup/halogen/shard-000.attempt-01.json"
            self.assertTrue(first_attempt.is_file())
            first_evidence = load_json(first_attempt)
            self.assertEqual(first_evidence["error"], "interrupted cleanup")
            self.assertFalse((call_dir / "transcript.md").exists())

            with mock.patch(
                "call_diarize.cleanup._http_json",
                return_value=response,
            ):
                decisions = run_model_shard(
                    "halogen",
                    "test-model",
                    shard,
                    raw_root,
                    "http://unused.invalid/v1/chat/completions",
                    {"a": 0},
                    timeout=1,
                    retries=1,
                )

            self.assertEqual(decisions[0]["action"], "keep")
            final = load_json(raw_root / "cleanup/halogen/shard-000.json")
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

    def test_unavailable_row_ignores_non_earlier_duplicate_target(self) -> None:
        unavailable = unavailable_row(
            window(102, first=102),
            "near/session-000102.json",
            ["forced unavailable"],
        )
        source_id = "near-c000102-unavailable"
        self.assertEqual(unavailable["source_id"], source_id)
        shard = {
            "shard_id": "006",
            "candidate_count": 1,
            "candidates": [unavailable],
        }
        value = {
            "shard_id": "006",
            "decisions": [
                {
                    "source_id": source_id,
                    "action": "duplicate",
                    "duplicate_of": source_id,
                    "reason": "model confused fixed availability with duplication",
                }
            ],
        }

        normalized = validate_decisions(value, shard, {source_id: 0})

        self.assertEqual(normalized[0]["action"], "unavailable")
        self.assertIsNone(normalized[0]["duplicate_of"])

    def test_drop_requires_model_duplicate_and_lexical_match(self) -> None:
        first = row("a", "This is an unmistakable repeated sentence.", 0, 3)
        second = row("b", "This is an unmistakable repeated sentence.", 3, 6)
        keep = {"source_id": "a", "action": "keep", "duplicate_of": None, "reason": ""}
        duplicate = {
            "source_id": "b",
            "action": "duplicate",
            "duplicate_of": "a",
            "reason": "",
        }
        decisions = {"halogen": {"a": keep, "b": duplicate}}
        kept, dropped = reduce_decisions([first, second], decisions)
        self.assertEqual([item["source_id"] for item in kept], ["a"])
        self.assertEqual([item["source_id"] for item in dropped], ["b"])
        self.assertEqual(dropped[0]["model_decisions"], {"halogen": duplicate})

        decisions["halogen"]["b"] = {
            "source_id": "b",
            "action": "keep",
            "duplicate_of": None,
            "reason": "",
        }
        kept, dropped = reduce_decisions([first, second], decisions)
        self.assertEqual(len(kept), 2)
        self.assertEqual(dropped, [])

        unrelated = row("c", "Something entirely different was said.", 6, 9)
        decisions["halogen"]["c"] = {
            "source_id": "c",
            "action": "duplicate",
            "duplicate_of": "a",
            "reason": "",
        }
        kept, dropped = reduce_decisions([first, second, unrelated], decisions)
        self.assertEqual(len(kept), 3)
        self.assertEqual(dropped, [])

    def test_lexical_match_is_same_channel_and_nearby(self) -> None:
        prior = row("a", "This is an unmistakable repeated sentence.", 0, 3)
        current = row("b", "This is an unmistakable repeated sentence.", 3, 6)
        self.assertEqual(lexical_duplicate_target(current, [prior]), "a")
        current["track"] = "far"
        self.assertIsNone(lexical_duplicate_target(current, [prior]))


if __name__ == "__main__":
    unittest.main()
