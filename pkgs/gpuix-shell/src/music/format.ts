// src/music/format.ts — FROZEN CONTRACT (MUSIC.md §6.1). Display words and figures shared by the
// GPUIX views, the launcher provider, the CLI, the rail chip and the OSD, so every surface says the
// same thing (05 §3.2, §12 format.test). Pure; no I/O.
import type { AlbumRef, PlayerState, TrackRef } from "./types";

const UNKNOWN_ALBUM = "[Unknown Album]";
const UNKNOWN_ARTIST = "[Unknown Artist]";

/** 5:36, 1:02:03 (mono figures role). Negative or NaN → 0:00. */
export function formatDuration(ms: number): string {
  const total = Math.max(0, Math.floor((Number.isFinite(ms) ? ms : 0) / 1000));
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  const ss = String(s).padStart(2, "0");
  return h > 0 ? `${h}:${String(m).padStart(2, "0")}:${ss}` : `${m}:${ss}`;
}

/** "39 min", "1 h 12 min", "2 h", "under a minute". */
export function formatDurationWords(ms: number): string {
  const min = Math.round(Math.max(0, ms) / 60000);
  if (min < 1) return "under a minute";
  const h = Math.floor(min / 60);
  const m = min % 60;
  if (h === 0) return `${m} min`;
  return m === 0 ? `${h} h` : `${h} h ${m} min`;
}

/** "1 song", "38,524 songs". */
export function plural(n: number, one: string, many = `${one}s`): string {
  return `${n.toLocaleString("en-US")} ${n === 1 ? one : many}`;
}

/** "" for 0 (show a play count only when > 0), else "1 play" / "12 plays". */
export function formatPlays(n: number): string {
  return n > 0 ? plural(n, "play") : "";
}

/** "1:12 / 3:40". */
export function formatClock(positionMs: number, durationMs: number): string {
  return `${formatDuration(positionMs)} / ${formatDuration(durationMs)}`;
}

/** Middle truncation by character budget: "Bon Iver, Bo…on Iver". */
export function truncateMiddle(s: string, max: number): string {
  const chars = [...s];
  if (chars.length <= max) return s;
  if (max <= 1) return "…";
  const head = Math.ceil((max - 1) / 2);
  const tail = Math.floor((max - 1) / 2);
  return chars.slice(0, head).join("") + "…" + (tail > 0 ? chars.slice(chars.length - tail).join("") : "");
}

/** End truncation: "For Emma · Bon I…". */
export function truncateEnd(s: string, max: number): string {
  const chars = [...s];
  return chars.length <= max ? s : chars.slice(0, Math.max(0, max - 1)).join("") + "…";
}

/** undefined for Navidrome's placeholder album (53 % of songs are in it). */
export function displayAlbum(name: string | undefined): string | undefined {
  const n = name?.trim();
  return n && n !== UNKNOWN_ALBUM ? n : undefined;
}

export function displayArtist(name: string | undefined): string | undefined {
  const n = name?.trim();
  return n && n !== UNKNOWN_ARTIST ? n : undefined;
}

/** Titles of rips often embed "Artist - Title"; drop the duplicated artist prefix. */
export function displayTitle(t: Pick<TrackRef, "title" | "artist">): string {
  const title = t.title.trim() || "Untitled";
  const artist = displayArtist(t.artist);
  if (!artist) return title;
  for (const sep of [" - ", " – ", " — "]) {
    const prefix = artist + sep;
    if (title.toLowerCase().startsWith(prefix.toLowerCase()) && title.length > prefix.length) {
      return title.slice(prefix.length).trim();
    }
  }
  return title;
}

/** "Artist · Album" (unknowns omitted; "Unknown artist" when nothing is left). */
export function songSubtitle(t: Pick<TrackRef, "artist" | "album">): string {
  const parts = [displayArtist(t.artist), displayAlbum(t.album)].filter(Boolean) as string[];
  return parts.length ? parts.join(" · ") : "Unknown artist";
}

/** "Artist · 2011". */
export function albumSubtitle(a: Pick<AlbumRef, "artist" | "year">): string {
  return [displayArtist(a.artist), a.year ? String(a.year) : undefined].filter(Boolean).join(" · ") || "Album";
}

/** "Title · Artist" for echoes, the chip, the OSD and Copy. */
export function trackLine(t: Pick<TrackRef, "title" | "artist">): string {
  const artist = displayArtist(t.artist);
  return artist ? `${displayTitle(t)} · ${artist}` : displayTitle(t);
}

/** One grapheme for the placeholder tile: first letter or digit, uppercase; "♪" when none. */
export function monogram(name: string | undefined): string {
  const n = (name ?? "").replace(/^(the|a|an)\s+/i, "");
  const m = n.match(/[\p{L}\p{N}]/u);
  return m ? m[0].toLocaleUpperCase() : "♪";
}

/** "just now", "5 min ago", "3 h ago", "3 d ago", "4 mo ago", "2 y ago". */
export function relativeAge(iso: string | undefined, now = Date.now()): string {
  const t = iso ? Date.parse(iso) : NaN;
  if (!Number.isFinite(t)) return "";
  const s = Math.max(0, (now - t) / 1000);
  if (s < 60) return "just now";
  if (s < 3600) return `${Math.floor(s / 60)} min ago`;
  if (s < 86400) return `${Math.floor(s / 3600)} h ago`;
  if (s < 86400 * 30) return `${Math.floor(s / 86400)} d ago`;
  if (s < 86400 * 365) return `${Math.floor(s / (86400 * 30))} mo ago`;
  return `${Math.floor(s / (86400 * 365))} y ago`;
}

/** Client-side position: positionMs + (now − positionAt) while playing, clamped to the duration. */
export function livePositionMs(s: Pick<PlayerState, "status" | "positionMs" | "positionAt" | "track">, now = Date.now()): number {
  const base = s.status === "playing" ? s.positionMs + Math.max(0, now - s.positionAt) : s.positionMs;
  const dur = s.track?.durationMs ?? 0;
  return dur > 0 ? Math.min(base, dur) : Math.max(0, base);
}

/** The state as words (U-03): "Playing", "Paused", "Buffering", "Stopped", "Failed". */
export function statusWord(status: PlayerState["status"]): string {
  return { playing: "Playing", paused: "Paused", buffering: "Buffering", stopped: "Stopped", error: "Failed" }[status];
}

/** One-line now-playing text for the CLI `status`/`now` verbs and the rail chip tooltip-free label. */
export function nowLine(s: PlayerState, now = Date.now()): string {
  if (!s.track) return s.message ?? "Nothing is playing";
  const glyph = s.status === "playing" ? "▶" : s.status === "paused" ? "‖" : "■";
  return `${glyph} ${trackLine(s.track)}  ${formatClock(livePositionMs(s, now), s.track.durationMs)}`;
}
