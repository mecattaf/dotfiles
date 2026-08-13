"""Identity gates shared by source resolution and recorded verification."""

from __future__ import annotations

import re
import unicodedata
from typing import Iterable


BER_ACCEPT = 0.15
DUR_TOL_ACOUSTIC = 12.0
DUR_TOL_ISRC = 3.0
DUR_TOL_METADATA = 2.0

VERSION_WORDS = {
    "remix",
    "mix",
    "edit",
    "version",
    "live",
    "acoustic",
    "instrumental",
    "instrumentale",
    "dub",
    "vip",
    "rework",
    "bootleg",
    "radio",
    "extended",
    "remaster",
    "remastered",
    "reprise",
    "demo",
    "cover",
    "unplugged",
    "session",
    "interlude",
    "intro",
    "outro",
    "club",
    "original",
}

NOISE_WORDS = {
    "official",
    "video",
    "audio",
    "music",
    "lyric",
    "lyrics",
    "visualizer",
    "visualiser",
    "hd",
    "hq",
    "4k",
    "1080p",
    "720p",
    "mv",
    "clip",
    "full",
    "stream",
    "streaming",
    "new",
    "out",
    "now",
    "free",
    "download",
    "premiere",
    "topic",
    "provided",
    "youtube",
    "records",
    "recordings",
    "release",
    "explicit",
}

FEAT_RE = re.compile(r"\b(feat|ft|featuring|avec|with)\b.*", re.I)


def norm(value: str | None) -> str:
    if not value:
        return ""
    value = unicodedata.normalize("NFKD", value)
    value = "".join(char for char in value if not unicodedata.combining(char))
    value = value.lower().replace("&", " and ").replace("’", "'")
    value = re.sub(r"[^a-z0-9]+", " ", value)
    return re.sub(r"\s+", " ", value).strip()


def core_and_version(title: str | None) -> tuple[list[str], set[str]]:
    value = norm(FEAT_RE.sub("", title or ""))
    tokens = [token for token in value.split() if token]
    version = {token for token in tokens if token in VERSION_WORDS}
    core = [
        token
        for token in tokens
        if token not in VERSION_WORDS
        and token not in NOISE_WORDS
        and not (len(token) == 1 and token.isdigit())
    ]
    return core, version


def version_signature(markers: Iterable[str]) -> set[str]:
    return set(markers) - {"original", "mix", "club", "version"}


def version_agrees(left: Iterable[str], right: Iterable[str]) -> bool:
    return version_signature(left) == version_signature(right)


def core_agrees(left: Iterable[str], right: Iterable[str]) -> bool:
    """Use the campaign's containment rule without fuzzy similarity."""
    left_set, right_set = set(left), set(right)
    if not left_set or not right_set:
        return False
    shorter, longer = (
        (left_set, right_set)
        if len(left_set) <= len(right_set)
        else (right_set, left_set)
    )
    missing = shorter - longer
    return not missing or (
        len(missing) == 1
        and len(shorter) >= 4
        and all(len(token) <= 3 for token in missing)
    )


def title_agrees(
    reference: str | None,
    candidate: str | None,
    allowed_context: Iterable[str] = (),
) -> bool:
    """Require every candidate title token to be explained by identity context.

    Artist/album/label tokens may decorate an upload title.  Unexplained title
    tokens may name another movement or version (``Part Two``), so accepting
    them merely because the shorter title is contained would violate the exact-
    recording bar.
    """
    ref_core, ref_version = core_and_version(reference)
    got_core, got_version = core_and_version(candidate)
    if not ref_core or not got_core or not version_agrees(ref_version, got_version):
        return False
    reference_tokens, candidate_tokens = set(ref_core), set(got_core)
    if not reference_tokens.issubset(candidate_tokens):
        return False
    allowed_tokens: set[str] = set()
    for value in allowed_context:
        allowed_tokens.update(core_and_version(value)[0])
    return (candidate_tokens - reference_tokens).issubset(allowed_tokens)


def artist_agrees(artists: Iterable[str], candidate_text: str | None) -> bool:
    haystack = norm(candidate_text)
    for artist in artists:
        for piece in re.split(r"[,&/]| x | and ", artist or ""):
            needle = norm(piece)
            if len(needle) >= 3 and needle in haystack:
                return True
    return False


def metadata_verdict(
    *,
    reference_titles: Iterable[str],
    reference_artists: Iterable[str],
    candidate_title: str,
    candidate_channel: str,
    candidate_duration_s: float,
    source_duration_s: float | None,
    mb_recording: dict | None,
    reference_context: Iterable[str] = (),
) -> tuple[str | None, dict | str]:
    """Apply the ISRC or metadata bar and return auditable evidence."""
    titles = [title for title in reference_titles if title]
    artists = [artist for artist in reference_artists if artist]
    if not any(
        title_agrees(title, candidate_title, [*artists, *reference_context])
        for title in titles
    ):
        return None, "title_or_version_mismatch"
    if not artist_agrees(artists, f"{candidate_title} {candidate_channel}"):
        return None, "artist_mismatch"

    mb_length_ms = (mb_recording or {}).get("length_ms")
    if (
        mb_recording
        and mb_recording.get("isrc")
        and mb_length_ms
        and source_duration_s is not None
    ):
        mb_duration_s = float(mb_length_ms) / 1000.0
        if (
            abs(candidate_duration_s - source_duration_s) <= DUR_TOL_ISRC
            and abs(candidate_duration_s - mb_duration_s) <= DUR_TOL_ISRC
        ):
            return "isrc", {
                "isrc": (mb_recording or {}).get("isrc"),
                "mb_recording": (mb_recording or {}).get("mbid"),
                "mb_title": (mb_recording or {}).get("title"),
                "mb_artist": (mb_recording or {}).get("artist"),
                "dur_ref_s": round(source_duration_s, 1),
                "dur_mb_s": round(mb_duration_s, 1),
                "dur_got_s": round(candidate_duration_s, 1),
            }
        return None, "duration_outside_isrc_tolerance"

    reference_duration = source_duration_s
    if reference_duration is None and mb_length_ms:
        reference_duration = float(mb_length_ms) / 1000.0
    if reference_duration is None:
        return None, "no_reference_duration"
    if abs(candidate_duration_s - reference_duration) <= DUR_TOL_METADATA:
        return "metadata", {
            "matched_title": titles[0] if titles else "",
            "dur_ref_s": round(reference_duration, 1),
            "dur_got_s": round(candidate_duration_s, 1),
        }
    return None, "duration_outside_metadata_tolerance"
