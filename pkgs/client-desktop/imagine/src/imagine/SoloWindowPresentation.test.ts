import { expect, test } from "bun:test";
import type { Geometry } from "@domicile-desktop/manganese-window-management/placement";
import type { StageScreen } from "@domicile-desktop/manganese-window-management/screens/stage-screens";
import type { WindowState } from "@domicile-desktop/manganese-window-management/window-state";
import { WindowAction as A } from "@domicile-desktop/manganese-window-management/window-state";
import { agencyReducer as reduce, initialAgencyState } from "./policy";
import { agencyPlacement } from "./layout";
import { presentSoloWindows, soloWindowCss, soloWindowGroups } from "./SoloWindowPresentation";

const displays = [
  { name: "upper", box: { x: 0, y: 0, width: 1440, height: 900 } },
  { name: "lower", box: { x: 0, y: 900, width: 1440, height: 900 } },
];
const fresh = () => reduce(initialAgencyState(), A.ScreensDescribed(displays));
const appear = (state: WindowState, id: string) => reduce(state, A.AppAppeared(id, id));
const screen = (state: WindowState, name: string): StageScreen => {
  const display = state.screens.find(item => item.name === name)!;
  const workspace = state.workspaces.find(item => item.name === display.current)!;
  const geometry: Geometry = { name, screen: display.box, workspace: display.box,
    desktop: { x: 0, y: 0, width: 1440, height: 1800 } };
  return { current: workspace.name, floats: workspace.floats, fullscreen: undefined,
    geometry, screenful: agencyPlacement(workspace, geometry) };
};

test("one managed window loses its focus marker without changing any placement or state", () => {
  const state = appear(fresh(), "solo");
  const before = screen(state, "upper");
  const saved = JSON.stringify(state);
  const result = presentSoloWindows([before], state);
  expect(result.borderlessWindows).toEqual(new Set(["app:solo"]));
  expect(result.screens[0]!.screenful.focusBox).toBeUndefined();
  expect(result.screens[0]!.screenful.placements).toBe(before.screenful.placements);
  expect(result.screens[0]!.screenful.tabs).toBe(before.screenful.tabs);
  expect(result.screens[0]!.geometry).toBe(before.geometry);
  expect(JSON.stringify(state)).toBe(saved);
});

test("single-window and multi-window workspaces are independent on stacked displays", () => {
  let state = appear(appear(fresh(), "one"), "two");
  state = appear(reduce(state, A.WorkspaceSelected("10")), "lower");
  const upper = screen(state, "upper"), lower = screen(state, "lower");
  const result = presentSoloWindows([upper, lower], state);
  expect(result.screens[0]).toBe(upper);
  expect(result.screens[1]!.screenful.focusBox).toBeUndefined();
  expect(result.borderlessWindows).toEqual(new Set(["app:lower"]));
});

test("offscreen columns and hidden tab siblings still count as workspace tasks", () => {
  let state = appear(appear(fresh(), "one"), "two");
  expect(soloWindowGroups(state).has("1")).toBe(false);
  state = reduce(state, A.LayoutSet(3));
  expect(soloWindowGroups(state).has("1")).toBe(false);
});

test("shown floats count but hidden scratchpad windows do not", () => {
  let state = appear(appear(fresh(), "tile"), "float");
  state = reduce(state, A.WindowFloated("app:float"));
  expect(soloWindowGroups(state).has("1")).toBe(false);
  state = reduce(state, A.WindowSentToScratchpad());
  expect(soloWindowGroups(state).get("1")).toEqual(["app:tile"]);
});

test("a retained browser guest can be the solo task and an empty workspace has none", () => {
  const browser = { id: "guest", appId: "viewer", url: "https://example.test/", title: "private title",
    width: 0, height: 0, isApp: true, isPrivate: false, isCaptured: false, partition: "", popupWindow: undefined };
  const state = reduce(fresh(), A.BrowserWindowsListed([browser], []));
  expect(soloWindowGroups(state).get("1")).toEqual(["browser:guest"]);
  expect(soloWindowGroups(state).has("10")).toBe(false);
});

test("a lone floating tab group is borderless across tab switches", () => {
  const initial = appear(appear(fresh(), "one"), "two");
  const current = initial.workspaces.find(workspace => workspace.name === "1")!;
  const ids = ["app:one", "app:two"];
  const group = { kind: 0 as const, layout: 3 as const, focused: 0,
    fractions: [.5, .5], children: ids.map(id => ({ kind: 1 as const, id, focusedAt: 0 })) };
  const floating = { root: group, depth: 1, x: 40, y: 35, width: 800, height: 600,
    bare: false, scratchpad: false };
  const state = { ...initial, workspaces: initial.workspaces.map(workspace => workspace.name === "1"
    ? { ...current, tiling: { root: undefined, depth: 0 }, floats: [floating], floatFocus: ids[0] } : workspace) };
  const result = presentSoloWindows([screen(state, "upper")], state, () => true);
  expect(result.borderlessWindows).toEqual(new Set(ids));
  expect(result.screens[0]!.screenful.focusBox).toBeUndefined();
  const switched = reduce(state, A.WindowSelected(ids[1]!));
  expect(presentSoloWindows([screen(switched, "upper")], switched, () => true).borderlessWindows).toEqual(new Set(ids));
  expect(soloWindowGroups(state).has("1")).toBe(false);
});

test("a tile beside a floating group is not solo in either mode", () => {
  let state = appear(appear(fresh(), "tile"), "float");
  state = reduce(state, A.WindowFloated("app:float"));
  expect(soloWindowGroups(state, () => true).has("1")).toBe(false);
  expect(soloWindowGroups(state).has("1")).toBe(false);
});

test("border suppression is scoped to native/browser surfaces and cannot change geometry", () => {
  const css = soloWindowCss(new Set(["app:solo", "browser:guest", 'app:bad\"]{}<']));
  expect(css).toContain('app[app-id="solo"]');
  expect(css).toContain('webview[window="guest"]');
  expect(css).toContain("border-color:transparent!important");
  expect(css).not.toContain("border-width");
  expect(css).not.toContain("display:none");
  expect(css).not.toContain('app-id="bad"]{}<');
  expect(soloWindowCss(new Set(["untyped"]))).toBe("");
});
