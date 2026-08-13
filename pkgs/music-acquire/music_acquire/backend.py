"""Production source enumeration and acquisition backends.

Network-facing behavior is kept behind this object so the orchestration can be
regression-tested without touching SoundCloud, YouTube, Bandcamp, or PipeWire.
"""

from __future__ import annotations

import hashlib
import html
import http.cookiejar
import importlib.util
import json
import os
import re
import shlex
import shutil
import socket
import subprocess
import tempfile
import time
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any, Iterable

from .state import BatchState
from .verification import (
    BER_ACCEPT,
    DUR_TOL_ACOUSTIC,
    artist_agrees,
    core_and_version,
    metadata_verdict,
    norm,
    title_agrees,
    version_agrees,
)


AUDIO_EXTENSIONS = {
    ".aac",
    ".aif",
    ".aiff",
    ".alac",
    ".flac",
    ".m4a",
    ".m4b",
    ".mka",
    ".mp2",
    ".mp3",
    ".oga",
    ".ogg",
    ".opus",
    ".wav",
    ".webm",
    ".wma",
}

RATE_LIMIT_MARKERS = (
    "rate-limited",
    "rate limited",
    "http error 429",
    "too many requests",
    "sign in to confirm you're not a bot",
)
GONE_MARKERS = (
    "http error 404",
    "not found",
    "was removed",
    "has been removed",
    "no longer available",
    "does not exist",
)
DRM_MARKERS = ("drm protected", "premium only", "not available for free accounts")
UA = (
    "music-acquire/2026.08.13 "
    "(https://github.com/mecattaf/dotfiles; contact: thomas@leger.run)"
)


def stable_stem(item_id: str) -> str:
    value = re.sub(r"[/\\\x00-\x1f]", "-", str(item_id)).strip(" .")
    if not value:
        value = "item"
    if len(value.encode("utf-8")) > 180:
        digest = hashlib.sha256(value.encode()).hexdigest()[:16]
        value = value[:140].rstrip() + "-" + digest
    return value


def is_rate_limited(text: str | None) -> bool:
    value = (text or "").lower()
    return any(marker in value for marker in RATE_LIMIT_MARKERS)


def classify_failure(text: str | None) -> str:
    value = (text or "").lower()
    if any(marker in value for marker in DRM_MARKERS):
        return "drm"
    if any(marker in value for marker in GONE_MARKERS):
        return "gone"
    return "retryable"


class LiveBackend:
    """The real, deliberately conservative three-stage acquisition cascade."""

    def __init__(
        self,
        state: BatchState,
        out: Path,
        campaign_repo: Path,
        *,
        no_capture: bool = False,
        capture_host: str = "worker",
        environ: dict[str, str] | None = None,
    ):
        self.state = state
        self.out = out.expanduser().resolve()
        self.campaign_repo = campaign_repo.expanduser().resolve()
        self.no_capture = no_capture
        self.capture_host = capture_host
        self.environ = dict(os.environ if environ is None else environ)
        self.out.mkdir(parents=True, exist_ok=True)
        self.work = self.state.path / "work"
        self.previews = self.state.path / "previews"
        self.work.mkdir(parents=True, exist_ok=True)
        self.previews.mkdir(parents=True, exist_ok=True)
        self.sc_cookie = self.state.cookies_path / "soundcloud.txt"
        self.yt_cookie = self.state.cookies_path / "youtube-music.txt"
        self._client_id: str | None = None
        self._fpmatch = None
        self._duplicate_sc: dict[str, str] = {}
        self._duplicate_item: dict[str, str] = {}
        self._duplicate_yt: dict[str, str] = {}
        self._mb_cache: dict[str, dict[str, Any] | None] = {}
        self.capture_info: dict[str, Any] = {}
        self._load_duplicate_index()

    # -- process and HTTP mechanics -----------------------------------------

    def _run(
        self,
        command: list[str],
        *,
        timeout: float = 300,
        input_text: str | None = None,
        env: dict[str, str] | None = None,
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            command,
            capture_output=True,
            text=True,
            timeout=timeout,
            input=input_text,
            env=env,
            check=False,
        )

    @staticmethod
    def _copy_cookie(source: str, destination: Path) -> bool:
        src = Path(source)
        if not src.is_file() or not os.access(src, os.R_OK):
            return False
        destination.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        shutil.copyfile(src, destination)
        os.chmod(destination, 0o600)
        return True

    def prepare(self) -> dict[str, Any]:
        sc_source = self.environ.get(
            "MUSIC_ACQUIRE_SC_COOKIES", "/run/agenix/soundcloud-cookies"
        )
        yt_source = self.environ.get(
            "MUSIC_ACQUIRE_YT_COOKIES", "/run/agenix/youtube-music-cookies"
        )
        have_sc = self._copy_cookie(sc_source, self.sc_cookie)
        have_yt = self._copy_cookie(yt_source, self.yt_cookie)

        entitlement: str | None = None
        entitlement_error: str | None = None
        if have_sc:
            try:
                me = self._soundcloud_get("me", authenticated=True)
                entitlement = (
                    (((me or {}).get("consumer_subscription") or {}).get("product") or {}).get(
                        "id"
                    )
                )
            except Exception as error:  # the header records uncertainty; work may continue
                entitlement_error = f"{type(error).__name__}: {error}"[:240]

        host = socket.gethostname().split(".")[0]
        capture_reachable = host == self.capture_host
        capture_busy = False
        if host != self.capture_host:
            try:
                probe_script = (
                    "if systemctl --user is-active --quiet mc-tier3.service; "
                    "then echo busy; else echo ready; fi"
                )
                probe = self._run(
                    [
                        "ssh",
                        "-o",
                        "BatchMode=yes",
                        "-o",
                        "ConnectTimeout=5",
                        self.capture_host,
                        "sh -lc " + shlex.quote(probe_script),
                    ],
                    timeout=10,
                )
                capture_reachable = probe.returncode == 0
                capture_busy = probe.stdout.strip().endswith("busy")
            except (OSError, subprocess.TimeoutExpired):
                capture_reachable = False
        else:
            probe = self._run(
                ["systemctl", "--user", "is-active", "--quiet", "mc-tier3.service"],
                timeout=5,
            )
            capture_busy = probe.returncode == 0

        self.capture_info = {
            "requested": not self.no_capture,
            "host": self.capture_host,
            "host_reachable": capture_reachable,
            "host_busy": capture_busy,
            "entitlement": entitlement,
            "entitlement_active": entitlement == "consumer-high-tier",
            "entitlement_error": entitlement_error,
            "available": (
                not self.no_capture
                and capture_reachable
                and not capture_busy
                and entitlement == "consumer-high-tier"
            ),
            "soundcloud_cookie": have_sc,
            "youtube_cookie": have_yt,
        }
        return self.capture_info

    def _get_bytes(self, url: str, *, authenticated: bool = False) -> bytes:
        headers = {"User-Agent": UA}
        if authenticated and self.sc_cookie.exists():
            jar = http.cookiejar.MozillaCookieJar(str(self.sc_cookie))
            jar.load(ignore_discard=True, ignore_expires=True)
            # SoundCloud's browser session keeps oauth_token as a host-only
            # soundcloud.com cookie.  It is intentionally not sent to the
            # api-v2 subdomain; the web client promotes it to the OAuth header.
            token = next(
                (cookie.value for cookie in jar if cookie.name == "oauth_token"),
                None,
            )
            if token:
                headers["Authorization"] = "OAuth " + token
            request = urllib.request.Request(url, headers=headers)
            opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
            with opener.open(request, timeout=45) as response:
                return response.read()
        request = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(request, timeout=45) as response:
            return response.read()

    def _scrape_client_id(self) -> str:
        if self._client_id:
            return self._client_id
        page = self._get_bytes("https://soundcloud.com/").decode("utf-8", "replace")
        assets = re.findall(
            r'src="(https://a-v2\.sndcdn\.com/assets/[^"]+\.js)"', page
        )
        for asset in assets:
            body = self._get_bytes(asset).decode("utf-8", "replace")
            match = re.search(r'client_id\s*[=:]\s*"([A-Za-z0-9]{32})"', body)
            if match:
                self._client_id = match.group(1)
                return self._client_id
        raise RuntimeError("could not scrape SoundCloud's public client_id")

    def _soundcloud_get(
        self,
        endpoint: str,
        params: dict[str, str | int] | None = None,
        *,
        authenticated: bool = False,
    ) -> Any:
        query = dict(params or {})
        query["client_id"] = self._scrape_client_id()
        url = "https://api-v2.soundcloud.com/" + endpoint.lstrip("/")
        url += "?" + urllib.parse.urlencode(query)
        return json.loads(self._get_bytes(url, authenticated=authenticated))

    def _yt_entries(self, url: str, *, cookies: Path | None = None) -> list[dict[str, Any]]:
        command = [
            "yt-dlp",
            "--ignore-config",
            "--flat-playlist",
            "--dump-json",
            "--ignore-errors",
            "--no-warnings",
        ]
        if cookies and cookies.exists():
            command += ["--cookies", str(cookies)]
        command.append(url)
        result = self._run(command, timeout=900)
        rows = []
        for line in result.stdout.splitlines():
            try:
                row = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(row, dict):
                rows.append(row)
        if not rows and result.returncode != 0:
            raise RuntimeError((result.stderr or "enumeration failed")[-400:])
        return rows

    # -- source enumeration --------------------------------------------------

    def _resolve_soundcloud_artist(self, value: str) -> str:
        if value.startswith(("http://", "https://")):
            return value.rstrip("/")
        result = self._soundcloud_get("search/users", {"q": value, "limit": 20})
        users = result.get("collection") or []
        exact = [user for user in users if norm(user.get("username")) == norm(value)]
        chosen = (exact or users or [None])[0]
        if not chosen or not chosen.get("permalink_url"):
            raise RuntimeError(f"SoundCloud artist not found: {value}")
        return str(chosen["permalink_url"]).rstrip("/")

    @staticmethod
    def _sc_flat_item(row: dict[str, Any], source: str) -> dict[str, Any] | None:
        item_id = row.get("id")
        url = row.get("webpage_url") or row.get("url")
        if not item_id or not url or "/sets/" in str(url):
            return None
        return {
            "id": str(item_id),
            "sc_id": str(item_id),
            "url": url,
            "query": row.get("title") or url,
            "title": row.get("title"),
            "artist": row.get("uploader") or row.get("channel"),
            "duration_s": row.get("duration"),
            "source": source,
            "appearances": [],
        }

    def enumerate_soundcloud(
        self,
        artist: str,
        *,
        likes: bool = False,
        reposts: bool = False,
        sets: bool = False,
    ) -> tuple[str, list[dict[str, Any]]]:
        artist_url = self._resolve_soundcloud_artist(artist)
        feeds = ["tracks"]
        if likes:
            feeds.append("likes")
        if reposts:
            feeds.append("reposts")
        if sets:
            feeds.append("sets")
        items: dict[str, dict[str, Any]] = {}
        source = f"soundcloud:{artist_url}"
        for feed in feeds:
            rows = self._yt_entries(f"{artist_url}/{feed}", cookies=self.sc_cookie)
            if feed == "sets":
                set_urls = [
                    row.get("webpage_url") or row.get("url")
                    for row in rows
                    if row.get("webpage_url") or row.get("url")
                ]
                rows = []
                for set_url in set_urls:
                    rows.extend(self._yt_entries(str(set_url), cookies=self.sc_cookie))
            for row in rows:
                item = self._sc_flat_item(row, source)
                if item:
                    items.setdefault(item["id"], item)
        return artist_url, list(items.values())

    def enumerate_bandcamp(
        self, artist_url: str, *, alias: str | None = None
    ) -> list[dict[str, Any]]:
        base = artist_url.rstrip("/")
        releases = self._yt_entries(f"{base}/music")
        items: dict[str, dict[str, Any]] = {}
        for release in releases:
            release_url = release.get("webpage_url") or release.get("url")
            if not release_url:
                continue
            tracks = self._yt_entries(str(release_url))
            if not tracks:
                tracks = [release]
            for track in tracks:
                track_id = track.get("id")
                track_url = track.get("webpage_url") or track.get("url")
                if not track_id or not track_url:
                    continue
                item_id = f"bc-{track_id}"
                items.setdefault(
                    item_id,
                    {
                        "id": item_id,
                        "bandcamp_id": str(track_id),
                        "url": track_url,
                        "query": track.get("title") or track_url,
                        "title": track.get("title"),
                        "artist": track.get("artist") or track.get("uploader"),
                        "release_url": release_url,
                        "release_title": release.get("title"),
                        "alias": alias,
                        "source": f"bandcamp:{base}",
                        "appearances": [],
                    },
                )
        return list(items.values())

    def _resolve_youtube_artist(self, value: str) -> str:
        if value.startswith(("http://", "https://")):
            return value.rstrip("/")
        rows = self._yt_entries(f"ytsearch10:{value}", cookies=self.yt_cookie)
        ranked = []
        for row in rows:
            channel_url = row.get("channel_url") or row.get("uploader_url")
            channel = row.get("channel") or row.get("uploader") or ""
            if not channel_url:
                continue
            score = 0
            if norm(channel).removesuffix(" topic") == norm(value):
                score += 5
            if artist_agrees([value], f"{channel} {row.get('title') or ''}"):
                score += 2
            if str(channel).endswith("- Topic"):
                score += 1
            ranked.append((score, str(channel_url).rstrip("/")))
        if not ranked:
            raise RuntimeError(f"YouTube Music artist not found: {value}")
        ranked.sort(reverse=True)
        return ranked[0][1]

    def enumerate_ytmusic(self, artist: str) -> tuple[str, list[dict[str, Any]]]:
        artist_url = self._resolve_youtube_artist(artist)
        rows: list[dict[str, Any]] = []
        errors = []
        for suffix in ("/releases", "/videos"):
            try:
                rows.extend(self._yt_entries(artist_url + suffix, cookies=self.yt_cookie))
            except RuntimeError as error:
                errors.append(str(error))
        if not rows:
            rows = self._yt_entries(artist_url, cookies=self.yt_cookie)
        items: dict[str, dict[str, Any]] = {}
        for row in rows:
            video_id = row.get("id")
            url = row.get("webpage_url") or row.get("url")
            if video_id and url:
                item_id = f"yt-{video_id}"
                items.setdefault(
                    item_id,
                    {
                        "id": item_id,
                        "yt_id": str(video_id),
                        "url": url,
                        "query": row.get("title") or url,
                        "title": row.get("title"),
                        "artist": row.get("channel") or row.get("uploader"),
                        "source": f"ytmusic:{artist_url}",
                        "appearances": [],
                    },
                )
        if not items and errors:
            raise RuntimeError(errors[-1])
        return artist_url, list(items.values())

    # -- duplicate suppression ----------------------------------------------

    def _load_duplicate_index(self) -> None:
        staging = Path(
            self.environ.get("MUSIC_ACQUIRE_STAGING", "/mnt/nas/music-staging")
        )
        provenance = Path(
            self.environ.get(
                "MUSIC_ACQUIRE_PROVENANCE",
                str(self.campaign_repo / "ledgers" / "staging-provenance.tsv"),
            )
        )
        if provenance.exists():
            with provenance.open(encoding="utf-8") as handle:
                header = handle.readline().rstrip("\n").split("\t")
                index = {name: position for position, name in enumerate(header)}
                for line in handle:
                    fields = line.rstrip("\n").split("\t")
                    if len(fields) < len(header):
                        continue
                    relpath = fields[index.get("relpath", 2)]
                    path = str(staging / relpath)
                    sc_id = fields[index.get("sc_id", 5)] if "sc_id" in index else ""
                    if sc_id:
                        self._duplicate_sc.setdefault(sc_id, path)
                    if "extra" in index:
                        for part in fields[index["extra"]].split(";"):
                            key, _, value = part.partition("=")
                            if key == "acquire_id" and value:
                                self._duplicate_item.setdefault(value, path)
                            if key == "yt_id" and value:
                                self._duplicate_yt.setdefault(value, path)

        # Before beets runs there is deliberately no provenance snapshot yet.
        # Index the campaign's actual ingest files by their established naming
        # contract so an already-held SoundCloud id still short-circuits without
        # a network request (tier-1 uses ``<id> - title``; tiers 2/3 use ``<id>``).
        ingest = staging / "_ingest"
        lane_roots = {
            "soundcloud": ingest / "soundcloud",
            "tier2": ingest / "tier2",
            "tier3": ingest / "tier3",
        }
        for lane, root in lane_roots.items():
            if not root.is_dir():
                continue
            for path in root.rglob("*"):
                if not path.is_file() or path.suffix.lower() not in AUDIO_EXTENSIONS:
                    continue
                if lane == "soundcloud":
                    match = re.match(r"([0-9]+) - ", path.name)
                    sc_id = match.group(1) if match else ""
                else:
                    sc_id = path.stem if path.stem.isdigit() else ""
                if sc_id:
                    self._duplicate_sc.setdefault(sc_id, str(path))

        state_root = self.state.root
        if state_root.exists():
            for ledger in state_root.glob("*/ledger.jsonl"):
                final: dict[str, dict[str, Any]] = {}
                with ledger.open(encoding="utf-8") as handle:
                    for line in handle:
                        try:
                            row = json.loads(line)
                        except json.JSONDecodeError:
                            continue
                        if row.get("record") == "item" and row.get("id"):
                            final[str(row["id"])] = row
                for item_id, row in final.items():
                    if not str(row.get("disposition") or "").startswith("ok_"):
                        continue
                    path = row.get("path")
                    if path:
                        self._duplicate_item.setdefault(item_id, str(path))
                        if row.get("sc_id"):
                            self._duplicate_sc.setdefault(str(row["sc_id"]), str(path))
                        if row.get("yt_id"):
                            self._duplicate_yt.setdefault(str(row["yt_id"]), str(path))

    def duplicate(self, item: dict[str, Any], sc_track: dict[str, Any] | None = None):
        item_id = str(item["id"])
        if item_id in self._duplicate_item:
            return {"path": self._duplicate_item[item_id], "duplicate_id": item_id}
        sc_id = "" if (sc_track or {}).get("segment") else str(
            (sc_track or {}).get("id") or item.get("sc_id") or ""
        )
        if sc_id and sc_id in self._duplicate_sc:
            return {"path": self._duplicate_sc[sc_id], "duplicate_sc_id": sc_id}
        yt_id = str(item.get("yt_id") or "")
        if yt_id and yt_id in self._duplicate_yt:
            return {"path": self._duplicate_yt[yt_id], "duplicate_yt_id": yt_id}
        return None

    def remember(self, item: dict[str, Any], row: dict[str, Any]) -> None:
        path = row.get("path")
        if not path:
            return
        self._duplicate_item[str(item["id"])] = str(path)
        if row.get("sc_id"):
            self._duplicate_sc[str(row["sc_id"])] = str(path)
        if row.get("yt_id"):
            self._duplicate_yt[str(row["yt_id"])] = str(path)

    # -- SoundCloud resolution and direct acquisition -----------------------

    @staticmethod
    def _soundcloud_track(track: dict[str, Any]) -> dict[str, Any]:
        publisher = track.get("publisher_metadata") or {}
        transcodings = ((track.get("media") or {}).get("transcodings") or [])
        user = track.get("user") or {}
        return {
            "id": str(track["id"]),
            "resolved": True,
            "title": track.get("title"),
            "url": track.get("permalink_url"),
            "uploader": user.get("permalink"),
            "uploader_name": user.get("username"),
            "policy": track.get("policy"),
            "monetization_model": track.get("monetization_model"),
            "duration_ms": track.get("duration"),
            "full_duration_ms": track.get("full_duration") or track.get("duration"),
            "artwork_url": track.get("artwork_url"),
            "pm_artist": publisher.get("artist"),
            "pm_album_title": publisher.get("album_title"),
            "pm_release_title": publisher.get("release_title"),
            "pm_isrc": publisher.get("isrc"),
            "has_preview": any(value.get("snipped") for value in transcodings),
        }

    @staticmethod
    def _description_segments(
        description: str | None, full_duration_ms: int | None
    ) -> list[dict[str, Any]]:
        """Parse timestamped long-form tracklists without guessing boundaries."""
        starts: list[tuple[float, str]] = []
        timestamp = re.compile(
            r"(?<![0-9])(?:(?P<h>[0-9]{1,2}):)?"
            r"(?P<m>[0-9]{1,2}):(?P<s>[0-9]{2})(?![0-9])"
        )
        for line in (description or "").splitlines():
            match = timestamp.search(line)
            if not match:
                continue
            hours = int(match.group("h") or 0)
            minutes = int(match.group("m"))
            seconds = int(match.group("s"))
            if minutes >= 60 or seconds >= 60:
                continue
            start = float(hours * 3600 + minutes * 60 + seconds)
            title = timestamp.sub(" ", line)
            title = re.sub(
                r"^[\s\[\](){}#|]*[0-9]{1,3}\s*[.):-]\s*", "", title
            )
            title = re.sub(r"[\[\](){}|]", " ", title)
            title = re.sub(r"\s+", " ", title).strip(" -–—.:#")
            if title:
                starts.append((start, title))
        starts.sort(key=lambda value: value[0])
        duration_s = float(full_duration_ms or 0) / 1000.0
        segments = []
        for index, (start, title) in enumerate(starts):
            end = starts[index + 1][0] if index + 1 < len(starts) else duration_s
            if end > start:
                segments.append({"start_s": start, "end_s": end, "title": title})
        return segments

    def resolve_soundcloud(self, item: dict[str, Any]) -> dict[str, Any]:
        try:
            sc_id = item.get("sc_id")
            if sc_id:
                tracks = self._soundcloud_get("tracks", {"ids": str(sc_id)})
                if not tracks:
                    return {"status": "gone", "reason": "track_gone_upstream"}
                return {"status": "found", "track": self._soundcloud_track(tracks[0])}

            if not str(item.get("source") or "").startswith("tracklist:"):
                return {"status": "absent", "reason": "not_a_text_source"}
            candidates = []
            segment_candidates = []
            reference_title = item.get("title") or item.get("query")
            artists = [item.get("artist") or ""]
            search_queries = []
            seen_queries = set()
            for query in (item.get("query"), item.get("title"), item.get("artist")):
                key = norm(query)
                if query and key not in seen_queries:
                    seen_queries.add(key)
                    search_queries.append(query)
            seen_candidates = set()
            for query_index, query in enumerate(search_queries):
                result = self._soundcloud_get(
                    "search/tracks", {"q": query, "limit": 20}
                )
                for candidate in result.get("collection") or []:
                    candidate_id = str(candidate.get("id") or "")
                    if not candidate_id or candidate_id in seen_candidates:
                        continue
                    seen_candidates.add(candidate_id)
                    user = candidate.get("user") or {}
                    candidate_text = (
                        f"{candidate.get('title') or ''} "
                        f"{user.get('username') or ''}"
                    )
                    uploader_text = (
                        f"{user.get('username') or ''} "
                        f"{user.get('permalink') or ''}"
                    )
                    direct_title = title_agrees(
                        reference_title,
                        candidate.get("title"),
                        [*artists, item.get("album") or ""],
                    )
                    candidate_artist = not artists[0] or artist_agrees(
                        artists, candidate_text
                    )
                    if direct_title and candidate_artist:
                        exact = norm(candidate.get("title")) == norm(reference_title)
                        candidates.append((not exact, candidate))

                    # A timestamped official album/mix can carry the requested
                    # constituent track even when its container title differs.
                    # Require its uploader to agree with the artist so a DJ-set
                    # description is never mistaken for a clean source recording.
                    if artists[0] and artist_agrees(artists, uploader_text):
                        for segment in self._description_segments(
                            candidate.get("description"),
                            candidate.get("full_duration") or candidate.get("duration"),
                        ):
                            if title_agrees(
                                reference_title,
                                segment["title"],
                                [*artists, item.get("album") or ""],
                            ):
                                segment_candidates.append((candidate, segment))
                if candidates or segment_candidates:
                    break
                if query_index + 1 < len(search_queries):
                    time.sleep(
                        float(self.environ.get("MUSIC_ACQUIRE_SC_API_SLEEP", "0.35"))
                    )
            if not candidates:
                if segment_candidates:
                    candidate, segment = segment_candidates[0]
                    resolved = self._soundcloud_track(candidate)
                    segment_duration_ms = round(
                        (segment["end_s"] - segment["start_s"]) * 1000
                    )
                    resolved.update(
                        {
                            "title": segment["title"],
                            "parent_title": candidate.get("title"),
                            "full_duration_ms": segment_duration_ms,
                            "duration_ms": segment_duration_ms,
                            "segment": segment,
                            "has_preview": False,
                            "pm_artist": item.get("artist"),
                            "pm_release_title": item.get("title"),
                            "pm_album_title": item.get("album")
                            or candidate.get("title"),
                            "pm_isrc": None,
                        }
                    )
                    return {"status": "found", "track": resolved}
                return {"status": "absent", "reason": "no_soundcloud_candidate"}
            candidates.sort(key=lambda pair: pair[0])
            return {"status": "found", "track": self._soundcloud_track(candidates[0][1])}
        except Exception as error:
            return {
                "status": "retryable",
                "reason": "soundcloud_resolution_failed",
                "detail": f"{type(error).__name__}: {error}"[:300],
            }

    def _audio_for_stem(self, stem: str, directory: Path | None = None) -> Path | None:
        root = directory or self.out
        for path in sorted(root.glob(stem + ".*")):
            if path.suffix.lower() in AUDIO_EXTENSIONS and not path.name.endswith(".part"):
                if path.stat().st_size > 0:
                    return path
        return None

    def _download_native(
        self,
        *,
        url: str,
        item_id: str,
        cookies: Path | None,
        format_selector: str,
        timeout: float = 1800,
    ) -> dict[str, Any]:
        stem = stable_stem(item_id)
        held = self._audio_for_stem(stem)
        if held:
            return {"status": "ok", "path": str(held), "bytes": held.stat().st_size}
        command = [
            "yt-dlp",
            "--ignore-config",
            "--no-playlist",
            "--no-progress",
            "--no-warnings",
            "--sleep-requests",
            "1",
            "--retries",
            "5",
            "--fragment-retries",
            "5",
            "--no-overwrites",
            "--write-info-json",
            "--write-thumbnail",
            "--embed-thumbnail",
            "--embed-metadata",
            "-f",
            format_selector,
            "-o",
            str(self.out / (stem + ".%(ext)s")),
        ]
        if cookies and cookies.exists():
            command += ["--cookies", str(cookies)]
        command.append(url)
        try:
            result = self._run(command, timeout=timeout)
        except subprocess.TimeoutExpired:
            return {"status": "retryable", "reason": "download_timeout"}
        audio = self._audio_for_stem(stem)
        if audio:
            return {
                "status": "ok",
                "path": str(audio),
                "bytes": audio.stat().st_size,
                "download_note": (result.stderr or "")[-240:] or None,
            }
        detail = (result.stderr or result.stdout or "download produced no audio")[-400:]
        return {
            "status": classify_failure(detail),
            "reason": "download_failed",
            "detail": detail,
        }

    def download_soundcloud(
        self, item: dict[str, Any], track: dict[str, Any]
    ) -> dict[str, Any]:
        if not self.sc_cookie.exists():
            return {"status": "retryable", "reason": "soundcloud_cookie_unavailable"}
        if track.get("segment"):
            return self._download_soundcloud_segment(item, track)
        return self._download_native(
            url=str(track.get("url") or item.get("url")),
            item_id=str(item["id"]),
            cookies=self.sc_cookie,
            format_selector="download/bestaudio/best",
        )

    def _download_soundcloud_segment(
        self, item: dict[str, Any], track: dict[str, Any]
    ) -> dict[str, Any]:
        """Stream-copy one timestamped track from an official long-form upload."""
        output_stem = stable_stem(str(item["id"]))
        held = self._audio_for_stem(output_stem)
        if held:
            return {"status": "ok", "path": str(held), "bytes": held.stat().st_size}

        parent_stem = "sc-parent-" + stable_stem(str(track["id"]))
        parent = self._audio_for_stem(parent_stem, self.work)
        if not parent:
            command = [
                "yt-dlp",
                "--ignore-config",
                "--no-playlist",
                "--no-progress",
                "--no-warnings",
                "--sleep-requests",
                "1",
                "--retries",
                "5",
                "--fragment-retries",
                "5",
                "--no-overwrites",
                "--write-info-json",
                "--write-thumbnail",
                "--embed-thumbnail",
                "--embed-metadata",
                "--cookies",
                str(self.sc_cookie),
                "-f",
                "download/bestaudio/best",
                "-o",
                str(self.work / (parent_stem + ".%(ext)s")),
                str(track["url"]),
            ]
            try:
                result = self._run(command, timeout=3600)
            except subprocess.TimeoutExpired:
                return {"status": "retryable", "reason": "download_timeout"}
            parent = self._audio_for_stem(parent_stem, self.work)
            if not parent:
                detail = (
                    result.stderr or result.stdout or "download produced no audio"
                )[-400:]
                return {
                    "status": classify_failure(detail),
                    "reason": "download_failed",
                    "detail": detail,
                }

        segment = track["segment"]
        duration = float(segment["end_s"]) - float(segment["start_s"])
        final = self.out / (output_stem + parent.suffix.lower())
        # Keep the temporary beside the destination so the final rename is
        # atomic even when state lives locally and the ingest lane is on NAS.
        temporary = self.out / (
            "." + output_stem + ".segment.part" + parent.suffix.lower()
        )
        try:
            temporary.unlink(missing_ok=True)
        except OSError:
            return {"status": "retryable", "reason": "stale_segment_output"}
        command = [
            "ffmpeg",
            "-v",
            "error",
            "-nostdin",
            "-ss",
            f"{float(segment['start_s']):.3f}",
            "-i",
            str(parent),
            "-t",
            f"{duration:.3f}",
            "-map",
            "0",
            "-c",
            "copy",
            "-avoid_negative_ts",
            "make_zero",
            "-metadata",
            f"title={item.get('title') or segment['title']}",
            str(temporary),
        ]
        result = self._run(command, timeout=max(300, duration + 120))
        if (
            result.returncode != 0
            or not temporary.exists()
            or temporary.stat().st_size == 0
        ):
            return {
                "status": "retryable",
                "reason": "segment_stream_copy_failed",
                "detail": (result.stderr or "")[-300:],
            }
        os.replace(temporary, final)

        parent_info = self.work / (parent_stem + ".info.json")
        if parent_info.exists():
            try:
                info = json.loads(parent_info.read_text(encoding="utf-8"))
                info["music_acquire_segment"] = {
                    **segment,
                    "parent_sc_id": str(track["id"]),
                    "parent_sc_url": track.get("url"),
                }
                (self.out / (output_stem + ".info.json")).write_text(
                    json.dumps(info, ensure_ascii=False, indent=2) + "\n",
                    encoding="utf-8",
                )
            except (OSError, json.JSONDecodeError):
                pass
        for artwork in self.work.glob(parent_stem + ".*"):
            if artwork.suffix.lower() in {".jpg", ".jpeg", ".png", ".webp"}:
                destination = self.out / (output_stem + artwork.suffix.lower())
                if not destination.exists():
                    shutil.copyfile(artwork, destination)

        return {
            "status": "ok",
            "path": str(final),
            "bytes": final.stat().st_size,
            "segment": {
                **segment,
                "parent_sc_id": str(track["id"]),
                "parent_sc_url": track.get("url"),
            },
        }

    # -- MusicBrainz and YouTube verification -------------------------------

    def _musicbrainz_get(self, endpoint: str, params: dict[str, str]) -> Any:
        query = urllib.parse.urlencode({**params, "fmt": "json"})
        request = urllib.request.Request(
            f"https://musicbrainz.org/ws/2/{endpoint}?{query}",
            headers={"User-Agent": UA, "Accept": "application/json"},
        )
        with urllib.request.urlopen(request, timeout=45) as response:
            result = json.loads(response.read())
        time.sleep(float(self.environ.get("MUSIC_ACQUIRE_MB_SLEEP", "1")))
        return result

    @staticmethod
    def _mb_recording(row: dict[str, Any], isrc: str | None = None) -> dict[str, Any]:
        credits = row.get("artist-credit") or row.get("artist_credit") or []
        artists = []
        for credit in credits:
            if isinstance(credit, dict):
                artist = credit.get("artist") or {}
                name = artist.get("name") or credit.get("name")
                if name:
                    artists.append(name)
        if not artists and row.get("artist"):
            artists = [row["artist"]]
        isrcs = row.get("isrcs") or ([isrc] if isrc else [])
        return {
            "mbid": row.get("id") or row.get("mbid"),
            "title": row.get("title"),
            "artist": artists[0] if artists else None,
            "artists": artists,
            "length_ms": row.get("length") or row.get("length_ms"),
            "isrc": (isrcs or [None])[0],
        }

    def _mb_for_sc(self, track: dict[str, Any]) -> dict[str, Any] | None:
        isrc = track.get("pm_isrc")
        if not isrc:
            return None
        cache_key = "isrc:" + str(isrc)
        if cache_key in self._mb_cache:
            return self._mb_cache[cache_key]

        local = self.campaign_repo / "ledgers" / "musicbrainz-isrc.jsonl"
        state_local = Path.home() / ".local/state/music-tier2/musicbrainz-isrc.jsonl"
        for path in (local, state_local):
            if not path.exists():
                continue
            with path.open(encoding="utf-8") as handle:
                for line in handle:
                    try:
                        row = json.loads(line)
                    except json.JSONDecodeError:
                        continue
                    if row.get("isrc") != isrc or not row.get("found"):
                        continue
                    recordings = row.get("recordings") or []
                    if recordings:
                        chosen = min(
                            recordings,
                            key=lambda value: abs(
                                (value.get("length_ms") or 0)
                                - (track.get("full_duration_ms") or 0)
                            ),
                        )
                        result = self._mb_recording(chosen, str(isrc))
                        self._mb_cache[cache_key] = result
                        return result
        try:
            response = self._musicbrainz_get(
                f"isrc/{urllib.parse.quote(str(isrc))}",
                {"inc": "recordings+artist-credits"},
            )
            recordings = response.get("recordings") or []
            if recordings:
                chosen = min(
                    recordings,
                    key=lambda value: abs(
                        (value.get("length") or 0) - (track.get("full_duration_ms") or 0)
                    ),
                )
                result = self._mb_recording(chosen, str(isrc))
                self._mb_cache[cache_key] = result
                return result
        except Exception:
            pass
        self._mb_cache[cache_key] = None
        return None

    def _mb_for_text(self, item: dict[str, Any]) -> dict[str, Any] | None:
        artist = item.get("artist") or ""
        title = item.get("title") or item.get("query") or ""
        cache_key = "text:" + norm(f"{artist} {title}")
        if cache_key in self._mb_cache:
            return self._mb_cache[cache_key]
        query = f'recording:"{title}"'
        if artist:
            query += f' AND artist:"{artist}"'
        try:
            response = self._musicbrainz_get(
                "recording/", {"query": query, "limit": "10", "inc": "isrcs"}
            )
        except Exception:
            self._mb_cache[cache_key] = None
            return None
        candidates = []
        for row in response.get("recordings") or []:
            record = self._mb_recording(row)
            if not record.get("length_ms"):
                continue
            if not title_agrees(
                title, record.get("title"), [artist, item.get("album") or ""]
            ):
                continue
            if artist and not artist_agrees([artist], " ".join(record.get("artists") or [])):
                continue
            candidates.append(record)
        result = candidates[0] if candidates else None
        self._mb_cache[cache_key] = result
        return result

    def _yt_search(self, query: str, count: int = 8) -> tuple[list[dict[str, Any]], str]:
        command = [
            "yt-dlp",
            "--ignore-config",
            "--no-warnings",
            "--flat-playlist",
            "--print",
            "%(id)s\t%(duration)s\t%(channel)s\t%(title)s",
        ]
        if self.yt_cookie.exists():
            command += ["--cookies", str(self.yt_cookie)]
        command.append(f"ytsearch{count}:{query}")
        try:
            result = self._run(command, timeout=150)
        except subprocess.TimeoutExpired:
            return [], "timeout"
        candidates = []
        for line in result.stdout.splitlines():
            fields = line.split("\t")
            if len(fields) != 4:
                continue
            video_id, duration, channel, title = fields
            try:
                duration_s = float(duration)
            except ValueError:
                continue
            candidates.append(
                {
                    "id": video_id,
                    "duration": duration_s,
                    "channel": channel,
                    "title": title,
                }
            )
        error = result.stderr or ""
        if result.returncode != 0 and not error:
            error = f"yt-dlp search exited {result.returncode}"
        return candidates, error

    def _preview(self, track: dict[str, Any]) -> Path | None:
        path = self.previews / (stable_stem(str(track["id"])) + ".mp3")
        if path.exists() and path.stat().st_size > 20_000:
            return path
        command = [
            "yt-dlp",
            "--ignore-config",
            "--no-warnings",
            "-f",
            "bestaudio",
            "-o",
            str(path),
            str(track["url"]),
        ]
        try:
            self._run(command, timeout=180)
        except subprocess.TimeoutExpired:
            return None
        return path if path.exists() and path.stat().st_size > 20_000 else None

    def _yt_section(self, video_id: str) -> tuple[Path | None, str | None]:
        section_dir = Path(tempfile.mkdtemp(prefix="yt-section-", dir=self.work))
        stem = section_dir / "candidate"
        command = [
            "yt-dlp",
            "--ignore-config",
            "--no-warnings",
            "--sleep-requests",
            "1",
            "-f",
            "bestaudio",
            "--download-sections",
            "*0-90",
            "--force-keyframes-at-cuts",
            "-o",
            str(stem) + ".%(ext)s",
        ]
        if self.yt_cookie.exists():
            command += ["--cookies", str(self.yt_cookie)]
        command.append(f"https://www.youtube.com/watch?v={video_id}")
        try:
            result = self._run(command, timeout=360)
        except subprocess.TimeoutExpired:
            return None, "timeout"
        files = [path for path in section_dir.iterdir() if path.is_file()]
        audio = next(
            (path for path in files if path.suffix.lower() in AUDIO_EXTENSIONS), None
        )
        return audio, None if audio else (result.stderr or "section download failed")[-400:]

    def _load_fpmatch(self):
        if self._fpmatch is not None:
            return self._fpmatch
        path = self.campaign_repo / "scripts" / "fpmatch.py"
        if not path.exists():
            raise RuntimeError(f"missing campaign fingerprint matcher: {path}")
        spec = importlib.util.spec_from_file_location("music_acquire_fpmatch", path)
        if spec is None or spec.loader is None:
            raise RuntimeError(f"cannot import {path}")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        self._fpmatch = module
        return module

    @staticmethod
    def _identity(item: dict[str, Any], track: dict[str, Any] | None, mb: dict | None):
        titles: list[str] = []
        artists: list[str] = []
        if mb:
            titles.append(mb.get("title") or "")
            artists.extend(mb.get("artists") or [mb.get("artist") or ""])
        if track:
            titles.extend(
                value
                for value in (track.get("pm_release_title"), track.get("title"))
                if value
            )
            artists.extend(
                value
                for value in (track.get("pm_artist"), track.get("uploader_name"))
                if value
            )
        else:
            titles.extend(value for value in (item.get("title"), item.get("query")) if value)
            artists.extend(value for value in (item.get("artist"),) if value)
        return titles, artists

    def verify_youtube(
        self, item: dict[str, Any], track: dict[str, Any] | None
    ) -> dict[str, Any]:
        if not self.yt_cookie.exists():
            return {"status": "retryable", "reason": "youtube_cookie_unavailable"}
        mb = self._mb_for_sc(track) if track else self._mb_for_text(item)
        titles, artists = self._identity(item, track, mb)
        if track:
            duration_ms = track.get("full_duration_ms") or track.get("duration_ms")
            target_s = float(duration_ms) / 1000.0 if duration_ms else None
        else:
            target_s = (
                float(mb["length_ms"]) / 1000.0 if mb and mb.get("length_ms") else None
            )
        if target_s is None:
            return {"status": "unverified", "reason": "no_reference_duration"}

        queries = []
        if mb:
            queries.append(f"{mb.get('artist') or ''} {mb.get('title') or ''}".strip())
        if item.get("artist") and item.get("title"):
            queries.append(f"{item['artist']} {item['title']}")
        if track and track.get("pm_artist") and track.get("pm_release_title"):
            queries.append(f"{track['pm_artist']} {track['pm_release_title']}")
        queries.append(item.get("query") or (titles[0] if titles else ""))
        unique_queries = []
        seen_queries = set()
        for query in queries:
            key = norm(query)
            if query and key not in seen_queries:
                seen_queries.add(key)
                unique_queries.append(query)

        candidates: dict[str, dict[str, Any]] = {}
        search_errors = []
        for query in unique_queries[:4]:
            rows, error = self._yt_search(query)
            search_errors.append(error)
            for candidate in rows:
                if abs(candidate["duration"] - target_s) <= 8.0:
                    candidates.setdefault(candidate["id"], candidate)
            if len(candidates) >= 3:
                break
        if not candidates:
            if any(is_rate_limited(error) for error in search_errors):
                return {"status": "retryable", "reason": "throttled_during_search"}
            if any(error.strip() for error in search_errors):
                return {
                    "status": "retryable",
                    "reason": "youtube_search_failed",
                    "detail": next(error[-300:] for error in search_errors if error.strip()),
                }
            return {
                "status": "unverified",
                "reason": "no_candidate",
                "queries": unique_queries,
            }

        def score(candidate: dict[str, Any]) -> tuple[float, str]:
            value = 0.0
            context = [
                *artists,
                item.get("album") or "",
                (track or {}).get("pm_album_title") or "",
            ]
            if any(
                title_agrees(title, candidate["title"], context) for title in titles
            ):
                value += 3
            if artist_agrees(artists, f"{candidate['title']} {candidate['channel']}"):
                value += 2
            if str(candidate.get("channel") or "").endswith("- Topic"):
                value += 1.5
            value -= abs(candidate["duration"] - target_s) / 4.0
            return (-value, candidate["id"])

        ranked = sorted(candidates.values(), key=score)[:3]
        preview = self._preview(track) if track and track.get("has_preview") else None
        rejects = []
        accepted = None
        section_failures = 0
        if preview:
            matcher = self._load_fpmatch()
            for candidate in ranked:
                section, error = self._yt_section(candidate["id"])
                if error and is_rate_limited(error):
                    return {
                        "status": "retryable",
                        "reason": "throttled_during_verification",
                        "detail": error[-240:],
                    }
                if not section:
                    section_failures += 1
                    rejects.append({**candidate, "rejected": "section_download_failed"})
                    continue
                try:
                    result = matcher.compare(str(preview), str(section))
                finally:
                    shutil.rmtree(section.parent, ignore_errors=True)
                duration_delta = abs(candidate["duration"] - target_s)
                if result and result[0] <= BER_ACCEPT and duration_delta <= DUR_TOL_ACOUSTIC:
                    accepted = {
                        "candidate": candidate,
                        "verdict": "acoustic",
                        "evidence": {
                            "ber": round(result[0], 4),
                            "offset_s": result[1],
                            "overlap_s": round(result[2], 1),
                            "dur_ref_s": round(target_s, 1),
                            "dur_got_s": candidate["duration"],
                        },
                    }
                    break
                rejects.append(
                    {
                        **candidate,
                        "rejected": f"ber_{round(result[0], 4) if result else 'unreadable'}",
                    }
                )
            if not accepted and section_failures == len(ranked):
                return {
                    "status": "retryable",
                    "reason": "no_audio_fetched_for_any_candidate",
                    "candidates": rejects,
                }
        else:
            for candidate in ranked:
                verdict, evidence = metadata_verdict(
                    reference_titles=titles,
                    reference_artists=artists,
                    candidate_title=candidate["title"],
                    candidate_channel=candidate["channel"],
                    candidate_duration_s=candidate["duration"],
                    source_duration_s=target_s,
                    mb_recording=mb,
                    reference_context=[
                        item.get("album") or "",
                        (track or {}).get("pm_album_title") or "",
                    ],
                )
                if verdict:
                    accepted = {
                        "candidate": candidate,
                        "verdict": verdict,
                        "evidence": evidence,
                    }
                    break
                rejects.append({**candidate, "rejected": evidence})

        if not accepted:
            return {
                "status": "unverified",
                "reason": "unverified",
                "queries": unique_queries,
                "candidates": rejects,
            }
        candidate = accepted["candidate"]
        downloaded = self._download_native(
            url=f"https://www.youtube.com/watch?v={candidate['id']}",
            item_id=str(item["id"]),
            cookies=self.yt_cookie,
            format_selector="bestaudio/best",
        )
        if downloaded.get("status") != "ok":
            return {
                "status": "retryable",
                "reason": "verified_but_download_failed",
                "detail": downloaded.get("detail") or downloaded.get("reason"),
                "yt_id": candidate["id"],
                "verdict": accepted["verdict"],
                "evidence": accepted["evidence"],
            }
        return {
            "status": "ok",
            "path": downloaded["path"],
            "bytes": downloaded.get("bytes"),
            "yt_id": candidate["id"],
            "yt_title": candidate["title"],
            "yt_channel": candidate["channel"],
            "verdict": accepted["verdict"],
            "evidence": accepted["evidence"],
            "also_considered": rejects,
        }

    def download_ytmusic(self, item: dict[str, Any]) -> dict[str, Any]:
        result = self._download_native(
            url=str(item["url"]),
            item_id=str(item["id"]),
            cookies=self.yt_cookie,
            format_selector="bestaudio/best",
        )
        if result.get("status") == "ok":
            result.update(
                {
                    "yt_id": item.get("yt_id"),
                    "verdict": "source",
                    "evidence": {"artist_source": item.get("source")},
                }
            )
        return result

    def retry_youtube_download(
        self, item: dict[str, Any], previous: dict[str, Any]
    ) -> dict[str, Any]:
        """Retry a proven video id without paying for verification again."""
        if not self.yt_cookie.exists():
            return {"status": "retryable", "reason": "youtube_cookie_unavailable"}
        video_id = str(previous["yt_id"])
        downloaded = self._download_native(
            url=f"https://www.youtube.com/watch?v={video_id}",
            item_id=str(item["id"]),
            cookies=self.yt_cookie,
            format_selector="bestaudio/best",
        )
        if downloaded.get("status") != "ok":
            return {
                "status": "retryable",
                "reason": "verified_but_download_failed",
                "detail": downloaded.get("detail") or downloaded.get("reason"),
                "yt_id": video_id,
                "verdict": previous.get("verdict"),
                "evidence": previous.get("evidence") or {},
            }
        return {
            "status": "ok",
            "path": downloaded["path"],
            "bytes": downloaded.get("bytes"),
            "yt_id": video_id,
            "yt_title": previous.get("yt_title"),
            "yt_channel": previous.get("yt_channel"),
            "verdict": previous.get("verdict"),
            "evidence": previous.get("evidence") or {},
            "repaired_from": "verified_but_download_failed",
        }

    def download_bandcamp(self, item: dict[str, Any]) -> dict[str, Any]:
        result = self._download_native(
            url=str(item["url"]),
            item_id=str(item["id"]),
            cookies=None,
            format_selector="mp3-128/bestaudio/best",
        )
        if result.get("status") == "ok":
            result.update(
                {
                    "bandcamp_id": item.get("bandcamp_id"),
                    "verdict": "source",
                    "evidence": {
                        "release_url": item.get("release_url"),
                        "alias": item.get("alias"),
                        "purchases_attempted": False,
                    },
                }
            )
        return result

    # -- worker-resident realtime capture -----------------------------------

    def capture(self, item: dict[str, Any], track: dict[str, Any]) -> dict[str, Any]:
        if track.get("segment"):
            return {
                "status": "unavailable",
                "reason": "capture_unsupported_segment",
            }
        info = self.capture_info
        if self.no_capture:
            return {"status": "unavailable", "reason": "capture_unavailable"}
        if info.get("host_busy"):
            return {"status": "retryable", "reason": "capture_host_busy"}
        if not info.get("host_reachable") or not info.get("entitlement_active"):
            return {"status": "unavailable", "reason": "capture_unavailable"}
        if socket.gethostname().split(".")[0] == self.capture_host:
            return self._capture_local(item, track)
        return self._capture_remote(item, track)

    def _capture_work_item(self, item: dict[str, Any], track: dict[str, Any]) -> dict[str, Any]:
        return {
            "id": stable_stem(str(item["id"])),
            "url": track.get("url"),
            "title": track.get("title") or item.get("title"),
            "full_duration_ms": track.get("full_duration_ms"),
            "artwork_url": track.get("artwork_url"),
        }

    @staticmethod
    def _capture_result(ledger: Path, capture_id: str) -> dict[str, Any]:
        final = None
        if ledger.exists():
            with ledger.open(encoding="utf-8") as handle:
                for line in handle:
                    try:
                        row = json.loads(line)
                    except json.JSONDecodeError:
                        continue
                    if str(row.get("id")) == capture_id:
                        final = row
        if not final:
            return {"status": "retryable", "reason": "capture_produced_no_ledger_row"}
        if final.get("status") == "ok":
            return {
                "status": "ok",
                "path": final.get("path"),
                "evidence": final.get("evidence") or {},
            }
        reason = str(final.get("reason") or "capture_failed")
        if "fingerprint_mismatch" in reason or "duration_mismatch" in reason:
            return {
                "status": "rejected",
                "reason": "capture_verification_failed",
                "evidence": final.get("evidence") or {},
                "detail": reason,
            }
        return {
            "status": "retryable",
            "reason": reason,
            "evidence": final.get("evidence") or {},
        }

    def _capture_local(self, item: dict[str, Any], track: dict[str, Any]) -> dict[str, Any]:
        script = self.campaign_repo / "scripts" / "tier3-capture.py"
        if not script.exists():
            return {"status": "unavailable", "reason": "capture_engine_missing"}
        capture_state = self.state.path / "capture"
        capture_state.mkdir(parents=True, exist_ok=True)
        capture_item = self._capture_work_item(item, track)
        worklist = capture_state / "worklist.jsonl"
        worklist.write_text(json.dumps(capture_item, ensure_ascii=False) + "\n", encoding="utf-8")
        if self.sc_cookie.exists():
            shutil.copyfile(self.sc_cookie, capture_state / "sc-cookies.txt")
            os.chmod(capture_state / "sc-cookies.txt", 0o600)
        preview = self.previews / (stable_stem(str(track["id"])) + ".mp3")
        capture_previews = capture_state / "previews"
        capture_previews.mkdir(exist_ok=True)
        if preview.exists():
            shutil.copyfile(preview, capture_previews / (capture_item["id"] + ".mp3"))
        env = dict(self.environ)
        env.update(
            {
                "TIER3_STATE": str(capture_state),
                "TIER3_OUT": str(self.out),
                "TIER3_PREVIEWS": str(capture_previews),
                "TIER3_LIMIT": "1",
            }
        )
        result = self._run(
            ["python3", str(script), str(worklist)], timeout=7200, env=env
        )
        outcome = self._capture_result(
            capture_state / "tier3-captures.jsonl", capture_item["id"]
        )
        if outcome.get("status") != "ok" and result.returncode != 0:
            outcome.setdefault("detail", (result.stderr or "")[-300:])
        return outcome

    def _capture_remote(self, item: dict[str, Any], track: dict[str, Any]) -> dict[str, Any]:
        capture_item = self._capture_work_item(item, track)
        batch = stable_stem(self.state.batch)
        remote_state = f"/home/tom/.local/state/music-acquire-capture/{batch}"
        remote_out = f"/home/tom/music-staging/_ingest/acquire-{batch}"
        remote_repo = self.environ.get(
            "MUSIC_ACQUIRE_REMOTE_REPO", "/home/tom/mecattaf/music-consolidation"
        )
        setup = (
            f"mkdir -p {shlex.quote(remote_state)}/previews {shlex.quote(remote_out)}; "
            f"install -m 600 /run/agenix/soundcloud-cookies "
            f"{shlex.quote(remote_state)}/sc-cookies.txt; "
            f"cat > {shlex.quote(remote_state)}/worklist-one.jsonl"
        )
        result = self._run(
            ["ssh", self.capture_host, "bash", "-lc", shlex.quote(setup)],
            input_text=json.dumps(capture_item, ensure_ascii=False) + "\n",
            timeout=30,
        )
        if result.returncode != 0:
            return {
                "status": "retryable",
                "reason": "capture_remote_setup_failed",
                "detail": (result.stderr or "")[-300:],
            }
        preview = self.previews / (stable_stem(str(track["id"])) + ".mp3")
        if preview.exists():
            copied = self._run(
                [
                    "scp",
                    "-q",
                    str(preview),
                    f"{self.capture_host}:{remote_state}/previews/{capture_item['id']}.mp3",
                ],
                timeout=120,
            )
            if copied.returncode != 0:
                return {"status": "retryable", "reason": "capture_preview_copy_failed"}
        run_command = (
            f"TIER3_STATE={shlex.quote(remote_state)} "
            f"TIER3_OUT={shlex.quote(remote_out)} "
            f"TIER3_PREVIEWS={shlex.quote(remote_state + '/previews')} "
            "TIER3_LIMIT=1 "
            "FPCALC=/home/tom/.local/state/music-campaign/deps/chromaprint/bin/fpcalc "
            f"python3 {shlex.quote(remote_repo + '/scripts/tier3-capture.py')} "
            f"{shlex.quote(remote_state + '/worklist-one.jsonl')}"
        )
        try:
            ran = self._run(
                ["ssh", self.capture_host, "bash", "-lc", shlex.quote(run_command)],
                timeout=7200,
            )
        except subprocess.TimeoutExpired:
            return {"status": "retryable", "reason": "capture_timeout"}
        local_ledger = self.state.path / "capture-remote-ledger.jsonl"
        copied_ledger = self._run(
            [
                "scp",
                "-q",
                f"{self.capture_host}:{remote_state}/tier3-captures.jsonl",
                str(local_ledger),
            ],
            timeout=120,
        )
        if copied_ledger.returncode != 0:
            return {
                "status": "retryable",
                "reason": "capture_ledger_copy_failed",
                "detail": (ran.stderr or "")[-300:],
            }
        outcome = self._capture_result(local_ledger, capture_item["id"])
        if outcome.get("status") == "ok":
            remote_path = str(outcome.get("path"))
            suffix = Path(remote_path).suffix or ".flac"
            local_path = self.out / (stable_stem(str(item["id"])) + suffix)
            copied_audio = self._run(
                ["scp", "-q", f"{self.capture_host}:{remote_path}", str(local_path)],
                timeout=1800,
            )
            if copied_audio.returncode != 0 or not local_path.exists():
                return {"status": "retryable", "reason": "capture_audio_copy_failed"}
            outcome["path"] = str(local_path)
        return outcome
