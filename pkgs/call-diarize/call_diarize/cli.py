"""Command-line orchestration for the frozen VibeVoice fusion pipeline."""

from __future__ import annotations

import argparse
import gc
import hashlib
import math
import os
import shutil
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from . import __version__
from .asr import VibeVoiceASR, ensure_model_layout, gpu_probe
from .cleanup import MODELS, preflight_models, reduce_consensus, run_both_models
from .pipeline import (
    AudioActivity,
    Validation,
    Window,
    candidate_shards,
    format_time,
    load_json,
    mixed_lexical_conflicts,
    segment_track,
    segments_to_rows,
    slice_track,
    sort_rows,
    unavailable_row,
    validate_asr_result,
    validate_capture_files,
    write_json_exclusive,
    write_text_final,
)


DEFAULT_ENDPOINT = "http://127.0.0.1:9292/v1/chat/completions"
DEFAULT_CONTEXT = (
    "English-language business call. Preserve personal names, organization names, "
    "acronyms, and technical vocabulary exactly as spoken."
)


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(
        prog="call-diarize",
        description=(
            "Turn near.wav, far.wav, and mix.wav in one call directory into a "
            "GPU-backed Thomas/Remote transcript."
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
        "--llama-swap-endpoint",
        default=os.environ.get("CALL_DIARIZE_LLAMA_SWAP_ENDPOINT", DEFAULT_ENDPOINT),
        help=argparse.SUPPRESS,
    )
    result.add_argument(
        "--llama-timeout",
        type=int,
        default=1200,
        help=argparse.SUPPRESS,
    )
    result.add_argument(
        "--max-new-tokens",
        type=int,
        default=1024,
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
    return "\n".join(pieces)


def _state_root() -> Path:
    configured = os.environ.get("CALL_DIARIZE_STATE_ROOT")
    if configured:
        return Path(configured).expanduser()
    xdg = os.environ.get("XDG_STATE_HOME")
    if xdg:
        return Path(xdg).expanduser() / "call-diarize"
    home = os.environ.get("HOME")
    if not home:
        raise RuntimeError("HOME or XDG_STATE_HOME is required for call-diarize state")
    return Path(home) / ".local" / "state" / "call-diarize"


def _support_dir() -> Path:
    configured = os.environ.get("CALL_DIARIZE_MODEL_SUPPORT")
    if not configured:
        raise RuntimeError("launcher did not set CALL_DIARIZE_MODEL_SUPPORT")
    return Path(configured)


def _run_config(call_dir: Path, hotwords: str) -> dict[str, Any]:
    sources = {}
    for name in ("near.wav", "far.wav", "mix.wav"):
        stat = (call_dir / name).stat()
        sources[name] = {"size": stat.st_size, "mtime_ns": stat.st_mtime_ns}
    return {
        "schema": 1,
        "pipeline_version": __version__,
        "hotwords_sha256": hashlib.sha256(hotwords.encode("utf-8")).hexdigest(),
        "sources": sources,
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
        print(
            f"ASR cached {window.track} {window.start:.2f}s/{window.nominal_seconds}s",
            flush=True,
        )
        return value, str(relative)
    print(
        f"ASR {window.track} {window.start:.2f}s/{window.nominal_seconds}s "
        f"({window.actual_seconds:.2f}s audio)",
        flush=True,
    )
    value = engine.transcribe(window, hotwords)
    write_json_exclusive(path, value)
    runtime = value["runtime"]
    print(
        f"ASR done in {runtime['generation_seconds']:.1f}s "
        f"({runtime['realtime_factor']:.2f}x realtime, {runtime['generated_tokens']} tokens)",
        flush=True,
    )
    return value, str(relative)


def _process_tree(
    initial: Window,
    levels: list[int],
    source: Path,
    temp_root: Path,
    engine: VibeVoiceASR,
    hotwords: str,
    raw_root: Path,
    activity: AudioActivity,
    selected: list[tuple[Window, dict[str, Any], str]],
    unavailable: list[tuple[Window, str, Validation]],
    rejections: list[dict[str, Any]],
    runtime_records: list[dict[str, Any]],
) -> None:
    level_index = levels.index(initial.nominal_seconds)

    def visit(window: Window, index: int) -> None:
        result, raw_path = _load_or_transcribe(engine, window, hotwords, raw_root)
        runtime = result.get("runtime")
        if not isinstance(runtime, dict):
            raise RuntimeError(f"ASR result lacks GPU runtime evidence: {raw_path}")
        runtime_records.append(runtime)
        validation = validate_asr_result(result, window, activity.support)
        if validation.accepted:
            selected.append((window, result, raw_path))
            return

        rejection = {
            "track": window.track,
            "global_start": round(window.start, 3),
            "global_end": round(window.start + window.actual_seconds, 3),
            "resolution_seconds": window.nominal_seconds,
            "raw": raw_path,
            "reasons": list(validation.reasons),
            "low_channel_support_rows": list(validation.low_support_rows),
        }
        rejections.append(rejection)
        print(
            f"rejected {window.track} {window.start:.2f}s/{window.nominal_seconds}s: "
            + "; ".join(validation.reasons),
            flush=True,
        )

        if index + 1 >= len(levels):
            unavailable.append((window, raw_path, validation))
            return
        child_seconds = levels[index + 1]
        # A short tail is already no longer than the next retry size; slicing it
        # again would submit identical audio and is not recursive refinement.
        if window.actual_seconds <= child_seconds + 0.001:
            unavailable.append((window, raw_path, validation))
            return
        child_count = max(1, math.ceil((window.actual_seconds - 0.001) / child_seconds))
        for child_index in range(child_count):
            child_start = window.start + child_index * child_seconds
            if child_start >= window.start + window.actual_seconds - 0.001:
                continue
            child = slice_track(
                source,
                window.track,
                child_start,
                child_seconds,
                temp_root,
            )
            visit(child, index + 1)

    visit(initial, level_index)


def _rows_from_selected(
    selected: list[tuple[Window, dict[str, Any], str]],
    activity: AudioActivity,
) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for window, result, raw_path in selected:
        rows.extend(segments_to_rows(result, window, raw_path, activity.support))
    return sort_rows(rows)


def _render_transcript(rows: list[dict[str, Any]], manifest: dict[str, Any]) -> str:
    lines = [
        "# Call transcript",
        "",
        (
            "Generated locally with GPU-backed VibeVoice-ASR. Thomas is fixed by the near "
            "channel; Remote is the combined far channel. Simultaneous rows are retained."
        ),
        "",
        (
            f"ASR leaves: {manifest['leaf_counts']['60']}×60 s, "
            f"{manifest['leaf_counts']['30']}×30 s, {manifest['leaf_counts']['15']}×15 s."
        ),
        "",
    ]
    for row in rows:
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
        f"  - {item.get('text') or item.get('isolated_text') or '; '.join(item.get('reasons', []))}",
    ]


def _render_review(
    rejections: list[dict[str, Any]],
    final_unavailable: list[dict[str, Any]],
    disagreements: list[dict[str, Any]],
    lexical_conflicts: list[dict[str, Any]],
    dropped: list[dict[str, Any]],
) -> str:
    low_support = [
        {**row, "raw": rejection["raw"]}
        for rejection in rejections
        for row in rejection["low_channel_support_rows"]
    ]
    lines = [
        "# Call transcript review queue",
        "",
        "This file is generated evidence. Recording WAVs and raw ASR JSON were not modified.",
        "",
        "## Summary",
        "",
        f"- Rejected ASR windows across all retry levels: {len(rejections)}",
        f"- Final unavailable spans: {len(final_unavailable)}",
        f"- Low-channel-support rows seen in rejected windows: {len(low_support)}",
        f"- Gemma/Qwen decision disagreements: {len(disagreements)}",
        f"- Near/far versus mixed lexical conflicts: {len(lexical_conflicts)}",
        f"- Consensus duplicates removed: {len(dropped)}",
        "",
        "## Final unavailable spans",
        "",
    ]
    if final_unavailable:
        for item in final_unavailable:
            lines.extend(_review_item("unavailable", item))
    else:
        lines.append("None.")

    lines.extend(["", "## Low-channel-support rows", ""])
    if low_support:
        for item in low_support:
            lines.extend(
                [
                    (
                        f"- `{item['raw']}` [{format_time(item['global_start'])}–"
                        f"{format_time(item['global_end'])}] selected activity "
                        f"{item['activity']['selected']:.3f}"
                    ),
                    f"  - {item['text']}",
                ]
            )
    else:
        lines.append("None.")

    lines.extend(["", "## Cleanup-model disagreements", ""])
    if disagreements:
        for item in disagreements:
            lines.extend(_review_item("disagreement", item))
            lines.append(
                f"  - Gemma: `{item['gemma']['action']}`; Qwen: `{item['qwen']['action']}`"
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

    lines.extend(["", "## Consensus duplicate drops", ""])
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
    state_root = _state_root()
    support_dir = _support_dir()
    model_dir = ensure_model_layout(state_root, support_dir)

    advertised_models = preflight_models(args.llama_swap_endpoint)
    gpu = gpu_probe()
    print(
        f"GPU gate: {gpu['device_name']} · Torch {gpu['torch_version']} · ROCm {gpu['rocm_version']}",
        flush=True,
    )

    run_config = _run_config(call_dir, hotwords)
    raw_root = _prepare_raw_root(call_dir, run_config)
    _ensure_run_config(raw_root, run_config)

    selected_by_track: dict[str, list[tuple[Window, dict[str, Any], str]]] = {
        "near": [],
        "far": [],
        "mix": [],
    }
    unavailable_by_track: dict[str, list[tuple[Window, str, Validation]]] = {
        "near": [],
        "far": [],
        "mix": [],
    }
    rejections: list[dict[str, Any]] = []
    runtime_records: list[dict[str, Any]] = []

    with tempfile.TemporaryDirectory(prefix="call-diarize-") as temporary:
        temp_root = Path(temporary)
        initial = {
            "near": segment_track(call_dir / "near.wav", "near", 60, temp_root),
            "far": segment_track(call_dir / "far.wav", "far", 60, temp_root),
            "mix": segment_track(call_dir / "mix.wav", "mix", 30, temp_root),
        }
        with AudioActivity(call_dir) as activity:
            engine = VibeVoiceASR(model_dir, max_new_tokens=args.max_new_tokens)
            try:
                for track in ("near", "far", "mix"):
                    levels = [60, 30, 15] if track != "mix" else [30, 15]
                    for window in initial[track]:
                        _process_tree(
                            window,
                            levels,
                            call_dir / f"{track}.wav",
                            temp_root,
                            engine,
                            hotwords,
                            raw_root,
                            activity,
                            selected_by_track[track],
                            unavailable_by_track[track],
                            rejections,
                            runtime_records,
                        )
            finally:
                engine.close()
                del engine
                gc.collect()

            isolated = _rows_from_selected(
                selected_by_track["near"] + selected_by_track["far"], activity
            )
            final_unavailable = []
            for track in ("near", "far", "mix"):
                for window, raw_path, validation in unavailable_by_track[track]:
                    row = unavailable_row(window, raw_path, validation.reasons)
                    if track != "mix":
                        isolated.append(row)
                    final_unavailable.append(row)
            isolated = sort_rows(isolated)

            mixed = _rows_from_selected(selected_by_track["mix"], activity)
            lexical_conflicts = mixed_lexical_conflicts(isolated, mixed)

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
    decisions = run_both_models(
        shards,
        isolated,
        raw_root,
        args.llama_swap_endpoint,
        args.llama_timeout,
    )
    cleaned, dropped, disagreements = reduce_consensus(isolated, decisions)

    leaf_counts = {"60": 0, "30": 0, "15": 0}
    for selected in selected_by_track.values():
        for window, _, _ in selected:
            leaf_counts[str(window.nominal_seconds)] += 1
    generation_seconds = sum(
        float(item.get("generation_seconds", 0)) for item in runtime_records
    )
    audio_seconds = sum(float(item.get("audio_seconds", 0)) for item in runtime_records)
    manifest = {
        "schema": 1,
        "pipeline_version": __version__,
        "method": "VibeVoice near/far 60s + mixed 30s; rejected windows recurse to 30s/15s",
        "call_dir": str(call_dir),
        "recording_durations": durations,
        "gpu": gpu,
        "llama_swap_models": MODELS,
        "llama_swap_advertised_model_count": len(advertised_models),
        "leaf_counts": leaf_counts,
        "rejected_window_count": len(rejections),
        "final_unavailable_count": len(final_unavailable),
        "isolated_candidate_count": len(isolated),
        "published_row_count": len(cleaned),
        "consensus_duplicate_drop_count": len(dropped),
        "asr_generation_seconds": round(generation_seconds, 3),
        "asr_audio_seconds": round(audio_seconds, 3),
        "asr_realtime_factor": round(generation_seconds / max(audio_seconds, 0.001), 3),
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
        disagreements,
        lexical_conflicts,
        dropped,
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
