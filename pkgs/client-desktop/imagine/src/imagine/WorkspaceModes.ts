import type { Rect } from "@domicile-desktop/manganese-window-management/rect";
import { activeIdOf, reduceWindows, WindowAction } from "@domicile-desktop/manganese-window-management/window-state";
import type { WindowState } from "@domicile-desktop/manganese-window-management/window-state";
import { windowsIn } from "./GaplessFrames";

export type WorkspaceMode = "scrolling" | "floating";
type Workspace = WindowState["workspaces"][number];
type Tiling = Workspace["tiling"];
type Node = NonNullable<Tiling["root"]>;
type Float = Workspace["floats"][number];
export type WorkspaceModeRecord = {
  readonly mode: WorkspaceMode;
  /** The prior tiled topology, kept separately from floated groups. */
  readonly tiled?: Tiling;
  /** Only windows floated by workspace mode, never explicit dialogs/floats. */
  readonly automatic: readonly string[];
  readonly floating: readonly Float[];
  readonly zoom: Readonly<Record<string, Rect>>;
};
export type WorkspaceModeMemory = Readonly<Record<string, WorkspaceModeRecord>>;
export type WorkspaceModeTransition = { readonly state: WindowState; readonly memory: WorkspaceModeMemory };
export const EMPTY_WORKSPACE_MODES: WorkspaceModeMemory = Object.freeze({});
export const workspaceModeOf = (memory: WorkspaceModeMemory, workspace: string): WorkspaceMode => memory[workspace]?.mode ?? "scrolling";

const idsOf = (workspace: Workspace) => [
  ...(workspace.tiling.root === undefined ? [] : windowsIn(workspace.tiling.root)),
  ...workspace.floats.flatMap(float => windowsIn(float.root)),
];
const columnRoots = (node: Node): readonly Node[] => node.kind === 0 && node.layout === 0
  ? node.children.flatMap(columnRoots) : [node];
const equalIds = (a: readonly string[], b: readonly string[]) => a.length === b.length && a.every(id => b.includes(id));
const normalize = (node: Extract<Node, {children: readonly Node[]}>, children: readonly {node: Node; at: number}[]): Node | undefined => {
  if (children.length === 0) return undefined;
  const total = children.reduce((sum, child) => sum + node.fractions[child.at]!, 0);
  return { ...node, children: children.map(child => child.node),
    fractions: children.map(child => total > 0 ? node.fractions[child.at]! / total : 1 / children.length),
    focused: Math.max(0, children.findIndex(child => child.at === node.focused)) };
};
const merge = (a: Node | undefined, b: Node | undefined): Node | undefined => a === undefined ? b : b === undefined ? a
  : { kind: 0, layout: 0, children: [a, b], fractions: [.5, .5], focused: 0 };
const focusedRoot = (root: Node, id: string): Node => {
  if (root.kind === 1) return root;
  const focused = root.children.findIndex(child => windowsIn(child).includes(id));
  if (focused < 0) return root;
  const child = focusedRoot(root.children[focused]!, id);
  return root.focused === focused && child === root.children[focused] ? root : {
    ...root, focused, children: root.children.map((old, at) => at === focused ? child : old),
  };
};
const pruned = (node: Node | undefined, keep: (id: string) => boolean): Node | undefined => {
  if (node === undefined) return undefined;
  if (node.kind === 1) return keep(node.id) ? node : undefined;
  return normalize(node, node.children.flatMap((child, at) => {
    const result = pruned(child, keep); return result === undefined ? [] : [{node: result, at}];
  }));
};

/** Retain ordering/splits from the tiled checkpoint and current group contents.
 * Groups that were joined while floating are inserted once, at their first
 * old position. Closed, hidden or moved-away windows are never reintroduced. */
function retile(saved: Tiling | undefined, groups: readonly Float[], extra: Node | undefined): Tiling {
  const used = new Set<Float>();
  const visit = (node: Node): Node | undefined => {
    const ids = windowsIn(node);
    const exact = groups.find(group => !used.has(group) && equalIds(windowsIn(group.root), ids));
    if (exact !== undefined) { used.add(exact); return exact.root; }
    if (node.kind === 1) {
      const group = groups.find(item => windowsIn(item.root).includes(node.id));
      if (group === undefined || used.has(group)) return undefined;
      used.add(group); return group.root;
    }
    return normalize(node, node.children.flatMap((child, at) => {
      const result = visit(child); return result === undefined ? [] : [{node: result, at}];
    }));
  };
  let root = saved?.root === undefined ? undefined : visit(saved.root);
  for (const group of groups) if (!used.has(group)) root = merge(root, group.root);
  return { root: merge(root, extra), depth: saved?.depth ?? 64 };
}

const floatFor = (root: Node, area: Rect, index: number, cached: readonly Float[]): Float => {
  const ids = windowsIn(root);
  const old = cached.find(float => windowsIn(float.root).some(id => ids.includes(id)));
  const width = Math.min(area.width, old?.width ?? Math.max(240, area.width * .72));
  const height = Math.min(area.height, old?.height ?? Math.max(120, area.height * .78));
  return { root, depth: 64, bare: false, scratchpad: false,
    width, height,
    x: Math.max(area.x, Math.min(old?.x ?? area.x + 24 + index * 28, area.x + area.width - width)),
    y: Math.max(area.y, Math.min(old?.y ?? area.y + 24 + index * 28, area.y + area.height - height)) };
};

/** A workspace mode change is geometry/state only. No app is opened or closed.
 * area uses coordinates local to the output, like stock floating geometry. */
export function setWorkspaceMode(state: WindowState, memory: WorkspaceModeMemory, name: string,
  mode: WorkspaceMode, area: Rect): WorkspaceModeTransition {
  const workspace = state.workspaces.find(item => item.name === name);
  if (workspace === undefined || area.width <= 0 || area.height <= 0) return { state, memory };
  const old: WorkspaceModeRecord = memory[name] ?? { mode: "scrolling", automatic: [], floating: [], zoom: {} };
  if (old.mode === mode) return mode === "floating" ? floatIncoming(state, memory, workspace, old, area) : { state, memory };
  // A fullscreen reference may name an ancestor spanning multiple columns.
  // Keep that topology intact until fullscreen exits, then the ordinary
  // reconciliation pass can float the workspace without breaking its NodeRef.
  if (mode === "floating" && workspace.fullscreen !== undefined) return {state,
    memory: {...memory, [name]: {...old, mode, tiled: undefined, automatic: []}}};
  const active = activeIdOf(state);
  let next: Workspace;
  let record: WorkspaceModeRecord;
  if (mode === "floating") {
    const roots = workspace.tiling.root === undefined ? [] : columnRoots(workspace.tiling.root);
    const added = roots.map((root, index) => floatFor(root, area, workspace.floats.length + index, old.floating));
    next = { ...workspace, tiling: { root: undefined, depth: 0 }, floats: [...workspace.floats, ...added],
      floatFocus: active !== undefined && added.some(float => windowsIn(float.root).includes(active)) ? active : workspace.floatFocus };
    record = { ...old, mode, tiled: workspace.tiling, automatic: roots.flatMap(windowsIn), floating: added };
  } else {
    const automatic = new Set(old.automatic);
    const owned = workspace.floats.filter(float => !float.bare && !float.scratchpad && windowsIn(float.root).every(id => automatic.has(id)));
    const floats = workspace.floats.filter(float => !owned.includes(float));
    next = { ...workspace, tiling: retile(old.tiled, owned, workspace.tiling.root), floats,
      floatFocus: workspace.floatFocus !== undefined && floats.some(float => windowsIn(float.root).includes(workspace.floatFocus!))
        ? workspace.floatFocus : undefined };
    record = { ...old, mode, automatic: [], floating: owned, tiled: undefined, zoom: {} };
  }
  if (active !== undefined && idsOf(workspace).includes(active) && idsOf(next).includes(active)) {
    next = { ...next,
      tiling: next.tiling.root === undefined ? next.tiling : {...next.tiling, root: focusedRoot(next.tiling.root, active)},
      floatFocus: next.floats.some(float => windowsIn(float.root).includes(active)) ? active : undefined };
  }
  return { state: { ...state, workspaces: state.workspaces.map(item => item === workspace ? next : item) },
    memory: { ...memory, [name]: record } };
}

function floatIncoming(state: WindowState, memory: WorkspaceModeMemory, workspace: Workspace,
  record: WorkspaceModeRecord, area: Rect): WorkspaceModeTransition {
  if (workspace.fullscreen !== undefined) return {state, memory};
  const root = workspace.tiling.root;
  if (root === undefined) return { state, memory };
  const groups = columnRoots(root).map((node, index) => floatFor(node, area, workspace.floats.length + index, record.floating));
  const active = activeIdOf(state);
  const next = { ...workspace, tiling: { root: undefined, depth: 0 }, floats: [...workspace.floats, ...groups],
    floatFocus: active !== undefined && windowsIn(root).includes(active) ? active : workspace.floatFocus };
  const incoming = new Set(windowsIn(root));
  return { state: { ...state, workspaces: state.workspaces.map(item => item === workspace ? next : item) },
    memory: { ...memory, [workspace.name]: { ...record,
      tiled: { depth: record.tiled?.depth ?? 64, root: merge(pruned(record.tiled?.root, id => !incoming.has(id)), root) },
      automatic: [...new Set([...record.automatic, ...windowsIn(root)])],
      floating: [...record.floating.filter(float => !windowsIn(float.root).some(id => incoming.has(id))), ...groups] } } };
}

/** New normal windows inherit their workspace's mode; existing explicit floats
 * keep their rectangles. Call after the ordinary window reducer transaction. */
export function reconcileWorkspaceModes(state: WindowState, memory: WorkspaceModeMemory,
  areaFor: (workspace: string) => Rect | undefined): WorkspaceModeTransition {
  let result = {state, memory};
  for (const workspace of state.workspaces) {
    if (workspaceModeOf(result.memory, workspace.name) !== "floating") continue;
    const area = areaFor(workspace.name);
    if (area === undefined) continue;
    result = setWorkspaceMode(result.state, result.memory, workspace.name, "floating", area);
  }
  return result;
}

/** Cache mode-owned float positions for returning after the next mode switch. */
export function rememberFloatingGeometry(state: WindowState, memory: WorkspaceModeMemory): WorkspaceModeMemory {
  let next = memory;
  for (const workspace of state.workspaces) {
    const record = memory[workspace.name];
    if (record?.mode !== "floating" || workspace.fullscreen !== undefined) continue;
    const live = new Set(idsOf(workspace));
    const automatic = record.automatic.filter(id => live.has(id));
    const floating = workspace.floats.filter(float => windowsIn(float.root).every(id => automatic.includes(id)));
    if (JSON.stringify([record.automatic, record.floating]) !== JSON.stringify([automatic, floating]))
      next = { ...next, [workspace.name]: { ...record, automatic, floating } };
  }
  return next;
}

/** Zoom fills the usable area without telling an app it is fullscreen. */
export function toggleWindowZoom(state: WindowState, memory: WorkspaceModeMemory, id: string, area: Rect): WorkspaceModeTransition {
  const workspace = state.workspaces.find(item => item.floats.some(float => windowsIn(float.root).includes(id)));
  const floating = workspace?.floats.find(float => windowsIn(float.root).includes(id));
  if (workspace === undefined || floating === undefined) return {state, memory};
  const record: WorkspaceModeRecord = memory[workspace.name] ?? {mode: "scrolling", automatic: [], floating: [], zoom: {}};
  const anchor = windowsIn(floating.root)[0]!;
  const saved = record.zoom[anchor];
  const zoom = { ...record.zoom };
  if (saved !== undefined) delete zoom[anchor];
  else zoom[anchor] = {x: floating.x, y: floating.y, width: floating.width, height: floating.height};
  return { state: reduceWindows(state, WindowAction.WindowResized(id, saved ?? area)),
    memory: { ...memory, [workspace.name]: { ...record, zoom } } };
}

const object = (value: unknown): Record<string, unknown> => {
  if (typeof value !== "object" || value === null || Array.isArray(value)) throw Error("Invalid workspace mode state");
  return value as Record<string, unknown>;
};
const number = (value: unknown, min = 0, max = 1e7): number => {
  if (typeof value !== "number" || !Number.isFinite(value) || value < min || value > max) throw Error("Invalid workspace mode geometry");
  return value;
};
const id = (value: unknown): string => {
  if (typeof value !== "string" || value.length > 512 || !/^(app|browser):.+/.test(value) || /[\x00-\x1f\x7f]/.test(value)) throw Error("Invalid workspace mode window identity");
  return value;
};
const rect = (value: unknown): Rect => { const v = object(value); return {x: number(v.x, -1e7), y: number(v.y, -1e7), width: number(v.width, .001), height: number(v.height, .001)}; };

/** Decode the private persistence payload only after the caller checks its
 * desktop-process identity. Arbitrary commands, titles and URLs are absent. */
export function decodeWorkspaceModes(value: unknown): WorkspaceModeMemory {
  const payload = object(value);
  const memory: Record<string, WorkspaceModeRecord> = {};
  let count = 0;
  const tree = (value: unknown, depth = 0): Node => {
    if (++count > 16384 || depth > 64) throw Error("Workspace mode tree limit");
    const node = object(value);
    if (node.kind === 1) {
      const focusedAt = number(node.focusedAt, 0, Number.MAX_SAFE_INTEGER);
      if (!Number.isSafeInteger(focusedAt)) throw Error("Invalid workspace mode focus order");
      return {kind: 1, id: id(node.id), focusedAt};
    }
    if (node.kind !== 0 || ![0,1,2,3].includes(node.layout as number) || !Array.isArray(node.children) ||
      node.children.length === 0 || !Array.isArray(node.fractions) || node.children.length !== node.fractions.length)
      throw Error("Invalid workspace mode tree");
    const focused = number(node.focused, 0, node.children.length - 1);
    if (!Number.isSafeInteger(focused)) throw Error("Invalid workspace mode selection");
    const fractions = node.fractions.map(value => number(value, 0, 1));
    if (Math.abs(fractions.reduce((sum, n) => sum + n, 0) - 1) > 1e-6) throw Error("Invalid workspace mode shares");
    return {kind: 0, layout: node.layout as 0|1|2|3, focused, fractions, children: node.children.map(child => tree(child, depth + 1))};
  };
  const tiling = (value: unknown): Tiling => {
    const v = object(value), depth = number(v.depth, 0, 64);
    if (!Number.isSafeInteger(depth)) throw Error("Invalid workspace mode depth");
    return {depth, root: v.root === undefined ? undefined : tree(v.root)};
  };
  const float = (value: unknown): Float => {
    const v = object(value);
    if (typeof v.bare !== "boolean" || typeof v.scratchpad !== "boolean") throw Error("Invalid saved floating flags");
    const depth = number(v.depth, 0, 64);
    if (!Number.isSafeInteger(depth)) throw Error("Invalid saved floating depth");
    return {...rect(v), depth, root: tree(v.root), bare: v.bare, scratchpad: v.scratchpad};
  };
  for (const [name, raw] of Object.entries(payload)) {
    if (!/^(?:[1-9]|10)$/.test(name)) throw Error("Invalid workspace mode name");
    const record = object(raw);
    if (record.mode !== "scrolling" && record.mode !== "floating") throw Error("Invalid workspace mode");
    if (!Array.isArray(record.automatic) || record.automatic.length > 4096 || !Array.isArray(record.floating) || record.floating.length > 4096)
      throw Error("Workspace mode window limit");
    const zoom: Record<string, Rect> = {};
    const zoomEntries = Object.entries(object(record.zoom));
    if (zoomEntries.length > 4096) throw Error("Workspace mode zoom limit");
    for (const [key, value] of zoomEntries) zoom[id(key)] = rect(value);
    const automatic = record.automatic.map(id);
    if (new Set(automatic).size !== automatic.length) throw Error("Duplicate workspace mode window");
    memory[name] = {mode: record.mode, automatic, floating: record.floating.map(float), zoom,
      tiled: record.tiled === undefined ? undefined : tiling(record.tiled)};
    const groups = memory[name]!.floating.flatMap(item => windowsIn(item.root));
    const tiledIds = memory[name]!.tiled?.root === undefined ? [] : windowsIn(memory[name]!.tiled!.root!);
    if (new Set(groups).size !== groups.length || new Set(tiledIds).size !== tiledIds.length)
      throw Error("Duplicate workspace mode layout window");
  }
  return memory;
}
