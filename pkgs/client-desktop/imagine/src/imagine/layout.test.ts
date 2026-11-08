import { describe, expect, test } from "bun:test";
import type { Geometry } from "@domicile-desktop/manganese-window-management/placement";
import { stageScreensOf } from "@domicile-desktop/manganese-window-management/screens/stage-screens";
import type { WindowState } from "@domicile-desktop/manganese-window-management/window-state";
import { agencyPlacement, agencyScreens } from "./layout";
import { initialAgencyState } from "./policy";

type Workspace = WindowState["workspaces"][number];
type Node = NonNullable<Workspace["tiling"]["root"]>;
const leaf = (id: string): Node => ({ kind: 1, id, focusedAt: 0 });
const group = (layout: 0 | 1 | 2 | 3, children: readonly Node[], focused = 0,
  fractions = children.map(() => 1 / children.length)): Node =>
  ({ kind: 0, layout, children, focused, fractions });
const workspace = (root: Node, name = "1"): Workspace => ({
  name, floats: [], floatFocus: undefined, fullscreen: undefined,
  tiling: { root, depth: 10 },
});
const geometry: Geometry = {
  name: "upper", screen: { x: 0, y: 0, width: 1440, height: 900 },
  workspace: { x: 0, y: 0, width: 1440, height: 900 },
  desktop: { x: 0, y: 0, width: 1440, height: 1800 },
};

describe("Agency zero-gap public Stage placement", () => {
  test("one window touches every output edge and keeps stock title/surface tuck", () => {
    const placed = agencyPlacement(workspace(leaf("a")), geometry).placements[0]!;
    expect(placed.frame).toEqual(geometry.screen);
    expect(placed.bar).toEqual({ x: 0, y: 0, width: 1440, height: 30 });
    expect(placed.surface).toEqual({ x: 0, y: 29, width: 1440, height: 871 });
    expect(placed.bare).toBe(false);
  });
  test("nested horizontal/vertical splits meet with no margins or gaps", () => {
    const root = group(0, [leaf("a"), group(1, [leaf("b"), leaf("c")])], 1, [1 / 3, 2 / 3]);
    const result = agencyPlacement(workspace(root), geometry);
    const a = result.placements.find(({ id }) => id === "a")!.frame;
    const b = result.placements.find(({ id }) => id === "b")!.frame;
    const c = result.placements.find(({ id }) => id === "c")!.frame;
    expect(a).toEqual({ x: 0, y: 0, width: 480, height: 900 });
    expect(b).toEqual({ x: 480, y: 0, width: 960, height: 450 });
    expect(c).toEqual({ x: 480, y: 450, width: 960, height: 450 });
    expect(a.x + a.width).toBe(b.x);
    expect(b.y + b.height).toBe(c.y);
  });
  test("nested tab groups retain tabs and remove the group well's margin", () => {
    const root = group(3, [leaf("a"), group(0, [leaf("b"), leaf("c")])], 1);
    const result = agencyPlacement(workspace(root), geometry);
    const b = result.placements.find(({ id }) => id === "b")!;
    const c = result.placements.find(({ id }) => id === "c")!;
    expect(result.tabs).toHaveLength(1);
    expect(result.tabs[0]!.well).toEqual({ x: 0, y: 30, width: 1440, height: 870 });
    expect(b.frame).toEqual({ x: 0, y: 30, width: 720, height: 870 });
    expect(c.frame).toEqual({ x: 720, y: 30, width: 720, height: 870 });
    expect(result.placements.find(({ id }) => id === "a")!.surface).toBeUndefined();
  });
  test("group fullscreen keeps zero gaps and one copy of each window", () => {
    const normal = workspace(group(0, [leaf("a"), leaf("b")]));
    const result = agencyPlacement({ ...normal, fullscreen: { id: "a", up: 1, global: false } }, geometry);
    expect(result.placements).toHaveLength(2);
    expect(result.placements.map(({ depth }) => depth)).toEqual([2000, 2000]);
    expect(result.placements.map(({ frame }) => frame)).toEqual([
      { x: 0, y: 0, width: 720, height: 900 }, { x: 720, y: 0, width: 720, height: 900 },
    ]);
  });
  test("client fullscreen still fills the complete screen without title chrome", () => {
    const normal = workspace(leaf("a"));
    const result = agencyPlacement({ ...normal, fullscreen: { id: "a", up: 0, global: false, bare: true } }, geometry);
    expect(result.placements[0]!.bare).toBe(true);
    expect(result.placements[0]!.surface).toEqual(geometry.screen);
  });
  test("scale-2 logical outputs reserve only the focused rail and no bar strip", () => {
    const upper = workspace(leaf("a"));
    const lower = workspace(leaf("b"), "10");
    const state = { ...initialAgencyState(), focused: "upper", workspaces: [upper, lower], screens: [
      { name: "upper", current: "1", box: geometry.screen },
      { name: "lower", current: "10", box: { ...geometry.screen, y: 900 } },
    ] };
    const displays = [
      { name: "upper", position: [0, 0] as const, size: [1440, 900] as const, scale: 2 },
      { name: "lower", position: [0, 900] as const, size: [1440, 900] as const, scale: 2 },
    ];
    const base = stageScreensOf(state, displays, { byDesk: new WeakMap(), last: new Map() });
    const open = agencyScreens(base, state, "upper", 256);
    expect(open[0]!.screenful.placements[0]!.frame).toEqual({ x: 256, y: 0, width: 1184, height: 900 });
    expect(open[1]!.screenful.placements[0]!.frame).toEqual({ x: 0, y: 900, width: 1440, height: 900 });
    const closed = agencyScreens(base, state, undefined, 256);
    expect(closed[0]!.screenful.placements[0]!.frame).toEqual(geometry.screen);
  });
});
