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
