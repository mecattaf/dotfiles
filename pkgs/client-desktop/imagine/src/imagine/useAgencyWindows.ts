import { isAgentDesktopId } from "./AgentWindows";
import { restoreLayout } from "./LayoutRestore";
import { useLayoutPersistence } from "./useLayoutPersistence";
import type { LayoutRestoreAction, LayoutPersistenceOptions } from "./useLayoutPersistence";
// Agency's state/effects bridge, adapted from Manganese useWindows.ts,
// window-changes.ts, window-requests.ts and open-command.ts at:
// https://github.com/cprussin/domicile/tree/67c29a9906905bd5e1679803232c2f510b3fed9e
// The public upstream reducer and SDK remain dependencies; Agency owns policy.ts.
/*
MIT License
Copyright (c) 2026 Connor Prussin
Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:
The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/
import type { Display } from "@domicile-desktop/component-library/display-source";
import type { Domicile } from "@domicile-desktop/sdk/desktop/desktop";
import type { ClientWindow } from "@domicile-desktop/sdk/desktop/windows";
import { SystemErrorKind } from "@domicile-desktop/sdk/system";
import type { WindowRequest } from "@domicile-desktop/sdk/window-state";
import { WindowRequestKind } from "@domicile-desktop/sdk/window-state";
import {
  useCallback,
  useEffect,
  useLayoutEffect,
  useMemo,
  useReducer,
  useRef,
} from "react";
import type { FloatingRules } from "@domicile-desktop/manganese-window-management/floating/floating-rules";
import { opensFloating } from "@domicile-desktop/manganese-window-management/floating/floating-rules";
import type { SizeLimit } from "@domicile-desktop/manganese-window-management/window";
import type { Listening } from "@domicile-desktop/sdk/system";
import { createAgencyReducer, DEFAULT_AGENCY_POLICY, initialAgencyState } from "./policy";
import type { AgencyPolicy } from "./policy";
import { reduceAmbient } from "./AmbientChat";
import type { AmbientTransition } from "./AmbientChat";
import { placeChatWindow, reduceChatNativeBatch } from "./ChatWindow";
import type { ChatPlacement, ChatReservation, ChatNativeBatch } from "./ChatWindow";
import { externalWebCommand } from "./WebBrowser";
import type { WebBrowserOptions } from "./WebBrowser";
import { appIdOf, appWindowId, browserIdOf } from "@domicile-desktop/manganese-window-management/window";
import type { WindowAction, WindowState } from "@domicile-desktop/manganese-window-management/window-state";
import {
  WindowAction as Action,
  activeIdOf,
  activeIsPrivate,
  closedIdsOf,
  killedIdsOf,
  WindowActionKind,
  windowsInGroup,
} from "@domicile-desktop/manganese-window-management/window-state";

export type Windows = WindowState & {
  /**
   * Dispatches a desktop action from a key binding or the chrome.
   *
   * A single entry point keeps the key bindings a table of actions. It also
   * runs the side effects the reducer cannot, such as `exec` and `kill`.
   */
  act: (action: WindowAction) => void;
  /** One atomic local background-view transaction, without process side effects. */
  transitionAmbient: (transition: AmbientTransition) => void;
  placeChat: (placement: ChatPlacement) => void;
  reserveChat: (tag: string, placement: ChatReservation | undefined) => void;
  layoutReady: boolean;
  layoutIdentity?: string;
  recoverLayout: (snapshot: import("./ipc/snapshot").Snapshot) => void;
  layoutError?: string;
  /** The active window, floating or tiled. */
  activeId: string | undefined;
};

/** No app runs in the background. One array, so the default never changes. */
const NO_BACKGROUND_APPS: readonly string[] = [];

/**
 * The desktop's windows and the actions that change them.
 *
 * Host events (clients appearing, closing, setting a cursor) and user commands
 * share one reducer. Client pixels never pass through the page: the `<app>`
 * element embeds the compositor's surface.
 *
 * @param displays - the desk the host described. `undefined` until it has
 *   described one.
 * @param floating - which client windows open floating, besides dialogs.
 * @param backgroundApps - the app ids whose app windows run in the
 *   background: they open hidden and hide when closed. See
 *   `WindowState.background`.
 * @param openFile - the argv that opens a file the launcher chose.
 */
export const useAgencyWindows = (
  domicile: Domicile,
  displays: readonly Display[] | undefined,
  floating: FloatingRules,
  backgroundApps: readonly string[] = NO_BACKGROUND_APPS,
  openFile: (path: string) => readonly string[] = openCommand,
  policy: AgencyPolicy = DEFAULT_AGENCY_POLICY,
  webBrowser?: WebBrowserOptions,
  layoutPersistence?: LayoutPersistenceOptions,
): Windows => {
  const reducer = useMemo(() => {
    const reduce = createAgencyReducer(policy);
    return (before: WindowState, action: WindowAction | AmbientTransition | ChatPlacement | ChatNativeBatch | LayoutRestoreAction) =>
      "restoreLayout" in action ? (() => { try { return restoreLayout(before, action.snapshot, policy); }
        catch { console.error("Imagine rejected saved layout"); return before; } })()
      : "ambient" in action ? reduceAmbient(before, action, reduce)
      : "chatNativeBatch" in action ? reduceChatNativeBatch(before, action, reduce)
      : "chatPlacement" in action ? placeChatWindow(before, action, reduce) : reduce(before, action);
  }, [policy]);
  const [state, dispatch] = useReducer(reducer, undefined, () => initialAgencyState(policy));
  const layout = useLayoutPersistence(domicile, state, displays !== undefined, layoutPersistence, dispatch);
  const recoverLayout = useCallback((snapshot: import("./ipc/snapshot").Snapshot) => dispatch({ restoreLayout: true, snapshot }), []);
  const transitionAmbient = useCallback((transition: AmbientTransition) => dispatch(transition), []);
  const placeChat = useCallback((placement: ChatPlacement) => dispatch(placement), []);
  const reservations = useRef(new Map<string, { placement: ChatReservation; expires: number }>());
  const reserveChat = useCallback((tag: string, placement: ChatReservation | undefined) => {
    if (placement === undefined) reservations.current.delete(tag);
    else reservations.current.set(tag, { placement, expires: Date.now() + 150000 });
  }, []);
  // The state as last drawn, for `act` to read without depending on it. A new
  // `act` would re-add every listener that runs commands.
  const drawn = useRef(state);
  useLayoutEffect(() => {
    drawn.current = state;
  }, [state]);

  // Side effects the reducer cannot perform: spawning processes, locking,
  // asking a client to close, and opening or closing browser windows. A client
  // window is removed when the host reports it closed, and a browser window
  // when the engine's list drops it. Keeping these as actions keeps the
  // reducer pure and the bindings one table.
  const act = useCallback(
    (action: WindowAction) => {
      dispatch(action);
      if (action.kind === WindowActionKind.CommandExecuted) {
        domicile.processes.launch(action.argv);
      }
      if (action.kind === WindowActionKind.DeskLocked) {
        domicile.session.lock();
      }
      if (action.kind === WindowActionKind.ScreenshotTaken) {
        takeScreenshot(domicile);
      }
      if (action.kind === WindowActionKind.FileOpened) {
        domicile.processes.launch(openFile(action.path));
      }
      if (action.kind === WindowActionKind.AppLaunched) {
        domicile.processes.launch(action.command);
      }
      if (action.kind === WindowActionKind.ClipboardSearched) {
        // From a private window, the search stays private.
        const url = clipboardUrl(domicile);
        if (url !== undefined) {
          const command = externalWebCommand(webBrowser, url, activeIsPrivate(drawn.current));
          if (command !== undefined) domicile.processes.launch(command);
          else if (activeIsPrivate(drawn.current)) {
            domicile.browser.openPrivate(url);
          } else {
            domicile.browser.open(url);
          }
        }
      }
      if (action.kind === WindowActionKind.BrowserOpened) {
        const command = externalWebCommand(webBrowser, action.src, action.isPrivate);
        if (command !== undefined) domicile.processes.launch(command);
        else if (action.isPrivate) {
          domicile.browser.openPrivate(action.src);
        } else {
          domicile.browser.open(action.src);
        }
      }
      // A background app's window hides instead; the reducer hides it.
      if (action.kind === WindowActionKind.WindowClosed) {
        closeWindows(domicile, closedIdsOf(drawn.current, [action.id]));
      }
      // A `focus parent` selection closes whole, as in sway.
      if (action.kind === WindowActionKind.WindowKilled) {
        closeWindows(
          domicile,
          closedIdsOf(drawn.current, killedIdsOf(drawn.current)),
        );
      }
      if (action.kind === WindowActionKind.GroupClosed) {
        closeWindows(
          domicile,
          closedIdsOf(
            drawn.current,
            windowsInGroup(drawn.current, action.group),
          ),
        );
      }
    },
    [domicile, openFile, webBrowser],
  );

  // The host's last window list, diffed against the next. A ref, not
  // effect-local, so a re-run effect does not announce every window again.
  const listed = useRef<readonly ClientWindow[]>([]);

  useEffect(() => {
    const { browser, windows } = domicile;
    // A client's size places only a window that opens floating; the engine's
    // pointer scaling uses it too.
    const windowsChanged = () => {
      const now = windows.list;
      const placements: ChatPlacement[] = [];
      for (const [tag, claim] of reservations.current) {
        const matches = now.filter(({ desktopId }) => desktopId.includes(tag));
        if (claim.expires < Date.now()) reservations.current.delete(tag);
        else if (matches.length === 1) {
          placements.push({ ...claim.placement, id: appWindowId(matches[0]!.appId) });
          reservations.current.delete(tag);
        }
      }
      dispatch({ chatNativeBatch: true, actions: nativeWindowActions(floating, listed.current, now), placements });
      listed.current = now;
    };
    const focusChanged = () => {
      dispatch(Action.FocusChanged(windows.focused));
    };
    // The compositor forwards the request without granting it;
    // `reduceWindows` decides.
    const focusRequested = (appId: string) => {
      if (!windows.list.some(w => w.appId === appId && isAgentDesktopId(w.desktopId)))
        dispatch(Action.FocusRequested(appWindowId(appId)));
    };
    // Every browser window, from the engine. After `domicile load-shell` it
    // holds the previous shell's windows.
    const browserWindowsChanged = () => {
      const listedBrowsers = browser.windows;
      if (listedBrowsers !== undefined) {
        dispatch(Action.BrowserWindowsListed(listedBrowsers, backgroundApps));
      }
    };
    windowsChanged();
    focusChanged();
    browserWindowsChanged();
    // `AppWindow` and `AppPopup` render each window's `frame`.
    windows.syncFrames();
    const stops = [
      windows.on("change", windowsChanged),
      windows.on("focuschange", focusChanged),
      windows.on("focusrequest", focusRequested),
      browser.on("change", browserWindowsChanged),
    ];
    return () => {
      for (const stop of stops) {
        stop();
      }
    };
  }, [backgroundApps, domicile, floating]);

  // Clients' requests, which the compositor reports without granting.
  useEffect(() => {
    const hearing = listenAgencyRequests(domicile, (request) => {
      const action = actionFor(request);
      if (action !== undefined) {
        dispatch(action);
      }
    });
    return hearing.stop;
  }, [domicile]);

  // The desk the host described, which bounds where windows can go.
  useEffect(() => {
    if (displays !== undefined) {
      dispatch(Action.ScreensDescribed(placedOf(displays)));
    }
  }, [displays, policy]);

  return useMemo(
    () => ({
      ...state,
      act,
      transitionAmbient,
      placeChat,
      reserveChat,
      activeId: activeIdOf(state),
      layoutReady: layout.ready,
      layoutIdentity: layout.identity,
      recoverLayout,
      layoutError: layout.error,
    }),
    [act, state, transitionAmbient, placeChat, reserveChat, recoverLayout, layout.ready, layout.error, layout.identity],
  );
};

/**
 * What a client's request does. Fullscreen fills the window's screen, as a
 * page's fullscreen does. Windows tile, so maximizing changes nothing.
 */
const actionFor = (request: WindowRequest): WindowAction | undefined => {
  switch (request.kind) {
    case WindowRequestKind.Fullscreen:
      return Action.PageFullscreened(appWindowId(request.appId), true);
    case WindowRequestKind.Unfullscreen:
      return Action.PageFullscreened(appWindowId(request.appId), false);
    case WindowRequestKind.Maximize:
    case WindowRequestKind.Unmaximize:
      return undefined;
  }
};

type PlacedScreen = Parameters<typeof Action.ScreensDescribed>[0][number];

/** The desk's displays as the screens the desktop is told of. */
const placedOf = (displays: readonly Display[]): readonly PlacedScreen[] =>
  displays.map(({ name, position, size }) => ({
    box: { height: size[1], width: size[0], x: position[0], y: position[1] },
    name,
  }));

/** Takes a screenshot, logging any failure but a dismissed dialog. */
const takeScreenshot = (domicile: Pick<Domicile, "capture">) => {
  domicile.capture
    .screenshot()
    .then((taken) => {
      taken.match({
        Err: (error) => {
          if (error.kind !== SystemErrorKind.Canceled) {
            // biome-ignore lint/suspicious/noConsole: surfacing a failed screenshot
            console.error("The screenshot was not saved", error);
          }
        },
        // The PNG is under `$XDG_PICTURES_DIR/Screenshots/`, or on the
        // clipboard after Ctrl+C. A portal screenshot says nothing either.
        Ok: () => undefined,
      });
    })
    .catch((error: unknown) => {
      // biome-ignore lint/suspicious/noConsole: surfacing a broken desktop call
      console.error("The screenshot was not taken", error);
    });
};

/**
 * The newest copy as a site or a search URL, or `undefined` when the clipboard
 * holds no text.
 *
 * Reads the row's preview, so a long copy is cut short.
 */
const clipboardUrl = (
  domicile: Pick<Domicile, "clipboard">,
): string | undefined => {
  const newest = domicile.clipboard.entries?.[0];
  return newest === undefined ? undefined : clipboardDestination(newest.preview);
};

/** Asks the compositor or the engine to close each window in `ids`. */
const closeWindows = (
  domicile: Pick<Domicile, "browser" | "windows">,
  ids: readonly string[],
) => {
  for (const id of ids) {
    const appId = appIdOf(id);
    if (appId !== undefined) {
      domicile.windows.close(appId);
    }
    const browser = browserIdOf(id);
    if (browser !== undefined) {
      domicile.browser.close(browser);
    }
  }
};

const SCRIPT =
  'case $1 in /*) exec xdg-open "$1" ;; *) exec xdg-open "$HOME/$1" ;; esac';

/** `$0` for the script, which prefixes `sh` error messages. */
const NAME = "domicile-launcher";

/** The argv that opens `path` with the user's default application. */
const openCommand = (path: string): readonly string[] => [
  "sh",
  "-c",
  SCRIPT,
  NAME,
  path,
];

/**
 * The window actions between two host window lists: appearances and changes
 * in `after`'s order, then closings.
 *
 * The host lists every window after any change; the reducer takes individual
 * events. A popup is placed rather than announced, since it is drawn over its
 * window, not laid out. A window `rules` or its client marks opens floating.
 */
export const nativeWindowActions = (
  rules: FloatingRules,
  before: readonly ClientWindow[],
  after: readonly ClientWindow[],
): readonly WindowAction[] => {
  // Keyed once: the host lists every window on every change.
  const was = new Map(before.map((window) => [window.appId, window]));
  const listed = new Set(after.map(({ appId }) => appId));
  return [
    ...after.flatMap((window) =>
      changesOf(rules, was.get(window.appId), window),
    ),
    ...before
      .filter(({ appId }) => !listed.has(appId))
      .map(({ appId }) => Action.AppClosed(appId)),
  ];
};

/** The changes to one window. `was` is `undefined` for a new one. */
const changesOf = (
  rules: FloatingRules,
  was: ClientWindow | undefined,
  window: ClientWindow,
): readonly WindowAction[] =>
  window.parent === undefined
    ? toplevelChanges(rules, was, window)
    : popupChanges(was, window, window.parent);

const toplevelChanges = (
  rules: FloatingRules,
  was: ClientWindow | undefined,
  window: ClientWindow,
): readonly WindowAction[] => {
  const { appId } = window;
  const before = was ?? { ...window, ...UNSAID };
  const minSize = limitOf(window.minWidth, window.minHeight);
  const maxSize = limitOf(window.maxWidth, window.maxHeight);
  return [
    ...(was === undefined ? [appeared(rules, window)] : []),
    ...(was !== undefined && before.title !== window.title
      ? [Action.AppTitled(appId, named(window.title))]
      : []),
    ...(sameLimit(limitOf(before.minWidth, before.minHeight), minSize)
      ? []
      : [Action.AppMinSize(appId, minSize)]),
    ...(sameLimit(limitOf(before.maxWidth, before.maxHeight), maxSize)
      ? []
      : [Action.AppMaxSize(appId, maxSize)]),
    ...(before.cursor === window.cursor
      ? []
      : [Action.AppCursorChanged(appId, window.cursor)]),
    ...(before.desktopId === window.desktopId
      ? []
      : [Action.AppDesktopIdChanged(appId, window.desktopId)]),
    ...(before.frame === window.frame
      ? []
      : [Action.AppFrameSynced(appId, window.frame)]),
  ];
};

const popupChanges = (
  was: ClientWindow | undefined,
  window: ClientWindow,
  parent: string,
): readonly WindowAction[] =>
  was !== undefined &&
  was.parent === parent &&
  was.x === window.x &&
  was.y === window.y &&
  was.width === window.width &&
  was.height === window.height &&
  was.frame === window.frame
    ? []
    : [Action.PopupPlaced(popupOf(window, parent))];

/** A window's state before its client has sent anything. */
const UNSAID = {
  cursor: "default",
  desktopId: "",
  frame: 0,
  maxHeight: undefined,
  maxWidth: undefined,
  minHeight: undefined,
  minWidth: undefined,
} as const;

/** The action that opens a new window, tiled or floating. */
const appeared = (rules: FloatingRules, window: ClientWindow): WindowAction => {
  const { appId, clientFrame, height, title, width } = window;
  if (!opensFloating(rules, window)) {
    return Action.AppAppeared(appId, named(title));
  } else if (width === undefined || height === undefined) {
    throw new Error(`windows: ${appId} is listed before it drew`);
  } else {
    return Action.AppAppearedFloating(
      appId,
      named(title),
      [width, height],
      clientFrame,
    );
  }
};

/** A popup's placement. */
const popupOf = (window: ClientWindow, parent: string): Parameters<typeof Action.PopupPlaced>[0] => {
  const { height, width, x, y } = window;
  if (
    x === undefined ||
    y === undefined ||
    width === undefined ||
    height === undefined
  ) {
    throw new Error(`shell: popup ${window.appId} is listed with no place`);
  } else {
    return {
      appId: window.appId,
      frame: window.frame,
      parent,
      position: [x, y],
      size: [width, height],
    };
  }
};

const limitOf = (
  width: number | undefined,
  height: number | undefined,
): SizeLimit => [width, height];

const sameLimit = (a: SizeLimit, b: SizeLimit): boolean =>
  a[0] === b[0] && a[1] === b[1];

/** A title, or `undefined` for an untitled window. */
const named = (title: string): string | undefined =>
  title === "" ? undefined : title;

/** Listen to requests owned by this shell mount, including late-open cleanup. */
export const listenAgencyRequests = (
  domicile: Pick<Domicile, "windows">,
  onRequest: (request: WindowRequest) => void,
  report: (error: unknown) => void = (error) => console.error("this page cannot hear window requests", error),
): { stop: () => void } => {
  let stopped = false;
  let listening: Listening<WindowRequest> | undefined;
  domicile.windows.requests().then(async (result) => {
    const opened = result.match({ Err: (error) => { report(error); return undefined; }, Ok: (value) => value });
    if (opened === undefined) return;
    if (stopped) { opened.stop(); return; }
    listening = opened;
    for await (const request of opened.items) {
      if (stopped) break;
      onRequest(request);
    }
  }).catch(report);
  return { stop: () => {
    if (!stopped) {
      stopped = true;
      listening?.stop();
      listening = undefined;
    }
  } };
};

/**
 * Agency's bounded clipboard routing. The stock shell builder exposes only
 * direct shell dependencies, so importing the separate address package from
 * config is unavailable. Keep explicit schemes, localhost and domain-shaped
 * copies as URLs; search other text without importing its TLD/tag engine.
 */
export const clipboardDestination = (copied: string): string | undefined => {
  const text = copied.trim();
  if (text === "") return undefined;
  if (/^[a-z][a-z0-9+.-]*:\/\//i.test(text)
    || /^(about|data|domicile|mailto|view-source):/i.test(text)) return text;
  if (!/\s/.test(text)) {
    try {
      const url = new URL(`https://${text}`);
      if (url.hostname === "localhost" || /^[a-z0-9-]+(?:\.[a-z0-9-]+)+$/i.test(url.hostname)) return url.href;
    } catch { /* Ordinary clipboard text is searched below. */ }
  }
  return `https://google.com/search?q=${encodeURIComponent(text)}`;
};
