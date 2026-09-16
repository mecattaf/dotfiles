"""Deterministic audio mechanics, validation, and transcript reduction."""

from __future__ import annotations

import bisect
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

# VibeVoice-ASR-Streaming frame geometry, fixed by the checkpoint's
# preprocessor_config.json (asr.verify_checkpoint refuses any other):
# 22 frames of advance plus 4 frames of lookahead, 3200 samples per frame.
SAMPLE_RATE = 24_000
FRAME_SAMPLES = 3_200
CHUNK_FRAMES = 22
LOOKAHEAD_FRAMES = 4
CHUNK_SAMPLES = CHUNK_FRAMES * FRAME_SAMPLES
LOOKAHEAD_SAMPLES = LOOKAHEAD_FRAMES * FRAME_SAMPLES
CHUNK_SECONDS = CHUNK_SAMPLES / SAMPLE_RATE
# One streaming session (fresh prompt and KV cache) per 102 chunks, 299.2 s:
# inside the eight-minute recordings the model was reported for, and a
# resumable unit of GPU work.
SESSION_CHUNKS = 102
# Streaming output carries no timestamps. Times are the bounds of the chunks
# in which text was emitted, so they are only as precise as CHUNK_SECONDS and
# can trail speech by up to one chunk. Rows break on speaker labels, on a
# silent chunk, or once a row spans this long.
ROW_MAX_SECONDS = 30.0
SPEAKER_LABEL_RE = re.compile(r"(?:^|(?<=\s))Speaker[ \t]+(\d+)[ \t]*:")
SENTENCE_RE = re.compile(r"[^.!?]+(?:[.!?]+|$)")
# Streaming output marks pauses inline ("[Silence][Silence]") without sentence
# punctuation. They are blanked in place so offsets still map to chunks and a
# chunk holding only a marker counts as silent.
NON_SPEECH_MARKER_RE = re.compile(r"\[(?:silence|noise|human sounds|music)\]", re.I)


@dataclass(frozen=True)
class Window:
    """One streaming session: consecutive checkpoint chunks of one track."""

    track: str
    first_chunk: int
    chunk_count: int
    track_samples: int
    audio_path: Path

    @property
    def start(self) -> float:
        return self.first_chunk * CHUNK_SAMPLES / SAMPLE_RATE

    @property
    def actual_seconds(self) -> float:
        end = min(
            self.track_samples, (self.first_chunk + self.chunk_count) * CHUNK_SAMPLES
        )
        return (end - self.first_chunk * CHUNK_SAMPLES) / SAMPLE_RATE

    def chunk_span(self, chunk: int) -> tuple[float, float]:
        """Global bounds of one chunk, by global chunk index."""

        start = chunk * CHUNK_SAMPLES
        end = min(self.track_samples, start + CHUNK_SAMPLES)
        return start / SAMPLE_RATE, end / SAMPLE_RATE

    @property
    def key(self) -> str:
        return f"{self.track}/session-{self.first_chunk:06d}.json"

    def request_identity(self, hotwords: str) -> dict[str, Any]:
        return {
            "track": self.track,
            "first_chunk": self.first_chunk,
            "chunk_count": self.chunk_count,
            "chunk_samples": CHUNK_SAMPLES,
            "lookahead_samples": LOOKAHEAD_SAMPLES,
            "audio_seconds": round(self.actual_seconds, 6),
            "hotwords_sha256": hashlib.sha256(hotwords.encode("utf-8")).hexdigest(),
        }


@dataclass(frozen=True)
class Validation:
    accepted: bool
    reasons: tuple[str, ...]


def words(text: str) -> list[str]:
    return [token.lower() for token in WORD_RE.findall(text)]


def normalized_text(text: str) -> str:
    return " ".join(words(text))


def is_non_speech(text: str) -> bool:
    return text.strip().lower() in NON_SPEECH


def is_unavailable(text: str) -> bool:
    lowered = text.strip().lower()
    return lowered in UNAVAILABLE_TEXT or "decoder repetition" in lowered


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
    for width in range(2, min(7, len(tokens) // 8) + 1):
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


def prepare_track(source: Path, track: str, output_dir: Path) -> list[Window]:
    """Resample one recording to 24 kHz mono and lay out its sessions."""

    path = output_dir / f"{track}-24k.wav"
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
            str(SAMPLE_RATE),
            "-ac",
            "1",
            "-c:a",
            "pcm_s16le",
            str(path),
        ],
        check=True,
    )
    with wave.open(str(path), "rb") as handle:
        if (
            handle.getframerate() != SAMPLE_RATE
            or handle.getnchannels() != 1
            or handle.getsampwidth() != 2
        ):
            raise RuntimeError(f"ffmpeg did not produce 24 kHz mono PCM16: {path}")
        samples = handle.getnframes()
    total_chunks = math.ceil(samples / CHUNK_SAMPLES)
    return [
        Window(
            track=track,
            first_chunk=first,
            chunk_count=min(SESSION_CHUNKS, total_chunks - first),
            track_samples=samples,
            audio_path=path,
        )
        for first in range(0, total_chunks, SESSION_CHUNKS)
    ]


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

    def chunk_activity(self, track: str, start: float, end: float) -> float:
        """Best chunk-sized activity over a span and the chunk before it.

        Text is emitted in the chunk where the model finished hearing it, so a
        short reply can sit in the preceding chunk and fill little of a long
        row. A hallucination on a silent channel stays low in every slice.
        """

        cursor = max(0.0, start - CHUNK_SECONDS)
        best = 0.0
        while cursor < end:
            best = max(
                best,
                self.activity_fraction(
                    track, cursor, min(end, cursor + CHUNK_SECONDS)
                ),
            )
            cursor += CHUNK_SECONDS
        return best

    def support(self, track: str, start: float, end: float) -> dict[str, float]:
        near = self.chunk_activity("near", start, end)
        far = self.chunk_activity("far", start, end)
        selected = (
            near if track == "near" else far if track == "far" else max(near, far)
        )
        return {
            "near": round(near, 4),
            "far": round(far, 4),
            "selected": round(selected, 4),
        }


def validate_asr_result(result: dict[str, Any], window: Window) -> Validation:
    """Require one decoded text per requested chunk, in order."""

    chunks = result.get("chunks")
    if not isinstance(chunks, list):
        return Validation(False, ("ASR output has no chunk list",))
    reasons: list[str] = []
    if len(chunks) != window.chunk_count:
        reasons.append(
            f"ASR output has {len(chunks)} chunks; the session has {window.chunk_count}"
        )
    for ordinal, chunk in enumerate(chunks):
        expected = window.first_chunk + ordinal
        if not isinstance(chunk, dict):
            reasons.append(f"chunk {expected} is not an object")
            continue
        if chunk.get("index") != expected:
            reasons.append(
                f"chunk {ordinal} has index {chunk.get('index')!r}, expected {expected}"
            )
        if not isinstance(chunk.get("text"), str):
            reasons.append(f"chunk {expected} has non-string text")
    return Validation(not reasons, tuple(reasons))


def _utterance_spans(text: str) -> list[tuple[str | None, int, int]]:
    labels = list(SPEAKER_LABEL_RE.finditer(text))
    if not labels:
        return [(None, 0, len(text))]
    spans: list[tuple[str | None, int, int]] = []
    if text[: labels[0].start()].strip():
        spans.append((None, 0, labels[0].start()))
    for ordinal, label in enumerate(labels):
        end = labels[ordinal + 1].start() if ordinal + 1 < len(labels) else len(text)
        spans.append((label.group(1), label.end(), end))
    return spans


def streaming_groups(
    chunk_texts: list[str], first_chunk: int = 0
) -> list[dict[str, Any]]:
    """Split concatenated streaming text into speaker-labelled rows.

    Speaker labels may straddle chunk boundaries, so parsing runs over the
    joined text and each sentence is mapped back to the chunks that emitted
    its first and last characters.
    """

    joined = NON_SPEECH_MARKER_RE.sub(
        lambda marker: " " * len(marker.group()), "".join(chunk_texts)
    )
    offsets: list[int] = []
    cursor = 0
    for text in chunk_texts:
        offsets.append(cursor)
        cursor += len(text)

    def chunk_at(position: int) -> int:
        return first_chunk + bisect.bisect_right(offsets, position) - 1

    groups: list[dict[str, Any]] = []
    for speaker, begin, end in _utterance_spans(joined):
        current: dict[str, Any] | None = None
        for match in SENTENCE_RE.finditer(joined, begin, end):
            piece = match.group()
            stripped = " ".join(piece.split())
            if not stripped:
                continue
            first = chunk_at(match.start() + len(piece) - len(piece.lstrip()))
            last = chunk_at(match.start() + len(piece.rstrip()) - 1)
            if current is not None and (
                first - current["last_chunk"] > 1
                or (last + 1 - current["first_chunk"]) * CHUNK_SECONDS > ROW_MAX_SECONDS
            ):
                groups.append(current)
                current = None
            if current is None:
                current = {
                    "speaker": speaker,
                    "first_chunk": first,
                    "last_chunk": last,
                    "sentences": [stripped],
                }
            else:
                current["last_chunk"] = last
                current["sentences"].append(stripped)
        if current is not None:
            groups.append(current)
    return groups


def track_speaker(track: str) -> str:
    return {"near": "Thomas", "far": "Remote", "mix": "Mixed"}.get(track, "Unknown")


def session_rows(
    result: dict[str, Any],
    window: Window,
    raw_path: str,
    support: Callable[[str, float, float], dict[str, float]],
    max_new_tokens: int,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    """Return transcript rows and low-channel-support rows withheld from them.

    The channel fixes the speaker. The model's speaker id is kept only as a
    session-local hint. Decoder loops and chunks that exhausted their token
    budget become unavailable rows.
    """

    chunks = result["chunks"]
    capped = {
        int(chunk["index"])
        for chunk in chunks
        if int(chunk.get("decoded_token_count", 0)) >= max_new_tokens
    }
    rows: list[dict[str, Any]] = []
    withheld: list[dict[str, Any]] = []
    groups = streaming_groups(
        [str(chunk["text"]) for chunk in chunks], window.first_chunk
    )
    for ordinal, group in enumerate(groups):
        text = " ".join(group["sentences"])
        if is_non_speech(text):
            continue
        start, _ = window.chunk_span(group["first_chunk"])
        _, end = window.chunk_span(group["last_chunk"])
        row = {
            "source_id": f"{window.track}-c{window.first_chunk:06d}-s{ordinal:03d}",
            "track": window.track,
            "speaker": track_speaker(window.track),
            "start": round(start, 3),
            "end": round(end, 3),
            "text": text,
            "kind": "unavailable" if is_unavailable(text) else "speech",
            "channel_activity": None,
            "time_resolution_seconds": round(CHUNK_SECONDS, 4),
            "source_chunks": [group["first_chunk"], group["last_chunk"]],
            "source_raw": raw_path,
            "asr_speaker_id_session_local": group["speaker"],
        }
        reasons = []
        loop = decoder_loop_reason(text)
        if loop:
            reasons.append(f"decoder loop: {loop}")
        exhausted = sorted(
            index
            for index in capped
            if group["first_chunk"] <= index <= group["last_chunk"]
        )
        if exhausted:
            reasons.append(f"chunks {exhausted} exhausted {max_new_tokens} tokens")
        if reasons:
            row.update(
                {
                    "kind": "unavailable",
                    "asr_text": text,
                    "text": "[Speech unavailable; see review queue]",
                    "validation_reasons": reasons,
                }
            )
            rows.append(row)
            continue
        if row["kind"] == "speech":
            evidence = support(window.track, start, end)
            row["channel_activity"] = evidence
            if evidence["selected"] < MIN_CHANNEL_ACTIVITY:
                withheld.append(row)
                continue
        rows.append(row)
    return rows, withheld


def unavailable_row(
    window: Window, raw_path: str, reasons: Iterable[str]
) -> dict[str, Any]:
    return {
        "source_id": f"{window.track}-c{window.first_chunk:06d}-unavailable",
        "track": window.track,
        "speaker": track_speaker(window.track),
        "start": round(window.start, 3),
        "end": round(window.start + window.actual_seconds, 3),
        "text": "[Speech unavailable; see review queue]",
        "kind": "unavailable",
        "channel_activity": None,
        "time_resolution_seconds": round(CHUNK_SECONDS, 4),
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
