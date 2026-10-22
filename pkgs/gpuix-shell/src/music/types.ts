// src/music/types.ts — FROZEN CONTRACT (docs/gpuix-shell/MUSIC.md §6.1).
// Shared by every music module: the daemon/service, the ctl.sock protocol, the CLI, the launcher
// provider, the GPUIX views, the rail chip and the tests. Grown from 05-ux-spec.md §9.2; the
// differences are listed in MUSIC.md §6.1. Pure types: no runtime code, no @gpuix import.
//
// Secret rule: no value of any type in this file ever holds a credential or a tokenised URL.
// Art reaches clients as LOCAL FILE PATHS; links are Navidrome web-UI links (no auth).
import type { ArtBucket, Route } from "../launcher/provider";

export type { ArtBucket };

// ── catalogue atoms (what rows, queues and the player carry) ────────────────────────────────

export type MusicKind = "song" | "album" | "artist" | "playlist" | "genre";

export interface TrackRef {
  id: string;
  title: string;
  /** Subsonic `displayArtist` (falls back to `artist`). */
  artist: string;
  artistId?: string;
  album: string;
  albumId?: string;
  coverArt?: string;
  /** From Subsonic `duration` (s) × 1000; 0 when the server has none. */
  durationMs: number;
  year?: number;
  track?: number;
  disc?: number;
  genre?: string;
  /** Subsonic `starred` present. */
  liked: boolean;
  /** Absent on the server = 0. */
  playCount: number;
  suffix?: string;
  bitRate?: number;
}

export interface AlbumRef {
  id: string;
  name: string;
  artist: string;
  artistId?: string;
  year?: number;
  songCount: number;
  durationMs: number;
  coverArt?: string;
  liked: boolean;
  playCount: number;
  releaseTypes?: string[];
  genre?: string;
  /** ISO date the album was added (`created`). */
  created?: string;
}

export interface ArtistRef {
  id: string;
  name: string;
  albumCount: number;
  coverArt?: string;
  liked: boolean;
}

export interface PlaylistRef {
  id: string;
  name: string;
  songCount: number;
  durationMs: number;
  /** ISO date. */
  changed: string;
  readonly: boolean;
  coverArt?: string;
  comment?: string;
}

export interface GenreRef {
  name: string;
  songCount: number;
  albumCount: number;
}

// ── search ─────────────────────────────────────────────────────────────────────────────────

export type SearchScope = "all" | "songs" | "albums" | "artists" | "playlists";

export type SearchHit =
  | { kind: "song"; song: TrackRef; score: number }
  | { kind: "album"; album: AlbumRef; score: number }
  | { kind: "artist"; artist: ArtistRef; score: number }
  | { kind: "playlist"; playlist: PlaylistRef; score: number };

/**
 * One complete snapshot for (query, scope, offset). The search stream yields the local-index
 * partial first (final = false), then the merged result (final = true); each replaces the last.
 * Lists are already ranked (MUSIC.md §5.3) and de-duplicated by id.
 */
export interface MusicSearchResult {
  query: string;
  scope: SearchScope;
  offset: number;
  final: boolean;
  top: SearchHit | null;
  songs: TrackRef[];
  artists: ArtistRef[];
  albums: AlbumRef[];
  playlists: PlaylistRef[];
  /** A further page exists for that section (scope views page on scroll). */
  more: { songs: boolean; artists: boolean; albums: boolean; playlists: boolean };
  /** Honest states (U-04): the server half and the local index half. */
  server: "pending" | "done" | "failed" | "skipped";
  index: "ready" | "building" | "absent";
  /** For the footer/debug only; never logged with the query text. */
  timing?: { localMs: number; serverMs?: number };
}

// ── pages (drill-down views) ─────────────────────────────────────────────────────────────────

export interface AlbumPage {
  album: AlbumRef;
  /** Disc/track order as the server returns it. */
  tracks: TrackRef[];
  discTitles: Array<{ disc: number; title: string }>;
}

export interface ArtistPage {
  artist: ArtistRef;
  /** Markdown, HTML stripped; absent when Navidrome has none. */
  biography?: string;
  /** `getTopSongs` (Last.fm); may be short or empty. */
  popular: TrackRef[];
  popularSource: "lastfm" | "plays" | "none";
  /** Filled from the artist's songs by playCount when `popular` has fewer than 5. */
  mostPlayed: TrackRef[];
  /** Newest first, split by OpenSubsonic releaseTypes; "[Unknown Album]" sorts last. */
  albums: AlbumRef[];
  singles: AlbumRef[];
  compilations: AlbumRef[];
  appearsOn: AlbumRef[];
  /** In-library similar artists only. */
  similar: ArtistRef[];
}

export interface PlaylistPage {
  playlist: PlaylistRef;
  tracks: TrackRef[];
}

export type AlbumShelf = "recent" | "newest" | "frequent" | "random" | "starred" | "highest" | "alphabeticalByName";

export interface HomePage {
  /** The loaded track (or the restored queue head); null hides the Continue section. */
  continue: {
    track: TrackRef;
    status: PlayerStatus;
    upNext: number;
    contextRemaining: number;
    context: PlayContext | null;
  } | null;
  /** Non-empty shelves only, in this order: recent, newest, frequent, random. ≤ 5 albums each. */
  shelves: Array<{ id: AlbumShelf; title: string; albums: AlbumRef[] }>;
  /** Newest first, ≤ 10. */
  recentSearches: string[];
  counts: { songs: number; albums: number; artists: number; playlists: number } | null;
}

export interface LikedPage {
  songs: TrackRef[];
  albums: AlbumRef[];
  artists: ArtistRef[];
}

export interface LyricsDoc {
  synced: boolean;
  lines: Array<{ startMs?: number; text: string }>;
  offsetMs?: number;
  source: "navidrome" | "lrclib";
}

export interface OutputSink {
  /** mpv audio-device name, e.g. "auto" or "pipewire/alsa_output…". */
  name: string;
  description: string;
  active: boolean;
}

// ── player and queue ─────────────────────────────────────────────────────────────────────────

export type PlayContext =
  | { kind: "album" | "playlist" | "artist"; id: string; name: string }
  | { kind: "radio"; seed: RadioSeed; name: string }
  | { kind: "search"; query: string; name: string }
  | { kind: "genre"; name: string }
  | { kind: "liked" | "library-shuffle" | "queue"; name: string };

export type RepeatMode = "off" | "all" | "one";
export type PlayerStatus = "stopped" | "buffering" | "playing" | "paused" | "error";
export type ServerStatus = "online" | "offline" | "unauthorized" | "indexing";

export interface PlayerState {
  /** Increments on every change; clients drop older events. */
  seq: number;
  status: PlayerStatus;
  track: TrackRef | null;
  /**
   * Position at `positionAt`. `positionAt` is EPOCH ms (Date.now()), not a monotonic clock:
   * under bun no monotonic clock is shared between processes (04 §8, measured). Clients
   * extrapolate with livePositionMs() in format.ts while status = "playing".
   */
  positionMs: number;
  positionAt: number;
  /** Player (mpv) volume 0..100; the system volume stays with ~/.local/bin/volume. */
  volume: number;
  muted: boolean;
  shuffle: boolean;
  repeat: RepeatMode;
  context: PlayContext | null;
  /** Counts only; the full queue comes from queue(). */
  upNext: number;
  contextRemaining: number;
  queueRev: number;
  /** PipeWire sink description. */
  output?: string;
  server: ServerStatus;
  /** Local cover path for the current track at bucket 96 (rail chip, OSD). */
  artPath?: string;
  /** "End of queue" is a status message, not an error. */
  message?: string;
  error?: { message: string; fix?: string };
}

export interface QueueSnapshot {
  rev: number;
  current: TrackRef | null;
  /** "Next in queue": user-added, played first. */
  upNext: TrackRef[];
  context: PlayContext | null;
  /** Remaining context in play order (shuffled when shuffle is on). */
  contextNext: TrackRef[];
  /** Last 20, newest first. */
  history: TrackRef[];
}

// ── commands (every state change, from any client) ───────────────────────────────────────────

export type RadioSeed = { kind: "song" | "artist" | "album"; id: string };
export type LikeTarget = { kind: "song" | "album" | "artist"; id: string };

/**
 * What to play. `track` carries metadata the client already holds, so no refetch is needed;
 * album/playlist/artist/genre ids are resolved by the backend; `query` plays the top result
 * ("Just Play", `gpuix-shell music play "bon iver"`).
 */
export type PlayItem =
  | { kind: MusicKind; id: string }
  | { kind: "track"; track: TrackRef }
  | { kind: "query"; query: string };

export type MusicCommand =
  | { cmd: "play"; items: PlayItem[]; context?: PlayContext; startIndex?: number; shuffle?: boolean }
  | { cmd: "enqueue"; items: PlayItem[]; where: "next" | "end" }
  | { cmd: "toggle" | "play-resume" | "pause" | "next" | "previous" | "stop" }
  | { cmd: "seek"; seconds: number; relative: boolean }
  | { cmd: "volume"; value: number; relative: boolean }
  | { cmd: "mute"; on?: boolean }
  | { cmd: "shuffle"; on?: boolean }
  | { cmd: "repeat"; mode?: RepeatMode }
  | { cmd: "like"; target: LikeTarget | "current"; on?: boolean }
  | { cmd: "radio"; seed: RadioSeed | "current" }
  | { cmd: "shuffle-all" }
  | { cmd: "queue.move"; rev: number; from: number; to: number }
  | { cmd: "queue.remove"; rev: number; indexes: number[] }
  | { cmd: "queue.clear"; rev: number; part: "up-next" | "all" }
  | { cmd: "queue.jump"; rev: number; index: number }
  | { cmd: "queue.restore"; snapshot: QueueSnapshot }
  | { cmd: "playlist.add"; playlistId: string; songIds: string[] }
  | { cmd: "playlist.create"; name: string; songIds: string[] }
  | { cmd: "output"; sink: string }
  | { cmd: "recent-search.add"; query: string }
  | { cmd: "recent-search.remove"; query?: string } // no query = remove all
  | { cmd: "rescan" }; // revalidate the library index now (Ctrl+R)

export interface MusicError {
  code:
    | "daemon"
    | "offline"
    | "unauthorized"
    | "forbidden"
    | "not-found"
    | "stale-rev"
    | "nothing-playing"
    | "usage"
    | "player";
  /** What happened (U-17). Never a URL, token or username. */
  message: string;
  /** What to do. */
  fix?: string;
}

export type CommandOrigin = "ui" | "cli" | "mpris" | "chip" | "sway";

/** Commands resolve (never reject) with an outcome; the echo is the same text everywhere (UI footer, CLI, OSD). */
export type MusicOutcome =
  | { ok: true; echo?: string; undo?: MusicCommand }
  | { ok: false; error: MusicError };

// ── the backend every client talks to (in-process service, ctl.sock client, fakes) ───────────

export interface MusicBackend {
  readonly kind: "local" | "socket" | "fake";
  /** Last known state, synchronously. */
  state(): PlayerState;
  /** Called at once with the current state, then on every change. Returns unsubscribe. */
  watch(listener: (state: PlayerState) => void): () => void;
  /** Local partial first, merged final second; a new call should abort the previous signal. */
  search(query: string, opts?: { scope?: SearchScope; offset?: number; signal?: AbortSignal }): AsyncIterable<MusicSearchResult>;
  home(signal?: AbortSignal): Promise<HomePage>;
  album(id: string, signal?: AbortSignal): Promise<AlbumPage>;
  artist(id: string, signal?: AbortSignal): Promise<ArtistPage>;
  playlist(id: string, signal?: AbortSignal): Promise<PlaylistPage>;
  playlists(signal?: AbortSignal): Promise<PlaylistRef[]>;
  albums(shelf: AlbumShelf, o?: { offset?: number; size?: number }, signal?: AbortSignal): Promise<AlbumRef[]>;
  liked(signal?: AbortSignal): Promise<LikedPage>;
  genres(signal?: AbortSignal): Promise<GenreRef[]>;
  queue(signal?: AbortSignal): Promise<QueueSnapshot>;
  lyrics(songId: string, signal?: AbortSignal): Promise<LyricsDoc | null>;
  /** Local file path of the cover at that bucket, or null (draw the placeholder). Never a URL. */
  art(coverArt: string, bucket: ArtBucket, signal?: AbortSignal): Promise<string | null>;
  /** Navidrome web-UI link (no credential); songs link to their album. */
  link(kind: "album" | "artist" | "playlist" | "song", id: string): Promise<string>;
  outputs(signal?: AbortSignal): Promise<OutputSink[]>;
  /**
   * Every state change. Resolves, never rejects. `origin` tells the service whether to send an
   * OSD (transport from outside the UI: cli, mpris, chip, sway) or let the footer echo (ui).
   */
  run(command: MusicCommand, o?: { origin?: CommandOrigin }): Promise<MusicOutcome>;
  dispose(): Promise<void>;
}

// ── ctl.sock wire protocol ($XDG_RUNTIME_DIR/gpuix-shell/music/ctl.sock, JSON lines) ─────────

export type MusicQuery =
  | { cmd: "hello" } // → { protocol: 1, backend: "local" | "fake", pid: number }
  | { cmd: "state" }
  | { cmd: "watch" } // turns the connection into an event stream
  | { cmd: "search"; query: string; scope?: SearchScope; offset?: number } // partial lines, then the final
  | { cmd: "home" }
  | { cmd: "album"; id: string }
  | { cmd: "artist"; id: string }
  | { cmd: "playlist"; id: string }
  | { cmd: "playlists" }
  | { cmd: "albums"; shelf: AlbumShelf; offset?: number; size?: number }
  | { cmd: "liked" }
  | { cmd: "genres" }
  | { cmd: "queue.get" }
  | { cmd: "lyrics"; id: string }
  | { cmd: "art"; coverArt: string; bucket: ArtBucket }
  | { cmd: "link"; kind: "album" | "artist" | "playlist" | "song"; id: string }
  | { cmd: "outputs" }
  | { cmd: "cancel"; target: number }; // abort the request with that id (search on the next keystroke)

export type MusicRequest = MusicCommand | MusicQuery;

/** Every request line is `{ "id": n, ...MusicRequest }`; responses echo the id. `origin` applies to commands. */
export type MusicRequestFrame = MusicRequest & { id: number; origin?: CommandOrigin };

export type MusicResponse =
  | { id: number; ok: true; partial?: boolean; result: unknown }
  | { id: number; ok: false; error: MusicError }
  | { event: "state"; state: PlayerState }
  | { event: "queue"; rev: number }
  | { event: "index"; status: ServerStatus; artists: number; albums: number };

// ── launcher row payload (MusicProvider puts this in Row.data) ───────────────────────────────

export type MusicRowData =
  | { kind: "song"; song: TrackRef; context?: PlayContext; index?: number }
  | { kind: "album"; album: AlbumRef }
  | { kind: "artist"; artist: ArtistRef }
  | { kind: "playlist"; playlist: PlaylistRef }
  | { kind: "genre"; name: string; songCount: number; albumCount: number }
  | { kind: "link"; route: Route; count?: string }
  | { kind: "recent-search"; query: string }
  | { kind: "command"; command: MusicCommand };
