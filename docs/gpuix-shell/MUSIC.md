# MUSIC — Navidrome in the GPUIX shell: the consolidated spec and build plan

**Status:** SPEC v1, written 2026-10-20 at about 23:55 CEST by the music design pass (Claude Opus 5.5,
cc2 seat). Build: **not started**. The completer (job 014) replaces this line with the real state.

Tom's order (BRIEF §5): *"i would like to have a navidrome music selection in the gpuix shell ; so a
demo implementation of that would be very nice to have tomorrow morning ... impress me here with
raycast+spotify level searching and playing control from within the launcher"*.

This file is the single spec the seven music builders code against. It consolidates the five
research notes in [`music/`](music/):

| Short | Note | Owns |
|---|---|---|
| R01 | [01-raycast-spotify-model.md](music/01-raycast-spotify-model.md) | what "Spotify-level" means, the Raycast keymap translated (§10), ranked parity list (§11) |
| R02 | [02-navidrome-ext-and-cliamp.md](music/02-navidrome-ext-and-cliamp.md) | the baseline we beat (Raycast Navidrome extension), cliamp's player model, ranked additions (§5) |
| R03 | [03-subsonic-api-live.md](music/03-subsonic-api-live.md) | **measured** API reference: endpoints, shapes, latencies, quirks, auth |
| R04 | [04-playback-engine.md](music/04-playback-engine.md) | **measured** playback engine: mpv argv, fd IPC, two-entry window, queue, reporting, MPRIS |
| R05 | [05-ux-spec.md](music/05-ux-spec.md) | the UX: views, wireframes, geometry, tokens, keys, commands, provider contract |

**Precedence.** Measured facts in R03/R04 bind everyone. Then this file. Then your packet prompt.
Then R05 > R04 > R03 > R02 > R01. Where a packet prompt says something different from this file,
§11 lists the override and the reason; follow this file. Builders do not ask; they decide, log a
`music:` line in [ASSUMPTIONS.md](ASSUMPTIONS.md), and report the difference in
`music/BUILD-LOG.md`.

---

## 0. The decision in one paragraph

Everything sits behind one TypeScript interface, **`MusicBackend`** (`src/music/types.ts`, already
in the tree and typechecked). A **music service** implements it. The service owns the Subsonic client
(the only code that reads the credential file), the local library index (instant, typo-tolerant
search over 11,118 artists, 16,208 albums and 1,235 playlists), the art cache (cover art as local
file paths, never URLs), and the player (one mpv child over an inherited socketpair, a queue model
we own, a gapless two-entry window, play reporting and MPRIS). Clients talk to a `MusicBackend`:
the **GPUIX views** (`MusicRoot`), the **CLI** (`gpuix-shell music <verb>`), the **launcher
provider**, the **rail chip** and MPRIS. A backend is either in-process (`createMusicService`) or
remote over `$XDG_RUNTIME_DIR/gpuix-shell/music/ctl.sock` (`connectBackend`). **For the morning demo**
the service runs inside the standalone GPUIX demo window (`src/music/demo/main.tsx`) and also serves
`ctl.sock`, so the CLI, MPRIS keys and a second window all control the same player. The shell's
headless daemon (`gpuix-shell music serve`) is the same service without a window (P1).

---

## 1. Scope

### 1.1 P0: the morning demo (must work; each line is checked in §8)

| # | Capability | Origin |
|---|---|---|
| A1 | A standalone GPUIX window, **"Music"** (`appId gpuix-shell-music`, 900 × 640), styled as the launcher panel: header with input and scope chips, sectioned body, mini-player strip, footer with echo, primary action and `Actions Ctrl K`. `--layer` opens it instead as the launcher's overlay layer surface (700 × 580, top margin 108, keyboard exclusive). | R05 §3.1 |
| A2 | **Home** on an empty query: Continue (current track), Jump back in (`recent`), New in library (`newest`), Most played (`frequent`), Random albums, Browse links, Recent searches. Empty shelves are hidden. | R05 §5.2 |
| A3 | **Search as you type**: the local index paints first (no network round trip), the server's `search3` merges in after 60 ms, the cursor never jumps under a moving row. Sections: Top result · Songs 4 · Artists 3 · Albums 6 · Playlists 4. Cross-field and typo matches the server cannot do (`davis kind` → "Kind of Blue" by Miles Davis when the library has it). | R05 §5.3, §8 |
| A4 | **Enter plays, in context**: a song from search plays and continues with its album; a song inside an album or playlist plays that list from that song; album, playlist and artist rows play the whole thing; `Shift+Enter` plays and closes. | R05 §10, R01 §3.3 |
| A5 | **Drill-down** on a stack: Album (header with cover, facts, Play/Shuffle/Add to queue/Navidrome; tracklist by disc), Artist (popular, albums grid, similar artists, bio), Playlist; `Ctrl+Enter` opens, `Esc`/`Backspace` on empty input pops. | R05 §5.4–5.5, §5.9 |
| A6 | **Now Playing** view: 240 px cover, title/artist/album, state words, live progress bar and `1:12 / 3:40` (extrapolated, no polling), transport buttons (shuffle, previous, play/pause, next, repeat, like), Up next list. | R05 §5.6 |
| A7 | **Mini-player strip** on every other view; clicking it opens Now Playing. The playing row is marked (2 px accent bar, accent title, word "Playing") in every list. | R05 §3.1–3.2 |
| A8 | **Player keys in every view**: `Ctrl+Space` play/pause (`Space` when the input is empty), `Ctrl+→/←` next/previous (previous restarts after 3 s), `Alt+→/←` seek ±15 s, `Ctrl+↑/↓` music volume ±10, `Alt+S` shuffle, `Alt+R` repeat cycle, `Alt+N` play next, `Alt+Q` add to queue, `Ctrl+L` like/unlike (star), `Alt+L` like the current track. | R05 §4 |
| A9 | **Actions panel** `Ctrl+K` (alias `Ctrl+B`): every action of the selected row with its keycap, grouped by consequence, with its own filter field. | R05 §5.11 |
| A10 | **Echo and Undo**: every action echoes in the footer for 6 s ("Added Holocene to the queue · Undo Ctrl+Z"); queue edits, plays and likes offer `Ctrl+Z`. | R05 §0.6 |
| A11 | **Queue view**: Now playing · Next in queue · Next from <context> · History; `Enter` jumps, `Ctrl+X` removes, `Ctrl+Shift+↑/↓` moves, `Ctrl+Shift+X` clears Next in queue; rev-guarded. | R05 §5.7 |
| A12 | **CLI** `gpuix-shell music <verb>` against the running window: `status`, `toggle`, `next`, `prev`, `seek`, `volume`, `shuffle`, `repeat`, `like`, `play "<query>"`, `search`, `queue`. Until wave 2's top-level `gpuix-shell` exists: `bun src/music/cli.ts <verb>`. | R05 §6 |
| A13 | **MPRIS** `org.mpris.MediaPlayer2.gpuix_music` when a session bus exists, so `playerctl`, F3/F4/F5 and the XF86 media keys already drive it on the Zenbook (`media` → `playerctl`). Absent bus = skipped quietly. | R04 §11 |
| A14 | **Honest states**: indexing, offline ("Can't reach Navidrome at music.internal"), unauthorized (names the credential file path only), no results, nothing playing, empty liked. | R05 §3.5 |
| A15 | **Fake mode** `NAVIDROME_FAKE=1`: the whole demo runs on a synthetic catalogue with lavfi tones, no network and no credential. The GUI smoke uses it. | — |

### 1.2 P1: Spotify-level completeness (build after P0 is green; the completer ranks what is left)

Like on albums/artists; Liked view (`getStarred2`); Library view (shelves, genres, years, artists A–Z)
and Playlists list-detail; scope views with infinite paging (`search3` offsets); Radio
(`Ctrl+Shift+R`, layered sources, endless refill); Shuffle all songs; Add to playlist picker (`Alt+P`;
the account has `playlistRole:false`, so expect "Failed" until Tom rules); output device picker
(`Ctrl+Shift+K`); recent searches with remove/clear; root launcher contributions (music rows, no-view
commands, fallback "Search music for …") once wave 2's launcher host exists; rail now-playing chip
mounted by the rail owner; OSD for transport outside the launcher; the headless daemon
`gpuix-shell music serve` and its HM unit; server play-queue save/restore (`savePlayQueueByIndex`,
the Continue shelf "from <client>"); detail pane `Ctrl+I`; Copy link / Copy title / Open in Navidrome.

### 1.3 P2: delight (designed, not tonight)

Synced lyrics highlighting (Navidrome has lyrics for ~1 % of songs, none synced); LRCLIB fallback
(off by default: sends artist/title off the box); ratings; Generate playlist with the local model
(`gpuix-shell ask`); Opus over Tailscale with `timeOffset` seeking; a song-level local index for typo
search over titles (03 §4.5: 45.8 MB dump → 6.1 MB trimmed); track-change toast; MPRIS TrackList;
"who is listening" (`getNowPlaying`).

### 1.4 Out

Podcasts/episodes, Spotify Connect (no Subsonic equivalent; Navidrome jukebox would play on the
headless strix), Copy embed code, DJ, private session, downloads, EQ/speed. Writes from tests or
probes (§4.7).

---

## 2. Architecture

```
                         ┌─────────────── one bun process: the demo window (P0) ──────────────────┐
 Tom's keys ───────────► │ GPUIX window "Music"  (src/music/demo/main.tsx)                         │
 (Wayland seat)          │   <MusicRoot backend={service}/>   src/music/ui/**   (no secret)        │
                         │            │ MusicBackend (in-process)                                  │
                         │   MusicService  src/music/service/**  ── implements MusicBackend        │
                         │     ├─ SubsonicApi    src/music/subsonic/**  ← ONLY reader of the cred  │
                         │     ├─ LibraryCache + LibraryIndex + searchMusic + pages + ArtCache     │
                         │     │                 src/music/library/**                              │
                         │     ├─ Player         src/music/player/**                               │
                         │     │    ├─ Queue (pure)  ├─ PlayReporter  ├─ MPRIS (dbus-next)         │
                         │     │    └─ mpv child ◄── fd://3 socketpair, JSON IPC (token URLs here)  │
                         │     └─ serveBackend(ctl.sock)  src/music/ipc/server.ts                  │
                         └─────────────▲──────────────────────────────▲──────────────────────────────┘
   gpuix-shell music <verb> ──────────┘ ctl.sock (JSON lines, 0600)    │ session bus
   (src/music/cli.ts → connectBackend)                                  │
   launcher provider / rail chip (P1) ─► connectBackend                 └── playerctl, F3/F4/F5, XF86Audio*
```

Hosts of the service:

| Host | When | Backend seen by the UI |
|---|---|---|
| `bun src/music/demo/main.tsx` | **P0 demo** | in-process `MusicService`, plus `ctl.sock` for the CLI |
| `gpuix-shell music serve` (`cli.ts serve`) | P1 daemon, systemd user unit `gpuix-shell-music.service` | — (headless) |
| the wave-2 launcher (`Mod+D`, `$mod+m`) | P1 | `connectBackend(ctl.sock)`; music views render `<MusicRoot embedded>` as the provider's custom view |
| `bun src/music/demo/main.tsx --daemon` | P1 | `connectBackend(ctl.sock)` to a running daemon |

Why in-process for the demo: one process to start, nothing to orchestrate at 7 am, and the same
`MusicBackend` boundary means switching to the daemon is a constructor swap. The cost: in the demo
the credential lives in the same process as the GPUIX renderer. The views still never receive a URL
(art is a local path; links are web-UI links), so `getAutomationTree()` never contains a token. The
shell daemon (P1) restores R05 §2's full separation. Logged.

### 2.1 Two flows, end to end

**Keystroke `b` → `bo` → `bon` in Search.** `MusicRoot` aborts the previous search and calls
`backend.search("bon", {scope:"all", signal})`. The service delegates to `searchMusic`
(library/search.ts), which yields a **partial** from `LibraryIndex.query` (< 8 ms, no network), then
sleeps 60 ms (abortable), calls `api.search("bon", {artist:6, album:12, song:24})` (13–29 ms at the
server), merges and re-ranks, and yields the **final**. The view replaces rows and applies the
cursor-pin rule. Art for visible rows is requested with `backend.art(coverArt, 96, signal)`; the art
cache answers with a local path or `null` (placeholder monogram until then).

**Enter on a song row.** The view calls `backend.run({cmd:"play", items:[{kind:"track", track}],
context:{kind:"search", query, name}}, {origin:"ui"})`. The service resolves "song from search" to
`[song, ...rest of its album after it]` (one `getAlbum`), calls `player.play(tracks, 0, context)`,
which replaces the queue's context (keeping Next in queue), reconciles the mpv window
(`loadfile <fresh-salt URL> replace` + successor `append`, sent over fd IPC) and emits a state. The
service returns `{ok:true, echo:"Playing Holocene", undo:{cmd:"queue.restore", snapshot}}`; the
footer shows the echo; `watch` listeners (the strip, the chip, ctl.sock watchers, MPRIS) get the new
`PlayerState`. No surface polls; positions are extrapolated from `positionMs`/`positionAt`.

---

## 3. Facts that bind (measured tonight; details in R03/R04/R05 §1)

| Fact | Consequence |
|---|---|
| Navidrome 0.63.2, Subsonic 1.16.1, OpenSubsonic; extensions `formPost`, `songLyrics` 1–2, `indexBasedQueue`, `playbackReport`, `transcoding`, `transcodeOffset`; **no `apiKeyAuthentication`** | salted-token auth; every stream URL is a replayable secret |
| 38,524 songs, 16,208 albums, 11,118 album artists (14,610 incl. track artists), 1,235 playlists, 3,966 genres (136 with ≥ 20 songs) | virtualise every long list; songs are NOT in the local index |
| 53 % of songs in `[Unknown Album]`, 5,237 in `[Unknown Artist]`, many titles embed "Artist - Title" | `format.ts` hides placeholders and de-duplicates titles |
| `search3`: word-prefix AND, diacritics folded, ≥ 2 chars, **no relevance ranking**, no infix, no typo tolerance, no totals; empty query dumps everything | client-side ranking; never send an empty query; local index for cross-field and typo matches |
| `search3` 13–29 ms; `getArtists` 0.93 s / 4.6 MB; `getAlbumList2` ≤ 500 per page (33 pages ≈ 6.8 s); `getSimilarSongs2` 2.3–2.9 s; `getTopSongs` 0.3 s and sparse; cover art 90–170 ms cold (1.1 s playlist mosaic) | debounce 60 ms; index built in the background and cached; radio shows a loading state |
| Unset optional keys are **absent**, not null; empty lists drop the key (`"randomSongs":{}`); `getAlbumInfo2` answers under `albumInfo`; errors are HTTP 200 + `status:"failed"`; a bad stream id answers a JSON/XML error body with HTTP 200 | `map.ts` defaults; the client checks `Content-Type` for media |
| Raw stream (`format=raw`): 206 + `Accept-Ranges`, first audio ~87–103 ms, seek 4–5 ms; transcoded: not seekable | raw by default; opus only with `NAVIDROME_MAX_BITRATE` |
| Streaming has no side effects; now-playing/plays move only via `reportPlayback`/`scrobble` | tests may stream; tests may not report |
| mpv 0.41: prints `Playing: <url>` on stdout; its ytdl_hook passes the URL to yt-dlp on argv even under `--no-config`; socket files go stale; fd-IPC mpv dies within 0.8 s of its parent | the R04 §4 argv; fd IPC; no socket file by default |
| `--gapless-audio=yes --audio-samplerate=48000` → 1–2 ms transitions; `weak` → 494 ms gap on a rate change | as R04 §4 |
| bun 1.4.2: `process.hrtime`/`performance.now()` are process-relative | `positionAt` is epoch ms |
| `navidrome-credentials.age` is `editors ++ strixOnly`; the Zenbook has no credential file | the demo runbook (§9) hands the file to the client's tmpfs for the session, or Tom rekeys |
| `@gpuix/native` 0.11.0: no audio API; `GpuixRenderer.getAutomationTree()`, `simulateKeystrokes`, `@gpuix/react` `createRenderer` + `enableAutomation`, `TestGpuixRenderer` is **not** in the published Linux binary (`hasTestGpuixRenderer() === false`, checked tonight) | UI tests are pure-logic; rendering is verified by the compositor smoke |
| `EventPayload` carries `key`, `keyChar`, `modifiers {shift, ctrl, alt, cmd}`; `KeyEvent.preventDefault()`; window-level `onKeyDown` runs after element handlers | keymap resolves `"ctrl-shift-enter"`-style keystrokes built from those fields |

---

## 4. Secret and safety rules (non-negotiable; `secrets.test.ts` in each packet checks its part)

1. Only `src/music/subsonic/auth.ts` reads `NAVIDROME_CREDENTIALS_FILE` (default
   `/run/agenix/navidrome-credentials`; lines `NAVIDROME_USER=` / `NAVIDROME_PASSWORD=`). It reads it
   when a request or URL is minted, so rotation needs no restart. Never copy, cache, log, print, put
   in argv, or put in a child's environment.
2. Token auth `t = md5(password + s)`, `s` = 8 random bytes hex (`node:crypto`), fresh per request.
   JSON calls use **POST form bodies** (`formPost`), so tokens never sit in a URL.
3. `streamUrl()` is the only API that returns a token URL. It travels client → `player/mpv.ts` →
   mpv's IPC `loadfile`, nowhere else: not argv, not logs, not state files, not MPRIS
   (`xesam:url` = web-UI link, `mpris:artUrl` = `file://` path), not `ctl.sock`, not the GPUIX tree.
   Cover art is fetched as bytes by the client and handed out as **local file paths**.
4. mpv runs with R04 §4's argv (`--no-terminal --msg-level=all=error --ytdl=no --no-config
   --resume-playback=no …`). The engine never reads mpv's `path`/`filename`/`stream-open-filename`/
   `playlist` properties.
5. Every log line and error message passes `redact()` (`subsonic/redact.ts`): query values of
   `u`, `t`, `s`, `p`, `apiKey`, `jwt` and `/share/img/<jwt>` segments are replaced by `<redacted>`.
   Errors name the credential **path** at most.
6. Fixtures are scrubbed: the username becomes `<user>`, share-image JWTs become `<jwt>`. The
   recorder asserts that no 32-hex `t=` value and no password substring is in its output.
7. **Tests and probes never write to Navidrome**: no `star`, `scrobble`, `reportPlayback`,
   `savePlayQueue*`, playlist, bookmark or rating call. Write paths are tested against a fake `fetch`.
   Live runs set `NAVIDROME_SCROBBLE=0 NAVIDROME_SAVE_QUEUE=0` and never press like.
8. Compositor tests run only under `home/dot_local/bin/runtime-test --render-node
   /dev/dri/renderD128` with the isolated Sway of BRIEF §5. Unit tests set `XDG_RUNTIME_DIR`,
   `XDG_STATE_HOME`, `XDG_CACHE_HOME` to temp dirs and never touch the live runtime directory. Nobody
   restarts Sway, herdr or the user manager. Coredumps are not suppressed.
9. `ctl.sock`: its directory is created mode 700, the socket chmod 600. A stale socket (connect →
   `ECONNREFUSED`) is unlinked by **exact path**; the directory is never globbed or cleaned.

---

## 5. Behaviour (what each module must do)

### 5.1 Subsonic client (`src/music/subsonic/`, packet M1)

- Implements `SubsonicApi` (§6.2) exactly; `createSubsonicClient()` returns it.
- Transport: `POST ${baseUrl}/rest/<endpoint>` with `application/x-www-form-urlencoded` body
  (`u,t,s,v=1.16.1,c=gpuix-shell,f=json` + params; arrays as repeated keys). Default timeout 8 s
  (`AbortSignal.any([caller, timeout])`). One retry, reads only, network errors only (never on a
  Subsonic error, never on writes). gzip is honoured by fetch.
- Errors → `SubsonicError(kind, code, endpoint, message)`; mapping: missing/unreadable credential
  file → `credentials`; fetch failure/DNS/connect → `unreachable`; timeout → `timeout`; caller abort
  → `aborted`; code 40/41 → `auth`; 50 → `forbidden`; 70 → `not-found`; 10 → `usage`; non-2xx HTTP →
  `unreachable` with code `-status` (a plain-text 404 means an unknown endpoint → `server`).
- Response quirks handled in the client, not in callers: `albumInfo2 ?? albumInfo`; `toArray` for
  single-object answers (old Subsonic habit); empty list keys treated as `[]` by callers via `?? []`.
- `coverArt(id, size)`: GET (URL built inside the client, never returned), checks `Content-Type`
  starts with `image/` (else throws `SubsonicError("not-found"|"server")`), returns bytes. An
  in-memory LRU (default 200 entries, keyed `id@size`) dedups concurrent and repeated fetches.
- `streamUrl(id, o)`: `format=raw` unless `o.maxBitRate` or config `maxBitRate` → `format=opus&
  maxBitRate=n` (+ `timeOffset`). Fresh salt per call.
- `webUrl(kind, id)` → `${baseUrl}/app/#/<kind>/<id>/show`.
- `schema.ts`: zod v4 **loose** schemas (`z.looseObject`, optional everything Navidrome omits) for
  the envelope, `Song`, `Album`, `Artist`, `Playlist`, `SearchResult3`, `AlbumList2`, `Artists`.
  Used by the fixture tests always, and by the client only when `GPUIX_MUSIC_VALIDATE=1` (no
  hot-path cost).
- `record-fixtures.ts`: a bun script, refuses to run without `NAVIDROME_LIVE=1`, read-only endpoint
  allowlist, writes the §8.2 fixture set scrubbed (§4.6), each file ≤ 200 KB (truncate long lists
  and say so in a `_note` key).

### 5.2 Library (`src/music/library/`, packet M2)

**Cache** (`cache.ts`). Snapshot = artists (`getArtists`, flattened), albums (`getAlbumList2
alphabeticalByName`, paged 500 until a short page; trim names, the first entry is `"\n"`),
playlists (`getPlaylists`), genres (`getGenres`), stamp (`getScanStatus` `lastScan`, `count`,
`folderCount`). File: `$XDG_CACHE_HOME/gpuix-shell/music/library.json` (atomic write). Lifecycle:
`load()` from disk at service start (fast, never blocks first paint) → `refresh()` in the background:
fetch the stamp; rebuild when the stamp differs, the snapshot is older than 24 h, or `force`
(`Ctrl+R`, `rescan` command). Playlists and genres are re-fetched on every refresh (cheap, they change
without a scan). No timer: refresh runs at start and on demand only. Status `absent → building →
ready` drives the "Indexing the library" notice.

**Rank** (`normalize.ts`, `rank.ts`; R05 §8). Normalise: NFKD, strip marks, lowercase, `&` → `and`,
punctuation → space, collapse spaces; a leading `the ` is ignored for ranking only. Base score of a
candidate against the query:

| Match | Base |
|---|---|
| exact name | 1000 |
| name starts with the query | 800 |
| every query token prefixes a word of the name | 600 |
| every token prefixes a word of name ∪ artist (albums) — `davis kind` → Kind of Blue | 520 |
| every token contained | 400 |
| in-order subsequence over the name, 300 − 8 per gap char, floor 100 | 100–300 |
| one edit (substitution/insertion/deletion/transposition) on a token of ≥ 5 chars, others prefix | 150 |
| server hit not matched locally, at server rank r | 450 − 10 r |

Boosts: `+20·log2(1+playCount)`, `+60` liked, `+40` played in the last 30 days (`history.jsonl`),
`+frecency` (≤ 50, opened via this UI; half-life 14 days). Type prior artist +30, album +15,
playlist +10, song 0 counts **only** for the Top result and only when two candidates are within 5 %.

**Index** (`index.ts`). Built from a snapshot: pre-normalised name/artist strings and token lists for
~28k names. `query(q)` returns scored local hits per kind, top 50 each, in < 8 ms (assert on a
synthetic 30k fixture; report the measured time).

**Search** (`search.ts`; R05 §8 timing). `searchMusic(deps, query, o)` is an async generator:

1. `query.trim() === ""` → yield nothing (the UI shows Home). One character → local only, `server:"skipped"`.
2. LRU (50) hit on `(scope, offset, normalised query)` → yield that final, return.
3. Yield the **partial** from the index (`final:false`, `server:"pending"`; `index` status as is).
4. Sleep 60 ms (abort-aware), then `api.search` with `{artist:6, album:12, song:24}` for scope
   `all`, or 60 of the one kind with its offset for a scope view. Playlists are never in `search3`:
   they come from the local index (and the snapshot's list when the index is absent).
5. Merge: de-duplicate by id (local refs win for metadata, server adds what local lacks), rank every
   candidate with the same `matchScore` + boosts, take the Top result across kinds, cap sections at
   Songs 4 · Artists 3 · Albums 6 · Playlists 4 for `all` (full page for a scope), set `more` flags.
   Yield the **final** (`final:true`, `server:"done"`). On a server error, yield the final from
   local only with `server:"failed"` (the view shows the offline line, keeps local rows).
6. Log `music.search ms_local ms_server rows` through the injected logger, never the query text.

**Pages** (`pages.ts`). `albumPage` (`getAlbum`; disc titles), `artistPage` (`getArtist` +
`getArtistInfo2` + `getTopSongs(name)`; `popularSource` "lastfm" when top songs ≥ 1; when fewer than 5,
`mostPlayed` fills to 5 from the artist's album songs by playCount, fetched lazily only for the first
3 albums; albums split by `releaseTypes` into albums / singles+EPs / compilations / appears-on
(album artist ≠ this artist), newest first, `[Unknown Album]` last; bio HTML → Markdown, links kept),
`playlistPage`, `homePage` (shelves recent/newest/frequent/random, 5 each, in parallel, empties
dropped; recent searches; counts from the snapshot), `likedPage`, `genreList` (≥ 20 songs, by count).

**Art cache** (`art-cache.ts`; R05 §3.3). `path(coverArt, bucket)` → `$XDG_CACHE_HOME/gpuix-shell/
music/art/<sha1(coverArt)>-<bucket>.<jpg|png|webp>`; disk hit → path at once; miss → queue a fetch
(6 concurrent, newest request first, aborted when its signal aborts before start, in-flight dedup),
atomic write, resolve path; failure → `null` and a session negative cache. `prune()` at service start
evicts least-recently-modified files above 300 MB. Never stores a URL.

**Recents** (`recents.ts`). `RecentSearches` (`searches.json`: > 3 chars, dedupe, newest first,
max 10, remove one/all), `Frecency` (`frecency.json`), `playedSince(historyFile, sinceMs)` reading
M3's `history.jsonl`.

### 5.3 Player (`src/music/player/`, packet M3) — R04 is the design; this is the summary

- **mpv** (`mpv.ts`): spawn `config.mpvPath` with `mpvArgs()` = R04 §4's `MPV_ARGS` verbatim plus
  `--input-ipc-client=fd://3` (stdio `["ignore","ignore","pipe","pipe"]`; fd 3 is the socketpair),
  `--ao=<config.ao>` when set (tests: `null`), `--volume=<persisted>`, and with
  `GPUIX_SHELL_MPV_DEBUG_SOCKET=1` also `--input-ipc-server=<paths.mpvDebugSock>` (unlinked by exact
  path on exit). `GPUIX_MUSIC_BITPERFECT=1` swaps in `--gapless-audio=weak` without the 48 kHz flag.
  stderr lines go through `redact()` to the logger. `MpvIpc` is **transport-agnostic** (any
  `Duplex`): request ids, a 3 s reply timeout (→ engine hang path), `observe_property` with ids,
  event fan-out, `request_log_messages warn`.
- **Window** (`player.ts`, R04 §5): mpv's playlist is only `[current, successor]`. `reconcile()` after
  every queue mutation (coalesced to a microtask); advance detection keyed on `playlist_entry_id`
  from `start-file`, never on `playlist-pos`; manual next/previous/jump/play = `replace` (bump `gen`);
  repeat-one re-appends the same queue entry as successor (no `loop-file`); restore-paused uses named
  `loadfile` with `options:{start}` after `set pause yes` (R04 M12). URLs are minted at `loadfile`
  time and never stored (eid → uid map only).
- **Queue** (`queue.ts`, pure, R04 §6): play replaces the context and keeps Next in queue; next =
  user segment first; previous = restart after 3 s else history; shuffle only the context after the
  user segment (Fisher–Yates with an injectable rng); unshuffle restores order after the current;
  repeat off → all → one; enqueue `next` (head of Next in queue) / `end` (tail of Next in queue);
  rev-guarded move/remove/jump/clear; `snapshot()`/`restore()` for Undo; 10,000 item cap; history
  trimmed to 500 (snapshot shows 20); `unplayable` entries skipped by `peekNext`.
  **Positions in queue commands** (`queue.move/remove/jump` `from`/`to`/`indexes`/`index`) are
  **upcoming positions**: 0 = the first row of `upNext`, `upNext.length` = the first row of
  `contextNext`. A move across that boundary changes the entry's origin (R05 §5.7).
- **States** (R04 §8): project to `PlayerState` with `seq`, epoch-ms `positionAt`; emit on
  discontinuities only (track change, pause, seek, buffering, volume, queue rev, drift > 1 s), never
  per `time-pos`.
- **Reporting** (`scrobble.ts`, R04 §9): `reportPlayback` (`ignoreScrobble=true`) on start, pause,
  resume, seek, stop and a 60 s in-process heartbeat while playing; fallback `scrobble
  submission=false`; a play counts once via `scrobble submission=true&time=<start epoch ms>` when the
  track is > 30 s and listened time ≥ min(duration/2, 240 s); listened time sums positive `time-pos`
  deltas < 1.5 s. Qualified plays append to `history.jsonl`. Offline failures go to
  `scrobbles-pending.jsonl`, replayed after the next successful call (no timer), 14-day window,
  500-line cap. `NAVIDROME_SCROBBLE=0` disables all of it.
- **Persistence** (`state-files.ts`, R04 §7): `queue.json` (debounced 1 s), `now.json` (5 s while
  playing, on change, on SIGTERM with `cleanStop`), `state.json` (volume default 70, muted,
  normalize, autoplay, output). Crash-resume plays only if `now.json` is < 30 s old, same `bootId`,
  `wasPlaying` and no `cleanStop`; otherwise restore paused. No file ever holds a URL.
- **Server queue** (`playqueue-sync.ts`, P1): `savePlayQueueByIndex` window of ≤ 1,000 around the
  index, on pause / track change (debounced 5 s) / stop; restore adopts the server queue when newer
  by > 5 s and `changedBy !== "gpuix-shell"`. `NAVIDROME_SAVE_QUEUE=0` disables.
- **Failures** (R04 §12): mpv exit/hang → respawn with back-off 1/2/4/8/16 s, reload at position;
  > 5 respawns in 2 min → `engine failed`; `end-file error` → one `diagnose()` call → unreachable/auth
  pause with error; not-found/format → mark unplayable and skip; 3 consecutive failures stop.
- **MPRIS** (`mpris.ts`, R04 §11): bus name `org.mpris.MediaPlayer2.gpuix_music` (`DO_NOT_QUEUE`),
  Identity "Music", DesktopEntry "gpuix-shell-music"; Player properties and methods as R04's table;
  `mpris:trackid` per queue entry uid; `xesam:url` = web link; `mpris:artUrl` = `file://` art path
  at bucket 256. No session bus (`DBUS_SESSION_BUS_ADDRESS` unset or connect fails) → return `null`
  and log once. Name already owned → in the demo, log and continue without MPRIS; in `serve`, exit 1.
- **Outputs**: `audio-device-list` → `OutputSink[]`; `setOutput(name)` sets `audio-device` live
  (P1, unverified against the live PipeWire).
- **Radio** (`radio.ts`, P1, R05 §5.10): layered `getSimilarSongs(song)` → `getSimilarSongs2(artist)` →
  top songs of ≤ 5 similar artists → `getRandomSongs genre=<seed genre> fromYear=y−5 toYear=y+5`;
  dedupe by id, ≤ 2 per artist per 10, seed first; refill at ≤ 5 remaining from layers 3–4.

### 5.4 Service (`src/music/service/`, packet M6)

`createMusicService(o)` builds `api` (`createSubsonicClient`, or `createFakeSubsonic()` when
`config.fake`), the library cache (load from disk, refresh in background), index, art cache (prune
at start), recents, the player (`musicServerFromApi(api, config)` port), MPRIS (`o.mpris ?? true`),
and optionally `serveBackend(service, {path: paths.ctlSock})` (`o.serveSocket ?? true`). It
implements `MusicBackend` (`kind: "local"`).

**Play resolution** (`service/play.ts`; R05 §10):

| Request | Queue built |
|---|---|
| one `track`/`song` item, context `search` (or none) | that song, then the rest of its album **after** it (one `getAlbum`; the song alone when `albumId` is absent or the album is `[Unknown Album]`); context name "<title> · from search" |
| `track` items + `startIndex` + context `album`/`playlist`/`liked`/`queue` | those tracks from `startIndex` |
| `album:<id>` | `getAlbum` tracks in disc/track order |
| `playlist:<id>` | `getPlaylist` entries |
| `artist:<id>` | `getTopSongs(name)` when ≥ 5; else the artist's songs by album year, newest first, cap 200 |
| `genre:<name>` | `getRandomSongs genre size=100`, refilled at ≤ 5 |
| `query:"…"` | the final top result of `searchMusic`; artist/album/playlist/song as above; none → `{ok:false, error:{code:"not-found", message:"No results for \"…\""}}` |
| `shuffle-all` | `getRandomSongs size=100`, context `library-shuffle`, refilled |
| `radio` | `player/radio.ts` (P1); before it exists: `getSimilarSongs2(artistId)` then `getRandomSongs` by genre |

`shuffle: true` sets shuffle on before `play`. Every play/enqueue records the current search query
in recent searches (when the UI passes context `search`) and bumps frecency for the item.

**Outcomes and echoes** (`service/echo.ts`, pure; one text for footer, CLI and OSD; R05 §6, R01 §7.7):

| Command | Echo | Undo |
|---|---|---|
| play | "Playing Holocene" / "Playing Bon Iver, Bon Iver" / "Shuffling Bon Iver" | `queue.restore` previous snapshot |
| enqueue next / end | "Holocene plays next" / "Added Holocene to the queue" ("Added 10 songs to the queue") | `queue.restore` |
| toggle | "Paused" / "Playing Holocene" | — |
| next / previous | "Skipped to Towers" / "Replaying" / "Back to Perth" | — |
| seek | "Skipped ahead 15 seconds" / "Skipped back 15 seconds" / "Jumped to 1:30" | — |
| volume | "Music volume 70%"; invalid → `usage` "Volume must be between 0 and 100" / "Volume must be a number" | — |
| mute | "Music muted" / "Music unmuted" | — |
| shuffle / repeat | "Shuffle is on" / "Repeat: all" | — |
| like / unlike | "Liked Holocene" / "Removed Holocene from Liked" | inverse `like` |
| queue.move / remove / clear / jump | "Moved Teardrop up" / "Removed Teardrop" / "Cleared Next in queue" / "Playing Teardrop" | `queue.restore` |
| stale rev | `{ok:false, error:{code:"stale-rev", message:"The queue changed; nothing was moved"}}` | — |
| track verbs with nothing loaded | `nothing-playing` "Nothing is currently playing" | — |
| radio | "Playing radio from Holocene" | `queue.restore` |
| shuffle-all | "Shuffling 38,524 songs" | `queue.restore` |
| playlist.add | "Added Holocene to Late night"; error 50 → "Failed: Navidrome says this account may not edit playlists" | — |

Likes are optimistic: the state/rows flip at once; a server refusal reverts and returns
`{ok:false}`. Commands with `origin` other than `"ui"` also send the OSD payload (M7's `sendOsd`;
transport and volume only; nothing for a natural track change).

### 5.5 ctl.sock and CLI (`src/music/ipc/`, `src/music/cli.ts`, packet M4)

**Wire**: one JSON object per line both ways (`MusicRequestFrame` / `MusicResponse` in
`types.ts`). `hello` first (protocol 1). Commands → `backend.run(cmd, {origin: frame.origin ??
"cli"})` → `{id, ok:true, result: MusicOutcome}`. Queries → the typed method → `{id, ok:true,
result}`; failures → `{id, ok:false, error}`. `search` streams: each yielded snapshot is a line with
`partial: !final`, the final line `partial:false`. `cancel {target}` aborts that request's
controller (the socket client sends it when the caller's signal aborts). `watch` subscribes: one
`state` event at once, then one per change, plus `queue` and `index` events; the connection stays an
event stream. Server-side errors never include a stack or a URL.

**`connectBackend(o)`** implements `MusicBackend` (`kind:"socket"`) over one request connection plus
one watch connection; `state()` returns the last watched state (an idle placeholder until the
first event); reconnects the watch with back-off; rejects reads with `MusicFailure {code:"daemon",
message:"Music is not running", fix:"Start it with systemctl --user start gpuix-shell-music"}` when
the socket is absent or refuses.

**CLI** (`gpuix-shell music <verb>`; until wave 2's dispatcher: `bun src/music/cli.ts <verb>`):

| Verb | Command / output |
|---|---|
| `serve` | `createMusicService({serveSocket:true})`, stays in the foreground, SIGTERM → `dispose({cleanStop:true})` |
| `status` / `now` `[--json]` | one line `▶ Holocene · Bon Iver  2:31 / 5:36` (`nowLine`), or the `PlayerState` JSON |
| `watch` | JSON lines of state events |
| `toggle` · `play` (no arg = resume) · `pause` · `stop` · `next` · `prev`/`previous` | transport |
| `play <kind>:<id>` · `play "<query>"` | `play` with `PlayItem`s |
| `seek <+15|-15|90|1:30>` | relative when signed |
| `volume`/`vol <70|+10|-10>` · `mute [on|off]` | player volume |
| `shuffle [on|off|toggle]` · `repeat [off|all|one|cycle]` | modes |
| `like`/`star [on|off|toggle]` | like the current track |
| `radio` · `shuffle-all` | P1 sources |
| `search <query> [--json] [--scope songs|albums|artists|playlists]` | waits for the final; prints up to 10 lines `kind  id  title · subtitle` |
| `queue [--json]` · `queue add <kind>:<id> [--next]` · `queue clear` | queue |
| `open [route]` | `gpuix-shell launcher --view music/<route>` when that binary exists, else spawns the demo window with `--route <route>` (detached) |
| `output [list|<sink>]` · `copy` · `link` | P1 |

Human output is one line (the echo). Exit codes: **0** done · **2** usage (with R01 §7.7 messages) ·
**3** daemon not running ("Music is not running" + fix) · **4** offline or unauthorized · **5**
nothing playing. `--start` (or `GPUIX_MUSIC_AUTOSTART=1`) spawns `cli.ts serve` detached when the
socket is absent and retries for 3 s; the default is not to start audio implicitly. `parseMusicArgs`
is pure and table-tested.

### 5.6 Launcher provider (`src/music/provider/`, packet M4)

`createMusicProvider({backend, renderView})` implements `LauncherProvider<MusicRowData>` from
`src/launcher/provider.ts` (R05 §9.1, in the tree):

- `prime()`: resolves the backend (≤ 50 ms budget; a socket backend that is absent leaves the
  provider in the "Music is not running" state rather than failing).
- `search(query)` at the launcher **root**: one section "Music" with up to `rootLimit = 3` rows (top
  result first, then the best song/album/artist), rows built by `rowsFromSearch`; a "Commands"
  section of matching no-view commands (§6.7 `MUSIC_COMMANDS`, matched on title + keywords); when
  nothing matches, the fallback row `Search music for "…"` (opens `music/search?q=…`). Async iterable:
  local partial then final, exactly as the backend yields.
- Rows: ids `music:<kind>:<id>`, `art: { key: coverArt, shape, monogram, load: (bucket, signal) =>
  backend.art(coverArt, bucket, signal) }` (never a URL), accessories per R05 §3.2 using `format.ts`.
- `actions(row)` per kind, in R05 §5.11 order and groups: Play (↵), Open (Ctrl+↵), Play and close
  (Shift+↵), Play next (Alt+N), Add to queue (Alt+Q), Shuffle play (Ctrl+Shift+S), Start radio
  (Ctrl+Shift+R), Like/Unlike (Ctrl+L), Add to playlist… (Alt+P), Go to artist (Ctrl+G), Open in
  Navidrome (Ctrl+O, `ctx.openExternal(await backend.link(...))`), Copy link (Ctrl+Shift+C), Copy
  title (Ctrl+Shift+T). Each `run` calls `backend.run(..., {origin:"ui"})` and maps the outcome to
  `ActionOutcome` (`echo`, `undo: () => backend.run(outcome.undo)`, `error`).
- `open(route)`: every `music/*` route returns a `LauncherView` with `layout:"custom"` whose
  `render(props)` is `renderView(route, props)`; the integrator passes `(route, props) =>
  <MusicRoot backend embedded initialRoute={parseRoute(route.path)} size={props.size}
  onClose={props.ctx.close}/>`. The provider never imports `ui/` (no cycle, testable without GPUIX).
- `commands`: the `MUSIC_COMMANDS` registry; `run(args, ctx)` = the CLI verb's command.
- `strip()`: returns null (the music view draws its own strip; the root strip is wave 2's call).

### 5.7 GPUIX views (`src/music/ui/`, packet M5)

Built only from `@gpuix/react` host elements (`div`, `text`, `img`, `input`, `virtual-list`, `svg`,
`anchored`), `jsxImportSource @gpuix/react`, **every `<text>` names its colour** (GPUIX text does not
inherit), Anthropic Sans for UI, `AnthropicMono Nerd Font` for figures, Anthropic Serif only for lyrics
and bio prose. Flat and opaque, hairlines not shadows, no blur, no motion except the 2 px loading bar
and the progress fill (R05 §3, KIT). Layout geometry is R05 §3.1–3.2 scaled to `size`:
header 56 · hairline · body · hairline · strip 40 (when a track is loaded and not in Now Playing) ·
hairline · footer 35; body padding 12; rows 44 (song/album/artist/playlist), 40 (tracks), 72 (top
result), 28 (section headers); grid cards 5 per row; outer radius 16 in `--layer` mode, 0 in the
demo window (Sway draws the border).

**Views** (one file each, all driven by the same reducer and keymap):

| View (route) | File | P | Content |
|---|---|---|---|
| home (`""`) | `HomeView.tsx` | P0 | R05 §5.2 sections from `backend.home()` |
| search (`search?q=&scope=`) | `SearchView.tsx` | P0 | input-driven stream from `backend.search`; Top result card; sections; scope chips (Tab / Shift+Tab / Ctrl+P); scope views as lists (albums/artists as 5-column grids, P1) with paging on `onVisibleRange` |
| album (`album/<id>`) | `AlbumView.tsx` | P0 | header (cover 160, title, artist link, facts line, Play [brand] · Shuffle · Add to queue · Navidrome), discs, track rows, local filter |
| artist (`artist/<id>`) | `ArtistView.tsx` | P0 | header (circle 96, facts, two bio lines), Popular (source labelled), Most played by you, Albums grid, Singles and EPs, Appears on, Similar artists |
| playlist (`playlist/<id>`) | `PlaylistView.tsx` | P0 | album-like header + tracks |
| now playing (`now-playing`) | `NowPlaying.tsx` | P0 | R05 §5.6 layout; tabs Up next · Lyrics · Info (Lyrics/Info P1) |
| queue (`queue`) | `QueueView.tsx` | P0 | R05 §5.7 sections and keys |
| library (`library`, `library/<shelf>`, `liked`, `playlists`) | `LibraryView.tsx` | P1 | R05 §5.8–5.9 |
| root | `MusicRoot.tsx` | P0 | the frame, the view stack, global keys, actions panel, strip, footer echo/Undo, state subscription |

**Components** (`ui/components/`): `Row` (one grammar: leading cell, title + subtitle, ≤ 3
accessories, current/selected/hover looks, `testId`), `Art` (fixed-size placeholder tile with
monogram → `<img src={localPath} objectFit="cover">` with explicit width and height; circle for
artists), `Progress` (4 px track/fill; click/drag seeks via `onLayout` bounds; `aria-valuetext`),
`Section` (header 28: title, mono count, "Show all ›"), `Keycap`, `Accessory`, `MiniPlayer`
(strip), `Transport`, `Header` (back `‹`, breadcrumb word, input, scope chips, loading bar),
`Footer` (echo or context words · primary label ↵ · Actions Ctrl K), `ActionsPanel` (`anchored` to
the footer, width 340, own filter input, rows 32, groups split by hairlines), `EmptyState` (title +
hint + optional action), `Grid` (5 cards per virtual row), `TopResult`.

**Interaction rules** (R05 §4, §5.3, §9.3):

- The input keeps focus; the list cursor is state, not focus. `tabNavigation: false`,
  `keyboardFocusDim: false` on the window. Hover sets the cursor.
- Cursor pinning: after a keystroke the cursor sits on row 0 until the user moves it; after that it
  is pinned **by row id**; arriving rows never move it; if the pinned row disappears, the nearest
  surviving row above takes it.
- Key routing order: actions panel → view keys → the selected row's action shortcuts → global keys.
  Handlers call `preventDefault()` when they consume a key. If the `<input>` consumes `Ctrl+←/→` as
  word motion before `onKeyDown`, `Ctrl+.`/`Ctrl+,` are the next/previous fallbacks (the smoke
  decides; record the answer in BUILD-LOG).
- Esc: close panel → clear query → pop view → `onClose()` at the root. `Shift+Esc` closes from any
  depth. `Backspace` on an empty input pops.
- Undo: `Ctrl+Z` runs the last outcome's `undo` command within 6 s.
- `Space` toggles play/pause only when the input is empty; typed characters always go to the input
  (no single-letter shortcuts while a text field has focus; this supersedes the packet prompt's
  `s` = star and `?` = help, §11).
- testIds (for the automation tree and the smoke): `music.root`, `music.input`, `music.view.<view>`,
  `music.top`, `music.row.<kind>.<id>` (song rows inside a container: `music.row.song.<id>`),
  `music.section.<id>`, `music.strip`, `music.strip.toggle`, `music.footer.echo`, `music.panel`,
  `music.panel.<actionId>`, `music.nowplaying`, `music.progress`, `music.transport.<button>`.
  Every row also has `role="option"`, `aria-selected`, `aria-label` and `aria-description` (state
  words: "Playing", "Liked", "12 plays").
- Theme: `theme.ts` exports `THEMES` (§6.8) and `loadShellTheme()`, which reads
  `~/.config/theme/gpuix-shell.json` when present (BRIEF §3.5; maps role names it knows, ignores the
  rest) and falls back to `noir`. If wave 1's `docs/gpuix-shell/DESIGN.md` exists when you build,
  its token names and values win; record any difference in BUILD-LOG.

### 5.8 Demo (`src/music/demo/`, packet M6)

- `main.tsx` flags: `--fake` (= `NAVIDROME_FAKE=1`), `--layer` (overlay layer surface 700 × 580,
  `namespace gpuix-shell-launcher`, `layer overlay`, `anchor ["top"]`, `margin [108,0,0,0]`,
  `keyboardInteractivity "exclusive"`, Esc at root exits), `--route <path>` (initial route),
  `--daemon` (use `connectBackend` instead of an in-process service), `--no-socket` (do not serve
  `ctl.sock`). Window mode: `title "Music"`, `appId "gpuix-shell-music"`, 900 × 640,
  `windowBackground "opaque"`. It creates the renderer with `createRenderer()` and passes it to
  `render(..., {renderer})`; with `GPUIX_MUSIC_TREE_DUMP=<file>` it writes
  `renderer.getAutomationTree()` to that file on `SIGUSR1`; with `GPUIX_AUTOMATION=stdio` it calls
  `enableAutomation(renderer)`. SIGINT/SIGTERM → `service.dispose({cleanStop:true})`, then exit.
- `run.sh`: resolves bun (`$BUN`, `bun` on PATH, the soak build path, else `nix shell nixpkgs#bun`),
  links `node_modules` from probe011 only when the package has none, builds `LD_LIBRARY_PATH` from
  `nix build --no-link --print-out-paths` of `libxkbcommon wayland vulkan-loader fontconfig.lib
  freetype libglvnd xorg.libX11 xorg.libxcb openssl.out stdenv.cc.cc.lib` (falling back to the
  rail-probe's `/nix/store` globs), sets `VK_ICD_FILENAMES` only when unset and the radeon ICD
  exists, then `exec bun src/music/demo/main.tsx "$@"`.
- `on-client.sh`: Tom's one command (§9). Run from the strix.
- `testing/` (also M6): `catalog.ts` (deterministic synthetic catalogue: 5 artists, 10 albums,
  50 songs, 3 playlists; must contain ≥ 3 hits for `tal` across kinds and an album "Kind of Blue
  Skies" by "Mira Davis" for the cross-field case), `fake-subsonic.ts` (`SubsonicApi` over the
  catalogue; `streamUrl` → `av://lavfi:sine=frequency=<220..880>:duration=<song s>`; `coverArt` →
  a solid-colour PNG from `png.ts`; writes recorded in memory, never sent anywhere), `fake-backend.ts`
  (`MusicBackend` in memory, no mpv, for UI/provider unit tests), `png.ts` (tiny PNG encoder over
  `node:zlib`).

### 5.9 Integration and docs (`src/music/integration/`, docs, packet M7)

- `now-playing-chip.ts`: `chipModel(state)` (R05 §7.1: hidden when nothing is loaded or the daemon
  is down; glyph ⏸ while playing, ▶ paused; progress 0..1; `aria-valuetext`), `osdPayload(state,
  cause)` (R05 §7.2), `sendOsd(payload, {shellSock, fallback})`: writes one JSON line to
  `$XDG_RUNTIME_DIR/gpuix-shell/shell.sock`; when absent, nothing (R05: no fallback to mako) unless
  `GPUIX_MUSIC_OSD=notify-send`, which runs `notify-send -a Music -r 4242 -i <artPath> "<title>"
  "<artist>"` (arguments carry only metadata and a local path).
- `NowPlayingChip.tsx`: the rail chip component (196 × 46 expanded, 40 × 40 collapsed; click →
  `onOpen`, middle click → toggle, wheel → volume ±5 with `origin:"chip"`), mounted later by the rail
  owner with a socket backend.
- `sway-binds.conf.fragment` (proposal, not included anywhere): `$mod+m` → `gpuix-shell launcher
  --view music`, `$mod+Shift+m` → `… --view music/now-playing`; the media keys stay on `media` →
  `playerctl`, with the proposed one-line change `playerctl -p gpuix_music,%any`.
- `gpuix-shell-music.desktop` (Name "Music", `Exec=gpuix-shell music open`, Icon
  `audio-x-generic`), also the MPRIS `DesktopEntry`.
- `gpuix-shell-music.service` (proposal for `home/gpuix-shell.nix`): `ExecStart=gpuix-shell music
  serve`, `Type=dbus`, `BusName=org.mpris.MediaPlayer2.gpuix_music`, `Restart=on-failure`,
  `RestartSec=1`, `PartOf`/`WantedBy=sway-physical-session.target`, the three `NAVIDROME_*` env
  lines; no timer.
- `src/music/index.ts`: the public entry points for the shell (`createMusicService`,
  `connectBackend`, `serveBackend`, `createMusicProvider`, `MusicRoot`, `runMusicCli`,
  `NowPlayingChip`, `chipModel`).
- Docs: `docs/gpuix-shell/music/DEMO.md` (the runbook of §9 expanded: what works, what is stubbed,
  the key map) and `docs/gpuix-shell/music/ABOVE-RAYCAST.md` (what this does that the Raycast
  Navidrome extension cannot, from R02 §1.7 and §5, marked implemented / designed honestly).

---

## 6. Interfaces (exact TypeScript)

### 6.1 Frozen files already in the tree (do not change signatures; add only via the completer)

Written by this design pass and checked with `tsc --strict --noEmit` (exit 0) and `bun test
src/music/format.test.ts` (5 pass):

| File | Content |
|---|---|
| `pkgs/gpuix-shell/package.json`, `tsconfig.json`, `node_modules/` | deps pinned exact for gpuix (0.11.0), react 19.2.0, dbus-next 0.10.2, zod ^4, typescript 5.9.3; `bun install` done once (do not re-run concurrently; if you must add a dependency, note it in BUILD-LOG and let the completer install) |
| `src/launcher/provider.ts` | R05 §9.1 verbatim (the launcher provider contract; wave 2's launcher owner inherits it) |
| `src/music/types.ts` | the shared domain types, `MusicBackend`, `MusicCommand`, `MusicOutcome`, the ctl.sock wire protocol, `MusicRowData` |
| `src/music/errors.ts` | `MusicFailure`, `isMusicFailure`, `isAbort`, `toMusicError(e, {host, credentialsFile})` |
| `src/music/config.ts` | `musicConfig(env)`, `musicPaths(env)`, `MusicConfig`, `MusicPaths`, `SEARCH` constants (every env var and path) |
| `src/music/format.ts` (+ test) | `formatDuration`, `formatDurationWords`, `plural`, `formatPlays`, `formatClock`, `truncateMiddle`, `truncateEnd`, `displayAlbum`, `displayArtist`, `displayTitle`, `songSubtitle`, `albumSubtitle`, `trackLine`, `monogram`, `relativeAge`, `livePositionMs`, `statusWord`, `nowLine` |
| `src/music/subsonic/types.ts` | R03 §8 verbatim (measured response shapes) |
| `src/music/subsonic/api.ts` | `SubsonicApi`, `SubsonicError`, `SubsonicErrorKind`, `StarTarget`, `SearchCounts`, `AlbumListOptions`, `ReportState` |
| `src/music/subsonic/map.ts` | `toTrackRef`, `toAlbumRef`, `toArtistRef`, `toPlaylistRef`, `toGenreRef` |

Differences from R05 §9.2 (deliberate): `PlayItem` gains `{kind:"track", track}` (no refetch);
reads and commands are split (`MusicQuery` / `MusicCommand`), commands resolve a `MusicOutcome` whose
`undo` is itself a command; `output` list/set split into the `outputs` query and `output` command;
`hello`, `cancel`, `shuffle-all`, `playlist.create`, `recent-search.*`, `rescan` added; `positionAt` is
epoch ms; `PlayerState.message` carries "End of queue"; `MusicRowData` gains `command`; frames carry
`origin`.

### 6.2 Subsonic (M1) — `src/music/subsonic/`

```ts
// auth.ts
import type { MusicConfig } from "../config";
export interface SubsonicCreds { baseUrl: string; user: string; password: string }
export const CLIENT_NAME = "gpuix-shell";
export const API_VERSION = "1.16.1";
/** Reads the credential file NOW (every call); throws SubsonicError("credentials") naming the path only. */
export function readCreds(cfg: Pick<MusicConfig, "baseUrl" | "credentialsFile">): SubsonicCreds;
/** u, t, s (8 random bytes hex, fresh), v, c — without f (media endpoints must not get f=json). */
export function authParams(c: SubsonicCreds): URLSearchParams;

// redact.ts
export function redact(text: string): string;          // §4.5
export function redactUrl(url: string): string;        // origin + path, no query

// client.ts
import type { SubsonicApi } from "./api";
export interface ClientOptions {
  config?: MusicConfig;            // default musicConfig()
  fetch?: typeof fetch;            // tests inject a fake
  timeoutMs?: number;              // default 8000
  retries?: number;                // default 1 (reads, network errors only)
  validate?: boolean;              // default env GPUIX_MUSIC_VALIDATE === "1"
  coverLru?: number;               // default 200 entries
  log?: (event: string, fields?: Record<string, string | number | boolean>) => void;
}
export function createSubsonicClient(o?: ClientOptions): SubsonicApi;

// schema.ts
import { z } from "zod";
export const EnvelopeSchema: z.ZodType; export const SongSchema: z.ZodType; export const AlbumSchema: z.ZodType;
export const ArtistSchema: z.ZodType; export const PlaylistSchema: z.ZodType; export const SearchResult3Schema: z.ZodType;
export const AlbumList2Schema: z.ZodType; export const ArtistsSchema: z.ZodType;
export function validateResponse(endpoint: string, json: unknown): void;   // throws SubsonicError("server") with the zod path, no values

// record-fixtures.ts — bun script; NAVIDROME_LIVE=1 required; read-only allowlist; scrubs per §4.6
```

### 6.3 Library (M2) — `src/music/library/`

```ts
import type { SubsonicApi } from "../subsonic/api";
import type * as S from "../subsonic/types";
import type { AlbumRef, ArtBucket, ArtistPage, AlbumPage, ArtistRef, GenreRef, HomePage, LikedPage,
  MusicSearchResult, PlaylistPage, PlaylistRef, SearchScope, AlbumShelf } from "../types";

// cache.ts
export type IndexStatus = "absent" | "building" | "ready";
export interface LibraryStamp { lastScan: string; songs: number; folders: number }
export interface LibrarySnapshot {
  version: 1; builtAt: number; stamp: LibraryStamp;
  artists: ArtistRef[]; albums: AlbumRef[]; playlists: PlaylistRef[]; genres: GenreRef[];
}
export interface LibraryCache {
  readonly status: IndexStatus;
  snapshot(): LibrarySnapshot | null;
  load(): Promise<LibrarySnapshot | null>;                                   // disk only
  refresh(o?: { force?: boolean; signal?: AbortSignal }): Promise<LibrarySnapshot>;
  onChange(listener: (s: LibrarySnapshot | null, status: IndexStatus) => void): () => void;
}
export function createLibraryCache(o: { api: SubsonicApi; file: string; maxAgeMs?: number; now?: () => number;
  pageSize?: number; log?: (event: string, fields?: Record<string, string | number | boolean>) => void }): LibraryCache;
export function needsRebuild(s: LibrarySnapshot | null, stamp: LibraryStamp, now: number, maxAgeMs: number): boolean;

// normalize.ts / rank.ts
export function normalize(s: string): string;
export function tokens(s: string): string[];
export interface RankFields { name: string; artist?: string }
export function matchScore(query: string, f: RankFields): number;            // 0 = no match (table §5.2)
export function boost(o: { playCount?: number; liked?: boolean; recent?: boolean; frecency?: number }): number;
export const TYPE_PRIOR: { artist: 30; album: 15; playlist: 10; song: 0 };

// index.ts
export interface Scored<T> { ref: T; score: number }
export interface LocalHits { artists: Scored<ArtistRef>[]; albums: Scored<AlbumRef>[]; playlists: Scored<PlaylistRef>[] }
export class LibraryIndex {
  constructor(s: LibrarySnapshot, o?: { recent?: (id: string) => boolean; frecency?: (id: string) => number });
  query(q: string, o?: { limit?: number }): LocalHits;                       // < 8 ms on 30k names
  readonly size: number;
}

// search.ts
export interface SearchDeps {
  api: SubsonicApi;
  index(): LibraryIndex | null;
  indexStatus(): IndexStatus;
  playlists(): PlaylistRef[];                                                // fallback when the index is absent
  recent?: (id: string) => boolean;
  frecency?: (id: string) => number;
  debounceMs?: number;                                                       // default SEARCH.serverDebounceMs
  log?: (event: string, fields?: Record<string, string | number | boolean>) => void;
}
export function searchMusic(deps: SearchDeps, query: string,
  o?: { scope?: SearchScope; offset?: number; signal?: AbortSignal }): AsyncIterable<MusicSearchResult>;
/** Pure merge + rank + cap; tested on fixtures. */
export function mergeResults(query: string, scope: SearchScope, offset: number, local: LocalHits,
  server: S.SearchResult3 | null, o?: { recent?: (id: string) => boolean; frecency?: (id: string) => number }):
  Pick<MusicSearchResult, "top" | "songs" | "artists" | "albums" | "playlists" | "more">;

// pages.ts
export function albumPage(api: SubsonicApi, id: string, signal?: AbortSignal): Promise<AlbumPage>;
export function artistPage(api: SubsonicApi, id: string, signal?: AbortSignal): Promise<ArtistPage>;
export function playlistPage(api: SubsonicApi, id: string, signal?: AbortSignal): Promise<PlaylistPage>;
export function homeShelves(api: SubsonicApi, signal?: AbortSignal): Promise<HomePage["shelves"]>;
export function albumShelf(api: SubsonicApi, shelf: AlbumShelf, o?: { offset?: number; size?: number }, signal?: AbortSignal): Promise<AlbumRef[]>;
export function likedPage(api: SubsonicApi, signal?: AbortSignal): Promise<LikedPage>;
export function genreList(api: SubsonicApi, o?: { minSongs?: number }, signal?: AbortSignal): Promise<GenreRef[]>;
export function bioToMarkdown(html: string): string;

// art-cache.ts
export interface ArtCache {
  path(coverArt: string, bucket: ArtBucket, signal?: AbortSignal): Promise<string | null>;
  prune(maxBytes?: number): Promise<void>;
}
export function createArtCache(o: { api: SubsonicApi; dir: string; concurrency?: number; maxBytes?: number }): ArtCache;
export function artFileName(coverArt: string, bucket: ArtBucket, contentType: string): string;

// recents.ts
export class RecentSearches { constructor(file: string); list(): string[]; add(q: string): void; remove(q?: string): void }
export class Frecency { constructor(file: string, now?: () => number); bump(id: string): void; score(id: string): number }
export function playedSince(historyFile: string, sinceMs: number): Set<string>;
```

### 6.4 Player (M3) — `src/music/player/`

```ts
import type { Duplex } from "node:stream";
import type { MusicConfig } from "../config";
import type { SubsonicApi } from "../subsonic/api";
import type { CommandOrigin, MusicCommand, MusicOutcome, OutputSink, PlayContext, PlayerState,
  QueueSnapshot, RepeatMode, TrackRef } from "../types";

// mpv.ts
export const MPV_ARGS: readonly string[];                                   // R04 §4 verbatim, without the IPC flag
export function mpvArgs(cfg: Pick<MusicConfig, "ao" | "bitPerfect" | "mpvDebugSocket" | "paths">, volume: number): string[];
export class MpvIpc {
  constructor(stream: Duplex, o?: { timeoutMs?: number });
  command<T = unknown>(...args: unknown[]): Promise<T>;
  commandNamed<T = unknown>(cmd: Record<string, unknown>): Promise<T>;
  get<T = unknown>(prop: string): Promise<T>;
  set(prop: string, value: unknown): Promise<void>;
  observe(prop: string, cb: (value: unknown) => void): Promise<() => void>;
  on(event: string, cb: (ev: Record<string, unknown>) => void): () => void;
  close(): void;
}
export interface MpvProcess { ipc: MpvIpc; pid: number; exited: Promise<{ code: number | null; signal: string | null }>; kill(sig?: NodeJS.Signals): void }
export function spawnMpv(o: { path: string; args: string[]; log?: (line: string) => void }): Promise<MpvProcess>;

// queue.ts (pure)
export type Origin = "context" | "user";
export interface Entry { uid: string; track: TrackRef; origin: Origin; unplayable?: true }
export interface QueueState { items: Entry[]; index: number; shuffle: boolean; repeat: RepeatMode;
  unshuffled?: string[]; context: PlayContext | null; rev: number }
export class QueueStaleError extends Error {}
export class Queue {
  constructor(state?: QueueState, rng?: () => number);
  get state(): QueueState;
  get current(): Entry | null;
  play(tracks: TrackRef[], startIndex: number, context: PlayContext | null, o?: { shuffle?: boolean }): QueueSnapshot; // returns the previous snapshot
  next(o?: { auto?: boolean }): Entry | null;                               // null = end of queue
  previous(positionMs: number): { restart: boolean; entry: Entry | null };
  peekNext(o?: { auto?: boolean }): Entry | null;
  advanceTo(uid: string): void;
  enqueue(tracks: TrackRef[], where: "next" | "end"): void;
  appendToContext(tracks: TrackRef[]): void;
  move(rev: number, from: number, to: number): void;                         // upcoming positions (§5.3)
  remove(rev: number, positions: number[]): void;
  jump(rev: number, position: number): Entry;
  clear(rev: number, part: "up-next" | "all"): void;
  setShuffle(on: boolean): void;
  setRepeat(mode: RepeatMode): void;
  cycleRepeat(): RepeatMode;
  markUnplayable(uid: string): void;
  remaining(): { upNext: number; context: number };
  snapshot(): QueueSnapshot;
  restore(s: QueueSnapshot): void;
  toJSON(): QueueState;
}

// server-port.ts — R04 §14's MusicServer, implemented over SubsonicApi
export interface MusicServer {
  streamUrl(id: string): string;
  getSong(id: string): Promise<TrackRef>;
  refill(context: PlayContext, last: TrackRef | null): Promise<TrackRef[]>;
  reportPlayback(r: { id: string; positionMs: number; state: "starting" | "playing" | "paused" | "stopped" }): Promise<void>;
  scrobble(plays: { id: string; time: number }[], submission: boolean): Promise<void>;
  savePlayQueueByIndex(ids: string[], currentIndex: number, positionMs: number): Promise<void>;
  getPlayQueueByIndex(): Promise<{ tracks: TrackRef[]; currentIndex: number; positionMs: number; changed: string; changedBy: string } | null>;
  diagnose(id: string): Promise<"unreachable" | "auth" | "not-found" | "ok">;
}
export function musicServerFromApi(api: SubsonicApi, cfg: MusicConfig): MusicServer;

// observable.ts
export interface Observable<T> { readonly value: T; subscribe(listener: (value: T) => void): () => void }
export function observable<T>(initial: T): Observable<T> & { set(value: T): void };

// player.ts — R04 §14
export type EngineEvent =
  | { type: "trackChanged"; entry: Entry; auto: boolean } | { type: "ended" }
  | { type: "queueChanged"; rev: number } | { type: "played"; id: string }
  | { type: "volume"; volume: number; muted: boolean } | { type: "error"; kind: string; message: string };
export interface PlayerOptions {
  server: MusicServer; config: MusicConfig;
  mpvExtraArgs?: string[]; scrobble?: boolean; saveServerQueue?: boolean; now?: () => number;
  log?: (event: string, fields?: Record<string, string | number | boolean>) => void;
}
export class Player {
  static start(o: PlayerOptions): Promise<Player>;
  dispose(o?: { cleanStop?: boolean }): Promise<void>;
  readonly state$: Observable<PlayerState>;
  readonly events$: Observable<EngineEvent | null>;
  play(tracks: TrackRef[], startIndex?: number, context?: PlayContext | null, o?: { shuffle?: boolean }): Promise<QueueSnapshot>;
  toggle(): Promise<void>; resume(): Promise<void>; pause(): Promise<void>; stop(): Promise<void>;
  next(): Promise<void>; previous(): Promise<{ restarted: boolean }>;
  seek(seconds: number, relative?: boolean): Promise<void>;
  setVolume(value: number, relative?: boolean): Promise<number>;
  setMuted(on?: boolean): Promise<boolean>;
  setShuffle(on?: boolean): Promise<boolean>; setRepeat(mode?: RepeatMode): Promise<RepeatMode>;
  enqueue(tracks: TrackRef[], where: "next" | "end"): Promise<QueueSnapshot>;
  appendToContext(tracks: TrackRef[]): Promise<void>;
  move(rev: number, from: number, to: number): Promise<QueueSnapshot>;
  remove(rev: number, positions: number[]): Promise<QueueSnapshot>;
  jump(rev: number, position: number): Promise<QueueSnapshot>;
  clear(rev: number, part: "up-next" | "all"): Promise<QueueSnapshot>;
  snapshot(): QueueSnapshot;
  restore(s: QueueSnapshot): Promise<void>;
  setLiked(id: string, liked: boolean): void;                                // keep TrackRefs in the queue in sync
  outputs(): Promise<OutputSink[]>; setOutput(name: string): Promise<void>;
}

// mpris.ts
export interface MprisHost { state(): PlayerState; run(c: MusicCommand, o?: { origin?: CommandOrigin }): Promise<MusicOutcome>; raise(): void }
export interface MprisHandle { update(s: PlayerState): void; seeked(positionMs: number): void; stop(): Promise<void> }
export function startMpris(host: MprisHost, o?: { busName?: string; artPath?: (s: PlayerState) => string | undefined;
  webUrl?: (s: PlayerState) => string | undefined }): Promise<MprisHandle | null>;

// radio.ts (P1)
export function radioTracks(api: SubsonicApi, seed: { kind: "song" | "artist" | "album"; id: string }, o?: { exclude?: Set<string>; count?: number }): Promise<TrackRef[]>;

// smoke-play.ts — bun script (§8.3)
```

### 6.5 Service and test doubles (M6) — `src/music/service/`, `src/music/testing/`

```ts
import type { MusicConfig } from "../config";
import type { SubsonicApi } from "../subsonic/api";
import type { MusicBackend, MusicCommand, MusicOutcome, PlayContext, PlayItem, PlayerState, TrackRef } from "../types";

// service/service.ts
export interface ServiceOptions {
  config?: MusicConfig;                // default musicConfig()
  api?: SubsonicApi;                   // default config.fake ? createFakeSubsonic() : createSubsonicClient({config})
  mpris?: boolean;                     // default true (skipped quietly without a session bus)
  serveSocket?: boolean;               // default true: serveBackend(service, {path: config.paths.ctlSock})
  mpvExtraArgs?: string[];
  log?: (event: string, fields?: Record<string, string | number | boolean>) => void;
}
export interface MusicService extends MusicBackend {
  readonly kind: "local";
  readonly config: MusicConfig;
  /** Resolves when the player is up and the library snapshot is loaded from disk (not rebuilt). */
  readonly ready: Promise<void>;
  dispose(o?: { cleanStop?: boolean }): Promise<void>;
}
export function createMusicService(o?: ServiceOptions): Promise<MusicService>;

// service/play.ts
export interface ResolvedPlay { tracks: TrackRef[]; startIndex: number; context: PlayContext | null; label: string }
export function resolvePlay(api: SubsonicApi, req: { items: PlayItem[]; context?: PlayContext; startIndex?: number },
  deps: { searchTop(query: string): Promise<PlayItem | null> }, signal?: AbortSignal): Promise<ResolvedPlay>;

// service/echo.ts (pure)
export function echoFor(cmd: MusicCommand, before: PlayerState, after: PlayerState, extra?: { label?: string; count?: number }): string | undefined;

// testing/catalog.ts
export interface FakeCatalog { artists: import("../subsonic/types").ArtistWithAlbums[]; albums: import("../subsonic/types").AlbumWithSongs[];
  songs: import("../subsonic/types").Song[]; playlists: Array<import("../subsonic/types").Playlist & { entry: import("../subsonic/types").Song[] }> }
export function fakeCatalog(seed?: number): FakeCatalog;                     // deterministic; 5 artists, 10 albums, 50 songs, 3 playlists
// testing/fake-subsonic.ts
export function createFakeSubsonic(o?: { catalog?: FakeCatalog; latencyMs?: number; fail?: "offline" | "auth" }): SubsonicApi & { writes: Array<{ endpoint: string; params: unknown }> };
// testing/fake-backend.ts
export function createFakeBackend(o?: { catalog?: FakeCatalog; state?: Partial<PlayerState> }): MusicBackend & { commands: MusicCommand[]; setState(p: Partial<PlayerState>): void };
// testing/png.ts
export function solidPng(size: number, rgb: [number, number, number]): Uint8Array;
```

### 6.6 ctl.sock and CLI (M4) — `src/music/ipc/`, `src/music/cli.ts`

```ts
import type { MusicBackend, MusicCommand, MusicRequestFrame, MusicResponse, SearchScope } from "../types";

// ipc/codec.ts
export function encodeLine(v: MusicRequestFrame | MusicResponse): string;      // JSON + "\n"
export class LineDecoder { push(chunk: string | Uint8Array): unknown[] }      // tolerant of split lines; drops lines > 4 MiB

// ipc/server.ts
export interface SocketServer { readonly path: string; close(): Promise<void> }
export function serveBackend(backend: MusicBackend, o: { path: string;
  log?: (event: string, fields?: Record<string, string | number | boolean>) => void }): Promise<SocketServer>;
/** Pure dispatch of one frame against a backend (also used by tests without a socket). */
export function dispatchFrame(backend: MusicBackend, frame: MusicRequestFrame,
  send: (r: MusicResponse) => void, signal: AbortSignal): Promise<void>;

// ipc/client.ts
export function connectBackend(o: { path: string; timeoutMs?: number }): Promise<MusicBackend & { readonly kind: "socket" }>;

// cli.ts
export type CliVerb = "serve" | "status" | "watch" | "toggle" | "play" | "pause" | "stop" | "next" | "previous" | "seek"
  | "volume" | "mute" | "shuffle" | "repeat" | "like" | "radio" | "shuffle-all" | "search" | "queue" | "open" | "output" | "copy" | "link";
export type ParsedArgs =
  | { ok: true; verb: CliVerb; json: boolean; start: boolean; command?: MusicCommand;
      search?: { query: string; scope: SearchScope }; route?: string; queue?: "show" | "add" | "clear" }
  | { ok: false; message: string };
export function parseMusicArgs(argv: string[]): ParsedArgs;                   // pure
export interface CliIO { stdout(s: string): void; stderr(s: string): void; env: Record<string, string | undefined> }
export function runMusicCli(argv: string[], io?: CliIO): Promise<number>;    // exit code (§5.5)
// if (import.meta.main) process.exit(await runMusicCli(process.argv.slice(2)));
```

### 6.7 Launcher provider (M4) — `src/music/provider/`

```ts
import type { ReactNode } from "react";
import type { Action, CommandId, CustomViewProps, LauncherProvider, Route, Row, Section } from "../../launcher/provider";
import type { MusicBackend, MusicCommand, MusicRowData, MusicSearchResult } from "../types";

// provider/music-provider.ts
export interface MusicProviderOptions {
  backend: MusicBackend | (() => Promise<MusicBackend>);
  renderView?: (route: Route, props: CustomViewProps) => ReactNode;
}
export function createMusicProvider(o: MusicProviderOptions): LauncherProvider<MusicRowData>;

// provider/rows.ts (pure)
export function rowsFromSearch(r: MusicSearchResult, o?: { root?: boolean; rootLimit?: number }): Section<MusicRowData>[];
export function songRow(t: import("../types").TrackRef, o?: { context?: import("../types").PlayContext; index?: number }): Row<MusicRowData>;
export function albumRow(a: import("../types").AlbumRef): Row<MusicRowData>;
export function artistRow(a: import("../types").ArtistRef): Row<MusicRowData>;
export function playlistRow(p: import("../types").PlaylistRef): Row<MusicRowData>;

// provider/actions.ts
export function actionsFor(row: Row<MusicRowData>, backend: MusicBackend): Action<MusicRowData>[];

// provider/commands.ts (pure registry; the CLI, root rows and MPRIS share these ids)
export interface MusicCommandSpec { id: CommandId; title: string; keywords: string[]; cli: string; build(args: string[]): MusicCommand | null }
export const MUSIC_COMMANDS: readonly MusicCommandSpec[];   // music.toggle, .next, .previous, .seek, .stop, .volume, .mute, .shuffle,
                                                            // .repeat, .like-current, .radio-current, .shuffle-all, .now-playing, .queue, .open
```

### 6.8 GPUIX views (M5) — `src/music/ui/`

```ts
import type { ReactNode } from "react";
import type { AlbumShelf, MusicBackend, MusicCommand, SearchScope } from "../types";

// routes.ts
export type MusicRoute =
  | { view: "home" } | { view: "search"; query: string; scope: SearchScope }
  | { view: "album"; id: string; focusTrackId?: string } | { view: "artist"; id: string }
  | { view: "playlist"; id: string } | { view: "playlists" } | { view: "library" } | { view: "shelf"; shelf: AlbumShelf }
  | { view: "liked" } | { view: "queue" } | { view: "now-playing"; tab?: "up-next" | "lyrics" | "info" }
  | { view: "output" } | { view: "pick-playlist"; songIds: string[] };
export function parseRoute(path: string): MusicRoute | null;               // "", "search?q=bon&scope=all", "album/<id>", "now-playing", …
export function routePath(r: MusicRoute): string;

// state.ts (pure)
export interface ViewFrame { route: MusicRoute; query: string; scope: SearchScope; cursorId: string | null; cursorMoved: boolean }
export interface Echo { text: string; tone: "default" | "danger"; undo?: MusicCommand; until: number }
export interface UiState {
  stack: ViewFrame[];
  panel: { open: boolean; filter: string; cursor: number };
  detail: boolean;
  echo: Echo | null;
  lastError: string | null;
}
export type UiAction =
  | { type: "push"; route: MusicRoute } | { type: "pop" } | { type: "query"; text: string }
  | { type: "scope"; dir: 1 | -1 } | { type: "scope-set"; scope: SearchScope }
  | { type: "cursor"; id: string | null; moved: boolean } | { type: "rows"; ids: string[] }
  | { type: "panel"; open: boolean } | { type: "panel-filter"; text: string } | { type: "panel-cursor"; delta: number }
  | { type: "detail" } | { type: "echo"; text: string; tone?: "default" | "danger"; undo?: MusicCommand; now: number }
  | { type: "echo-expire"; now: number } | { type: "error"; message: string };
export function initialUiState(route?: MusicRoute): UiState;
export function uiReducer(s: UiState, a: UiAction): UiState;
export function pinCursor(prevIds: string[], nextIds: string[], cursorId: string | null, moved: boolean): string | null;

// keymap.ts (pure)
export type ViewKind = MusicRoute["view"];
export type RowActionId = "play" | "open" | "play-close" | "play-next" | "add-to-queue" | "shuffle-play" | "radio" | "like" | "unlike"
  | "add-to-playlist" | "popular" | "go-artist" | "open-navidrome" | "copy-link" | "copy-title" | "remove" | "remove-all" | "move-up" | "move-down";
export type UiCommand =
  | { kind: "nav"; to: "up" | "down" | "page-up" | "page-down" | "left" | "right" | "back" | "close" | "close-all" }
  | { kind: "row"; action: RowActionId } | { kind: "panel" } | { kind: "detail" } | { kind: "scope"; dir: 1 | -1 }
  | { kind: "refresh" } | { kind: "undo" } | { kind: "copy-error" }
  | { kind: "music"; command: MusicCommand } | { kind: "go"; route: MusicRoute };
export interface KeyContext { view: ViewKind; inputEmpty: boolean; panelOpen: boolean }
export interface KeyBinding { keys: string[]; command: UiCommand; title: string; views?: ViewKind[]; whenInputEmpty?: boolean }
export const KEYMAP: readonly KeyBinding[];
export function keystrokeOf(e: { key?: string; modifiers?: { ctrl: boolean; alt: boolean; shift: boolean; cmd: boolean } }): string; // "ctrl-shift-enter"
export function resolveKey(keystroke: string, ctx: KeyContext): UiCommand | null;

// theme.ts
export interface MusicTheme {
  name: "noir" | "claude-dark" | "claude-light";
  surface: { overlay: string; sunken: string; base: string };
  line: { hairline: string; default: string; strong: string };
  state: { selected: string; hover: string };
  ink: { default: string; muted: string; subtle: string; onBrand: string };
  accent: { default: string; muted: string };
  brand: { emphasis: string };
  status: { dangerFg: string };
  font: { ui: "Anthropic Sans"; mono: "AnthropicMono Nerd Font"; prose: "Anthropic Serif" };
}
export const THEMES: Readonly<Record<MusicTheme["name"], MusicTheme>>;
export function loadShellTheme(path?: string): MusicTheme;                  // ~/.config/theme/gpuix-shell.json, else noir
export function ThemeProvider(p: { theme: MusicTheme; children: ReactNode }): ReactNode;
export function useTheme(): MusicTheme;

// effects.ts
export interface UiEffects { copy(text: string): Promise<void>; openExternal(url: string): Promise<void>; now(): number }
export const defaultEffects: UiEffects;                                      // wl-copy via stdin; xdg-open http(s) only

// hooks.ts
export function useMusicState(backend: MusicBackend): import("../types").PlayerState;
export function useLivePosition(state: import("../types").PlayerState, hz?: number): number;   // 4 Hz while playing and mounted
export function useArt(backend: MusicBackend, coverArt: string | undefined, bucket: 96 | 256 | 512): string | null;
export function useSearch(backend: MusicBackend, query: string, scope: SearchScope): import("../types").MusicSearchResult | null;

// MusicRoot.tsx
export interface MusicRootProps {
  backend: MusicBackend;
  size: { width: number; height: number };
  theme?: MusicTheme;
  initialRoute?: MusicRoute;
  embedded?: boolean;                  // inside the launcher host: no outer frame/radius; Esc at root → onClose
  layer?: boolean;                     // --layer mode: radius 16, 1 px line.strong edge
  onClose?(): void;
  effects?: Partial<UiEffects>;
}
export function MusicRoot(p: MusicRootProps): ReactNode;
// SearchView, HomeView, AlbumView, ArtistView, PlaylistView, NowPlaying, QueueView, LibraryView:
export interface ViewProps { backend: MusicBackend; frame: import("./state").ViewFrame; size: { width: number; height: number };
  dispatch(a: import("./state").UiAction): void; run(c: MusicCommand): Promise<void>; push(r: MusicRoute): void }
```

Theme values (noir from R05 §3.4; the two Claude themes derived from `home/themes/*.nix`; replace with
DESIGN.md's if it exists):

| Role | noir | claude-dark | claude-light |
|---|---|---|---|
| surface.overlay / sunken / base | #101111 / #000000 / #000000 | #20201F / #151515 / #1A1A1A | #FFFFFF / #F3F3F0 / #F9F9F7 |
| line.hairline / default / strong | rgba(222,220,209,.15) / .30 / .44 | same as noir | rgba(31,30,29,.15) / .30 / .44 |
| state.selected / hover | #242321 / #161615 | #2E2E2C / #262624 | #ECEBE6 / #F3F3F0 |
| ink.default / muted / subtle / onBrand | #D3D7DE / #818898 / #818898 / #131313 | #EAECF0 / #818898 / #52514E / #131313 | #131313 / #52514E / #6E7687 / #FFFFFF |
| accent.default / muted | #70B8FF / rgba(112,184,255,.13) | same as noir | #0051C2 / rgba(0,81,194,.13) |
| brand.emphasis | #D97757 | #D97757 | #D97757 |
| status.dangerFg | #F47B85 | #F47B85 | #B80A18 |

### 6.9 Demo (M6) — `src/music/demo/`

`main.tsx` (flags §5.8; it renders on import, so it exports nothing), `args.ts` (pure, tested),
`run.sh`, `on-client.sh` (flags §9).

```ts
// demo/args.ts
export interface DemoArgs { fake: boolean; layer: boolean; route?: string; daemon: boolean; socket: boolean }
export function parseDemoArgs(argv: string[]): DemoArgs;
```

### 6.10 Integration (M7) — `src/music/integration/`

```ts
import type { ReactNode } from "react";
import type { MusicBackend, MusicCommand, PlayerState } from "../types";

// now-playing-chip.ts
export interface ChipModel { visible: boolean; title: string; artist: string; status: "playing" | "paused" | "buffering";
  glyph: "⏸" | "▶"; artPath?: string; progress: number; timeText: string; ariaValueText: string }
export function chipModel(s: PlayerState | null, now?: number): ChipModel;
export interface OsdPayload { type: "osd"; slot: "music"; title: string; subtitle: string; art?: string; level: number; word: string }
export function osdPayload(s: PlayerState, cause: { kind: "transport" | "volume"; command: MusicCommand }): OsdPayload | null;
export function sendOsd(p: OsdPayload, o: { shellSock: string; fallback?: "none" | "notify-send" }): Promise<boolean>;

// NowPlayingChip.tsx
export function NowPlayingChip(p: { backend: MusicBackend; collapsed?: boolean; onOpen?(): void }): ReactNode;
```

---

## 7. Packets and file ownership (seven parallel builders)

Rules for everyone:

- You own only your paths. Read anything. If you need a change in someone else's file or a frozen
  file, write the request in BUILD-LOG under your heading; the completer (job 014) applies it.
- Code against the frozen files (§6.1) and the signatures above. If a dependency module does not
  exist yet when you need it, code against its §6 signature and test with your own small stub; do
  not create another packet's file.
- Run your tests with `/home/tom/today/2026-10-14-convergence-soak/build/bun/bin/bun test <files>`
  from `pkgs/gpuix-shell`, and typecheck your own files with `bun x tsc --noEmit -p .` (errors in
  files you do not own are noted, not fixed).
- Never re-run `bun install` (one install is done). Commit nothing.
- End with a status block in `docs/gpuix-shell/music/BUILD-LOG.md` under `## M<n> <title>`:
  done / not done / untested, test counts, anything you could not verify.

| Packet | Job file | Owns | P0 deliverables | Tests (bun) |
|---|---|---|---|---|
| **M1 Subsonic client** | 007-build_subsonic | `src/music/subsonic/{auth,client,redact,schema,record-fixtures}.ts`, `src/music/subsonic/fixtures/**`, tests (frozen in the dir: `types.ts`, `api.ts`, `map.ts`) | `createSubsonicClient` covering every `SubsonicApi` method; recorded scrubbed fixtures (§8.2) | `client.test.ts` (fake fetch: POST form body, fresh salt, md5 token, error kinds, Content-Type check, LRU, retry only on reads), `redact.test.ts`, `schema.test.ts` (every fixture validates), `map.test.ts` (fixtures → refs), `secrets.test.ts` (canary password never in errors/logs), `client.live.test.ts` (skipped unless `NAVIDROME_LIVE=1`: ping, search "daft punk", album of the first hit, one cover at 96) |
| **M2 Library and search** | 008-build_library | `src/music/library/**` | cache, index, rank, search stream, pages, art cache, recents | `rank.test.ts` (the §5.2 table incl. `davis kind`, diacritics, `&`/and, typo, Top-result prior), `index.test.ts` (30k synthetic names, < 8 ms report), `search.test.ts` (partial → final order, abort mid-debounce yields nothing more, 1-char local only, LRU, server failure → local final `failed`), `cache.test.ts` (needsRebuild: stamp, 24 h, force; paging until a short page), `pages.test.ts` (fixtures: release-type split, popular fallback), `art-cache.test.ts` (fake api: dedup, abort, atomic file, never a URL on disk), `recents.test.ts` |
| **M3 Player** | 009-build_player_ | `src/music/player/**` | mpv spawn + IPC, two-entry window, queue, state projection, persistence, reporting, MPRIS, server port; `smoke-play.ts` | `queue.test.ts` (R04 §6 table, positions semantics, rev guards, shuffle/unshuffle, undo), `mpv-ipc.test.ts` (fake `net.Server` speaking mpv JSON: ids, timeouts, observe, events), `player.test.ts` (real mpv `--ao=null` + fake server with `av://lavfi:sine` URLs: gapless advance, repeat-one = two plays, previous 3 s rule, kill -9 respawn, crash-resume), `scrobble.test.ts` (qualify rule, seeks don't count, one submission per play, disabled flag), `state-files.test.ts` (atomic, no URL), `mpris.test.ts` (under `dbus-run-session`, skipped when absent), `secrets.test.ts` (argv spy: no URL in spawn args) |
| **M4 Provider, CLI, ctl.sock** | 010-build_launcher | `src/music/provider/**`, `src/music/ipc/**`, `src/music/cli.ts`, tests | `serveBackend`/`connectBackend`, `runMusicCli` with every P0 verb, `createMusicProvider` | `cli.test.ts` (parse table, exit codes against a fake backend over a temp socket), `ipc.test.ts` (round trip of every query and command, search partial/final streaming, cancel, watch events, stale socket unlink by exact path, mode 600), `rows.test.ts` (fixtures → sections, caps, accessories, no URL anywhere in rows), `provider.test.ts` (root limit, commands matching, fallback row, actions order: [0] Enter, [1] Ctrl+Enter) |
| **M5 GPUIX views** | 011-build_GPUIX | `src/music/ui/**` | `MusicRoot` + every P0 view and component, keymap, reducer, theme, hooks | `state.test.ts` (stack, query, scope cycle, echo expiry, `pinCursor` cases), `keymap.test.ts` (every §5.7/R05 §4 key resolves per view; no collisions per view; Space only with empty input), `theme.test.ts` (three themes complete; loader fallback). `@gpuix/react/testing`'s native test renderer is **not** in the published binary (checked: `hasTestGpuixRenderer() === false`), so render tests are skipped and the GUI smoke covers rendering |
| **M6 Service, demo, fakes, GUI smoke** | 012-build_demo | `src/music/service/**`, `src/music/testing/**`, `src/music/demo/**`, `tests/gpuix-shell/music/**` | `createMusicService`, play resolution, echoes; fake catalogue/api/backend; demo window + `run.sh` + `on-client.sh`; the GUI smoke run once | `service.test.ts` (fake api + `--ao=null` mpv: play from search continues with album, artist fallback, query play, like optimistic + revert, undo restores), `echo.test.ts`, `play.test.ts`, `catalog.test.ts` (determinism, the `tal` and `davis kind` cases), demo `args.test.ts`; GUI smoke (§8.4) under runtime-test, screenshots to `docs/gpuix-shell/music/evidence/gui/` |
| **M7 Integration and docs** | 013-build_docs | `src/music/integration/**`, `src/music/index.ts`, `docs/gpuix-shell/music/DEMO.md`, `docs/gpuix-shell/music/ABOVE-RAYCAST.md` | chip model + component, OSD sender, Sway fragment, desktop file, user unit proposal, public barrel, the two docs | `chip.test.ts` (visibility, glyphs, progress clamp, aria text), `osd.test.ts` (payload shapes; sendOsd to a temp socket; absent socket = false, no fallback by default) |

The completer (job 014) owns integration across packets: typecheck, all tests, the live smoke, the
GUI smoke rerun, `docs/gpuix-shell/music/STATUS.md`, and this file's status line.

---

## 8. Test plan

### 8.1 Unit tests (`bun test`, no network, no compositor, no live runtime dir)

All listed per packet in §7. Shared rules: temp `XDG_*` dirs; fixtures from §8.2 or the synthetic
catalogue; no test calls a write endpoint (writes are asserted against a fake `fetch` or the fake
api's `writes` list); mpv tests use `--ao=null` and lavfi URLs (R04 M11) so they need no audio
device and no server. Run everything: `cd pkgs/gpuix-shell && bun test src/music`.

### 8.2 Recorded fixtures (M1, `src/music/subsonic/fixtures/`)

Recorded once from `http://music.internal` with `NAVIDROME_LIVE=1 bun
src/music/subsonic/record-fixtures.ts`, read-only, scrubbed (§4.6), ≤ 200 KB each:

`ping`, `getOpenSubsonicExtensions`, `getScanStatus`, `search3-daft-punk` (6/12/24), `search3-love-songs`
(songs 60), `search3-empty-section` (a query with no artists), `getAlbum` (first album of the Daft Punk
search), `getAlbum-multidisc` (if found among the first 200 newest; else omitted and noted),
`getArtist` (Daft Punk), `getArtistInfo2`, `getTopSongs-daft-punk`, `getTopSongs-empty`
(Parcels), `getAlbumList2-newest-20`, `getAlbumList2-recent`, `getRandomSongs-10`, `getPlaylists`
(first 50 entries, `_note` says truncated), `getPlaylist` (the smallest non-empty), `getGenres` (top 50),
`getStarred2` (empty today), `getLyricsBySongId-empty`, `getArtists` (3 index letters, `_note`
truncated), `error-70` (`getSong id=nope`). The recorder never calls a write endpoint and refuses to
start without `NAVIDROME_LIVE=1`. Other packets read fixtures; only M1 writes them.

### 8.3 Live smoke: search and 3 seconds of audio (M3 writes it, the completer runs it)

```
cd pkgs/gpuix-shell
NAVIDROME_LIVE=1 NAVIDROME_SCROBBLE=0 NAVIDROME_SAVE_QUEUE=0 GPUIX_MUSIC_AO=null \
  XDG_STATE_HOME=$(mktemp -d) XDG_CACHE_HOME=$(mktemp -d) \
  /home/tom/today/2026-10-14-convergence-soak/build/bun/bin/bun src/music/player/smoke-play.ts "daft punk"
```

It creates the real client, runs `search3`, takes the first song, starts a `Player` (MPRIS off, mpv
`/etc/profiles/per-user/tom/bin/mpv` or `GPUIX_SHELL_MPV`), plays it, waits 3 s, reads mpv `time-pos`
directly and the projected `PlayerState`, stops, disposes, and prints one JSON line
`{"ok":true,"song":"<id>","firstAudioMs":…,"timePosStart":…,"timePosEnd":…,"advancedS":…}`. Pass =
`advancedS ≥ 2.0` and `status` was `playing`. It prints no URL (the test greps its own output for
`t=`/`s=`). `--audible` drops `GPUIX_MUSIC_AO=null` (on the strix there is no listener in the closet,
so the default stays null). No reportPlayback, no scrobble, no queue save. Streaming itself is
side-effect free (R03 §0.4). The client half is `NAVIDROME_LIVE=1 bun test
src/music/subsonic/client.live.test.ts`.

### 8.4 GUI smoke under runtime-test (M6 writes and runs it once; the completer reruns it)

```
cd /home/tom/.wt/dotfiles/gpuix-shell
home/dot_local/bin/runtime-test --render-node /dev/dri/renderD128 -- \
  python3 tests/gpuix-shell/music/smoke_music_demo.py
```

`smoke_music_demo.py` follows `docs/gpuix-shell/evidence/rail-probe/smoke.py` (private headless Sway
1.12 from the store path in BRIEF §5, `WLR_RENDERER=gles2`, `WLR_RENDER_DRM_DEVICE=/dev/dri/renderD128`,
`LD_LIBRARY_PATH` from the store globs, D-Bus addresses pointed at `/nonexistent` so MPRIS is skipped,
`assert not (XDG_RUNTIME_DIR/bus).exists()` to prove isolation), then:

1. Temp `XDG_STATE_HOME`/`XDG_CACHE_HOME`; env `NAVIDROME_FAKE=1 GPUIX_MUSIC_AO=null
   GPUIX_MUSIC_TREE_DUMP=<out>/tree.json`; start `bun src/music/demo/main.tsx --fake`.
2. Wait (≤ 20 s) for a view with `app_id == "gpuix-shell-music"` in `swaymsg -t get_tree`, focused.
   `grim` → `01-home.png`.
3. Type `tal` with `wtype tal` (the seat's virtual keyboard; if wtype cannot bind
   `zwp_virtual_keyboard_manager_v1`, fall back to `GPUIX_AUTOMATION=stdio` + `@gpuix/native/automation`
   `launch()`/`getByTestId("music.input").fill("tal")` and say which path ran). Wait 600 ms, `kill
   -USR1`, read `tree.json`: assert `music.input` has value `tal` and at least one `music.row.*` and
   `music.top` exist. `grim` → `02-search-tal.png`.
4. `wtype -k Return`; poll `bun src/music/cli.ts status --json` (the sandbox's own `ctl.sock`) until
   `status == "playing"` (≤ 5 s) and the track id equals the top result's id. `grim` →
   `03-playing.png` (strip visible).
5. `wtype -M ctrl -k k -m ctrl` → `04-actions.png`; `wtype -k Escape`.
6. `wtype -M ctrl -k Right -m ctrl` → assert the track changed within 2 s (records the R05 §4 open
   question: does `Ctrl+→` reach `onKeyDown` through the `<input>`? Not fatal; logged).
7. `bun src/music/cli.ts next` → `seq` advanced, exit 0. `bun src/music/cli.ts volume 150` → exit 2.
8. Click the strip: `swaymsg seat seat0 cursor set <x> <y>` at the strip centre, `cursor press
   button1`, `cursor release button1` → `05-now-playing.png`; tree has `music.nowplaying`.
9. Type `davis kind` into Search (Esc back first) → tree has `music.row.album.<Kind of Blue Skies id>`
   → `06-cross-field.png`.
10. Terminate the app (SIGTERM, ≤ 5 s), then Sway. Pixel check with PIL: every screenshot has more
    than 2 distinct colours in the window rect (not blank). Copy PNGs and `tree.json` to
    `docs/gpuix-shell/music/evidence/gui/`; write `result.json` with each step's pass/fail.

Pass = steps 2–5, 7, 8 pass. Step 6 and the wtype-vs-automation path are recorded either way.
An optional `--live` flag runs the same steps against the real Navidrome (read-only:
`NAVIDROME_SCROBBLE=0 NAVIDROME_SAVE_QUEUE=0`, never like), typing `daft` instead of `tal`; it
is not part of the pass criteria.

### 8.5 What counts as verified

A claim is verified only when a command in BUILD-LOG or STATUS shows it ran and passed. The
following are known **unverified** before the build and must stay labelled so until shown: `<img>`
with a local path on a GPUIX surface; `Ctrl+←/→` and `Alt+…` delivery through `<input>`; wtype on
headless Sway; `audio-device-list` against the live PipeWire; every write endpoint's live behaviour
(star, scrobble, reportPlayback, savePlayQueueByIndex, updatePlaylist); MPRIS on the Zenbook's real
session bus; Zenbook latency to `music.internal`.

---

## 9. Demo runbook for Tom (the morning)

Tom's shells are herdr panes on the strix; the screen and speakers are the Zenbook's. The demo must
draw on the Zenbook's Sway and play through its PipeWire. The Zenbook has no checkout and no
`navidrome-credentials` (strixOnly). Hence one script, run **from any strix shell**:

```
~/.wt/dotfiles/gpuix-shell/pkgs/gpuix-shell/src/music/demo/on-client.sh
```

What it does (M6 implements it; M7's DEMO.md explains it):

1. `rsync -a --delete` `pkgs/gpuix-shell/{package.json,tsconfig.json,src,node_modules}` to
   `client:~/.cache/gpuix-shell-demo/` (a build directory, not a clone of the repo).
2. Makes bun available there: `nix copy --to ssh-ng://client` of the exact
   `/nix/store/…-bun-1.4.2` the strix uses; if the client refuses the path, `run.sh` falls back to
   `nix shell nixpkgs#bun`.
3. Credentials: if `client:/run/agenix/navidrome-credentials` exists (after Tom's rekey), use it.
   Otherwise stream the strix file over SSH **stdin** into
   `client:$XDG_RUNTIME_DIR/gpuix-shell/navidrome-credentials` (umask 077, tmpfs: RAM only, gone at
   logout or reboot) and point `NAVIDROME_CREDENTIALS_FILE` at it. Nothing is printed; it says one
   line, "copying the Navidrome credential to the client's runtime dir for this session". `--fake`
   skips this step and runs the synthetic catalogue.
4. Launches inside Tom's running Sway on the client:
   `swaymsg exec 'env NAVIDROME_CREDENTIALS_FILE=… ~/.cache/gpuix-shell-demo/src/music/demo/run.sh'`
   (found via `/run/user/<uid>/sway-ipc.*.sock`), so the window inherits Sway's Wayland, PipeWire and
   D-Bus session: MPRIS registers and the F3/F4/F5 and XF86 media keys reach it at once.
   `--layer` opens the launcher-overlay variant instead of a window.

Flags: `--fake` (synthetic catalogue, no credential, no network), `--layer` (launcher overlay
instead of a window), `--no-scrobble` (`NAVIDROME_SCROBBLE=0`), `cli <verb…>` (runs
`src/music/cli.ts <verb…>` on the client with the same bun, e.g. `on-client.sh cli status`),
`stop` (SIGTERM to the client's demo process; clean stop, credential file removed).

Then, on the Zenbook: the **Music** window opens on the current workspace with Home. Try: type
`daft` → Enter; `Ctrl+K`; `Alt+Q` on another song, then `Ctrl+Z`; `Ctrl+Enter` on an album; `Esc`;
`Ctrl+→`; click the strip for Now Playing; press F4 (next) from any window; from a strix shell,
`on-client.sh cli status` and `on-client.sh cli next`.

Fallbacks: `on-client.sh --fake` (no credential, no network); and on the strix, the GUI smoke
screenshots in `docs/gpuix-shell/music/evidence/gui/` show it without any client.

The durable route (Tom's call, Q1 in §12): add the client's host key to
`navidrome-credentials.age` recipients (`editors ++ strixOnly ++ clientOnly`), widen the `mkIf` in
`modules/secrets.nix`, rekey with an editor key. Then step 3 becomes a no-op and the HM unit
`gpuix-shell-music.service` can run on the Zenbook.

---

## 10. Hooks into the rest of the shell (for waves 2–4)

- **Top-level CLI**: `src/main.ts` routes `gpuix-shell music …` to `runMusicCli(argv)`.
- **Launcher**: register `createMusicProvider({ backend: () => connectBackend({path:
  musicPaths().ctlSock}), renderView: (route, props) => <MusicRoot backend embedded … /> })`. Routes
  `music/*` open the music views; `gpuix-shell launcher --view music/<path>` is the deep link.
- **Rail**: mount `<NowPlayingChip backend={socketBackend} collapsed={…} onOpen={() => open
  "music/now-playing"} />` in the rail footer above the clock (R05 §7.1). The chip hides itself when
  the daemon is down or idle.
- **OSD**: the notifications/OSD process accepts `{"type":"osd","slot":"music",…}` lines on
  `shell.sock` (R05 §7.2).
- **Nix** (`pkgs/gpuix-shell/default.nix`, wave 2): wrap with `--set GPUIX_SHELL_MPV
  ${pkgs.mpv}/bin/mpv`; `nativeCheckInputs = [ mpv dbus ]` for `player.test.ts` and `mpris.test.ts`;
  `dbus-next` is a runtime dependency.
- **HM** (`home/gpuix-shell.nix`): the `gpuix-shell-music.service` proposal from
  `src/music/integration/`; the desktop file; never enabled together with another MPRIS music
  daemon. Not activated tonight.
- **Sway**: the fragment's `$mod+m` / `$mod+Shift+m` (proposed; `$mod+m` is free since 2026-10-12)
  and the `media` one-liner.
- **Theme**: when `home/themes/default.nix` gains the `gpuix-shell.json` fragment, `loadShellTheme()`
  reads it; the symlink watcher belongs to the shell's theme loader, which re-renders `MusicRoot`
  with the new theme.

---

## 11. Overrides of the packet prompts (follow this file)

| Packet prompt says | This spec says | Why |
|---|---|---|
| M1: "zod schemas for responses" (as the types) | TS types = R03 §8 (frozen `types.ts`); zod loose schemas in `schema.ts` for fixture tests and opt-in validation | measured shapes already typechecked; zod on the hot path costs and breaks on Navidrome's omitted keys if strict |
| M1: `getPlayQueue/savePlayQueue`, `coverArtUrl(id,size)` | `playQueue()` = `getPlayQueueByIndex`, `savePlayQueueByIndex`; `coverArt()` returns bytes, no URL method | duplicates are legal (R04 §6); a cover URL is a token |
| M2: `library.json` in `$XDG_STATE_HOME` | `$XDG_CACHE_HOME/gpuix-shell/music/library.json` | it is a rebuildable cache (R05 §8) |
| M2: songs via `search3` inside `index.ts` | `index.ts` is local-only; `search.ts` merges `search3`; `pages.ts` + `art-cache.ts` also M2 | one ranking path; balances packet sizes |
| M3: `--input-ipc-server=$XDG_RUNTIME_DIR/gpuix-shell/mpv.sock --really-quiet` | fd://3 socketpair + R04 §4 argv; debug socket only with `GPUIX_SHELL_MPV_DEBUG_SOCKET=1` | measured stale sockets, orphan audio, token leaks via stdout and ytdl_hook (R04 M2–M4, M9) |
| M3: MPRIS `org.mpris.MediaPlayer2.gpuixshell` | `org.mpris.MediaPlayer2.gpuix_music` | one name, already in R05's `media` one-liner (ASSUMPTIONS) |
| M3: "mpv IPC against a fake socket server" | yes, via the transport-agnostic `MpvIpc(Duplex)`; plus real-mpv tests with `--ao=null` and lavfi | both are cheap and the real one catches event-order bugs |
| M3: scrobble at 50 % or 4 min | as R04 §9: > 30 s tracks, min(50 %, 240 s) of *listened* time, one counting path | measured design; deterministic whatever `ignoreScrobble=false` does |
| M4: socket `$XDG_RUNTIME_DIR/gpuix-shell/music.sock` | `$XDG_RUNTIME_DIR/gpuix-shell/music/ctl.sock` | R05 §2 (logged) |
| M4: CLI "or starts it" | does not start audio implicitly; `--start` / `GPUIX_MUSIC_AUTOSTART=1` | a key bind should not surprise-start a player; exit 3 tells how |
| M4: rows with `icon(art url)` | `Row.art.load()` → local path; `icon` is a Lucide name only | the token never reaches GPUIX's inspectable tree (R05 §3.3) |
| M4: verbs `vol`, `star`, `now` | kept as aliases of `volume`, `like`, `status` | R05 §6 names stay canonical |
| M5: global keys `s` star, `?` help | `Ctrl+L`/`Alt+L` like, `Ctrl+K` actions (the help); no single-letter shortcuts while the input has focus | typing `s` into Search must type `s` |
| M5: views only take a `MusicBackend` | yes; plus `theme`, `size`, `initialRoute`, `embedded`, `layer`, `onClose`, `effects` | needed to mount in the launcher and to test effects |
| M6: "FakeBackend … with 50 synthetic songs" as the demo's fake mode | demo fake mode = the real service over `createFakeSubsonic()` (lavfi tones, real mpv `--ao=null` in tests); `createFakeBackend()` exists for unit tests | the GUI smoke then exercises the real service, queue and player |
| M6: owns `demo/*` and `tests/gpuix-shell/music/*` | also `service/*` and `testing/*` | the demo is where the real backend is wired |
| M7: OSD via `notify-send -a music -r <id>` with art in `$XDG_RUNTIME_DIR/gpuix-shell/art/` | `shell.sock` OSD line first (R05 §7.2); `notify-send` only with `GPUIX_MUSIC_OSD=notify-send`; art path from the shared art cache | R05: no fallback to mako; one art cache |
| M7: `$mod+Shift+m` toggles the music launcher | `$mod+m` music, `$mod+Shift+m` now playing (R05 §6) | both proposals, not activated |
| R05 §13 file names (`music/daemon/*`, `music/views/*`, `music/lexicon.ts`) | the orchestrator's layout: `subsonic/ library/ player/ provider/ ui/ cli.ts demo/` (+ `service/ ipc/ testing/ integration/`) | the build jobs were generated with these paths |
| R05 testId `"music." + row.id` (→ `music.music:song:…`) | `music.row.<kind>.<id>` | readable selectors |

---

## 12. Assumptions logged (ASSUMPTIONS.md, `music:`) and open questions for Tom

Logged by this pass: the contract files and `package.json` were created by the design pass to stop
seven builders racing; the module layout in §11; the in-process demo service that also serves
`ctl.sock`; the library cache in `XDG_CACHE_HOME`; queue command positions are upcoming positions;
`on-client.sh` copies the credential into the client's tmpfs for the session when Tom runs it; testId
scheme; Claude-theme token values derived from `home/themes/*.nix` pending DESIGN.md; the CLI never
autostarts audio; radio is P1; MPRIS is P0 code but the demo never depends on it.

Open for Tom (defaults taken; nothing blocks):

- **Q1** Rekey `navidrome-credentials.age` for the client (default: the per-session tmpfs handoff in
  `on-client.sh`; refuse it by running `--fake` or by deleting step 3).
- **Q2** `$mod+m` / `$mod+Shift+m` binds (proposed only).
- **Q3** LRCLIB lyrics fallback (default off).
- **Q4** Playlist editing for the account (`playlistRole:false`; Add to playlist may answer Failed).
- **Q5** Scrobbling from the demo is on (it keeps Jump back in / Most played alive). Default on;
  `on-client.sh --no-scrobble` turns it off.

---

## 13. What this pass did, and did not do

**Done (and checked):** read BRIEF and the five research notes in full; read the seven builder job
prompts and the completer's so the packets match them; inspected `@gpuix/native`/`@gpuix/react` 0.11.0
(key events, automation, `createRenderer`/`enableAutomation`, `getAutomationTree`, test renderer
absent from the published binary); created `pkgs/gpuix-shell/{package.json,tsconfig.json}` and ran
`bun install` once (140 packages; `node-gyp` postinstall of an optional dbus-next dependency was
blocked by bun and is not needed); wrote the frozen files of §6.1; `tsc --strict --noEmit` exit 0;
`bun test src/music/format.test.ts` 5 pass; every TypeScript block of §6.2–6.10 compiled as a
`.d.ts` in a scratch copy of the tree against the frozen files: 0 errors (a planted error was
reported, so the check ran).

**Not done:** no client, library, player, UI, demo or smoke code beyond the frozen contracts; no
Navidrome call, mpv run or compositor test in this pass (the research notes' measurements stand);
the GPUIX `<img>` local-path rendering, key delivery through `<input>`, and wtype on headless Sway
remain unverified until the GUI smoke runs.
