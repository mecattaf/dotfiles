import { Axis } from "@domicile-desktop/manganese-window-management/direction";
import type { Placement, Screenful } from "@domicile-desktop/manganese-window-management/placement";
import { spanning } from "@domicile-desktop/manganese-window-management/rect";
import type { StageScreen } from "@domicile-desktop/manganese-window-management/screens/stage-screens";
import type { WindowState } from "@domicile-desktop/manganese-window-management/window-state";
import { windowsIn } from "./GaplessFrames";
import { agencyPlacement } from "./layout";

type Workspace = WindowState["workspaces"][number];
type Node = NonNullable<Workspace["tiling"]["root"]>;
type Piece = { readonly node: Node; readonly path: readonly number[] };
type Numbers = Readonly<Record<string, number>>;
export type ScrollPreferences = {
  readonly widths: Numbers;
  readonly heights: Numbers;
  readonly horizontal: Numbers;
  readonly vertical: Numbers;
  /** The focus last followed on each workspace; manual pans retain their offset. */
  readonly followed: Readonly<Record<string, string>>;
};
export const emptyScrollPreferences = (): ScrollPreferences => ({ widths: {}, heights: {}, horizontal: {}, vertical: {}, followed: {} });
const PRESETS = [1 / 3, 1 / 2, 2 / 3, 1] as const;
export const nextScrollPreset = (value: number, backward = false): number => backward
  ? PRESETS.toReversed().find(preset => preset < value - 0.005) ?? 1
  : PRESETS.find(preset => preset > value + 0.005) ?? 1 / 3;

/** A presentation copy opens every tab without changing the recoverable tree. */
const opened = (node: Node): Node => node.kind === 1 ? node : {
  ...node, layout: node.layout === 3 ? 0 : node.layout === 2 ? 1 : node.layout,
  children: node.children.map(opened),
};
const pieces = (node: Node, axis: Axis, path: readonly number[] = []): readonly Piece[] =>
  node.kind === 0 && node.layout === axis
    ? node.children.flatMap((child, index) => pieces(child, axis, [...path, index]))
    : [{ node, path }];
const focusedIn = (node: Node): string => {
  if (node.kind === 1) return node.id;
  const child = node.children[node.focused];
  if (child === undefined) throw Error("Scrolling layout has no focused child");
  return focusedIn(child);
};
const ratioOf = (node: Node, saved: Numbers) => windowsIn(node).map(id => saved[id]).find(value => value !== undefined) ?? 1;
const keyOf = (node: Node) => windowsIn(node)[0]!;
const minimumExtent = (node: Node, axis: Axis, state: WindowState): number => {
  if (node.kind === 1) {
    const window = state.windows.find(candidate => candidate.id === node.id);
    return window !== undefined && "minSize" in window ? window.minSize[axis] ?? 0 : 0;
  }
  const sizes = node.children.map(child => minimumExtent(child, axis, state));
  return node.layout === axis
    ? Math.max(0, ...sizes.map((size, index) => size / (node.fractions[index]! > 0 ? node.fractions[index]! : 1 / sizes.length)))
    : Math.max(0, ...sizes);
};
const clamp = (value: number, length: number, viewport: number) => Math.max(0, Math.min(value, Math.max(0, length - viewport)));
const reveal = (before: number, start: number, length: number, viewport: number) =>
  length >= viewport || start < before ? start : start + length > before + viewport ? start + length - viewport : before;
const contains = (node: Node, id: string | undefined) => id !== undefined && windowsIn(node).includes(id);
const updateNumber = (values: Numbers, key: string, value: number): Numbers => values[key] === value ? values : { ...values, [key]: value };
const withoutChrome = (placement: Placement): Placement => ({
  ...placement, bare: true, surface: placement.frame, behind: undefined, strip: undefined,
  tabbed: undefined, soleTab: false, bar: { ...placement.frame, height: 0 },
});

/**
 * Draw the existing windows on an unbounded ribbon. Only the viewport moves:
 * no native window, guest, workspace, group or floating placement is replaced.
 * Every output keeps its real clipping rectangle, including the rail reserve.
 */
export function scrollingScreens(base: readonly StageScreen[], state: WindowState, preferences: ScrollPreferences,
  scrollWorkspace: (name: string) => boolean = () => true): { screens: readonly StageScreen[]; preferences: ScrollPreferences } {
  let next = preferences;
  const screens = base.map(screen => {
    if (!scrollWorkspace(screen.current) || screen.fullscreen !== undefined) return screen;
    const workspace = state.workspaces.find(candidate => candidate.name === screen.current);
    const root = workspace?.tiling.root;
    if (workspace === undefined || root === undefined) return screen;
    const viewport = screen.geometry.workspace;
    if (viewport.width <= 0 || viewport.height <= 0) return screen;
    const tree = opened(root);
    const columns = pieces(tree, Axis.Horizontal);
    const active = workspace.floatFocus === undefined ? focusedIn(root) : undefined;
    const follow = active !== undefined && next.followed[workspace.name] !== active;
    let left = 0;
    const measured = columns.map(column => {
      const width = Math.max(minimumExtent(column.node, Axis.Horizontal, state), viewport.width * ratioOf(column.node, next.widths));
      const result = { ...column, width, left };
      left += width;
      return result;
    });
    let horizontal = clamp(next.horizontal[workspace.name] ?? 0, left, viewport.width);
    const selected = measured.find(column => contains(column.node, active));
    if (follow && selected !== undefined) horizontal = clamp(reveal(horizontal, selected.left, selected.width, viewport.width), left, viewport.width);
    next = { ...next, horizontal: updateNumber(next.horizontal, workspace.name, horizontal),
      followed: active === undefined || next.followed[workspace.name] === active ? next.followed : { ...next.followed, [workspace.name]: active } };
    const drawn: Screenful[] = measured.map(column => {
      const rows = pieces(column.node, Axis.Vertical);
      let top = 0;
      const measuredRows = rows.map(row => {
        const height = Math.max(minimumExtent(row.node, Axis.Vertical, state), viewport.height * ratioOf(row.node, next.heights));
        const result = { ...row, top, height };
        top += height;
        return result;
      });
      const key = keyOf(column.node);
      let vertical = clamp(next.vertical[key] ?? 0, top, viewport.height);
      const selectedRow = measuredRows.find(row => contains(row.node, active));
      if (follow && selectedRow !== undefined) vertical = clamp(reveal(vertical, selectedRow.top, selectedRow.height, viewport.height), top, viewport.height);
      next = { ...next, vertical: updateNumber(next.vertical, key, vertical) };
      const parts = measuredRows.map(row => agencyPlacement({ ...workspace, floats: [], floatFocus: undefined,
        fullscreen: undefined, tiling: { root: row.node, depth: Math.max(0, workspace.tiling.depth - column.path.length - row.path.length) } },
      { ...screen.geometry, workspace: {
        x: viewport.x + column.left - horizontal, y: viewport.y + row.top - vertical,
        width: column.width, height: row.height,
      } }));
      return { placements: parts.flatMap(part => part.placements.map(withoutChrome)), tabs: [], focusBox: undefined };
    });
    const placements = [...drawn.flatMap(part => part.placements), ...screen.screenful.placements.filter(placement => placement.depth > 0)];
    const focus = screen.screenful.focusBox;
    const selectedFrames = focus === undefined ? [] : placements.filter(placement => focus.windows.includes(placement.id)).map(placement => placement.frame);
    const selectedBounds = selectedFrames.reduce<Placement["frame"] | undefined>((bounds, frame) => bounds === undefined ? frame : spanning(bounds, frame), undefined);
    return { ...screen, screenful: {
      placements,
      tabs: screen.screenful.tabs.filter(tab => tab.depth > 0),
      focusBox: focus === undefined || focus.depth > 0 || selectedBounds === undefined ? focus
        : { ...focus, rect: selectedBounds, selection: focus.selection === undefined ? undefined : selectedBounds },
    } };
  });
  const unchanged = Object.keys(next).every(key => next[key as keyof ScrollPreferences] === preferences[key as keyof ScrollPreferences]);
  return { screens, preferences: unchanged ? preferences : next };
}

function targetOf(state: WindowState, id: string, axis: Axis) {
  const workspace = state.workspaces.find(candidate => candidate.tiling.root !== undefined && contains(candidate.tiling.root, id));
  if (workspace?.tiling.root === undefined) return;
  const columns = pieces(opened(workspace.tiling.root), Axis.Horizontal);
  const column = columns.find(candidate => contains(candidate.node, id));
  if (column === undefined) return;
  const target = axis === Axis.Horizontal ? column : pieces(column.node, Axis.Vertical).find(row => contains(row.node, id));
  return target === undefined ? undefined : { workspace, target: target.node };
}

/** Set one column width or stacked row height; group siblings keep one size. */
export function setScrollSize(preferences: ScrollPreferences, state: WindowState, id: string, axis: Axis, value: number): ScrollPreferences {
  const target = targetOf(state, id, axis);
  if (target === undefined) return preferences;
  if (!Number.isFinite(value) || value < 1 / 64 || value > 4) throw Error("Scrolling size is outside its supported range");
  const property = axis === Axis.Horizontal ? "widths" : "heights";
  const values = { ...preferences[property] };
  for (const window of windowsIn(target.target)) values[window] = value;
  return { ...preferences, [property]: values, followed: { ...preferences.followed, [target.workspace.name]: "" } };
}
export function cycleScrollSize(preferences: ScrollPreferences, state: WindowState, id: string, axis: Axis, backward = false, extent?: number): ScrollPreferences {
  const target = targetOf(state, id, axis);
  return target === undefined ? preferences : setScrollSize(preferences, state, id, axis,
    nextScrollPreset(Math.max(ratioOf(target.target, axis === Axis.Horizontal ? preferences.widths : preferences.heights),
      extent === undefined || extent <= 0 ? 0 : minimumExtent(target.target, axis, state) / extent), backward));
}
export function scrollSizeOf(preferences: ScrollPreferences, state: WindowState, id: string, axis: Axis): number | undefined {
  const target = targetOf(state, id, axis);
  return target === undefined ? undefined : ratioOf(target.target, axis === Axis.Horizontal ? preferences.widths : preferences.heights);
}

/** Closed IDs must not leak preferences to a later native window incarnation. */
export function pruneScrollPreferences(preferences: ScrollPreferences, state: WindowState): ScrollPreferences {
  const live = new Set(state.windows.map(window => window.id));
  const workspaces = new Set(state.workspaces.map(workspace => workspace.name));
  const prune = <T>(values: Readonly<Record<string, T>>, keep: (key: string, value: T) => boolean): Readonly<Record<string, T>> => {
    const entries = Object.entries(values).filter(([key, value]) => keep(key, value));
    return entries.length === Object.keys(values).length ? values : Object.fromEntries(entries);
  };
  const next = { widths: prune(preferences.widths, key => live.has(key)), heights: prune(preferences.heights, key => live.has(key)),
    vertical: prune(preferences.vertical, key => live.has(key)), horizontal: prune(preferences.horizontal, key => workspaces.has(key)),
    followed: prune(preferences.followed, (key, id) => workspaces.has(key) && (id === "" || live.has(id))) };
  return Object.keys(next).every(key => next[key as keyof ScrollPreferences] === preferences[key as keyof ScrollPreferences]) ? preferences : next;
}

/** Pan a workspace's ribbon, or the column containing its focused window. */
export function panScroll(preferences: ScrollPreferences, state: WindowState, workspaceName: string, axis: Axis, delta: number): ScrollPreferences {
  if (!Number.isFinite(delta)) throw Error("Scrolling delta must be finite");
  const workspace = state.workspaces.find(candidate => candidate.name === workspaceName);
  if (workspace?.tiling.root === undefined) return preferences;
  const id = focusedIn(workspace.tiling.root);
  const column = pieces(opened(workspace.tiling.root), Axis.Horizontal).find(candidate => contains(candidate.node, id));
  if (column === undefined) return preferences;
  const property = axis === Axis.Horizontal ? "horizontal" : "vertical";
  const key = axis === Axis.Horizontal ? workspaceName : keyOf(column.node);
  return { ...preferences, [property]: { ...preferences[property], [key]: Math.max(0, (preferences[property][key] ?? 0) + delta) },
    followed: { ...preferences.followed, [workspaceName]: id } };
}

export function encodeScrollPreferences(identity: string, preferences: ScrollPreferences): string {
  return JSON.stringify({ version: 1, identity, preferences });
}
/** Refuse malformed or differently scoped state before any geometry or write. */
export function decodeScrollPreferences(text: string, identity: string): ScrollPreferences {
  if (text.length > 4 * 1024 * 1024) throw Error("Saved scrolling layout is too large");
  const parsed: unknown = JSON.parse(text);
  const record = (value: unknown): Record<string, unknown> => {
    if (typeof value !== "object" || value === null || Array.isArray(value)) throw Error("Invalid saved scrolling layout");
    return value as Record<string, unknown>;
  };
  const value = record(parsed);
  if (value.version !== 1 || value.identity !== identity) throw Error("Saved scrolling identity mismatch");
  const saved = record(value.preferences);
  const numbers = (property: string, sizes = false): Numbers => {
    const values = record(saved[property]);
    const entries = Object.entries(values);
    if (entries.length > 4096 || entries.some(([key, number]) => key.length > 512 || typeof number !== "number" || !Number.isFinite(number)
      || number < (sizes ? 1 / 64 : 0) || number > (sizes ? 4 : 100_000_000))) throw Error("Invalid saved scrolling values");
    return values as Record<string, number>;
  };
  const followed = record(saved.followed);
  if (Object.keys(followed).length > 4096 || Object.entries(followed).some(([key, id]) => key.length > 512 || typeof id !== "string" || id.length > 512)) throw Error("Invalid saved scrolling focus");
  return { widths: numbers("widths", true), heights: numbers("heights", true), horizontal: numbers("horizontal"), vertical: numbers("vertical"), followed: followed as Record<string, string> };
}
