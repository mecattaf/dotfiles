"""Command-line front door for the acquisition cascade."""

from __future__ import annotations

import argparse
import json
import os
import re
import socket
import sys
import time
import unicodedata
from pathlib import Path
from typing import Any, Iterable

from . import __version__
from .backend import LiveBackend
from .state import BatchState, all_batch_statuses
from .verification import norm


DEFAULT_STATE_ROOT = Path("~/.local/state/music-acquire")
DEFAULT_CAMPAIGN_REPO = Path("~/mecattaf/music-consolidation")
DEFAULT_STAGING = Path("/mnt/nas/music-staging/_ingest")


def slug(value: str) -> str:
    text = unicodedata.normalize("NFKD", value)
    text = "".join(char for char in text if not unicodedata.combining(char))
    text = re.sub(r"[^A-Za-z0-9]+", "-", text.lower()).strip("-")
    return text[:80] or "batch"


def load_jsonl(path: Path) -> list[dict[str, Any]]:
    rows = []
    with path.open(encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, 1):
            if not line.strip():
                continue
            try:
                row = json.loads(line)
            except json.JSONDecodeError as error:
                raise ValueError(f"{path}:{line_number}: {error}") from error
            if not isinstance(row, dict):
                raise ValueError(f"{path}:{line_number}: expected a JSON object")
            rows.append(row)
    return rows


def tracklist_items(path: Path, source_filter: str | None = None) -> list[dict[str, Any]]:
    merged: dict[str, dict[str, Any]] = {}
    order: list[str] = []
    for row in load_jsonl(path):
        appearances = list(row.get("appearances") or [])
        if source_filter and not any(
            appearance.get("source") == source_filter for appearance in appearances
        ):
            continue
        item_id = str(row.get("key") or row.get("id") or norm(row.get("query") or ""))
        if not item_id:
            raise ValueError("tracklist row has no key, id, or usable query")
        source = source_filter or (
            appearances[0].get("source") if len({a.get("source") for a in appearances}) == 1 else "mixed"
        )
        item = {
            **row,
            "id": item_id,
            "key": row.get("key") or item_id,
            "source": f"tracklist:{source}",
            "appearances": appearances,
        }
        if item_id not in merged:
            merged[item_id] = item
            order.append(item_id)
            continue
        current = merged[item_id]
        seen = {
            json.dumps(appearance, sort_keys=True, ensure_ascii=False)
            for appearance in current.get("appearances") or []
        }
        for appearance in appearances:
            key = json.dumps(appearance, sort_keys=True, ensure_ascii=False)
            if key not in seen:
                current.setdefault("appearances", []).append(appearance)
                seen.add(key)
    return [merged[item_id] for item_id in order]


def _without_status(outcome: dict[str, Any]) -> dict[str, Any]:
    return {key: value for key, value in outcome.items() if key != "status" and value is not None}


class Acquirer:
    """Deterministic orchestration over an injectable acquisition backend."""

    def __init__(
        self,
        state: BatchState,
        backend: Any,
        *,
        limit: int = 0,
        backoff_seconds: float | None = None,
        dry_limit: int | None = None,
    ):
        self.state = state
        self.backend = backend
        self.limit = max(0, limit)
        self.backoff_seconds = (
            float(os.environ.get("MUSIC_ACQUIRE_BACKOFF", "3600"))
            if backoff_seconds is None
            else backoff_seconds
        )
        self.dry_limit = (
            int(os.environ.get("MUSIC_ACQUIRE_DRY_LIMIT", "4"))
            if dry_limit is None
            else dry_limit
        )
        self.dry_streak = 0
        self.final = state.final_rows()

    def _record(self, item: dict[str, Any], disposition: str, **fields: Any):
        row = self.state.record(item, disposition, **fields)
        self.final[str(item["id"])] = row
        if disposition.startswith("ok_"):
            self.dry_streak = 0
            self.backend.remember(item, row)
        elif disposition == "retryable" and fields.get("reason") in {
            "throttled_during_search",
            "throttled_during_verification",
            "no_audio_fetched_for_any_candidate",
        }:
            self.dry_streak += 1
            if self.dry_streak >= self.dry_limit:
                self.state.append(
                    {
                        "record": "event",
                        "ts": row["ts"],
                        "event": "backoff",
                        "reason": "consecutive_dry_attempts",
                        "seconds": self.backoff_seconds,
                    }
                )
                self.dry_streak = 0
                if self.backoff_seconds > 0:
                    time.sleep(self.backoff_seconds)
        return row

    def _duplicate(self, item: dict[str, Any], track: dict[str, Any] | None = None):
        duplicate = self.backend.duplicate(item, track)
        if duplicate:
            return self._record(item, "skipped_duplicate", **duplicate)
        return None

    @staticmethod
    def _sc_fields(track: dict[str, Any]) -> dict[str, Any]:
        if track.get("segment"):
            return {
                "sc_id": None,
                "sc_parent_id": str(track["id"]),
                "sc_url": track.get("url"),
            }
        return {"sc_id": str(track["id"]), "sc_url": track.get("url")}

    def _direct_source(self, item: dict[str, Any], verb: str):
        if self._duplicate(item):
            return
        if verb == "bandcamp":
            outcome = self.backend.download_bandcamp(item)
            disposition = "ok_bandcamp"
        else:
            outcome = self.backend.download_ytmusic(item)
            disposition = "ok_youtube"
        status = outcome.get("status")
        if status == "ok":
            self._record(item, disposition, **_without_status(outcome))
        elif status == "gone":
            self._record(item, "gone", **_without_status(outcome))
        else:
            self._record(item, "retryable", **_without_status(outcome))

    def _cascade(self, item: dict[str, Any]):
        if self._duplicate(item):
            return
        previous = self.final.get(str(item["id"])) or {}
        if (
            previous.get("disposition") == "retryable"
            and previous.get("stage") == "youtube"
            and previous.get("reason") == "verified_but_download_failed"
            and previous.get("yt_id")
        ):
            youtube = self.backend.retry_youtube_download(item, previous)
            if youtube.get("status") == "ok":
                self._record(
                    item,
                    "ok_youtube",
                    sc_id=previous.get("sc_id"),
                    sc_url=previous.get("sc_url"),
                    **_without_status(youtube),
                )
            else:
                self._record(
                    item,
                    "retryable",
                    sc_id=previous.get("sc_id"),
                    sc_url=previous.get("sc_url"),
                    **_without_status(youtube),
                    stage="youtube",
                )
            return

        resolved = self.backend.resolve_soundcloud(item)
        status = resolved.get("status")
        if status == "retryable":
            self._record(item, "retryable", **_without_status(resolved))
            return
        if status == "gone":
            self._record(item, "gone", **_without_status(resolved))
            return

        track = resolved.get("track") if status == "found" else None
        if track and self._duplicate(item, track):
            return

        resume_capture = (
            previous.get("disposition") == "retryable"
            and previous.get("stage") == "capture"
        ) or (
            previous.get("disposition") == "fallthrough"
            and previous.get("reason") == "capture_unavailable"
        )
        if resume_capture and track:
            self._finish_capture(item, track, previous.get("stage2_reason"))
            return

        resume_youtube = (
            previous.get("disposition") == "retryable"
            and previous.get("stage") == "youtube"
        )
        if track and not resume_youtube:
            direct = self.backend.download_soundcloud(item, track)
            direct_status = direct.get("status")
            if direct_status == "ok":
                self._record(
                    item,
                    "ok_soundcloud",
                    **_without_status(direct),
                    **self._sc_fields(track),
                    verdict="source",
                    evidence={
                        "duration_s": round(
                            float(track.get("full_duration_ms") or 0) / 1000.0, 1
                        )
                    },
                )
                return
            if direct_status == "retryable":
                self._record(
                    item,
                    "retryable",
                    **_without_status(direct),
                    **self._sc_fields(track),
                    stage="soundcloud",
                )
                return

        youtube = self.backend.verify_youtube(item, track)
        youtube_status = youtube.get("status")
        common = self._sc_fields(track) if track else {"sc_id": None, "sc_url": None}
        if youtube_status == "ok":
            self._record(
                item, "ok_youtube", **common, **_without_status(youtube)
            )
            return
        if youtube_status == "retryable":
            self._record(
                item,
                "retryable",
                **common,
                **_without_status(youtube),
                stage="youtube",
            )
            return
        if not track:
            self._record(
                item, "fallthrough", **common, **_without_status(youtube)
            )
            return

        self._finish_capture(item, track, youtube.get("reason"), youtube)

    def _finish_capture(
        self,
        item: dict[str, Any],
        track: dict[str, Any],
        stage2_reason: str | None,
        youtube: dict[str, Any] | None = None,
    ) -> None:
        capture = self.backend.capture(item, track)
        capture_status = capture.get("status")
        common = self._sc_fields(track)
        if capture_status == "ok":
            self._record(
                item,
                "ok_capture",
                **common,
                **_without_status(capture),
                verdict="acoustic" if track.get("has_preview") else "capture",
            )
        elif capture_status == "retryable":
            self._record(
                item,
                "retryable",
                **common,
                **_without_status(capture),
                stage2_reason=stage2_reason,
                stage="capture",
            )
        else:
            fields = _without_status(capture)
            fields.setdefault("reason", "capture_unavailable")
            fields["stage2_reason"] = stage2_reason
            if youtube and youtube.get("candidates"):
                fields["stage2_candidates"] = youtube["candidates"]
            self._record(item, "fallthrough", **common, **fields)

    def run(self, items: Iterable[dict[str, Any]], verb: str) -> int:
        archived = self.state.archived()
        attempted = 0
        for item in items:
            if str(item["id"]) in archived:
                continue
            if self.limit and attempted >= self.limit:
                break
            if verb in {"bandcamp", "ytmusic"}:
                self._direct_source(item, verb)
            else:
                self._cascade(item)
            attempted += 1
            archived = self.state.archived()
        return attempted


def _common_parser() -> argparse.ArgumentParser:
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--batch", default=argparse.SUPPRESS)
    common.add_argument("--dry-run", action="store_true", default=argparse.SUPPRESS)
    common.add_argument("--limit", type=int, default=argparse.SUPPRESS)
    common.add_argument("--no-capture", action="store_true", default=argparse.SUPPRESS)
    common.add_argument("--out", type=Path, default=argparse.SUPPRESS)
    return common


def parser() -> argparse.ArgumentParser:
    common = _common_parser()
    root = argparse.ArgumentParser(
        prog="acquire",
        description="Land source audio only when its identity is recorded and defensible.",
        parents=[common],
    )
    root.add_argument("--version", action="version", version=__version__)
    commands = root.add_subparsers(dest="verb", required=True)

    tracklist = commands.add_parser("tracklist", parents=[common])
    tracklist.add_argument("worklist", type=Path)
    tracklist.add_argument(
        "--source", choices=("goldcast", "synapson", "vent-2024")
    )

    soundcloud = commands.add_parser("soundcloud", parents=[common])
    soundcloud.add_argument("artist")
    soundcloud.add_argument("--likes", action="store_true")
    soundcloud.add_argument("--reposts", action="store_true")
    soundcloud.add_argument("--sets", action="store_true")

    bandcamp = commands.add_parser("bandcamp", parents=[common])
    bandcamp.add_argument("artist")
    bandcamp.add_argument("--alias")

    ytmusic = commands.add_parser("ytmusic", parents=[common])
    ytmusic.add_argument("artist")

    status = commands.add_parser("status", parents=[common])
    status.add_argument("--json", action="store_true")

    commands.add_parser("resume", parents=[common])
    return root


def _state_root(environ: dict[str, str]) -> Path:
    return Path(environ.get("MUSIC_ACQUIRE_STATE_ROOT", str(DEFAULT_STATE_ROOT))).expanduser()


def _campaign_repo(environ: dict[str, str]) -> Path:
    return Path(
        environ.get("MUSIC_CONSOLIDATION_REPO", str(DEFAULT_CAMPAIGN_REPO))
    ).expanduser()


def _human_status(statuses: list[dict[str, Any]]) -> None:
    if not statuses:
        print("no music-acquire batches")
        return
    for value in statuses:
        percent = 100.0 * value["completion"]
        counts = " ".join(
            f"{name}={count}" for name, count in value["dispositions"].items()
        )
        estimate = value.get("estimate_seconds")
        eta = f" eta={estimate}s" if estimate is not None and value["remaining"] else ""
        print(
            f"{value['batch']}: {value['archived']}/{value['total']} "
            f"({percent:.1f}%) remaining={value['remaining']}{eta}"
        )
        if counts:
            print(f"  {counts}")


def _default_batch(args: argparse.Namespace) -> str:
    if hasattr(args, "batch"):
        return slug(args.batch)
    if args.verb == "tracklist":
        return slug(args.source or args.worklist.stem)
    if args.verb in {"soundcloud", "bandcamp", "ytmusic"}:
        return slug(args.artist.rstrip("/").rsplit("/", 1)[-1])
    raise ValueError("--batch is required")


def _enumerate(
    args: argparse.Namespace, backend: LiveBackend | None
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    if args.verb == "tracklist":
        path = args.worklist.expanduser().resolve()
        items = tracklist_items(path, args.source)
        return items, {
            "verb": "tracklist",
            "source": str(path),
            "input": str(path),
            "source_filter": args.source,
        }
    if backend is None:
        raise RuntimeError("a live backend is required for remote enumeration")
    if args.verb == "soundcloud":
        artist_url, items = backend.enumerate_soundcloud(
            args.artist, likes=args.likes, reposts=args.reposts, sets=args.sets
        )
        return items, {
            "verb": "soundcloud",
            "source": artist_url,
            "input": args.artist,
            "likes": args.likes,
            "reposts": args.reposts,
            "sets": args.sets,
        }
    if args.verb == "bandcamp":
        items = backend.enumerate_bandcamp(args.artist, alias=args.alias)
        return items, {
            "verb": "bandcamp",
            "source": args.artist,
            "input": args.artist,
            "alias": args.alias,
        }
    artist_url, items = backend.enumerate_ytmusic(args.artist)
    return items, {"verb": "ytmusic", "source": artist_url, "input": args.artist}


def main(argv: list[str] | None = None, *, environ: dict[str, str] | None = None) -> int:
    environ = dict(os.environ if environ is None else environ)
    args = parser().parse_args(argv)
    state_root = _state_root(environ)

    if args.verb == "status":
        if hasattr(args, "batch"):
            statuses = [BatchState(state_root, slug(args.batch)).status()]
        else:
            statuses = all_batch_statuses(state_root)
        if args.json:
            print(json.dumps({"batches": statuses}, ensure_ascii=False, sort_keys=True))
        else:
            _human_status(statuses)
        return 0

    if args.verb == "resume" and not hasattr(args, "batch"):
        parser().error("resume requires --batch NAME")

    batch = _default_batch(args)
    state = BatchState(state_root, batch)
    no_capture = bool(getattr(args, "no_capture", False))
    limit = max(0, int(getattr(args, "limit", 0)))
    dry_run = bool(getattr(args, "dry_run", False))
    campaign_repo = _campaign_repo(environ)
    backend: LiveBackend | None = None

    if args.verb == "resume":
        request = state.request()
        verb = str(request["verb"])
        items = state.worklist()
        out = Path(getattr(args, "out", request["out"])).expanduser()
    else:
        verb = args.verb
        existing_request = state.request() if state.request_path.exists() else None
        if existing_request:
            if existing_request.get("verb") != verb:
                parser().error(
                    f"batch {batch!r} belongs to {existing_request.get('verb')!r}, "
                    f"not {verb!r}"
                )
            requested_input = (
                str(args.worklist.expanduser().resolve())
                if verb == "tracklist"
                else args.artist
            )
            old_input = existing_request.get("input") or existing_request.get("source")
            if old_input is not None and old_input != requested_input:
                parser().error(
                    f"batch {batch!r} already belongs to source {old_input!r}"
                )
            if verb == "tracklist" and existing_request.get("source_filter") != args.source:
                parser().error(
                    f"batch {batch!r} already uses --source "
                    f"{existing_request.get('source_filter')!r}"
                )
            request = existing_request
            out = Path(getattr(args, "out", request["out"])).expanduser()
            if verb == "tracklist":
                fresh_items, _ = _enumerate(args, None)
                state.merge_worklist(fresh_items)
            items = state.worklist()
        else:
            out = Path(
                getattr(args, "out", DEFAULT_STAGING / f"acquire-{batch}")
            ).expanduser()
            # Remote enumeration needs command/cookie mechanics but deliberately
            # precedes prepare(): a dry run never probes entitlement.
            if verb == "tracklist":
                items, request = _enumerate(args, None)
            else:
                backend = LiveBackend(
                    state,
                    out,
                    campaign_repo,
                    no_capture=no_capture,
                    capture_host=environ.get("MUSIC_ACQUIRE_CAPTURE_HOST", "worker"),
                    environ=environ,
                )
                items, request = _enumerate(args, backend)
            request.update({"batch": batch, "out": str(out), "no_capture": no_capture})
            state.merge_worklist(items)
            state.save_request(request)
            items = state.worklist()

    archived = state.archived()
    remaining = [item for item in items if str(item["id"]) not in archived]
    if dry_run:
        preview = {
            "batch": batch,
            "verb": verb,
            "total": len(items),
            "remaining": len(remaining),
            "would_attempt": min(len(remaining), limit) if limit else len(remaining),
            "out": str(out),
        }
        print(json.dumps(preview, ensure_ascii=False, sort_keys=True))
        return 0

    reopenable = args.verb == "resume" and not no_capture and any(
        row.get("disposition") == "fallthrough"
        and row.get("reason") == "capture_unavailable"
        for row in state.final_rows().values()
    )
    if not remaining and not reopenable:
        status = state.status()
        print(
            f"batch {batch}: attempted 0; "
            f"{status['archived']}/{status['total']} archived"
        )
        return 0

    if backend is None:
        backend = LiveBackend(
            state,
            out,
            campaign_repo,
            no_capture=no_capture,
            capture_host=environ.get("MUSIC_ACQUIRE_CAPTURE_HOST", "worker"),
            environ=environ,
        )
    capture = backend.prepare()
    if args.verb == "resume" and not no_capture and (
        capture.get("entitlement_active") and capture.get("host_reachable")
    ):
        state.reopen_capture_unavailable()
        items = state.worklist()
    state.append_header(
        verb=verb,
        source=request.get("source"),
        host=socket.gethostname(),
        out=str(out),
        entitlement=capture.get("entitlement"),
        capture=capture,
    )
    attempted = Acquirer(state, backend, limit=limit).run(items, verb)
    status = state.status()
    print(
        f"batch {batch}: attempted {attempted}; "
        f"{status['archived']}/{status['total']} archived"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
