# 05 — Music in the launcher: the UX spec (views, keys, chip, provider contract)

Written 2026-10-21 overnight by the music design agent (Opus seat) for Tom's gpuix-shell build. This
is the design the music builders code against. It is grounded in four sources, cited by short name:

| Short | What | Where |
|---|---|---|
| R01 | Raycast spotify-player / spotify-controls model, Linux keymap §10, priorities §11 | `docs/gpuix-shell/music/01-raycast-spotify-model.md` |
| R02 | Raycast Navidrome extension + cliamp, live numbers §4, ranked additions §5 | `docs/gpuix-shell/music/02-navidrome-ext-and-cliamp.md` |
| KIT | Design kit digest: surfaces, tokens, U-01..U-19 | `docs/gpuix-shell/wave1/11-design-kit-shells-digest.md` |
| GPX | `@gpuix/native` + `@gpuix/react` 0.11.0 type definitions and CHANGELOG | probe011 `node_modules/@gpuix/{native/index.d.ts,native/dist/host.d.ts,react/dist/**}`, `~/Downloads/gpuix/CHANGELOG.md` |

Labels: **MEASURED** = I ran it tonight (read-only Subsonic calls, credentials read at runtime and
never printed); **GPX** = a fact read from the GPUIX type definitions or CHANGELOG; **DECIDED** = a
design call made here and logged in `ASSUMPTIONS.md` with the `music:` prefix. Nothing here was
rendered: no compositor test was part of this task. Every wireframe is unverified until the smoke in
§12 runs under `runtime-test --render-node`.

---

## 0. What Tom gets, and what "Spotify + Raycast level" means here

Press `Mod+M`. The launcher opens on **Music**: what is playing, what you played last, what is new.
Type `bon`. Before the server answers, the local index already shows Bon Iver as the **Top result**.
About 60 ms later the server's songs merge in below without moving the row under the cursor. `Enter`
plays Holocene in the context of its album. The mini-player strip at the bottom starts moving.
`Ctrl+Enter` opens the album, `Alt+Q` queues a song, `Ctrl+Shift+R` starts a radio from it,
`Ctrl+K` shows every action with its keys, and `Esc` steps back. From any window, `F3`/`F4`/`F5`
and the XF86 media keys work through MPRIS. `gpuix-shell music next` works from a script. The left
rail shows a now-playing chip with 24 px cover art.

The bar, made testable (each line is an acceptance check in §12):

1. **Zero-RTT first paint.** The first rows for any query come from the local index, which holds
   11,118 artists, 16,208 albums and 1,235 playlists. They paint before any network round trip.
2. **Typo and cross-field tolerance the server lacks.** MEASURED: `search3 "davis kind"` returns 0
   hits. The local index matches tokens across album name and album artist, so "Kind of Blue" by
   Miles Davis is found when it is in the library.
3. **Enter plays, everywhere, in context.** A song inside an album, playlist or radio plays that
   list from that song. A song from search plays and then continues with its album.
4. **Control without leaving the keyboard or opening a view.** Transport keys work in every music
   view. No-view commands are in the root launcher. The CLI verbs and MPRIS run the same command ids
   (U-10).
5. **Live state everywhere.** The playing row is marked in every list. The mini-player strip, the
   Now Playing view and the rail chip follow the daemon's state events. Nothing polls.
6. **Every action is echoed, and the reversible ones offer Undo.** This covers queue edits, likes
   and replacing the queue (U-09).
7. **Honest states.** Indexing, partial, offline, unauthorized, empty and failed each get their own
   screen, with what to do next (U-04, U-17).

Beyond Raycast's Navidrome extension, which cannot play anything (R02 §1, R01 §11 "Baseline"), and
beyond spotify-player, which has no queue editing, no live progress and no local fuzzy matching.

---

## 1. Ground truth measured tonight, and what each fact forces

MEASURED 2026-10-21 from the strix over the closet LAN, against `http://music.internal`, read-only.

| Fact | Value | Forces |
|---|---|---|
| Server | Navidrome 0.63.2, Subsonic 1.16.1, OpenSubsonic, extensions `songLyrics` 1–2, `indexBasedQueue`, `playbackReport`, `transcoding`, `transcodeOffset`, `formPost`; **no `apiKeyAuthentication`** | token+salt auth: every stream/cover URL is a secret (§11) |
| Library | **38,524 songs**, **16,208 albums**, **11,118 artists**, 1,235 playlists (one owner, median 7 songs), 3,966 genre tags (136 with ≥ 20 songs) | everything is virtualised; genres are filtered by default; playlists are searched locally |
| `search3` latency | 11–20 ms typical; 78 ms for `the`; empty query pages 500 songs in 90 ms | server debounce 60 ms (not Raycast's ~120 ms) |
| `search3` semantics | word-prefix AND only: `radioh` ✓, `bon iv` ✓, `beyonce` = `beyoncé` ✓, **`davis kind` ✗ (0)**, `kind of blue` ✗ (0) | a local fuzzy index (artists + albums with their artist + playlists) merged with server hits (§8) |
| Index build | `getArtists` 0.89 s; `getAlbumList2 alphabeticalByName` × 33 pages = 6.8 s | build once, cache on disk, revalidate on `getScanStatus` change; never block first paint |
| Cover art | `getCoverArt` 1.17 s cold for one 64 px JPEG | disk cache by art id, placeholders of the final size, prefetch the visible range |
| Stream | `stream` → `audio/mp4` m4a 257 kbps, `Accept-Ranges: bytes`, 206 on range | mpv streams directly; seeking works without transcoding |
| Radio sources | `getSimilarSongs2(artist)` 1.1–3.8 s, 3 songs for Bon Iver; `getSimilarSongs(song)` 0 songs; `getTopSongs` 1 song; R02: similar songs for only 4 of 8 artists | radio is a layered mix with labelled sources, a loading state and a genre/era fallback (§5.10) |
| Artist info | `getArtistInfo2`: 4 similar artists, biography 1,593 chars, image URLs | Artist view has a bio (markdown) and similar artists |
| Lyrics | `getLyricsBySongId` answers but returned no lines for the sampled song (R02: 0 of 8) | the lyrics pane must look good empty; synced highlighting is unverified on real data |
| Starred | 0 starred items | Liked views open on an empty state that teaches `Ctrl+L` |
| Song fields | no `playCount`/`starred` key when zero/unset (omitted, not `0`/`false`) | treat absent as 0 / not liked; show a play count only when > 0 |
| Account | `playlistRole: false`, `jukeboxRole: false`, `adminRole: true`, `streamRole: true` | playlist writes may be refused (error 50): show the refusal; playback is local mpv |
| Credential file | `secrets/navidrome-credentials.age` recipients = `editors ++ strixOnly` (`secrets.nix:112`) | **the Zenbook has no credential today**; see §14 Q1 |

---

## 2. Process model

```
                                  gpuix-shell music <verb>  (Sway, scripts) ──┐
                                  F3/F4/F5, XF86Audio* → media → playerctl ──┤ MPRIS
                                                                              ▼
 ┌─────────────────────────────┐   JSON lines, mode 600      ┌────────────────────────────────────────────────┐
 │ launcher process            │◄─── ctl.sock ────────────►  │ gpuix-shell music serve   (no window)          │
 │  MusicProvider (no secret)  │                             │ Subsonic client: the ONLY credential reader    │
 │  views/*.tsx                │                             │ Lexicon (local fuzzy index, disk cached)       │
 └─────────────────────────────┘                             │ Art cache ($XDG_CACHE_HOME/…/music/art)        │
 ┌─────────────────────────────┐   watch → state events      │ Queue + player model (rev-guarded)             │
 │ rail process: NowPlaying    │◄─── ctl.sock ────────────►  │ mpv child ── mpv.sock (JSON IPC; URLs here)    │
 │ chip (24 px art)            │                             │ Scrobbler, play-queue sync, MPRIS (dbus-next)  │
 └─────────────────────────────┘                             │ history.jsonl, searches.json (state dir)       │
 ┌─────────────────────────────┐   {"type":"osd",…}          └────────────────────────────────────────────────┘
 │ notifications/OSD process   │◄─── shell.sock ────────────
 └─────────────────────────────┘
```

DECIDED:

- **One long-lived daemon, `gpuix-shell music serve`.** It is a headless Node process with no
  GPUIX renderer. It is the only process that reads `NAVIDROME_CREDENTIALS_FILE`. It owns mpv, the
  queue, the local index and the art cache. The launcher is a short-lived overlay, so it cannot own
  playback. One GPUIX renderer is one window (KIT §4.9).
- **Sockets:** `$XDG_RUNTIME_DIR/gpuix-shell/music/ctl.sock` (the daemon's API) and
  `$XDG_RUNTIME_DIR/gpuix-shell/music/mpv.sock` (mpv's IPC, which only the daemon touches). The
  directory is mode 700 and the sockets 600. The engine probe already uses that mpv path.
- **The launcher provider is a thin client.** It never reads the credential and never sees a
  tokenised URL. Cover art arrives as a local file path. This keeps the token out of GPUIX's
  retained tree, which `getAutomationTree()` can serialize.
- **systemd:** `gpuix-shell-music.service`, bound to `sway-physical-session.target` like the other
  surfaces (BRIEF §3.2). It is declared by the HM module and is not activated tonight. No timer is
  declared: the daemon's own in-process intervals are not systemd timers.
- **If the daemon is not running**, every music view shows one state, "Music is not running", with
  the fix `systemctl --user start gpuix-shell-music`. CLI verbs exit 3 with the same text.

---

## 3. Visual grammar

### 3.1 The launcher frame with music inside (700 × 580, KIT §3.1)

Layer `overlay`, anchor `top`, margin `[round(0.12 × output height), 0, 0, 0]` (108 at 900 high),
exclusive zone −1, keyboard `exclusive`, namespace `gpuix-shell-launcher`. Outer radius 16, ground
`surface.overlay`, a 1 px `line.strong` edge, no shadow and no scrim in any theme (KIT §3.1 rule 3).
The overlay snaps open on its first frame with no enter motion (rule 8).

```
 y=0   ┌ header 56 ─ back ‹ · breadcrumb · input 15/20 · scope chips 20 high ───────────┐
 y=56  ├ hairline 1 (line.hairline) ─────────────────────────────────────────────────────┤
 y=57  │ body: one <virtual-list> of flattened sections                                 │
       │   height 446 with the mini-player strip, 487 without                           │
 y=503 ├ hairline 1 ─────────────────────────────────────────────────────────────────────┤
 y=504 │ mini-player strip 40 (only when a track is loaded and the view is not Now playing)│
 y=544 ├ hairline 1 ─────────────────────────────────────────────────────────────────────┤
 y=545 │ footer 35: echo / context word (left) · primary action ↵ · Actions Ctrl K        │
 y=580 └─────────────────────────────────────────────────────────────────────────────────┘
```

- **Header (56).** Padding 0 16. When the view depth is above 0, a back affordance `‹` (16, `ink.muted`,
  clickable, same as `Esc`) comes first, then the breadcrumb word in 13/18 `ink.muted` ("Music",
  "Album", "Queue"), then `<input autoFocus>` at 15/20 `ink.default` with placeholder `ink.subtle`.
  Scope chips sit on the right: 20 high, radius 6, 12/16 text, gap 4. The active chip has
  `state.selected` fill and `ink.default` text; the others have no fill and `ink.muted` text.
  A 2 px indeterminate **loading bar** draws on the header's bottom hairline while a request is in
  flight for more than 150 ms. It is clipped and moves by `left` only (KIT §4.5).
- **Mini-player strip (40),** R01 §12 and R02 §5.3. It is not drawn when nothing is loaded. It holds,
  in order:
  - the cover at 24, radius 4;
  - the title at 13/18 with ` · Artist` in `ink.muted`, middle-truncated to its budget;
  - a 120 × 4 progress bar;
  - `1:12 / 3:40` in mono figures 12/18;
  - three 28 × 28 icon buttons: previous, play/pause, next.
  Clicking the strip outside a button pushes Now Playing.
- **Footer (35).** Left: the **echo** for 6 s after an action ("Added Holocene to the queue · Undo
  Ctrl+Z"). Otherwise the section context ("Music · 38,524 songs") in 12/18 `ink.muted`. Right: the
  primary action label and `↵`, a 1 px vertical hairline, then `Actions` with `Ctrl K`. Keycaps are
  mono 12, `ink.subtle`, in a 1 px `line.default` box with radius 4.

### 3.2 Row types (one row grammar, U-13: leading cell, title, trailing state, trailing action)

All rows are 676 wide inside 12 px body padding, radius 8, horizontal padding 8. Hover equals the
keyboard cursor and uses the `state.selected` fill with the title at weight 500. **Current**
(playing) uses a 2 px accent leading bar and the title in `accent.default`. Selected, current and
focused coexist (U-13, KIT §4.6).

| Row | Height | Leading | Title / subtitle | Trailing accessories (≤ 3, mono figures where numeric) |
|---|---|---|---|---|
| Song (in search, library, radio) | 44 (`size.row.launcher`) | cover 40, radius 4 (2 px vertical inset) | title 13/18 · subtitle 12/16 `ink.muted` "Artist · Album" | `12 plays` (only > 0) · `♥` + word "Liked" for AT · `5:36` |
| Track (in album, playlist, queue) | 40 (launcher compact) | track number, mono 12, right-aligned in 24 px; for current, the 2 px bar plus a `▶`/`‖` glyph instead | title 13/18 and, only when they differ from the album artist, ` · Artists` in `ink.muted` on the same line | plays · `♥` · `4:22` |
| Queue track | 40 | cover 24 + index (mono) | "Title · Artist" on one line | `♥` · `4:22` |
| Album | 44 | cover 40, radius 4 | name · "Artist · 2011" | `10 songs` · `48 min` |
| Artist | 44 | image 40, **circle** (avatars are the only `full` radius, KIT §4.4) | name · "Artist" | `4 albums` |
| Playlist | 44 | cover 40, radius 4 | name · "42 songs · 2 h 51 min" | `changed 3 d ago` |
| Genre / decade / link | 44 | Lucide icon 18 in a 40 sunken tile | name · count words | `›` when it navigates |
| Top result | 72 | cover 56 (circle for artists) | name 16/20 · type word + facts ("Artist · 4 albums") | a `Play` text button, 28 high, radius 8, `line.default` edge |
| Section header | 28 | — | 12/16 `ink.muted` weight 500, sentence case | count in mono, then "Show all" (`›`) when there are more |
| Grid card | 174 (166 + 8 gap) per row of 5 | cover 112 at 6 px inset in a 124 cell (circle for artists) | title 13/18, one line · meta 12/16 "2011 · Album" | — |

Hit areas are at least 24 × 24 (U-07). Every row carries `role="option"`, `aria-selected`,
`aria-label` (title, subtitle) and `aria-description` (state words: "Playing", "Liked", "12 plays").
It also carries `testId = "music." + row.id` (U-10, GPX `testId`).

**Match wash.** The title and subtitle `<text>` of each row declare `highlight` with one spec per
query token (`color = accent.muted`, `radius 2`). The highlight is declared on the row, not the
list, so virtualisation needs no `matchIndexOffset` (GPX CHANGELOG "highlight").

### 3.3 Cover art

- Size buckets: **96** (rows 40, chip 24, strip 24, footer), **256** (grid 112, detail headers 160,
  artist 96), **512** (Now Playing 240). These cover output scale 2 on the Zenbook (1440 × 900
  logical).
- `<img src={localPath} objectFit="cover">` with explicit `width`/`height`, so nothing moves when
  the image decodes (U-12, GPX: "pass both width and height"). The http(s) `src` support in GPX is
  **not used**: the Subsonic URL carries the token, and the retained tree is inspectable.
- **Placeholder** until the path resolves: a `surface.sunken` tile of the final size and shape. It
  shows a monogram (first letter, 40 % of the tile height, `ink.subtle`). Placeholders never pulse
  (KIT p.skeleton is static).
- **Prefetch:** on `onVisibleRange` the host asks the visible rows ± 10 for art. The daemon allows
  6 concurrent fetches with the newest request first, and aborts requests whose rows scrolled away.
- **Cache:** `$XDG_CACHE_HOME/gpuix-shell/music/art/<sha1(coverArtId)>-<bucket>.jpg`, written
  atomically (temp file, then rename), capped at 300 MB with LRU eviction when the daemon starts.
  It is keyed by art id, never by URL (R02 §5.11).

### 3.4 Tokens the music UI uses (role names only, U-18; Noir values for reference)

| Use | Role | Noir |
|---|---|---|
| frame ground / edge | `surface.overlay` / `line.strong` | #101111 / #DEDCD1 @ 0.44 |
| separators | `line.hairline` | #DEDCD1 @ 0.15 |
| hover = keyboard cursor / selected | `state.selected` (pre-blended) | #242321 |
| pointer-only hover on buttons | `state.hover` | #161615 |
| titles / body | `ink.default` | #D3D7DE |
| subtitles, figures, words | `ink.muted` / `ink.subtle` | #818898 |
| current (now playing) bar and title, progress fill while playing, toggled transport glyphs | `accent.default` | #70B8FF |
| progress track | `line.default` | #DEDCD1 @ 0.30 |
| progress fill while paused | `ink.muted` | #818898 |
| the one primary button per view (Play in album/artist/playlist headers) | `brand.emphasis` fill, `ink.on-brand` text | #D97757 / #131313 |
| liked glyph ♥ | `ink.default` (the word carries the meaning, not the colour, U-02) | — |
| placeholder tile | `surface.sunken` + `ink.subtle` monogram | #000000 / #818898 |
| match wash | `accent.muted` | accent @ 0.13 |
| errors | `status.danger.fg` with the word "Failed" | #F47B85 |

Faces: `Anthropic Sans` (ui) for everything except durations, counts and times, which use the
`figures` role (`AnthropicMono Nerd Font` 12/18), and **lyrics**, which use `Anthropic Serif` 15 @ 1.65
(the prose voice: "authored reading", KIT §4.3). Every `<text>` names its colour, because GPUIX text
does not inherit colour (KIT §4.9). Text is written in sentence case, with no styled capitals.

### 3.5 States every music list can be in (U-04)

| State | Body | Footer echo |
|---|---|---|
| Loading (> 150 ms) | previous rows stay (`keepPreviousData`) + header loading bar; first load: 6 placeholder rows of final height | — |
| Indexing (lexicon not ready) | server results only; a one-line notice above the first section: "Indexing the library · fuzzy matches in a moment" | — |
| Partial | the section's status line, e.g. "Server results pending" or "Similar songs unavailable · showing same genre and era" | — |
| No results | "No results for "kind of blue"" + rows: "Search all songs for …" (scope Songs), "Start radio from …" (if a seed is selected) | — |
| Offline | "Can't reach Navidrome at music.internal" / "Check Tailscale or the closet LAN, then press Ctrl+R" | Retry Ctrl+R |
| Unauthorized | "Navidrome refused the saved credentials" / "Check /run/agenix/navidrome-credentials" (path only, never its content) | — |
| Daemon down | "Music is not running" / "Start it with systemctl --user start gpuix-shell-music" | — |
| Empty (valid) | per view (e.g. "Nothing liked yet · press Ctrl+L on any song") | — |
| Failed action | the action's error echo, `status.danger.fg` + the word "Failed" ("Failed to add to Late night: Navidrome says this account may not edit playlists") | Copy error Ctrl+T |

---

## 4. Keyboard grammar (every music view)

The base is R01 §10 (Raycast with ⌘ → Ctrl, ⌥ → Alt), already logged. Overrides are marked **D**
and logged. The input always keeps focus. The list cursor is application state, not a focus target
(U-11: composites are one tab stop). Keys run in this order: the actions panel layer, the view's
keys, the shortcuts of the selected row's actions, then host defaults (§9.3).

**Navigation**

| Key | Does |
|---|---|
| type | query (search views) or filter (lists); in Now Playing, typing jumps to Search with that text |
| `↑` `↓` | move the cursor; `PageUp`/`PageDown` by a page; in grids, `←` `→` move by card when the input is empty |
| `Tab` / `Shift+Tab` (alias `Ctrl+P` for the next scope) | cycle the scope chips (All · Songs · Albums · Artists · Playlists; per view in §5) |
| `Enter` | primary action of the row: **Play** (songs play in context; albums, playlists and artists play) |
| `Ctrl+Enter` **D** | **Open** (drill into album / artist / playlist / genre; on a song, open its album scrolled to it). Raycast's default secondary key |
| `Shift+Enter` | Play and close the launcher |
| `Ctrl+Shift+A` | Open (R01's alias, kept) |
| `Ctrl+K` (alias `Ctrl+B`) | actions panel |
| `Ctrl+I` **D** | toggle the detail pane |
| `Esc` | close panel → clear the query → pop view → close the launcher at the root |
| `Backspace` on an empty input | pop view |
| `Shift+Esc` | close the launcher from any depth |
| `Ctrl+R` | refresh the view (refetch, bypassing the cache) |

**D:** there is no Emacs-style `Ctrl+N`/`Ctrl+P` cursor movement, because `Ctrl+P` is R01's scope
key.

**Row actions (on the selected row)**

| Key | Does |
|---|---|
| `Alt+N` | play next (insert at the head of "Next in queue") |
| `Alt+Q` | add to queue (append to "Next in queue") |
| `Ctrl+Shift+S` **D** | shuffle-play the album / playlist / artist / genre (R01 had Save album; liking an album or artist folds into `Ctrl+L`) |
| `Ctrl+Shift+R` | start radio from the row |
| `Ctrl+L` | like / unlike (Subsonic star) song, album or artist; toggle by known state |
| `Ctrl+D` | unlike (explicit) |
| `Alt+P` | add to playlist… (picker) |
| `Ctrl+Y` | popular songs (artist rows) |
| `Ctrl+G` **D** | go to artist |
| `Ctrl+O` | open in Navidrome (`$NAVIDROME_URL/app/#/<album|artist|playlist>/<id>/show`; songs open their album) |
| `Ctrl+Shift+C` / `Ctrl+Shift+T` | copy Navidrome link / copy "Title · Artist" |
| `Ctrl+X` / `Ctrl+Shift+X` | remove (queue, recent searches) / remove all, with Undo |
| `Ctrl+Z` | undo the last echoed action (6 s window, one level) |
| `Ctrl+T` | copy the last error |

**Player (any music view, any row)**

| Key | Does |
|---|---|
| `Ctrl+Space` | play / pause (and `Space` when the input is empty, as in Now Playing) |
| `Ctrl+→` / `Ctrl+←` | next / previous (previous restarts if more than 3 s in, R01) |
| `Alt+→` / `Alt+←` | seek +15 s / −15 s |
| `Ctrl+↑` / `Ctrl+↓` | music volume +10 / −10 (mpv volume, not the system volume) |
| `Alt+S` / `Alt+R` | shuffle on/off / repeat off → all → one |
| `Alt+L` **D** | like / unlike the **current** track (from any row) |
| `Ctrl+Shift+K` | output device (PipeWire sinks) |
| `Ctrl+Shift+F` / `Ctrl+Shift+L` | go to Search / Library |

Unverified: `Ctrl+Space`, the `Alt+arrow` keys and `Ctrl+arrow` keys reaching an exclusive-keyboard
layer surface unmodified under Sway, and the GPUI `<input>` not consuming `Ctrl+←/→` as word motion
before the `onKeyDown` handler runs. The handler calls `preventDefault()` (GPX `KeyEvent`). If the
input wins, the fallback is `Ctrl+.`/`Ctrl+,` for next/previous, and the smoke in §12 must decide.

---

## 5. Views

Each view is a `LauncherView` (§9) at a `Route` `music/<path>`. A route can be opened directly
with `gpuix-shell launcher --view music/<path>` (U-14: links carry view state).

### 5.1 Launcher root: the Music entry and root contributions

```
╭────────────────────────────────────────────────────────────────────────────╮
│  ⌕  Search apps, windows, workspaces, music…                               │
├────────────────────────────────────────────────────────────────────────────┤
│ Suggestions                                                                │
│  [♪]  Music                         Search your library                ›   │
│  [▣]  Now playing: Holocene         Bon Iver · Playing · 2:31 / 5:36   ›   │
│  …                                                                         │
├────────────────────────────────────────────────────────────────────────────┤
│ [▣] Holocene · Bon Iver   ━━━━━━━━──────── 2:31 / 5:36      ⏮   ⏸   ⏭      │
├────────────────────────────────────────────────────────────────────────────┤
│                                                 Open  ↵  │  Actions Ctrl K │
╰────────────────────────────────────────────────────────────────────────────╯
```

With a query (`bon`), the root gets a **Music** section capped at 3 rows (`rootLimit`). It holds the
top artist, album and song from the daemon's local index plus the server merge. The header row offers
`Tab` "Search in Music", which pushes `music/search` with the query (Raycast "search in extension").
No-view **commands** match by name: "Play or pause music", "Next track", "Previous track", "Like
current track", "Shuffle music", "Repeat music", "Music volume up/down", "Start radio from current
track", "Shuffle all songs", "Show music queue", "Show now playing". When nothing matches, there is a
root fallback row: "Search music for "…"".

Keys: as at the launcher root. `Enter` on **Music** pushes `music` (5.2). `Enter` on "Now playing"
pushes `music/now-playing`. Commands run with no view and echo in the footer.

### 5.2 Music home (empty query) — route `music`

```
╭────────────────────────────────────────────────────────────────────────────╮
│ ‹ Music   What do you want to listen to?    All Songs Albums Artists Lists │
├────────────────────────────────────────────────────────────────────────────┤
│ Continue                                                                   │
│▌[▣] Holocene                          Playing · 2:31 / 5:36                │
│     Bon Iver · Next: Towers, then 12 more                                  │
│ Jump back in                                                    Show all › │
│ ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐                     │
│ │  112   │ │        │ │        │ │        │ │        │                     │
│ └────────┘ └────────┘ └────────┘ └────────┘ └────────┘                     │
│ Bon Iver,  22, A Mil  Mezzanine  Untrue     In Rainbo                      │
│ 2011       2016       1998       2007       2007                           │
│ New in library                                                  Show all › │
│ (5 cards)                                                                  │
│ Browse                                                                     │
│  [≡] Library                                                           ›   │
│  [≡] Playlists                      1,235                              ›   │
│  [≡] Queue                          13 up next                         ›   │
│  [~] Radio from Holocene                                               ›   │
│  [⤨] Shuffle all songs              38,524 songs                           │
│ Recent searches                                                            │
│  [⌕] bon iver                                                              │
├────────────────────────────────────────────────────────────────────────────┤
│                                                 Play  ↵  │  Actions Ctrl K │
╰────────────────────────────────────────────────────────────────────────────╯
```

Sections:

| Section | Source |
|---|---|
| **Continue** | the daemon's current track, or the server play queue restored at daemon start (`getPlayQueue`). Hidden when both are empty. |
| **Jump back in** | `getAlbumList2 type=recent size=5` |
| **New in library** | `newest` |
| **Most played** | `frequent` |
| **Random albums** | `random`, re-rolled by `Ctrl+R` |
| **Browse** | links |
| **Recent searches** | ≤ 10, recorded after a 3 s settle on > 3 chars or on any play/queue action (R01 §3.2, R02 §5.6) |

Each shelf is one grid row of 5 cards with "Show all" (a pushed grid). The cursor moves between cards
with `←`/`→` on an empty input. `Enter` on Continue toggles play/pause, and `Ctrl+Enter` opens Now
Playing.

### 5.3 Search — route `music/search?q=…` (also the home view once the query is non-empty)

```
╭────────────────────────────────────────────────────────────────────────────╮
│ ‹ Music   bon▏                              All Songs Albums Artists Lists │
├────────────────────────────────────────────────────────────────────────────┤
│ Top result                                                                 │
│▌╭──────╮ Bon Iver                                                ┌──────┐  │
│ │  ◯   │ Artist · 4 albums · 38 songs                            │ Play │  │
│ ╰──────╯                                                         └──────┘  │
│ Songs                                                     24 · Show all ›  │
│  [▣] Holocene                                         12 plays  ♥    5:36  │
│      Bon Iver · Bon Iver, Bon Iver                                         │
│  [▣] Skinny Love                                                     3:58  │
│      Bon Iver · For Emma, Forever Ago                                      │
│  [▣] Bon Appétit                                                     3:47  │
│      Perfume Genius · No Shape                                             │
│ Artists                                                    5 · Show all ›  │
│  (◯) Bon Iver                                                  4 albums    │
│  (◯) Bonobo                                                    7 albums    │
│ Albums                                                     8 · Show all ›  │
│  [▣] Bon Iver, Bon Iver                                   2011  10 songs   │
│      Bon Iver                                                              │
├────────────────────────────────────────────────────────────────────────────┤
│ [▣] Holocene · Bon Iver   ━━━━━━━━──────── 2:31 / 5:36      ⏮   ⏸   ⏭      │
├────────────────────────────────────────────────────────────────────────────┤
│                                                 Play  ↵  │  Actions Ctrl K │
╰────────────────────────────────────────────────────────────────────────────╯
```

- **Order and caps (D):** Top result (1) · Songs 4 · Artists 3 · Albums 6 · Playlists 4. "Liked
  songs" leads Playlists when the query matches "like" or "liked". Genres 2 appear only on a strong
  match. This is Spotify desktop's order (songs right after the top result, because Enter-to-play
  is the commonest act). R01's Raycast order put Artists first.
- **Scopes** (`Tab`/`Ctrl+P`, or a prefix in the query): All · Songs (`s:`) · Albums (`al:`, grid) ·
  Artists (`ar:`, grid) · Playlists (`p:`), plus prefix-only `g:` genre and `y:1997` or
  `y:1990-1999` year. In a single scope the list is complete and pages by `search3` offsets on
  `onVisibleRange` (infinite list). The local index answers Albums, Artists and Playlists first.
- **Cursor rule (U-12):** until the person moves the cursor after a keystroke, the cursor sits on
  row 0 (the Top result). After they move it, the cursor is pinned **by row id**. Arriving server
  rows insert around it and never under it. If the pinned row disappears, the cursor goes to the
  nearest surviving row above it.
- Data, ranking and timing: §8.
- Keys: §4. `Enter` on the Top result plays it. On an artist that is popular songs; if those are
  fewer than 5, it plays the artist's songs by album year, newest first. `Ctrl+Enter` opens.

### 5.4 Album — route `music/album/<id>`

```
╭────────────────────────────────────────────────────────────────────────────╮
│ ‹ Album   Filter 10 songs…                                                 │
├────────────────────────────────────────────────────────────────────────────┤
│  ┌──────────────┐  Bon Iver, Bon Iver                                      │
│  │              │  Bon Iver                                                │
│  │     160      │  Album · 2011 · 10 songs · 39 min · Indie folk           │
│  │              │                                                          │
│  │              │  ┌────────┐ ┌─────────┐ ┌──────────────┐ ┌───────────┐   │
│  └──────────────┘  │ ▶ Play │ │ Shuffle │ │ Add to queue │ │ Navidrome │   │
│                    └────────┘ └─────────┘ └──────────────┘ └───────────┘   │
│ Disc 1                                                                     │
│▌ ▶  Perth                                              ♥          4:22     │
│  2  Minnesota, WI                                                 3:52     │
│  3  Holocene                                  12 plays            5:36     │
│  4  Towers                                                        3:08     │
│  …                                                                         │
├────────────────────────────────────────────────────────────────────────────┤
│ [▣] Perth · Bon Iver      ━━━──────────────── 0:41 / 4:22      ⏮   ⏸   ⏭   │
├────────────────────────────────────────────────────────────────────────────┤
│ Liked Bon Iver, Bon Iver · Undo Ctrl+Z          Play  ↵  │  Actions Ctrl K │
╰────────────────────────────────────────────────────────────────────────────╯
```

- **Header** (192, the first virtual-list item, so it scrolls away):
  - cover 160, radius 8;
  - title 18/22 weight 600, then the artist 14/21 (`Ctrl+G` goes there; it is clickable);
  - a facts line 13/20 `ink.muted`, with the total duration in words ("39 min", "1 h 12 min");
  - buttons 34 high, radius 8. **Play** is the view's one `brand.emphasis` button. Shuffle, Add to
    queue and Navidrome are outline buttons.
  Each button mirrors a key and is not a tab stop. Play is `Enter` with the cursor on the header row
  (where the view opens when nothing from this album is playing). Shuffle is `Ctrl+Shift+S`, Add to
  queue is `Alt+Q` and Navidrome is `Ctrl+O`, from any row of the view.
- **Tracks:** `getAlbum`. Multi-disc albums get one section per disc ("Disc 2 · <discTitle>").
  `filtering: "launcher"`: typing filters tracks locally.
- `Enter` on a track plays the album from that track (context = album). The cursor opens on the
  header row, or on the current track if this album is playing. `Ctrl+Enter` on a track opens its
  artist.
- Empty filter result: "No song in this album matches "…"".

### 5.5 Artist — route `music/artist/<id>`

```
╭────────────────────────────────────────────────────────────────────────────╮
│ ‹ Artist  Filter Bon Iver…                     All Songs Albums Similar    │
├────────────────────────────────────────────────────────────────────────────┤
│   ╭──────────╮  Bon Iver                                                   │
│   │    96    │  Artist · 4 albums · 38 songs · 2 plays this month          │
│   │  circle  │  Bon Iver is an American indie folk band founded in 2006    │
│   ╰──────────╯  by Justin Vernon…   (Ctrl+I reads the full biography)      │
│                 ┌────────┐ ┌─────────┐ ┌───────┐ ┌───────────┐             │
│                 │ ▶ Play │ │ Shuffle │ │ Radio │ │ Navidrome │             │
│                 └────────┘ └─────────┘ └───────┘ └───────────┘             │
│ Popular                                              via Last.fm · 1 song  │
│  1 [▣] Holocene                                       12 plays    5:36     │
│ Most played by you                                                         │
│  2 [▣] Perth                                           4 plays    4:22     │
│ Albums                                                                     │
│ ┌────────┐ ┌────────┐ ┌────────┐                                           │
│ │        │ │        │ │        │   (5-column grid, newest first)           │
│ └────────┘ └────────┘ └────────┘                                           │
│ Singles and EPs  ·  Appears on  ·  Similar artists (circles, 4)            │
├────────────────────────────────────────────────────────────────────────────┤
│                                                 Play  ↵  │  Actions Ctrl K │
╰────────────────────────────────────────────────────────────────────────────╯
```

- **Data:** `getArtist` (albums), `getArtistInfo2` (biography, similar artists; 0.3 s),
  `getTopSongs` (sparse: 1 song for Bon Iver), and the artist's album songs for the fallback.
- **Popular** = `getTopSongs`. When it returns fewer than 5, a second section **Most played by you**
  fills up to 5 from the artist's songs by `playCount`. The sections are labelled honestly with
  their source (U-04 "partial").
- **Albums** split by OpenSubsonic `releaseTypes`: Albums · Singles and EPs · Compilations ·
  Appears on (albums where the artist is not the album artist). Each is newest first.
- **Biography:** stripped of HTML to Markdown. Two lines show in the header; the full text is in the
  detail pane (`<markdown>`, with links opened externally via `onLinkClick` → `xdg-open`).
- **Similar artists:** `getArtistInfo2.similarArtist` (those with an `id` in the library). `Enter`
  opens that artist.
- Scopes: All · Songs (all songs by the artist, paged) · Albums (grid) · Similar.
- `Enter` on the header plays popular songs. `Ctrl+Shift+S` shuffles every song by the artist.

### 5.6 Now Playing — route `music/now-playing` (layout `custom`)

```
╭────────────────────────────────────────────────────────────────────────────╮
│ ‹ Now playing   Type to search…                    Up next  Lyrics  Info   │
├────────────────────────────────────────────────────────────────────────────┤
│  ┌──────────────────────────┐   Holocene                                   │
│  │                          │   Bon Iver                                   │
│  │                          │   Bon Iver, Bon Iver · 2011                  │
│  │                          │                                              │
│  │        240 × 240         │   Playing · Shuffle off · Repeat all         │
│  │                          │   ♥ Liked · 12 plays · Volume 70             │
│  │                          │                                              │
│  │                          │   Up next                                    │
│  │                          │   [▣] Towers · Bon Iver              3:08    │
│  │                          │   [▣] Michicant · Bon Iver           3:35    │
│  └──────────────────────────┘   From: Bon Iver, Bon Iver · 7 more          │
│                                                                            │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━──────────────────────────────────  │
│  2:31                                                                5:36  │
│                                                                            │
│       ⤨          ⏮          ⏸          ⏭          ↻          ♥             │
├────────────────────────────────────────────────────────────────────────────┤
│                                                Pause  ↵  │  Actions Ctrl K │
╰────────────────────────────────────────────────────────────────────────────╯
```

- **Geometry:** padding 20. Cover 240 × 240, radius 8, from the 512 bucket. The right column starts
  at x = 284 and is 396 wide:
  - title 18/22 weight 600, then the artist 14/21 (`Ctrl+G`), then "Album · Year" 13/20 `ink.muted`
    (`Ctrl+Enter` opens the album);
  - a state line in 12/18 `ink.muted`, made of words: "Playing / Paused / Buffering", "Shuffle on/off",
    "Repeat off/all/one" (U-03: a state is a word);
  - a facts line: "♥ Liked", plays, "Volume 70";
  - the tab area (`Tab` cycles Up next · Lyrics · Info).
  Below the cover:
  - **progress**: 4 px high, 652 wide, radius 2, track `line.default`, fill `accent.default`, or
    `ink.muted` when paused. Clicking or dragging seeks, with x read from the bar's `onLayout`
    bounds. `aria-valuetext` reads "2:31 of 5:36, playing";
  - the figures row 12/18 mono. Clicking the total toggles it to the remaining time ("−3:05").
- **Transport:** 6 buttons, each 36 × 36 with radius 8: shuffle, previous, play/pause, next,
  repeat (`↻`, with a `1` badge for repeat one), like. Toggled ones use `accent.default` glyphs, and
  the word is in the state line, so colour is never the only cue. Each button has an `aria-label`,
  and `aria-valuetext` carries its state.
- **Keys here:** `Space` or `Enter` play/pause (the input is empty). `←`/`→` seek ∓10 s, and with
  `Shift` ∓30 s. `↑`/`↓` move in Up next, where `Enter` on a row jumps to it. The §4 player keys
  also work. Printable keys switch to Search with that text. `Ctrl+L` likes the current track.
  `Ctrl+Shift+R` starts a radio from it. `Alt+P` adds it to a playlist.
- **Lyrics tab:** the right column becomes one line "Holocene · Bon Iver", then a `<virtual-list>`
  of lyric lines in `Anthropic Serif` 15 @ 1.65.
  - Synced lyrics (`structuredLyrics[].synced`): the current line is `ink.default`; the others are
    `ink.muted`. The current line is kept at one third of the height with `scrollToItem(index,
    −viewport/3)` (GPX). There is a ±250 ms offset, as in cliamp. `Enter` on a line seeks to it.
  - Unsynced lyrics: `<markdown>` paragraphs.
  - Empty: "No lyrics for this track" / "Navidrome has none embedded or beside the file", and, when
    LRCLIB is enabled, "Search LRCLIB" (off by default; it sends artist and title off the box —
    logged).
- **Info tab:** format and bitrate ("m4a · 257 kbps · 44.1 kHz"), streaming mode ("original" or
  "transcoded to Opus 128 kbps"), size, genres, BPM, added date, path, MusicBrainz id
  (`Ctrl+Shift+C` copies the field under the cursor).
- **Nothing loaded:** the cover is a 240 sunken tile with ♪, then "Nothing is playing" / "Search with
  Ctrl+Shift+F, or shuffle everything with Ctrl+Shift+S". `Ctrl+Shift+S` here = Shuffle all songs.

### 5.7 Queue — route `music/queue`

```
╭────────────────────────────────────────────────────────────────────────────╮
│ ‹ Queue   Filter queue…                             15 songs · 1 h 2 min   │
├────────────────────────────────────────────────────────────────────────────┤
│ Now playing                                                                │
│▌[▣] Holocene · Bon Iver                       Playing            5:36      │
│ Next in queue                                       2 · Clear Ctrl+Shift+X │
│  1 [▣] Re: Stacks · Bon Iver                                     6:41      │
│  2 [▣] Teardrop · Massive Attack                                 5:29      │
│ Next from: Bon Iver, Bon Iver                       Shuffle off · 7 songs  │
│  3 [▣] Towers · Bon Iver                                         3:08      │
│  4 [▣] Michicant · Bon Iver                                      3:35      │
│  …                                                                         │
│ History                                                       20 · Show ›  │
├────────────────────────────────────────────────────────────────────────────┤
│ Moved Teardrop up · Undo Ctrl+Z                 Jump  ↵  │  Actions Ctrl K │
╰────────────────────────────────────────────────────────────────────────────╯
```

- **Model** (cliamp, R02 §5.7):
  - "Next in queue" holds the items added by Play next (`Alt+N`) and Add to queue (`Alt+Q`). They
    play before the context resumes.
  - "Next from: <context>" is the rest of the album, playlist, radio or search the track was played
    from, in shuffled order when shuffle is on.
  - "History" holds the last 20 played tracks, collapsed into a link.
  - Playing a new context replaces the context and **keeps** "Next in queue" (Spotify behaviour).
- **Keys:**
  - `Enter`: jump (play this; everything before it moves to history).
  - `Ctrl+Shift+↑`/`↓`: move one place (R01). Moving across the section boundary moves an item
    between "Next in queue" and the context.
  - `Alt+N` on a context row: move it to the head of "Next in queue".
  - `Ctrl+X`: remove. `Ctrl+Shift+X`: clear "Next in queue" (the context stays). Every edit echoes
    and offers `Ctrl+Z`.
  - Typing filters locally.
- **Mutations carry the queue `rev`.** A stale edit, made after the queue changed underneath it, is
  refused and the view refreshes. The echo says "The queue changed; nothing was moved" (R02 §5.7).

### 5.8 Library — route `music/library` and its lists

```
╭────────────────────────────────────────────────────────────────────────────╮
│ ‹ Library   Filter library…                                                │
├────────────────────────────────────────────────────────────────────────────┤
│ Your music                                                                 │
│▌ [◷] New in library                         16,208 albums             ›    │
│  [↺] Recently played                                                  ›    │
│  [▲] Most played                                                      ›    │
│  [♥] Liked                                  Nothing yet               ›    │
│  [⤨] Random albums                                                    ›    │
│  [⤨] Shuffle all songs                      38,524 songs                   │
│ Browse by                                                                  │
│  [♫] Genres                                 136 with 20+ songs        ›    │
│  [≡] Playlists                              1,235                     ›    │
│  [◫] Years                                  1950s to 2020s            ›    │
│  [◯] Artists A to Z                         11,118                    ›    │
├────────────────────────────────────────────────────────────────────────────┤
│                                                 Open  ↵  │  Actions Ctrl K │
╰────────────────────────────────────────────────────────────────────────────╯
```

| Row → route | Source | Layout | Notes |
|---|---|---|---|
| New in library → `library/newest` | `getAlbumList2 newest`, paged 60 | grid | `Ctrl+Shift+G` toggles grid/list (D) |
| Recently played → `library/recent` | `recent` + local `history.jsonl` songs | grid + "Songs" list | |
| Most played → `library/frequent` | `frequent` | grid | album play count in the card meta |
| Liked → `library/liked` | `getStarred2` | sections Songs · Albums · Artists | empty today: "Nothing liked yet · press Ctrl+L on any song, album or artist" |
| Random albums → `library/random` | `random` | grid | `Ctrl+R` re-rolls |
| Shuffle all songs (no view) | `getRandomSongs size=100`, refilled at ≤ 5 left | — | context "Library shuffle" |
| Genres → `library/genres` | `getGenres` | list | the 136 with ≥ 20 songs, by song count; typing searches all 3,966; `Enter` plays a genre mix; `Ctrl+Enter` opens `genre/<name>` (albums grid + songs) |
| Playlists → `playlists` | §5.9 | list-detail | |
| Years → `library/years` | decades from the local index (album `year`) with counts | list → years → grid | `y:1997` works in search too |
| Artists A to Z → `library/artists` | local index (11,118) | list with letter section headers | typing filters locally; `Enter` plays, `Ctrl+Enter` opens |

### 5.9 Playlists — route `music/playlists`, then `music/playlist/<id>`

```
╭────────────────────────────────────────────────────────────────────────────╮
│ ‹ Playlists  Filter 1,235 playlists…                                       │
├──────────────────────────────┬─────────────────────────────────────────────┤
│▌[▣] Late night               │  ┌────────────┐  Late night                 │
│     42 songs · 2 h 51 min    │  │            │  Playlist · 42 songs        │
│ [▣] Run                      │  │    160     │  2 h 51 min                 │
│     12 songs · 48 min        │  │            │  Changed 3 days ago         │
│ [▣] Liked songs              │  └────────────┘                             │
│     0 songs                  │   1  Holocene · Bon Iver            5:36    │
│ [▣] Sunday                   │   2  Teardrop · Massive Attack      5:29    │
│     7 songs · 31 min         │   3  …                                      │
├──────────────────────────────┴─────────────────────────────────────────────┤
│                                                 Play  ↵  │  Actions Ctrl K │
╰────────────────────────────────────────────────────────────────────────────╯
```

- **Layout** `list-detail`: list 300 wide | hairline | detail 375. The detail is `detail(row)`: cover
  160, facts, the comment as Markdown, and the first 8 tracks. It loads after the cursor rests for
  120 ms, and the request is aborted when the cursor moves on.
- **Sort:** recently changed first. "Liked songs" (the `getStarred2` songs) is pinned first.
  Filtering is local fuzzy over the names.
- `Enter` plays and `Ctrl+Enter` opens `playlist/<id>`. That view is a tracklist like the Album view
  (§5.4), with header Play / Shuffle / Add to queue / Navidrome, and `Ctrl+X` = "Remove from this
  playlist".
- **Add to playlist picker** (`Alt+P`, route `music/pick-playlist?song=<id>`):
  - the same list, filtered to playlists where `readonly` is false;
  - a top row "New playlist from this song";
  - a ✓ "Already in playlist" accessory, checked lazily for the selected row only.
  The write is `updatePlaylist songIdToAdd`. The account has `playlistRole: false`. If Navidrome
  refuses (error 50), the echo is "Failed: Navidrome says this account may not edit playlists".
  This is unverified, because no write was made tonight.

### 5.10 Radio — route `music/radio/<song|artist|album>/<id>`

```
╭────────────────────────────────────────────────────────────────────────────╮
│ ‹ Radio   Filter…                                       from Holocene      │
├────────────────────────────────────────────────────────────────────────────┤
│ Seed                                                                       │
│▌[▣] Holocene                                        Song · Bon Iver        │
│ Similar songs                               via Last.fm, in your library   │
│  [▣] Re: Stacks · Bon Iver                                       6:41      │
│  [▣] Flume · Bon Iver                                            3:39      │
│ From similar artists                    Sufjan Stevens, Iron & Wine, …     │
│  [▣] Chicago · Sufjan Stevens                                    6:04      │
│ Same genre and era                                 Indie folk · 2006–2016  │
│  [▣] …                                                                     │
│ Finding more ···                                                           │
├────────────────────────────────────────────────────────────────────────────┤
│                                           Play radio  ↵  │  Actions Ctrl K │
╰────────────────────────────────────────────────────────────────────────────╯
```

- **Layered sources, labelled honestly** (MEASURED sparse, R02 §5.9):
  1. `getSimilarSongs(songId)`;
  2. `getSimilarSongs2(artistId)`;
  3. `getTopSongs` of up to 5 `getArtistInfo2.similarArtist`;
  4. `getRandomSongs genre=<seed genre> fromYear=year−5 toYear=year+5`.
  Results are de-duplicated by id, at most 2 per artist in each window of 10 tracks, and the seed
  plays first.
- **Loading:** each section paints as its source answers (similar songs measured at 1.1–3.8 s).
  The trailing "Finding more ···" uses the 3-dot `p.spinner` (KIT §4.5, stepped by a timer, no
  motion).
- **Endless:** while radio is the context, the daemon refills from layers 3 and 4 when 5 or fewer
  tracks remain.
- `Enter` on the seed or the footer action plays the radio (context "Radio · Holocene"). `Enter` on
  a row plays the radio from that row.
- **Route without an id** (`music/radio`): the current track is the seed; with nothing playing, the
  selected search row is.

### 5.11 Actions panel (`Ctrl+K`)

```
│                                    ╭────────────────────────────────────╮  │
│                                    │ Filter actions…                    │  │
│                                    ├────────────────────────────────────┤  │
│                                    │ Play                            ↵  │  │
│                                    │ Open album               Ctrl ↵    │  │
│                                    │ Play and close          Shift ↵    │  │
│                                    │ ────────────────────────────────── │  │
│                                    │ Play next                  Alt N   │  │
│                                    │ Add to queue               Alt Q   │  │
│                                    │ Start radio         Ctrl Shift R   │  │
│                                    │ Like song                 Ctrl L   │  │
│                                    │ Add to playlist…           Alt P   │  │
│                                    │ ────────────────────────────────── │  │
│                                    │ Go to artist              Ctrl G   │  │
│                                    │ Open in Navidrome         Ctrl O   │  │
│                                    │ Copy link           Ctrl Shift C   │  │
│                                    ╰────────────────────────────────────╯  │
├────────────────────────────────────────────────────────────────────────────┤
│                                                 Play  ↵  │  Actions Ctrl K │
```

- **GPX:**
  - `<anchored side="top" align="end" gap={8} fit="snap">`, anchored to the footer's
    "Actions" text. It stays inside the 700 × 580 surface, since popups cannot leave it (KIT §4.9).
  - Wrapped in `DismissableLayer`, so `Esc` closes only the panel and focus returns to the input.
  - Width 340, radius 12, ground `surface.overlay`, a 1 px `line.strong` edge, no shadow. Rows are
    32, actions are grouped by hairlines, and each has a filter input of its own.
- **Contents:** `actions(row)` in order, grouped by consequence: play · queue · library writes ·
  navigate · external/copy. A disabled action shows its `unavailable` reason as its subtitle (U-10).

### 5.12 Output device (`Ctrl+Shift+K`) — route `music/output`

A list of PipeWire sinks (`wpctl status` / `pw-dump`, reusing the `audio-route` conventions from R02
§5.14). The active sink is marked with the word "Active". `Enter` sets mpv `audio-device` live. A
near-silent stored volume is lifted before routing, per commit `97ef81a9`. P1.

---

## 6. Commands and controls (one registry, U-10)

Every row below is a `Command` in `MusicProvider.commands`. The launcher root, the CLI, MPRIS, the
OSD/rail and the in-view keys all call the same id over `ctl.sock`.

| Command id | Root title | CLI `gpuix-shell music …` | In-view key | MPRIS | Echo (and Undo) |
|---|---|---|---|---|---|
| `music.toggle` | Play or pause music | `toggle` (also `play`, `pause`) | `Ctrl+Space` | PlayPause/Play/Pause | "Paused" / "Playing Holocene" |
| `music.next` | Next track | `next` | `Ctrl+→` | Next | "Skipped to Towers" |
| `music.previous` | Previous track | `prev` | `Ctrl+←` | Previous | "Replaying" or "Back to Perth" |
| `music.seek` | — | `seek +15` / `seek -15` / `seek 1:30` | `Alt+→/←` | Seek/SetPosition | "Skipped ahead 15 seconds" |
| `music.stop` | Stop music | `stop` | — | Stop | "Stopped" |
| `music.volume` | Music volume up / down | `volume 70` / `volume +10` / `volume -10` | `Ctrl+↑/↓` | Volume | "Music volume 70%" (validated 0–100, R01 §7.7 messages) |
| `music.mute` | Mute music | `mute [on|off]` | — | — | "Music muted" |
| `music.shuffle` | Shuffle music | `shuffle [on|off|toggle]` | `Alt+S` | Shuffle | "Shuffle is on" |
| `music.repeat` | Repeat music | `repeat [off|all|one|cycle]` | `Alt+R` | LoopStatus | "Repeat: all" |
| `music.like-current` | Like current track | `like [--toggle|on|off]` | `Alt+L` | — | "Liked Holocene" · Undo |
| `music.radio-current` | Start radio from current track | `radio` | `Ctrl+Shift+R` (Now Playing) | — | "Playing radio from Holocene" · Undo (restores the queue) |
| `music.shuffle-all` | Shuffle all songs | `shuffle-all` | `Ctrl+Shift+S` (Now Playing, empty) | — | "Shuffling 38,524 songs" · Undo |
| `music.play` | — | `play <song|album|playlist|artist>:<id>` or `play "<query>"` (the top result, R01 "Just Play") | `Enter` | — | "Playing …" · Undo |
| `music.enqueue` | — | `queue add <kind>:<id> [--next]` | `Alt+Q` / `Alt+N` | — | "Added … to the queue" · Undo |
| `music.queue` | Show music queue | `queue [--json]` | — | — | — |
| `music.now-playing` | Show now playing | `open now-playing` | `Ctrl+Enter` on Continue | Raise | — |
| `music.open` | Music | `open [route]` → `gpuix-shell launcher --view music/<route>` | — | — | — |
| `music.output` | Choose music output | `output [list|<sink>]` | `Ctrl+Shift+K` | — | "Playing on INZONE" |
| `music.status` | — | `status [--json]` | — | Metadata/PlaybackStatus | prints `▶ Holocene · Bon Iver  2:31 / 5:36` |
| `music.watch` | — | `watch` (JSON lines of state events) | — | PropertiesChanged | — |
| `music.copy-current` | Copy current track | `copy` | `Ctrl+Shift+T` (Now Playing) | — | "Copied Holocene · Bon Iver" |

- **CLI contract:**
  - exit 0 = done;
  - 2 = usage, with R01 §7.7's messages ("Volume must be between 0 and 100");
  - 3 = daemon not running;
  - 4 = server unreachable or refused;
  - 5 = nothing playing (for track verbs), "Nothing is currently playing".
  Human output is one line. `--json` prints the `PlayerState` of §9.2.
  The CLI verbs ask the daemon to send an OSD (§7.2) **unless** the launcher is open, where the
  footer echoes instead.
- **Sway (proposed, not activated tonight).**
  - `bindsym $mod+m exec gpuix-shell launcher --view music`. `$mod+m` is free:
    `binds.conf` has no `$mod+m` since the SoundCloud pane was removed on 2026-10-12.
  - `bindsym $mod+Shift+m exec gpuix-shell launcher --view music/now-playing`.
  - Media keys stay as they are. `F3`/`F4`/`F5` and `XF86AudioPlay/Next/Prev` already run `media` →
    `playerctl`, which reaches the daemon through MPRIS. A one-line follow-up makes `media` prefer
    the music daemon: `playerctl -p gpuix_music,%any`.
- **MPRIS:** bus name `org.mpris.MediaPlayer2.gpuix_music`, Identity "Music", `CanRaise` →
  `music.now-playing`. `mpris:artUrl` is the **`file://` cache path**, never the Subsonic URL.
  Published by the daemon via `dbus-next`, because the installed mpv has no MPRIS script (R02 §5.15).

---

## 7. Rail chip and OSD

### 7.1 Now-playing chip in the rail (`a.rail-surface` footer, above the clock)

```
 expanded rail (220 wide, row 196)              collapsed rail (56 wide)
 ┌──────────────────────────────────────┐       ┌──────┐
 │ ┌──┐ Holocene                      ⏸ │       │ ┌──┐ │
 │ └──┘ Bon Iver · 2:31                 │       │ └──┘ │
 │ ━━━━━━━━━━━━━━────────────────────── │       │ ━━── │
 └──────────────────────────────────────┘       └──────┘
   196 × 46: art 24 (radius 4), title 13/18,       40 × 40: art 24 centred,
   meta 12/16 (artist ink.muted, time mono),        2 px progress under it
   state glyph 16 (⏸ while playing, ▶ paused),
   2 px progress line inset 8 at the bottom
```

- **Geometry.** Height 46 follows the rail's multi-line row rule: 30 + 16 per extra line (KIT §4.4).
  Content inset 8 horizontal / 6 vertical. The art is from the 96 bucket.
- **Interaction.** The X1 rail draws **no menu, popover or tooltip** (KIT §3.1 rule 5), so R01 P1
  #19's click menu is **not** drawn (D).
  - Click: `gpuix-shell launcher --view music/now-playing`.
  - Middle click (`onAuxClick`, button 1): `music.toggle`.
  - Wheel (`onScroll` deltaY): `music.volume ±5`, with the OSD.
  - When the rail has keyboard focus (on-demand): `Enter` opens Now Playing, `Space` toggles.
- **Visibility.** Hidden when the daemon is unreachable or nothing is loaded (U-04). Paused tracks
  keep the chip with the glyph `▶` and `aria-valuetext` "Paused".
- **Ownership.** The music builder exports `NowPlayingChip` and `useMusicState()` from
  `src/music/ui/chip.tsx`. The rail owner mounts them. The chip re-renders from state events. The
  progress line advances from a 1 s interval that runs only while the status is `playing` and the
  rail surface is mapped.

### 7.2 OSD (the one replaceable slot, KIT §3.1: "label, icon and a level bar")

When transport runs from outside the launcher (CLI, Sway, MPRIS, chip wheel), the daemon sends this
to `shell.sock`:

`{"type":"osd","slot":"music","title":"Holocene","subtitle":"Bon Iver","art":"/…/art/…-96.jpg","level":0.45,"word":"Playing"}`.

The OSD owner draws it like this: art 24 as the icon, "Holocene · Bon Iver" as the label, and the
level bar as the progress. For volume commands the level bar is the volume and the label is "Music
volume 70%". Nothing is sent for a natural track change (U-16: finished work lights up without
taking focus; the rail chip changes instead). A track-change toast is an option, `toast = false` by
default (D; R02 §5.11 proposed one on by default). When `shell.sock` is absent, nothing happens
(no fallback to mako).

---

## 8. Search: index, ranking, timing

**The lexicon (daemon, in memory, disk-cached at `$XDG_CACHE_HOME/gpuix-shell/music/lexicon.json`).**

| Kind | Fields kept |
|---|---|
| Artists (`getArtists`) | id, name, albumCount, coverArt |
| Albums (`getAlbumList2 alphabeticalByName`, paged 500) | id, name, artist, artistId, year, songCount, duration, coverArt, genre, playCount, played |
| Playlists (`getPlaylists`) | id, name, songCount, duration, changed, readonly, coverArt |
| Genres (`getGenres`) | name, songCount, albumCount |

- **Stamp:** `getScanStatus.lastScan` together with the counts. At daemon start the disk copy loads
  first. INFERRED cost, not measured: about 4 MB trimmed, parsed in under 50 ms. If the stamp changed
  or the copy is older than 24 h, it is rebuilt in the background. The rebuild is checked at start
  and on `Ctrl+R`; no timer is involved. Songs are **not** in the lexicon: `search3` already serves
  them in 11–20 ms.
- **Normalisation:** NFKD, strip marks, lowercase, `&` ↔ `and`, drop punctuation, and ignore a
  leading `the ` for ranking only.

**Matching and score** (one function, pure, unit-tested; R02 §5.2 + §5.18):

| Match on a field | Base |
|---|---|
| exact name | 1000 |
| name prefix | 800 |
| every query token prefixes a word of the name | 600 |
| every token prefixes a word of name ∪ artist (albums) — **"davis kind" → Kind of Blue** | 520 |
| every token contained | 400 |
| in-order subsequence (fuzzy), minus 8 per gap char | 100–300 |
| one edit on a token of ≥ 5 chars (typo) | 150 |
| server hit not otherwise matched locally (`search3` relevance rank r) | 450 − 10 r |

Then the boosts:

- `+20 × log2(1 + playCount)`;
- `+60` liked;
- `+40` played in the last 30 days (local `history.jsonl`);
- a type prior: artist +30, album +15, playlist +10, song 0. It only counts toward the Top result
  when two candidates are within 5 %.

The Top result is the highest final score. Sections keep their own order by score.

**Timing (per keystroke):**

1. The launcher sends `{cmd:"search", query, scope}` at once. The daemon answers a **partial**
   snapshot from the lexicon (target < 8 ms for 28k names). The launcher paints it.
2. The daemon debounces 60 ms, then calls `search3` (artistCount 6, albumCount 12, songCount 24,
   or 60 per page in a single scope) with an `AbortSignal`. The next keystroke aborts it.
3. The **final** snapshot merges and de-duplicates by id and replaces the partial one. The cursor
   rule of §5.3 applies.
4. An LRU of 50 recent `(scope, query)` finals makes backspace instant.

Timing is logged as `music.search ms_local ms_server rows`, never with the query text in the
journal.

---

## 9. The provider contract (TypeScript)

These types are **the** launcher provider interface for wave 2: apps, windows, herdr, clipboard,
files and music all implement it. They go verbatim in `pkgs/gpuix-shell/src/launcher/provider.ts`.
If wave 2 already created that file, the music builder conforms to it and reports any difference
instead of forking. The music-specific types (§9.2) live in `src/music/types.ts`.

### 9.1 `src/launcher/provider.ts`

```ts
// The one contract between the launcher host and every provider. Pure types, framework-free except
// the ReactNode slot for custom views; logic tests import nothing from @gpuix/*.
import type { ReactNode } from "react";

/** Stable command id (U-10): "<provider>.<verb>[-<noun>]", e.g. "music.play-next". */
export type CommandId = string;

/** GPUIX keystroke syntax (GPX `press()`): lowercase, "-"-joined, e.g. "ctrl-shift-enter". */
export type Keystroke = string;

/** A place in the launcher (U-14: links carry view state). `music/album/al-123?q=…`. */
export interface Route {
  provider: string;
  /** "" = the provider's home; otherwise e.g. "album/al-123", "library/newest". */
  path: string;
  query?: string;
  scope?: string;
}

/** Art is resolved lazily to a LOCAL file path; never a URL (secrets, U-12 geometry). */
export type ArtBucket = 96 | 256 | 512;
export interface Art {
  /** Cache identity (e.g. the Subsonic coverArt id). Equal keys share one image. */
  key: string;
  shape: "square" | "circle";
  /** One grapheme painted on the placeholder tile until load() resolves. */
  monogram: string;
  load(bucket: ArtBucket, signal: AbortSignal): Promise<string | null>;
}

export interface Accessory {
  text: string;
  /** "figure" = mono figures role (times, counts); default "text" = ui face. */
  face?: "figure" | "text";
  tone?: "default" | "muted" | "accent";
  /** Optional glyph drawn before the text (♥, ▶). Never the only carrier of meaning. */
  glyph?: string;
  /** Words for assistive technology: "Liked", "12 plays", "5 minutes 36 seconds". */
  label: string;
}

/** Live decoration, evaluated at render time for visible rows only. */
export interface RowState {
  /** The "current" look: 2 px accent leading bar + accent title (e.g. the playing song). */
  current?: boolean;
  /** A state word drawn as meta and announced: "Playing", "Paused", "Queued". */
  word?: string;
  /** Reason this row cannot act; the row draws disabled and says why. */
  unavailable?: string;
}

export type RowHeight = "row" | "track" | "hero" | "card";

export interface Row<D = unknown> {
  /** Globally unique and stable across lenses and launches: "music:song:<id>" (U-14). */
  id: string;
  /** Provider vocabulary; the host only uses it for testIds and grouping. */
  kind: string;
  title: string;
  subtitle?: string;
  art?: Art;
  /** Lucide icon name when there is no art. */
  icon?: string;
  /** Trailing, at most 3, drawn right-aligned in order. */
  accessories?: Accessory[];
  /** Leading figure for tracklists ("3"); replaced by ▶/‖ when current. */
  ordinal?: string;
  height?: RowHeight;
  state?: RowState;
  /** Extra local-filter text when the view uses filtering: "launcher". */
  keywords?: string[];
  data: D;
}

export type SectionLayout = "list" | "grid" | "hero";

export type SectionStatus =
  | { kind: "ready" }
  | { kind: "loading"; label: string }
  | { kind: "partial"; note: string }
  | { kind: "stale"; since: number }
  | { kind: "empty"; title: string; hint?: string }
  | { kind: "failed"; message: string; fix?: string; retry?: CommandId };

export interface Section<D = unknown> {
  /** Stable within the view: "top", "songs", "albums", "disc-1". */
  id: string;
  /** Sentence case; omitted = no header row. */
  title?: string;
  /** Right side of the header: "via Last.fm", "Shuffle off · 7 songs". */
  note?: string;
  layout?: SectionLayout;
  rows: Row<D>[];
  /** Drawn in the header when larger than rows.length. */
  total?: number;
  /** "Show all ›" target. */
  more?: Route;
  status?: SectionStatus;
}

/**
 * Every yielded value is a COMPLETE snapshot for this query and replaces the previous one
 * (local-first partial, then the merged final). The host aborts `signal` on the next keystroke
 * and ignores anything yielded after that.
 */
export type SearchResult = Section[] | Promise<Section[]> | AsyncIterable<Section[]>;

/** What an action does, declared before it runs (U-09). */
export type Consequence =
  | "navigates"
  | "plays"
  | "queues"
  | "writes-server"
  | "opens-external"
  | "copies"
  | "none";

export interface ActionOutcome {
  /** Footer echo for 6 s: "Added Holocene to the queue". */
  echo?: string;
  /** Offered as "Undo Ctrl+Z" while the echo shows. */
  undo?: () => Promise<void>;
  push?: Route;
  close?: boolean;
  error?: { message: string; fix?: string };
}

export interface Action<D = unknown> {
  id: CommandId;
  /** Verb and noun, sentence case: "Play album", "Add to queue". */
  title: string;
  icon?: string;
  shortcut?: Keystroke;
  consequence: Consequence;
  style?: "default" | "primary" | "destructive";
  /** Present = drawn disabled in the panel with this reason as subtitle. */
  unavailable?: string;
  /** Panel grouping; a hairline separates groups. */
  group?: "play" | "queue" | "library" | "navigate" | "external";
  run(row: Row<D>, ctx: ActionContext): Promise<ActionOutcome | void>;
}

export interface DetailPane {
  art?: Art;
  artSize?: 160 | 240;
  title: string;
  subtitle?: string;
  metadata?: Array<{ label: string; value: string; face?: "figure" | "text"; route?: Route }>;
  /** Rendered with <markdown>; links open externally. */
  markdown?: string;
  rows?: Row[];
  status?: SectionStatus;
}

export type Layout = "list" | "grid" | "list-detail" | "custom";

/** What every list surface implements: the provider's root contribution and each pushed view. */
export interface ListSource<D = unknown> {
  search(query: string, signal: AbortSignal): SearchResult;
  /** [0] runs on Enter, [1] on Ctrl+Enter unless they name other shortcuts. */
  actions(row: Row<D>): Action<D>[];
  detail?(row: Row<D>, signal: AbortSignal): Promise<DetailPane | null>;
}

export interface LauncherView<D = unknown> extends ListSource<D> {
  route: Route;
  /** Breadcrumb word: "Album", "Queue". */
  title: string;
  placeholder: string;
  layout: Layout;
  /** Tab / Shift+Tab cycle these; the id is passed back through route.scope. */
  scopes?: Array<{ id: string; title: string; prefix?: string }>;
  /** "launcher": host filters loaded rows locally; "provider": search() runs per keystroke. */
  filtering: "launcher" | "provider";
  /** Initial cursor: a row id, else the first row. */
  initialCursor?(): string | undefined;
  /** Layout "custom" only (Now playing): rendered in the body slot. */
  render?(props: CustomViewProps): ReactNode;
  /** View-local bindings, listed in the actions panel under "View". */
  keys?: Array<{ shortcut: Keystroke; title: string; run(ctx: ActionContext): void }>;
}

export interface Command {
  id: CommandId;
  title: string;
  subtitle?: string;
  keywords?: string[];
  consequence: Consequence;
  /** CLI argv after "gpuix-shell <provider>"; the same function serves the root row. */
  run(args: string[], ctx: ActionContext): Promise<ActionOutcome | void>;
}

export interface LauncherProvider<D = unknown> extends ListSource<D> {
  id: string;
  title: string;
  icon: string;
  /** Root matching for the provider entry itself. */
  keywords: string[];
  /**
   * Called once when the launcher process starts. Must resolve fast (≤ 50 ms budget before first
   * paint) from disk or a daemon; revalidate in the background and call ctx.invalidate("data").
   */
  prime(ctx: ProviderContext): Promise<void>;
  /** Max rows of this provider in the mixed root list (default 3). */
  rootLimit?: number;
  /** Views this provider can push. null = unknown route (host shows "Not found"). */
  open?(route: Route): LauncherView<D> | null;
  /** Live per-row decoration without re-running search (now-playing marks, queued words). */
  rowState?(row: Row<D>): RowState | undefined;
  /** No-view commands: root rows, CLI verbs, Sway binds, MPRIS all reach these ids. */
  commands?: Command[];
  /** Persistent status for the strip slot (music: the mini-player); null = slot hidden. */
  strip?(props: CustomViewProps): ReactNode | null;
  dispose?(): void;
}

export interface ProviderContext {
  cacheDir: string;
  stateDir: string;
  runtimeDir: string;
  /** "state": re-render visible rows (rowState, strip); "data": re-run the current search. */
  invalidate(what: "state" | "data"): void;
  /** Structured log; values must never contain secrets or tokenised URLs. */
  log(event: string, fields?: Record<string, string | number | boolean>): void;
}

export interface ActionContext extends ProviderContext {
  push(route: Route): void;
  pop(): void;
  close(): void;
  echo(text: string, undo?: () => Promise<void>): void;
  /** wl-copy, text on stdin, never argv. */
  copy(text: string): Promise<void>;
  /** xdg-open after scheme validation (http/https only). */
  openExternal(url: string): Promise<void>;
  /** The current route's query and scope. */
  route(): Route;
}

export interface CustomViewProps {
  ctx: ActionContext;
  query: string;
  setQuery(query: string): void;
  /** Width/height of the body slot in logical px. */
  size: { width: number; height: number };
}
```

### 9.2 `src/music/types.ts` (daemon ↔ provider ↔ CLI ↔ rail)

```ts
export type MusicKind = "song" | "album" | "artist" | "playlist" | "genre";

export interface TrackRef {
  id: string;
  title: string;
  artist: string; // displayArtist
  artistId?: string;
  album: string;
  albumId?: string;
  coverArt?: string;
  durationMs: number;
  year?: number;
  track?: number;
  disc?: number;
  genre?: string;
  liked: boolean; // Subsonic `starred` present
  playCount: number; // absent = 0
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
  changed: string;
  readonly: boolean;
  coverArt?: string;
  comment?: string;
}

/** Row payload the MusicProvider puts in Row.data. */
export type MusicRowData =
  | { kind: "song"; song: TrackRef; context?: PlayContext; index?: number }
  | { kind: "album"; album: AlbumRef }
  | { kind: "artist"; artist: ArtistRef }
  | { kind: "playlist"; playlist: PlaylistRef }
  | { kind: "genre"; name: string; songCount: number; albumCount: number }
  | { kind: "link"; route: import("../launcher/provider").Route; count?: string }
  | { kind: "recent-search"; query: string };

export type PlayContext =
  | { kind: "album" | "playlist" | "artist"; id: string; name: string }
  | { kind: "radio"; seed: { kind: "song" | "artist" | "album"; id: string }; name: string }
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
  /** Position at `positionAt` (daemon monotonic ms); clients extrapolate while playing. */
  positionMs: number;
  positionAt: number;
  volume: number; // 0..100, mpv volume
  muted: boolean;
  shuffle: boolean;
  repeat: RepeatMode;
  context: PlayContext | null;
  /** Counts only; the full queue comes from queue.get. */
  upNext: number;
  contextRemaining: number;
  queueRev: number;
  output?: string; // PipeWire sink description
  server: ServerStatus;
  /** Local cover path for the current track at bucket 96 (rail chip, MPRIS artUrl). */
  artPath?: string;
  error?: { message: string; fix?: string };
}

export interface QueueSnapshot {
  rev: number;
  current: TrackRef | null;
  upNext: TrackRef[]; // user-added, played first
  context: PlayContext | null;
  contextNext: TrackRef[]; // remaining, in play order (shuffled when shuffle is on)
  history: TrackRef[]; // last 20, newest first
}

export type PlayItem = { kind: MusicKind; id: string } | { kind: "query"; query: string };

/** Requests over $XDG_RUNTIME_DIR/gpuix-shell/music/ctl.sock, one JSON object per line. */
export type MusicRequest =
  | { cmd: "state" }
  | { cmd: "watch" }
  | { cmd: "search"; query: string; scope?: "all" | "songs" | "albums" | "artists" | "playlists"; offset?: number }
  | { cmd: "browse"; path: string; offset?: number } // album/<id>, artist/<id>, library/newest, …
  | { cmd: "play"; items: PlayItem[]; context?: PlayContext; startIndex?: number; shuffle?: boolean }
  | { cmd: "enqueue"; items: PlayItem[]; where: "next" | "end" }
  | { cmd: "toggle" | "play-resume" | "pause" | "next" | "previous" | "stop" }
  | { cmd: "seek"; seconds: number; relative: boolean }
  | { cmd: "volume"; value: number; relative: boolean }
  | { cmd: "mute"; on?: boolean }
  | { cmd: "shuffle"; on?: boolean }
  | { cmd: "repeat"; mode?: RepeatMode }
  | { cmd: "like"; target: { kind: "song" | "album" | "artist"; id: string } | "current"; on?: boolean }
  | { cmd: "radio"; seed: { kind: "song" | "artist" | "album"; id: string } | "current" }
  | { cmd: "queue.get" }
  | { cmd: "queue.move"; rev: number; from: number; to: number }
  | { cmd: "queue.remove"; rev: number; indexes: number[] }
  | { cmd: "queue.clear"; rev: number; part: "up-next" | "all" }
  | { cmd: "queue.jump"; rev: number; index: number }
  | { cmd: "queue.restore"; snapshot: QueueSnapshot } // Undo
  | { cmd: "lyrics"; id: string }
  | { cmd: "art"; coverArt: string; bucket: 96 | 256 | 512 }
  | { cmd: "link"; kind: "album" | "artist" | "playlist" | "song"; id: string } // web URL, no secret
  | { cmd: "playlist.add"; playlistId: string; songIds: string[] }
  | { cmd: "output"; sink?: string };

export interface MusicError {
  code: "daemon" | "offline" | "unauthorized" | "forbidden" | "not-found" | "stale-rev" | "nothing-playing" | "usage" | "player";
  message: string; // what happened, U-17
  fix?: string; // what to do
}

/** Responses: `partial: true` lines may precede the final one for search/browse/radio. */
export type MusicResponse =
  | { id: number; ok: true; partial?: boolean; result: unknown }
  | { id: number; ok: false; error: MusicError }
  | { event: "state"; state: PlayerState }
  | { event: "queue"; rev: number }
  | { event: "index"; status: ServerStatus; artists: number; albums: number };
```

Every request is framed `{ "id": n, ...MusicRequest }`. The daemon answers with the same `id`.
`watch` turns the connection into an event stream: one `state` event at once, then an event on each
change. Position is **not** streamed: clients extrapolate `positionMs + (now − positionAt)` while
`status = playing`, and repaint the progress at 4 Hz only while visible.

### 9.3 Host obligations (what the wave-2 launcher does for every provider)

1. **The view stack.** `push`, `pop`, `Esc` and `Backspace` on an empty input, `Shift+Esc` to close.
   The route of each view is restored with its query, scope and cursor row id when popping back.
2. **One `<virtual-list>` per body.** It flattens the sections into header rows, rows and grid rows
   (5 cards each). It is given `itemCount` with an `estimatedItemHeight` of 44 and a `windowStart`
   window of 60 (GPX: windowed list; no wrapper component). `onVisibleRange` drives the window, art
   prefetch and paging.
3. **The cursor model** of §5.3: id-pinned, with `scrollToItem` keeping it visible. Hover sets the
   cursor (hover equals the keyboard cursor, U-11).
4. **Key routing order.** Actions panel (`DismissableLayer`), then `view.keys`, then the shortcuts in
   `actions(row)`, then host defaults. It renders with `tabNavigation: false` and
   `keyboardFocusDim: false` (GPX `WindowKeyEventHandlers`), and the input keeps focus.
5. **Echo, Undo and the error echo** in the footer. The undo closure is kept for 6 s.
6. **The actions panel** (§5.11), built from `actions(row)` plus `view.keys`.
7. **`filtering: "launcher"`.** The host filters loaded rows with the same scoring function as the
   music index (§8). It is exported from `src/launcher/match.ts`, so every provider ranks alike.
8. **Detail pane.** It is shown for layout `list-detail`, and toggled by `Ctrl+I` for the others,
   after the cursor rests for 120 ms.
9. **The `strip` slot** above the footer for the active provider: music's mini-player.
10. **Stale snapshots.** `invalidate("state")` repaints visible rows through `rowState`.
    `invalidate("data")` re-runs `search` for the current query and keeps rows during the reload.

---

## 10. Player semantics the UX promises (the daemon must hold them)

- **Play.** The context is replaced and "Next in queue" is kept. The previous `QueueSnapshot` is
  kept for one Undo.
- **Search song (no container).** Enter plays it, then the rest of its album from the next track
  (Spotify-style autoplay, R01 P0 #2), with the context "Holocene · from search".
- **Next.** "Next in queue" goes first, then the context. At the end of the context:
  - repeat all wraps;
  - a radio, genre or library-shuffle context refills;
  - otherwise playback stops, the status becomes "End of queue", and the chip shows Paused.
- **Previous.** If more than 3 s have played, restart the track; otherwise go back to the previous
  track in history.
- **Shuffle on.** The remaining context is shuffled with Fisher–Yates; the current track stays and
  "Next in queue" is never shuffled. **Shuffle off** restores the context's order after the current
  track.
- **Repeat one** loops the current track (mpv `loop-file=inf`). Next still skips.
- **Gapless.** The daemon keeps mpv's internal playlist as current + next only
  (`--gapless-audio=yes --prefetch-playlist=yes`). The daemon's queue is the truth, and mpv is a
  two-slot window onto it.
- **Volume.** mpv volume 0–100, default 70, kept in `$XDG_STATE_HOME/gpuix-shell/music/state.json`.
  The system volume stays with `~/.local/bin/volume`.
- **Play reporting** (R02 §5.8). `scrobble submission=false` at start; `submission=true` at ≥ 50 %
  or 240 s. This keeps Jump back in, Most played and play counts alive.
- **Resume.** `savePlayQueue` (current id, upcoming ids, position) runs on pause, on track change
  and on daemon stop (signal). `getPlayQueue` restores the queue paused at daemon start; it is the
  "Continue" shelf. No tokenised URL is ever written to disk (R02 §5.7).
- **Likes.** `star`/`unstar` with an optimistic row state. If the server refuses, the row reverts and
  the echo shows the failure (U-09: pending until the authority answers).

---

## 11. Secrets and safety (non-negotiable)

- The credential file is read **only by the daemon**, at request time. It is never copied, cached,
  logged, put in argv, or put in the environment of a child.
- A CSPRNG salt is used per request. Stream and cover URLs exist only in the daemon's memory and are
  passed to mpv **over `mpv.sock`** (`loadfile` over IPC), never on mpv's command line, where
  `/proc/*/cmdline` would show them.
- mpv runs with `--no-terminal --msg-level=all=no` (or `really-quiet`) so that it never prints
  "Playing: <url>" into the journal. Errors are read from IPC `end-file` events and sanitised to
  "Stream failed (HTTP 401)".
- The launcher, rail, CLI and OSD only ever receive ids, metadata, local art paths and Navidrome
  **web** links (`/app/#/…`), which carry no credential.
- Logs strip query strings. A unit test feeds a known fake password through every log, error and
  echo path and asserts that it never appears (§12).
- Unauthorized states name the file path only.

---

## 12. Tests and acceptance

**Pure-logic `bun test` (no compositor, no network; fixtures from recorded, scrubbed JSON):**

| File | Asserts |
|---|---|
| `music/rank.test.ts` | the §8 table: exact > prefix > word-prefix > cross-field (`"davis kind"` finds a "Kind of Blue / Miles Davis" album fixture) > contains > fuzzy > typo; diacritics; `&`/and; Top-result tie-break by type prior |
| `music/search-merge.test.ts` | partial → final snapshot replace; de-dup by id; cursor pinning by id across a merge (U-12); abort drops late yields |
| `music/queue.test.ts` | play keeps "Next in queue"; next/previous 3 s rule; shuffle keeps current and up-next; repeat modes; rev-guarded move/remove refuse stale revs; undo restores the exact snapshot |
| `music/radio.test.ts` | layered sources, ≤ 2 per artist per 10, refill at ≤ 5 |
| `music/format.test.ts` | `5:36`, `1:02:03`, "39 min", "1 h 12 min", "12 plays"/"1 play", middle truncation by character budget (U-17) |
| `music/keymap.test.ts` | every §4 key resolves to the documented command id in each view; no two bindings collide within a view |
| `music/secrets.test.ts` | a fake password and token never appear in logs, errors, echoes, MPRIS metadata, CLI output, or argv handed to `spawn` |
| `music/cli.test.ts` | the exit codes and messages of §6 against a fake daemon socket |
| `launcher/provider.test.ts` | a stub provider through the host model: async-iterable snapshots, invalidate("state") vs ("data"), actions order → Enter/Ctrl+Enter |

**Compositor smoke `tests/gpuix-shell/smoke_music.py`** (only under `runtime-test --render-node
/dev/dri/renderD128`, isolated Sway 1.12, `WLR_RENDERER=gles2`, BRIEF §5 recipe):

1. Start the daemon against a **fake Subsonic server** (a local HTTP fixture that serves the
   scrubbed JSON plus one silent 3 s m4a). The real Navidrome is never written to: no star, no
   scrobble, no savePlayQueue.
2. Open `gpuix-shell launcher --view music`.
3. Type `davis kind` → assert a row with testId `music.music:album:<fixture id>` within 50 ms of the
   keystroke (automation tree).
4. `Enter` → assert the daemon state is `playing`. Assert the strip testId `music.strip` shows the
   title, and the row has the `current` look (aria-description "Playing").
5. Press `Ctrl+K` → the panel lists "Add to queue · Alt Q". Press `Alt+Q` → the footer echo text.
   Press `Ctrl+Z` → the queue count is restored.
6. Push `music/now-playing` and grim it. Then open the rail with the chip mounted and grim it. Store
   both under `docs/gpuix-shell/evidence/music/`.
7. `gpuix-shell music next` from a shell → the state changes and the OSD message reaches a fake
   `shell.sock` listener.

The smoke also decides the two unverified key questions of §4 (`Ctrl+←/→` inside `<input>`, and
`Alt`/`Ctrl+Space` delivery).

**Morning acceptance (Tom, on the strix under runtime-test or on the Zenbook once Q1 is settled):**
items 1–7 of §0.

---

## 13. Build slices and file layout

Seven builders follow this spec. **P0** is the morning demo. **P1** completes Spotify-level parity.
**P2** is delight.

```
pkgs/gpuix-shell/src/
  launcher/provider.ts        §9.1 (owner: wave 2; created here only if absent, then handed over)
  launcher/match.ts           §8 scoring, shared by host local filtering
  music/types.ts              §9.2
  music/subsonic/client.ts    auth, request, error mapping, URL minting (secret boundary)
  music/lexicon.ts            index build, disk cache, stamp
  music/rank.ts  search.ts    §8
  music/art-cache.ts          §3.3
  music/daemon/{server,queue,player-mpv,radio,scrobble,playqueue-sync,mpris,osd}.ts
  music/cli.ts                §6
  music/provider.ts           MusicProvider implements LauncherProvider (thin client)
  music/views/{home,search,album,artist,now-playing,queue,library,playlists,radio,output,pick-playlist}.tsx
  music/ui/{rows,grid,strip,chip,progress,transport,lyrics,format}.tsx|ts
tests/gpuix-shell/smoke_music.py, tests/gpuix-shell/fixtures/subsonic/*
```

| Slice | P | Contents |
|---|---|---|
| A. Daemon core | P0 | client + secrets, mpv over IPC, queue model, ctl.sock, state events, scrobble |
| B. Search | P0 | lexicon, rank, search merge, art cache |
| C. Launcher frame + provider | P0 | §9 types, minimal host if wave 2's is absent (flagged `music-demo host`), Search, Home, actions panel, strip, footer echo/Undo |
| D. Detail views | P0 album, now playing · P1 artist, playlists, library | §5.4–5.9 |
| E. Controls | P0 CLI + root commands · P1 MPRIS, OSD | §6, §7.2 |
| F. Rail chip | P1 | §7.1, exported for the rail owner |
| G. Tests + smoke + fixtures | P0 | §12 |
| later | P2 | radio view polish, lyrics sync, output picker, add-to-playlist, play-queue sync restore, ratings, generate playlist with the local model (`gpuix-shell ask`), Opus over Tailscale (R02 §5.19) |

---

## 14. Assumptions taken (logged in `ASSUMPTIONS.md`, prefix `music:`) and open questions for Tom

Decided here:

1. `Ctrl+Enter` = Open (drill-down), Raycast's secondary-action default. R02 §5.1 had play next,
   which stays `Alt+N` per R01.
2. `Ctrl+L` toggles like on songs, albums and artists. `Ctrl+Shift+S` becomes Shuffle play, because
   R01's Save album / Follow artist fold into `Ctrl+L`. `Ctrl+I` toggles the detail pane, `Ctrl+G`
   goes to the artist, and `Alt+L` likes the current track.
3. The search order is Top result · Songs 4 · Artists 3 · Albums 6 · Playlists 4 (Spotify desktop),
   not Raycast's Artists-first.
4. The server debounce is 60 ms (measured 11–78 ms), and the local index paints first.
5. One daemon (`gpuix-shell music serve`) holds the credential, the index, the art cache and the
   player. The launcher provider holds no secret.
6. The sockets live under `$XDG_RUNTIME_DIR/gpuix-shell/music/`, and the CLI is
   `gpuix-shell music …`. This supersedes R02's `gpuix-music`.
7. The rail chip draws no menu: click opens Now Playing, middle click toggles, the wheel sets the
   volume. This supersedes R01 P1 #19, per the X1 rule.
8. The OSD shows only for transport outside the launcher. The track-change toast is off by default.
9. Position is extrapolated by clients from `positionMs`/`positionAt`, and not streamed.
10. Cover art reaches GPUIX only as local cache paths. The GPX http `src` is deliberately unused.
11. Lyrics use the prose face (Anthropic Serif 15 @ 1.65).

Open for Tom (defaults already taken, so nothing blocks):

- **Q1.** The credential `navidrome-credentials.age` is `strixOnly`, so the Zenbook, where the shell
  runs, cannot read it. The default is to demo on the strix under runtime-test. Deploying to the
  Zenbook needs the client host key added to the secret's recipients and a rekey, and that is Tom's
  call. It is not done tonight.
- **Q2.** `$mod+m` / `$mod+Shift+m` for Music / Now Playing. They are proposed and not activated.
- **Q3.** The LRCLIB lyrics fallback is off by default (it sends artist and title off the box).
- **Q4.** `playlistRole: false`: should the account get playlist editing in Navidrome? Until then,
  "Add to playlist" may answer "Failed".

---

## What was done / not done

- **Done:** I read the GPUIX 0.11.0 native and React type definitions and the CHANGELOG entries for
  `<img>` http `src`, the windowed `<virtual-list>`, `highlight`, layer shell, `anchored` and
  `DismissableLayer`. I read the design digest (KIT) and research notes 01 and 02, and checked Sway
  binds (`$mod+m` is free) and the `media` → `playerctl` path. I ran two read-only Subsonic probes
  (capabilities, counts, latencies, search semantics, radio and lyrics yield), reading the
  credentials at runtime and printing none of them.
- **Not done:** nothing was rendered or built. The wireframes, the key delivery under Sway, the GPUI
  input's handling of `Ctrl+←/→`, `<img>` file paths on a layer surface, synced lyrics on real data
  and every write endpoint (star, scrobble, savePlayQueue, updatePlaylist) are **unverified**.
- **Checked:** both TypeScript blocks of §9, extracted as `src/launcher/provider.ts` and
  `src/music/types.ts`, pass `tsc 5.9.3 --strict --noEmit` against `@types/react`. They were not
  compiled against a host implementation, because none exists yet.
