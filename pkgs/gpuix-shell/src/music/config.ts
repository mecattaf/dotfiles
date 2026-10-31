// src/music/config.ts — FROZEN CONTRACT (MUSIC.md §6.1). Every environment variable and every
// path the music feature uses, in one place. Tests pass their own `env` with temp XDG dirs and
// never touch the live runtime directory.
import { homedir, userInfo } from "node:os";
import { join } from "node:path";

export interface MusicConfig {
  /** NAVIDROME_URL, trailing slashes trimmed. Default http://music.internal. */
  baseUrl: string;
  /** NAVIDROME_CREDENTIALS_FILE. Default /run/agenix/navidrome-credentials. Read only by subsonic/auth.ts. */
  credentialsFile: string;
  /** NAVIDROME_FAKE=1: in-memory catalogue (testing/fake-subsonic.ts), lavfi tones, no network. */
  fake: boolean;
  /** NAVIDROME_SCROBBLE (default on). 0 = no reportPlayback, no scrobble, nothing written to listening history. */
  scrobble: boolean;
  /** NAVIDROME_SAVE_QUEUE (default on). 0 = never call savePlayQueueByIndex. */
  saveServerQueue: boolean;
  /** NAVIDROME_MAX_BITRATE: kbps; set = format=opus&maxBitRate (thin links). Unset = format=raw. */
  maxBitRate?: number;
  /** GPUIX_SHELL_MPV, else "mpv" on PATH. */
  mpvPath: string;
  /** GPUIX_MUSIC_AO: e.g. "null" for tests and headless runs; unset = mpv's default (pipewire). */
  ao?: string;
  /** GPUIX_SHELL_MPV_DEBUG_SOCKET=1: also expose mpv's IPC at paths.mpvDebugSock (off by default). */
  mpvDebugSocket: boolean;
  /** GPUIX_MUSIC_BITPERFECT=1: --gapless-audio=weak, no forced 48 kHz (04 §4). */
  bitPerfect: boolean;
  paths: MusicPaths;
}

export interface MusicPaths {
  /** $XDG_RUNTIME_DIR/gpuix-shell/music (mode 700). */
  runtimeDir: string;
  ctlSock: string;
  mpvDebugSock: string;
  /** $XDG_RUNTIME_DIR/gpuix-shell/shell.sock — the shell's OSD/notify socket (may be absent). */
  shellSock: string;
  /** $XDG_STATE_HOME/gpuix-shell/music */
  stateDir: string;
  queueFile: string; // queue.json
  nowFile: string; // now.json
  playerStateFile: string; // state.json (volume, muted, normalize, autoplay, output)
  historyFile: string; // history.jsonl
  pendingScrobblesFile: string; // scrobbles-pending.jsonl
  searchesFile: string; // searches.json (recent searches)
  frecencyFile: string; // frecency.json
  /** $XDG_CACHE_HOME/gpuix-shell/music */
  cacheDir: string;
  libraryFile: string; // library.json (the local index; rebuildable)
  artDir: string; // art/<sha1(coverArt)>-<bucket>.<ext>
}

const on = (v: string | undefined, dflt: boolean) => (v === undefined || v === "" ? dflt : v !== "0" && v !== "false");

export function musicPaths(env: Record<string, string | undefined> = process.env): MusicPaths {
  const runtimeRoot = env.XDG_RUNTIME_DIR || `/run/user/${userInfo().uid}`;
  const home = env.HOME || homedir();
  const state = join(env.XDG_STATE_HOME || join(home, ".local/state"), "gpuix-shell/music");
  const cache = join(env.XDG_CACHE_HOME || join(home, ".cache"), "gpuix-shell/music");
  const runtimeDir = join(runtimeRoot, "gpuix-shell/music");
  return {
    runtimeDir,
    ctlSock: join(runtimeDir, "ctl.sock"),
    mpvDebugSock: join(runtimeDir, "mpv.sock"),
    shellSock: join(runtimeRoot, "gpuix-shell/shell.sock"),
    stateDir: state,
    queueFile: join(state, "queue.json"),
    nowFile: join(state, "now.json"),
    playerStateFile: join(state, "state.json"),
    historyFile: join(state, "history.jsonl"),
    pendingScrobblesFile: join(state, "scrobbles-pending.jsonl"),
    searchesFile: join(state, "searches.json"),
    frecencyFile: join(state, "frecency.json"),
    cacheDir: cache,
    libraryFile: join(cache, "library.json"),
    artDir: join(cache, "art"),
  };
}

export function musicConfig(env: Record<string, string | undefined> = process.env): MusicConfig {
  const kbps = Number(env.NAVIDROME_MAX_BITRATE);
  return {
    baseUrl: (env.NAVIDROME_URL || "http://music.internal").replace(/\/+$/, ""),
    credentialsFile: env.NAVIDROME_CREDENTIALS_FILE || "/run/agenix/navidrome-credentials",
    fake: on(env.NAVIDROME_FAKE, false),
    scrobble: on(env.NAVIDROME_SCROBBLE, true),
    saveServerQueue: on(env.NAVIDROME_SAVE_QUEUE, true),
    maxBitRate: Number.isFinite(kbps) && kbps > 0 ? kbps : undefined,
    mpvPath: env.GPUIX_SHELL_MPV || "mpv",
    ao: env.GPUIX_MUSIC_AO || undefined,
    mpvDebugSocket: on(env.GPUIX_SHELL_MPV_DEBUG_SOCKET, false),
    bitPerfect: on(env.GPUIX_MUSIC_BITPERFECT, false),
    paths: musicPaths(env),
  };
}

/** Search timing and caps (05 §5.3, §8). */
export const SEARCH = {
  minServerChars: 2,
  serverDebounceMs: 60,
  serverCounts: { artist: 6, album: 12, song: 24 },
  scopePage: 60,
  caps: { songs: 4, artists: 3, albums: 6, playlists: 4 },
  lruSize: 50,
} as const;
