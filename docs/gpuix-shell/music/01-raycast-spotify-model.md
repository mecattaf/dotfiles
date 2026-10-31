# 01 — The Raycast Spotify interaction model (what "Spotify-level" means)

Research note for the gpuix-shell Navidrome music demo (BRIEF §5: "raycast+spotify level
searching and playing control from within the launcher"). Written overnight 2026-10-20/21 by the
music research agent (Claude Opus, cc2 seat). Nothing here was run against Navidrome; this is a
reading of upstream source plus store screenshots.

**Sources read in full** (sparse clone of `raycast/extensions` at `d0885a53`, 2026-10-20 16:09 +0200,
kept at `/tmp/claude-1000/gpuix-music-ref/raycast-ext/extensions/`):

| Extension | Store page | Installs (store, 2026-10-20) | Last change | Commands |
|---|---|---|---|---|
| `spotify-player` by mattisssa (+38 contributors) | raycast.com/mattisssa/spotify-player | 496,758 | 2026-09-26 "Reduce Library and Playlist Memory Usage" | 35 (10 enabled by default, 25 `disabledByDefault`) + 7 AI tools |
| `spotify-controls` by thomas | raycast.com/thomas/spotify-controls | 46,458 | 2026-10-09 "Previous Track" fix | 22 (all enabled) |
| `navidrome` (baseline we must beat) | raycast/extensions `extensions/navidrome` | — | — | 4 views, **no playback** |

Every file in `spotify-player/src/**` (except the generated 5,125-line `helpers/spotify.api.ts`
OpenAPI client) and `spotify-controls/src/**` was read; the 7 + 1 store screenshots in
`metadata/` were viewed. The Raycast common shortcut table was checked against
developers.raycast.com/api-reference/keyboard. Vicinae's Linux defaults were read from
`/home/tom/Downloads/vicinae/src/server/src/internal/keyboard/keybind-manager.cpp`.

---

## 0. The Raycast primitives both extensions are built from

Knowing these is half the model, because "Spotify-level" in Raycast is mostly these
primitives used well.

| Primitive | Behaviour we must mirror in GPUIX |
|---|---|
| `List` / `Grid` with `searchBarPlaceholder` | One text field on top; results below in titled **sections**; first row auto-selected; ↑/↓ move; Enter = first action. |
| `throttle: true` | `onSearchTextChange` fires after a short typing pause (delay is Raycast-internal and undocumented), not per key. Used by Search. |
| `filtering: true` | Raycast filters already-loaded items locally (fuzzy on title/subtitle), no network. Used by Your Library. |
| `isLoading` | A thin animated loading bar under the search field; previous rows stay visible. |
| `useCachedPromise(fn, args, {keepPreviousData})` | Stale-while-revalidate, **persisted across launches** per argument tuple. Reopening Search with the same query paints instantly from disk, then refreshes. `keepPreviousData` keeps the old result list on screen while the new query loads (no flash of empty). |
| `searchBarAccessory={<List.Dropdown>}` | A category dropdown at the right end of the search field ("All ⌄"). Vicinae opens it with Ctrl+P. |
| `List.Item {icon,title,subtitle,accessories}` | Row = 24-ish px icon (image, optionally circle-masked) · bold title · dim subtitle inline · right-aligned dim accessories (text / icon / tag). |
| `Grid` (`columns={5}`) | Square tiles, image `content`, title + subtitle under the tile; artists use circle mask. |
| `ActionPanel` (⌘K) | Floating panel bottom-right with its own "Search for actions…" field; actions listed with icons and right-aligned keycaps; `ActionPanel.Section` draws a hairline; `ActionPanel.Submenu` opens a nested list. The **first** action is Enter; the second is ⌘Enter. |
| Bottom bar | Left: command icon + command title ("Search", "Now Playing"). Right: primary action title + ↵ keycap, then "Actions ⌘K". |
| `Action.Push` / Esc / `popToRoot` | Navigation stack. Push a new list (e.g. album → songs); Esc or the ‹ arrow pops; `popToRoot` + close is used after "close-on-action" commands. |
| `Detail {markdown, metadata}` | Left: markdown (H1 title, "by Artist", cover image). Right: a metadata column of Label / TagList rows, separated by a vertical hairline. |
| `List.EmptyView {icon,title,description,actions}` | Centred icon + title + description, with its own action panel (e.g. Refresh ⌘R). |
| `showToast` (Animated → Success/Failure) | In-window status at bottom-left: "Playing…" spinner → "Playing" check. Failure toasts may carry a primary action ("Copy Error ⌘T"). |
| `showHUD` | Small dark pill shown **after the window closes** ("Skipped to next", "Volume set to 50%"). Used by every no-view command. |
| `MenuBarExtra` | Menu-bar icon + title, dropdown of items, `Submenu`s, `Section`s, keycap hints; `interval` re-runs the command in background. |
| `LocalStorage` / `Cache` | Small persistent key-value stores (recent searches, TTL'd API cache). |
| `launchCommand` / `updateCommandMetadata` | One command opens another (Now Playing → Search); a background command rewrites its own subtitle in the root list (live "Now: Song - Artist ♥"). |
| Extension/command preferences | Per-command settings (`topView`, `musicOnly`, menu-bar text length …) and one extension-wide `closeWindowOnAction`. |

**Common shortcut constants** (Raycast docs, confirmed by the screenshots):
`Copy`/`CopyDeeplink` ⌘⇧C · `Open` ⌘O · `OpenWith` ⌘⇧O · `Refresh` ⌘R · `Remove` ⌃X ·
`RemoveAll` ⌃⇧X · `ToggleQuickLook` ⌘Y · `New` ⌘N · `Edit` ⌘E · `Duplicate` ⌘D · `Save` ⌘S ·
`Pin` ⌘. · `MoveUp`/`MoveDown` ⌘⌥↑/↓ · `CopyName` ⌘⌥C · `CopyPath` ⌘⌃C.
On Windows every ⌘ becomes Ctrl and ⌥ becomes Alt (the extension declares both).

---

## 1. spotify-player — command inventory

`closeWindowOnAction` (extension-wide checkbox, default **false**): when false, actions show an
in-window toast and the view stays open; when true, actions show a HUD and `popToRoot()`.

| # | Command (`name`) | Title | Mode | Args | Default? | Per-command preferences | What it does |
|---|---|---|---|---|---|---|---|
| 1 | `search` | Search | view (List/Grid) | — (accepts `launchContext.query` / `fallbackText`) | on | `musicOnly` ☐ (hide podcasts/episodes), `topView` ▾ artists (playlists/albums/artists/tracks/shows/episodes) | Unified catalogue search with category dropdown |
| 2 | `yourLibrary` | Your Library | view (List/Grid) | — | on | `Default-View` ▾ All | Saved playlists/albums/artists/songs/shows/episodes |
| 3 | `nowPlaying` | Now Playing | view (Detail) | — | on | — | Current track sheet + all transport actions |
| 4 | `nowPlayingMenuBar` | Menu Bar Player | menu-bar, `interval: 30s` | — | on | `hideIconWhenIdle` ☐, `hideArtistName` ☐, `cleanupTitle` ☐, `maxTextLength` "30", `iconType` ▾ spotify-icon/cover-image | Title in macOS menu bar + dropdown player |
| 5 | `togglePlayPause` | Toggle Play/Pause | no-view | — | on | — | HUD "Paused"/"Playing" |
| 6 | `next` | Next | no-view | — | on | — | HUD "Skipped to next" |
| 7 | `previous` | Previous | no-view | — | on | — | HUD "Skipped to previous" |
| 8 | `devices` | Select Device | view (List) | — | on | — | Spotify Connect device picker |
| 9 | `addPlayingSongToPlaylist` | Add Playing Song to Playlist | view (List) | — (quicklink `launchContext.playlistId`) | off | `duplicateSongCheck` ☐ | Playlist picker for the current song |
| 10 | `removeSongFromPlaylist` | Remove Playing Song from Playlist | no-view (alerts) | — | off | — | Remove current song from its context playlist, confirm, offer skip |
| 11 | `like` | Like | no-view | — | off | — | HUD "Liked {song} by {artist}" / "…has already been liked" |
| 12 | `dislike` | Dislike | no-view | — | off | — | HUD "Disliked {song}" |
| 13 | `volume` | Set Volume | no-view | `volume` text, required | off | — | Validates 0–100; HUD "Volume set to N%" |
| 14–18 | `volume0/25/50/75/100` | Set Volume to N% | no-view | — | off | — | Presets |
| 19–20 | `volumeUp` / `volumeDown` | Turn Volume Up/Down | no-view | — | off | — | ±10 %, clamped |
| 21 | `toggleShuffle` | Toggle Shuffle | no-view | — | off | — | HUD "Shuffle is on/off" |
| 22 | `cycleRepeat` | Cycle Repeat | no-view | — | off | — | off → context → track → off; HUD "Repeat is set to X" |
| 23 | `replay` | Replay | no-view | — | off | — | Seek 0; HUD "Replaying" |
| 24 | `current-track` | Current Track | no-view, `interval: 1m` | — | off | — | Rewrites its own root-list subtitle to `Song - Artist ♥/♡` |
| 25 | `startRadio` | Start Radio | no-view | — | off | — | Recommendations seeded by current track; HUD "Playing Radio" |
| 26 | `copyUrl` | Copy URL | no-view | — | off | — | Clipboard html `<a>` + text URL; HUD |
| 27 | `copyArtistAndTitle` | Copy Artist and Title | no-view | — | off | — | Clipboard `Song · Artist` |
| 28 | `justPlay` | Just Play | no-view | `query` text, required ("Song / Artist") | off | — | First track hit → play; HUD "Playing X by Y" / "No results for q" |
| 29 | `queue` | Queue | view (List) | — | off | — | Upcoming items |
| 30 | `generatePlaylist` | Generate Playlist | view (List) | `description` text, optional | on | — | Raycast AI → 10 songs → resolve → play/queue/save/tune |
| 31 | `startDJ` | Start DJ | no-view | — | off | — | Spotify DJ playlist via AppleScript |
| 32 | `copyEmbed` | Copy Embed Code | no-view | — | off | — | iframe snippet |
| 33–34 | `skip15` / `back15` | Skip/Back 15 Seconds | no-view | — | off | — | Seek ±15 s (past end → next) |
| 35 | `findLyrics` | Find Lyrics | view (Detail) | — | on | — | LRCLIB lookup for the current song |

AI tools (Raycast AI "@spotify …"): `search`, `play`, `get-current-user`, `get-current-track`,
`create-playlist`, `add-track-to-playlist`, `queue`.

## 2. spotify-controls — command inventory

All AppleScript against the Spotify macOS app; every no-view command first calls
`closeMainWindow({clearRootSearch:true})` so the launcher disappears before the script runs ("keeps
the UI snappy").

| Command | Title | Mode | Args / prefs | Feedback |
|---|---|---|---|---|
| `play` / `pause` / `playPause` | Play / Pause / Toggle Play/Pause | no-view | — | none (window just closes) |
| `nextTrack` / `previousTrack` | Next Track / Previous Track | no-view | pref `nextTrackNotificationEnabled` / `previousTrackNotificationEnabled` ☐ | optional HUD `🎧 Song by Artist` (or `… (Paused)`) |
| `current` | Current Track | no-view | — | HUD `🎧 Song by Artist` / "Not playing" |
| `forwardXseconds` / `backwardXseconds` | Skip Forward / Skip Backward | no-view | pref `secondsToSkip` "15" | none; only while playing |
| `backwardToBeginning` | Backward to the Beginning | no-view | — | none |
| `increaseVolume` / `decreaseVolume` | Increase/Decrease Volume | no-view | optional arg `step` (placeholder 10); pref `volumeStep` "10" | none |
| `muteVolume`, `quarterVolume`, `halfVolume`, `threeQuartersVolume`, `fullVolume` | Mute / Set Volume to 25/50/75/100% | no-view | — | none |
| `copyUrl` | Copy Current Track URL | no-view | — | toast "Copied URL to clipboard" |
| `shuffle` / `repeat` | Toggle Shuffle / Toggle Repeat | no-view | — | toast "Shuffle On/Off", "Repeat On/Off" |
| `shufflePlay` | Shuffle Play | no-view | — | sets shuffle and starts playing |
| `privateSession` | Toggle Private Session | no-view | — | toast (clicks the app's menu via System Events) |
| `menuBarPlayer` | Menu Bar Player | menu-bar, `interval: 10s` | `hideIconWhenIdle`, `hideArtistName`, `cleanupSongTitle`, `nowPlayingTextLength` "30", `menuBarIcon` ▾ spotify/artwork/music, `showTextInMenuBar` ☐ | — |

Two behaviours worth copying verbatim:

- **Previous semantics:** "Spotify's previous restarts the current track when it has been playing
  for more than ~3 s, so … we check the player position and run the command twice if it's greater
  than 3 seconds." (`previousTrack.ts`). spotify-controls makes Previous *always* go to the previous
  track; Spotify's own semantics (restart when > 3 s) are the more familiar ones. We implement
  Spotify's rule and make it explicit (§8 B6).
- **Root-search presence:** each control is a root command (screenshot: typing "spotify controls"
  lists Pause / Copy Current Track URL / Toggle Play/Pause / Current Track / Play / Next Track /
  Previous Track / Shuffle Play / Toggle Repeat / Toggle Shuffle, each with the Spotify icon,
  subtitle "Spotify", accessory "Command", primary action "Open Command"). Fast control = type 2–3
  letters in the launcher root and press Enter; a separate "music mode" is not needed for it.

---

## 3. Search (spotify-player `search.tsx`)

### 3.1 States and layout

| State | Container | Content |
|---|---|---|
| Empty query | `List` | `EmptyView` "What do you want to listen to?" + section **Recent searches** (≤10 rows) |
| Query, filter **All** | `List` (throttled, `keepPreviousData`) | Sections in order: `topView` first (default **Artists**), then the remaining types in the order Artists 3 · Songs 4 · Albums 6 · Playlists 6 (+ Liked Songs row first) · Podcasts & Shows 3 · Episodes 3 |
| Filter **Songs** / **Playlists** / **Episodes** | `List` | That section, all items returned (≤50) |
| Filter **Artists** / **Albums** / **Podcasts & Shows** | `Grid`, 5 columns, small inset for artists | Tiles with cover (circle for artists) |

- Placeholder: "What do you want to listen to" (search), dropdown tooltip "Filter search", items
  All · Artists · Songs · Albums · Playlists · Podcasts & Shows · Episodes (`musicOnly` removes the
  last two and coerces `topView` to artists).
- The API request is always `search(q, [track,artist,album,playlist,show,episode], limit 50)`: **one
  request, all types, 50 each**; filters only change how much is displayed. No pagination.
- Null items are filtered out of every category (Spotify returns `null` holes).
- The filter is kept when the query changes; the view switches List ↔ Grid when the filter does.

```
┌──────────────────────────────────────────────────────────────────────┐
│ ‹  bon iver▌                                               All ⌄     │  search field + dropdown
├──────────────────────────────────────────────────────────────────────┤  ▁▁▁▁ loading bar while fetching
│ Artists                                                              │
│▌(◉) Bon Iver                                                         │  circle-masked photo
│ (◉) Justin Vernon                                                    │
│ (◉) Ben Howard                                                       │
│ Songs                                                                │
│ [▣] Skinny Love            Bon Iver                          03:58   │  icon=smallest album art
│ [▣] exile (feat. Bon Iver) Taylor Swift                      04:45   │  subtitle=artists ", "
│ [▣] The Wolves (Act I and II)  Bon Iver                      05:22   │  accessory=mm:ss
│ [▣] re:stacks              Bon Iver                          06:41   │
│ Albums                                                               │
│ [▣] i,i                    Bon Iver · 2019                10 songs   │  subtitle=artists · YYYY
│ … (6)                                                                │
│ Playlists                                                            │
│ [♥] Liked Songs                                            9 songs   │  pseudo-playlist, always first
│ [▣] Quiet Mornings         Alex                           32 songs   │  subtitle=owner
├──────────────────────────────────────────────────────────────────────┤
│ (S) Search                                  Play ↵ │ Actions ⌘ K     │  bottom bar
└──────────────────────────────────────────────────────────────────────┘
```

Grid filter (Artists / Albums), screenshot 04/05:

```
┌──────────────────────────────────────────────────────────────────────┐
│ ‹  bon iver                                             Artists ⌄    │
│ Artists                                                              │
│ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐                         │
│ │ (◉)  │ │ (◉)  │ │ (◉)  │ │ (◉)  │ │ (◉)  │   5 columns              │
│ └──────┘ └──────┘ └──────┘ └──────┘ └──────┘                         │
│ Bon Iver  Justin V. Ben Howard …                 title (+ subtitle for │
│ ┌──────┐ ┌──────┐ …                             albums: "Bon Iver · 2019")
└──────────────────────────────────────────────────────────────────────┘
```

### 3.2 Recent searches

- Stored in `LocalStorage["recent-searches"]` as a JSON array, newest first.
- Added when `query.length > 3`, not already present, and the search has finished loading; the
  write is debounced **3 s** (so only the settled query is stored).
- Shown only when the field is empty, at most 10.
- Row actions: **Search Again** (Enter, sets the field) · section · **Remove Search** ⌃X
  (destructive) · **Remove All Searches** ⌃⇧X → confirm alert "Are you sure? This will remove all
  recent searches." [Remove] [Cancel] with "don't ask again" (`rememberUserChoice`).

### 3.3 Item layouts and action panels (shared by Search, Library, drill-downs)

| Type | Icon | Title | Subtitle | Accessories | Grid tile |
|---|---|---|---|---|---|
| Artist | largest image, **circle mask**, fallback dot | name | — | — | circle image + name |
| Album | largest cover | name | `Artist, Artist · YYYY` | `N songs` | cover + title + subtitle |
| Song | **smallest** album image | name | artists joined `, ` | `mm:ss` (`hh:mm:ss` ≥1 h) | (list only) |
| Playlist | smallest image, fallback blank doc | name | owner display name | [green ✓ "Already in playlist"] + `N songs` | cover |
| Liked Songs (pseudo) | Spotify liked-songs art | "Liked Songs" | — | `N songs` | — |
| Show | cover | name | — | `N episodes` | cover |
| Episode | show/episode image | name | — | `mm:ss` | (list only) |

Action panels (first row = Enter; `—` = section hairline). Shortcuts as on macOS.

| Item | Actions |
|---|---|
| **Artist** | Play ↵ · Show Albums ⌘⇧A (→ Albums grid) · Show Popular Songs ⌘Y (→ Songs list) · Start Radio ⌘⇧R · — · Copy URL ⌘⇧C · Copy Embed Code ⌘⇧E · Copy Artist and Title ⌘⇧T (copies the name) · Open on Spotify ⌘O |
| **Album** | Play ↵ · Show Songs ⌘⇧A · Add to Library ⌘⇧S / Remove from Library ⌘⇧D (state-dependent; afterwards HUD + close) · — · footer (Copy URL, Embed, Copy title, Open) |
| **Song** | Play ↵ · Go to Album ⌘⇧A (only outside album view) · Start Radio ⌘⇧R · Like ⌘L **or** Dislike ⌘D (one of them, from a live "is saved?" check; only in Search/Library rows) · Add to Queue ⌥Q · Add to Playlist ⌘A (→ playlist picker) · — · footer |
| **Playlist** | Play ↵ · Show Songs ⌘⇧A · — · footer |
| **Liked Songs** | Play ↵ (context = the user's collection) · Show Songs ⌘⇧A · — · footer |
| **Show** | Play ↵ · Show Episodes ⌘⇧A · — · footer |
| **Episode** | Play ↵ · Add to Queue ⌥Q · — · footer |

Play semantics (`api/play.ts`, `PlayAction.tsx`):

- Song in Search/Library → plays **that one track** (`uris:[track]`).
- Song inside an album or playlist list → plays the **context from that track**
  (`context_uri` + `offset.uri`), so the rest of the album/playlist follows.
- Optional `tracksToQueue`: one call `play({uris:[this, ...others]})` instead of N queue calls.
- Album / playlist / artist / show → plays the context (artist = Spotify's artist context).
- No active device → AppleScript launches Spotify, then retries the Web API up to 5× (1 s min
  backoff) only for the transient "no active device" error; permanent errors bail.
- Feedback: toast "Playing…" (animated) → "Playing" (success); failure toast title "No active
  device" or "Failed to play" with primary action **Copy Error ⌘T**. With `closeWindowOnAction`:
  HUD "Playing" / "Failed to play" + close.

### 3.4 Drill-down views (pushed onto the stack)

| View | Container | Placeholder | Source | Limit | Notes |
|---|---|---|---|---|---|
| Albums of artist | Grid (default 5 col), one section titled with the artist name | "Search albums" | artist albums | 50 | Intends newest-first; the comparator is malformed (`sort(a => Date.parse(…))`) so the order is effectively the API's. We sort properly by year, descending. |
| Songs (album / playlist / popular / liked) | List, local filtering | "Search songs" | album tracks / playlist tracks / given list | album 50, playlist 500 (paged 50) | Rows are Song rows; Play uses the album/playlist as context. Like/Dislike is **not** offered in these rows (only in Search/Library rows). We offer it everywhere. |
| Episodes of show | List | "Search episodes" | show episodes | — | Empty: "No Podcast Details / Spotify did not return details for this podcast." |

---

## 4. Your Library (`yourLibrary.tsx`)

- Same layout grammar as Search; placeholder "Search your library"; dropdown order
  **All · Playlists · Albums · Artists · Songs · Podcasts & Shows · Episodes**; initial filter from
  the `Default-View` preference.
- `filtering: true` → typing filters loaded rows locally; no network per keystroke.
- **All**: sections Playlists · Albums · Artists · Liked Songs · Podcasts & Shows · Saved Episodes,
  **6 rows each while the field is empty, unlimited once you type**. Artists/Albums/Shows switch to
  a 5-column Grid when filtered to that category.
- Data per category is fetched in parallel (`Promise.all`) for All, or alone for a single category.
- Sources: user playlists (all pages), saved albums, followed artists, saved tracks (first 50 only),
  saved shows, saved episodes — each TTL-cached 5 min.

```
┌──────────────────────────────────────────────────────────────────────┐
│ ‹  Search your library…▌                                   All ⌄     │
│ Playlists                                                            │
│▌[♥] Liked Songs                                            9 songs   │
│ [▣] Quiet Mornings        Alex                            32 songs   │
│ [▣] Indie Favourites      Alex                            54 songs   │
│ Albums                                                               │
│ [▣] i,i                   Bon Iver · 2019                 10 songs   │
│ [▣] 22, A Million         Bon Iver · 2016                 10 songs   │
│ Artists …   Liked Songs …   Podcasts & Shows …   Saved Episodes …    │
├──────────────────────────────────────────────────────────────────────┤
│ (S) Your Library                            Play ↵ │ Actions ⌘ K     │
└──────────────────────────────────────────────────────────────────────┘
```

---

## 5. Now Playing (`nowPlaying.tsx`) — the "player sheet"

`Detail` view, loaded once on open (no live progress, no auto-refresh; it revalidates after its own
actions). Only `currentlyPlaying` is fetched first; devices, playlists, the profile, "is liked" and
"which playlists contain it" are deferred until track data exists (1 API call on mount).

```
┌──────────────────────────────────────────────────────────────────────┐
│ ‹                                                                    │
│                                              │ Track                 │
│  For Emma                       (H1)         │ For Emma              │
│  by Bon Iver                                 │ Duration              │
│                                              │ 03:40                 │
│        ┌──────────────────────┐              │ Artist (or Artists)   │
│        │                      │              │ Bon Iver              │
│        │  album art 250×250   │              │ Album                 │
│        │                      │              │ For Emma, Forever Ago │
│        └──────────────────────┘              │ Liked                 │
│                                              │ ♡̸ No   (♥ Yes / ◷ Checking… / ? Unknown)
│                                              │ In Playlists          │
│                                              │ [▣ Quiet Mornings] [▣ …]  (TagList)
├──────────────────────────────────────────────┴───────────────────────┤
│ (S) Now Playing                            Pause ↵ │ Actions ⌘ K     │
└──────────────────────────────────────────────────────────────────────┘
```

Action panel, in order:

| Action | Shortcut | Notes |
|---|---|---|
| Pause / Play | ↵ | state-dependent single action |
| Dislike / Like | ⌘D / ⌘L | state-dependent; tracks only |
| Next | ⌘→ | toast "Skipped to next", revalidate, debounced menu-bar refresh (5 s) |
| Previous | ⌘← | toast "Skipped to previous" |
| Start Radio | ⌘⇧R | seeded by track + first artist; waits 300 ms then revalidates |
| Go to Album | ⌘⇧A | pushes the album's Songs list |
| Add to Playlist | ⌘A | pushes the playlist picker |
| Connect Device ▸ | ⌘⇧K | submenu of non-restricted devices; active = speaker-on icon, others dimmed speaker-off |
| — Copy URL / Copy Embed Code / Copy Artist and Title / Open on Spotify | ⌘⇧C / ⌘⇧E / ⌘⇧T / ⌘O | footer |

Episode variant: markdown H1 = show name, then episode name, image, description; metadata Title /
Name / About; no like/next/radio block.

Empty state: `List.EmptyView` icon ♪ "Nothing is playing right now", actions **Your Library ⌘⇧L**,
**Search ⌘⇧F**, **Refresh ⌘R** (they `launchCommand` the other commands).

---

## 6. Menu-bar players

### 6.1 spotify-player `nowPlayingMenuBar` (interval 30 s in the manifest; the README still says 10 s)

Menu-bar title = `formatTitle`: `Song · Artist` (or `Song` with `hideArtistName`), optional
`cleanupSongTitle` (cut at the first `(`, `[`, ` - ` or `feat./ft./featuring`), truncated to
`maxTextLength` (default 30, `0` = icon only) + `…`. Icon = Spotify glyph or the smallest cover
(rounded) with `iconType = cover-image`.

```
            ┌──────────────────────────────┐
  (S) For Emma · Bon Iver   ◀ menu-bar item │
            ├──────────────────────────────┤
            │ ⏸ Pause                      │  (▶ Play when paused)
            │ ♡ Like                       │  (Dislike when liked)
            │ ⏭ Next                       │
            │ ⏮ Previous                   │
            │ ♪ Start Radio                │  (episodes: ↻ Skip 15 s / ↺ Back 15 s)
            │ ≡ Add to Playlist          ▸ │  owned playlists: ✓ green = contains → click removes
            │ ▯ Connect Device           ▸ │  devices: speaker-on green = active
            ├──────────────────────────────┤
            │ ⤢ Now Playing                │  opens the Now Playing view
            ├──────────────────────────────┤
            │ 🔗 Copy URL            ⇧⌘C   │
            │ </> Copy Embed Code    ⇧⌘E   │
            │ (S) Open on Spotify     ⌘O   │
            ├──────────────────────────────┤
            │ Configure Command       ⌘,   │
            └──────────────────────────────┘
```

Idle states: while loading it renders `isLoading` (never `null`, so the item does not blink away);
Spotify not running → "Spotify needs to be opened" + **Open Spotify**; nothing playing, or data
older than 2 h and not playing → "Nothing is playing right now" + **Your library** · **Search** ·
**Open Spotify**; `hideIconWhenIdle` hides the item entirely in both.

Cost discipline: reads the app state through AppleScript first (free); the Web API is called only
when the URI changed; playlists/devices/liked lookups run only when the user opens the menu
(`LaunchType.UserInitiated`), not on the 30 s background tick.

### 6.2 spotify-controls `menuBarPlayer` (interval 10 s)

Icon from `menuBarIcon` (Spotify / track artwork / ♪), optional title `Song by Artist`
(`showTextInMenuBar`), truncated to `nowPlayingTextLength`; `cleanupSongTitle` strips
"- Remastered 2011", "(… Version)", "[… Remaster]".

```
  (S) Song by Artist ▾
  ┌───────────────────────┐
  │ Song by Artist        │  (or "Not playing"; info row, no action)
  ├───────────────────────┤
  │ ⏸ Pause / ▶ Play      │
  │ ⏭ Next                │
  │ ⏮ Previous            │
  ├───────────────────────┤
  │ Configure Command      │
  └───────────────────────┘
```

---

## 7. The remaining views

### 7.1 Queue (`queue.tsx`, disabled by default)

List of upcoming items (Song rows / Episode rows, full Song action panel each); no reorder, no
remove (Spotify's API has neither), no "now playing" row. Error: EmptyView "Unable to load queue" +
error text + Refresh ⌘R. Empty: EmptyView "Queue / Your queue is empty." + Refresh ⌘R.

### 7.2 Select Device (`devices.tsx`)

```
┌──────────────────────────────────────────────────────────────────────┐
│ ‹  Search…                                                           │
│ 🔊 MacBook Pro     Computer                                  Active  │
│▌🔇 iPhone          Smartphone                                        │
│ 🔇 Living Room     Speaker                                           │
├──────────────────────────────────────────────────────────────────────┤
│ (S) Select Device                   Connect to iPhone ↵ │ Actions ⌘K │
└──────────────────────────────────────────────────────────────────────┘
```

Row: icon speaker-on (active) / dimmed speaker-off; title name; subtitle type; accessory "Active".
Actions: **Connect to {name}** (only for inactive rows; revalidates after 500 ms) · **Refresh ⌘R**.
Error: "Unable to load devices"; empty: "No devices found / You don't have any devices connected to
your account."

### 7.3 Add Playing Song to Playlist (`addPlayingSongToPlaylist.tsx` + `PlaylistPicker.tsx`)

List "Search for Playlist" of **owned** playlists only. Selecting a row (`onSelectionChange`)
starts an abortable membership check (version snapshot + paged scan, at most 2 requests in flight);
the row then shows ✓ "Already in playlist". The single action reads "Add or Remove from Playlist"
until checked, then **Add to Playlist** (+) or **Remove from Playlist** (−). On run it re-checks the
playlist version; if the playlist changed elsewhere it refreshes and fails with "Playlist Changed —
choose the updated action". Second action: **Create Quicklink to Add to {playlist}** (a deep link
that later adds the playing song to that playlist with no UI; optional duplicate check with a
"Add to playlist anyways" toast action). Nothing playing → EmptyView "Nothing is playing right now"
with Your Library / Search (and Retry after a failed quicklink add).

### 7.4 Remove Playing Song from Playlist (no-view, alerts)

Failure toasts for nothing playing / episode / no track / not in a playlist context. Otherwise
confirm "Remove Song — … This will delete every instance of the song." [Remove] (remembered), then
"Skip Song — "{name}" has been removed from the playlist. Do you want to skip to the next song?"
[Skip].

### 7.5 Find Lyrics (`findLyrics.tsx`)

Detail; navigation title `Song - Artist`; markdown `# Song`, **Artist:**, **Album:**, `---`, one
paragraph per non-empty lyric line. Source LRCLIB `/api/get?track_name&artist_name&album_name&duration`
(10 s timeout; synced timestamps stripped; "Instrumental" shown for instrumentals). Actions: Copy
Lyrics ⌘C · Copy Song Info ⌘⇧C · Search Web for Lyrics ⌘S. Error page: "# Error … ## Tips".

### 7.6 Generate Playlist (`generatePlaylist.tsx`)

List whose search field doubles as the prompt box ("Search songs or enter a prompt to
generate/tune"). Flow: Raycast AI (Perplexity Sonar) returns minified JSON `{name, description,
tracks:[{name, artists}]}` for 10 songs → each resolved by `track:… artist:…` search (first hit) →
list. Sections:

```
│ Actions                                                              │
│  ✦ Tune: "more upbeat"          Press Enter to apply   (when typing) │
│  ▶ Play Playlist                                                     │
│  + Add Playlist to Spotify      (→ toast with "Play {name}" action)  │
│  ≡ Add Songs to Queue           (starts playback if no device)       │
│  ↺ Revert to Previous Version   "previous prompt"                    │
│  ↻ Redo Next Version            "next prompt"                        │
│  ◷ View Tune History            N versions  (→ list, ✓ current, tag "Current") │
│ {Playlist name}                 (Song rows)                          │
│ Generation History              (archived generations: View / Delete)│
```

Errors: section "Error" with "Generation Error" + red tag "Failed", "Retry: "{prompt}"" and "Keep
Previous Version".

### 7.7 No-view feedback strings (spotify-player)

| Situation | HUD / toast |
|---|---|
| any track command, nothing playing | "Nothing is currently playing" |
| player command without a device | "No active device" |
| volume arg not numeric / out of range | "Volume must be a number" / "Volume must be between 0 and 100" |
| volume ok | "Volume set to N%" |
| like on an episode | "Liking episodes is not supported yet" |
| like twice | "{song} by {artist} has already been liked" |
| shuffle / repeat | "Shuffle is on/off", "Repeat is set to off/context/track" |
| copy | "Copied URL to clipboard", "Copied artist and track title to clipboard" |
| just play | "Playing {song} by {artist}" / "No results for {q}" |
| seek | "Skipped ahead 15 seconds" / "Skipped back 15 seconds" / "Replaying" |

---

## 8. Data, caching, debounce, pagination (what makes it feel fast)

| Mechanism | spotify-player detail | Our equivalent |
|---|---|---|
| Search debounce | `List throttle` + `useCachedPromise([query], {keepPreviousData})`, `execute` only when the query is non-empty | 120 ms debounce, abort the in-flight `search3` on the next keystroke, keep the old rows, loading bar |
| Persistent SWR | `useCachedPromise` persists the last result per args across launches | in-memory LRU keyed by `(view, filter, query)` + optional on-disk snapshot of Library/recents; paint cached first, revalidate |
| TTL cache | `withCache(key, ttl)`: currently-playing 10 s, devices 30 s, me 1 h, playlists 5 min (shared in-flight promise), library categories 5 min | starred/playlists 5 min, invalidated by our own star/playlist mutations; now-playing comes from mpv IPC events (no polling) |
| Invalidation | like/unlike clears `library:tracks`, `currently-playing`, `liked:<ids>`; playlist add/remove clears `playlists` | same keys, Subsonic edition |
| Rate limit | global 429 back-off honouring `Retry-After`, one retry | LAN server: one retry on network error, then the error state |
| Deferred secondary fetches | Now Playing loads track first, then devices/playlists/me/liked/membership | same order: track + art first, then starred flag, then playlist membership |
| Pagination | none in lists; playlists fetched across all pages; playlist tracks ≤500; album tracks ≤50; saved tracks first 50 only | needed: 34k tracks. Filtered Songs/Albums/Artists views page with `songOffset`/`albumOffset`/`artistOffset` on scroll-to-bottom ("infinite list") |
| Membership scan | sequential, ≤2 concurrent, abortable, never caches whole playlists | `getPlaylist` per owned playlist (Navidrome playlists are small; cache 5 min) |
| Menu-bar economy | AppleScript first; API only on URI change; heavy lookups only when the menu opens | the rail widget listens to mpv/MPRIS property changes; no timers (also: BRIEF forbids new timers in dotfiles) |

---

## 9. Mapping Spotify concepts onto Navidrome 0.63.2 (OpenSubsonic) + mpv

Auth for every call: `u`, `t = md5(password + salt)`, `s = salt`, `v = 1.16.1`, `c = gpuix-shell`,
`f = json` (as the Raycast Navidrome extension does), credentials read at runtime from
`NAVIDROME_CREDENTIALS_FILE` (default `/run/agenix/navidrome-credentials`), base URL from
`NAVIDROME_URL` (default `http://music.internal`). Stream and cover URLs carry the token: pass
them to mpv over its **IPC socket** (`loadfile`), never on mpv's command line (visible in
`/proc/*/cmdline`), and never log them.

| Spotify concept (Raycast) | Navidrome / OpenSubsonic call | Player side (mpv JSON IPC) |
|---|---|---|
| search (all types, one call) | `search3?query&artistCount&albumCount&songCount` (+ `*Offset` for paging); playlists are **not** in search3 → `getPlaylists` once, filter locally | — |
| artist → albums | `getArtist?id` (`album[]`) | — |
| artist → popular songs | `getTopSongs?artist=<name>&count` (needs Navidrome's Last.fm agent; can be empty → fall back to the artist's songs by `playCount`) | — |
| album → songs | `getAlbum?id` (`song[]`) | — |
| playlist → songs | `getPlaylist?id` (`entry[]`) | — |
| play track / context | stream URL `rest/stream?id=…` | `loadfile <url> replace` then `loadfile <url> append` for the rest of the context; `playlist-play-index` to start mid-context |
| add to queue / play next | — | `loadfile <url> append` / `loadfile <url> insert-next` (mpv ≥ 0.38; installed 0.41); we own the queue, so reorder/remove/clear are also possible (`playlist-move`, `playlist-remove`, `playlist-clear`) |
| queue view | — | `get_property playlist` + our song metadata keyed by id |
| now playing | `getCoverArt?id&size`, song metadata we enqueued | `observe_property` `time-pos`, `duration`, `pause`, `playlist-pos`, `volume`, `mute`, `loop-file`, `loop-playlist` |
| play/pause, next, previous | — | `cycle pause`, `playlist-next`, `playlist-prev` (Spotify rule: if `time-pos > 3` → `seek 0 absolute`) |
| seek ±15, replay | — | `seek 15` / `seek -15` / `seek 0 absolute` |
| shuffle | — | `playlist-shuffle` / `playlist-unshuffle` |
| repeat cycle off→context→track | — | `loop-playlist=no/inf` + `loop-file=no/inf` |
| volume set/±10/presets | — | `set volume N` (player volume; system volume stays with `~/.local/bin/volume`) |
| like / dislike (saved tracks) | `star?id` / `unstar?id`; state from `song.starred` | — |
| save album / follow artist | `star?albumId` / `star?artistId` | — |
| Liked Songs | `getStarred2` → `song[]` | — |
| Your Library | `getStarred2` (artists, albums, songs) + `getPlaylists` + `getAlbumList2?type=newest|recent|frequent|random|highest` | — |
| start radio | `getSimilarSongs2?id=<artistId>` / `getSimilarSongs?id=<songId>` (Last.fm-dependent) → fallback `getRandomSongs?genre=<seed genre>` | replace queue |
| add/remove playlist entry | `updatePlaylist?playlistId&songIdToAdd` / `&songIndexToRemove` (indexes, so read `getPlaylist` first); `createPlaylist?name&songId…` | — |
| devices / transfer playback | none (Spotify Connect has no Subsonic equivalent; Navidrome jukebox mode would play on the headless strix) | PipeWire sinks: `audio-device-list` → `set audio-device`; or reuse `~/.local/bin/audio-route` (the F9 picker) |
| copy URL | Navidrome web route `…/app/#/album/<albumId>/show` (songs link to their album); public link via `createShare` only if sharing is enabled | — |
| open on Spotify | open that URL in Chrome (workspace 10) | — |
| lyrics | `getLyricsBySongId?id` (OpenSubsonic `songLyrics`: structured, possibly synced lines), fallback `getLyrics?artist&title` | `time-pos` drives the highlighted synced line |
| play counts / recently played | `scrobble?id&submission=false` on start, `submission=true` past 50 % or 4 min | `time-pos` |
| current-track subtitle | — | from the same state the rail reads |
| AI generate playlist | local model at `http://strix:8731` (Halogen until the Gufo cutover; send the exact served id) → resolve each `{title, artist}` with `search3` | replace / append |

Hardware keys already route through MPRIS: Sway binds F3/F4/F5 and `XF86AudioPlay/Next/Prev` to
`~/.local/bin/media`, which runs `playerctl play-pause|next|previous` on the default player. If the
music daemon publishes `org.mpris.MediaPlayer2.*` (via `dbus-next`, or mpv's MPRIS script), those
keys control Navidrome playback with no Sway change. The installed mpv wrapper
(`mpv-with-scripts-0.41.0`) did not show an `mpris` string in a quick grep; treat MPRIS as
something we publish ourselves until checked.

---

## 10. Linux keymap: the Raycast shortcuts translated for the GPUIX launcher

Rule: ⌘ → Ctrl, ⌥ → Alt (Raycast's own Windows mapping), with the three exceptions marked ✱
where Ctrl would collide with text editing in the search field. Alt groups the player/queue
operations.

| Action | Raycast macOS | Raycast Windows | **gpuix-shell** | Note |
|---|---|---|---|---|
| Primary action (Play / Pause / Connect / Search Again) | ↵ | ↵ | **Enter** | |
| Play and close launcher | — | — | **Shift+Enter** | ours: Raycast only has the global `closeWindowOnAction` |
| Open action panel | ⌘K | Ctrl+K | **Ctrl+K** (also Ctrl+B) | Ctrl+B is Vicinae's Linux default; keep both for muscle memory |
| Category dropdown | (click) | (click) | **Ctrl+P** | Vicinae `open-search-filter` |
| Back / pop view | Esc | Esc | **Esc** (Esc on root closes) | |
| Show content (albums / songs / episodes / Go to Album) | ⌘⇧A | Ctrl+Shift+A | **Ctrl+Shift+A** | |
| Show Popular Songs | ⌘Y | Ctrl+Y | **Ctrl+Y** | |
| Start Radio | ⌘⇧R | Ctrl+Shift+R | **Ctrl+Shift+R** | |
| Like | ⌘L | Ctrl+L | **Ctrl+L** | = star |
| Dislike | ⌘D | Ctrl+D | **Ctrl+D** | = unstar |
| Add to Queue | ⌥Q | Alt+Q | **Alt+Q** | |
| Play Next | — | — | **Alt+N** | ours (we own the queue) |
| Add to Playlist | ⌘A | Ctrl+A | ✱ **Alt+P** | Ctrl+A is select-all in the search field |
| Save album / follow artist | ⌘⇧S / ⌘⇧D | Ctrl+Shift+S / D | **Ctrl+Shift+S / Ctrl+Shift+D** | |
| Next / Previous | ⌘→ / ⌘← | Ctrl+→ / Ctrl+← | **Ctrl+Right / Ctrl+Left** | also Spotify desktop's keys; costs word-jump in the field, accepted |
| Volume ±10 | — | — | **Ctrl+Up / Ctrl+Down** | Spotify desktop's keys |
| Shuffle / Repeat | — | — | ✱ **Alt+S / Alt+R** | Ctrl+S/Ctrl+R are Save/Refresh in Raycast/Vicinae |
| Seek ±15 s | — | — | **Alt+Right / Alt+Left** | |
| Play/Pause from any music view | (Enter in Now Playing) | | **Ctrl+Space** (and Space in Now Playing, which has no text field) | |
| Connect Device / output | ⌘⇧K | Ctrl+Shift+K | **Ctrl+Shift+K** | PipeWire sinks |
| Open Search / Library from Now Playing | ⌘⇧F / ⌘⇧L | Ctrl+Shift+F / L | **Ctrl+Shift+F / Ctrl+Shift+L** | |
| Copy URL | ⌘⇧C | Ctrl+Shift+C | **Ctrl+Shift+C** | |
| Copy Artist and Title | ⌘⇧T | Ctrl+Shift+T | **Ctrl+Shift+T** | |
| Open in Navidrome (was Open on Spotify) | ⌘O | Ctrl+O | **Ctrl+O** | |
| Refresh | ⌘R | Ctrl+R | **Ctrl+R** | |
| Remove recent / Remove all | ⌃X / ⌃⇧X | Ctrl+X / Ctrl+Shift+X | **Ctrl+X / Ctrl+Shift+X** | |
| Copy Error (failure toast) | ⌘T | Ctrl+T | **Ctrl+T** | |
| Configure | ⌘, | Ctrl+, | **Ctrl+,** | |
| Lyrics: copy / copy info / search web | ⌘C / ⌘⇧C / ⌘S | | **Ctrl+C / Ctrl+Shift+C / Ctrl+S** | |

Every action row in our action panel shows its keycaps right-aligned, as Raycast does; the bottom
bar always shows "{primary} ↵ · Actions Ctrl K".

---

## 11. What we must reproduce for Navidrome, ranked

Priority = effect on Tom's first five minutes with the demo. P0 is the morning demo; P1 makes it
complete Spotify-level parity; P2 is delight. Each item names its Raycast origin.

### P0 — the demo (search, play, control, from the launcher)

1. **Search-as-you-type music mode in the launcher** (Search §3.1): one `search3` per settled
   query (~120 ms debounce), stale request aborted, previous rows kept while loading, loading bar.
   Sections in Raycast's order and caps: **Artists 3 · Songs 4 · Albums 6 · Playlists 6** (Liked
   Songs first), playlists filtered locally from `getPlaylists`. Placeholder "What do you want to
   listen to?".
2. **Enter plays** with Raycast's semantics: a song from search plays alone, then Spotify-style
   autoplay is ours to choose (append the rest of its album); a song inside an album/playlist plays
   that context from that song; album/playlist play the whole context; artist plays top songs
   (fallback: all songs). Playback through a single mpv instance driven over JSON IPC, gapless.
3. **Row anatomy** (§3.3): cover icon (circle for artists, smallest art for songs), bold title, dim
   inline subtitle (`Artist · YYYY`, `Artist, Artist`, owner), right accessories (`mm:ss`, `N songs`).
   Cover art from `getCoverArt` at list size (≈48 px) and cached.
4. **Action panel on Ctrl+K** with the per-type action sets of §3.3, icons, keycaps, section
   hairlines, its own filter field; bottom bar "Play ↵ · Actions Ctrl K"; all shortcuts of §10 work
   without opening the panel.
5. **Drill-down stack** (§3.4): Artist → Albums grid (5 columns, newest first) / Top songs; Album →
   Songs; Playlist → Songs; song → Go to Album; Esc pops, Esc on root closes.
6. **Now Playing sheet** (§5) as a launcher view: large cover, H1 title, "by Artist", metadata
   column (Track, Duration, Artist, Album, Liked ♥/♡), plus what Raycast lacks: a **live progress
   bar and elapsed/remaining time** driven by mpv events. Enter = Play/Pause; Ctrl+←/→, Ctrl+L,
   Ctrl+Shift+R, Ctrl+Shift+A, Alt+P all work there.
7. **Transport without opening a view** (§1 no-view rows, §2): `gpuix-shell music
   toggle|next|prev|like|shuffle|repeat|vol±|seek±` CLI verbs, Previous with the 3-second rule,
   each confirmed by the shell OSD/HUD ("Skipped to next", "▶ For Emma · Bon Iver"), and the same
   verbs as root launcher commands (type "next" → Enter).
8. **MPRIS publication** so the existing F3/F4/F5 and XF86Audio keys (`media` → `playerctl`) and
   the shell's MPRIS client control Navidrome playback for free (§9).
9. **Error and empty states** with actions (§3.2, §5, §7): empty query → "What do you want to
   listen to?" + recent searches; "No results for {q}"; server unreachable (Tailscale/DNS down) →
   "Can't reach Navidrome" + Retry Ctrl+R; "Nothing is playing right now" + Search/Library; play
   failure toast with Copy Error Ctrl+T.

### P1 — Spotify-level completeness

10. **Like/Dislike = star/unstar** on every song row and in Now Playing, state-aware single action,
    toast "Liked"/"Disliked"; Liked Songs pseudo-playlist (`getStarred2`).
11. **Category dropdown (Ctrl+P)** All / Artists (grid) / Songs / Albums (grid) / Playlists, with
    **infinite paging** via search3 offsets in the single-category views (34k tracks; Raycast never
    pages).
12. **Your Library** (§4): Playlists · Starred Albums · Starred Artists · Liked Songs, 6 each until
    typing, local fuzzy filtering, plus Navidrome's Recently Added / Recently Played / Most Played /
    Random shelves (the Raycast Navidrome extension's only views).
13. **Queue view** (§7.1) and **Add to Queue (Alt+Q) / Play Next (Alt+N)**, with what Spotify cannot do:
    remove (Ctrl+X), reorder (Ctrl+Shift+↑/↓), clear.
14. **Start Radio (Ctrl+Shift+R)** from song/artist/now-playing: `getSimilarSongs*`, fallback random
    by genre; toast "Starting Radio…" → "Playing Radio".
15. **Add to Playlist picker (Alt+P)** (§7.3): owned playlists, ✓ when the song is already there,
    Add/Remove toggle, "New Playlist…" row, Add Playing Song to Playlist as a root command.
16. **Player modes**: shuffle toggle, repeat cycle off → context → track, volume set (argument
    0–100 with Raycast's validation messages) / ±10 / presets, seek ±15, replay.
17. **Recent searches** (§3.2): >3 chars, 3 s settle, newest first, max 10, Search Again /
    Remove Ctrl+X / Remove All Ctrl+Shift+X with confirmation.
18. **Copy and open**: Copy URL (Navidrome web link) Ctrl+Shift+C, Copy "Song · Artist"
    Ctrl+Shift+T, Open in Navidrome Ctrl+O.
19. **Rail now-playing widget** = the menu-bar player (§6): cover icon, `Song · Artist` truncated to
    30 + "…", optional title cleanup, hidden when idle; click opens the §6.1 menu (Play/Pause, Like,
    Next, Previous, Start Radio, Add to Playlist ▸, Output ▸, Now Playing, Copy URL, Open in
    Navidrome). Event-driven, no timers.
20. **Root-launcher integration**: music verbs as root commands; a "Now Playing" root item whose
    subtitle is live `Song - Artist ♥` (`current-track`); "Just Play {query}" with an inline
    argument; the root fallback "Search music for '{q}'" (Raycast `fallbackText`).
21. **Scrobbling** (now-playing at start, submission past 50 % / 4 min) so Navidrome's Most/Recently
    Played and play counts stay correct; Spotify does this server-side, we must do it.
22. **Output device picker (Ctrl+Shift+K)** = Select Device (§7.2) over PipeWire sinks, active
    marked "Active", switching mpv's `audio-device` live.

### P2 — delight

23. **Lyrics** (§7.5) from `getLyricsBySongId`, synced-line highlight following playback;
    Copy Lyrics Ctrl+C.
24. **Generate Playlist** (§7.6) with the local model; tune / revert / history; Play, Add to Queue,
    Save as Navidrome playlist.
25. **Quick bindings**: "add playing song to playlist X" as a Sway-bindable CLI verb (the Quicklink
    idea), duplicate check with "Add anyway".
26. **Rating** (`setRating` 1–5), which Spotify does not have.
27. **Remove playing song from its playlist** (§7.4) with confirmation and "skip to next?".
28. **Play-queue sync** with Navidrome (`savePlayQueue`/`getPlayQueue`) so the queue survives a
    restart and appears on Tom's other Subsonic clients.
29. **`closeOnAction` preference** (default stay open, like Raycast) and Shift+Enter "play and close".
30. **AI tools** for the `gpuix-shell ask` surface: search, play, queue, current track,
    create playlist, add to playlist (Raycast's 7 tools).

### Deliberately not reproduced

Podcasts / shows / episodes (Tom's Navidrome holds music; not in scope tonight), Copy Embed Code,
Spotify DJ, Private Session, AppleScript fallbacks, OAuth/Premium handling, the Spotify 429
choreography, Raycast's 30 s menu-bar polling (we are event-driven).

### Baseline we beat: the Raycast Navidrome extension

4 views (Search, Recently Added Albums, Most Played Albums, Playlists); `search3` with fixed counts
5/10/10 and locally filtered playlists; recent searches; rows with Navidrome-orange "Playlist" tags;
actions are only **Open in Navidrome**, **Copy name** ⌘C, **Copy URL** ⌘⇧C. **It cannot play
anything.** Every P0 item above is beyond it. (Read here at `raycast/extensions` HEAD `d0885a53`;
the full reading at the pinned `c33bf4cb`, with cliamp and live server numbers, is
`02-navidrome-ext-and-cliamp.md`. That note also proposes the LRCLIB lyrics fallback be **off** by
default, so P2 item 23 uses Navidrome's own lyrics first.)

---

## 12. Target composite (how the pieces sit in the GPUIX launcher)

```
┌───────────────────────────── launcher 700×580, overlay ─────────────────────────────┐
│ ♪  bon iv▌                                                              All ⌄       │
│ ▁▁▁▁▁▁▁▁▁▁                                                                          │
│ Artists                                                                             │
│▌(◉) Bon Iver                                                       12 albums        │
│ Songs                                                                               │
│ [▣] Skinny Love                 Bon Iver                       ♥   03:58            │
│ [▣] Holocene                    Bon Iver                           05:36            │
│ Albums                                                                              │
│ [▣] For Emma, Forever Ago       Bon Iver · 2008                    9 songs          │
│ Playlists                                                                           │
│ [♥] Liked Songs                                                    214 songs        │
├─────────────────────────────────────────────────────────────────────────────────────┤
│ [▣] For Emma · Bon Iver  ━━━━━━━●──────── 1:12 / 3:40   ⏮ ⏸ ⏭  🔀 🔁   (mini-player)│
├─────────────────────────────────────────────────────────────────────────────────────┤
│ ♪ Music                                       Play ↵ │ Actions Ctrl K              │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

The mini-player strip is our addition (Raycast keeps playback state out of list views); it makes
"control from within the launcher" visible while searching and is clickable (opens Now Playing).
Flat, opaque, hairline separators, Anthropic Sans with mono figures for durations, per BRIEF §1/§3.

---

## What was done / not done

- Done: read both extensions' manifests and every hand-written source file, the
  `navidrome` extension's API and search view, the 8 store screenshots, the Raycast keyboard
  reference and Vicinae's Linux keybind defaults; checked how F3–F5 and the XF86Audio keys
  reach players in this branch (`media` → `playerctl`).
- Not done: no Navidrome call, mpv run or GPUI render was made for this note. Endpoint behaviour
  that depends on server configuration (`getTopSongs`, `getSimilarSongs*` need Navidrome's Last.fm
  agent; `createShare` needs sharing enabled; lyrics need embedded/sidecar lyrics) is **unverified**
  against music.internal. The `throttle` delay value is undocumented by Raycast and was not
  measured. Whether the installed mpv carries an MPRIS script was checked only by a string grep of
  the wrapper binary.
