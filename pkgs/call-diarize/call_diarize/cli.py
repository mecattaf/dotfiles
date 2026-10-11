"""Command-line orchestration for streaming VibeVoice call transcription."""

from __future__ import annotations

import argparse
import gc
import hashlib
import os
import shutil
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from . import __version__
from .asr import ASR_MODEL, MODEL_ARTIFACT, VibeVoiceASR, gpu_probe, verify_checkpoint
from .cleanup import (
    MODELS,
    chat_completions_url,
    preflight_models,
    reduce_decisions,
    run_cleanup,
)
from .pipeline import (
    CHUNK_SECONDS,
    SESSION_CHUNKS,
    AudioActivity,
    Window,
    candidate_shards,
    format_time,
    load_json,
    mixed_lexical_conflicts,
    prepare_track,
    session_rows,
    sort_rows,
    unavailable_row,
    validate_asr_result,
    validate_capture_files,
    write_json_exclusive,
    write_text_final,
)


DEFAULT_INFERENCE_URL = "http://strix:8731"
DEFAULT_CONTEXT = (
    "English-language business call. Preserve personal names, organization names, "
    "acronyms, and technical vocabulary exactly as spoken."
)


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(
        prog="call-diarize",
        description=(
            "Turn near.wav, far.wav, and mix.wav in one call directory into a "
            "GPU-backed Thomas/Remote transcript with VibeVoice-ASR-Streaming-7B."
        ),
    )
    result.add_argument("call_dir", type=Path, help="recording directory")
    result.add_argument(
        "--force",
        action="store_true",
        help="rebuild final tool-owned artifacts; source recordings are never modified",
    )
    result.add_argument(
        "--hotwords",
        action="append",
        default=[],
        metavar="TEXT",
        help="call-specific names or vocabulary (repeatable)",
    )
    result.add_argument(
        "--hotwords-file",
        action="append",
        default=[],
        type=Path,
        metavar="PATH",
        help="UTF-8 file containing call-specific names or vocabulary (repeatable)",
    )
    result.add_argument(
        "--inference-endpoint",
        default=os.environ.get("CALL_DIARIZE_INFERENCE_URL", DEFAULT_INFERENCE_URL),
        metavar="URL",
        help=(
            "Halogen Flash base URL or its /v1/chat/completions URL "
            "(default: $CALL_DIARIZE_INFERENCE_URL or http://strix:8731)"
        ),
    )
    result.add_argument(
        "--inference-timeout",
        type=int,
        default=1200,
        help=argparse.SUPPRESS,
    )
    result.add_argument(
        "--max-new-tokens",
        type=int,
        default=256,
        help=argparse.SUPPRESS,
    )
    result.add_argument(
        "--version", action="version", version=f"%(prog)s {__version__}"
    )
    return result


def collect_hotwords(values: list[str], files: list[Path]) -> str:
    pieces = [DEFAULT_CONTEXT]
    pieces.extend(value.strip() for value in values if value.strip())
    for path in files:
        if not path.is_file():
            raise ValueError(f"hotwords file does not exist: {path}")
        text = path.read_text(encoding="utf-8").strip()
        if text:
            pieces.append(text)
    # The streaming prompt ends in a newline after this text; keep it one line.
    return " ".join(" ".join(pieces).split())


def _run_config(
    call_dir: Path, hotwords: str, max_new_tokens: int
) -> dict[str, Any]:
    sources = {}
    for name in ("near.wav", "far.wav", "mix.wav"):
        stat = (call_dir / name).stat()
        sources[name] = {"size": stat.st_size, "mtime_ns": stat.st_mtime_ns}
    return {
        "schema": 1,
        "pipeline_version": __version__,
        "hotwords_sha256": hashlib.sha256(hotwords.encode("utf-8")).hexdigest(),
        "sources": sources,
        "asr_model": ASR_MODEL,
        "max_new_tokens": max_new_tokens,
        "models": MODELS,
    }


def _ensure_run_config(raw_root: Path, expected: dict[str, Any]) -> None:
    path = raw_root / "run-config.json"
    if path.exists():
        actual = load_json(path)
        if actual != expected:
            raise RuntimeError(
                f"existing ASR evidence was produced with different inputs/options: {path}"
            )
        return
    write_json_exclusive(path, expected)


def _prepare_raw_root(
    call_dir: Path, expected_config: dict[str, Any] | None = None
) -> Path:
    """Resume compatible evidence or preserve an incompatible partial run.

    Successful chunk and cleanup records are expensive, immutable checkpoints.
    Reuse them only when their run configuration exactly matches the current
    sources and options. Evidence without that proof is preserved wholesale
    under a timestamped sibling before a new evidence root is created.
    """

    raw_root = call_dir / "asr-raw"
    transcript_path = call_dir / "transcript.md"
    raw_root_exists = raw_root.exists() or raw_root.is_symlink()
    resume = False
    if (
        raw_root_exists
        and not transcript_path.exists()
        and expected_config is not None
    ):
        config_path = raw_root / "run-config.json"
        if raw_root.is_dir() and config_path.is_file():
            try:
                resume = load_json(config_path) == expected_config
            except (OSError, ValueError):
                resume = False
    if resume:
        print(
            f"call-diarize: resuming compatible partial evidence: {raw_root}",
            flush=True,
        )
    elif raw_root_exists and not transcript_path.exists():
        timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
        quarantine_base = call_dir / f"asr-raw.stale-{timestamp}"
        quarantine = quarantine_base
        suffix = 2
        while quarantine.exists() or quarantine.is_symlink():
            quarantine = quarantine_base.with_name(
                f"{quarantine_base.name}-{suffix}"
            )
            suffix += 1
        shutil.move(str(raw_root), str(quarantine))
        print(
            f"call-diarize: quarantined partial evidence: {raw_root} -> {quarantine}",
            flush=True,
        )
    raw_root.mkdir(parents=True, exist_ok=True)
    return raw_root


def _load_or_transcribe(
    engine: VibeVoiceASR,
    window: Window,
    hotwords: str,
    raw_root: Path,
) -> tuple[dict[str, Any], str]:
    relative = Path(window.key)
    path = raw_root / relative
    expected = window.request_identity(hotwords)
    if path.exists():
        value = load_json(path)
        if value.get("request") != expected:
            raise RuntimeError(f"cached ASR request identity mismatch: {path}")
        print(f"ASR cached {window.track} session at {window.start:.2f}s", flush=True)
        return value, str(relative)
    print(
        f"ASR {window.track} session at {window.start:.2f}s "
        f"({window.chunk_count} chunks, {window.actual_seconds:.2f}s audio)",
        flush=True,
    )
    value = engine.transcribe(window, hotwords)
    write_json_exclusive(path, value)
    runtime = value["runtime"]
    print(
        f"ASR done in {runtime['generation_seconds']:.1f}s "
        f"({runtime['realtime_factor']:.2f}x realtime, "
        f"peak {runtime['peak_gpu_memory_bytes'] / 2**30:.1f} GiB allocated)",
        flush=True,
    )
    return value, str(relative)


def _process_session(
    window: Window,
    engine: VibeVoiceASR,
    hotwords: str,
    raw_root: Path,
    activity: AudioActivity,
    max_new_tokens: int,
    rows: list[dict[str, Any]],
    withheld: list[dict[str, Any]],
    rejections: list[dict[str, Any]],
    runtime_records: list[dict[str, Any]],
) -> None:
    result, raw_path = _load_or_transcribe(engine, window, hotwords, raw_root)
    runtime = result.get("runtime")
    if not isinstance(runtime, dict):
        raise RuntimeError(f"ASR result lacks GPU runtime evidence: {raw_path}")
    runtime_records.append(runtime)
    validation = validate_asr_result(result, window)
    if not validation.accepted:
        rejections.append(
            {
                "track": window.track,
                "global_start": round(window.start, 3),
                "global_end": round(window.start + window.actual_seconds, 3),
                "raw": raw_path,
                "reasons": list(validation.reasons),
            }
        )
        print(
            f"rejected {window.track} session at {window.start:.2f}s: "
            + "; ".join(validation.reasons),
            flush=True,
        )
        rows.append(unavailable_row(window, raw_path, validation.reasons))
        return
    accepted, low_support = session_rows(
        result, window, raw_path, activity.support, max_new_tokens
    )
    rows.extend(accepted)
    withheld.extend(low_support)


def _render_transcript(rows: list[dict[str, Any]], manifest: dict[str, Any]) -> str:
    lines = [
        "# Call transcript",
        "",
        (
            "Generated locally with GPU-backed VibeVoice-ASR-Streaming-7B. Thomas is "
            "fixed by the near channel; Remote is the combined far channel. "
            "Simultaneous rows are retained."
        ),
        "",
        (
            f"Streaming ASR emits no timestamps: times are {CHUNK_SECONDS:.3f} s chunk "
            "bounds and may trail speech by one chunk. Sessions: "
            f"{manifest['session_counts']['near']} near, "
            f"{manifest['session_counts']['far']} far, "
            f"{manifest['session_counts']['mix']} mixed."
        ),
        "",
    ]
    marked_failure_shards: set[str] = set()
    for row in rows:
        cleanup_failures = row.get("cleanup_failures", [])
        failed_shards = sorted(
            {str(failure["shard_id"]) for failure in cleanup_failures}
        )
        for shard_id in failed_shards:
            if shard_id not in marked_failure_shards:
                lines.extend([f"<!-- cleanup-failed shard-{shard_id} -->", ""])
                marked_failure_shards.add(shard_id)
        if failed_shards:
            label = "raw; cleanup-failed " + ",".join(
                f"shard-{shard_id}" for shard_id in failed_shards
            )
        else:
            label = "unavailable" if row["kind"] == "unavailable" else "speech"
        lines.extend(
            [
                (
                    f"**[{format_time(row['start'])}–{format_time(row['end'])}] "
                    f"{row['speaker']} ({label}):** {row['text']}"
                ),
                "",
            ]
        )
    if not rows:
        lines.extend(
            [
                "_No speech was detected in the near or far recording channels._",
                "",
            ]
        )
    return "\n".join(lines).rstrip() + "\n"


def _review_item(prefix: str, item: dict[str, Any]) -> list[str]:
    return [
        (
            f"- {prefix} `{item.get('source_id', item.get('raw', 'unknown'))}` "
            f"[{format_time(float(item['start'] if 'start' in item else item['global_start']))}–"
            f"{format_time(float(item['end'] if 'end' in item else item['global_end']))}]"
        ),
        "  - "
        + (
            "; ".join(item.get("validation_reasons") or item.get("reasons", []))
            or item.get("isolated_text")
            or item.get("text", "")
        ),
    ]


def _render_review(
    rejections: list[dict[str, Any]],
    final_unavailable: list[dict[str, Any]],
    cleanup_failures: list[dict[str, Any]],
    lexical_conflicts: list[dict[str, Any]],
    dropped: list[dict[str, Any]],
    low_support: list[dict[str, Any]],
) -> str:
    failed_shards = {str(failure["shard_id"]) for failure in cleanup_failures}
    lines = [
        "# Call transcript review queue",
        "",
        "This file is generated evidence. Recording WAVs and raw ASR JSON were not modified.",
        "",
        "## Summary",
        "",
        f"- Rejected streaming ASR sessions: {len(rejections)}",
        f"- Final unavailable spans: {len(final_unavailable)}",
        f"- Cleanup model/shard failures: {len(cleanup_failures)}",
        f"- Raw-ASR fallback shards: {len(failed_shards)}",
        f"- Low-channel-support rows withheld from the transcript: {len(low_support)}",
        f"- Near/far versus mixed lexical conflicts: {len(lexical_conflicts)}",
        f"- Proven duplicates removed: {len(dropped)}",
        "",
        "## Final unavailable spans",
        "",
    ]
    if final_unavailable:
        for item in final_unavailable:
            lines.extend(_review_item("unavailable", item))
            if item.get("asr_text"):
                lines.append(f"  - ASR text: {item['asr_text']}")
    else:
        lines.append("None.")

    lines.extend(["", "## Cleanup raw-ASR fallbacks", ""])
    if cleanup_failures:
        for failure in cleanup_failures:
            lines.extend(
                [
                    (
                        f"- shard-{failure['shard_id']} `{failure['label']}` "
                        f"({failure['model']}): kept {len(failure['candidate_ids'])} "
                        "raw candidate(s)."
                    ),
                    f"  - Evidence: `{failure['evidence_path']}`",
                ]
            )
    else:
        lines.append("None.")

    lines.extend(["", "## Withheld low-channel-support rows", ""])
    if low_support:
        for item in low_support:
            lines.extend(
                [
                    (
                        f"- `{item['source_raw']}` [{format_time(item['start'])}–"
                        f"{format_time(item['end'])}] {item['speaker']} channel activity "
                        f"{item['channel_activity']['selected']:.3f}"
                    ),
                    f"  - {item['text']}",
                ]
            )
    else:
        lines.append("None.")

    lines.extend(["", "## Mixed-track lexical conflicts", ""])
    if lexical_conflicts:
        for item in lexical_conflicts:
            lines.extend(_review_item("lexical conflict", item))
            lines.append(
                f"  - Mixed cross-check ({item['isolated_token_recall_from_mix']:.3f} recall): "
                f"{item['mixed_text']}"
            )
    else:
        lines.append("None.")

    lines.extend(["", "## Proven duplicate drops", ""])
    if dropped:
        for item in dropped:
            lines.extend(_review_item("duplicate", item))
            lines.append(f"  - Matched earlier source `{item['duplicate_of']}`.")
    else:
        lines.append("None.")
    return "\n".join(lines).rstrip() + "\n"


def _publish(path: Path, text: str, force: bool) -> None:
    if path.exists() and path.read_text(encoding="utf-8") == text:
        return
    write_text_final(path, text, force)


def execute(args: argparse.Namespace) -> int:
    call_dir = args.call_dir.expanduser().resolve()
    transcript_path = call_dir / "transcript.md"
    review_path = call_dir / "review-queue.md"
    if transcript_path.exists() and not args.force:
        print(
            f"call-diarize: transcript already exists, nothing to do: {transcript_path}"
        )
        return 0
    if not call_dir.is_dir():
        raise ValueError(f"call directory does not exist: {call_dir}")
    if review_path.exists() and not args.force:
        # A matching partial publication is accepted later; an unrelated file
        # remains protected by the final content comparison.
        print(
            f"call-diarize: found partial review artifact; it will be verified: {review_path}"
        )

    durations = validate_capture_files(call_dir)
    hotwords = collect_hotwords(args.hotwords, args.hotwords_file)
    model_dir = MODEL_ARTIFACT
    verify_checkpoint(model_dir)

    inference_endpoint = chat_completions_url(args.inference_endpoint)
    advertised_models = preflight_models(inference_endpoint)
    gpu = gpu_probe()
    print(
        f"GPU gate: {gpu['device_name']} · Torch {gpu['torch_version']} · ROCm {gpu['rocm_version']}",
        flush=True,
    )

    run_config = _run_config(call_dir, hotwords, args.max_new_tokens)
    raw_root = _prepare_raw_root(call_dir, run_config)
    _ensure_run_config(raw_root, run_config)

    rows_by_track: dict[str, list[dict[str, Any]]] = {
        "near": [],
        "far": [],
        "mix": [],
    }
    low_support: list[dict[str, Any]] = []
    rejections: list[dict[str, Any]] = []
    runtime_records: list[dict[str, Any]] = []

    with tempfile.TemporaryDirectory(prefix="call-diarize-") as temporary:
        temp_root = Path(temporary)
        sessions = {
            track: prepare_track(call_dir / f"{track}.wav", track, temp_root)
            for track in ("near", "far", "mix")
        }
        with AudioActivity(call_dir) as activity:
            engine = VibeVoiceASR(model_dir, max_new_tokens=args.max_new_tokens)
            try:
                for track in ("near", "far", "mix"):
                    for window in sessions[track]:
                        _process_session(
                            window,
                            engine,
                            hotwords,
                            raw_root,
                            activity,
                            args.max_new_tokens,
                            rows_by_track[track],
                            # Mixed rows only cross-check the isolated channels.
                            low_support if track != "mix" else [],
                            rejections,
                            runtime_records,
                        )
            finally:
                engine.close()
                del engine
                gc.collect()

    isolated = sort_rows(rows_by_track["near"] + rows_by_track["far"])
    final_unavailable = [
        row
        for track in ("near", "far", "mix")
        for row in rows_by_track[track]
        if row["kind"] == "unavailable"
    ]
    lexical_conflicts = mixed_lexical_conflicts(isolated, rows_by_track["mix"])

    shards = candidate_shards(isolated, limit=10)
    row_index = {row["source_id"]: index for index, row in enumerate(isolated)}
    for shard in shards:
        first = row_index[shard["candidates"][0]["source_id"]]
        previous = isolated[first - 1] if first else None
        shard["previous_context"] = (
            {
                "source_id": previous["source_id"],
                "speaker_fixed_by_channel": previous["speaker"],
                "text": previous["text"],
            }
            if previous
            else None
        )
    decisions, cleanup_failures = run_cleanup(
        shards,
        isolated,
        raw_root,
        inference_endpoint,
        args.inference_timeout,
    )
    cleaned, dropped = reduce_decisions(isolated, decisions, cleanup_failures)

    session_counts = {track: len(windows) for track, windows in sessions.items()}
    generation_seconds = sum(
        float(item.get("generation_seconds", 0)) for item in runtime_records
    )
    audio_seconds = sum(float(item.get("audio_seconds", 0)) for item in runtime_records)
    raw_fallback_shards = {
        str(failure["shard_id"]) for failure in cleanup_failures
    }
    raw_fallback_candidates = {
        str(source_id)
        for failure in cleanup_failures
        for source_id in failure["candidate_ids"]
    }
    manifest = {
        "schema": 1,
        "pipeline_version": __version__,
        "method": (
            "VibeVoice-ASR-Streaming-7B live-style decoding of near/far/mix in "
            f"{SESSION_CHUNKS}-chunk sessions; chunk-resolution times"
        ),
        "call_dir": str(call_dir),
        "recording_durations": durations,
        "gpu": gpu,
        "asr_model": ASR_MODEL,
        "cleanup_models": MODELS,
        "inference_endpoint": inference_endpoint,
        "inference_advertised_model_count": len(advertised_models),
        "session_counts": session_counts,
        "rejected_session_count": len(rejections),
        "final_unavailable_count": len(final_unavailable),
        "isolated_candidate_count": len(isolated),
        "published_row_count": len(cleaned),
        "proven_duplicate_drop_count": len(dropped),
        "low_support_withheld_count": len(low_support),
        "cleanup_failure_count": len(cleanup_failures),
        "raw_fallback_shard_count": len(raw_fallback_shards),
        "raw_fallback_candidate_count": len(raw_fallback_candidates),
        "cleanup_failures": cleanup_failures,
        "asr_generation_seconds": round(generation_seconds, 3),
        "asr_audio_seconds": round(audio_seconds, 3),
        "asr_realtime_factor": round(generation_seconds / max(audio_seconds, 0.001), 3),
        "asr_peak_gpu_memory_bytes": max(
            (int(item.get("peak_gpu_memory_bytes", 0)) for item in runtime_records),
            default=0,
        ),
        "all_inference_gpu_backed": bool(runtime_records)
        and all(
            item.get("device_name") == gpu["device_name"] for item in runtime_records
        ),
    }
    if not manifest["all_inference_gpu_backed"]:
        raise RuntimeError("ASR runtime evidence did not prove GPU-backed inference")

    manifest_path = raw_root / "manifest.json"
    if manifest_path.exists():
        if load_json(manifest_path) != manifest:
            raise RuntimeError(
                f"refusing to overwrite different run manifest: {manifest_path}"
            )
    else:
        write_json_exclusive(manifest_path, manifest)

    review = _render_review(
        rejections,
        final_unavailable,
        cleanup_failures,
        lexical_conflicts,
        dropped,
        low_support,
    )
    transcript = _render_transcript(cleaned, manifest)
    _publish(review_path, review, args.force)
    _publish(transcript_path, transcript, args.force)
    print(
        f"wrote {transcript_path} ({len(cleaned)} rows) and {review_path}; "
        f"ASR {manifest['asr_realtime_factor']:.2f}x realtime on {gpu['device_name']}",
        flush=True,
    )
    return 0


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    try:
        return execute(args)
    except KeyboardInterrupt:
        print("call-diarize: interrupted", file=sys.stderr)
        return 130
    except Exception as exc:
        print(f"call-diarize: error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
