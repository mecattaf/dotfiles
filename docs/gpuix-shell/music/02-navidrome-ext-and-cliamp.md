# 02 — The Raycast Navidrome extension and cliamp, read end to end

Written overnight 2026-10-20/21 by a music-workflow agent (Claude, all-Opus run) for Tom's
order in BRIEF §5: "a navidrome music selection in the gpuix shell ... raycast+spotify level
searching and playing control from within the launcher".

Sources read in full (nothing summarised from memory):

| Source | Pin | What was read |
|---|---|---|
| raycast/extensions `extensions/navidrome` | commit `c33bf4cb4b9ad70c2b93432ee713ffb7486ed331` | the whole tree via the contents API (17 entries): `package.json`, `README.md`, `CHANGELOG.md`, `src/api.ts`, `src/components.tsx`, `src/search.tsx`, `src/recently-added.tsx`, `src/most-played.tsx`, `src/playlists.tsx` (the two screenshots, the icon and `package-lock.json` were not opened) |
| bjarneo/cliamp | `main` at `5656a55e` (2026-10-18, "feat(ui): add the Ethereal visualizer"); there was no pin, so this is HEAD | `README.md`, `docs/navidrome.md`, `docs/keybindings.md`, `docs/remote-control.md`, `docs/history.md`, `docs/lyrics.md`, `external/navidrome/{client,favorites}.go`, `internal/resume/resume.go`, `config/config.go` (Navidrome section), `player/{player,engine,gapless,nav_buffer,pipeline}.go` (structure), `playlist/playlist.go` (API), `ui/model/{view,layout,init,providers,playback}.go` (layout and resume paths), `main.go` / `providers.go` (wiring), `mediactl/service_linux.go` (MPRIS) |
| Tom's Navidrome | 0.63.2 at `http://music.internal` | read-only probe from the strix (`ping`, `getOpenSubsonicExtensions`, `getScanStatus`, `search3`, lists, `getSimilarSongs2`, `getLyricsBySongId`, `getTopSongs`, `getPlayQueue`, `getArtistInfo2`, `getArtists`). The probe read `/run/agenix/navidrome-credentials` at runtime; no credential value was printed, copied or written. §4 has the numbers. |

---

## 0. In one paragraph

The Raycast extension only **browses**. It has four commands (Search, Recently Added, Most
Played, Playlists), uses three data endpoints (`search3`, `getPlaylists`, `getAlbumList2`)
plus `getCoverArt` image URLs, and every primary
action opens the Navidrome **web UI** in a browser. It cannot play, queue, star or scrobble.
Its best ideas are UI ones: a unified, sectioned search with typed colour tags and cover
thumbnails, a recent-search history shown when the query is empty, and grids for album
lists. cliamp is the reverse. It is a complete **player** (gapless engine, play-next queue,
shuffle and repeat, undo, scrobbling, stars, a resume file, an IPC v2 remote with jobs and
events, MPRIS, headless mode), but its Navidrome search covers songs only, it shows no cover
art, it never uses OpenSubsonic extras (server lyrics, similar songs, server play queue),
and it writes tokenised stream URLs to disk. The gpuix launcher should take Raycast's
search-and-act surface, put a cliamp-grade player daemon behind it (mpv over JSON IPC), and
then add what neither has. §5 ranks those additions.

---

## 1. Raycast Navidrome extension (`c33bf4cb`)

Author `alexandervarney`, MIT, category Media, `platforms: ["macOS"]`. The changelog lists
two releases: "Initial Release" (2026-03-09: Search with recent searches, Recently Added,
Most Played, token auth, open and copy actions) and "Playlists" (2026-07-06: a Playlists
command, playlists in Search, open playlist in Navidrome). Dependencies are
`@raycast/api ^1.83.1`, `@raycast/utils ^1.17.0` and `md5 ^2.3.0`.

### 1.1 Commands

| Command (`name`) | Title | Mode | Raycast view | Data source |
|---|---|---|---|---|
| `search` | Search | view | `List`, `throttle`, sections | `search3` per query, plus `getPlaylists` once, filtered on the client |
| `recently-added` | Recently Added Albums | view | `Grid`, `columns={5}` | `getAlbumList2 type=newest size=40` |
| `most-played` | Most Played Albums | view | `Grid`, `columns={5}` | `getAlbumList2 type=frequent size=40` |
| `playlists` | Playlists | view | `List` | `getPlaylists` |

### 1.2 Preferences (extension level, all required)

| Name | Type | Notes |
|---|---|---|
| `serverUrl` | textfield | trailing `/` trimmed (`replace(/\/+$/, "")`) |
| `username` | textfield | |
| `password` | password | stored by Raycast. The token is derived from it for every call. |

There are no command-level preferences: no result counts, no default action, no stream
format.

### 1.3 Auth and transport (`src/api.ts`)

- Salt: **12 characters** from `[a-z0-9]`, drawn with `Math.random()` (not a CSPRNG), and
  **new on every call**, including every cover-art URL.
- Token: `md5(password + salt)` from the `md5` npm package.
- Query params on every call: `u`, `t`, `s`, `v=1.16.1`, `c=raycast-navidrome`, `f=json`.
- URL: `${serverUrl}/rest/${endpoint}?${params}`, sent as a plain `fetch` GET with no
  timeout, abort or retry.
- Errors: a non-2xx status throws `HTTP error: …`. `subsonic-response.status === "failed"`
  throws `Navidrome API error: <message>`. Commands show these as `showFailureToast`, plus
  an `EmptyView` saying "Check your server URL and credentials in Raycast preferences".
- `toArray()` normalises the old Subsonic habit of returning a single object instead of a
  one-element array.
- `ping()` is defined but **never called**. The extension does not validate its
  preferences.

### 1.4 Endpoints used (exact)

| Endpoint | Params sent | Used by |
|---|---|---|
| `search3` | `query`, `artistCount=5`, `albumCount=10`, `songCount=10` (no offsets) | Search |
| `getPlaylists` | — | Search (fetched once, then filtered by `name`/`comment` substring, top 10), Playlists |
| `getAlbumList2` | `type` (`newest` or `frequent`), `size=40`, `offset=0` | Recently Added, Most Played |
| `getCoverArt` | `id`, `size` (100 in lists, 300 in grids) | every icon and grid tile, as an `<img>` URL with the auth params embedded |
| `ping` | — | defined, unused |

It also builds web-UI deep links (not API calls): `${base}/app/#/artist/{id}/show`,
`/app/#/album/{id}/show` and `/app/#/playlist/{id}/show`. For a song it links to the
album: `/app/#/album/{albumId}/show`, or `/app/#/album/{songId}/show` when `albumId` is
missing, which is a broken link.

### 1.5 View layouts

**Search** (`List`, placeholder "Search artists, albums, songs, and playlists...", `throttle`,
`useCachedPromise(..., { keepPreviousData: true })`):

- Empty query with history: section "Recent Searches" (subtitle = count), rows with a clock
  icon.
- Empty query, no history: `EmptyView` "Search Your Library".
- Results come in four fixed sections, each subtitled with its count, in this order:
  **Artists** (≤5), **Albums** (≤10), **Songs** (≤10), **Playlists** (≤10).
- Row anatomy:

| Kind | Icon | Title | Subtitle | Accessories (right) |
|---|---|---|---|---|
| Artist | cover (rounded) or `PersonCircle` | name | "N albums" | ★ yellow if `starred`; tag **Artist** purple |
| Album | cover (rounded) or `Music` | name | "artist · year" | ★; "N tracks"; tag **Album** blue |
| Song | cover (rounded) or `Music` | title | "artist · album" | ★; `m:ss`; tag **Song** green |
| Playlist | cover (rounded) or `List` | name | comment, or "by owner" | "N tracks"; "1h 23m"; tag **Playlist** orange |

- Errors: "Search Failed" when nothing can be shown, "No Results" for an empty result.

**Recently Added / Most Played** (`Grid`, 5 columns): 300 px cover tiles with the album
title and the artist as subtitle. The search bar filters only the 40 loaded tiles on the
client. Empty states are "Your library appears to be empty" and "Play some music first!".

**Playlists** (`List`): the same `PlaylistItem` row as in Search. The search bar filters on
the client.

### 1.6 Actions and shortcuts

| Key | Action | Where |
|---|---|---|
| `Enter` | Open in Navidrome (`Action.OpenInBrowser`). For songs this is "Open Album in Navidrome". | every item |
| `⌘C` | Copy name or title | every item |
| `⌘⇧C` | Copy web URL | every item |
| `Enter` | Search Again (re-runs a recent query) | recent-search row |
| `⌃X` | Remove from recent searches | recent-search row |
| `⌃⇧X` | Clear all recent searches | recent-search row |

Recent searches live in `LocalStorage["recent-searches"]`: a JSON array, newest first, deduplicated,
capped at **10**. A query is recorded **only when "Open in Navidrome" fires** (`onOpen`).
Copy actions do not record it.

### 1.7 Limitations (all from reading the code; nothing was run, since Raycast is macOS-only)

1. **No playback of any kind**: no play, queue, pause, skip, seek, volume, now-playing or
   controls. Its only verb is "open the web UI".
2. **No drill-down.** Artist → albums → tracks never happens inside Raycast: no
   `push(<Detail/>)`, no `List.Item.Detail` side pane, no tracklists.
3. No star/unstar (stars are shown but cannot be toggled), no rating, no "Liked" view.
4. Fixed, small result caps (5/10/10/10) with no pagination or "show more". Grids hold
   exactly 40 albums.
5. Fixed section order (Artists before Songs, always) with no "top result" or relevance
   ranking across types.
6. No type filter (no `searchBarAccessory` dropdown or prefix syntax).
7. Only two album lists (`newest`, `frequent`). The server's `recent`, `random`, `starred`,
   `byYear` and `byGenre` lists are not used.
8. **Cover-art URLs carry a fresh salt on every render**, so each re-render is a new URL.
   That defeats Raycast's image cache and re-fetches thumbnails. The tokens also end up in
   the image cache.
9. Salt from `Math.random()`. The Subsonic spec only asks for a random salt, but a CSPRNG
   costs nothing.
10. "Search Again" calls `setQuery(recent)`, but the `List` is uncontrolled (no `searchText`
    prop), so results update while the search bar stays empty. `searchTextRef` is dead
    code.
11. No preference validation (`ping` is unused). A wrong password shows up only as a failed
    search.
12. Playlists are fetched once per command open and never refreshed. With Tom's **1,235
    playlists** (measured, §4) that is fine for size but stale after edits.
13. Song links fall back to `album/{songId}`, a broken URL when `albumId` is absent.
14. macOS only.

---

## 2. cliamp (`bjarneo/cliamp` @ `5656a55e`)

cliamp is a Go TUI music player ("inspired by Winamp") built on Bubbletea and Lip Gloss,
with audio through `gopxl/beep`. Navidrome is one of about 20 providers (local, radio,
podcasts, YouTube, Spotify via go-librespot, Qobuz, Tidal, Plex, Jellyfin, Emby, Lyrion,
Audiobookshelf, …). It ships a Nix flake (`nix run github:bjarneo/cliamp`).

### 2.1 Navidrome client (`external/navidrome/client.go`, `favorites.go`)

Auth: an **8-byte `crypto/rand` salt, hex-encoded (16 chars)**, falling back to the
nanosecond clock if `rand` fails. Token is `md5(password + salt)`, new per URL. Params are
`u`, `t`, `s`, **`v=1.0.0`** (understated, since it uses 1.8+ and 1.9+ features), `c=cliamp`
and `f=json`. It sets a fixed `User-Agent` on API calls and the stream download, so
Navidrome registers **one** player for cliamp, which matters for per-player transcoding
settings. HTTP timeout 30 s, response cap 128 MiB, errors via
`subsonic-response.status/error{code,message}`.

Credentials come from the `[navidrome]` section of `~/.config/cliamp/config.toml` (`url`,
`user`, `password` in plaintext, plus `browse_sort`, `format`, `scrobble`) or the
`NAVIDROME_URL`, `NAVIDROME_USER` and `NAVIDROME_PASS` environment variables. `cliamp setup`
validates them with `ping.view`.

| Endpoint | Params | Purpose |
|---|---|---|
| `ping.view` | — | setup wizard, connectivity |
| `getPlaylists` | — | provider pane (cached until `Ctrl+R`) |
| `getPlaylist` | `id` | playlist tracks (cached per id) |
| `getArtists` | — | browser "By Artist" (index flattened) |
| `getArtist` | `id` | an artist's albums |
| `getAlbumList2` | `type`, `offset`, `size` (≤500) | browser "By Album", paged, with 8 sort types: `alphabeticalByName`, `alphabeticalByArtist`, `newest`, `recent`, `frequent`, `starred`, `byYear`, `byGenre` (the chosen sort is saved as `browse_sort`) |
| `getAlbum` | `id` | album tracks |
| `search3` | `query`, `songCount=limit` (default 50), `albumCount=0`, `artistCount=0` | `Ctrl+F` search, **songs only** |
| `stream` | `id`, optional `format` (`raw` bypasses server transcoding; `mp3`/`aac`/`opus` are requests that the server's player transcoding overrides) | playback URL |
| `scrobble` | `id`, `submission=false` (now playing) or `true` with `time` in ms | play reporting (opt out with `scrobble = false`) |
| `star` / `unstar` | `id` | `f` favourite toggle (**local favourite is the source of truth**; stars made in the web UI are not read back) |

Not used: `getCoverArt` (no art anywhere in the TUI), `getLyricsBySongId` (lyrics come from
embedded tags, then LRCLIB, then NetEase), `getSimilarSongs*`, `getTopSongs`,
`getRandomSongs`, `getStarred2`, `getPlayQueue`/`savePlayQueue`, `getArtistInfo2`,
`setRating`, `createPlaylist`/`updatePlaylist`, `getGenres`, `getOpenSubsonicExtensions`.

### 2.2 Feature table (as it applies to Navidrome)

| Area | cliamp behaviour |
|---|---|
| Browse | provider pane lists playlists, `Enter` loads one. `N` opens a full-screen browser with modes By Album / By Artist / By Artist→Album, a breadcrumb header ("Navidrome / Miles Davis / Kind of Blue / Tracks") and right-aligned durations |
| Browser track actions | `Enter` append one, `a` append all, `R` replace the queue and play, `q` play next, `f` favourite, `s` cycle album sort |
| Search | `Ctrl+F` sends the query to `search3` (songs only, 50). The results overlay has `Enter` play now, `a` append, `q` play next, `f` favourite. `/` is a local fuzzy filter (in-order subsequence, ranked) over the visible list |
| Playback | play/pause, stop, next/prev, seek ±5 s / ±30 s, `N j` jumps to N×10 %, `Ctrl+J` jump to time, volume in dB (floor to +6), speed 0.25–2.0×, mono, 10-band EQ with presets, output device picker (`d`) |
| Queue | separate **play-next** list (`a` toggles, `A` manager: reorder, remove, clear), shuffle (play-order view), repeat Off/All/One, `Shift+↑↓` move, `x` remove, `Ctrl+Z` undo |
| Persistence | `resume.json` (track and position), `history.toml` (Recently Played, 200 entries), local favourites, local playlists in TOML, saved album sort |
| Lyrics | `y`: embedded, then LRCLIB, then NetEase. Synced highlighting for Navidrome tracks, `[`/`]` offset ±250 ms (saved) |
| Remote | IPC v2 over `~/.config/cliamp/cliamp.sock` (0600, NDJSON): `state.get`, `operation.submit` (jobs), `job.get`/`cancel`, `subscribe` (events), `spectrum.get`. CLI: `cliamp toggle/next/status --json/remote …` |
| Desktop | MPRIS on Linux (godbus), so media keys and `playerctl` work. `--daemon` headless mode with the same API, Lua plugins (`now-playing.lua`, `webhook.lua`, …) |
| Look | Winamp-like stacked TUI, about 40 visualizers, about 25 TOML themes, layout tiers |

### 2.3 Playback engine (`player/`)

The pipeline, from the `Player` doc comment:

```
[Gapless] -> [Speed] -> [10x Biquad EQ] -> [Tap] -> [Volume + Mono] -> [Ctrl] -> speaker
     ├─ current: [Decode A] → [Resample A]
     └─ next:    [Decode B] → [Resample B]  (preloaded)
```

- **Gapless**: `gaplessStreamer` never stops the speaker. On exhaustion it pulls from the
  preloaded `next`, and with nothing queued it fills silence (`drained`). The model calls
  `BeginPreload`/`PreloadForGeneration` for the next track and `ClearPreload` when
  shuffle, repeat or the queue changes the successor. Generation counters (`playGen`,
  `preloadGen`, `seekGen`) reject stale async starts.
- **Subsonic streams** (`IsSubsonicStreamURL`: `/rest/stream`, `/rest/download`) take the
  **buffered pipeline**. `navBuffer` downloads progressively into a temp file (32 KiB
  chunks, 5 s stall timeout) and ffmpeg decodes from it. That is what gives seeking and
  gapless on HTTP. Live streams take a separate path.
- Volume is in dB; the visualizer tap sits before volume. The `Engine` interface is
  mockable for tests.

The gpuix equivalent is **mpv**: `--gapless-audio=yes`, `--prefetch-playlist=yes` and mpv's
own demuxer cache cover what `gaplessStreamer` and `navBuffer` do. EQ is
`af=lavfi=[equalizer…]`, speed is `speed`, and the device is `audio-device`.

### 2.4 Queue model (`playlist/playlist.go`)

The live playlist is an ordered track list with a shuffle order, plus a play-next queue of
track indexes. `Next()` resolves in the order queue → repeat-one → shuffled or sequential
order (wrapping under repeat-all) and prunes unplayable entries. `PeekNext()` feeds
preload. `Snapshot()`/`Restore()` give undo. `Revision()` is monotonic and is what IPC
`if_revision` checks for optimistic concurrency, returning a `conflict` error for stale GUI
actions. Moving tracks is refused while shuffle is on.

### 2.5 TUI layout (`ui/model/view.go`, `layout.go`)

Rows stack top to bottom. The **full** tier is title, track info, time/status, spectrum
visualizer, seek bar (heavy played cells, light remainder, round head), controls
(Source / Volume / EQ / Shuffle / Repeat / Speed; `Tab` cycles focus), provider pill,
playlist header, playlist, hint bar and bottom status. A **two-column** variant moves the
settings to a right pane beside the playlist, and there is a "closed settings" variant.
Smaller tiers are **compact**, **minimal (40×10)** and **simplified**, and anything smaller
gets a resize message. The marquee title holds at the start of each loop. `Ctrl+K`/`?`
opens a filterable keymap that can run the selected command, which is a command palette
inside a TUI.

### 2.6 Keybindings (Navidrome-relevant subset; full list in `docs/keybindings.md`)

| Key | Action |
|---|---|
| `Space` | play/pause |
| `s` | stop |
| `>` `.` / `<` `,` | next / previous |
| `←` `→` / `⇧←` `⇧→` | seek ±5 s / ±30 s |
| `N` `j` | seek to N×10 % |
| `+` `-` | volume |
| `]` `[` | speed ±0.25× |
| `m` | mono |
| `e` | EQ preset |
| `d` | audio device |
| `Enter` | play selected |
| `a` | toggle play-next |
| `A` | queue manager |
| `x` | remove |
| `⇧↑` `⇧↓` | move |
| `Ctrl+Z` | undo |
| `z` | shuffle |
| `r` | repeat |
| `/` | local fuzzy filter |
| `Ctrl+F` | provider search |
| `N` | Navidrome browser |
| `f` | favourite (stars on the server too) |
| `y` | lyrics |
| `i` | full info |
| `w` | write to a local playlist |
| `Ctrl+S` | save the track file to `~/Music/cliamp` |
| `Ctrl+K` / `?` | command keymap |
| `q` | quit (saves resume) |

### 2.7 `resume.json` (`internal/resume/resume.go`)

It lives at `~/.config/cliamp/resume.json`, mode 0600, written atomically:

```json
{"path": "<track path or stream URL>", "position_sec": 123, "playlist": "<name>",
 "context": [/* full Track list, Jellyfin/Emby only */], "context_index": 4}
```

`SaveState` skips an empty path, a negative position, or position 0 with no context. It
is written on `q`, `SIGINT`, `SIGTERM` and `SIGHUP`, and continuously for Jellyfin and
Emby through `serverResumeSaver`. On start, `SetResume(path, secs)` arms a one-shot seek
that fires when a track with **that exact path** plays.

What this means for Navidrome (code reading, not run):

- The saved `path` **is the stream URL**, with `u`, `t` and `s` embedded. The comment in
  `providers.go` confirms that "history, favorites and saved playlists keep these URLs".
  A Subsonic token+salt pair stays valid until the password changes, so `resume.json`,
  `history.toml`, favourites and saved playlists each hold a **replayable credential**.
- Every `buildURL` call uses a fresh salt, so a Navidrome track fetched again after a
  restart has a **different path**. The equality match in `SetResume` then never fires
  unless the exact old URL is replayed (from history or a saved playlist). Context restore
  (`restoreServerContext`) is implemented only for Jellyfin and Emby. Navidrome resume is
  therefore effectively best-effort.
- Nothing uses the server's own `savePlayQueue`/`getPlayQueue`, so a resume never moves
  between devices.

### 2.8 Limitations relevant to us

1. A TUI only: no cover art, no image grid, no GUI.
2. Navidrome search is **songs only** (no artists, albums or playlists as results) with no
   cross-type ranking.
3. Persists **tokenised URLs** (resume, history, favourites, playlists).
4. Navidrome resume does not survive the per-call salt (above). No server play queue.
5. Stars are local-first and one-way: server stars are never read (`getStarred2` unused).
6. No server-side discovery: no `getSimilarSongs2` radio, `getTopSongs`, `getRandomSongs`,
   or genre or decade shuffles.
7. Server lyrics (`songLyrics` extension) are ignored in favour of LRCLIB and NetEase over
   the network.
8. `v=1.0.0` understates the protocol, and it never queries `getOpenSubsonicExtensions`.
9. Password in plaintext TOML (or the environment). There is no credentials-file mode like
   `/run/agenix/...`.

---

## 3. Endpoint matrix: Raycast vs cliamp vs Tom's server vs what we will call

"Live" means it answered `ok` on Tom's 0.63.2 in the §4 probe.

| Endpoint | Raycast | cliamp | Live on Tom's server | gpuix launcher (proposed) |
|---|---|---|---|---|
| `ping` | defined, unused | setup | ✓ 12 ms | at start, and on a credential-file change |
| `getOpenSubsonicExtensions` | — | — | ✓ (6 extensions) | gate optional features at start |
| `search3` | 5/10/10 | songs ×50 | ✓ 11–52 ms | every keystroke (debounced, aborting the stale request), all types, with paging for "show more" |
| `getPlaylists` | ✓ | ✓ | ✓ 1,235 playlists, 68 ms | cached, refreshed in the background |
| `getPlaylist` | — | ✓ | (not probed) | playlist page, play |
| `getArtists` | — | ✓ | ✓ 11,118 artists, **4.6 MB, ~1 s** | local index only (never on the hot path) |
| `getArtist` / `getAlbum` | — | ✓ | (not probed) | artist and album pages |
| `getAlbumList2` | newest, frequent | 8 types | ✓ newest / recent / frequent | home shelves: Jump back in (`recent`), New (`newest`), Most played (`frequent`), Random |
| `getCoverArt` | ✓ | — | (not probed) | rows, grid, now-playing, track-change toast, cached on disk by `coverArt` id |
| `stream` | — | ✓ | (not probed) | mpv `loadfile` |
| `scrobble` | — | ✓ | (not probed) | now-playing at start, submission at ≥50 % or 4 min |
| `star` / `unstar` / `getStarred2` | shows stars | star only | ✓ (**0 starred today**) | Like toggle, Liked Songs view; the server is the truth |
| `setRating` | — | — | (not probed) | 1–5 from the action panel |
| `getRandomSongs` | — | — | ✓ 12 ms | Shuffle library, "Play something" |
| `getSimilarSongs2` | — | — | ✓ **4 of 8 random artists had results**, ~470 ms | Start radio (artist or song) |
| `getTopSongs` | — | — | ✓ **2 of 8** artists, ~300 ms | artist page "Popular" |
| `getArtistInfo2` | — | — | ✓ ~320 ms | artist page bio and similar artists |
| `getLyricsBySongId` | — | — | ✓ endpoint works, **0 of 8** songs had lyrics | lyrics pane, then LRCLIB fallback |
| `getPlayQueue` / `savePlayQueue` (`…ByIndex` with `indexBasedQueue`) | — | — | ✓ `getPlayQueue` answered; `indexBasedQueue` advertised | queue persistence and cross-device resume |
| `createPlaylist` / `updatePlaylist` | — | — | (not probed; write calls) | Add to playlist, Save queue as playlist |
| `getGenres` / `getSongsByGenre` | — | — | ✓ **3,966 genres** (messy tags) | genre shuffle over the top N by `songCount` only |
| `getScanStatus` | — | — | ✓ 38,524 songs, 12,352 folders | header count, "library updated" hint |
| `getInternetRadioStations` | — | — | ✓ 0 stations | skip |
| `getNowPlaying` | — | — | ✓ 0 entries | optional "who is listening" |

---

## 4. Measured on Tom's Navidrome (strix → `http://music.internal`, 2026-10-20 late evening, one run)

- `ping`: ok, protocol 1.16.1, `type=navidrome`, `serverVersion=0.63.2 (v0.63.2)`,
  `openSubsonic=true`, 12 ms.
- OpenSubsonic extensions advertised: `transcodeOffset` [1], `formPost` [1], `songLyrics`
  [1, 2], `indexBasedQueue` [1], `transcoding` [1], `playbackReport` [1].
  **`apiKeyAuthentication` is not advertised**, so token+salt stays the auth scheme.
- `getScanStatus`: **38,524 songs** (the brief's "~34k" is low), 12,352 folders, last scan
  2026-08-28 (quick).
- `search3` latency: `radiohead` 19 ms (1 artist, 1 album, 2 songs); `mi` 52 ms (30 KB for
  5/10/20); `bea` 16 ms. `kind of blue` returned nothing. That album may simply not be in
  the library; I did not check further. Server search is fast enough for per-keystroke
  queries over the LAN. The Zenbook over Tailscale will add RTT (not measured).
- Song objects carry the full OpenSubsonic field set: `displayArtist`, `artists[]`,
  `albumArtists[]`, `contributors`, `genres[]`, `moods`, `bpm`, `isrc`, `musicBrainzId`,
  `replayGain`, `bitDepth`, `samplingRate`, `channelCount`, `explicitStatus`, `size`,
  `suffix`, `bitRate`, `coverArt`, `path`, …
- In a sample of 6 songs, `replayGain` was `{}` and the formats were mostly lossy (mp3
  128/320, m4a 160). Loudness normalisation from tags will not do much, so mpv
  `--replaygain` is not worth tuning.
- 0 starred items, 0 internet radio stations, and `recent` and `frequent` album lists
  populated (so scrobbles exist).

---

## 5. What more we can add above it (ranked)

Ordered by how much each one moves the demo toward "raycast+spotify level searching and
playing control from within the launcher", weighted by what can be ready by morning. Items
1–6 are the demo, 7–12 make it a daily driver, and 13–20 are the foundation for later.

1. **Actually play, from the launcher, through one player daemon.** `Enter` = play now,
   `Ctrl+Enter` = play next, `Alt+Enter` = add to queue. Make it context-aware the way
   Spotify is: `Enter` on a song from an album or playlist plays that list from that song;
   `Enter` on an artist plays top songs (`getTopSongs`, falling back to that artist's
   albums). Back it with a small music daemon that owns **one mpv** started with
   `--idle --no-video --gapless-audio=yes --prefetch-playlist=yes
   --input-ipc-server=$XDG_RUNTIME_DIR/gpuix-music/mpv.sock` and drives it over JSON IPC
   (`loadfile … append-play`, `playlist-move`, `playlist-remove`, `observe_property
   time-pos/pause/playlist-pos/idle-active`). Stream URLs go to mpv **over IPC, never
   argv**, so the token never shows in `/proc/*/cmdline`. Neither reference has this
   combination: Raycast cannot play, and cliamp has no launcher.
2. **One ranked result list with a Top Result**, not fixed sections. Merge `search3`
   artists, albums and songs with the client-filtered playlists. Score on exact, prefix
   and word-prefix match on `name`/`title`/`displayArtist`, a boost for play count and
   recency (`getAlbumList2 frequent/recent` cached), a boost for stars, and a type prior.
   Show a large Top Result row (cover, type tag, a Play affordance), then grouped sections
   with "show more" paging (`*Offset`). Add type filters by `Tab`-cycling chips
   (All / Songs / Albums / Artists / Playlists) and prefixes (`s:` `al:` `ar:` `p:`).
   Debounce about 60 ms and abort stale requests. Keep Raycast's colour tags and
   accessories (★, track count, duration).
3. **Now Playing in the launcher and on the rail.** A sticky strip at the bottom of the
   launcher (cover, title · artist, a seek bar in cliamp's heavy/light style, elapsed /
   total, ⏮ ⏯ ⏭, volume). Add a rail mini-player slot. Launcher commands that work
   without opening a view: "Pause", "Next", "Previous", "Like current song", "Shuffle
   on/off", "Repeat", "Seek +30 s". Sway `XF86Audio*` bindings call the same verbs.
4. **Raycast-style action panel (`Ctrl+K`) on every row:** Play, Play next, Add to queue,
   Shuffle play, Start radio, Go to artist, Go to album, Add to playlist…, Like/Unlike,
   Rate…, Open in Navidrome (the web deep links from §1.4, with the broken song fallback
   fixed), Copy "Artist – Title", Copy web link. Show each action's shortcut, as Raycast
   does.
5. **Drill-down pages on a navigation stack** (`Enter` pushes, `Esc` pops).
   - Artist: header with cover, a "Popular" list from `getTopSongs`, albums from
     `getArtist` sorted by year, similar artists and a bio from `getArtistInfo2`.
   - Album: tracklist from `getAlbum`, with Play and Shuffle.
   - Playlist: from `getPlaylist`.
   - Breadcrumb in the header, as in cliamp's "Navidrome / Artist / Album".
6. **A home view when the query is empty**, laid out like Spotify's home:
   - "Continue" (the server play queue, item 7)
   - "Jump back in" (`recent` albums)
   - "New in library" (`newest`)
   - "Most played" (`frequent`)
   - "Random albums" (`random`)
   - recent searches, which Raycast already has: capped list, `Ctrl+X` remove one,
     `Ctrl+Shift+X` clear all

   Record a search on any act (play or queue), not only on open. Render the shelves as
   Raycast's 5-column grid, or as horizontal shelves.
7. **A queue view backed by the server play queue.** Show Up Next with play-next items
   first, then the rest of the context, as cliamp separates them. Support reorder
   (`Shift+↑↓`), remove, clear and undo (`Ctrl+Z`, as cliamp does). Persist with
   `savePlayQueue` (the `…ByIndex` variants, since the server advertises
   `indexBasedQueue`) and restore with `getPlayQueue`. Resume then works across a shell
   restart **and** across Navidrome's web UI and phone clients, with no tokenised URLs on
   disk (fixes both cliamp §2.7 problems). Use a cliamp-style revision number on the
   daemon so a stale UI action is refused instead of clobbering the queue.
8. **Play reporting.** `scrobble submission=false` on track start, and `submission=true`
   with `time` at ≥50 % or 4 min. This keeps "Most played" and "Jump back in" alive. The
   server also advertises `playbackReport`; read its spec before switching to it.
9. **Radio and shuffle.** "Start radio" from a song or artist uses `getSimilarSongs2`.
   It returned results for only 4 of 8 sampled artists, so fall back to that artist's
   genres, then to `getRandomSongs`. Keep it endless by refilling when ≤3 tracks remain.
   Also offer "Shuffle library" (`getRandomSongs size=50`), a genre shuffle over the top
   genres by `songCount` (3,966 raw genres is too many to list), and a decade shuffle
   (`getRandomSongs fromYear/toYear`).
10. **Like, Liked Songs and rating**, with the server as the truth. `star`/`unstar` and
    `getStarred2` (cliamp is local-first and one-way). Tom has 0 stars today, so the view
    starts empty. Add `setRating` from the action panel.
11. **Cover art done right.** `getCoverArt id size=…`, cached on disk under
    `$XDG_CACHE_HOME/gpuix-shell/music/art/<coverArt>-<size>`, keyed by the art id and
    **never by the tokenised URL** (fixes the cache-busting in Raycast §1.7.8). Use it in
    rows, grids, the now-playing strip and a **track-change toast** through the shell's
    own notification surface (the mako replacement), with ⏭ and ♥ buttons.
12. **Lyrics pane**: `getLyricsBySongId` first (structured, synced lines are highlighted
    against mpv `time-pos`, with a ±250 ms offset as in cliamp). Server lyrics were absent
    for 8 of 8 sampled songs, so add an optional LRCLIB fallback. It is off by default
    because it sends artist and title off the box; Tom decides.
13. **Playlist management**: "Add to playlist…" opens a fuzzy picker over the 1,235
    playlists (`updatePlaylist songIdToAdd`), plus "Save queue as playlist"
    (`createPlaylist`) and "Remove from this playlist".
14. **Output device and volume** wired to the existing audio stack. List PipeWire sinks,
    set mpv `audio-device`, and reuse the dotfiles' F9 audio picker conventions (commit
    `97ef81a9`, "lifts a near-silent stored volume before routing into a sink") instead of
    inventing a second picker.
15. **MPRIS.** The daemon publishes `org.mpris.MediaPlayer2.gpuix_music` so `playerctl`,
    media keys and Bluetooth headset buttons work, as cliamp's `mediactl` does. mpv has no
    MPRIS script in Tom's profile today (none under `share/mpv/scripts`), so either the
    daemon implements MPRIS or `mpvScripts.mpris` gets added.
16. **A CLI and IPC on the daemon**, mirroring cliamp's v2 shape at a smaller scale:
    `gpuix-music play "<query>"`, `toggle`, `next`, `like`, `status --json`, plus an event
    stream the rail and launcher subscribe to (`state`, `queue`, `position` at about 4 Hz
    only while visible). Sway bindings and scripts use the same verbs as the UI.
17. **Credential hygiene as a feature.** Read `NAVIDROME_CREDENTIALS_FILE` (default
    `/run/agenix/navidrome-credentials`) at runtime and `NAVIDROME_URL` (default
    `http://music.internal`, fallback `http://strix.tail8dd1.ts.net:4533`). Use a
    CSPRNG salt per request, never log or persist a URL that carries `t`/`s`, and
    re-mint stream URLs on demand from song ids. Tom's server has no API-key extension,
    so this is the best available.
18. **A local index for typo-tolerant, zero-RTT search.** Build it in the background from
    `getArtists` (4.6 MB, about 1 s), paged `getAlbumList2` and the playlist list. Add
    songs later; an empty-query `search3` page sync works on Navidrome according to other
    clients' practice, but I have **not verified** that here. Use it for fuzzy matching
    (cliamp's in-order subsequence plus scoring) when `search3` returns nothing or
    returns slowly over Tailscale (typos, transliterations, partial words).
19. **Quality policy by network.** Use `format=raw` on the closet LAN. On Tailscale, use
    Opus at about 128 kbps with `maxBitRate`, relying on the advertised
    `transcodeOffset` (seek inside transcoded streams) and `transcoding` extensions. Read
    their specs before relying on them.
20. **Later, not tonight:** an offline cache or downloads (`download`, cliamp's `Ctrl+S`),
    EQ presets and speed (mpv `af`/`speed`; cliamp has them), multi-select for batch
    queueing (cliamp's mark with `Space`), year/decade grids, and "who's listening"
    (`getNowPlaying`).

Taken from cliamp: gapless and preload, a play-next queue separate from the context,
undo, revision-guarded mutations, headless parity (the UI is just a client of the daemon),
MPRIS, and resume on quit and on signal.

Taken from Raycast: one search box over every type, colour type tags and accessories,
cover thumbnails, recent searches with remove and clear, album grids, Open in web UI and
Copy as secondary actions.

---

## 6. What was and was not verified

- **Verified by running:** the extension's tree listing and file contents at `c33bf4cb`;
  the cliamp clone at `5656a55e`; every §4 number (one probe run from the strix over the
  closet LAN). The probe was read-only (no `star`, `scrobble`, `savePlayQueue` or
  playlist writes) and printed no credential.
- **From code reading only, not executed:** every Raycast limitation in §1.7 (Raycast is
  macOS-only, so nothing could be run); cliamp's resume and salt mismatch and its
  tokenised-URL persistence (§2.7); cliamp's engine and queue semantics.
- **Not verified at all:** the exact endpoint shapes of the `playbackReport`,
  `transcoding` and `indexBasedQueue` extensions (named from the extension list, specs not
  fetched tonight); empty-query `search3` full sync on 0.63.2; Tailscale latency from the
  Zenbook; `getCoverArt` and `stream` responses (not called, to avoid touching playback
  or now-playing state).
- No GUI or compositor test was part of this task, so none ran.
