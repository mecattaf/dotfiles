// Pure policy and request-lifecycle checks. Run on compute through runtime-test.
import { describe, expect, test } from "bun:test";
import { Ok } from "@cprussin/option-result";
import { Axis, Direction } from "@domicile-desktop/manganese-window-management/direction";
import {
  activeIdOf, NO_WINDOWS, reduceWindows, WindowAction as A,
  workspaceNamed, workspaceHere,
} from "@domicile-desktop/manganese-window-management/window-state";
import type { WindowState } from "@domicile-desktop/manganese-window-management/window-state";
import type { ClientWindow } from "@domicile-desktop/sdk/desktop/windows";
import type { BrowserWindow } from "@domicile-desktop/sdk/desktop/browser";
import { WindowRequest } from "@domicile-desktop/sdk/window-state";
import {
  agencyReducer, createAgencyReducer, initialAgencyState,
} from "./policy";
import { clipboardDestination, listenAgencyRequests, nativeWindowActions } from "./useAgencyWindows";
import { outputToward } from "./AgencyKeys";

const screens = [
  { name: "upper", box: { x: 0, y: 0, width: 1440, height: 900 } },
  { name: "lower", box: { x: 0, y: 900, width: 1440, height: 900 } },
];
const reduce = (state: WindowState, ...actions: A[]) => actions.reduce(agencyReducer, state);
const fresh = () => reduce(initialAgencyState(), A.ScreensDescribed(screens));
const opened = (id: string) => A.AppAppeared(id, id);
type Node = NonNullable<WindowState["workspaces"][number]["tiling"]["root"]>;
const groups = (node: Node | undefined): string[][] => node === undefined ? []
  : "id" in node ? [[node.id]]
  : node.children.every((child) => "id" in child)
    ? [node.children.flatMap((child) => "id" in child ? [child.id] : [])]
    : node.children.flatMap(groups);
const tiled = (state: WindowState, name = "1") => groups(workspaceNamed(state, name).tiling.root);
const shown = (state: WindowState) => state.screens.map(({ name, current }) => [name, current]);
const browser = (id: string, extra: Partial<BrowserWindow> = {}): BrowserWindow => ({
  id, appId: "", url: "about:blank", title: id, width: 0, height: 0,
  isApp: false, isCaptured: false, isPrivate: false, partition: "", popupWindow: undefined,
  ...extra,
});
const client = (appId: string, extra: Partial<ClientWindow> = {}): ClientWindow => ({
  appId, title: appId, desktopId: "fixture", cursor: "default", frame: 0,
  minWidth: undefined, minHeight: undefined, maxWidth: undefined, maxHeight: undefined,
  parent: undefined, dialog: false, clientFrame: false, width: 800, height: 600, x: 0, y: 0,
  ...extra,
} as ClientWindow);

const settle = async () => { for (let n = 0; n < 12; n++) await Promise.resolve(); };

describe("fixed workspace homes", () => {
  test("starts on upper1/lower10 and reserves every empty slot", () => {
    const state = fresh();
    expect(shown(state)).toEqual([["upper", "1"], ["lower", "10"]]);
    for (let n = 1; n <= 9; n++) expect(state.homes[String(n)]).toBe("upper");
    expect(state.homes["10"]).toBe("lower");
  });
  test("selecting empty1..9 from downstairs always goes upstairs", () => {
    for (let n = 1; n <= 9; n++) {
      const state = reduce(fresh(), A.WorkspaceSelected("10"), A.WorkspaceSelected(String(n)));
      expect(state.focused).toBe("upper");
      expect(workspaceHere(state).name).toBe(String(n));
      expect(shown(state)[1]).toEqual(["lower", "10"]);
    }
  });
  test("keyboard focus survives native focus/list feedback, while actual output hover still follows the pointer", () => {
    const listed = [client("a"), client("b")];
    const ready = reduce(fresh(), ...nativeWindowActions([], [], listed), A.FocusChanged("b"));
    const selected = reduce(ready, A.WorkspaceSelected("10"), A.KeyPressed(),
      A.FocusChanged(undefined), A.ScreensDescribed(screens));
    expect(selected.focused).toBe("lower");
    expect(selected.pressed).toBe(1);
    expect(workspaceHere(selected).name).toBe("10");
    expect(shown(selected)).toEqual([["upper", "1"], ["lower", "10"]]);
    expect(tiled(selected, "1")).toEqual([["app:a"], ["app:b"]]);
    // Selecting a slot must not pin focus against a later pointer crossing.
    const crossed = reduce(selected, A.ScreenHovered("upper"));
    expect(crossed.focused).toBe("upper");
    expect(crossed.homes["10"]).toBe("lower");
    expect(shown(crossed)).toEqual([["upper", "1"], ["lower", "10"]]);
  });
  test("repeating the slot chord does not invoke stock back-and-forth", () => {
    const state = reduce(fresh(), A.WorkspaceSelected("10"), A.WorkspaceSelected("1"), A.WorkspaceSelected("1"));
    expect(state.focused).toBe("upper");
    expect(workspaceHere(state).name).toBe("1");
  });
  test("sending a window downstairs does not move the upper workspace", () => {
    const state = reduce(fresh(), opened("a"), A.WindowSentToWorkspace("10"));
    expect(state.focused).toBe("upper");
    expect(tiled(state, "10")).toEqual([["app:a"]]);
    expect(state.homes["1"]).toBe("upper");
  });
  test("empty homes survive close, hide and metadata transitions", () => {
    const state = reduce(fresh(), A.WorkspaceSelected("7"), opened("a"), A.AppClosed("a"), A.WorkspaceSelected("10"));
    expect(state.homes["7"]).toBe("upper");
    expect(reduce(state, A.WorkspaceSelected("7")).focused).toBe("upper");
  });
  test("one-screen fallback keeps10 usable and restores lower on reconnect", () => {
    const single = reduce(fresh(), A.ScreensDescribed([screens[0]!]), A.WorkspaceSelected("10"), opened("a"));
    expect(single.homes["10"]).toBe("upper");
    const both = reduce(single, A.ScreensDescribed(screens));
    expect(both.homes["10"]).toBe("lower");
    expect(shown(both)).toEqual([["upper", "1"], ["lower", "10"]]);
    expect(both.focused).toBe("lower");
    expect(tiled(both, "10")).toEqual([["app:a"]]);
  });
  test("explicit identities outrank enumeration/geometry order", () => {
    const reducer = createAgencyReducer({ upperDisplay: "lower", lowerDisplay: "upper" });
    const state = reducer(initialAgencyState(), A.ScreensDescribed(screens.toReversed()));
    expect(state.homes["1"]).toBe("lower");
    expect(state.homes["10"]).toBe("upper");
  });
});

describe("split insertion", () => {
  test("each normal native window splits, including initial lists", () => {
    const actions = nativeWindowActions([], [], [client("a"), client("b"), client("c")]);
    const state = reduce(fresh(), ...actions);
    expect(tiled(state)).toEqual([["app:a"], ["app:b"], ["app:c"]]);
    expect(activeIdOf(state)).toBe("app:c");
  });
  test("new workspaces and downstairs get the same insertion policy", () => {
    const state = reduce(fresh(), A.WorkspaceSelected("4"), opened("a"), opened("b"), A.WorkspaceSelected("10"), opened("c"), opened("d"));
    expect(tiled(state, "4")).toEqual([["app:a"], ["app:b"]]);
    expect(tiled(state, "10")).toEqual([["app:c"], ["app:d"]]);
  });
  test("one browser batch splits every normal window in opening order", () => {
    const state = reduce(fresh(), A.BrowserWindowsListed([browser("a"), browser("b"), browser("c")]));
    expect(tiled(state)).toEqual([["browser:a"], ["browser:b"], ["browser:c"]]);
    expect(activeIdOf(state)).toBe("browser:c");
  });
  test("browser popup/background entries retain stock floating/hidden behavior", () => {
    const state = reduce(fresh(), A.BrowserWindowsListed([
      browser("a"), browser("dialog", { width: 400, height: 250, popupWindow: 1 }),
      browser("hidden", { isApp: true, appId: "inbox" }),
    ], ["inbox"]));
    expect(tiled(state)).toEqual([["browser:a"]]);
    expect(workspaceNamed(state, "1").floats).toHaveLength(1);
    expect(state.background).toContain("browser:hidden");
    expect(activeIdOf(state)).toBe("browser:dialog");
  });
  test("native dialogs and popups do not become tiled windows", () => {
    const state = reduce(fresh(), ...nativeWindowActions([], [], [
      client("a"), client("dialog", { dialog: true }),
      client("menu", { parent: "a", width: 100, height: 80 }),
    ]));
    expect(tiled(state)).toEqual([["app:a"]]);
    expect(workspaceNamed(state, "1").floats).toHaveLength(1);
    expect(state.popups.map(({ appId }) => appId)).toEqual(["menu"]);
  });
  test("normal windows joining an explicitly floating group stay floating", () => {
    const state = reduce(fresh(), opened("a"), A.FloatToggled(), opened("b"));
    expect(workspaceNamed(state, "1").floats).toHaveLength(1);
    expect(tiled(state)).toEqual([]);
    expect(activeIdOf(state)).toBe("app:b");
  });
  test("an explicit tab group remains available, while the next window splits", () => {
    const stockTabs = reduceWindows(reduceWindows(NO_WINDOWS, opened("a")), opened("b"));
    const tabbed = workspaceNamed(stockTabs, "1").tiling.root!;
    if ("id" in tabbed) throw Error("stock fixture should be grouped");
    const tabs = reduce(fresh(), opened("a"), opened("b"), A.ParentFocused(), A.ParentFocused(), A.LayoutSet(tabbed.layout));
    expect(tiled(tabs)).toEqual([["app:a", "app:b"]]);
    const next = reduce(tabs, opened("c"));
    expect(tiled(next)).toEqual([["app:a", "app:b"], ["app:c"]]);
  });
  test("replayed lists and metadata do not resplit intentional groups", () => {
    const before = reduce(fresh(), A.BrowserWindowsListed([browser("a"), browser("b")]));
    const after = reduce(before, A.BrowserWindowsListed([browser("a", { title: "renamed" }), browser("b")]));
    expect(workspaceNamed(after, "1").tiling).toBe(workspaceNamed(before, "1").tiling);
    expect(after.windows.find(({ id }) => id === "browser:a")?.title).toBe("renamed");
  });
  test("the chosen axis applies to each new split", () => {
    const reducer = createAgencyReducer({ defaultSplitAxis: Axis.Vertical });
    const state = [A.ScreensDescribed(screens), opened("a"), opened("b")].reduce(reducer, initialAgencyState());
    const reference = reduceWindows(reduceWindows(NO_WINDOWS, opened("a")), opened("b"));
    const vertical = reduceWindows(reference, A.ContainerSplit(Axis.Vertical));
    expect(workspaceNamed(state, "1").tiling.root?.layout).toBe(workspaceNamed(vertical, "1").tiling.root?.layout);
  });
});

describe("owned request lifecycle", () => {
  test("late-open request listeners are stopped once without dispatch", async () => {
    let resolve!: (value: any) => void;
    let stops = 0;
    const received: unknown[] = [];
    const pending = new Promise<any>((done) => { resolve = done; });
    const host = { windows: { requests: () => pending } } as any;
    const listener = listenAgencyRequests(host, (request) => received.push(request));
    listener.stop(); listener.stop();
    resolve(Ok({ items: new ReadableStream(), stop: () => { stops++; } }));
    await settle();
    expect(stops).toBe(1);
    expect(received).toEqual([]);
  });
  test("owned streams stop dispatching after unmount and surface failures", async () => {
    let controller!: ReadableStreamDefaultController<any>;
    let stops = 0;
    const received: unknown[] = [];
    const errors: unknown[] = [];
    const stream = new ReadableStream({ start(c) { controller = c; } });
    const host = { windows: { requests: async () => Ok({ items: stream, stop: () => { stops++; controller.close(); } }) } } as any;
    const listener = listenAgencyRequests(host, (request) => received.push(request), (error) => errors.push(error));
    await settle();
    const first = WindowRequest.Fullscreen("a", undefined);
    controller.enqueue(first);
    await settle();
    listener.stop(); listener.stop();
    await settle();
    expect(received).toEqual([first]);
    expect(stops).toBe(1);
    expect(errors).toEqual([]);
    const failed = { windows: { requests: async () => { throw Error("fixture failure"); } } } as any;
    listenAgencyRequests(failed, () => {}, (error) => errors.push(error));
    await settle();
    expect(errors).toHaveLength(1);
  });
});

describe("bounded clipboard routing", () => {
  test("keeps explicit URLs and recognizes local/domain copies", () => {
    expect(clipboardDestination(" https://example.com/a?q=1 ")).toBe("https://example.com/a?q=1");
    expect(clipboardDestination("localhost:5173")).toBe("https://localhost:5173/");
    expect(clipboardDestination("example.com/path")).toBe("https://example.com/path");
    expect(clipboardDestination("mailto:tom@example.com")).toBe("mailto:tom@example.com");
  });
  test("searches ordinary text and ignores an empty copy", () => {
    expect(clipboardDestination("ratio 16:9")).toBe("https://google.com/search?q=ratio%2016%3A9");
    expect(clipboardDestination("  ")).toBeUndefined();
  });
});

describe("direct vertical output focus", () => {
  test("jumps past local vertical neighbors and restores the other output's selection", () => {
    const reducer = createAgencyReducer({ defaultSplitAxis: Axis.Vertical });
    const ready = [A.ScreensDescribed(screens), opened("a"), opened("b"), A.WindowSelected("app:a")]
      .reduce(reducer, initialAgencyState());
    const windowStep = reducer(ready, A.FocusStepped(Direction.Down));
    expect(windowStep.focused).toBe("upper");
    expect(activeIdOf(windowStep)).toBe("app:b");
    const target = outputToward(ready.screens, ready.focused, "down");
    expect(target).toBe("lower");
    const lower = reduce(ready, A.ScreenHovered(target!), A.KeyPressed());
    expect(lower.focused).toBe("lower");
    expect(activeIdOf(lower)).toBeUndefined();
    expect(lower.pressed).toBe(1);
    expect(shown(lower)).toEqual([["upper", "1"], ["lower", "10"]]);
    const upper = reduce(lower, A.ScreenHovered(outputToward(lower.screens, lower.focused, "up")!), A.KeyPressed());
    expect(upper.focused).toBe("upper");
    expect(activeIdOf(upper)).toBe("app:a");
    expect(upper.pressed).toBe(2);
  });
  test("dock mode and horizontal neighbors do not invent a vertical target", () => {
    const single = reduce(fresh(), A.ScreensDescribed([screens[0]!]));
    expect(outputToward(single.screens, "upper", "down")).toBeUndefined();
    expect(outputToward(single.screens, "upper", "up")).toBeUndefined();
    const horizontal = [...single.screens, { name: "right", current: "10",
      box: { x: 1440, y: 0, width: 1440, height: 900 } }];
    expect(outputToward(horizontal, "upper", "down")).toBeUndefined();
  });
  test("uses logical geometry and chooses the nearest screen beyond the edge", () => {
    const placed = [
      { name: "upper", current: "1", box: { x: -100, y: -900, width: 1440, height: 900 } },
      { name: "lower", current: "10", box: { x: -100, y: 0, width: 1440, height: 900 } },
      { name: "far", current: "2", box: { x: 2000, y: 0, width: 1440, height: 900 } },
      { name: "overlap", current: "3", box: { x: -100, y: -450, width: 1440, height: 900 } },
    ];
    expect(outputToward(placed, "upper", "down")).toBe("lower");
    expect(outputToward(placed, "lower", "up")).toBe("upper");
  });
  test("a disconnected or not-yet-described output is a no-op", () => {
    expect(outputToward([], "missing", "down")).toBeUndefined();
    expect(outputToward(fresh().screens, "missing", "up")).toBeUndefined();
  });
});
