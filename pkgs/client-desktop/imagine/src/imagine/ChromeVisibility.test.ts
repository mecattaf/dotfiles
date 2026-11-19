import { describe, expect, test } from "bun:test";
import type { Geometry } from "@domicile-desktop/manganese-window-management/placement";
import type { StageScreen } from "@domicile-desktop/manganese-window-management/screens/stage-screens";
import type { WindowState } from "@domicile-desktop/manganese-window-management/window-state";
import { agencyPlacement } from "./layout";
import { chromeCommand, presentChrome, pruneChromeVisibility, roundedChromeCss, toggleChrome } from "./ChromeVisibility";

type Workspace = WindowState["workspaces"][number];
type Node = NonNullable<Workspace["tiling"]["root"]>;
const leaf = (id: string): Node => ({ kind: 1, id, focusedAt: 0 });
const group = (layout: 0 | 1 | 2 | 3, children: readonly Node[], focused = 0): Node =>
  ({ kind: 0, layout, children, focused, fractions: children.map(() => 1 / children.length) });
const geometry: Geometry = {
  name: "upper", screen: { x: 0, y: 0, width: 1440, height: 900 },
  workspace: { x: 256, y: 0, width: 1184, height: 900 },
  desktop: { x: 0, y: 0, width: 1440, height: 1800 },
};
const workspace = (root: Node): Workspace => ({ name: "1", floats: [],
  floatFocus: undefined, fullscreen: undefined, tiling: { root, depth: 10 } });
const screen = (state: Workspace): StageScreen => ({ current: "1", floats: state.floats,
  fullscreen: state.fullscreen === undefined ? undefined : { group: false, windows: [state.fullscreen.id] },
  geometry, screenful: agencyPlacement(state, geometry) });

describe("Imagine per-running-window chrome", () => {
  test("toggle preserves ids, native frame identity, layout and original placement", () => {
    const state = workspace(group(0, [leaf("app:one"), leaf("browser:two")]));
    const original = screen(state), source = JSON.stringify(original);
    const hidden = toggleChrome(new Set(), "app:one");
    const result = presentChrome([original], hidden);
    const before = original.screenful.placements[0]!, after = result.screens[0]!.screenful.placements[0]!;
    expect(after.id).toBe(before.id);
    expect(after.frame).toBe(before.frame);
    expect(after.surface).toBe(after.frame);
    expect(after.surface!.height - before.surface!.height).toBe(29);
    expect(after.bare).toBe(true);
    expect(result.screens[0]!.screenful.placements[1]).toBe(original.screenful.placements[1]);
    expect(result.roundedWindows).toEqual(new Set(["app:one"]));
    expect(JSON.stringify(original)).toBe(source);
    expect(presentChrome([original], toggleChrome(hidden, "app:one")).screens[0]).toBe(original);
  });
  test("a shared strip hides only while its visible window requests it", () => {
    const a = leaf("app:one"), b = leaf("browser:two");
    const original = screen(workspace(group(3, [a, b])));
    const hidden = new Set(["app:one"]);
    const result = presentChrome([original], hidden).screens[0]!.screenful;
    expect(result.placements.every((place) => place.bare && place.strip === undefined)).toBe(true);
    expect(result.placements[0]!.surface).toEqual(geometry.workspace);
    expect(result.placements[1]!.surface).toBeUndefined();
    const siblingSelected = screen(workspace(group(3, [a, b], 1)));
    expect(presentChrome([siblingSelected], hidden).screens[0]).toBe(siblingSelected);
  });
  test("stacking reclaims the whole immediate strip and leaves siblings hidden", () => {
    const result = presentChrome([screen(workspace(group(2, [leaf("a"), leaf("b")])))], new Set(["a"]));
    const placements = result.screens[0]!.screenful.placements;
    expect(placements[0]!.surface).toEqual(geometry.workspace);
    expect(placements[1]!.surface).toBeUndefined();
  });
  test("nested ancestor container tabs remain while leaf chrome is hidden", () => {
    const original = screen(workspace(group(3, [group(0, [leaf("a"), leaf("b")]), leaf("c")])));
    const result = presentChrome([original], new Set(["a"])).screens[0]!;
    expect(result.screenful.tabs).toEqual(original.screenful.tabs);
    expect(result.screenful.placements.find(({ id }) => id === "a")!.surface!.y).toBe(30);
    expect(result.screenful.placements.find(({ id }) => id === "b")).toBe(original.screenful.placements.find(({ id }) => id === "b"));
  });
  test("floating keeps frame geometry and fullscreen does not gain rounded screen corners", () => {
    const state = workspace(leaf("tile"));
    const floating = { root: leaf("float"), depth: 10, x: 25, y: 40, width: 600, height: 400,
      bare: false, scratchpad: false };
    const original = screen({ ...state, floats: [floating] });
    const result = presentChrome([original], new Set(["float"]));
    const place = result.screens[0]!.screenful.placements.find(({ id }) => id === "float")!;
    expect(place.surface).toEqual({ x: 25, y: 40, width: 600, height: 400 });
    expect(result.roundedWindows.has("float")).toBe(true);
    const fullscreen = screen({ ...state, fullscreen: { id: "tile", up: 0, global: false } });
    const full = presentChrome([fullscreen], new Set(["tile"]));
    expect(full.screens[0]!.screenful.placements[0]!.surface).toEqual(geometry.screen);
    expect(full.roundedWindows.size).toBe(0);
    const bare = screen({ ...state, fullscreen: { id: "tile", up: 0, global: false, bare: true } });
    expect(presentChrome([bare], new Set(["tile"])).screens[0]).toBe(bare);
  });
  test("commands are explicit, focused by default, and never target a closed window", () => {
    const empty = new Set<string>(), live = new Set(["app:one", "browser:two"]);
    const first = chromeCommand(empty, ["chrome", "toggle"], "app:one", live);
    expect(first.hidden).toEqual(new Set(["app:one"]));
    expect(chromeCommand(first.hidden, ["chrome", "show", "app:one"], undefined, live).hidden.size).toBe(0);
    expect(chromeCommand(empty, ["chrome", "hide", "missing"], "app:one", live).error).toBeDefined();
    expect(chromeCommand(empty, ["chrome", "hide", "app:one", "extra"], undefined, live).error).toBeDefined();
    expect(chromeCommand(empty, ["rail", "toggle"], "app:one", live).handled).toBe(false);
    expect(pruneChromeVisibility(first.hidden, new Set(["browser:two"])).size).toBe(0);
    expect(pruneChromeVisibility(first.hidden, live)).toBe(first.hidden);
  });
  test("corner styles identify host surfaces, never titles or mutable URLs", () => {
    const css = roundedChromeCss(new Set(["app:one", "browser:two", 'app:a\"]{}<']));
    expect(css).toContain('app[app-id="one"]');
    expect(css).toContain('webview[window="two"]');
    expect(css).toContain("border-start-start-radius:8px");
    expect(css).not.toContain('app-id="a"]{}<');
    expect(roundedChromeCss(new Set(["unknown"]))).toBe("");
  });
});
