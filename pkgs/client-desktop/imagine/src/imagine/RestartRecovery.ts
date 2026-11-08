import { WindowKind } from "@domicile-desktop/manganese-window-management/window";
import type { WindowState } from "@domicile-desktop/manganese-window-management/window-state";
import type { CatalogueState } from "./SessionCatalogue";
import { restoreLayout } from "./LayoutRestore";
import { projectSnapshot } from "./ipc/snapshot";
import type { Snapshot, Tree } from "./ipc/snapshot";

export type RecoveryRoute = { kind: "web"; server: string; tag: string } | { kind: "chat"; server: string; session: string; tag: string } |
  { kind: "terminal"; server: string; session: string; terminal: string };
export type RecoverySlot = { savedWindow: string; route: RecoveryRoute };
export type RecoveryCheckpoint = { version: 1; incarnation: string; savedAt: number;
  pinned?: true; snapshot: Snapshot; slots: readonly RecoverySlot[]; omitted: number };
export type RecoveryBinding = { savedWindow: string; window: string };

/** The checkpoint grants no execution authority. Only DSH viewer identities are
 * recoverable; ordinary applications remain listed as omitted. */
export function captureRecovery(state: WindowState, catalogue: CatalogueState, server: string,
  incarnation: string, savedAt = Date.now()): RecoveryCheckpoint {
  return captureSnapshotRecovery(projectSnapshot({ state, screens: [] }), catalogue, server, incarnation, savedAt);
}

/** Also used by the bounded pre-restart exporter, which consumes the existing
 * read-only snapshot protocol and the owner's viewer metadata. */
export function captureSnapshotRecovery(snapshot: Snapshot, catalogue: Pick<CatalogueState, "viewers" | "mainViewers" | "terminals">,
  server: string, incarnation: string, savedAt = Date.now()): RecoveryCheckpoint {
  const slots: RecoverySlot[] = [], sessions = new Set<string>();
  const native = snapshot.windows.filter(w => w.kind === "native");
  for (const tag of catalogue.mainViewers) {
    const matches = native.filter(w => w.desktopAppId?.value.includes(tag));
    if (matches.length === 1 && !slots.some(s => s.savedWindow === matches[0]!.id.value)) slots.push({ savedWindow: matches[0]!.id.value, route: { kind: "web", server, tag } });
  }
  // Migrate only the declared legacy Agency Web app. No URL, title, generic
  // browser tab or ambient layer can become a launch command or session id.
  const legacy = snapshot.windows.filter(w => w.kind === "browser" && w.appId?.value === "agency-web" && !w.isPrivate);
  if (legacy.length === 1 && !slots.some(s => s.route.kind === "web")) slots.push({
    savedWindow: legacy[0]!.id.value, route: { kind: "web", server, tag: "agencychat" + incarnation.slice(0, 32) },
  });
  for (const viewer of catalogue.viewers) {
    const matches = native.filter(w => w.desktopAppId?.value.includes(viewer.tag));
    if (matches.length !== 1 || sessions.has(viewer.sessionId) || slots.some(s => s.savedWindow === matches[0]!.id.value)) continue;
    sessions.add(viewer.sessionId);
    slots.push({ savedWindow: matches[0]!.id.value, route: { kind: "chat", server, session: viewer.sessionId, tag: viewer.tag } });
  }
  for (const { route } of catalogue.terminals) {
    const matches = native.filter(w => w.desktopAppId?.value === route.windowClass);
    if (matches.length !== 1 || slots.some(s => s.savedWindow === matches[0]!.id.value)) continue;
    slots.push({ savedWindow: matches[0]!.id.value, route: { kind: "terminal", server: route.server, session: route.session, terminal: route.terminal } });
  }
  return { version: 1, incarnation, savedAt, snapshot, slots, omitted: snapshot.windows.length - slots.length };
}

/** Rebind only explicitly resolved new SDK windows, never saved app-N IDs.
 * Missing leaves are pruned before names can collide after a restart. */
export function rebindRecovery(checkpoint: RecoveryCheckpoint, state: WindowState,
  bindings: readonly RecoveryBinding[], reveal: boolean): Snapshot {
  const ids = new Map<string, string>(), used = new Set<string>();
  for (const binding of bindings) {
    if (!checkpoint.slots.some(s => s.savedWindow === binding.savedWindow) || ids.has(binding.savedWindow) || used.has(binding.window) ||
      !state.windows.some(w => w.id === binding.window && w.kind === WindowKind.App)) throw Error("Invalid recovered viewer binding");
    ids.set(binding.savedWindow, binding.window); used.add(binding.window);
  }
  const current = projectSnapshot({ state, screens: [] });
  let nodes = 0;
  const tree = (old: Tree | null, depth = 0): Tree | null => {
    if (old === null) return null;
    if (++nodes > 16384 || depth > 64) throw Error("Recovery tree exceeds its limit");
    if (old.kind === "window") {
      const value = ids.get(old.window.value);
      return value === undefined ? null : { ...old, window: { kind: "window", value } };
    }
    const kept = old.children.map((child, at) => ({ child: tree(child, depth + 1), at })).filter(x => x.child !== null);
    if (kept.length === 0) return null;
    return { ...old, children: kept.map(x => x.child!), fractions: kept.map(x => old.fractions[x.at]!),
      focusedChild: Math.max(0, kept.findIndex(x => x.at === old.focusedChild)) };
  };
  const ref = (old: { kind: "window"; value: string } | null) => {
    const value = old === null ? undefined : ids.get(old.value);
    return value === undefined ? null : { kind: "window" as const, value };
  };
  const snapshot = checkpoint.snapshot;
  const oldFocus = snapshot.windows.find(w => w.kind === "native" && w.nativeId?.value === snapshot.focus.nativeWindow?.value);
  const focusWindow = ids.get(snapshot.focus.shellWindow?.value ?? oldFocus?.id.value ?? "");
  const newFocus = state.windows.find(w => w.id === focusWindow && w.kind === WindowKind.App);
  const rebound: Snapshot = { ...snapshot,
    windows: current.windows.filter(w => used.has(w.id.value)),
    workspaces: snapshot.workspaces.map(w => ({ ...w,
      tiling: { ...w.tiling, root: tree(w.tiling.root) },
      floats: w.floats.flatMap(f => { const root = tree(f.root); return root === null ? [] : [{ ...f, root }]; }),
      floatFocus: ref(w.floatFocus),
      fullscreen: w.fullscreen && ref(w.fullscreen.window) ? { ...w.fullscreen, window: ref(w.fullscreen.window)! } : null,
      enclosedWindows: w.enclosedWindows.flatMap(w => ref(w) ?? []),
    })),
    scratchpad: { ...snapshot.scratchpad, windows: snapshot.scratchpad.windows.flatMap(w => ref(w) ?? []) },
    background: snapshot.background.flatMap(w => ref(w) ?? []), unplaced: snapshot.unplaced.flatMap(w => ref(w) ?? []),
    outputs: reveal ? snapshot.outputs : current.outputs,
    focus: reveal ? { ...snapshot.focus, shellWindow: ref(snapshot.focus.shellWindow),
      nativeWindow: newFocus?.kind === WindowKind.App ? { kind: "native-window", value: newFocus.appId } : null } : current.focus,
    popups: [],
  };
  restoreLayout(state, rebound); // Validate the whole rebound graph before dispatch.
  return rebound;
}

/** Corrupt checkpoints stay on disk for inspection and never become commands. */
export function decodeRecovery(text: string): RecoveryCheckpoint {
  if (text.length > 8 * 1024 * 1024) throw Error("Recovery checkpoint exceeds its limit");
  const value = JSON.parse(text) as RecoveryCheckpoint;
  const identity = (x: unknown) => typeof x === "string" && /^[\w-]{1,128}$/.test(x);
  if ((value.pinned !== undefined && value.pinned !== true) || value.version !== 1 || !/^[a-f0-9]{64}$/.test(value.incarnation) || !Number.isSafeInteger(value.savedAt) || value.savedAt < 0 ||
    !Number.isSafeInteger(value.omitted) || value.omitted < 0 || !Array.isArray(value.slots) || value.slots.length > 4096 ||
    !Array.isArray(value.snapshot.windows) || value.snapshot.windows.length > 4096 ||
    !Array.isArray(value.snapshot.workspaces) || value.snapshot.workspaces.length !== 10 || !Array.isArray(value.snapshot.outputs)) throw Error("Invalid recovery checkpoint");
  const saved = new Set<string>();
  for (const slot of value.slots) {
    const route = slot.route;
    if (typeof slot.savedWindow !== "string" || saved.has(slot.savedWindow) || !value.snapshot.windows.some(w => w.id.value === slot.savedWindow && (w.kind === "native" || (route.kind === "web" && w.kind === "browser" && w.appId?.value === "agency-web" && !w.isPrivate))) ||
      !identity(route.server) || (route.kind !== "web" && !identity(route.session)) || (route.kind === "chat" || route.kind === "web" ? !/^agencychat[a-f0-9]{32}$/.test(route.tag) : route.kind !== "terminal" || !identity(route.terminal))) throw Error("Invalid recovered viewer identity");
    saved.add(slot.savedWindow);
  }
  return value;
}
