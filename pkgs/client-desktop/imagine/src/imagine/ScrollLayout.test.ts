import { describe, expect, test } from "bun:test";
import { Axis } from "@domicile-desktop/manganese-window-management/direction";
import { stageScreensOf } from "@domicile-desktop/manganese-window-management/screens/stage-screens";
import { WindowAction as A } from "@domicile-desktop/manganese-window-management/window-state";
import type { WindowState } from "@domicile-desktop/manganese-window-management/window-state";
import { windowsIn } from "./GaplessFrames";
import { agencyScreens } from "./layout";
import { agencyReducer as reduce, initialAgencyState } from "./policy";
import {
  cycleScrollSize, decodeScrollPreferences, emptyScrollPreferences, encodeScrollPreferences,
  panScroll, pruneScrollPreferences, scrollingScreens, setScrollSize,
} from "./ScrollLayout";

type Node = NonNullable<WindowState["workspaces"][number]["tiling"]["root"]>;
const leaf = (id: string): Node => ({ kind: 1, id: "app:" + id, focusedAt: 1 });
const group = (layout: 0 | 1 | 2 | 3, children: readonly Node[], focused = 0): Node =>
  ({ kind: 0, layout, children, focused, fractions: children.map(() => 1 / children.length) });
const display = { name: "upper", position: [0, 0] as const, size: [1440, 900] as const, scale: 2 };
const lower = { name: "lower", position: [0, 900] as const, size: [1440, 900] as const, scale: 2 };
function stateOf(root: Node, second?: Node): WindowState {
  let state = reduce(initialAgencyState(), A.ScreensDescribed([
    { name: "upper", box: { x: 0, y: 0, width: 1440, height: 900 } },
    ...(second === undefined ? [] : [{ name: "lower", box: { x: 0, y: 900, width: 1440, height: 900 } }]),
  ]));
  for (const id of [...windowsIn(root), ...(second === undefined ? [] : windowsIn(second))]) state = reduce(state, A.AppAppeared(id.slice(4), id));
  return { ...state, focused: "upper", workspaces: state.workspaces.map(workspace => workspace.name === "1"
    ? { ...workspace, tiling: { root, depth: 100 } } : workspace.name === "10" && second !== undefined
      ? { ...workspace, tiling: { root: second, depth: 100 } } : { ...workspace, tiling: { root: undefined, depth: 0 } }),
    screens: state.screens.map(screen => ({ ...screen, current: screen.name === "lower" ? "10" : "1" })) };
}
const baseOf = (state: WindowState, rail = false) => agencyScreens(stageScreensOf(state, state.screens.length === 1 ? [display] : [display, lower],
  { byDesk: new WeakMap(), last: new Map() }), state, rail ? "upper" : undefined, 256);
const frame = (result: ReturnType<typeof scrollingScreens>, id: string) =>
  result.screens.flatMap(screen => screen.screenful.placements).find(placement => placement.id === "app:" + id)!.frame;

describe("scrolling presentation without replacing windows", () => {
  test("previous tabs become separate full-width columns and all tiled chrome disappears", () => {
    const state = stateOf(group(3, [leaf("one"), leaf("two")], 1));
    const original = JSON.stringify(state);
    const base = baseOf(state);
    const result = scrollingScreens(base, state, emptyScrollPreferences());
    expect(frame(result, "one")).toEqual({ x: -1440, y: 0, width: 1440, height: 900 });
    expect(frame(result, "two")).toEqual({ x: 0, y: 0, width: 1440, height: 900 });
    expect(result.screens[0]!.screenful.tabs).toHaveLength(0);
    for (const placement of result.screens[0]!.screenful.placements) {
      expect(placement.bare).toBeTrue(); expect(placement.strip).toBeUndefined();
      expect(placement.bar.height).toBe(0); expect(placement.surface).toEqual(placement.frame);
    }
    expect(JSON.stringify(state)).toBe(original);
    expect(result.screens[0]!.geometry).toBe(base[0]!.geometry);
  });

  test("width and height cycle through all four fractions, including true full size", () => {
    const state = stateOf(group(0, [leaf("one"), leaf("two")], 0));
    let preferences = emptyScrollPreferences();
    for (const fraction of [1 / 3, 1 / 2, 2 / 3, 1, 1 / 3]) {
      preferences = cycleScrollSize(preferences, state, "app:one", Axis.Horizontal);
      const result = scrollingScreens(baseOf(state), state, preferences);
      expect(frame(result, "one").width).toBeCloseTo(1440 * fraction);
      expect(frame(result, "two").x).toBeCloseTo(frame(result, "one").x + frame(result, "one").width);
      expect(state.workspaces[0]!.fullscreen).toBeUndefined();
    }
    preferences = cycleScrollSize(preferences, state, "app:one", Axis.Horizontal, true);
    expect(frame(scrollingScreens(baseOf(state), state, preferences), "one").width).toBe(1440);
    preferences = cycleScrollSize(preferences, state, "app:one", Axis.Vertical);
    expect(frame(scrollingScreens(baseOf(state), state, preferences), "one").height).toBe(300);
  });

  test("stacked windows scroll vertically while their shared column changes width together", () => {
    const state = stateOf(group(0, [leaf("left"), group(2, [leaf("top"), leaf("bottom")], 1)], 1));
    let preferences = cycleScrollSize(emptyScrollPreferences(), state, "app:bottom", Axis.Horizontal, true);
    preferences = cycleScrollSize(preferences, state, "app:bottom", Axis.Vertical);
    const result = scrollingScreens(baseOf(state), state, preferences);
    expect(frame(result, "top").width).toBeCloseTo(960);
    expect(frame(result, "bottom").width).toBeCloseTo(960);
    expect(frame(result, "bottom").height).toBe(300);
    expect(frame(result, "top").y + frame(result, "top").height).toBe(frame(result, "bottom").y);
    expect(frame(result, "bottom").y).toBe(600);
  });

  test("focus follows an offscreen column and manual pans remain until focus changes", () => {
    const state = stateOf(group(0, [leaf("one"), leaf("two"), leaf("three")], 2));
    const shown = scrollingScreens(baseOf(state), state, emptyScrollPreferences());
    expect(shown.preferences.horizontal["1"]).toBe(2880);
    const panned = panScroll(shown.preferences, state, "1", Axis.Horizontal, -500);
    const manual = scrollingScreens(baseOf(state), state, panned);
    expect(manual.preferences.horizontal["1"]).toBe(2380);
    expect(frame(manual, "three").x).toBe(500);
    const focused = reduce(state, A.WindowSelected("app:one"));
    const followed = scrollingScreens(baseOf(focused), focused, manual.preferences);
    expect(frame(followed, "one").x).toBe(0);
  });

  test("a rail and a second scaled output use their own logical viewport", () => {
    const state = stateOf(group(3, [leaf("one"), leaf("two")], 1), group(0, [leaf("lower-one"), leaf("lower-two")], 1));
    const bases = baseOf(state, true);
    const result = scrollingScreens(bases, state, emptyScrollPreferences());
    expect(frame(result, "two")).toEqual({ x: 256, y: 0, width: 1184, height: 900 });
    expect(frame(result, "lower-two")).toEqual({ x: 0, y: 900, width: 1440, height: 900 });
    expect(result.screens.map(screen => screen.geometry.screen)).toEqual(bases.map(screen => screen.geometry.screen));
  });

  test("floating mode, dialogs and explicit fullscreen keep their original placements", () => {
    const state = stateOf(group(3, [leaf("one"), leaf("two")], 1));
    const bases = baseOf(state);
    expect(scrollingScreens(bases, state, emptyScrollPreferences(), () => false).screens[0]).toBe(bases[0]);
    const floated = reduce(state, A.WindowFloated("app:two"));
    const floats = baseOf(floated);
    const result = scrollingScreens(floats, floated, emptyScrollPreferences());
    expect(result.screens[0]!.screenful.placements.find(placement => placement.id === "app:two"))
      .toBe(floats[0]!.screenful.placements.find(placement => placement.id === "app:two"));
    const fullscreen = reduce(state, A.WindowFullscreened("app:two"));
    const fullBases = baseOf(fullscreen);
    expect(scrollingScreens(fullBases, fullscreen, emptyScrollPreferences()).screens[0]).toBe(fullBases[0]);
  });

  test("nested horizontal groups inside vertical columns have no tabbed overlaps", () => {
    const state = stateOf(group(1, [group(3, [leaf("a"), leaf("b")]), group(3, [leaf("c"), leaf("d")])], 1));
    const result = scrollingScreens(baseOf(state), state, emptyScrollPreferences());
    const placements = result.screens[0]!.screenful.placements;
    expect(placements).toHaveLength(4);
    for (let a = 0; a < placements.length; a++) for (let b = a + 1; b < placements.length; b++) {
      const first = placements[a]!.frame, second = placements[b]!.frame;
      const overlaps = first.x < second.x + second.width && second.x < first.x + first.width
        && first.y < second.y + second.height && second.y < first.y + first.height;
      expect(overlaps).toBeFalse();
    }
  });

  test("client minimum sizes are honored and too-small presets advance from the actual width", () => {
    let state = stateOf(group(0, [leaf("one"), leaf("two")], 0));
    state = reduce(state, A.AppMinSize("one", [800, 400]));
    let preferences = setScrollSize(emptyScrollPreferences(), state, "app:one", Axis.Horizontal, 1 / 3);
    preferences = setScrollSize(preferences, state, "app:one", Axis.Vertical, 1 / 3);
    const initial = scrollingScreens(baseOf(state), state, preferences);
    expect(frame(initial, "one").width).toBe(800);
    expect(frame(initial, "one").height).toBe(400);
    preferences = cycleScrollSize(preferences, state, "app:one", Axis.Horizontal, false, 1440);
    expect(frame(scrollingScreens(baseOf(state), state, preferences), "one").width).toBeCloseTo(960);
  });

  test("page-requested fullscreen is still bare fullscreen rather than a scrolling size", () => {
    const state = reduce(stateOf(group(0, [leaf("one"), leaf("two")], 0)), A.PageFullscreened("app:one", true));
    const bases = baseOf(state);
    const before = JSON.stringify(state);
    const result = scrollingScreens(bases, state, emptyScrollPreferences());
    expect(result.screens[0]).toBe(bases[0]);
    expect(result.screens[0]!.screenful.placements.find(placement => placement.id === "app:one")!.bare).toBeTrue();
    expect(JSON.stringify(state)).toBe(before);
  });
});

describe("scrolling recovery", () => {
  test("encoding and decoding reproduces exact widths, heights and manually panned offsets", () => {
    const state = stateOf(group(0, [leaf("one"), group(1, [leaf("two"), leaf("three")], 1)], 1));
    let preferences = setScrollSize(emptyScrollPreferences(), state, "app:three", Axis.Horizontal, 2 / 3);
    preferences = setScrollSize(preferences, state, "app:two", Axis.Vertical, 1 / 2);
    const before = scrollingScreens(baseOf(state), state, preferences);
    preferences = panScroll(before.preferences, state, "1", Axis.Horizontal, -120);
    const panned = scrollingScreens(baseOf(state), state, preferences);
    const identity = "a".repeat(64);
    const recovered = decodeScrollPreferences(encodeScrollPreferences(identity, panned.preferences), identity);
    const after = scrollingScreens(baseOf(state), state, recovered);
    expect(after.screens).toEqual(panned.screens);
    expect(after.preferences).toBe(recovered);
  });
  test("wrong desktop identity, malformed geometry and oversized inputs are refused", () => {
    const text = encodeScrollPreferences("old", emptyScrollPreferences());
    expect(() => decodeScrollPreferences(text, "new")).toThrow();
    expect(() => decodeScrollPreferences('{"version":1,"identity":"same","preferences":[]}', "same")).toThrow();
    const preferences = { ...emptyScrollPreferences(), widths: { "app:bad": 0 } };
    expect(() => decodeScrollPreferences(encodeScrollPreferences("same", preferences), "same")).toThrow();
    expect(() => decodeScrollPreferences(" ".repeat(4 * 1024 * 1024 + 1), "same")).toThrow();
  });
  test("closed windows lose their size preferences while unrelated live windows keep theirs", () => {
    const state = stateOf(group(0, [leaf("one"), leaf("two")]));
    const preferences = { ...emptyScrollPreferences(), widths: { "app:one": 1 / 3, "app:closed": 1 / 2 } };
    const pruned = pruneScrollPreferences(preferences, state);
    expect(pruned.widths).toEqual({ "app:one": 1 / 3 });
    expect(pruneScrollPreferences(pruned, state)).toBe(pruned);
  });
});
