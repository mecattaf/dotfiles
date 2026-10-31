# 03 — Subsonic / OpenSubsonic API, measured live against Navidrome 0.63.2

Measured 2026-10-20 between 23:10 and 23:25 CEST from the strix, against
`http://music.internal` (Caddy on the strix → navidrome-relay → Navidrome on the
NAS). Every call was a read: no star, scrobble, rating, playlist, queue,
bookmark or login write was sent. Write endpoints are documented from the
OpenSubsonic spec and marked **(doc only, not called)**.

Probe tool: [`probe/subsonic-get`](probe/subsonic-get), a bash script that reads
`/run/agenix/navidrome-credentials` at run time, sends credentials to curl on
stdin (never on argv), redacts the username from output and refuses write
endpoints. `subsonic-get --time …` prints curl's `time_total` in ms; `--url …`
prints a URL with every auth value masked. All JSON below is trimmed (`…`) and
the username is shown as `<user>`.

Common parameters on every call: `v=1.16.1&c=gpuix-shell&f=json` plus the auth
triple `u`, `t`, `s` (section 3).

---

## 0. What the builder needs to know first

1. **Server:** `{"type":"navidrome","serverVersion":"0.63.2 (v0.63.2)","openSubsonic":true,"version":"1.16.1"}`.
   OpenSubsonic extensions: `transcodeOffset`, `formPost`, `songLyrics` v1+v2,
   `indexBasedQueue`, `transcoding`, `playbackReport`. The server does **not** advertise
   `apiKeyAuthentication`, `topSongsByArtistId`, `sonicSimilarity` or `getPodcastEpisode`.
2. **Library:** 38,524 songs; 16,208 albums; 11,118 album artists (`getArtists`), 14,610
   artists in total (`search3` with an empty query, track artists included); 3,966 genres; 1,235
   playlists (all auto-imported `.m3u8`); about 6,000 hours and 739 GB. More than half the songs
   (20,416) sit in `[Unknown Album]`, 5,237 in `[Unknown Artist]`, and 3,056 have numeric-only
   titles (SoundCloud and YouTube rips). Only 59 songs have ever been played; nothing is starred
   or rated. So "frequent", "recent", "starred" and "highest" are nearly empty today, and the
   launcher needs non-empty fallbacks ("newest", "random").
3. **Search:** `search3` takes 13–29 ms at the server for launcher-sized pages. It matches word
   prefixes, ANDs the terms in any order, ignores diacritics (`beyonce` = `Beyoncé`) and needs at
   least 2 characters (`p` → nothing; `pa` → results). It does no infix matching (`ccina` → nothing),
   tolerates no typos (`rosalia` → nothing), returns **no totals** and **does not rank by
   relevance**: `justice` returns "Orchestre Lamoureux, Justice, Thomas Roussel" before
   "Justice". Re-rank on the client (section 4.5).
4. **Playback:** a plain `GET /rest/stream?id=…&u&t&s&v&c` works in mpv. With raw streams
   (no `format`, or `format=raw`) the server answers `206` with `Accept-Ranges: bytes`. mpv
   reaches its first `time-pos` in about 100 ms and seeks instantly (a `seek 180` landed at
   180.5 s). Transcoded streams (`format=opus`) arrive chunked, are **not seekable**, and mpv's
   `duration` is wrong for them, so seek with `timeOffset=<s>` and take the duration from the
   Subsonic `duration` field. Streaming has **no side effects**: `getNowPlaying` stayed empty and
   `playCount` did not change. Now-playing and play counts move only through `scrobble` or
   `reportPlayback`.
5. **Credentials are strix-only today.** `secrets.nix` encrypts `navidrome-credentials` for
   `editors ++ strixOnly`, and `modules/secrets.nix` installs it only when `hostName == "strix"`.
   The shell runs on the Zenbook, so it has no credential file there (section 2).
6. **Cover art:** `getCoverArt?id=<coverArt>&size=N` returns a JPEG that is N×N up to the
   original's size (album originals measured 500 px). It is served with
   `Cache-Control: public, max-age=315360000`, and ids carry a content hash (`al-<id>_<hash>`),
   so a disk cache keyed by `id+size` never needs invalidating. The first hit costs 90–170 ms,
   cached hits about 5 ms. `artistImageUrl` / `*ImageUrl` values are pre-signed
   `http://music.internal/share/img/<jwt>?size=N` URLs that work **without auth**.
7. **Quirks found live:** `getAlbumInfo2` returns its payload under the key **`albumInfo`**, not
   `albumInfo2`. Empty lists drop the array key entirely (`"randomSongs":{}`,
   `"starred2":{}`, `"nowPlaying":{}`). `getAlbumList2` caps `size` at 500. `search3`
   has no cap (`songCount=60000` returned all 38,524 songs in 3.8 s and 45.8 MB). Errors
   come back with HTTP 200 and `status:"failed"`. A `stream` error comes back as XML
   (or JSON with `f=json`) under HTTP 200, so check `Content-Type` before handing a URL to
   mpv as audio. (Measured: a Subsonic XML error document when no `f` was sent.) Unknown
   endpoints return a plain-text `404 page not found`.

---

## 1. Measured library and server facts

| Fact | Value | Source call |
|---|---|---|
| Songs | 38,524 | `getScanStatus.count`; `search3 query=""` (all) |
| Folders scanned | 12,352 | `getScanStatus.folderCount` |
| Last scan | 2026-08-28T10:24:54+02:00, `scanType:"quick"`, 116.6 s | `getScanStatus` |
| Albums | 16,208 | `search3 query="" albumCount=500` paged |
| Album artists | 11,118 in 26 index letters | `getArtists` |
| All artists | 14,610 | `search3 query="" artistCount=5000` paged |
| Genres | 3,966 (top: Rap 2,724 songs, Electronic 2,529, Pop 2,475, Hip-Hop 1,849, House 1,623) | `getGenres` |
| Playlists | 1,235 holding 16,662 entries; largest 410 | `getPlaylists` |
| Formats | mp3 17,590; m4a 14,037; opus 4,724; flac 1,502; wav 577; aif/aiff 61; wma 23; mp2 8; ogg 2 | `search3` all songs |
| Median bit rate | 256 kbps | same |
| Duration | median 268 s, p90 519 s, max 100,941 s (28 h) | same |
| Field gaps | `track` on only 12,223 songs; `year` missing on 9,683; `genre` on 14,080; `duration` on 329 | same |
| Plays | 59 songs carry `playCount`/`played`; 34 albums appear in `recent`/`frequent` | `getAlbumList2` |
| Starred / rated | 0 / 0 | `getStarred2`, `getAlbumList2 type=highest` |
| Lyrics | 5 of 600 sampled songs (~1 %), all `synced:false`, `lang:"eng"` | `getLyricsBySongId` |
| Users | 1 (admin, `streamRole`, `downloadRole`, `shareRole`, `scrobblingEnabled:true`) | `getUser`, `getUsers` |
| Music folders | `[{"id":1,"name":"Music Library"}]` | `getMusicFolders` |
| Web UI config | `defaultDownsamplingFormat:"opus"`, `lastFMEnabled:true`, `listenBrainzEnabled:true`, `enableNowPlaying:true`, `playbackReportIntervalMs:60000`, `uiSearchDebounceMs:200`, `variousArtistsId:"63sqASlAfjbGMuLP4JhnZU"` | `window.__APP_CONFIG__` in `/app/` |

---

## 2. Reaching the server from the shell (deployment facts)

| Base URL | From the strix (tested) | Note |
|---|---|---|
| `http://music.internal` | ok | AdGuard rewrite (`modules/adguardhome.nix`) → strix Caddy → `127.0.0.1:4533` relay → NAS. On the NAS resolver, `music.internal` answers 10.42.0.2, so the Zenbook resolves it while on the house LAN. |
| `http://strix:4533`, `http://10.42.0.2:4533`, `http://127.0.0.1:4533` | ok | Same relay. |
| `http://strix.tail8dd1.ts.net:4533` | **did not resolve on the strix** | The strix does not resolve its own MagicDNS name. Expect it to work only from a roaming tailnet client. |

**Credential gap.** The Zenbook has no `/run/agenix/navidrome-credentials`. Its
recipients are `editors ++ strixOnly` (`secrets.nix:112`), and the only installer is
`lib.mkIf (hostName == "strix")` in `modules/secrets.nix`. Its documented reader is the
`navidrome-scan` fish function. Options for the builder, in order of preference:

1. Add the client to the recipients (`editors ++ strixOnly ++ clientOnly`) and widen the
   `mkIf`. This needs an editor key to re-key the secret (`agenix -r`), so it is Tom's call.
2. The code reads `NAVIDROME_CREDENTIALS_FILE` (default `/run/agenix/navidrome-credentials`)
   and `NAVIDROME_URL` (default `http://music.internal`). When the file is absent, the music
   provider hides itself with a single "music: no credentials file" row rather than failing.
3. Demo on the strix under `runtime-test` (the file is readable there by `tom`, mode 0400).

Never put the values in git, logs, argv, `ps`-visible URLs or screenshots.

---

## 3. Authentication

Subsonic token auth, as implemented by Navidrome:

```
s = random salt (≥ 6 chars; we use 16 hex chars)
t = md5_hex(password + s)        // lowercase hex
?u=<username>&t=<t>&s=<s>&v=1.16.1&c=gpuix-shell&f=json
```

Measured error shapes (all HTTP 200):

| Case | `error` |
|---|---|
| no `u` | `{"code":10,"message":"missing parameter: 'u'"}` |
| wrong user/token | `{"code":40,"message":"Wrong username or password"}` |
| asking `getUser` for another user | `{"code":50,"message":"User is not authorized for the given operation"}` |
| missing required param | `{"code":10,"message":"missing parameter: 'genre'"}` |
| unknown id | `{"code":70,"message":"Song not found"}` / `"Album not found"` / `"Artwork not found"` / `"data not found"` (stream) |
| bad list type | `{"code":0,"message":"type 'bogus' not implemented"}` |

Other measured facts:
- A `.view` suffix works (`/rest/ping.view`).
- With no `f`, responses are XML.
- gzip is honoured (`Content-Encoding: gzip`).
- **`formPost` works.** `POST /rest/search3` with an `application/x-www-form-urlencoded`
  body holding the auth and query parameters returned the same JSON. Use POST for every
  JSON call so tokens stay out of URLs and proxy logs. Use GET URLs only where a URL must be
  handed to something else (mpv for `stream`, an image loader for `getCoverArt`).
- **Security note:** Subsonic salted tokens never expire, and the server keeps no record of
  used salts. A leaked `stream` URL is therefore a reusable credential until the password
  changes. Pass stream URLs to mpv over its JSON IPC socket (`loadfile`), never as argv
  (argv shows up in `ps`). Never log them, and never put them in notifications or the clipboard.

### 3.1 Auth helper (TypeScript, Bun/Node; tested equivalent in bash)

```ts
// src/music/subsonic/auth.ts
import { createHash, randomBytes } from "node:crypto";
import { readFileSync } from "node:fs";

export interface SubsonicCreds { baseUrl: string; user: string; password: string }

export function loadCreds(env = process.env): SubsonicCreds | null {
  const baseUrl = (env.NAVIDROME_URL ?? "http://music.internal").replace(/\/+$/, "");
  const file = env.NAVIDROME_CREDENTIALS_FILE ?? "/run/agenix/navidrome-credentials";
  let text: string;
  try { text = readFileSync(file, "utf8"); } catch { return null; } // provider hides itself
  const get = (k: string) => text.match(new RegExp(`^${k}=(.*)$`, "m"))?.[1]?.trim()
    .replace(/^(['"])(.*)\1$/, "$2");
  const user = get("NAVIDROME_USER"), password = get("NAVIDROME_PASSWORD");
  return user && password ? { baseUrl, user, password } : null;
}

export const CLIENT = "gpuix-shell";
export const API_VERSION = "1.16.1";

/** Fresh salt per request; returns params WITHOUT f (stream/getCoverArt must not get f=json). */
export function authParams(c: SubsonicCreds): URLSearchParams {
  const s = randomBytes(8).toString("hex");
  const t = createHash("md5").update(c.password + s).digest("hex");
  return new URLSearchParams({ u: c.user, t, s, v: API_VERSION, c: CLIENT });
}

type Params = Record<string, string | number | boolean | Array<string | number> | undefined>;
function append(q: URLSearchParams, p: Params) {
  for (const [k, v] of Object.entries(p)) {
    if (v === undefined) continue;
    for (const x of Array.isArray(v) ? v : [v]) q.append(k, String(x)); // repeated id=… for scrobble/savePlayQueue
  }
}

export class SubsonicError extends Error {
  constructor(public code: number, message: string, public endpoint: string) { super(message); }
}

/** JSON call via formPost (tokens never in a URL). */
export async function call<T>(c: SubsonicCreds, endpoint: string, p: Params = {},
                              signal?: AbortSignal): Promise<T> {
  const body = authParams(c); body.set("f", "json"); append(body, p);
  const r = await fetch(`${c.baseUrl}/rest/${endpoint}`, { method: "POST", body, signal });
  if (!r.ok) throw new SubsonicError(-r.status, `${r.status} ${r.statusText}`, endpoint); // e.g. 404 unknown endpoint
  const j = (await r.json())["subsonic-response"];
  if (j.status !== "ok") throw new SubsonicError(j.error?.code ?? 0, j.error?.message ?? "failed", endpoint);
  return j as T;
}

/** URL for things that need a URL (mpv, image cache fetch). Treat as a secret. */
export function mediaUrl(c: SubsonicCreds, endpoint: "stream" | "download" | "getCoverArt", p: Params): string {
  const q = authParams(c); append(q, p);
  return `${c.baseUrl}/rest/${endpoint}?${q}`;
}
```

---

## 4. Endpoint reference (measured)

Latency is the median of 5 runs of `curl time_total` from the strix (warm Navidrome
caches unless stated). From the Zenbook, add LAN or Wi-Fi RTT.

### 4.1 System

**`ping`**: 4 ms.
```json
{"subsonic-response":{"status":"ok","version":"1.16.1","type":"navidrome","serverVersion":"0.63.2 (v0.63.2)","openSubsonic":true}}
```

**`getLicense`** → `"license":{"valid":true}`

**`getOpenSubsonicExtensions`** (no auth needed per spec; we sent auth):
```json
"openSubsonicExtensions":[{"name":"transcodeOffset","versions":[1]},{"name":"formPost","versions":[1]},
 {"name":"songLyrics","versions":[1,2]},{"name":"indexBasedQueue","versions":[1]},
 {"name":"transcoding","versions":[1]},{"name":"playbackReport","versions":[1]}]
```

**`getMusicFolders`** → `"musicFolders":{"musicFolder":[{"id":1,"name":"Music Library"}]}`

**`getScanStatus`** → `"scanStatus":{"scanning":false,"count":38524,"folderCount":12352,"lastScan":"2026-08-28T10:24:54.560233133+02:00","scanType":"quick","elapsedTime":116560233133}`
(`elapsedTime` is in nanoseconds). Use it for "N songs" in the provider header and as a
change signal.

**`getUser`** `username=<self>` (another name → error 50):
```json
"user":{"username":"<user>","scrobblingEnabled":true,"adminRole":true,"settingsRole":false,"downloadRole":true,
 "uploadRole":false,"playlistRole":false,"coverArtRole":true,"commentRole":false,"podcastRole":false,
 "streamRole":true,"jukeboxRole":false,"shareRole":true,"videoConversionRole":false,"folder":[1]}
```
`playlistRole:false`: as far as I know from Navidrome's source, it never sets this flag and
does not check it in `createPlaylist`. That is not exercised here. Do not grey out
"Add to playlist" on that flag; handle an error 50 if it ever comes back.

### 4.2 Browse

**`getArtists`** (930 ms, **4.6 MB**; call once and cache. Never call it per keystroke):
```json
"artists":{"ignoredArticles":"The El La Los Las Le Les Os As O A","lastModified":1787905378000,
 "index":[{"name":"#","artist":[…]}, …26 entries…, {"name":"C","artist":[
   {"id":"22Ik9HRRaf5s9pO7InzXdu","name":"C","coverArt":"ar-22Ik9HRRaf5s9pO7InzXdu_0","albumCount":1,
    "artistImageUrl":"http://music.internal/share/img/<jwt>?size=600","musicBrainzId":"","sortName":"c",
    "roles":["albumartist","artist","maincredit"]}]}]}
```
Every entry has the `albumartist` role. Roles seen: albumartist, artist, maincredit,
composer, remixer. Compound credits are separate artists ("Daft Punk x Justice";
"Justice, Tame Impala, Rampa, Keinemusik").

**`getIndexes`** returns the same 11,118 artists in the folder-based shape. It supports
`ifModifiedSince=<lastModified>` and returns `"index"` empty when nothing changed. That is a
cheap "has the library changed?" probe for a local index.

**`getArtist id=`** (70 ms): `ArtistID3` + `album: AlbumID3[]`.
```json
"artist":{"id":"2YTKowlI2xJOj8Du42hJFZ","name":"Parcels","coverArt":"ar-2YTKowlI2xJOj8Du42hJFZ_0","albumCount":37,
 "artistImageUrl":"http://music.internal/share/img/<jwt>?size=600","musicBrainzId":"5318e774-…","sortName":"parcels",
 "roles":["maincredit","albumartist","artist","remixer"],
 "album":[{"id":"3Zzm02oyQIuQ8CNDYM5cb4","name":"Clockscared EP","artist":"Parcels","artistId":"2YTKowlI2xJOj8Du42hJFZ",
   "coverArt":"al-3Zzm02oyQIuQ8CNDYM5cb4_6a800655","songCount":6,"duration":1354,"created":"2026-08-18T12:03:58.403441545+02:00",
   "year":2015,"genre":"Funk","userRating":0,"genres":[{"name":"Funk"}],"musicBrainzId":"eb268dfa-…","isCompilation":false,
   "sortName":"clockscared ep","discTitles":[],"originalReleaseDate":{"year":2015,"month":3,"day":2},"releaseDate":{"year":2015},
   "releaseTypes":["ep"],"recordLabels":[],"moods":[],"artists":[{"id":"2YTKowlI2xJOj8Du42hJFZ","name":"Parcels"}],
   "displayArtist":"Parcels","explicitStatus":"","version":""}, …]}
```
Every artist with loose tracks has an `[Unknown Album]` album (Parcels has two, with 67
and 27 songs). Sort and label these last in the UI.

**`getAlbum id=`** (9 ms): `AlbumID3` + `song: Song[]`, in disc/track order.
```json
"album":{"id":"2xkkpe8mZ2CPgrtaMk176Z","name":"Live Vol. 1","artist":"Parcels","artistId":"2YTKowlI2xJOj8Du42hJFZ",
 "coverArt":"al-2xkkpe8mZ2CPgrtaMk176Z_6a82a52a","songCount":16,"duration":3585,"created":"…","year":2020,"genre":"Alternative",
 "userRating":0,"genres":[{"name":"Alternative"},{"name":"Music"}],"musicBrainzId":"","isCompilation":false,"sortName":"live vol. 1",
 "discTitles":[],"originalReleaseDate":{},"releaseDate":{},"releaseTypes":[],"recordLabels":[],"moods":[],
 "artists":[…],"displayArtist":"Parcels","explicitStatus":"","version":"","song":[ Song, … ]}
```

**`getSong id=`** (5 ms): the canonical `Song` ("Child") shape:
```json
"song":{"id":"knQBFakYGknBpS93V0Ceh5","parent":"27IOgjzYxZjO5ZuTJaNv8a","isDir":false,"title":"Civilization",
 "album":"Audio, Video, Disco","artist":"Justice","track":2,"year":2011,"genre":"Indie Rock",
 "coverArt":"mf-knQBFakYGknBpS93V0Ceh5_663d9232","size":8828592,"contentType":"audio/mpeg","suffix":"mp3",
 "duration":218,"bitRate":320,"path":"Justice/Audio, Video, Disco/02 - Civilization.mp3","created":"2026-07-13T14:14:35.458883359+02:00",
 "albumId":"27IOgjzYxZjO5ZuTJaNv8a","artistId":"6EQE4CiN4fEcjl0LGs2Rzt","type":"music","bpm":0,"comment":"UBP",
 "sortName":"civilization","mediaType":"song","musicBrainzId":"","isrc":["FR0NT1100370"],"genres":[{"name":"Indie Rock"}],
 "replayGain":{"trackGain":-10.87,"albumGain":-9.58,"trackPeak":1.114095,"albumPeak":1.131911},
 "channelCount":2,"samplingRate":44100,"bitDepth":0,"moods":[],"artists":[{"id":"6EQE4CiN4fEcjl0LGs2Rzt","name":"Justice"}],
 "displayArtist":"Justice","albumArtists":[…],"displayAlbumArtist":"Justice",
 "contributors":[{"role":"composer","artist":{"id":"6JcIiGn3nHhftUX0u3EYAT","name":"Gaspard Augé, Xavier de Rosnay"}}],
 "displayComposer":"Gaspard Augé, Xavier de Rosnay","explicitStatus":"","groupings":[],"works":[],"movements":[]}
```
Optional keys are **absent** when unset, never null: `track`, `discNumber`, `year`, `genre`,
`duration`, `bitRate`, `playCount`, `played`, `starred`, `userRating`. Played songs add
`"playCount":2,"played":"2026-10-11T22:32:00.360461844+02:00"`. `explicitStatus` is `""` or
`"explicit"` (487 songs). `comment` often holds a source URL (YouTube/SoundCloud).
`replayGain` is `{}` when untagged.

**`getMusicDirectory id=<artistId>`** works (folder view: children are albums with
`isDir:true`). The shell has no use for it, since the ID3 calls above are better.

### 4.3 Lists

**`getAlbumList2 type=… size≤500 offset=`** → `"albumList2":{"album":[AlbumID3…]}`.
`size>500` is silently capped at 500.

| `type` | Extra params | ms (size 500 / 50) | Count today | Note |
|---|---|---|---|---|
| `newest` | — | 126 / 59 | 500+ | By `created` (scan date). The default "Home" shelf. |
| `recent` | — | 37 | 34 | By `played`. |
| `frequent` | — | 32 / 12 | 34 | By `playCount` (top album: 14 plays). |
| `random` | — | 194 / 107 | 500 | The "shuffle shelf". |
| `alphabeticalByName` | — | 179 | 500+ | First entry has name `"\n"` (bad tag), so trim names. |
| `alphabeticalByArtist` | — | 108 | 500+ | |
| `highest` | — | 26 | 0 | No ratings. |
| `starred` | — | 23 | 0 | Nothing starred. |
| `byGenre` | `genre=` (required; else code 10) | — | Funk: 80 | Genre **name**, case-sensitive as in `getGenres`. |
| `byYear` | `fromYear`, `toYear` | — | — | `fromYear>toYear` sorts descending. Matches albums whose year *range* overlaps (a 1998 best-of appeared in 1975–1979). |

Album list items carry `playCount`/`played` when played:
```json
{"id":"2TrqiCnKVKeDQK5IflwHvP","name":"Tales of Patara","artist":"Mouma, Baso, Qualista","artistId":"…","coverArt":"al-…_6a7e2be9",
 "songCount":1,"duration":362,"playCount":1,"created":"2026-08-20T10:56:18…","year":2021,"genre":"Music",
 "played":"2026-10-11T21:24:21…","userRating":0,"genres":[…],"isCompilation":false,"sortName":"tales of patara", …}
```

**`getRandomSongs size≤500 genre= fromYear= toYear= musicFolderId=`** (28 ms for 50) →
`"randomSongs":{"song":[Song…]}`. `size=1000` returned 500. When nothing matches, the
response is `"randomSongs":{}` with no `song` key (`genre=Funk&fromYear=1970&toYear=1985`).
`genre=Funk` matches *any* of a song's genres, so the primary `genre` field shown can differ
(House, Disco). This is the "Shuffle all" and "Shuffle genre" backend.

**`getGenres`** (86 ms, 3,966 entries) →
`"genres":{"genre":[{"value":"Rap","songCount":2724,"albumCount":350}, …]}`. The name is in
**`value`**, not `name`. The list has a long tail of junk genres; show the top N by
`songCount`.

**`getStarred2`** → `"starred2":{}` today. When populated:
`{"artist"?:ArtistID3[],"album"?:AlbumID3[],"song"?:Song[]}`, each item with `"starred":"<ISO>"`.

### 4.4 Playlists

**`getPlaylists`** (64 ms, 1,235 entries):
```json
"playlists":{"playlist":[{"id":"9gz8i8ho9R2BNCeHZ75Vxl","name":"Juan Super Old","comment":"Auto-imported from 'Juan Super Old.m3u8'",
 "songCount":330,"duration":160370,"owner":"<user>","created":"2026-08-18T12:33:03…","changed":"2026-08-18T12:33:03…",
 "coverArt":"pl-9gz8i8ho9R2BNCeHZ75Vxl_6a8434df","readonly":false}, …]}
```
`public` is absent (false). Names follow `<soundcloud-user> / <title>`.

**`getPlaylist id=`** (67 ms for 330 entries) → `"playlist":{…same fields…, "entry":[Song…]}`.
The playlist `coverArt` is a server-generated mosaic **PNG**: 1,125 ms on first request,
about 100 ms after that.

**(doc only, not called)**
- `createPlaylist name=… songId=…×N` creates a playlist and returns it. `createPlaylist
  playlistId=… songId=…×N` *replaces* the entries of an existing one.
- `updatePlaylist playlistId= name? comment? public? songIdToAdd=…×N songIndexToRemove=…×N`
  returns an empty ok. Indexes are 0-based positions in the current entry list.
- `deletePlaylist id=`.

### 4.5 Search (`search3`), the launcher backbone

Params: `query`, `artistCount`/`artistOffset` (default 20/0), `albumCount`/`albumOffset`,
`songCount`/`songOffset`, `musicFolderId`. Response:
`"searchResult3":{"artist"?:ArtistID3[],"album"?:AlbumID3[],"song"?:Song[]}`. A section with
no hits is **absent**, and past-the-end offsets return `"searchResult3":{}`.

Latency (server, median of 9; `artistCount=5 albumCount=8 songCount=20` unless noted):

| Query | min / med / max ms | Top hits |
|---|---|---|
| `parcels` | 14 / 16 / 18 | artist Parcels; album "Parcels" |
| `daft punk` | 17 / 18 / 21 | artist Daft Punk; albums Discovery, Homework |
| `love` | 25 / 27 / 31 | 38 artists, 193 albums, 1,222 songs in total (counted by paging) |
| `love` at launcher size 3/5/10 | 23 / 25 / 27 | |
| `love` songs only, 50 | 28 / 29 / 33 | |
| `daf pun` (partial words) | 15 / 17 / 22 | Daft Punk |
| `beyonce` | 11 / 13 / 16 | "Beyonce" and "Beyoncé" |
| `kraak` | 14 / 15 / 18 | kraak & smaak |
| `p` (1 char) | 4 / 4 / 5 | **nothing**: minimum length is 2 |

Semantics measured:
- Word-prefix match on artist/album/title text: `pa` hits "Pa Lé", "PANG!", "Le Palace, Paris".
- Terms are ANDed in any order: `punk daft` = `daft punk`. Quoting does not force a phrase.
- Diacritics are folded.
- No infix (`ccina` misses "Saccina…") and no typo tolerance.
- **No relevance ranking:**
  - `justice` → artists `["Orchestre Lamoureux, Justice, Thomas Roussel","Justice, Tame Impala, …","Justice","Daft Punk x Justice"]`
  - `xx` → `["The xx & Jamie xx", …, "Jamie xx","The xx", …, "xxx"]`
- Paging is stable: `songOffset=5,songCount=5` equals items 6–10 of `songCount=10`.
- Empty `query=""` (or no `query`) returns *everything*, which makes it a cheap full dump.
  It is also a trap: never send an empty query from a keystroke handler.

Recommended launcher pipeline (Raycast/Spotify-grade feel):
1. Debounce 60–120 ms (the web UI uses 200). Require 2 or more characters. Abort the previous
   request with `AbortController`.
2. `search3 artistCount=6 albumCount=8 songCount=25` (≈25 ms), then **re-rank client-side**:
   exact name match (case- and diacritic-folded) > name starts with the query > every query word
   starts a word in the name > the rest. Tie-break artists by `albumCount`, albums and songs by
   `playCount`, then `year` descending. Pin a single "Top result" card (Spotify-style) from the
   best of the three sections.
3. Optional local fuzzy fallback for typos: one `search3 query="" songCount=60000` dump (3.8 s,
   45.8 MB JSON). Reduced to `[id,title,artist,album,albumId,duration,coverArt,playCount]` it is
   6.1 MB (2.2 MB gzipped), cached at `$XDG_CACHE_HOME/gpuix-shell/music/index.json`. Refresh it
   when `getIndexes ifModifiedSince=<lastModified>` returns a non-empty index or
   `getScanStatus.lastScan` changes. Query it only when the server returns 0 hits or the user
   types a likely typo.
4. Hide `[Unknown Album]` in album rows and subtitles (53 % of songs). Fall back to the title
   when the artist is `[Unknown Artist]`. Many titles already embed "Artist - Title", so de-dup
   the display ("Daft Punk - Daft Punk - Aerodynamic" appears verbatim).

### 4.6 Discovery (external agents; slow, call off the keystroke path)

The web UI config reports `lastFMEnabled:true` and `listenBrainzEnabled:true`. Biographies
look like AllMusic or Deezer text. Responses depend on the external agents and on matching
against the local library.

**`getTopSongs artist=<name> count=`** (by **name**; `topSongsByArtistId` is not advertised): 250–380 ms.
- `Daft Punk` → 5 songs: Instant Crush, Veridis Quo, One More Time, Around the World, Harder Better Faster Stronger.
- `Justice` → 3.
- `Parcels` → **0**: the library has only live versions, which do not match.

Response: `"topSongs":{"song"?:Song[]}`.

**`getSimilarSongs2 id=<artistId|songId|albumId> count=`**: **2.3–2.9 s, not cached**
(a repeat call also took 2.3 s). `id=` Justice → 10 songs mixing Justice and Daft Punk.
Response: `"similarSongs2":{"song"?:Song[]}`. v1 `getSimilarSongs` behaves the same. Use it
for "Start radio" with a spinner, and prefetch on hover or selection, never on keystroke.

**`getArtistInfo2 id= count= includeNotPresent=`**: 435–661 ms cold, 16 ms cached.
```json
"artistInfo2":{"biography":"Proving how all-encompassing the French touch style can be, Justice adds prog, metal, …",
 "musicBrainzId":"…","lastFmUrl":"http://www.justice.church/",
 "smallImageUrl":"http://music.internal/share/img/<jwt>?size=300","mediumImageUrl":"…?size=600","largeImageUrl":"…?size=1200",
 "similarArtist":[ArtistID3 (in-library only, 9 of requested 20 for Justice), …]}
```
`biography` is absent for some artists (Parcels). `lastFmUrl` held the artist's own website
in both samples.

**`getAlbumInfo2 id=<albumId>`**: 27 ms. **Quirk: the payload key is `albumInfo`.**
```json
{"subsonic-response":{"status":"ok",…,"albumInfo":{"musicBrainzId":"eb268dfa-…",
  "smallImageUrl":"…?size=300","mediumImageUrl":"…?size=600","largeImageUrl":"…?size=1200"}}}
```
`notes` was absent in all samples. Read `r.albumInfo2 ?? r.albumInfo`.

### 4.7 Lyrics

**`getLyricsBySongId id=`** (`songLyrics` ext, 5 ms):
```json
"lyricsList":{"structuredLyrics":[{"displayArtist":"Kolter","displayTitle":"Authentic Computers","lang":"eng","synced":false,
  "line":[{"value":"Everyone tries to be really authentic."},{"value":"I, for instance am super authentic."}, …]}]}
```
With no lyrics the response is `"lyricsList":{}`. Synced lyrics add `line[].start` (ms) and an
optional `offset`. No synced sample exists in the library (0 of 5 hits in a 600-song sample).
`songLyrics` v2 (advertised) is opt-in with `enhanced=true`. It adds `kind`
("main" / "translation" / "pronunciation"), `agents[]` and `cueLine[]` (word or syllable cues
with `byteStart`/`byteEnd`). It was not called, so make those fields optional in the types.

**`getLyrics artist= title=`** (legacy) → `"lyrics":{"artist":"Kolter","title":"Authentic Computers","value":"Everyone tries…\nI, for instance…"}`.
With no match: `"lyrics":{"value":""}`.

### 4.8 Media: cover art, stream, download, transcoding

**`getCoverArt id=<coverArt> size=`** returns bytes.
- Accepted ids: `al-<albumId>_<hash>`, `al-<albumId>`, a bare `<albumId>`, `ar-<artistId>_0`,
  `mf-<songId>_<hash>`, `pl-<playlistId>_<hash>`.
- Headers: `200`, `Content-Type: image/jpeg` (playlist mosaic: `image/png`),
  `Cache-Control: public, max-age=315360000`, `Last-Modified`.

| size | result (album `al-27IOgjzYxZjO5ZuTJaNv8a_663d9232`) |
|---|---|
| 32 | jpeg 32×32, 888 B |
| 64 | jpeg 64×64, 1,599 B |
| 128 | jpeg 128×128, 4,152 B |
| 300 | jpeg 300×300, 19,646 B |
| 600 / 1200 / omitted | jpeg 500×500, 71,413 B (original size; no upscaling) |
| artist `ar-…_0` size 600 | jpeg 600×600, 40,658 B (external image; 128,583 B unsized) |
| playlist `pl-…` size 300 | png 300×300, 149,611 B |

- First fetch costs 90–170 ms (playlist mosaic 1.1 s); cached fetches about 5 ms.
- Unknown id → HTTP 200 JSON error `{"code":70,"message":"Artwork not found"}`, so check
  `Content-Type`.
- Missing `id` → a placeholder **WebP** (`image/webp`).

Recommendation: rows at 64 (or 96 for HiDPI), the now-playing card at 300, and a disk cache at
`$XDG_CACHE_HOME/gpuix-shell/music/art/<id>@<size>.jpg` with no expiry. GPUIX image loading
then reads local files and the auth URL never leaves the shell process.

**`stream id= maxBitRate= format= timeOffset= estimateContentLength=`**: a plain GET with
auth params. **mpv plays it.**

| Request | Status / headers | TTFB | Note |
|---|---|---|---|
| `stream id=` (mp3 320) | `206`, `Accept-Ranges: bytes`, `Content-Range: bytes 0-65535/8828592`, `Content-Type: audio/mpeg`, `X-Content-Duration: 218.83` | 7 ms | Raw file, seekable. |
| `format=raw` | identical to the above | 6 ms | Explicitly never transcode. |
| opus source | `206`, `audio/ogg` | 78 ms | Raw. |
| `format=opus&maxBitRate=128` | `200`, `Accept-Ranges: none`, `Transfer-Encoding: chunked`, `audio/ogg` | 176 ms | 3.4 MB delivered in 2.2 s (~100× realtime). Not seekable. |
| `format=mp3&maxBitRate=128&estimateContentLength=true` | `200`, `Content-Length: 3585310` (estimate) | 62 ms | The estimate was 83 KB too long (curl error 18). |
| `maxBitRate=128` (no format) | `206` from the transcode cache, `audio/ogg` | 7 ms | The default downsampling format is opus. A cached transcode *is* range-capable. |
| bad id | `200`, `application/xml` (no `f`) `<error code="70" message="data not found">` | 6 ms | |

`X-Content-Duration` is present on all audio responses.

mpv, measured with `mpv --no-config --idle --no-video --ao=null --input-ipc-server=…` and the URL
sent over IPC (`{"command":["loadfile",URL,"replace"]}`):
- **Raw mp3:** first `time-pos` after **103 ms**; `duration` 218.8; `seekable:true`; `seek 180
  absolute` → 180.5 s; `media-title` "Civilization"; `metadata/by-key/artist` "Justice".
- **`format=opus&maxBitRate=96`:** first `time-pos` after 104 ms, but `duration` reported **3.97 s**
  (the buffered amount), `seekable:false`, and the seek was rejected ("Cannot seek in this stream").
- **`…&timeOffset=120`:** playback starts at 120 s of the song. mpv reports `time-pos` from 0 and
  `duration` 94.97 (the remainder), so the UI shows `timeOffset + time-pos`.

Recommendation:
- **Default to `format=raw`.** Every container here (wma, aif and mp2 included) decodes in mpv's
  ffmpeg, the LAN has the bandwidth, and raw streams are range-seekable.
- Use `format=opus&maxBitRate=128` only on a metered or roaming link, and implement seek there
  as "reload with `timeOffset`".
- Always take the duration from `Song.duration`.
- Gapless playback and a queue: mpv's `loadfile URL append-play` and its playlist (one mpv
  process, `--idle`, `--gapless-audio=weak`).
- ReplayGain: pass `--replaygain=track` when `Song.replayGain.trackGain` exists. mpv reads the
  tags itself from raw streams.

**`download id=`**: song → `206`, `Content-Disposition: attachment; filename="Civilization.mp3"`,
range-capable, never transcoded. An **album or playlist id** streams a `.zip`
(`Content-Disposition: attachment; filename="Audio_ Video_ Disco.zip"`, chunked, 54.8 MB in
0.32 s). The shell has no use for it beyond "Save to ~/Music".

**`transcoding` extension** (measured, read-only POST):
`POST /rest/getTranscodeDecision?mediaId=&mediaType=song&<auth>` with a `ClientInfo` JSON body:
```json
{"name":"gpuix-shell","platform":"linux-mpv","maxAudioBitrate":0,"maxTranscodingAudioBitrate":192,
 "directPlayProfiles":[{"containers":["mp3","flac","ogg","opus","m4a","mp4","wav","aiff"],
   "audioCodecs":["mp3","flac","opus","vorbis","aac","alac","pcm"],"protocols":["http"],"maxAudioChannels":2}],
 "transcodingProfiles":[{"container":"ogg","audioCodec":"opus","protocol":"http","maxAudioChannels":2}],
 "codecProfiles":[]}
```
→ for an mp3: `{"canDirectPlay":true,"canTranscode":false,"transcodeParams":"<jwt>","sourceStream":{"protocol":"http","container":"mp3","codec":"mp3","audioChannels":2,"audioBitrate":320000,"audioSamplerate":44100}}`

→ for a wma: `{"canDirectPlay":false,"canTranscode":true,"transcodeReason":["container 'wma' not supported by profile […]"],"transcodeParams":"<jwt>","sourceStream":{…"codec":"wmav2","audioBitrate":64000…},"transcodeStream":{"protocol":"http","container":"ogg","codec":"opus","audioChannels":2,"audioBitrate":64000,"audioSamplerate":48000}}`

`getTranscodeStream mediaId= mediaType= offset=<s> transcodeParams=<jwt>` streams the
result (not called). mpv can direct-play everything, so plain `stream format=raw` is
simpler. Keep this extension for a future phone or browser head.

### 4.9 Now playing, queue, bookmarks, radio

**`getNowPlaying`** (3 ms) → `"nowPlaying":{}` today. Per spec an entry is a `Song` plus
`username`, `minutesAgo`, `playerId`, `playerName?`, and, with `playbackReport`, `state`,
`positionMs` and `playbackRate`. Entries appear only after `scrobble submission=false` or
`reportPlayback`, **not** on `stream`. The entry shape was not observed live.

**`getPlayQueue`** → `"playQueue":{"username":"<user>","changed":"0001-01-01T00:00:00Z","changedBy":""}`
(empty; Go zero time). When set: `current` (song id), `position` (ms), `entry: Song[]`.

**`getPlayQueueByIndex`** (`indexBasedQueue`) →
`"playQueueByIndex":{"username":"<user>","changed":"0001-01-01T00:00:00Z","changedBy":""}`.
When set: `currentIndex` (0-based), `position` (ms), `entry: Song[]`. Duplicates are allowed.
**This is the cross-device queue sync:** the web UI, phone clients and the shell share one
server-side queue per user.

**`getBookmarks`** → `"bookmarks":{}`. When set:
`bookmark: {position, username, comment?, created, changed, entry: Song}[]`.

**`getInternetRadioStations`** → `"internetRadioStations":{}`. When set:
`internetRadioStation: {id, name, streamUrl, homePageUrl?}[]`. Nothing is configured.

**`getShares`** → `"shares":{}`.

### 4.10 State-changing endpoints (doc only, not called)

| Endpoint | Params | Effect / use in the shell |
|---|---|---|
| `scrobble` | `id` (×N), `time` (ms epoch, ×N), `submission` (default true) | `submission=false` sets now playing. `submission=true` counts a play: fire it at 50 % or 4 min, the Last.fm rule. Navidrome forwards to Last.fm or ListenBrainz when the user has linked them. Batch offline plays with repeated `id`/`time`. |
| `reportPlayback` (`playbackReport`) | `mediaId`, `mediaType=song`, `positionMs`, `state` (`starting`/`playing`/`paused`/`stopped`), `playbackRate` (1.0), `ignoreScrobble` (false) | Timeline reporting. Send on state changes plus a heartbeat; the web UI uses `playbackReportIntervalMs: 60000`. With `ignoreScrobble=true` it updates now playing only. Prefer it over `scrobble submission=false`, and do not send both for the same play. |
| `star` / `unstar` | `id` (song, ×N), `albumId` (×N), `artistId` (×N) | "♥ Like" (the Spotify heart). Empty response on success. |
| `setRating` | `id`, `rating` 0–5 (0 removes) | Feeds `getAlbumList2 type=highest`. |
| `savePlayQueue` | `id` (×N), `current` (song id), `position` (ms) | Saves the queue for cross-device resume. With no `id`, clears it. |
| `savePlayQueueByIndex` | `id` (×N), `currentIndex` (0-based; required when ids are given; out of range → code 10), `position` (ms) | Same, with duplicates allowed. Prefer this one. Save on pause, track change, quit, and every 30 s while playing. |
| `createBookmark` / `deleteBookmark` | `id`, `position` (ms), `comment` | Resume points for 28-hour mixes (max duration measured is 100,941 s). |
| `createPlaylist` / `updatePlaylist` / `deletePlaylist` | see 4.4 | "Add to playlist", "Save queue as playlist". |
| `createShare` | `id` (×N), `description`, `expires` | Public share link (`shareRole:true`). Not for the demo. |
| `startScan` | `fullScan` | Admin rescan. Not for the shell. |

---

## 5. Navidrome native REST `/api/*` (shape only, not logged in)

Measured without a token: `/api/song`, `/api/album`, `/api/queue` and `/api/events` → `401
{"error":"Not authenticated"}`; `GET /auth/login` → `405`. The rest is from Navidrome's source
conventions and was **not exercised**, because a login is a write (it updates `lastLoginAt`).

- `POST /auth/login` with `{"username":…,"password":…}` → `{"id","name","username","isAdmin",
  "token":"<JWT>","subsonicSalt","subsonicToken","avatar"?,"lastFMApiKey"?}`.
- Send the JWT as `x-nd-authorization: Bearer <JWT>`. A refreshed token comes back in the same
  response header, so always keep the latest one.
- Resources follow react-admin conventions: `GET /api/{song,album,artist,playlist,genre,radio,share,queue,library,player,transcoding,user}`
  with `_start`, `_end`, `_sort`, `_order` and filters as query params (`title=`, `album_id=`,
  `artist_id=`, `starred=true`, `genre_id=`). Totals come in the **`X-Total-Count`** header, which
  Subsonic never gives.
- `GET /api/events` is a Server-Sent Events stream (keepAlive, `scanStatus`, `refreshResource`,
  `nowPlayingCount`; `devNewEventStream:true` in the UI config). It is the only *push* channel
  Navidrome has.

Verdict: the shell does not need `/api`. Subsonic plus `formPost` covers search, browse,
playback, queue and likes. Revisit `/api/events` only to react to remote now-playing or scan
completion without polling.

---

## 6. "Open in Navidrome" deep links (web UI, hash router)

Base: `http://music.internal/app/` (`/` redirects there with a 302). Route patterns were
extracted from the 0.63.2 bundle (`/app/assets/index-BC2FYTT0.js`). They were not clicked in a
browser.

| Target | URL |
|---|---|
| Album | `http://music.internal/app/#/album/<albumId>/show` |
| Artist | `http://music.internal/app/#/artist/<artistId>/show`. The UI itself routes Various Artists (`63sqASlAfjbGMuLP4JhnZU`) to the album list filtered by artist instead. |
| Playlist | `http://music.internal/app/#/playlist/<playlistId>/show` |
| Radio station | `http://music.internal/app/#/radio/<id>/show` |
| Album shelves | `#/album/all`, `#/album/recentlyAdded`, `#/album/recentlyPlayed`, `#/album/starred`, `#/album/topRated` |
| Albums by artist | `#/album?filter={"artist_id":"<artistId>"}&order=ASC&sort=max_year` |
| Search albums / songs | `#/album?filter={"q":"<text>"}`, `#/song?filter={"q":"<text>"}` (react-admin `q` source; URL-encode the JSON) |
| Song | No song detail route. Open the album: `#/album/<song.albumId>/show`. |

---

## 7. Latency summary (server, median of 5, from the strix)

| Call | ms | | Call | ms |
|---|---|---|---|---|
| ping | 4 | | getNowPlaying | 3 |
| getSong | 5 | | getPlayQueue | 4 |
| getAlbum | 9 | | getLyricsBySongId | 5 |
| getArtist | 70 | | getStarred2 | 9 |
| getArtists (4.6 MB) | 930 | | getGenres | 86 |
| search3 (launcher page) | 13–29 | | getPlaylists | 64 |
| getAlbumList2 newest/random/frequent (50) | 59 / 107 / 12 | | getPlaylist (330) | 67 |
| getRandomSongs (50) | 28 | | getTopSongs | 321 |
| getArtistInfo2 cold / cached | 435–661 / 16 | | getSimilarSongs2 | 2,300–2,900 |
| getCoverArt cold / cached | 90–170 / 5 | | stream raw TTFB | 7 |

---

## 8. TypeScript type sketch (measured shapes)

```ts
// src/music/subsonic/types.ts — Navidrome 0.63.2, OpenSubsonic, API 1.16.1, measured 2026-10-20.
// Rule: Navidrome OMITS unset optional keys (never null) and omits empty arrays in list wrappers.

export type ISODate = string;            // "2026-08-18T12:20:23.874079478+02:00"; zero value "0001-01-01T00:00:00Z"

export interface Envelope {
  status: "ok" | "failed";
  version: string;                       // "1.16.1"
  type: string;                          // "navidrome"
  serverVersion: string;                 // "0.63.2 (v0.63.2)"
  openSubsonic: boolean;
  error?: { code: number; message: string }; // 0 generic, 10 missing param, 40 bad auth, 50 forbidden, 70 not found
}
export type R<K extends string, T> = Envelope & { [P in K]: T };

// ── shared atoms
export interface ArtistRef { id: string; name: string }
export interface GenreRef { name: string }
export interface ItemDate { year?: number; month?: number; day?: number }
export interface ReplayGain { trackGain?: number; albumGain?: number; trackPeak?: number; albumPeak?: number; baseGain?: number; fallbackGain?: number }
export interface Contributor { role: "composer" | "lyricist" | "arranger" | "remixer" | "performer" | "conductor" | "engineer" | string; subRole?: string; artist: ArtistRef }

// ── Song ("Child")
export interface Song {
  id: string; parent: string; isDir: false; type: "music"; mediaType: "song";
  title: string; sortName: string;
  album: string; albumId: string;        // album "[Unknown Album]" for loose tracks
  artist: string; artistId: string;      // artist "[Unknown Artist]" possible
  displayArtist: string; artists: ArtistRef[];
  displayAlbumArtist: string; albumArtists: ArtistRef[];
  displayComposer: string; contributors: Contributor[];
  coverArt: string;                      // "mf-<songId>_<hash>" | "al-<albumId>_<hash>" | "al-<albumId>_0"
  path: string; suffix: string; contentType: string;
  size?: number; duration?: number; bitRate?: number;  // seconds / kbps
  samplingRate: number; channelCount: number; bitDepth: number;
  track?: number; discNumber?: number; year?: number; genre?: string; genres: GenreRef[];
  bpm: number; comment: string; isrc: string[]; musicBrainzId: string;
  replayGain: ReplayGain; moods: string[]; groupings: string[]; works: unknown[]; movements: unknown[];
  explicitStatus: "" | "explicit" | "clean";
  created: ISODate;
  playCount?: number; played?: ISODate; starred?: ISODate; userRating?: number;
}

// ── Album (AlbumID3)
export interface Album {
  id: string; name: string; sortName: string; version: string;
  artist: string; artistId: string; displayArtist: string; artists: ArtistRef[];
  coverArt: string;                      // "al-<id>_<hash>"
  songCount: number; duration: number; created: ISODate;
  year?: number; genre?: string; genres: GenreRef[];
  playCount?: number; played?: ISODate; starred?: ISODate; userRating: number;
  musicBrainzId: string; isCompilation: boolean; explicitStatus: string;
  discTitles: { disc: number; title: string }[];
  originalReleaseDate: ItemDate; releaseDate: ItemDate;
  releaseTypes: string[];                // ["ep"], ["album"], ...
  recordLabels: { name: string }[]; moods: string[];
}
export interface AlbumWithSongs extends Album { song: Song[] }

// ── Artist (ArtistID3)
export interface Artist {
  id: string; name: string; sortName: string;
  coverArt: string;                      // "ar-<id>_0"
  albumCount: number;
  artistImageUrl: string;                // pre-signed, no auth: http://music.internal/share/img/<jwt>?size=600
  musicBrainzId: string;
  roles: ("albumartist" | "artist" | "maincredit" | "composer" | "remixer" | string)[];
  starred?: ISODate; userRating?: number;
}
export interface ArtistWithAlbums extends Artist { album: Album[] }

// ── responses
export type Ping = Envelope;
export type License = R<"license", { valid: boolean }>;
export type Extensions = R<"openSubsonicExtensions", { name: string; versions: number[] }[]>;
export type MusicFolders = R<"musicFolders", { musicFolder: { id: number; name: string }[] }>;
export type ScanStatus = R<"scanStatus", { scanning: boolean; count: number; folderCount: number; lastScan: ISODate; scanType: string; elapsedTime: number /* ns */ }>;
export type User = R<"user", {
  username: string; scrobblingEnabled: boolean; adminRole: boolean; settingsRole: boolean; downloadRole: boolean;
  uploadRole: boolean; playlistRole: boolean; coverArtRole: boolean; commentRole: boolean; podcastRole: boolean;
  streamRole: boolean; jukeboxRole: boolean; shareRole: boolean; videoConversionRole: boolean; folder: number[] }>;

export type Artists = R<"artists", { ignoredArticles: string; lastModified: number; index: { name: string; artist: Artist[] }[] }>;
export type ArtistResp = R<"artist", ArtistWithAlbums>;
export type AlbumResp = R<"album", AlbumWithSongs>;
export type SongResp = R<"song", Song>;

export type AlbumListType = "newest" | "recent" | "frequent" | "random" | "alphabeticalByName"
  | "alphabeticalByArtist" | "highest" | "starred" | "byGenre" | "byYear";
export type AlbumList2 = R<"albumList2", { album?: Album[] }>;        // size ≤ 500
export type RandomSongs = R<"randomSongs", { song?: Song[] }>;         // size ≤ 500
export type Genres = R<"genres", { genre: { value: string; songCount: number; albumCount: number }[] }>;
export type Starred2 = R<"starred2", { artist?: Artist[]; album?: Album[]; song?: Song[] }>;

export type SearchResult3 = R<"searchResult3", { artist?: Artist[]; album?: Album[]; song?: Song[] }>;

export interface Playlist {
  id: string; name: string; comment?: string; owner: string; public?: boolean;
  songCount: number; duration: number; created: ISODate; changed: ISODate;
  coverArt: string;                      // "pl-<id>_<hash>" → PNG mosaic
  readonly: boolean;
}
export type Playlists = R<"playlists", { playlist?: Playlist[] }>;
export type PlaylistResp = R<"playlist", Playlist & { entry?: Song[] }>;

export type TopSongs = R<"topSongs", { song?: Song[] }>;
export type SimilarSongs2 = R<"similarSongs2", { song?: Song[] }>;
export type ArtistInfo2 = R<"artistInfo2", {
  biography?: string; musicBrainzId?: string; lastFmUrl?: string;
  smallImageUrl?: string; mediumImageUrl?: string; largeImageUrl?: string;
  similarArtist?: Artist[] }>;
export interface AlbumInfoBody { notes?: string; musicBrainzId?: string; lastFmUrl?: string; smallImageUrl?: string; mediumImageUrl?: string; largeImageUrl?: string }
/** Navidrome 0.63.2 answers getAlbumInfo2 under "albumInfo" — accept both. */
export type AlbumInfo2 = Envelope & { albumInfo2?: AlbumInfoBody; albumInfo?: AlbumInfoBody };

export interface LyricLine { start?: number /* ms, synced only */; value: string }
export interface StructuredLyrics {
  lang: string; synced: boolean; line: LyricLine[];
  displayArtist?: string; displayTitle?: string; offset?: number;
  kind?: "main" | "translation" | "pronunciation";        // songLyrics v2 (enhanced=true), not observed
  agents?: unknown[]; cueLine?: unknown[];                  // songLyrics v2 (enhanced=true), not observed
}
export type LyricsList = R<"lyricsList", { structuredLyrics?: StructuredLyrics[] }>;
export type Lyrics = R<"lyrics", { artist?: string; title?: string; value: string }>;

export interface NowPlayingEntry extends Song {          // spec; not observed live (empty)
  username: string; minutesAgo: number; playerId: number; playerName?: string;
  state?: "starting" | "playing" | "paused" | "stopped"; positionMs?: number; playbackRate?: number;
}
export type NowPlaying = R<"nowPlaying", { entry?: NowPlayingEntry[] }>;

interface QueueBase { username: string; changed: ISODate; changedBy: string; position?: number /* ms */; entry?: Song[] }
export type PlayQueue = R<"playQueue", QueueBase & { current?: string }>;
export type PlayQueueByIndex = R<"playQueueByIndex", QueueBase & { currentIndex?: number }>;
export type Bookmarks = R<"bookmarks", { bookmark?: { position: number; username: string; comment?: string; created: ISODate; changed: ISODate; entry: Song }[] }>;
export type InternetRadioStations = R<"internetRadioStations", { internetRadioStation?: { id: string; name: string; streamUrl: string; homePageUrl?: string }[] }>;

export interface StreamDetails { protocol: string; container: string; codec: string; audioChannels: number; audioBitrate: number; audioProfile?: string; audioSamplerate: number; audioBitdepth?: number }
export type TranscodeDecision = R<"transcodeDecision", {
  canDirectPlay: boolean; canTranscode: boolean; transcodeReason?: string[]; errorReason?: string;
  transcodeParams: string; sourceStream: StreamDetails; transcodeStream?: StreamDetails }>;
```

### 8.1 Thin typed client (sketch)

```ts
// src/music/subsonic/client.ts
import { call, mediaUrl, type SubsonicCreds } from "./auth";
import type * as T from "./types";

export const subsonic = (c: SubsonicCreds) => ({
  ping: () => call<T.Ping>(c, "ping"),
  search: (query: string, n = { artist: 6, album: 8, song: 25 }, signal?: AbortSignal) =>
    query.trim().length < 2 ? Promise.resolve(null)
      : call<T.SearchResult3>(c, "search3", { query, artistCount: n.artist, albumCount: n.album, songCount: n.song }, signal),
  artist: (id: string) => call<T.ArtistResp>(c, "getArtist", { id }),
  album: (id: string) => call<T.AlbumResp>(c, "getAlbum", { id }),
  song: (id: string) => call<T.SongResp>(c, "getSong", { id }),
  albums: (type: T.AlbumListType, o: { size?: number; offset?: number; genre?: string; fromYear?: number; toYear?: number } = {}) =>
    call<T.AlbumList2>(c, "getAlbumList2", { ...o, type, size: Math.min(o.size ?? 50, 500) }),
  randomSongs: (size = 50, genre?: string) => call<T.RandomSongs>(c, "getRandomSongs", { size: Math.min(size, 500), genre }),
  playlists: () => call<T.Playlists>(c, "getPlaylists"),
  playlist: (id: string) => call<T.PlaylistResp>(c, "getPlaylist", { id }),
  topSongs: (artist: string, count = 10) => call<T.TopSongs>(c, "getTopSongs", { artist, count }),
  similar: (id: string, count = 50) => call<T.SimilarSongs2>(c, "getSimilarSongs2", { id, count }), // 2–3 s
  artistInfo: (id: string) => call<T.ArtistInfo2>(c, "getArtistInfo2", { id, count: 10 }),
  albumInfo: async (id: string) => { const r = await call<T.AlbumInfo2>(c, "getAlbumInfo2", { id }); return r.albumInfo2 ?? r.albumInfo ?? {}; },
  lyrics: (id: string) => call<T.LyricsList>(c, "getLyricsBySongId", { id }),
  queue: () => call<T.PlayQueueByIndex>(c, "getPlayQueueByIndex"),
  // writes — only from explicit user actions or real playback, never from tests:
  saveQueue: (ids: string[], currentIndex: number, positionMs: number) =>
    call<T.Envelope>(c, "savePlayQueueByIndex", ids.length ? { id: ids, currentIndex, position: Math.round(positionMs) } : {}),
  report: (mediaId: string, state: "starting" | "playing" | "paused" | "stopped", positionMs: number, ignoreScrobble = false) =>
    call<T.Envelope>(c, "reportPlayback", { mediaId, mediaType: "song", positionMs: Math.round(positionMs), state, playbackRate: 1, ignoreScrobble }),
  scrobble: (id: string, timeMs = Date.now()) => call<T.Envelope>(c, "scrobble", { id, time: timeMs, submission: true }),
  star: (o: { id?: string; albumId?: string; artistId?: string }) => call<T.Envelope>(c, "star", o),
  unstar: (o: { id?: string; albumId?: string; artistId?: string }) => call<T.Envelope>(c, "unstar", o),
  // URLs (secrets — hand to mpv over IPC / fetch into the art cache; never log)
  streamUrl: (id: string, o: { raw?: boolean; maxBitRate?: number; timeOffset?: number } = { raw: true }) =>
    mediaUrl(c, "stream", o.raw !== false && !o.maxBitRate ? { id, format: "raw" } : { id, format: "opus", maxBitRate: o.maxBitRate ?? 128, timeOffset: o.timeOffset }),
  coverUrl: (coverArt: string, size = 300) => mediaUrl(c, "getCoverArt", { id: coverArt, size }),
  webUrl: (k: "album" | "artist" | "playlist", id: string) => `${c.baseUrl}/app/#/${k}/${id}/show`,
});
```

---

## 9. Verified and not verified

Verified: the three `ts` blocks above (`auth.ts`, `types.ts`, `client.ts`) were extracted
verbatim and typechecked with `tsc --strict` (exit 0, with minimal `node:` shims). They were
then run with bun 1.4.2 against the live server: `ping` ok; `search("daft punk")` returned
5/8/25 in 65 ms wall time, cold process; a 1-char query returned null; `albums("newest",{size:900})`
returned 500; `albumInfo` read the `albumInfo` key; `song("nope")` threw `SubsonicError` 70;
a ranged `streamUrl` fetch returned 206 `audio/mpeg`; `coverUrl(…,64)` returned a 1,599 B
JPEG. Only read calls were made.

Not verified (say so, do not assume):

- No write endpoint was called: scrobble, reportPlayback, star/unstar, setRating,
  savePlayQueue(ByIndex), playlists, bookmarks and shares are documented from the
  OpenSubsonic spec. Their success shapes (empty envelope) are not measured.
- `getNowPlaying` entries, populated play queues, bookmarks, starred items, synced lyrics and
  songLyrics v2 fields were all empty on this server, so their shapes come from the spec.
- Navidrome `/api/*` beyond the unauthenticated 401/405 checks is from source knowledge.
  `/auth/login` was not called.
- Web UI deep links come from route strings in the bundle; they were not opened in a browser.
- Latencies were measured from the strix (loopback to Caddy, relay to the NAS). Zenbook
  numbers will add LAN or Wi-Fi RTT and were not measured.
- `http://strix.tail8dd1.ts.net:4533` did not resolve from the strix; it was not tested from a
  tailnet client.
- mpv was tested with `--ao=null` on the strix (no audio device, no compositor), not on the Zenbook.
