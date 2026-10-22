# 04 — The playback engine (mpv child over fd IPC, our own MPRIS2 server, a queue we own)

Written 2026-10-20 late evening by the music workflow's playback-engine designer (Claude, Opus 5.5)
for the builders of slice A ("Daemon core") and slice E's MPRIS half in
[05 §13](05-ux-spec.md).

- Everything marked **measured** was run on the strix tonight. The runs used `--ao=null`, so no
  PipeWire stream was opened, and a private `dbus-run-session` bus, so the live session bus never
  saw a test player. Probes and raw outputs are in [`evidence/04-playback/`](evidence/04-playback/),
  listed in §17.
- **Design** means decided, not yet built.
- **Unverified** means a claim that was not checked.

**Inputs:**

- BRIEF §5 (Tom's music order).
- [01](01-raycast-spotify-model.md), the Spotify/Raycast model and keymap.
- [02](02-navidrome-ext-and-cliamp.md), Navidrome endpoints and cliamp's engine.
- [03](03-subsonic-api-live.md), the live API reference.
- [05](05-ux-spec.md), the UX spec. **05 §9.2 owns the wire contract** (`ctl.sock` requests,
  `PlayerState`, `QueueSnapshot`, `TrackRef`, `PlayContext`), and **05 §10 owns the player
  semantics the UX promises**.

This doc owns what happens *inside* the daemon to keep those promises. Where it departs from 05,
§15 says so and why.

---

## 0. The decision in one paragraph

Playback runs in the headless daemon **`gpuix-shell music serve`** (05 §2; user unit
`gpuix-shell-music.service`, no GPUIX window). It owns:

- one **mpv 0.41** child, controlled over JSON IPC carried on an **inherited socketpair**
  (`--input-ipc-client=fd://3`) rather than a socket file;
- the **queue**: entries in play order with a current index, shuffle, repeat, and the
  "Next in queue" segment;
- a **two-entry mpv playlist window** (current + successor), which gives gapless and prefetched
  transitions;
- the **play reporter** (`reportPlayback` plus last.fm-rule submissions);
- **persistence**: local files with no URLs, plus Navidrome's index-based server queue;
- an **MPRIS2 server of our own**, `org.mpris.MediaPlayer2.gpuix_music` (05 §6), via `dbus-next`
  0.10.2.

Sway's F3–F5 and XF86Audio keys, `playerctl`, the OSD and the rail chip therefore reach Navidrome
playback through the same MPRIS path as Chrome or Spotify. The launcher and the rail are thin
clients on `$XDG_RUNTIME_DIR/gpuix-shell/music/ctl.sock` (05 §9.2), so closing the launcher never
stops the music. Option (b) is impossible: GPUIX has no audio API. Option (c), `pw-play`, is
rejected. mpv-mpris is **not** active in the installed mpv, and we would not use it even if it
were (§1.2).

## 1. Options weighed

### 1.1 (b) GPUIX has no audio API — confirmed

`@gpuix/native@0.11.0` (`probe011/node_modules/@gpuix/native/index.d.ts`, 804 lines) exports:

- the classes `GpuixRenderer`, `TestGpuixRenderer` and `AvailableUpdate`;
- the functions `checkUpdate`, `hasTestGpuixRenderer` and `isTerminal`;
- the window, layer-shell, path-prompt, event, bounds and highlight interfaces.

`grep -niE "audio|sound|media|play"` hits only a "display link" comment. The renderer draws and
nothing else, so audio must come from a separate process.

### 1.2 (a) mpv — chosen; mpv-mpris present in the store but not in Tom's mpv

- `/etc/profiles/per-user/tom/bin/mpv` resolves to `/nix/store/s7v1my9l…-mpv-with-scripts-0.41.0`
  (mpv v0.41.0, FFmpeg 8.1.2, libplacebo v7.360.1). Its makeCWrapper adds only `LUA_PATH`,
  `LUA_CPATH` and `yt-dlp` on `PATH`, with **no `--script=`**.
  `/etc/profiles/per-user/tom/share/mpv/scripts` does not exist. `home/home.nix:476` installs
  plain `mpv` (and `playerctl`, line 449) for every Home Manager host, the Zenbook included.
- `/nix/store/byx28nhj…-mpv-mpris-1.2/share/mpv/scripts/mpris.so` *is* in the store. Its only
  referrer is another `mpv-with-scripts-0.41.0` (`fgy2321m…`), reachable from two older
  `system-path` generations. Its wrapper has
  `--add-flags '--script=…/mpv-mpris-1.2/share/mpv/scripts/mpris.so'`. That wrapper is not on
  the current `PATH`, and the current system path has no `mpv` at all. So `pkgs.mpvScripts.mpris`
  is packaged in nixpkgs, but **absent from the mpv Tom runs**.
- Why we would not use mpv-mpris even if it were wired in:
  1. It publishes **mpv's** playlist and transport. Our mpv only ever holds two entries (§5), so
     Next/Previous from a media key would bypass the queue's shuffle, repeat and "Next in queue"
     rules.
  2. Its identity is `mpv`. Any other mpv the user runs, such as a video, collides with it.
  3. Its metadata comes from the file tags and mpv's `path`. **Measured**: `path` contains the
     Subsonic `u`/`t`/`s` query parameters (`pathLeaksAuth: true` in `nav-yes.json`). Publishing
     it as `xesam:url` would hand a replayable credential to every session-bus reader.
     (From reading mpv-mpris, not measured: it sets `xesam:url` from the path.)
  4. It has no Navidrome cover art, likes or play counts.
- `mpv --list-options` (0.41) confirms every flag used here: `--input-ipc-client`,
  `--input-ipc-server`, `--prefetch-playlist`, `--gapless-audio`, `--audio-client-name`,
  `--replaygain*`, `--volume-max`, `--load-scripts`, `--scripts`.

### 1.3 (c) PipeWire direct (`pw-play`) — rejected

It plays files through libsndfile. It has no HTTP input, no AAC/M4A (05 §1 measured m4a 257 kbps
streams on Tom's server), no seek control, no gapless successor and no IPC. Volume and output
routing still go through PipeWire, because mpv's default output there is `ao=pipewire` (§10).

## 2. What was measured tonight

| # | Measurement | Result | Evidence |
|---|---|---|---|
| M1 | **Brief's required probe:** `mpv --no-video --idle --input-ipc-server=<sock>` in the background under `timeout 5`, then `{"command":["get_property","mpv-version"]}` through socat | `{"data":"mpv v0.41.0","request_id":1,"error":"success"}`, 4–5 ms including socat startup. `idle-active` true. `current-ao` "property unavailable" while idle. `user-data/gpuix/owner` set and read back | `socat-probe.sh`, `socat-probe.out` |
| M2 | Socket file after mpv exits (SIGTERM from `timeout`, and a clean IPC `quit`) | **The socket file stays behind**; a connect gives `Connection refused`. A new mpv binds over the stale path without complaint. Lesson: test liveness by connecting, never by file existence, and unlink only our own exact path | `socat-probe.out` |
| M3 | IPC over an inherited socketpair: `spawn(mpv, [... "--input-ipc-client=fd://3"], {stdio:[…,"pipe"]})` | Works from **bun 1.4.2 and node 24.18**. First reply in about 32 ms, which is mpv startup. No file, so other processes cannot command our mpv | `fd-ipc.mjs`, `fd-ipc.out` |
| M4 | SIGKILL the parent of an fd-IPC mpv | **mpv exits within 0.8 s**, so a daemon crash never leaves orphaned audio | `orphan.mjs`, `orphan.out` |
| M5 | Event sequence of a two-entry window, with `playlist-remove 0` + `loadfile … append` on every advance (local FLAC/MP3 tones) | `end-file eof` → `start-file` → `playlist-pos 1` → (our remove) `playlist-pos 0` → `file-loaded` → `playback-restart`. `playlist-count` stays at 2. **Same-format transition 0–1 ms**. `time-pos` arrives at **≈10 Hz** (154 events in 15 s, median gap 99 ms, max 543 ms around a reconfigure) | `events.mjs`, `events.out` |
| M6 | A real Navidrome stream (Justice, "Ohio", MP3 320k, 241 s) loaded by IPC `loadfile` | **87 ms from loadfile to first audio** (68 ms on the second run). Seek to 150 s took 4–5 ms (HTTP Range). After 1.5 s the whole song was cached (`eof` cached, 5.4 MB forward). Tags include `replaygain_*`. `audio-params` 44.1 kHz stereo | `nav-stream.mjs`, `nav-yes.json`, `nav-no.json` |
| M7 | Navidrome track-to-track transition (seek to end − 4 s, successor appended) | **2 ms with `--prefetch-playlist=yes`**, 12 ms without (one run each, on the LAN) | same |
| M8 | Failure shapes: bogus song id / wrong credentials / unreachable host | `end-file reason=error`. `file_error` is `"unrecognized file format"` for **both** the bogus id and the bad credentials, so the server's JSON error body is fed to the demuxer. Unreachable gives `"loading failed"`. mpv cannot tell auth from not-found, so the engine diagnoses with an API call (§12) | `nav-errors.mjs`, `nav-errors.json` |
| M9 | Does mpv leak the token? | **Yes, twice, at default verbosity.** (1) stdout prints `Playing: http://…?u=…&t=…&s=…`. (2) On a load failure the built-in **ytdl_hook runs even under `--no-config`** and hands the authenticated URL to `yt-dlp` as a subprocess, on its argv. With the production argv (§4: `--ytdl=no --no-terminal --msg-level=all=error`) stderr is empty and nothing leaks | `nav-stream.mjs`, `nav-errors.json`, `final-argv.json` |
| M10 | Gapless across a sample-rate change (44.1 kHz FLAC → 48 kHz MP3) | `--gapless-audio=weak`: **494 ms gap**. `--gapless-audio=yes`: 1 ms. With `--gapless-audio=yes --audio-samplerate=48000`, 22.05 k → 44.1 k → 48 k gives 1 ms + 1 ms, and `audio-out-params` stays at 48000 | `final-argv.json`, `rate48.out`, `lavfi.out` |
| M11 | Fixture-free test audio: `loadfile av://lavfi:sine=frequency=440:duration=1.5` | Plays, gapless advance works, and `duration` is refined progressively (0.88 → 1.49) | `lavfi.mjs`, `lavfi.out` |
| M12 | Named-argument `loadfile` with a per-file `start` option, mpv started `--pause=yes` | `{"name":"loadfile","url":…,"flags":"replace","options":{"start":"4.5"}}` gives time-pos 4.5 and still paused. The appended successor starts at 0, so per-file options do not leak | `loadfile-start.mjs`, `loadfile-start.out` |
| M13 | MPRIS2 server in bun via dbus-next 0.10.2, on a **private bus** (`dbus-run-session`), driven by `playerctl` | `playerctl -l` lists the player. Metadata renders (`Justice — Civilization [3:38]`). `play-pause`, `next`, `previous`, `position 30`, `position 5+`, `volume 0.5`, `shuffle on` and `loop Playlist` all reached our handlers, and `PlaybackStatus` changed through `PropertiesChanged`. (The probe registered `…gpuixshell`, the name first suggested; §11 adopts 05's `gpuix_music`. The code is name-agnostic) | `mpris-probe.mjs`, `mpris-run.sh`, `mpris-run.out` |
| M14 | Server play queue, **read only** (`getPlayQueueByIndex`, `getPlayQueue`) | Both answer `ok` with no entries, `changedBy ""`, `changed 0001-01-01T00:00:00Z`. No other client uses the server queue today, so saving to it overwrites nothing | `queue-read.mjs`, `queue-read.json` |
| — | OpenSubsonic extensions (sibling probe, 02 §4 and 03) | `transcodeOffset`, `formPost`, `songLyrics` 1–2, **`indexBasedQueue`**, `transcoding`, **`playbackReport`** | 02 §4 |

None of tonight's probes called `scrobble`, `reportPlayback`, `savePlayQueue*` or `star`,
because those write to Tom's listening history or server state. They are specified below and
remain **unverified against the live server**.

## 3. Process architecture (inside 05 §2's box)

```
 Sway binds (F3–F5, XF86Audio*) ─► ~/.local/bin/media ─► playerctl ─┐
 rail chip / OSD ── ctl.sock watch (05) or MPRIS (other players) ───┤ session bus
                                                                    ▼
 ┌──────────────── gpuix-shell-music.service (bun, `gpuix-shell music serve`) ─────────────┐
 │ daemon/mpris.ts   org.mpris.MediaPlayer2.gpuix_music  (/org/mpris/MediaPlayer2)          │
 │        ▲                                                                                 │
 │ daemon/player.ts ── queue.ts (pure) ── scrobble.ts ── playqueue-sync.ts ── art-cache.ts  │
 │        │                                                                                 │
 │ daemon/player-mpv.ts ──fd://3 socketpair (JSON IPC)──► mpv --idle (child, ao=pipewire)   │
 │        │                                                     │ HTTP; token URL via IPC only
 │ daemon/server.ts  $XDG_RUNTIME_DIR/gpuix-shell/music/ctl.sock (05 §9.2)                  │
 └────────▲─────────────────────────────────────────────────────┼──────────────────────────┘
          │ JSON lines                                          ▼
 launcher MusicProvider, rail chip, `gpuix-shell music <verb>`   Navidrome 0.63.2 (music.internal)
```

- **Why fd IPC and not an mpv socket file** (05 §2 drew `music/mpv.sock`). Measured in M2–M4.
  - There is no socket file to go stale, collide or need cleaning, and no other process can
    drive our mpv.
  - mpv dies with its parent, so a daemon crash leaves no orphaned audio.
  - The daemon never touches its runtime directory beyond its own `ctl.sock` (the Sept-16 lesson).

  For poking at it by hand, set `GPUIX_SHELL_MPV_DEBUG_SOCKET=1`. The engine then *also* passes
  `--input-ipc-server=$XDG_RUNTIME_DIR/gpuix-shell/music/mpv.sock` (05's path), so `socat` works
  as in M1. The daemon unlinks that exact path on exit. It is off by default.
- **mpv binary.** In Nix, `${pkgs.mpv}/bin/mpv`, the same wrapper as measured (scripts list
  empty), baked into the wrapper as `GPUIX_SHELL_MPV`. In dev, the environment variable or `mpv`
  on `PATH`.
- **Runtime.** bun, like the rest of the shell (the desktop-shell precedent wraps `bun`). Every
  probe ran under bun 1.4.2, and M3 also under node 24.18.

## 4. The mpv invocation (production argv)

```ts
export const MPV_ARGS = [
  "--no-config",              // ignore ~/.config/mpv entirely (scripts, profiles, input.conf)
  "--idle=yes",               // stay alive with an empty playlist
  "--no-video", "--vid=no",   // audio only (embedded cover art is a video track)
  "--audio-display=no",
  "--no-terminal",            // M9: nothing on stdout/stderr (the "Playing: <url>" line carries the token)
  "--msg-level=all=error",
  "--input-ipc-client=fd://3",
  "--ytdl=no",                // M9: ytdl_hook runs even with --no-config and would get the token URL on argv
  "--load-scripts=no", "--osc=no", "--load-stats-overlay=no", "--load-console=no",
  "--load-auto-profiles=no", "--load-select=no", "--load-commands=no", "--load-positioning=no",
  "--resume-playback=no", "--save-position-on-quit=no",   // no watch_later files keyed by token URLs
  "--cache=yes", "--demuxer-max-bytes=64MiB", "--demuxer-readahead-secs=600", // whole song in RAM (M6: 1.5 s)
  "--prefetch-playlist=yes",  // M7: 2 ms vs 12 ms transitions; matters more over Tailscale
  "--gapless-audio=yes", "--audio-samplerate=48000",      // M10: no gap on rate changes; 48 k = PipeWire's default graph rate
  "--network-timeout=10",
  "--audio-client-name=gpuix-shell",   // the name pavucontrol / wpctl show
  "--volume-max=100",                  // no boost above 100 % (clipping)
  "--volume=70",                       // 05 §10 default; replaced by the persisted value at start
  "--replaygain=no",                   // §10; switchable at runtime
];
```

- `--audio-samplerate=48000` is the cost of `--gapless-audio=yes`. Without it, the output rate is
  whatever the first file had, so a 22 kHz first file would downsample everything after it.
  This repository configures no `default.clock.rate` or `allowed-rates` (grep), so PipeWire's
  graph runs at its 48 kHz default and resamples everything anyway. Forcing 48 kHz in mpv
  therefore loses nothing. `GPUIX_MUSIC_BITPERFECT=1` swaps both flags for `--gapless-audio=weak`
  and accepts the 494 ms gap on rate changes (M10).
- The engine sends `request_log_messages warn` over IPC. `log-message` events go through
  `redact()` (strip `u`/`t`/`s`/`p`/`apiKey` query values) before reaching the journal.
- `--ao` is left to mpv's default (pipewire on these hosts). Tests force `--ao=null`.

## 5. Loading tracks: the two-entry window (`daemon/player-mpv.ts`)

mpv's playlist is never the queue; 05 §10 says the same ("a two-slot window onto it"). It holds at
most `[current, successor]`.

```
state:  win = [{eid, uid}, {eid, uid}?]   // mpv playlist_entry_id ↔ queue entry uid
        gen                                // generation counter; bumped by every replace

reconcile():                               // after every queue mutation, coalesced to one microtask
  want0 = queue.current?.uid ; want1 = queue.peekNext({auto:true})?.uid   // repeat/shuffle/"Next in queue" applied
  if !want0:                 send stop; win = []; return
  if win[0]?.uid !== want0:  (set pause first when restoring paused)
                             eid = loadfile(url(want0), "replace", {start?}); win = [{eid, uid: want0}]; gen++
  if win[1]?.uid !== want1:  if win[1]: playlist-remove 1
                             if want1:  eid = loadfile(url(want1), "append"); win[1] = {eid, uid: want1}

on start-file {playlist_entry_id: eid}:
  if eid === win[1]?.eid:    // mpv auto-advanced (EOF, gapless/prefetched)
     queue.advanceTo(win[1].uid, {auto:true}); playlist-remove 0; win.shift(); reconcile()  // appends the new successor
  else if eid === win[0]?.eid: (our own replace, nothing to do)
  else: stale event from an older gen → ignore
```

- **Advance detection is keyed on `playlist_entry_id`, never on `playlist-pos`.** M5 shows
  `playlist-pos` going 1 → 0 when we remove entry 0. Reading positions as "previous" would be a
  bug. The entry id is stable and unique per `loadfile` (measured: ids 1…8 in M5).
- Manual `next`/`previous`/`jump`/`play` do a **replace**, which bumps `gen`. Gapless only matters
  for automatic advances.
- **Repeat one** loads the *same* queue entry again as the successor (a new mpv entry) and does
  **not** use `loop-file=inf` (05 §10 suggested it; see §15). The transition stays gapless (M5's
  `c.mp3` → `c.mp3` ran at 0–1 ms). Every loop is also a fresh `start-file`/`end-file` pair, which
  the scrobbler counts as a new play; `loop-file` emits neither. Next still skips, as 05 requires.
  `loop-file`/`loop-playlist` stay `no` throughout.
- Every URL is built at `loadfile` time by `music/subsonic/client.ts` (the secret boundary, 05
  §13) with a **fresh salt**. URLs are never stored: the window maps eid → uid, not eid → url.
- A queue mutation that changes the successor after mpv started prefetching just costs the
  prefetch. Correctness never depends on it.
- `stream` parameters: `id` plus `format=raw` by default. Seeking is by HTTP Range (M6, and 05 §1
  measured `Accept-Ranges: bytes` and 206 replies). `NAVIDROME_MAX_BITRATE=<kbps>` switches to
  `format=opus&maxBitRate=<n>` for thin links. In that case seeking beyond the cache becomes a
  replace with `timeOffset=<s>` (the server advertises `transcodeOffset`). That is **P2** (05 §13
  "Opus over Tailscale"), so the demo stays raw.

## 6. The queue model (`daemon/queue.ts`, pure, no I/O)

The engine uses 05 §9.2's `TrackRef`, `PlayContext` and `RepeatMode` unchanged, so the daemon
never converts between two track shapes.

```ts
import type { TrackRef, PlayContext, RepeatMode, QueueSnapshot } from "../types";
export type Origin = "context" | "user";          // "user" = 05's "Next in queue" (upNext)
export interface Entry { uid: string /* [a-z0-9]{10}, unique per insertion */; track: TrackRef; origin: Origin; unplayable?: true }
export interface QueueState {
  items: Entry[];                   // PLAY ORDER: history above index, upcoming below
  index: number;                    // -1 = empty
  shuffle: boolean; repeat: RepeatMode;
  unshuffled?: string[];            // context uids in their original order, captured when shuffle turned on
  context: PlayContext | null;
  rev: number;                      // 05's queueRev: +1 on every mutation
}
```

The **user segment** is the run of `origin:"user"` entries directly after `index`: 05's `upNext`,
which plays first. The context entries after it are 05's `contextNext`. The entries above `index`
are `history`, served newest first and capped at 20 in the snapshot. One list therefore yields
05's `QueueSnapshot` exactly, without keeping a second list in sync.

| Operation | Semantics (05 §10 where it speaks; this doc where it is silent) |
|---|---|
| `play(tracks, startIndex, context, {shuffle?})` | **Replaces the context and keeps "Next in queue"** (05 §10). The new context starts at `startIndex`, and the existing user segment stays queued right after it. With shuffle on, the chosen track plays first and the rest is Fisher–Yates shuffled after it. `unshuffled` = original order. The previous `QueueSnapshot` is kept for one Undo (05) |
| `next()` (manual) | User segment first, then context. At the end: `repeat all` wraps. A `radio`, `genre` or `library-shuffle` context refills (below). Otherwise stop with status "End of queue" (05 §10), keeping the queue, so the next play restarts at 0. Manual next under `repeat one` still advances (05) |
| auto-advance (EOF) | As `next()`, except `repeat one` replays the same entry (§5) |
| `previous()` | **More than 3 s in: restart** (seek 0, emit MPRIS `Seeked`). Otherwise `index-1`, the previous track in history (05 §10, R01). At 0: restart, or with `repeat all`, the last item |
| `enqueue(tracks, "next")` | Insert at `index+1` as `user`: plays right after the current track (05 `Alt+N`, Apple "Play Next") |
| `enqueue(tracks, "end")` | Insert at the **end of the user segment** as `user` (Spotify "Add to queue", 05 `Alt+Q`) |
| `appendToContext(tracks)` | Append at the very end as `context` (Apple "Play Last"). Not in 05's contract today; used by refills |
| `move(rev, from, to)` / `remove(rev, indexes)` / `jump(rev, index)` / `clear(rev, part)` | 05's rev-guarded ops. Indexes refer to `items` as of `rev`; a stale `rev` gives `stale-rev`. Removing the current item means next, then remove. `clear "up-next"` drops the user segment, `"all"` everything but the current item |
| `restore(snapshot)` | 05's Undo: rebuilds `items` from a `QueueSnapshot`, and keeps the current track playing when it is still the snapshot's current |
| `setShuffle(true)` | Shuffle only the **context entries after the user segment**. History, current and user segment keep their places (05: "the current track stays and Next in queue is never shuffled"). Record `unshuffled` |
| `setShuffle(false)` | Rebuild as `[context before current (original order), current, user segment, context after current (original order)]`, with `index` = the current's new place. That is 05's "restores the context's order after the current track". History of user-origin entries drops out of the list (it stays in `history.jsonl` and in the server's "recent") |
| `setRepeat(m)` / cycle | off → all → one → off |
| `peekNext({auto})` | The uid the window should load next. Pure, so it is unit-tested exhaustively |

- **Limits.** Up to 10,000 items. A `play()` beyond that keeps the 10,000 starting at
  `startIndex`. History above `index` is trimmed to 500.
- **Refilling contexts.** `library-shuffle` (05 `music.shuffle-all`) is fed by
  `getRandomSongs?size=200`. `radio` is fed by `daemon/radio.ts` (05 §5.10's layers). `genre` is fed
  by `getSongsByGenre` pages. 05 sets the refill trigger at **5 or fewer** remaining, and the
  engine takes that number. The refill is deduplicated against the last 200 ids, and the daemon
  never loads all 34k ids.
- **Duplicates** are legal: the same song can appear twice with different uids. Hence MPRIS track
  ids and server saves are per entry and per index (`indexBasedQueue`), never per song id.
- **Unplayable entries** (§12) stay in the list with `unplayable` set, so the queue view can grey
  them out. `peekNext` skips them.
- **Autoplay** (Spotify's radio at the end of an album) is a preference, `autoplay`, **default
  off**, because 05 §10 promises "End of queue". When on, the queue end appends a `radio` context
  seeded by the last track.

## 7. Persistence

All files live under `$XDG_STATE_HOME/gpuix-shell/music/` (default `~/.local/state/…`), are written
atomically (temp file + `rename`), and **never contain a URL or a credential** (test in §16).

| File | Content | Written |
|---|---|---|
| `queue.json` | `{version:1, savedAt, queue: QueueState}`. Entries carry the `TrackRef`, so a restore needs no API call. Up to about 2.5 MB at 10k items | on every queue mutation, debounced 1 s |
| `now.json` | `{savedAt, bootId, uid, index, positionMs, wasPlaying, cleanStop}` | every 5 s while playing, on every state change, and on SIGTERM (`cleanStop: true`) |
| `state.json` (05 §10's name) | `{volume (default 70), muted, normalize, autoplay, output}` | on change |
| `scrobbles-pending.jsonl` | `{id, time}` lines for submissions that failed offline | append, then rewrite after replay |
| `history.jsonl` (05) | one line per qualified play (§9), for 05's "Recently played" and ranking boosts | append |

**Server queue (`daemon/playqueue-sync.ts`, `indexBasedQueue`).**

- **Save.** `savePlayQueueByIndex` as a **POST form** (`formPost`, which 03 already uses for every
  call), with `c=gpuix-shell`. 10k ids × ~26 bytes would not fit a GET URL. It sends a window of at
  most 1,000 entries, `items[max(0, index−100) … index+900]`, with `currentIndex` rebased and
  `position=<ms>`. It is sent on pause, a track change (debounced 5 s) and daemon stop: 05's
  triggers. M14: the server queue is empty and unused, so this overwrites nothing today.
  `NAVIDROME_SAVE_QUEUE=0` turns it off. The by-index call (not 05's `savePlayQueue`) is used
  because duplicates are legal (§6).
- **Restore** happens on daemon start:
  1. Load `queue.json` and `now.json`. They exist because a server round-trip every 5 s for
     crash-resume would be chatty, and the daemon must also work offline.
  2. Fire `getPlayQueueByIndex` in parallel.
  3. If the server's `changed` is newer than the local `savedAt` by more than 5 s **and**
     `changedBy !== "gpuix-shell"`, the server queue wins and becomes 05's **Continue** shelf
     ("from \<changedBy\>").
  4. With no local files at all, adopt the server queue.
  5. The restored track is loaded **paused** at `positionMs` (M12: set `pause` to yes, then
     `loadfile … {start}`), so the first ▶ is instant.

## 8. Events → state (`daemon/player.ts`)

The engine keeps a richer internal state and projects it onto 05 §9.2's `PlayerState`
(`seq`, `status`, `track`, `positionMs`/`positionAt`, `volume`, `muted`, `shuffle`, `repeat`,
`context`, `upNext`, `contextRemaining`, `queueRev`, `output`, `server`, `artPath`, `error`).

```ts
type EngineStatus = "idle" | "loading" | "playing" | "paused" | "buffering" | "ended";
interface EngineState {
  engine: "starting" | "ready" | "restarting" | "failed";
  status: EngineStatus;
  current: (Entry & { index: number }) | null;
  positionMs: number; positionAt: number;  // see the clock rule below
  durationMs: number;                      // TrackRef.durationMs; mpv's duration only if the API had none (M11: mpv refines progressively)
  bufferedMs: number;                      // demuxer-cache-time, for a buffered bar if the UX wants one
  seekable: boolean; volume: number; muted: boolean; output: string;
  errorKind?: "credentials" | "auth" | "unreachable" | "not-found" | "format" | "engine";
}
```

| `EngineStatus` | → 05 `PlayerStatus` |
|---|---|
| `playing` | `playing` |
| `paused` | `paused` |
| `loading` | `buffering` |
| `buffering` | `buffering` |
| `idle` | `stopped` |
| `ended` | `stopped`, with the "End of queue" error-free message |
| any status with `errorKind` set and nothing playing | `error` |

- `errorKind` maps to 05's `MusicError.code` and `ServerStatus`:
  - `auth` → `unauthorized`;
  - `unreachable` → `offline`;
  - `credentials` → `unauthorized`, with the fix naming the file path;
  - `not-found` → `not-found`;
  - `format` and `engine` → `player`.
- **The clock rule for `positionAt`.** 05 says "daemon monotonic ms". It must be a clock **every
  process on the host shares**. **Measured** (`evidence/04-playback/mono.out`): under **bun 1.4.2**,
  `process.hrtime.bigint()` and `performance.now()` both count from *process start* (56 ms and 57 ms
  in a fresh process). Only node's `hrtime` reads CLOCK_MONOTONIC (656,532,318 ms, matching Python's
  `CLOCK_MONOTONIC` read on either side of it). Neither bun clock tried is shared across processes, so
  `positionAt` is **epoch ms, `Date.now()`**, in the daemon and in every client. Clients compute
  `positionMs + (Date.now() − positionAt)` while `playing`, clamped to `durationMs`. A wall-clock
  step (rare, since NTP slews) skews only until the next `state` event re-anchors.

The daemon observes these with `observe_property`: `time-pos`, `pause`, `paused-for-cache`,
`demuxer-cache-time`, `duration`, `seekable`, `volume`, `mute`, `audio-device`, `idle-active`. It
reacts to the events `start-file`, `file-loaded`, `playback-restart`, `end-file`, `seek` and
`log-message`.

| mpv | → engine / side effect |
|---|---|
| `start-file {playlist_entry_id}` | window logic (§5). `current` = the mapped entry, `status = loading`, position 0. Scrobbler `begin(entry)`. 05 `state` event |
| `file-loaded` | `seekable`, duration fallback. MPRIS `Metadata`. Art fetch through `art-cache.ts` |
| `playback-restart` | `status = pause ? paused : playing`, re-anchor `positionAt`. The first one per play reports `starting`/`playing` (§9) |
| `pause` | `playing` ↔ `paused`. MPRIS `PlaybackStatus`. Report |
| `paused-for-cache` true | `buffering`. MPRIS keeps "Playing" |
| `time-pos` (≈10 Hz, M5) | Fed in full to the scrobbler's listened-time counter. **Not streamed to clients** (05: position is extrapolated). Only discontinuities, such as a seek, a track change or a drift above 1 s from extrapolation, re-anchor and emit a `state` event |
| `seek` → `playback-restart` | Re-anchor. MPRIS `Seeked(µs)`. Report |
| `end-file reason=eof` | Nothing, because the successor's `start-file` drives the advance. With no successor: `ended` |
| `end-file reason=error` | §12 diagnosis |
| `volume`, `mute`, `audio-device` | Mirrored. MPRIS `Volume`. `state.json` |
| `log-message` | Redacted, then to the journal |

## 9. Play reporting

- **`NAVIDROME_SCROBBLE=1` is the default.** `0` sends **no** listening reports at all: no
  now-playing, no `reportPlayback`, no submissions.
- **Now playing (timeline).** On the first `playback-restart` of each play, send `reportPlayback`
  with `mediaId=<id>`, `mediaType=song`, `positionMs`, `state=starting`, then `playing`, and
  **`ignoreScrobble=true`**. Send it again with `paused`/`playing`/`stopped` on every pause, resume,
  seek and stop, plus a **60 s heartbeat while playing** (an in-process interval; 03 reports that
  Navidrome's web UI uses `playbackReportIntervalMs: 60000`). That follows 03's "prefer it over
  `scrobble submission=false`, and do not send both for the same play". If `reportPlayback` errors,
  fall back to `scrobble?id&submission=false`, which is 05 §10's start report.
- **Submission (the last.fm rule, 05 §10).** A play qualifies when the track is **longer than
  30 s** and the **listened time** reaches **min(duration / 2, 240 s)**. Listened time sums positive
  `time-pos` deltas below 1.5 s, so seeking forward does not count and seeking back is not counted
  twice. That fires **once per play**: `scrobble?id&submission=true&time=<epoch ms at play
  start>`. It also appends to `history.jsonl`. A repeat of the same entry (§5) is a new play.
- **One counting path only.** Reports always carry `ignoreScrobble=true`, and the explicit
  submission is the only thing that counts a play. That stays correct whatever Navidrome 0.63.2
  does with `ignoreScrobble=false`, which is **unverified**: the spec only defines the `true`
  case. This differs from an earlier `music:` assumption that flipped `ignoreScrobble=false` past
  the threshold; see §15.
- **Offline.** A failed submission is appended to `scrobbles-pending.jsonl` and replayed as one
  batched `scrobble` (repeated `id`/`time`, per 03) after the next successful API call. There is no
  retry timer, so dotfiles declare no new clock. Entries older than 14 days (last.fm's acceptance
  window) are dropped, and the file is capped at 500 lines.

## 10. Volume and output

- **The player volume is mpv's `volume` property** (0–100, software, `--volume-max=100`). It
  **defaults to 70** (05 §10), is persisted in `state.json`, and maps 1:1 to MPRIS `Volume`
  (0.0–1.0). mpv applies its own cubic curve to softvol, so the curve is perceptual already and we
  do not add one. (From mpv's source, not measured.) `mute` is separate, because MPRIS has no
  mute: Volume 0 is not mute.
- **System volume stays system.** `~/.local/bin/volume`, the OSD and the F-keys keep driving the
  PipeWire sink, as they do for every app. The launcher's `Ctrl+↑/↓` (05 §4) and the CLI `volume`
  verb set the **player** volume.
- **Not `ao-volume`** (the PipeWire stream volume), for two reasons. (1) WirePlumber's stream
  restore would persist it per application name, which gives two sources of truth. (2) It does not
  exist while mpv is idle: M1 showed `current-ao` "property unavailable" with no file loaded.
- **Output (05 `music.output`).** `audio-device` defaults to `auto`, which follows the PipeWire
  default sink, so the F9 `audio-route` picker moves music along with everything else. The output
  view lists `audio-device-list` (pipewire nodes), and `output <sink>` sets `audio-device` live.
  (Unverified: `audio-device-list` was not run tonight, to avoid touching the live PipeWire.)
- **Normalisation.** `normalize: "off" | "track" | "album"` maps to `replaygain`, default **off**.
  02 §4 found `replayGain` empty in 6 of 6 sampled songs, while M6's Justice track has −10 dB tags.
  Enabling it by default would make tagged songs quieter than untagged ones.

## 11. The MPRIS2 server (`daemon/mpris.ts`)

- **Bus name** `org.mpris.MediaPlayer2.gpuix_music` (05 §6, "MPRIS"), requested with `DO_NOT_QUEUE`.
  Failing to get it means another instance runs, so exit 1; the bus name is the singleton lock.
  The object is `/org/mpris/MediaPlayer2`. The unit is `Type=dbus` with `BusName=` that name, so
  systemd's readiness is "the name is on the bus".
- **`org.mpris.MediaPlayer2`.** `Identity "Music"` (05), `DesktopEntry "gpuix-shell-music"` (the
  HM module installs a `NoDisplay=true` desktop file for the icon), `CanRaise true`,
  `CanQuit false`, `HasTrackList false` in phase 1, and empty `SupportedUriSchemes`/`MimeTypes`.
  `Raise()` opens `music.now-playing` (`gpuix-shell launcher --view music/now-playing`).
- **`org.mpris.MediaPlayer2.Player`** (all of it exercised by `playerctl` in M13):

| MPRIS | ↔ engine |
|---|---|
| `PlaybackStatus` | playing/buffering/loading-while-playing → `Playing`; paused → `Paused`; idle/ended/error → `Stopped` |
| `LoopStatus` (rw) | `None`/`Playlist`/`Track` ↔ repeat off/all/one |
| `Shuffle` (rw) | `setShuffle` |
| `Volume` (rw) | `volume / 100` |
| `Position` | extrapolated position in µs. Not signalled, per spec; we emit `Seeked` instead on seeks, restarts and repeat-one loops |
| `Rate`, `MinimumRate`, `MaximumRate` | `1.0` |
| `CanGoNext` | a successor exists, or repeat/refill applies |
| `CanGoPrevious`, `CanPlay`, `CanPause`, `CanSeek`, `CanControl` | a current entry exists / the queue is non-empty / `seekable` / always true |
| `Next`, `Previous`, `Play`, `Pause`, `PlayPause`, `Stop` | the same commands as 05's `ctl.sock` verbs. `Previous` uses the 3 s rule |
| `Seek(offset µs)`, `SetPosition(trackId, µs)` | `SetPosition` is ignored unless `trackId` is the current one (spec) |
| `OpenUri(s)` | Accepts `navidrome:song:<id>`, `navidrome:album:<id>` and `navidrome:playlist:<id>` (05's `play <kind>:<id>` syntax), and plays them. The URI schemes stay unadvertised in phase 1 |

- **Metadata** (re-emitted on track change and once more when the art arrives):
  - `mpris:trackid`: `/org/gpuix/shell/music/track/<uid>`. Per *entry*, so duplicates are
    distinct, and never under `/org/mpris`. With no track it is
    `/org/mpris/MediaPlayer2/TrackList/NoTrack`.
  - `mpris:length`: µs, from `durationMs`.
  - `xesam:title`, `xesam:artist` (`as`), `xesam:album`, `xesam:trackNumber`, `xesam:discNumber`,
    `xesam:genre` (`as`), `xesam:contentCreated` (year) and `xesam:useCount` (playCount).
  - `xesam:url`: the `link` command's web URL, e.g.
    `http://music.internal/app/#/album/<albumId>/show`, which carries no auth.
  - `mpris:artUrl`: **a `file://` path from 05 §3.3's art cache**
    (`$XDG_CACHE_HOME/gpuix-shell/music/art/<sha1(coverArtId)>-256.jpg`), never
    `getCoverArt?…&t=…`. 05's `artPath` uses bucket 96 for the chip. MPRIS gets 256, because
    notification and OSD consumers draw it at 64–128 px.
- **TrackList, phase 2.** If it is ever wanted (few consumers read it; `playerctl` does not), it
  exposes a window from `index − 10` to `index + 50` with `CanEditTracks true`, mapped onto
  `jump`/`remove`/`enqueue next`.
- **Media keys.** The demo path is 05 §6's one-liner: `media` calls
  `playerctl -p gpuix_music,%any`. The later refinement is "most recently Playing wins", so a
  playing Chrome tab beats a paused music daemon. It belongs to whoever owns the rail's MPRIS
  aggregator.

## 12. Crash recovery and failure handling

| Failure | Detection | Action |
|---|---|---|
| **mpv crashes or exits unasked** | child `exit` / IPC close while not quitting | Respawn immediately, then back off 1, 2, 4, 8, 16 s. Reload the window with the current entry at its last position (M12 `start`), keeping play/pause. More than 5 respawns in 2 min gives `engine = failed` and `errorKind = engine`; the next user command retries once. Coredumps are **not** suppressed (tripwire-coredump should see them; AGENTS) |
| **mpv hangs** | any IPC request gets no reply within 3 s | SIGKILL the child, then the respawn path |
| **Stall** (network died before the song was cached) | `playing`, not `paused-for-cache`, and `time-pos` frozen for 8 s (an in-process timer, not a systemd clock) | Reload once at the position. A second stall goes through the error diagnosis below |
| **The daemon crashes** | systemd `Restart=on-failure`, `RestartSec=1` | mpv is gone already (M4: no orphan audio). On start, restore §7. **Crash-resume**: if `now.json` has `wasPlaying` and no `cleanStop`, is younger than 30 s, and `bootId` matches `/proc/sys/kernel/random/boot_id`, resume *playing* at `positionMs − 2000`. Otherwise restore paused (05: "restores the queue paused at daemon start"). A login, reboot or clean stop never blasts audio |
| **`end-file reason=error`** | M8: `unrecognized file format` (bad id *or* bad auth) / `loading failed` | Diagnose with one API call: `ping` fails at the network level → `unreachable`; Subsonic error 40/41 → `auth`; `getSong` error 70 → `not-found`; otherwise `format`. `unreachable`/`auth`: pause on that entry, set the error, keep the queue, and retry on the next play. `not-found`/`format`: mark the entry `unplayable`, skip to the next, echo. **Three consecutive failures stop playback** rather than racing through the queue |
| **Credentials missing or unreadable** | `client.ts` cannot read `NAVIDROME_CREDENTIALS_FILE`, or a key is missing | `errorKind = credentials`, with the message naming the *path* only. The queue, MPRIS and `ctl.sock` stay up (05 decides what the views show) |
| **Bus name taken** | `requestName` reply is not PRIMARY_OWNER | exit 1, so systemd shows it. No retry loop |
| **`ctl.sock` is stale** | connecting gives ECONNREFUSED (the M2 lesson) | Unlink **that exact path**, then bind. Never glob or clean the directory |

## 13. Credential flow (rules the engine code must keep)

1. Only `music/subsonic/client.ts` reads `NAVIDROME_CREDENTIALS_FILE` (05 §2). It reads it when a
   URL is minted (default `/run/agenix/navidrome-credentials`; keys `NAVIDROME_USER=` and
   `NAVIDROME_PASSWORD=`), so rotation needs no restart.
2. Token auth: `t = md5(password + s)` with a fresh 8-byte random `s` per URL. A (`t`, `s`) pair is
   replayable for as long as the password lives, which is why rules 3–5 exist.
3. Token URLs travel **only** from `client.ts` through `player-mpv.ts` to mpv, as IPC `loadfile`
   arguments. They never go on mpv's argv (visible in `/proc/*/cmdline`), never to yt-dlp
   (`--ytdl=no`, M9), never to the terminal (`--no-terminal`, M9), and never into watch_later
   (`--resume-playback=no`).
4. The engine never reads mpv's `path`, `filename`, `stream-open-filename` or `playlist`
   properties. It has no need to: the window maps eid → uid.
5. Nothing persistent or shared carries a URL: not the state files, not MPRIS metadata
   (`xesam:url` is the web UI link, `artUrl` is `file://`), not `ctl.sock` traffic, and not the
   journal (`redact()` on every mpv log line and every error message).
6. **Deploy blocker for the Zenbook** (also 03's assumption and 05 §14 Q1). `secrets.nix:112`
   encrypts `navidrome-credentials` for `editors ++ strixOnly`, and `modules/secrets.nix:193`
   installs it only when `hostName == "strix"`. The comment beside it gives the reason as "the
   zenbook left the fleet 2026-08-30", which is out of date: the Zenbook is the physical seat now
   (AGENTS, 2026-10-08). Until Tom adds the client's host key as a recipient and widens the `mkIf`,
   the daemon on the Zenbook runs with `errorKind = credentials`. Re-keying needs an editor key, so
   it is Tom's morning step. Tonight's tests run on the strix, where the file exists.

## 14. TypeScript API (engine side, inside the daemon)

```ts
// pkgs/gpuix-shell/src/music/daemon/player.ts
import type { TrackRef, PlayContext, RepeatMode, PlayerState, QueueSnapshot } from "../types";   // 05 §9.2

export interface Observable<T> {                 // ~40 lines in daemon/observable.ts, no RxJS
  readonly value: T;
  subscribe(listener: (value: T) => void): () => void;
}
export type EngineEvent =                        // feeds 05's echo strings, the OSD and history.jsonl
  | { type: "trackChanged"; entry: Entry; auto: boolean } | { type: "ended" }
  | { type: "queueChanged"; rev: number } | { type: "played"; id: string /* qualified per §9 */ }
  | { type: "volume"; volume: number; muted: boolean } | { type: "error"; kind: NonNullable<EngineState["errorKind"]>; message: string };

export interface PlayerOptions {
  server: MusicServer;              // the port below; production = music/subsonic/client.ts
  mpvPath?: string;                 // default $GPUIX_SHELL_MPV ?? "mpv"
  mpvExtraArgs?: string[];          // tests: ["--ao=null"]
  stateDir?: string; runtimeDir?: string;   // default XDG dirs; tests pass temp dirs
  scrobble?: boolean;               // default NAVIDROME_SCROBBLE !== "0"
  saveServerQueue?: boolean;        // default NAVIDROME_SAVE_QUEUE !== "0"
  mpris?: boolean;                  // default true; tests run under dbus-run-session or pass false
  now?: () => number;               // injectable epoch-ms clock (scrobble time and positionAt, §8)
}

export class Player {
  static start(opts: PlayerOptions): Promise<Player>;   // spawn mpv, restore §7, register MPRIS
  dispose(opts?: { cleanStop?: boolean }): Promise<void>;   // persist, report stopped, unregister, quit mpv

  readonly state$: Observable<PlayerState>;    // already projected to 05 §9.2 (seq-stamped)
  readonly engine$: Observable<EngineState>;   // internal detail for tests and the OSD
  readonly events$: Observable<EngineEvent | null>;

  // transport
  play(tracks: TrackRef[], startIndex?: number, context?: PlayContext | null, opts?: { shuffle?: boolean }): Promise<void>;
  toggle(): Promise<void>; resume(): Promise<void>; pause(): Promise<void>; stop(): Promise<void>;
  next(): Promise<void>; previous(): Promise<void>;
  seek(seconds: number, relative?: boolean): Promise<void>;
  setVolume(value: number, relative?: boolean): Promise<void>;   // player volume 0..100 (§10)
  setMuted(on?: boolean): Promise<void>;
  setShuffle(on?: boolean): Promise<boolean>; setRepeat(mode?: RepeatMode): Promise<RepeatMode>;   // undefined = toggle / cycle
  // queue
  enqueue(tracks: TrackRef[], where: "next" | "end"): Promise<void>;
  appendToContext(tracks: TrackRef[]): Promise<void>;
  move(rev: number, from: number, to: number): Promise<void>;
  remove(rev: number, indexes: number[]): Promise<void>;
  jump(rev: number, index: number): Promise<void>;
  clear(rev: number, part: "up-next" | "all"): Promise<void>;
  snapshot(): QueueSnapshot;
  restore(snapshot: QueueSnapshot): Promise<void>;
  // output and preferences
  outputs(): Promise<{ name: string; description: string }[]>; setOutput(name?: string): Promise<void>;
  setPreference(p: Partial<{ normalize: "off" | "track" | "album"; autoplay: boolean }>): Promise<void>;
}

// The port the engine consumes; music/subsonic/client.ts implements it. Tests use a fake whose
// streamUrl returns av://lavfi:sine=… (M11), so the engine is testable without a server.
export interface MusicServer {
  streamUrl(id: string): string;                             // fresh-salt token URL; never logged
  getSong(id: string): Promise<TrackRef>;
  refill(context: PlayContext, last: TrackRef | null): Promise<TrackRef[]>;   // radio / genre / library-shuffle
  reportPlayback(r: { id: string; positionMs: number; state: "starting" | "playing" | "paused" | "stopped" }): Promise<void>;
  scrobble(plays: { id: string; time: number }[], submission: boolean): Promise<void>;
  savePlayQueueByIndex(ids: string[], currentIndex: number, positionMs: number): Promise<void>;
  getPlayQueueByIndex(): Promise<{ tracks: TrackRef[]; currentIndex: number; positionMs: number; changed: string; changedBy: string } | null>;
  diagnose(id: string): Promise<"unreachable" | "auth" | "not-found" | "ok">;
}
```

**05 §9.2 request → engine call** (implemented in `daemon/server.ts`):

| `MusicRequest` | `Player` |
|---|---|
| `state` / `watch` | `state$.value` / `state$.subscribe` (plus `queue` events on `rev` change) |
| `play {items, context, startIndex, shuffle}` | resolve `PlayItem`s to `TrackRef[]` (album/playlist/artist/query via the client), then `play(…)` |
| `enqueue {items, where}` | `enqueue(…, where)` |
| `toggle`, `play-resume`, `pause`, `next`, `previous`, `stop` | `toggle`, `resume`, `pause`, `next`, `previous`, `stop` |
| `seek {seconds, relative}`, `volume {value, relative}`, `mute`, `shuffle`, `repeat` | `seek`, `setVolume`, `setMuted`, `setShuffle`, `setRepeat` |
| `radio {seed}` | `play(await radio.seed(seed), 0, {kind:"radio", …})` |
| `queue.get` / `.move` / `.remove` / `.clear` / `.jump` / `.restore` | `snapshot` / `move` / `remove` / `clear` / `jump` / `restore` |
| `output {sink}` | `outputs` / `setOutput` |
| `search`, `browse`, `like`, `lyrics`, `art`, `link`, `playlist.add` | not the engine: the client, lexicon and art-cache modules of 05 §13 |

## 15. Where this doc departs from earlier notes, and why

| Topic | Earlier note | This doc | Why |
|---|---|---|---|
| mpv IPC transport | 05 §2: `music/mpv.sock`. ASSUMPTIONS: "a JSON IPC socket" | fd socketpair; `mpv.sock` only with `GPUIX_SHELL_MPV_DEBUG_SOCKET=1` | M2: stale socket files. M4: no orphan audio. No other process can command mpv |
| Repeat one | 05 §10: `loop-file=inf` | Re-append the same entry as the successor | Uniform `start-file` events, so each loop scrobbles as a play, and gapless at 0–1 ms (M5). `loop-file` emits no per-loop event |
| Start report | 05 §10: `scrobble submission=false` | `reportPlayback ignoreScrobble=true`, falling back to `submission=false` | 03's endpoint table: prefer `reportPlayback`, never both |
| Counting a play | ASSUMPTIONS: `reportPlayback ignoreScrobble=false` past 50 %/4 min, 60 s heartbeat | Heartbeat kept. Counting only through `scrobble submission=true`, with reports always `ignoreScrobble=true` | Deterministic whatever the server does with `false` (unverified); the spec names `scrobble` as the offline path |
| Resume store | ASSUMPTIONS / 05: the server play queue is *the* resume store | Local `queue.json`/`now.json` (no URLs) **plus** the server queue by index | Crash-resume needs a 5 s position without server chatter, and the daemon must work offline. By-index because duplicates are legal |
| `positionAt` | 05: "daemon monotonic ms" | epoch ms (`Date.now()`) | Measured: under bun both `hrtime` and `performance.now()` count from process start, so no monotonic clock is shared between processes |
| MPRIS name | orchestrator prompt: `gpuixshell`; 05: `gpuix_music` | `gpuix_music`, Identity "Music" | One name for the builders. 05 already wired it into the `media` one-liner |

## 16. Files, tests and Nix

These are 05 §13's file names, plus three helpers.

```
pkgs/gpuix-shell/src/music/daemon/
  player.ts         Player: glue, projections, crash-resume                       player.test.ts
  player-mpv.ts     MpvEngine: spawn, fd IPC, request ids + 3 s timeouts, observe,
                    two-entry window (§5), log redaction, respawn                  (via player.test.ts)
  queue.ts          pure queue model (§6)                                          queue.test.ts (05's list + §6 rows)
  scrobble.ts       pure policy + reporter (§9)                                    scrobble.test.ts
  playqueue-sync.ts server save/restore (§7)                                       (fake MusicServer)
  state-files.ts    queue.json / now.json / state.json / pending (atomic)          state-files.test.ts
  mpris.ts          MPRIS server (§11)                                             mpris.test.ts
  server.ts         ctl.sock (05 §9.2) → Player                                    (05's cli.test.ts)
  observable.ts     Observable
  radio.ts, osd.ts  05's
pkgs/gpuix-shell/src/music/subsonic/redact.ts   redact(), shared with client.ts      (05's secrets.test.ts)
```

- **`player.test.ts`** runs real mpv with `--ao=null` and a `FakeMusicServer` whose `streamUrl`
  returns `av://lavfi:sine=…:duration=1` (M11). It needs no network, no fixtures and no PipeWire,
  and covers:
  - gapless auto-advance through the window;
  - repeat-one producing two `trackChanged` events and two `played`;
  - shuffle and successor reconcile;
  - `kill -9` of the mpv child, then respawn at the position;
  - daemon-restart crash-resume against a temp `now.json`;
  - the 3 s `previous` rule.
- **`mpris.test.ts`** runs under `dbus-run-session` (M13 recipe) and is skipped when that binary is
  absent.
- **Secrets.** 05's `secrets.test.ts` also asserts that a canary password and its tokens are
  absent from the state files, from `now.json`, and from the mpv argv (the spawn spy).
- Tests set `XDG_RUNTIME_DIR`, `XDG_STATE_HOME` and `XDG_CACHE_HOME` to temp dirs, and **never use
  the live runtime directory**. They neither source shell fragments nor start compositors, so
  plain `bun test` is within the runtime-isolation rules.
- **Live probe (manual, read-only).**
  [`evidence/04-playback/nav-stream.mjs`](evidence/04-playback/nav-stream.mjs) checks against
  `music.internal` with `ao=null`. The smoke in 05 §12 uses a fake Subsonic server instead.
- **Nix.**
  - Add `dbus-next@0.10.2` (exact pin; the version M13 ran) to `package.json`.
  - `default.nix` wraps with `--set GPUIX_SHELL_MPV ${pkgs.mpv}/bin/mpv`.
  - `nativeCheckInputs = [ mpv dbus ]` for the bun tests in the build.
- **HM.** `systemd.user.services.gpuix-shell-music`:
  - `ExecStart = gpuix-shell music serve`, `Type=dbus`, `BusName=org.mpris.MediaPlayer2.gpuix_music`,
    `Restart=on-failure`, `RestartSec=1`;
  - `PartOf`/`WantedBy = sway-physical-session.target`;
  - `Environment`: `NAVIDROME_URL=http://music.internal`,
    `NAVIDROME_CREDENTIALS_FILE=/run/agenix/navidrome-credentials`, `NAVIDROME_SCROBBLE=1`.

  No timers.

## 17. Evidence index (`evidence/04-playback/`)

| File | What |
|---|---|
| `socat-probe.sh` / `.out` | M1, M2 |
| `fd-ipc.mjs` / `.out` | M3 (bun and node) |
| `orphan.mjs` / `.out` | M4 |
| `events.mjs` / `.out` | M5 |
| `subsonic.mjs` | token-auth helper: reads the credential file at runtime, `redact()` |
| `nav-stream.mjs`, `nav-yes.json`, `nav-no.json` | M6, M7, and the stdout leak in M9 |
| `nav-errors.mjs` / `.json` | M8, and the ytdl leak in M9 (output redacted) |
| `final-argv.mjs` / `.json` | M9 fixed, M10 |
| `rate48.mjs` / `.out`, `lavfi.mjs` / `.out`, `loadfile-start.mjs` / `.out` | M10, M11, M12 |
| `mpris-probe.mjs`, `mpris-run.sh` / `.out` | M13. Needs `node_modules` with `dbus-next`; it ran with a symlink to `~/.wt/hyprland-solid-shell/pkgs/desktop-shell/node_modules` |
| `queue-read.mjs` / `.json` | M14 (read-only) |
| `mono.mjs` / `.out` | the §8 clock rule: bun's `hrtime` is process-relative, node's is CLOCK_MONOTONIC |

Every output was grepped for a 32-hex `t=` value, and for the literal password string, before it
was saved; neither occurs.

## 18. What was done, and what was not

**Done:** M1–M14 as listed above, plus the clock check in §8. The scratch dir was
`/tmp/claude-1000/gpuix-music-04-engine`. One early slip: the first M1 run used
`/tmp/claude-1000/gpuix-music-probe`, which turned out to be the sibling researcher's probe
directory. Only my own `mpv.sock` and `mpv.log` were created there, and they were removed again by
exact path; the sibling's files were not touched.

**Not done / unverified:**
- No PipeWire output was opened. `ao=pipewire`, `--audio-client-name` as seen in pavucontrol, and
  `audio-device-list` are unverified.
- `scrobble`, `reportPlayback` and `savePlayQueueByIndex` were not called (they write Tom's
  history and server state). Their shapes come from the OpenSubsonic spec pages read tonight, and
  from 03.
- The behaviour behind mpv's softvol curve and mpv-mpris's `xesam:url` comes from reading
  source, not from measurement.
- The M13 probe registered the earlier name `gpuixshell`. The name change is mechanical.
- TrackList and transcoded-stream seeking are phase 2.
- No engine code was written; this is the design the slice-A builders implement.
- The Zenbook cannot authenticate until Tom rules on the secret's recipients (§13.6).
