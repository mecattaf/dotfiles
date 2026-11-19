import { expect, test } from "bun:test";
import { WindowAction as A, activeIdOf, workspaceHolding } from "@domicile-desktop/manganese-window-management/window-state";
import { agencyReducer as reduce, initialAgencyState } from "./policy";
import { restoreLayout } from "./LayoutRestore";
import { projectSnapshot } from "./ipc/snapshot";
const displays = [{ name: "upper", box: { x: 0, y: 0, width: 1440, height: 900 } }, { name: "lower", box: { x: 0, y: 900, width: 1440, height: 900 } }];
const fresh = () => reduce(initialAgencyState(), A.ScreensDescribed(displays));
const appear = (state: ReturnType<typeof fresh>, id: string) => reduce(reduce(state, A.AppAppeared(id, id)), A.AppDesktopIdChanged(id, "test-" + id));
const snapshot = (state: ReturnType<typeof fresh>) => projectSnapshot({ state, screens: [] });
test("reload restores workspace membership, split trees, floats and both visible workspaces", () => {
  let before = appear(fresh(), "one");
  before = reduce(before, A.WorkspaceSelected("4")); before = appear(before, "two"); before = appear(before, "three");
  before = reduce(before, A.WorkspaceSelected("10")); before = appear(before, "lower");
  let after = fresh(); for (const id of ["one", "two", "three", "lower"]) after = appear(after, id);
  const windows = after.windows;
  after = restoreLayout(after, snapshot(before));
  expect(after.workspaces).toEqual(before.workspaces);
  expect(after.screens).toEqual(before.screens);
  expect(after.focused).toEqual(before.focused);
  expect(activeIdOf(after)).toBe(activeIdOf(before));
  expect(after.windows).toBe(windows);
});
test("closed windows are pruned and newly arrived windows keep their place", () => {
  let before = appear(fresh(), "closed"); before = reduce(before, A.WorkspaceSelected("5")); before = appear(before, "kept");
  let after = appear(appear(fresh(), "kept"), "new");
  after = restoreLayout(after, snapshot(before));
  expect(workspaceHolding(after, "app:kept")?.name).toBe("5");
  expect(workspaceHolding(after, "app:new")?.name).toBe("1");
  expect(after.windows.some(w => w.id === "app:closed")).toBeFalse();
});
test("an ID with a changed native desktop identity is not restored", () => {
  let old = reduce(fresh(), A.WorkspaceSelected("7")); old = appear(old, "reused");
  const now = reduce(appear(fresh(), "reused"), A.AppDesktopIdChanged("reused", "different"));
  const restored = restoreLayout(now, snapshot(old));
  expect(workspaceHolding(restored, "app:reused")?.name).toBe("1");
});
test("malformed and duplicate layouts are rejected before any reducer mutation", () => {
  const state = appear(fresh(), "one"), saved = snapshot(state);
  saved.workspaces[1]!.tiling.root = saved.workspaces[0]!.tiling.root;
  expect(() => restoreLayout(state, saved)).toThrow();
  expect(workspaceHolding(state, "app:one")?.name).toBe("1");
});
test("floating geometry, fullscreen and scratchpad survive a shell-only refresh", () => {
  let before = appear(appear(fresh(), "float"), "hidden");
  before = reduce(before, A.WindowSelected("app:hidden")); before = reduce(before, A.WindowSentToScratchpad());
  before = reduce(before, A.WindowFloated("app:float"));
  before = reduce(before, A.WindowFullscreened("app:float"));
  let now = appear(appear(fresh(), "float"), "hidden");
  const restored = restoreLayout(now, snapshot(before));
  expect(snapshot(restored).workspaces).toEqual(snapshot(before).workspaces);
  expect(restored.scratchpad).toEqual(before.scratchpad);
});
test("retained browser guests recover their workspace while keeping current SDK contents", () => {
  const browser = { id: "retained", appId: "agency-web", url: "http://127.0.0.1:17318/", title: "Old title", width: 0, height: 0,
    isApp: true, isPrivate: false, isCaptured: false, partition: "", popupWindow: undefined };
  const before = reduce(reduce(fresh(), A.WorkspaceSelected("8")), A.BrowserWindowsListed([browser], []));
  const current = reduce(fresh(), A.BrowserWindowsListed([{ ...browser, title: "Updated title" }], []));
  const restored = restoreLayout(current, snapshot(before));
  expect(workspaceHolding(restored, "browser:retained")?.name).toBe("8");
  expect(restored.windows).toBe(current.windows);
  expect(restored.windows[0]!.title).toBe("Updated title");
  expect(JSON.stringify(snapshot(restored))).not.toContain("Updated title");
});
