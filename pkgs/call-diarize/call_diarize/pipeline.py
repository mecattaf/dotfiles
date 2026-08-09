"""Deterministic audio mechanics, validation, and transcript reduction."""

from __future__ import annotations

import hashlib
import json
import math
import os
import re
import subprocess
import tempfile
import wave
from collections import Counter
from dataclasses import dataclass
from difflib import SequenceMatcher
from pathlib import Path
from typing import Any, Callable, Iterable


ACTIVE_DB = -45.0
MIN_CHANNEL_ACTIVITY = 0.10
WORD_RE = re.compile(r"[\wÀ-ÿ']+", re.UNICODE)
NON_SPEECH = {
    "",
    "[silence]",
    "[noise]",
    "[human sounds]",
    "[music]",
}
UNAVAILABLE_TEXT = {
    "[unintelligible speech]",
    "[speech unavailable]",
    "[no parseable asr output]",
}


@dataclass(frozen=True)
class Window:
    """One model input window with a global offset."""

    track: str
    start: float
    nominal_seconds: int
    actual_seconds: float
    audio_path: Path

    @property
    def key(self) -> str:
        start_ms = round(self.start * 1000)
        return f"{self.track}/{self.nominal_seconds:02d}s/{start_ms:012d}.json"

    def request_identity(self, hotwords: str) -> dict[str, Any]:
        return {
            "track": self.track,
            "global_start": round(self.start, 6),
            "nominal_seconds": self.nominal_seconds,
            "audio_seconds": round(self.actual_seconds, 6),
            "hotwords_sha256": hashlib.sha256(hotwords.encode("utf-8")).hexdigest(),
        }


@dataclass(frozen=True)
class Validation:
    accepted: bool
    reasons: tuple[str, ...]
    low_support_rows: tuple[dict[str, Any], ...]


def words(text: str) -> list[str]:
    return [token.lower() for token in WORD_RE.findall(text)]


def normalized_text(text: str) -> str:
    return " ".join(words(text))


def is_non_speech(text: str) -> bool:
    return text.strip().lower() in NON_SPEECH


def is_unavailable(text: str) -> bool:
    lowered = text.strip().lower()
    return lowered in UNAVAILABLE_TEXT or "decoder repetition" in lowered


def normalize_asr_segments(value: object) -> object:
    """Normalize the native v5 parser shape to the proven legacy contract."""

    if not isinstance(value, list):
        return value
    normalized: list[object] = []
    for segment in value:
        if not isinstance(segment, dict):
            normalized.append(segment)
            continue
        native_keys = {"Start", "End", "Content"}
        legacy_keys = {"start_time", "end_time", "text"}
        if native_keys <= segment.keys() and not (legacy_keys & segment.keys()):
            item = {
                "start_time": segment["Start"],
                "end_time": segment["End"],
                "text": segment["Content"],
            }
            if "Speaker" in segment:
                item["speaker_id"] = segment["Speaker"]
            normalized.append(item)
        else:
            normalized.append(segment)
    return normalized


def decoder_loop_reason(text: str) -> str | None:
    """Detect unmistakable decoder loops while leaving ordinary stutters alone."""

    digit = re.search(r"([0-9])\1{7,}", text)
    if digit:
        return f"digit {digit.group(1)!r} repeated at least eight times"

    token_run = re.search(r"(?i)\b([a-z]+)([.,]?)(?:\s+\1\2){7,}", text)
    if token_run:
        return f"token {token_run.group(1)!r} repeated at least eight times"

    tokens = words(text)
    # Catch multi-token cycles that evade the single-token expression. Eight
    # adjacent repetitions is intentionally far above conversational emphasis.
    for width in range(2, min(7, len(tokens) // 8 + 1)):
        for offset in range(0, len(tokens) - width * 8 + 1):
            phrase = tokens[offset : offset + width]
            repeats = 1
            cursor = offset + width
            while tokens[cursor : cursor + width] == phrase:
                repeats += 1
                cursor += width
            if repeats >= 8:
                return f"phrase {' '.join(phrase)!r} repeated {repeats} times"
    return None


def wav_seconds(path: Path, expected_rate: int | None = None) -> float:
    with wave.open(str(path), "rb") as handle:
        if handle.getnchannels() != 1 or handle.getsampwidth() != 2:
            raise ValueError(f"expected mono PCM16 WAV: {path}")
        if expected_rate is not None and handle.getframerate() != expected_rate:
            raise ValueError(
                f"expected {expected_rate} Hz WAV, got {handle.getframerate()}: {path}"
            )
        return handle.getnframes() / handle.getframerate()


def validate_capture_files(call_dir: Path) -> dict[str, float]:
    durations: dict[str, float] = {}
    for track in ("near", "far", "mix"):
        path = call_dir / f"{track}.wav"
        if not path.is_file():
            raise ValueError(f"missing required recording: {path}")
        durations[track] = wav_seconds(path, expected_rate=48_000)
    if max(durations.values()) - min(durations.values()) > 1.0:
        raise ValueError(
            f"recording track durations differ by more than one second: {durations}"
        )
    return durations


def segment_track(
    source: Path, track: str, seconds: int, output_dir: Path
) -> list[Window]:
    """Use ffmpeg's segment muxer to make aligned 24 kHz model inputs."""

    track_dir = output_dir / f"{track}-{seconds:02d}s"
    track_dir.mkdir(parents=True, exist_ok=True)
    pattern = track_dir / f"{track}-%06d.wav"
    subprocess.run(
        [
            "ffmpeg",
            "-y",
            "-nostdin",
            "-hide_banner",
            "-loglevel",
            "error",
            "-i",
            str(source),
            "-map",
            "0:a:0",
            "-ar",
            "24000",
            "-ac",
            "1",
            "-c:a",
            "pcm_s16le",
            "-f",
            "segment",
            "-segment_time",
            str(seconds),
            "-reset_timestamps",
            "1",
            str(pattern),
        ],
        check=True,
    )
    paths = sorted(track_dir.glob(f"{track}-*.wav"))
    if not paths:
        raise RuntimeError(f"ffmpeg produced no {track} chunks")
    return [
        Window(
            track=track,
            start=index * seconds,
            nominal_seconds=seconds,
            actual_seconds=wav_seconds(path, expected_rate=24_000),
            audio_path=path,
        )
        for index, path in enumerate(paths)
    ]


def slice_track(
    source: Path,
    track: str,
    start: float,
    seconds: int,
    output_dir: Path,
) -> Window:
    """Build one recursive retry window directly from the canonical source."""

    retry_dir = output_dir / f"{track}-{seconds:02d}s-retries"
    retry_dir.mkdir(parents=True, exist_ok=True)
    start_ms = round(start * 1000)
    path = retry_dir / f"{track}-{start_ms:012d}.wav"
    subprocess.run(
        [
            "ffmpeg",
            "-y",
            "-nostdin",
            "-hide_banner",
            "-loglevel",
            "error",
            "-ss",
            f"{start:.6f}",
            "-t",
            str(seconds),
            "-i",
            str(source),
            "-map",
            "0:a:0",
            "-ar",
            "24000",
            "-ac",
            "1",
            "-c:a",
            "pcm_s16le",
            str(path),
        ],
        check=True,
    )
    return Window(
        track=track,
        start=start,
        nominal_seconds=seconds,
        actual_seconds=wav_seconds(path, expected_rate=24_000),
        audio_path=path,
    )


class AudioActivity:
    """Measure activity against the physical near/far tracks on demand."""

    def __init__(self, call_dir: Path) -> None:
        import numpy as np

        self._np = np
        self._handles = {
            track: wave.open(str(call_dir / f"{track}.wav"), "rb")
            for track in ("near", "far")
        }
        rates = {handle.getframerate() for handle in self._handles.values()}
        if len(rates) != 1:
            raise ValueError("near/far sample rates differ")
        self.rate = rates.pop()

    def close(self) -> None:
        for handle in self._handles.values():
            handle.close()

    def __enter__(self) -> "AudioActivity":
        return self

    def __exit__(self, *_: object) -> None:
        self.close()

    def activity_fraction(self, track: str, start: float, end: float) -> float:
        handle = self._handles[track]
        first = max(0, min(handle.getnframes(), round(start * self.rate)))
        last = max(first + 1, min(handle.getnframes(), round(end * self.rate)))
        handle.setpos(first)
        values = self._np.frombuffer(
            handle.readframes(last - first), dtype="<i2"
        ).astype(self._np.float32)
        if not len(values):
            return 0.0
        values /= 32768.0
        frame = max(1, round(self.rate * 0.02))
        count = len(values) // frame
        if not count:
            return 0.0
        frames = values[: count * frame].reshape(count, frame)
        rms = self._np.sqrt(self._np.mean(frames.astype(self._np.float64) ** 2, axis=1))
        db = 20 * self._np.log10(self._np.maximum(rms, 1e-8))
        return float(self._np.mean(db > ACTIVE_DB))

    def support(self, track: str, start: float, end: float) -> dict[str, float]:
        near = self.activity_fraction("near", start, end)
        far = self.activity_fraction("far", start, end)
        selected = (
            near if track == "near" else far if track == "far" else max(near, far)
        )
        return {
            "near": round(near, 4),
            "far": round(far, 4),
            "selected": round(selected, 4),
        }


def _number(value: object) -> float | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    number = float(value)
    return number if math.isfinite(number) else None


def validate_asr_result(
    result: dict[str, Any],
    window: Window,
    support: Callable[[str, float, float], dict[str, float]],
) -> Validation:
    """Apply the frozen strict structural and channel-support gate."""

    reasons: list[str] = []
    low_support: list[dict[str, Any]] = []
    segments = normalize_asr_segments(result.get("segments"))
    if not isinstance(segments, list) or not segments:
        return Validation(
            False, ("ASR output was not a non-empty strict segment list",), ()
        )

    previous_start = 0.0
    previous_end = 0.0
    for ordinal, segment in enumerate(segments):
        if not isinstance(segment, dict):
            reasons.append(f"segment {ordinal} is not an object")
            continue
        start = _number(segment.get("start_time"))
        end = _number(segment.get("end_time"))
        text = segment.get("text")
        if start is None or end is None:
            reasons.append(f"segment {ordinal} has non-numeric or missing timestamps")
            continue
        if not isinstance(text, str):
            reasons.append(f"segment {ordinal} has non-string text")
            continue

        timestamps_valid = True
        if start < 0 or end < start or end > window.actual_seconds:
            reasons.append(
                f"segment {ordinal} violates 0 <= start <= end <= {window.actual_seconds:.6f} "
                f"({start:.6f}, {end:.6f})"
            )
            timestamps_valid = False
        if ordinal and start < previous_start:
            reasons.append(f"segment {ordinal} start timestamp regresses")
            timestamps_valid = False
        if ordinal and end < previous_end:
            reasons.append(f"segment {ordinal} end timestamp regresses")
            timestamps_valid = False
        previous_start = max(previous_start, start)
        previous_end = max(previous_end, end)

        loop = decoder_loop_reason(text)
        if loop:
            reasons.append(f"segment {ordinal} contains decoder loop: {loop}")

        if (
            timestamps_valid
            and not is_non_speech(text)
            and not is_unavailable(text)
            and end > start
        ):
            global_start = window.start + start
            global_end = window.start + end
            evidence = support(window.track, global_start, global_end)
            if evidence["selected"] < MIN_CHANNEL_ACTIVITY:
                item = {
                    "ordinal": ordinal,
                    "text": text,
                    "global_start": round(global_start, 3),
                    "global_end": round(global_end, 3),
                    "activity": evidence,
                }
                low_support.append(item)
                reasons.append(
                    f"segment {ordinal} has {evidence['selected']:.3f} matching channel activity"
                )

    return Validation(not reasons, tuple(reasons), tuple(low_support))


def segments_to_rows(
    result: dict[str, Any],
    window: Window,
    raw_path: str,
    support: Callable[[str, float, float], dict[str, float]],
) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    segments = normalize_asr_segments(result["segments"])
    if not isinstance(segments, list):
        raise ValueError("ASR segments were not a list")
    for ordinal, segment in enumerate(segments):
        if not isinstance(segment, dict):
            raise ValueError(f"ASR segment {ordinal} was not an object")
        text = str(segment["text"]).strip()
        if is_non_speech(text):
            continue
        start = window.start + float(segment["start_time"])
        end = window.start + float(segment["end_time"])
        evidence = support(window.track, start, end)
        rows.append(
            {
                "source_id": (
                    f"{window.track}-{round(window.start * 1000):012d}-"
                    f"{window.nominal_seconds:02d}-s{ordinal:03d}"
                ),
                "track": window.track,
                "speaker": "Thomas" if window.track == "near" else "Remote",
                "start": round(start, 3),
                "end": round(end, 3),
                "text": text,
                "kind": "unavailable" if is_unavailable(text) else "speech",
                "channel_activity": evidence,
                "source_resolution_seconds": window.nominal_seconds,
                "source_raw": raw_path,
                "asr_speaker_id_chunk_local": segment.get("speaker_id"),
            }
        )
    return rows


def unavailable_row(
    window: Window, raw_path: str, reasons: Iterable[str]
) -> dict[str, Any]:
    return {
        "source_id": (
            f"{window.track}-{round(window.start * 1000):012d}-"
            f"{window.nominal_seconds:02d}-unavailable"
        ),
        "track": window.track,
        "speaker": "Thomas" if window.track == "near" else "Remote",
        "start": round(window.start, 3),
        "end": round(window.start + window.actual_seconds, 3),
        "text": "[Speech unavailable; see review queue]",
        "kind": "unavailable",
        "channel_activity": None,
        "source_resolution_seconds": window.nominal_seconds,
        "source_raw": raw_path,
        "validation_reasons": list(reasons),
    }


def sort_rows(rows: Iterable[dict[str, Any]]) -> list[dict[str, Any]]:
    track_order = {"near": 0, "far": 1, "mix": 2}
    return sorted(
        rows,
        key=lambda row: (
            float(row["start"]),
            track_order.get(str(row.get("track")), 9),
            str(row["source_id"]),
        ),
    )


def lexical_duplicate_target(
    candidate: dict[str, Any],
    prior_rows: Iterable[dict[str, Any]],
) -> str | None:
    """Find a conservative same-channel duplicate immediately before a row."""

    current = normalized_text(str(candidate["text"]))
    if len(current) < 12:
        return None
    for previous in reversed(list(prior_rows)):
        if previous.get("kind") != "speech" or previous.get("track") != candidate.get(
            "track"
        ):
            continue
        if float(candidate["start"]) - float(previous["end"]) > 12.0:
            break
        prior = normalized_text(str(previous["text"]))
        if len(prior) < 12:
            continue
        similarity = SequenceMatcher(None, prior, current).ratio()
        containment = min(len(prior), len(current)) / max(
            len(prior), len(current)
        ) >= 0.60 and (prior in current or current in prior)
        if similarity >= 0.92 or containment:
            return str(previous["source_id"])
    return None


def lexical_recall(needle: str, haystack: str) -> float:
    left = Counter(words(needle))
    right = Counter(words(haystack))
    if not left:
        return 1.0
    return sum((left & right).values()) / sum(left.values())


def mixed_lexical_conflicts(
    isolated: Iterable[dict[str, Any]],
    mixed: Iterable[dict[str, Any]],
) -> list[dict[str, Any]]:
    mixed_rows = [row for row in mixed if row.get("kind") == "speech"]
    conflicts: list[dict[str, Any]] = []
    for row in isolated:
        if row.get("kind") != "speech" or len(words(str(row["text"]))) < 3:
            continue
        overlapping = [
            other
            for other in mixed_rows
            if min(float(row["end"]), float(other["end"]))
            - max(float(row["start"]), float(other["start"]))
            > 0.05
        ]
        combined = " ".join(str(other["text"]) for other in overlapping)
        recall = lexical_recall(str(row["text"]), combined)
        if recall < 0.35:
            conflicts.append(
                {
                    "source_id": row["source_id"],
                    "start": row["start"],
                    "end": row["end"],
                    "speaker": row["speaker"],
                    "isolated_text": row["text"],
                    "mixed_text": combined or "[no overlapping mixed-track speech]",
                    "isolated_token_recall_from_mix": round(recall, 3),
                }
            )
    return conflicts


def candidate_shards(
    rows: list[dict[str, Any]], limit: int = 10
) -> list[dict[str, Any]]:
    if limit < 1 or limit > 10:
        raise ValueError("cleanup shard limit must be between one and ten")
    return [
        {
            "shard_id": f"{offset // limit:03d}",
            "candidate_count": len(rows[offset : offset + limit]),
            "candidates": rows[offset : offset + limit],
        }
        for offset in range(0, len(rows), limit)
    ]


def format_time(seconds: float) -> str:
    seconds = max(0.0, float(seconds))
    hours, remainder = divmod(seconds, 3600)
    minutes, remainder = divmod(remainder, 60)
    if hours:
        return f"{int(hours):02d}:{int(minutes):02d}:{remainder:05.2f}"
    return f"{int(minutes):02d}:{remainder:05.2f}"


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json_exclusive(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = json.dumps(value, ensure_ascii=False, indent=2) + "\n"
    try:
        with path.open("x", encoding="utf-8") as handle:
            handle.write(payload)
    except FileExistsError as exc:
        raise RuntimeError(f"refusing to overwrite existing evidence: {path}") from exc


def write_text_final(path: Path, text: str, force: bool) -> None:
    """Publish a final artifact atomically; replacement requires explicit force."""

    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists() and not force:
        raise RuntimeError(f"refusing to overwrite existing file: {path}")
    fd, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(text)
            handle.flush()
            os.fsync(handle.fileno())
        if path.exists() and not force:
            raise RuntimeError(f"refusing to overwrite existing file: {path}")
        os.replace(temporary, path)
    finally:
        if temporary.exists():
            temporary.unlink()
