// src/music/subsonic/api.ts — FROZEN CONTRACT (docs/gpuix-shell/MUSIC.md §6.2).
// The public surface of the Subsonic client. `client.ts` implements it against Navidrome;
// `src/music/testing/fake-subsonic.ts` implements it in memory. Builders may add methods only
// through the integrator; never change a signature here.
//
// Secret rule (MUSIC.md §4): nothing returned by a method of this interface carries a credential,
// except `streamUrl()`, whose result goes to mpv over IPC and nowhere else.
import type * as T from "./types";

export type StarTarget = { id?: string | string[]; albumId?: string | string[]; artistId?: string | string[] };

export interface SearchCounts {
  artist?: number;
  album?: number;
  song?: number;
  artistOffset?: number;
  albumOffset?: number;
  songOffset?: number;
}

export interface AlbumListOptions {
  size?: number; // capped at 500 by the server
  offset?: number;
  genre?: string; // required by type "byGenre"
  fromYear?: number;
  toYear?: number;
}

export type ReportState = "starting" | "playing" | "paused" | "stopped";

/** Why a call failed. `message` never contains a URL, a token, a salt or the username. */
export type SubsonicErrorKind =
  | "credentials" // credential file missing, unreadable or without both keys
  | "unreachable" // DNS, connect, TLS or HTTP-level failure
  | "timeout"
  | "aborted"
  | "auth" // Subsonic 40 / 41
  | "forbidden" // Subsonic 50
  | "not-found" // Subsonic 70
  | "usage" // Subsonic 10 (missing parameter) or a non-audio body where audio was expected
  | "server"; // anything else

export class SubsonicError extends Error {
  constructor(
    public readonly kind: SubsonicErrorKind,
    /** Subsonic error code; negative = HTTP status; 0 = none. */
    public readonly code: number,
    public readonly endpoint: string,
    message: string,
  ) {
    super(message);
    this.name = "SubsonicError";
  }
}

export interface SubsonicApi {
  /** e.g. "http://music.internal" — no credential; used for web links and the offline message. */
  readonly baseUrl: string;

  // system
  ping(signal?: AbortSignal): Promise<T.Ping>;
  extensions(signal?: AbortSignal): Promise<T.Extensions>;
  scanStatus(signal?: AbortSignal): Promise<T.ScanStatus>;

  // browse
  artists(signal?: AbortSignal): Promise<T.Artists>; // 4.6 MB, ~1 s: library cache only
  artist(id: string, signal?: AbortSignal): Promise<T.ArtistResp>;
  album(id: string, signal?: AbortSignal): Promise<T.AlbumResp>;
  song(id: string, signal?: AbortSignal): Promise<T.SongResp>;
  albumList(type: T.AlbumListType, o?: AlbumListOptions, signal?: AbortSignal): Promise<T.AlbumList2>;
  randomSongs(o?: { size?: number; genre?: string; fromYear?: number; toYear?: number }, signal?: AbortSignal): Promise<T.RandomSongs>;
  genres(signal?: AbortSignal): Promise<T.Genres>;
  starred(signal?: AbortSignal): Promise<T.Starred2>;
  playlists(signal?: AbortSignal): Promise<T.Playlists>;
  playlist(id: string, signal?: AbortSignal): Promise<T.PlaylistResp>;

  /** `search3`. Resolves null without a request when `query.trim().length < 2` (an empty query dumps the library). */
  search(query: string, counts?: SearchCounts, signal?: AbortSignal): Promise<T.SearchResult3 | null>;

  // discovery (slow, Last.fm-backed; never on the keystroke path)
  topSongs(artistName: string, count?: number, signal?: AbortSignal): Promise<T.TopSongs>;
  similarSongs(id: string, count?: number, signal?: AbortSignal): Promise<T.SimilarSongs2>; // 2–3 s
  artistInfo(id: string, signal?: AbortSignal): Promise<T.ArtistInfo2>;
  /** Accepts Navidrome's `albumInfo` key as well as `albumInfo2`. */
  albumInfo(id: string, signal?: AbortSignal): Promise<T.AlbumInfoBody>;
  lyrics(songId: string, signal?: AbortSignal): Promise<T.LyricsList>;
  nowPlaying(signal?: AbortSignal): Promise<T.NowPlaying>;
  playQueue(signal?: AbortSignal): Promise<T.PlayQueueByIndex>;

  // writes: only from explicit user actions or real playback, never from tests or probes
  star(target: StarTarget): Promise<void>;
  unstar(target: StarTarget): Promise<void>;
  scrobble(plays: Array<{ id: string; time: number }>, submission: boolean): Promise<void>;
  reportPlayback(r: { mediaId: string; positionMs: number; state: ReportState; ignoreScrobble?: boolean }): Promise<void>;
  savePlayQueueByIndex(ids: string[], currentIndex: number, positionMs: number): Promise<void>;
  createPlaylist(name: string, songIds: string[]): Promise<T.PlaylistResp>;
  updatePlaylist(id: string, o: { name?: string; comment?: string; add?: string[]; removeIndexes?: number[] }): Promise<void>;
  deletePlaylist(id: string): Promise<void>;

  // media
  /** SECRET: a fresh-salt token URL. Hand it to mpv over IPC only; never log, persist or display it. */
  streamUrl(id: string, o?: { maxBitRate?: number; timeOffset?: number }): string;
  /** Cover bytes for the art cache; checks Content-Type (an unknown id answers JSON, not an image). */
  coverArt(coverArtId: string, size: number, signal?: AbortSignal): Promise<{ bytes: Uint8Array; contentType: string }>;
  /** Navidrome web UI link (no credential): `${baseUrl}/app/#/<kind>/<id>/show`. */
  webUrl(kind: "album" | "artist" | "playlist", id: string): string;
}
