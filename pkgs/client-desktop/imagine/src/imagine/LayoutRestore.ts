import { WindowKind } from "@domicile-desktop/manganese-window-management/window";
import type { WindowState } from "@domicile-desktop/manganese-window-management/window-state";
import { applyWorkspaceHomes } from "./policy";
import type { AgencyPolicy } from "./policy";
import type { Snapshot } from "./ipc/snapshot";

type Node = NonNullable<WindowState["workspaces"][number]["tiling"]["root"]>;
const integer = (n: number) => { if (!Number.isSafeInteger(n) || n < 0) throw Error("Invalid saved layout"); return n; };
const finite = (n: number) => { if (!Number.isFinite(n)) throw Error("Invalid saved geometry"); return n; };
const layouts = { "split-horizontal": 0, "split-vertical": 1, stacking: 2, tabbed: 3 } as const;
const merge = (a: Node | undefined, b: Node | undefined): Node | undefined => a === undefined ? b : b === undefined ? a :
  { kind: 0, layout: 0, children: [a, b], fractions: [.5, .5], focused: 0 };
function prune(node: Node | undefined, keep: (id: string) => boolean): Node | undefined {
  if (node === undefined) return;
  if ("id" in node) return keep(node.id) ? node : undefined;
  const children = node.children.map((child, at) => ({ node: prune(child, keep), share: node.fractions[at]!, at })).filter(x => x.node !== undefined);
  if (!children.length) return;
  const sum = children.reduce((n, x) => n + x.share, 0);
  return { ...node, children: children.map(x => x.node!), fractions: children.map(x => sum > 0 ? x.share / sum : 1 / children.length),
    focused: Math.max(0, children.findIndex(x => x.at === node.focused)) };
}

/** Restore layout only, retaining the SDK's current windows and display geometry.
 * The caller first verifies the desktop-process identity. Never spawn/reopen. */
export function restoreLayout(before: WindowState, snapshot: Snapshot, policy: AgencyPolicy = {}): WindowState {
  if (!Array.isArray(snapshot.windows) || snapshot.windows.length > 4096 || !Array.isArray(snapshot.workspaces) || snapshot.workspaces.length !== 10) throw Error("Invalid saved desktop");
  const matches = new Set(snapshot.windows.filter(old => before.windows.some(window => window.id === old.id.value &&
    (old.kind === "native" ? window.kind === WindowKind.App && window.appId === old.nativeId?.value && window.desktopId === (old.desktopAppId?.value ?? "") : window.kind !== WindowKind.App)))
    .map(window => window.id.value));
  const used = new Set<string>(); let nodes = 0;
  const tree = (value: Snapshot["workspaces"][number]["tiling"]["root"], depth = 0): Node | undefined => {
    if (value === null) return;
    if (++nodes > 16384 || depth > 64) throw Error("Saved layout exceeds its limit");
    if (value.kind === "window") {
      const id = value.window.value;
      if (!matches.has(id)) return;
      if (used.has(id)) throw Error("Duplicate saved window");
      used.add(id); return { kind: 1, id, focusedAt: integer(value.focusedAt) };
    }
    if (!Object.hasOwn(layouts, value.layout) || !value.children.length || value.children.length > 4096 || value.fractions.length !== value.children.length) throw Error("Invalid saved container");
    const focused = integer(value.focusedChild);
    if (focused >= value.children.length) throw Error("Invalid saved selection");
    const children = value.children.map((child, at) => ({ node: tree(child, depth + 1), at, share: finite(value.fractions[at]!) })).filter(x => x.node !== undefined);
    if (value.fractions.some(n => n < 0) || !children.length) return;
    const sum = children.reduce((n, x) => n + x.share, 0);
    return { kind: 0, layout: layouts[value.layout], children: children.map(x => x.node!),
      fractions: children.map(x => sum > 0 ? x.share / sum : 1 / children.length), focused: Math.max(0, children.findIndex(x => x.at === focused)) };
  };
  const names = new Set<string>();
  const workspaces = before.workspaces.map(current => {
    const saved = snapshot.workspaces.find(w => w.name === current.name);
    if (!saved || names.has(saved.name)) throw Error("Invalid saved workspaces");
    names.add(saved.name);
    const root = tree(saved.tiling.root);
    const floats = saved.floats.flatMap(f => {
      const node = tree(f.root); if (!node) return [];
      const { x, y, width, height } = f.rect;
      if (width <= 0 || height <= 0 || typeof f.bare !== "boolean" || typeof f.scratchpad !== "boolean") throw Error("Invalid saved float");
      return [{ x: finite(x), y: finite(y), width: finite(width), height: finite(height), bare: f.bare, scratchpad: f.scratchpad, depth: integer(f.depth), root: node }];
    });
    const extra = (id: string) => !matches.has(id);
    const extraFloats = current.floats.flatMap(f => { const root = prune(f.root, extra); return root ? [{ ...f, root }] : []; });
    const full = saved.fullscreen;
    return { ...current, tiling: { depth: integer(saved.tiling.depth), root: merge(root, prune(current.tiling.root, extra)) }, floats: [...floats, ...extraFloats],
      floatFocus: saved.floatFocus && matches.has(saved.floatFocus.value) ? saved.floatFocus.value : undefined,
      fullscreen: full && matches.has(full.window.value) ? { id: full.window.value, up: integer(full.up), global: full.global, ...(full.bare ? { bare: true as const } : {}), ...(full.byPage ? { byPage: true as const } : {}) } : undefined };
  });
  const hidden = (items: readonly {value: string}[]) => items.filter(item => matches.has(item.value)).map(item => {
    if (used.has(item.value)) throw Error("Duplicate hidden window"); used.add(item.value); return item.value;
  });
  const scratchpad = [...hidden(snapshot.scratchpad.windows), ...before.scratchpad.filter(id => !matches.has(id))];
  const background = [...hidden(snapshot.background), ...before.background.filter(id => !matches.has(id))];
  // Old unplaced windows remain unplaced. Unknown windows keep their fresh placement.
  const screens = before.screens.map(screen => {
    const old = snapshot.outputs.find(output => output.id.value === screen.name);
    return old && before.workspaces.some(w => w.name === old.visibleWorkspace.value) ? { ...screen, current: old.visibleWorkspace.value } : screen;
  });
  if (new Set(screens.map(s => s.current)).size !== screens.length) throw Error("Duplicated saved workspace visibility");
  const focused = snapshot.focus.output?.value;
  const nativeFocus = snapshot.focus.nativeWindow?.value;
  return applyWorkspaceHomes({ ...before, workspaces, scratchpad, background, screens,
    focused: screens.some(s => s.name === focused) ? focused! : before.focused,
    focusedId: nativeFocus && before.windows.some(w => w.kind === WindowKind.App && w.appId === nativeFocus) ? "app:" + nativeFocus : undefined,
    replayed: true }, policy);
}
