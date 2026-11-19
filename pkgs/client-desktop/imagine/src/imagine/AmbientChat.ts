// A viewer is disposable; the NAS DSH session is not owned by this controller.
// Only public stock67 SDK/window-management contracts are used here.
import type { BrowserWindow } from "@domicile-desktop/sdk/desktop/browser";
import type { Rect } from "@domicile-desktop/manganese-window-management/rect";
import { browserWindowId } from "@domicile-desktop/manganese-window-management/window";
import { reduceWindows, WindowAction, workspaceHolding } from "@domicile-desktop/manganese-window-management/window-state";
import type { WindowState } from "@domicile-desktop/manganese-window-management/window-state";

export const AMBIENT_CHAT_APP_ID = "agency-chat-ambient";
export const AMBIENT_CHAT_APPS: readonly string[] = Object.freeze([AMBIENT_CHAT_APP_ID]);

/** Client configuration only. No URL, browser token or provider state. */
export type AmbientChatOptions = {
  /** One reviewed client executable, looked up on PATH or given absolutely. */
  readonly launcher: string;
  readonly width?: number;
  readonly height?: number;
};
export type AmbientChatConfig = {
  readonly launcher: string;
  readonly width: number;
  readonly height: number;
};

/** Default disabled; a launcher is never inferred from the presence of DSH. */
export const ambientChatConfig = (options: AmbientChatOptions | undefined): AmbientChatConfig | undefined => {
  if (options === undefined) return undefined;
  if (!options.launcher || /[\s\0?#]/u.test(options.launcher) || options.launcher.includes("://")) {
    throw Error("Imagine ambient chat requires one executable path without arguments or a URL");
  }
  const width = options.width ?? 640;
  const height = options.height ?? 480;
  if (![width, height].every((value) => Number.isFinite(value) && value >= 120 && value <= 8192)) {
    throw Error("Imagine ambient chat dimensions must be finite and between 120 and 8192");
  }
  return Object.freeze({ launcher: options.launcher, width, height });
};

type Workspace = WindowState["workspaces"][number];
type Node = NonNullable<Workspace["tiling"]["root"]>;
const contains = (node: Node | undefined, id: string): boolean => node !== undefined &&
  ("id" in node ? node.id === id : node.children.some((child) => contains(child, id)));
const floating = (state: WindowState, id: string): boolean =>
  workspaceHolding(state, id)?.floats.some((float) => contains(float.root, id)) ?? false;

export type AmbientTarget = { readonly screen: string; readonly workspace: string };
export const ambientTarget = (state: WindowState): AmbientTarget | undefined => {
  const screen = state.screens.find(({ name }) => name === state.focused);
  return screen === undefined ? undefined : { screen: screen.name, workspace: screen.current };
};
const stillHere = (state: WindowState, target: AmbientTarget): boolean =>
  state.focused === target.screen && state.screens.some(({ name, current }) =>
    name === target.screen && current === target.workspace);

export type AmbientObservation =
  | { readonly kind: "unlisted" | "absent" }
  | { readonly kind: "error"; readonly error: string }
  | { readonly kind: "window"; readonly id: string; readonly shown: boolean };

/** Never derive app ownership from title, URL or a package desktop-entry name. */
export const observeAmbient = (state: WindowState, browsers: readonly BrowserWindow[] | undefined): AmbientObservation => {
  if (browsers === undefined) return { kind: "unlisted" };
  const matches = browsers.filter((window) => window.isApp && window.appId === AMBIENT_CHAT_APP_ID);
  if (matches.length > 1) return { kind: "error", error: "duplicate ambient app windows" };
  const found = matches[0];
  if (found === undefined) return { kind: "absent" };
  const id = browserWindowId(found.id);
  // The SDK list can precede its reducer event. Wait instead of adopting a
  // normal window before exact background membership has been established.
  if (!state.windows.some((window) => window.id === id)) return { kind: "unlisted" };
  if (!state.background.includes(id)) return { kind: "error", error: "ambient window is not retained as a background app" };
  return { kind: "window", id, shown: workspaceHolding(state, id) !== undefined };
};

/** Atomic local reducer transaction; not a new SDK/IPC action authority. */
export type AmbientTransition = {
  readonly ambient: true;
  readonly id: string;
  readonly visible: boolean;
  readonly target: AmbientTarget;
  readonly size: Pick<Rect, "width" | "height">;
};

/**
 * Evaluate against the reducer's current state, so two commands before the
 * next paint cannot accidentally toggle a float back into the tiling. A hide
 * never uses the generic scratchpad and never asks a guest/process to close.
 */
export const planAmbient = (state: WindowState, transition: AmbientTransition,
  reduce: (before: WindowState, action: WindowAction) => WindowState): {
    readonly state: WindowState;
    readonly geometry?: Rect;
    readonly error?: string;
  } => {
  const { id, target } = transition;
  if (!state.background.includes(id) || !state.windows.some((window) => window.id === id)) return { state };
  if (!transition.visible) return { state: reduce(state, WindowAction.WindowClosed(id)) };
  if (!stillHere(state, target)) return { state };
  const screen = state.screens.find(({ name }) => name === target.screen);
  if (screen === undefined) return { state };
  const held = workspaceHolding(state, id);
  const onTarget = held?.name === target.workspace;
  const alreadyFloating = floating(state, id);
  let next = held !== undefined && !onTarget ? reduce(state, WindowAction.WindowClosed(id)) : state;
  next = reduce(next, WindowAction.FocusRequested(id));
  if (!floating(next, id)) next = reduce(next, WindowAction.WindowFloated(id));
  if (!onTarget || !alreadyFloating) {
    // Float boxes are screen-relative. The native reducer, rather than a
    // copied private constant, remains the authority for minimum dimensions.
    const width = Math.max(1, Math.min(transition.size.width, screen.box.width));
    const height = Math.max(1, Math.min(transition.size.height, screen.box.height));
    next = reduce(next, WindowAction.WindowResized(id, {
      width, height, x: Math.max(0, (screen.box.width - width) / 2),
      y: Math.max(0, screen.box.height - height - Math.min(24, screen.box.height - height)),
    }));
  }
  const actual = workspaceHolding(next, id)?.floats.find((float) => contains(float.root, id));
  if (actual === undefined) return { state, error: "native window did not become floating" };
  if (actual.width > screen.box.width || actual.height > screen.box.height) {
    return { state, error: "focused output cannot contain the native floating minimum" };
  }
  // A requested size below the native minimum may have grown. Centre the
  // actual feasible size, not the wish; refuse an impossible fit above.
  if (!onTarget || !alreadyFloating) next = reduce(next, WindowAction.WindowResized(id, {
    width: actual.width, height: actual.height,
    x: (screen.box.width - actual.width) / 2,
    y: Math.max(0, screen.box.height - actual.height - Math.min(24, screen.box.height - actual.height)),
  }));
  const placed = workspaceHolding(next, id)?.floats.find((float) => contains(float.root, id));
  return { state: next, geometry: placed === undefined ? undefined : {
    width: placed.width, height: placed.height, x: placed.x, y: placed.y,
  } };
};

export const reduceAmbient = (state: WindowState, transition: AmbientTransition,
  reduce: (before: WindowState, action: WindowAction) => WindowState): WindowState =>
  planAmbient(state, transition, reduce).state;

export type AmbientSnapshot = {
  readonly state: WindowState;
  readonly browsers: readonly BrowserWindow[] | undefined;
  readonly blocked: boolean;
};
export type AmbientPorts = {
  readonly read: () => AmbientSnapshot;
  readonly transition: (update: AmbientTransition) => void;
  /** The launcher returns only after native open_app acknowledges. */
  readonly launch: (argv: readonly string[]) => Promise<void>;
  readonly report: (message: string) => void;
  readonly schedule?: (callback: () => void, ms: number) => () => void;
};
type Intent = { visible: boolean; target: AmbientTarget; sent: boolean };
type Opening = { completed: boolean; listed: boolean; timedOut: boolean; cancelDeadline: () => void };

/** Owns one launch and one absolute intent; DOM/DSH state is never mirrored. */
export const createAmbientChat = (config: AmbientChatConfig, ports: AmbientPorts) => {
  let disposed = false;
  let intent: Intent | undefined;
  let opening: Opening | undefined;
  const schedule = ports.schedule ?? ((callback: () => void, ms: number) => {
    const timer = setTimeout(callback, ms); return () => clearTimeout(timer);
  });
  const report = (message: string) => ports.report(`Imagine ambient chat: ${message}`);
  const finishOpening = () => { opening?.cancelDeadline(); opening = undefined; };
  const reconcile = () => {
    if (disposed) return;
    const current = ports.read();
    const observed = observeAmbient(current.state, current.browsers);
    if (current.blocked) { intent = undefined; return; }
    if (observed.kind === "error") {
      if (intent !== undefined) report(observed.error);
      intent = undefined; return;
    }
    if (observed.kind !== "window") {
      if (observed.kind === "absent" && opening === undefined) intent = undefined;
      return;
    }
    if (opening !== undefined) {
      opening.listed = true;
      if (opening.completed) finishOpening();
    }
    if (intent === undefined) return;
    if (intent.visible && !stillHere(current.state, intent.target)) {
      // New user navigation wins over a slow SSH/bootstrap completion.
      intent = undefined; return;
    }
    if (intent.sent) {
      const held = workspaceHolding(current.state, observed.id);
      if (intent.visible ? held?.name === intent.target.workspace && floating(current.state, observed.id) : !observed.shown) {
        intent = undefined;
      }
      return;
    }
    const transition: AmbientTransition = { ambient: true, id: observed.id, visible: intent.visible,
      target: intent.target, size: config };
    const planned = planAmbient(current.state, transition, reduceWindows);
    if (planned.error !== undefined) { report(planned.error); intent = undefined; return; }
    intent.sent = true;
    ports.transition(transition);
  };
  const launch = () => {
    if (opening !== undefined) return;
    const run: Opening = { completed: false, listed: false, timedOut: false, cancelDeadline: () => undefined };
    opening = run;
    run.cancelDeadline = schedule(() => {
      if (disposed || opening !== run) return;
      run.timedOut = true; intent = undefined;
      report("launcher or browser-list acknowledgement timed out; no automatic retry");
      if (run.completed) finishOpening();
    }, 30000);
    // A failed/timed-out launcher never closes a late guest or retries a
    // provider. Keeping a still-running call guarded prevents duplicate exec.
    let launched: Promise<void>;
    try { launched = ports.launch([config.launcher]); }
    catch { launched = Promise.reject(Error("launcher failed")); }
    launched.then(() => {
      if (disposed || opening !== run) return;
      run.completed = true;
      if (run.timedOut || run.listed) finishOpening();
      reconcile();
    }, () => {
      if (disposed || opening !== run) return;
      intent = undefined; finishOpening(); report("launcher failed; existing viewers were left intact");
    });
  };
  return {
    /** Words after `imagine`; no binding is installed by this module. */
    command(args: readonly string[]): boolean {
      if (args[0] !== "ambient-chat") return false;
      if (disposed) return true;
      const operation = args[1];
      if (args.length !== 2 || !["show", "hide", "toggle"].includes(operation ?? "")) {
        report("usage: imagine ambient-chat show|hide|toggle"); return true;
      }
      const current = ports.read();
      if (current.blocked) { intent = undefined; report("desktop lock or modal owns the keyboard"); return true; }
      const observed = observeAmbient(current.state, current.browsers);
      if (observed.kind === "error") { report(observed.error); return true; }
      if (observed.kind === "unlisted") { report("browser list is not ready; no viewer was opened"); return true; }
      const target = ambientTarget(current.state);
      if (target === undefined) { report("no focused output is available"); return true; }
      const visible = operation === "toggle" ? !(intent?.visible ?? (observed.kind === "window" && observed.shown)) : operation === "show";
      intent = { visible, target, sent: false };
      if (observed.kind === "absent") {
        if (visible) launch();
        if (opening === undefined) intent = undefined;
      } else reconcile();
      return true;
    },
    reconcile,
    /** Owned hidden pages cannot steal focus through window.focus/load. */
    consumesFocusRequest(id: string): boolean {
      if (disposed) return false;
      return ports.read().browsers?.some((window) => window.isApp && window.appId === AMBIENT_CHAT_APP_ID
        && browserWindowId(window.id) === id) ?? false;
    },
    dispose() {
      disposed = true; intent = undefined; finishOpening();
      // The launched helper/guest may complete later. Never kill either.
    },
  };
};
