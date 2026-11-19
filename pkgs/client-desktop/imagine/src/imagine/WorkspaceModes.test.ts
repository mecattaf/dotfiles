import { expect, test } from "bun:test";
import { WindowAction as A, activeIdOf } from "@domicile-desktop/manganese-window-management/window-state";
import type { WindowState } from "@domicile-desktop/manganese-window-management/window-state";
import { agencyReducer as reduce, initialAgencyState } from "./policy";
import { windowsIn } from "./GaplessFrames";
import { EMPTY_WORKSPACE_MODES, decodeWorkspaceModes, reconcileWorkspaceModes, rememberFloatingGeometry,
  setWorkspaceMode, toggleWindowZoom, workspaceModeOf } from "./WorkspaceModes";

type Node = NonNullable<WindowState["workspaces"][number]["tiling"]["root"]>;
const leaf = (id: string): Node => ({kind: 1, id, focusedAt: 1});
const group = (layout: 0|1|2|3, children: readonly Node[]): Node => ({kind: 0, layout, children,
  focused: children.length - 1, fractions: children.map(() => 1 / children.length)});
const area = {x: 0, y: 0, width: 1440, height: 900};
const fresh = () => reduce(initialAgencyState(), A.ScreensDescribed([{name: "upper", box: area}]));
const fixture = () => {
  let state = fresh();
  for (const id of ["one", "two", "three", "dialog"]) state = reduce(state, A.AppAppeared(id, id));
  const root = group(0, [group(3, [leaf("app:one"), leaf("app:two")]), leaf("app:three")]);
  return {...state, workspaces: state.workspaces.map(workspace => workspace.name !== "1" ? workspace : {
    ...workspace, tiling: {root, depth: 64},
    floats: [{root: leaf("app:dialog"), depth: 0, x: 14, y: 27, width: 360, height: 180, bare: true, scratchpad: false}],
  })};
};

test("workspace modes round-trip tab groups and leave actual native windows and other workspaces intact", () => {
  const before = fixture(), original = JSON.stringify(before);
  const floating = setWorkspaceMode(before, EMPTY_WORKSPACE_MODES, "1", "floating", area);
  const workspace = floating.state.workspaces[0]!;
  expect(workspaceModeOf(floating.memory, "1")).toBe("floating");
  expect(workspace.tiling.root).toBeUndefined();
  expect(workspace.floats).toHaveLength(3);
  expect(workspace.floats[0]).toBe(before.workspaces[0]!.floats[0]);
  expect(workspace.floats[1]!.root).toBe((before.workspaces[0]!.tiling.root as Extract<Node,{kind:0}>).children[0]);
  expect(floating.state.windows).toBe(before.windows);
  expect(floating.state.workspaces[1]).toBe(before.workspaces[1]);
  const restored = setWorkspaceMode(floating.state, floating.memory, "1", "scrolling", area);
  expect(restored.state.workspaces[0]!.tiling).toEqual(before.workspaces[0]!.tiling);
  expect(restored.state.workspaces[0]!.floats).toEqual(before.workspaces[0]!.floats);
  expect(JSON.stringify(before)).toBe(original);
});

test("closing or moving a window while floating never brings it back on mode switch", () => {
  const floating = setWorkspaceMode(fixture(), {}, "1", "floating", area);
  let state = reduce(floating.state, A.AppClosed("one"));
  state = reduce(state, A.WindowSelected("app:three"));
  state = reduce(state, A.WindowSentToWorkspace("2"));
  const restored = setWorkspaceMode(state, floating.memory, "1", "scrolling", area);
  const root = restored.state.workspaces[0]!.tiling.root!;
  expect(windowsIn(root)).toEqual(["app:two"]);
  expect(windowsIn(restored.state.workspaces[1]!.tiling.root!)).toContain("app:three");
  expect(restored.state.windows).toBe(state.windows);
});

test("new windows on a floating workspace inherit floating mode and remain recoverable as tiles", () => {
  const floating = setWorkspaceMode(fixture(), {}, "1", "floating", area);
  const appeared = reduce(floating.state, A.AppAppeared("new", "new"));
  const normalized = reconcileWorkspaceModes(appeared, floating.memory, () => area);
  expect(normalized.state.workspaces[0]!.tiling.root).toBeUndefined();
  expect(normalized.state.workspaces[0]!.floats.some(float => windowsIn(float.root).includes("app:new"))).toBe(true);
  const restored = setWorkspaceMode(normalized.state, normalized.memory, "1", "scrolling", area);
  expect(windowsIn(restored.state.workspaces[0]!.tiling.root!)).toContain("app:new");
  expect(restored.state.windows).toBe(appeared.windows);
});

test("floating geometry is restored after scrolling and survives private-memory serialization", () => {
  let floating = setWorkspaceMode(fixture(), {}, "1", "floating", area);
  const state = reduce(floating.state, A.WindowResized("app:three", {x: 180, y: 135, width: 700, height: 500}));
  const memory = rememberFloatingGeometry(state, floating.memory);
  const scrolling = setWorkspaceMode(state, memory, "1", "scrolling", area);
  const decoded = decodeWorkspaceModes(JSON.parse(JSON.stringify(scrolling.memory)));
  floating = setWorkspaceMode(scrolling.state, decoded, "1", "floating", area);
  const found = floating.state.workspaces[0]!.floats.find(float => windowsIn(float.root).includes("app:three"))!;
  expect({x: found.x, y: found.y, width: found.width, height: found.height}).toEqual({x: 180, y: 135, width: 700, height: 500});
});

test("the focused window stays focused when the floating group differs from the old split focus", () => {
  const floating = setWorkspaceMode(fixture(), {}, "1", "floating", area);
  const selected = reduce(floating.state, A.WindowSelected("app:one"));
  const scrolling = setWorkspaceMode(selected, floating.memory, "1", "scrolling", area);
  expect(activeIdOf(scrolling.state)).toBe("app:one");
  expect(scrolling.state.screens).toEqual(selected.screens);
});

test("changing a hidden workspace mode leaves the current workspace and its focus intact", () => {
  const selected = reduce(fixture(), A.WorkspaceSelected("2"));
  const source = reduce(selected, A.AppAppeared("other", "other"));
  const active = activeIdOf(source);
  const changed = setWorkspaceMode(source, {}, "1", "floating", area);
  expect(activeIdOf(changed.state)).toBe(active);
  expect(changed.state.screens).toBe(source.screens);
  expect(changed.state.focused).toBe(source.focused);
});

test("a fullscreen group keeps its topology until fullscreen exits", () => {
  const source = fixture();
  const full = {...source, workspaces: source.workspaces.map(workspace => workspace.name === "1"
    ? {...workspace, fullscreen: {id: "app:one", up: 1, global: false}} : workspace)};
  const changed = setWorkspaceMode(full, {}, "1", "floating", area);
  expect(changed.state).toBe(full);
  const exited = {...changed.state, workspaces: changed.state.workspaces.map(workspace => workspace.name === "1"
    ? {...workspace, fullscreen: undefined} : workspace)};
  const reconciled = reconcileWorkspaceModes(exited, changed.memory, () => area);
  expect(reconciled.state.workspaces[0]!.tiling.root).toBeUndefined();
  expect(reconciled.state.workspaces[0]!.floats.flatMap(float => windowsIn(float.root)).sort()).toEqual(["app:dialog", "app:one", "app:three", "app:two"]);
});

test("manually retiling an automatic float does not duplicate a saved window identity", () => {
  const floating = setWorkspaceMode(fixture(), {}, "1", "floating", area);
  const retiled = reduce(floating.state, A.WindowFloated("app:three"));
  const reconciled = reconcileWorkspaceModes(retiled, floating.memory, () => area);
  const decoded = decodeWorkspaceModes(JSON.parse(JSON.stringify(reconciled.memory)));
  const scrolling = setWorkspaceMode(reconciled.state, decoded, "1", "scrolling", area);
  const ids = windowsIn(scrolling.state.workspaces[0]!.tiling.root!);
  expect(ids.filter(id => id === "app:three")).toHaveLength(1);
});

test("geometric zoom restores its old rectangle without entering native fullscreen", () => {
  const floating = setWorkspaceMode(fixture(), {}, "1", "floating", area);
  const before = floating.state.workspaces[0]!.floats.find(float => windowsIn(float.root).includes("app:three"))!;
  const zoomed = toggleWindowZoom(floating.state, floating.memory, "app:three", area);
  expect(zoomed.state.workspaces[0]!.fullscreen).toBeUndefined();
  expect(zoomed.state.workspaces[0]!.floats.find(float => windowsIn(float.root).includes("app:three"))!.width).toBe(1440);
  const restored = toggleWindowZoom(zoomed.state, zoomed.memory, "app:three", area);
  expect(restored.state.workspaces[0]!.floats.find(float => windowsIn(float.root).includes("app:three"))).toEqual(before);
  expect(restored.state.windows).toBe(floating.state.windows);
});

test("minimizing with public actions hides a live client without closing it", () => {
  const floating = setWorkspaceMode(fixture(), {}, "1", "floating", area);
  const selected = reduce(floating.state, A.WindowSelected("app:three"));
  const hidden = reduce(selected, A.WindowSentToScratchpad());
  expect(hidden.scratchpad).toContain("app:three");
  expect(hidden.windows).toBe(floating.state.windows);
  expect(activeIdOf(hidden)).not.toBe("app:three");
});

test("invalid private mode payloads and impossible geometry are rejected or left alone", () => {
  expect(() => decodeWorkspaceModes({1: {mode: "floating", automatic: ["not-a-window"], floating: [], zoom: {}}})).toThrow();
  expect(() => decodeWorkspaceModes({11: {mode: "scrolling", automatic: [], floating: [], zoom: {}}})).toThrow();
  expect(() => decodeWorkspaceModes({1: {mode: "floating", automatic: [], floating: [], zoom: {},
    tiled: {depth: 0, root: {kind: 0, layout: 3, focused: 0, children: [leaf("app:one")], fractions: [2]}}}})).toThrow();
  const before = fixture();
  expect(setWorkspaceMode(before, {}, "1", "floating", {...area, width: 0}).state).toBe(before);
});
