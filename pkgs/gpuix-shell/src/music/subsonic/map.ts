// src/music/subsonic/map.ts — FROZEN CONTRACT (MUSIC.md §6.2). Subsonic shapes → the shared refs.
// Navidrome omits unset keys (never null): absent playCount = 0, absent starred = not liked.
import type { AlbumRef, ArtistRef, GenreRef, PlaylistRef, TrackRef } from "../types";
import type * as S from "./types";

const secs = (s: number | undefined) => Math.round((s ?? 0) * 1000);

export function toTrackRef(s: S.Song): TrackRef {
  return {
    id: s.id,
    title: (s.title ?? "").trim(),
    artist: s.displayArtist || s.artist || "",
    artistId: s.artistId || undefined,
    album: s.album ?? "",
    albumId: s.albumId || undefined,
    coverArt: s.coverArt || undefined,
    durationMs: secs(s.duration),
    year: s.year,
    track: s.track,
    disc: s.discNumber,
    genre: s.genre,
    liked: s.starred !== undefined,
    playCount: s.playCount ?? 0,
    suffix: s.suffix,
    bitRate: s.bitRate,
  };
}

export function toAlbumRef(a: S.Album): AlbumRef {
  return {
    id: a.id,
    name: (a.name ?? "").trim(),
    artist: a.displayArtist || a.artist || "",
    artistId: a.artistId || undefined,
    year: a.year,
    songCount: a.songCount ?? 0,
    durationMs: secs(a.duration),
    coverArt: a.coverArt || undefined,
    liked: a.starred !== undefined,
    playCount: a.playCount ?? 0,
    releaseTypes: a.releaseTypes?.length ? a.releaseTypes : undefined,
    genre: a.genre,
    created: a.created,
  };
}

export function toArtistRef(a: S.Artist): ArtistRef {
  return {
    id: a.id,
    name: (a.name ?? "").trim(),
    albumCount: a.albumCount ?? 0,
    coverArt: a.coverArt || undefined,
    liked: a.starred !== undefined,
  };
}

export function toPlaylistRef(p: S.Playlist): PlaylistRef {
  return {
    id: p.id,
    name: (p.name ?? "").trim(),
    songCount: p.songCount ?? 0,
    durationMs: secs(p.duration),
    changed: p.changed,
    readonly: !!p.readonly,
    coverArt: p.coverArt || undefined,
    comment: p.comment,
  };
}

export function toGenreRef(g: { value: string; songCount: number; albumCount: number }): GenreRef {
  return { name: g.value, songCount: g.songCount, albumCount: g.albumCount };
}
