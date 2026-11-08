import { expect, test } from "bun:test";
import { WindowAction as A, workspaceHolding, activeIdOf } from "@domicile-desktop/manganese-window-management/window-state";
import { appWindowId } from "@domicile-desktop/manganese-window-management/window";
import { agencyReducer as reduce, initialAgencyState } from "./policy";
import { chatOrigin, emptyChatWorkspace, placeChatWindow, reduceChatNativeBatch } from "./ChatWindow";

const fresh = () => reduce(initialAgencyState(), A.ScreensDescribed([
  { name: "upper", box: { x: 0, y: 0, width: 1440, height: 900 } },
  { name: "lower", box: { x: 0, y: 900, width: 1440, height: 900 } },
]));

test("Enter reserves an empty unshown workspace and places exactly its new native viewer", () => {
  let state = reduce(fresh(), A.AppAppeared("existing", "Existing"));
  expect(emptyChatWorkspace(state)).toBe("2");
  const origin = chatOrigin(state)!;
  state = reduce(state, A.AppAppeared("chrome-app", "Chat"));
  state = placeChatWindow(state, { chatPlacement: true, id: appWindowId("chrome-app"), workspace: "2", origin, reveal: true }, reduce);
  expect(workspaceHolding(state, appWindowId("chrome-app"))?.name).toBe("2");
  expect(workspaceHolding(state, appWindowId("existing"))?.name).toBe("1");
  expect(chatOrigin(state)?.workspace).toBe("2");
});

test("navigation after Enter wins over a delayed Chrome launch", () => {
  let state = fresh();
  const origin = chatOrigin(state)!;
  state = reduce(state, A.WorkspaceSelected("3"));
  state = reduce(state, A.AppAppeared("late", "Late"));
  state = placeChatWindow(state, { chatPlacement: true, id: appWindowId("late"), workspace: "2", origin, reveal: true }, reduce);
  expect(workspaceHolding(state, appWindowId("late"))?.name).toBe("2");
  expect(chatOrigin(state)?.workspace).toBe("3");
});

test("lock or modal can suppress late reveal without losing the chat", () => {
  let state = fresh();
  const origin = chatOrigin(state)!;
  state = reduce(state, A.AppAppeared("late", "Late"));
  state = placeChatWindow(state, { chatPlacement: true, id: appWindowId("late"), workspace: "2", origin, reveal: false }, reduce);
  expect(workspaceHolding(state, appWindowId("late"))?.name).toBe("2");
  expect(chatOrigin(state)?.workspace).toBe("1");
});

test("a workspace occupied since Enter is not reused", () => {
  let state = fresh();
  const origin = chatOrigin(state)!;
  state = reduce(state, A.WorkspaceSelected("2"));
  state = reduce(state, A.AppAppeared("someone-else", "Other"));
  state = reduce(state, A.WorkspaceSelected("1"));
  state = reduce(state, A.AppAppeared("chat", "Chat"));
  const before = state;
  state = placeChatWindow(state, { chatPlacement: true, id: appWindowId("chat"), workspace: "2", origin, reveal: true }, reduce);
  expect(state).toBe(before);
});

test("workspace 10 remains unavailable on a single display", () => {
  let state = reduce(initialAgencyState(), A.ScreensDescribed([
    { name: "one", box: { x: 0, y: 0, width: 1440, height: 900 } },
  ]));
  for (let number = 2; number <= 9; number++) {
    state = reduce(state, A.WorkspaceSelected(String(number)));
    state = reduce(state, A.AppAppeared("occupied-" + number, "Other"));
  }
  state = reduce(state, A.WorkspaceSelected("1"));
  expect(emptyChatWorkspace(state)).toBeUndefined();
});

test("first native announcement and placement are atomic and preserve old focus when reveal is suppressed", () => {
  const before = reduce(fresh(), A.AppAppeared("existing", "Existing"));
  const after = reduceChatNativeBatch(before, { chatNativeBatch: true,
    actions: [A.AppAppeared("new", "Chat"), A.AppDesktopIdChanged("new", "chrome-tag")],
    placements: [{ chatPlacement: true, id: appWindowId("new"), workspace: "2", origin: chatOrigin(before)!, reveal: false }],
  }, reduce);
  expect(workspaceHolding(after, appWindowId("new"))?.name).toBe("2");
  expect(activeIdOf(after)).toBe(appWindowId("existing"));
  expect(chatOrigin(after)?.workspace).toBe("1");
});
