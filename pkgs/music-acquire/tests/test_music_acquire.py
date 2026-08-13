from __future__ import annotations

import collections
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from music_acquire.backend import LiveBackend
from music_acquire.cli import Acquirer, main, tracklist_items
from music_acquire.state import BatchState
from music_acquire.verification import core_and_version, title_agrees, version_agrees


def track(item_id: str) -> dict:
    return {
        "id": item_id,
        "title": "Fixture",
        "url": f"https://soundcloud.com/fixture/{item_id}",
        "full_duration_ms": 170_000,
        "has_preview": True,
    }


class FakeBackend:
    def __init__(self, scenarios: dict[str, dict], duplicates: dict[str, dict] | None = None):
        self.scenarios = scenarios
        self.duplicates = duplicates or {}
        self.calls = collections.Counter()
        self.remembered = []

    def _scenario(self, item):
        return self.scenarios[str(item["id"])]

    def duplicate(self, item, sc_track=None):
        self.calls["duplicate"] += 1
        return self.duplicates.get(str(item["id"]))

    def resolve_soundcloud(self, item):
        self.calls["resolve_soundcloud"] += 1
        return self._scenario(item).get(
            "resolve", {"status": "found", "track": track(str(item["id"]))}
        )

    def download_soundcloud(self, item, sc_track):
        self.calls["download_soundcloud"] += 1
        return self._scenario(item).get("soundcloud", {"status": "drm"})

    def verify_youtube(self, item, sc_track):
        self.calls["verify_youtube"] += 1
        return self._scenario(item).get(
            "youtube", {"status": "unverified", "reason": "unverified"}
        )

    def retry_youtube_download(self, item, previous):
        self.calls["retry_youtube_download"] += 1
        return self._scenario(item)["youtube_retry"]

    def capture(self, item, sc_track):
        self.calls["capture"] += 1
        return self._scenario(item).get(
            "capture", {"status": "unavailable", "reason": "capture_unavailable"}
        )

    def download_bandcamp(self, item):
        self.calls["download_bandcamp"] += 1
        return self._scenario(item)["bandcamp"]

    def download_ytmusic(self, item):
        self.calls["download_ytmusic"] += 1
        return self._scenario(item)["ytmusic"]

    def remember(self, item, row):
        self.remembered.append((item["id"], row["disposition"]))


class BatchTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def state(self, batch="fixtures"):
        state = BatchState(self.root / "state", batch)
        state.merge_worklist([])
        return state

    @staticmethod
    def item(item_id, **values):
        return {
            "id": item_id,
            "query": values.pop("query", item_id),
            "source": values.pop("source", "tracklist:fixture"),
            "appearances": values.pop("appearances", []),
            **values,
        }

    def run_one(self, item, scenario, duplicates=None):
        state = self.state()
        state.merge_worklist([item])
        backend = FakeBackend({item["id"]: scenario}, duplicates)
        Acquirer(state, backend, backoff_seconds=0).run(state.worklist(), "tracklist")
        return state, backend, state.final_rows()[item["id"]]

    def test_stage_one_stops_before_youtube(self):
        item = self.item("liftboi-kirschberg")
        state, backend, row = self.run_one(
            item,
            {
                "resolve": {
                    "status": "found",
                    "track": {
                        **track("liftboi-kirschberg"),
                        "id": "289635627",
                        "full_duration_ms": 342_000,
                    },
                },
                "soundcloud": {"status": "ok", "path": "/music/kirschberg.mp3"},
            },
        )
        self.assertEqual(row["disposition"], "ok_soundcloud")
        self.assertEqual(row["evidence"]["duration_s"], 342.0)
        self.assertEqual(backend.calls["verify_youtube"], 0)
        self.assertEqual(backend.calls["capture"], 0)
        self.assertIn(item["id"], state.archived())

    def test_recorded_acoustic_fixture(self):
        item = self.item("1010003194")
        _, _, row = self.run_one(
            item,
            {
                "soundcloud": {"status": "drm"},
                "youtube": {
                    "status": "ok",
                    "path": "/music/1010003194.opus",
                    "yt_id": "JR7DCavxVVM",
                    "verdict": "acoustic",
                    "evidence": {
                        "ber": 0.0381,
                        "dur_ref_s": 170.1,
                        "dur_got_s": 171.0,
                    },
                },
            },
        )
        self.assertEqual(row["disposition"], "ok_youtube")
        self.assertEqual(row["yt_id"], "JR7DCavxVVM")
        self.assertEqual(row["evidence"]["ber"], 0.0381)

    def test_recorded_isrc_fixture(self):
        item = self.item("1016015629")
        _, _, row = self.run_one(
            item,
            {
                "soundcloud": {"status": "drm"},
                "youtube": {
                    "status": "ok",
                    "path": "/music/1016015629.webm",
                    "yt_id": "a9rZFirpbyQ",
                    "verdict": "isrc",
                    "evidence": {
                        "isrc": "FR9W11708727",
                        "mb_recording": "7ddc6397-2247-48f2-b419-9d0a9969620e",
                        "dur_ref_s": 208.6,
                        "dur_mb_s": 208.0,
                        "dur_got_s": 209.0,
                    },
                },
            },
        )
        self.assertEqual(row["disposition"], "ok_youtube")
        self.assertEqual(row["verdict"], "isrc")

    def test_recorded_capture_fixture(self):
        item = self.item("1028566936")
        _, backend, row = self.run_one(
            item,
            {
                "soundcloud": {"status": "drm"},
                "youtube": {"status": "unverified", "reason": "unverified"},
                "capture": {
                    "status": "ok",
                    "path": "/music/1028566936.flac",
                    "evidence": {
                        "captured_s": 137.5,
                        "ber_vs_preview": 0.0174,
                        "mean_volume_db": -10.6,
                        "artwork": "embedded",
                    },
                },
            },
        )
        self.assertEqual(row["disposition"], "ok_capture")
        self.assertTrue(row["path"].endswith(".flac"))
        self.assertEqual(backend.calls["capture"], 1)

    def test_wrong_version_stays_rejected(self):
        item = self.item("252618029")
        _, _, row = self.run_one(
            item,
            {
                "soundcloud": {"status": "drm"},
                "youtube": {"status": "unverified", "reason": "unverified"},
                "capture": {
                    "status": "rejected",
                    "reason": "capture_verification_failed",
                    "evidence": {"ber_attempts": [0.281, 0.285, 0.304]},
                },
            },
        )
        self.assertEqual(row["disposition"], "fallthrough")
        self.assertEqual(row["reason"], "capture_verification_failed")

    def test_deleted_upstream_is_gone_without_retry_loop(self):
        item = self.item("25858463")
        state, backend, row = self.run_one(
            item,
            {"resolve": {"status": "gone", "reason": "track_gone_upstream"}},
        )
        self.assertEqual(row["disposition"], "gone")
        self.assertIn(item["id"], state.archived())
        self.assertEqual(backend.calls["download_soundcloud"], 0)
        self.assertEqual(backend.calls["verify_youtube"], 0)

    def test_verified_download_auth_failure_is_retryable_and_unarchived(self):
        item = self.item("814429207")
        state, _, row = self.run_one(
            item,
            {
                "soundcloud": {"status": "drm"},
                "youtube": {
                    "status": "retryable",
                    "reason": "verified_but_download_failed",
                    "detail": "use --cookies for authentication",
                    "yt_id": "M3sYTPAlHvA",
                    "verdict": "metadata",
                },
            },
        )
        self.assertEqual(row["disposition"], "retryable")
        self.assertNotIn(item["id"], state.archived())

    def test_verified_download_retry_reuses_recorded_video_and_evidence(self):
        item = self.item("814429207")
        state = self.state()
        state.merge_worklist([item])
        state.record(
            item,
            "retryable",
            reason="verified_but_download_failed",
            stage="youtube",
            sc_id="814429207",
            yt_id="M3sYTPAlHvA",
            verdict="metadata",
            evidence={"dur_ref_s": 256.1, "dur_got_s": 256.0},
        )
        backend = FakeBackend(
            {
                item["id"]: {
                    "youtube_retry": {
                        "status": "ok",
                        "path": "/music/814429207.opus",
                        "yt_id": "M3sYTPAlHvA",
                        "verdict": "metadata",
                        "evidence": {"dur_ref_s": 256.1, "dur_got_s": 256.0},
                    }
                }
            }
        )
        Acquirer(state, backend, backoff_seconds=0).run(state.worklist(), "tracklist")
        row = state.final_rows()[item["id"]]
        self.assertEqual(row["disposition"], "ok_youtube")
        self.assertEqual(backend.calls["retry_youtube_download"], 1)
        self.assertEqual(backend.calls["resolve_soundcloud"], 0)
        self.assertEqual(backend.calls["verify_youtube"], 0)

    def test_capture_retry_skips_direct_and_youtube_stages(self):
        item = self.item("capture-retry")
        state = self.state()
        state.merge_worklist([item])
        state.record(
            item,
            "retryable",
            reason="capture_host_busy",
            stage="capture",
            stage2_reason="unverified",
            sc_id="capture-retry",
        )
        backend = FakeBackend(
            {
                item["id"]: {
                    "resolve": {"status": "found", "track": track(item["id"])},
                    "capture": {
                        "status": "ok",
                        "path": "/music/capture-retry.flac",
                        "evidence": {"ber_vs_preview": 0.02},
                    },
                }
            }
        )
        Acquirer(state, backend, backoff_seconds=0).run(state.worklist(), "tracklist")
        self.assertEqual(
            state.final_rows()[item["id"]]["disposition"], "ok_capture"
        )
        self.assertEqual(backend.calls["download_soundcloud"], 0)
        self.assertEqual(backend.calls["verify_youtube"], 0)
        self.assertEqual(backend.calls["capture"], 1)

    def test_duplicate_suppression_performs_no_network_call(self):
        item = self.item("101000650")
        state, backend, row = self.run_one(
            item,
            {},
            duplicates={item["id"]: {"path": "/held/101000650.mp3"}},
        )
        self.assertEqual(row["disposition"], "skipped_duplicate")
        self.assertEqual(backend.calls["resolve_soundcloud"], 0)
        self.assertIn(item["id"], state.archived())

    def test_no_capture_is_first_class_and_can_be_reopened(self):
        item = self.item("needs-capture")
        state, _, row = self.run_one(
            item,
            {
                "soundcloud": {"status": "drm"},
                "youtube": {"status": "unverified", "reason": "unverified"},
                "capture": {"status": "unavailable", "reason": "capture_unavailable"},
            },
        )
        self.assertEqual(row["disposition"], "fallthrough")
        self.assertIn(item["id"], state.archived())
        self.assertEqual(state.reopen_capture_unavailable(), [item["id"]])
        self.assertNotIn(item["id"], state.archived())

    def test_rerun_of_completed_batch_has_zero_network_calls(self):
        item = self.item("done")
        state, _, _ = self.run_one(
            item,
            {"soundcloud": {"status": "ok", "path": "/music/done.mp3"}},
        )
        backend = FakeBackend({item["id"]: {}})
        attempted = Acquirer(state, backend, backoff_seconds=0).run(
            state.worklist(), "tracklist"
        )
        self.assertEqual(attempted, 0)
        self.assertEqual(sum(backend.calls.values()), 0)

    def test_completed_cli_rerun_does_not_prepare_network_backend(self):
        worklist = self.root / "completed.jsonl"
        worklist.write_text(
            json.dumps(
                {"key": "done", "query": "Artist - Done", "appearances": []}
            )
            + "\n"
        )
        state_root = self.root / "cli-complete"
        state = BatchState(state_root, "completed")
        items = tracklist_items(worklist)
        state.merge_worklist(items)
        state.save_request(
            {
                "verb": "tracklist",
                "input": str(worklist.resolve()),
                "source": str(worklist.resolve()),
                "source_filter": None,
                "batch": "completed",
                "out": str(self.root / "out"),
            }
        )
        state.record(items[0], "ok_youtube", path="/music/done.opus")
        environment = {
            "MUSIC_ACQUIRE_STATE_ROOT": str(state_root),
            "MUSIC_CONSOLIDATION_REPO": str(self.root / "campaign"),
        }
        with mock.patch.object(
            LiveBackend, "prepare", side_effect=AssertionError("network prepare called")
        ):
            self.assertEqual(
                main(
                    ["tracklist", str(worklist), "--batch", "completed"],
                    environ=environment,
                ),
                0,
            )

    def test_last_write_wins_but_retryable_never_enters_archive(self):
        item = self.item("retry")
        state = self.state()
        state.merge_worklist([item])
        state.record(item, "retryable", reason="throttle")
        self.assertNotIn(item["id"], state.archived())
        state.record(item, "ok_youtube", path="/music/retry.opus")
        self.assertEqual(state.final_rows()[item["id"]]["disposition"], "ok_youtube")
        self.assertIn(item["id"], state.archived())

    def test_tracklist_merges_cross_source_and_repeat_appearances(self):
        worklist = self.root / "worklist.jsonl"
        rows = [
            {
                "key": "dire straits six blade knife",
                "query": "Dire Straits - Six Blade Knife (THE ODDNESS Re-work)",
                "artist": "Dire Straits",
                "title": "Six Blade Knife (THE ODDNESS Re-work)",
                "appearances": [
                    {
                        "source": "goldcast",
                        "set": "027",
                        "segment": "guestmix:The Oddness",
                        "position": 10,
                    }
                ],
            },
            {
                "key": "dire straits six blade knife",
                "query": "Dire Straits - Six Blade Knife (THE ODDNESS Re-work)",
                "artist": "Dire Straits",
                "title": "Six Blade Knife (THE ODDNESS Re-work)",
                "appearances": [
                    {
                        "source": "vent-2024",
                        "set": "2024",
                        "segment": "main",
                        "position": 95,
                    }
                ],
            },
            {
                "key": "chambord wonderland",
                "query": "Chambord - Wonderland (Maga Remix)",
                "artist": "Chambord",
                "title": "Wonderland (Maga Remix)",
                "appearances": [
                    {"source": "goldcast", "set": str(i), "segment": "main", "position": 2}
                    for i in range(4)
                ],
            },
        ]
        worklist.write_text("".join(json.dumps(row) + "\n" for row in rows))
        items = tracklist_items(worklist)
        self.assertEqual(len(items), 2)
        self.assertEqual(len(items[0]["appearances"]), 2)
        self.assertEqual(len(items[1]["appearances"]), 4)

    def test_status_json_has_totals_dispositions_and_estimate(self):
        worklist = self.root / "worklist.jsonl"
        worklist.write_text(
            json.dumps({"key": "one", "query": "Artist - One", "appearances": []})
            + "\n"
        )
        environment = {
            "MUSIC_ACQUIRE_STATE_ROOT": str(self.root / "cli-state"),
            "MUSIC_CONSOLIDATION_REPO": str(self.root / "campaign"),
        }
        self.assertEqual(
            main(
                ["tracklist", str(worklist), "--dry-run", "--out", str(self.root / "out")],
                environ=environment,
            ),
            0,
        )
        self.assertEqual(main(["status", "--batch", "worklist", "--json"], environ=environment), 0)


class VerificationTest(unittest.TestCase):
    def test_version_markers_are_sets_not_similarity(self):
        original = core_and_version("Lucy")
        instrumental = core_and_version("Lucy (Instrumentale)")
        remix = core_and_version("Lucy (Kaytranada Remix)")
        self.assertFalse(version_agrees(original[1], instrumental[1]))
        self.assertFalse(version_agrees(original[1], remix[1]))
        self.assertTrue(title_agrees("Lucy", "Lucy (Original Mix)"))
        self.assertFalse(title_agrees("Chapter One", "Chapter One Part Two"))
        self.assertTrue(title_agrees("Corrida", "SCH - Corrida", ["SCH"]))


class NativeDownloadTest(unittest.TestCase):
    def test_final_download_command_never_transcodes_or_overwrites(self):
        with tempfile.TemporaryDirectory() as temp_name:
            root = Path(temp_name)
            state = BatchState(root / "state", "native")
            state.merge_worklist([])
            backend = LiveBackend(
                state,
                root / "out",
                root / "campaign",
                no_capture=True,
                environ={"MUSIC_ACQUIRE_STAGING": str(root / "staging")},
            )
            commands = []

            def fake_run(command, **_kwargs):
                commands.append(command)
                template = Path(command[command.index("-o") + 1])
                output = Path(str(template).replace("%(ext)s", "webm"))
                output.parent.mkdir(parents=True, exist_ok=True)
                output.write_bytes(b"native codec bytes")
                return subprocess.CompletedProcess(command, 0, "", "")

            backend._run = fake_run
            result = backend._download_native(
                url="https://youtube.example/fixture",
                item_id="fixture",
                cookies=None,
                format_selector="bestaudio/best",
            )
            self.assertEqual(result["status"], "ok")
            command = commands[0]
            self.assertNotIn("-x", command)
            self.assertNotIn("--extract-audio", command)
            self.assertNotIn("--audio-format", command)
            self.assertNotIn("--recode-video", command)
            self.assertIn("--no-overwrites", command)

    def test_official_long_form_tracklist_is_resolved_and_stream_copied(self):
        description = """Tracklist:
01 - Visage [00:00]
02 - In A Search Of Touch [01:38]
07 - My Personality Shaped By Curves & Angles [24:09]
"""
        segments = LiveBackend._description_segments(description, 1_863_053)
        self.assertEqual(segments[-1]["start_s"], 1_449.0)
        self.assertAlmostEqual(segments[-1]["end_s"], 1_863.053)

        with tempfile.TemporaryDirectory() as temp_name:
            root = Path(temp_name)
            state = BatchState(root / "state", "segment")
            state.merge_worklist([])
            backend = LiveBackend(
                state,
                root / "out",
                root / "campaign",
                no_capture=True,
                environ={"MUSIC_ACQUIRE_STAGING": str(root / "staging")},
            )
            backend._soundcloud_get = lambda *_args, **_kwargs: {
                "collection": [
                    {
                        "id": 738396898,
                        "title": "HAKIMONU - Music For Children [Full Album]",
                        "description": description,
                        "duration": 1_863_053,
                        "full_duration": 1_863_053,
                        "permalink_url": "https://soundcloud.example/full-album",
                        "user": {"username": "HAKIMONU", "permalink": "hakimonu"},
                    }
                ]
            }
            item = {
                "id": "hakimonu my personality shaped by curves angles",
                "query": "Hakimonu - My Personality Shaped by Curves & Angles",
                "artist": "Hakimonu",
                "title": "My Personality Shaped by Curves & Angles",
                "album": None,
                "source": "tracklist:goldcast",
            }
            resolved = backend.resolve_soundcloud(item)
            self.assertEqual(resolved["status"], "found")
            self.assertEqual(resolved["track"]["segment"]["start_s"], 1_449.0)
            self.assertIsNone(backend.duplicate(item, resolved["track"]))

            parent = backend.work / "sc-parent-738396898.m4a"
            parent.write_bytes(b"native parent")
            commands = []

            def fake_run(command, **_kwargs):
                commands.append(command)
                Path(command[-1]).write_bytes(b"native segment")
                return subprocess.CompletedProcess(command, 0, "", "")

            backend._run = fake_run
            backend.sc_cookie.write_text("cookie")
            outcome = backend.download_soundcloud(item, resolved["track"])
            self.assertEqual(outcome["status"], "ok")
            self.assertEqual(outcome["segment"]["parent_sc_id"], "738396898")
            command = commands[0]
            self.assertEqual(Path(command[-1]).parent, backend.out)
            self.assertIn(".segment.part", Path(command[-1]).name)
            self.assertIn("copy", command)
            self.assertNotIn("libopus", command)
            self.assertNotIn("aac", command)


if __name__ == "__main__":
    unittest.main()
