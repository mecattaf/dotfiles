// src/launcher/provider.ts — the launcher provider contract, verbatim from docs/gpuix-shell/music/05-ux-spec.md §9.1.
// Created by the music design pass (MUSIC.md §6.4) because no launcher host existed yet; the wave-2 launcher
// owner takes it over. Change it only together with every provider that implements it.
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
