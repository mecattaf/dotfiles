import { expect, test } from "bun:test";
import { captureRecovery, captureSnapshotRecovery, rebindRecovery, decodeRecovery } from "./RestartRecovery";
import { EMPTY_CATALOGUE, receiveCatalogue } from "./SessionCatalogue";
import { initialAgencyState, agencyReducer as reduce } from "./policy";
import { WindowAction as A, workspaceHolding } from "@domicile-desktop/manganese-window-management/window-state";
import { restoreLayout } from "./LayoutRestore";
const tag = "agencychat" + "a".repeat(32);
const cat = receiveCatalogue(EMPTY_CATALOGUE, { type: "viewers", viewers: [{ sessionId: "session-a", tag }] }, "agency-web");
const add = (state: ReturnType<typeof initialAgencyState>, id: string, desktop: string) => reduce(reduce(state, A.AppAppeared(id, "PRIVATE TITLE")), A.AppDesktopIdChanged(id, desktop));
const saved = () => {
  let state = add(initialAgencyState(), "old-id", "chrome-file__" + tag + "_start");
  state = reduce(state, A.WindowSelected("app:old-id"));
  state = reduce(state, A.WindowSentToWorkspace("4"));
  state = add(state, "unrelated", "unrelated-app");
  return captureRecovery(state, cat, "agency-web", "a".repeat(64), 123);
};
test("checkpoint records DSH identities and layout without titles, URLs, commands or provider state", () => {
  const checkpoint = saved();
  expect(checkpoint.slots).toHaveLength(1); expect(checkpoint.omitted).toBe(1);
  expect(checkpoint.slots[0]!.route).toEqual({ kind: "chat", server: "agency-web", session: "session-a", tag });
  const text = JSON.stringify(checkpoint);
  for (const secret of ["PRIVATE TITLE", "http://", '"argv"', '"prompt"']) expect(text.includes(secret)).toBeFalse();
});
test("rebinds a new SDK identity after a real restart and keeps unrelated fresh windows", () => {
  let current = add(initialAgencyState(), "unrelated", "chrome-file__" + tag + "_start");
  current = add(current, "old-id", "new-unrelated-app"); // deliberate app-ID reuse
  const checkpoint = saved();
  const rebound = rebindRecovery(checkpoint, current, [{ savedWindow: "app:old-id", window: "app:unrelated" }], false);
  const restored = restoreLayout(current, rebound);
  expect(workspaceHolding(restored, "app:unrelated")?.name).toBe("4");
  expect(workspaceHolding(restored, "app:old-id")?.name).toBe("1");
  expect(restored.windows).toEqual(current.windows);
});
test("refuses duplicate bindings, missing windows and unknown saved slots", () => {
  const checkpoint = saved(), current = add(initialAgencyState(), "new", "chrome-file__" + tag + "_start");
  const binding = { savedWindow: "app:old-id", window: "app:new" };
  expect(() => rebindRecovery(checkpoint, current, [binding, binding], false)).toThrow();
  expect(() => rebindRecovery(checkpoint, current, [{ ...binding, window: "app:missing" }], false)).toThrow();
  expect(() => rebindRecovery(checkpoint, current, [{ ...binding, savedWindow: "app:unrelated" }], false)).toThrow();
});
test("ambiguous DSH viewer tags and duplicate session viewers are omitted from automatic recovery", () => {
  let state = add(initialAgencyState(), "one", "chrome-" + tag);
  state = add(state, "two", "chrome-" + tag);
  expect(captureRecovery(state, cat, "agency-web", "b".repeat(64), 0).slots).toHaveLength(0);
});
test("the ordinary DSH web window can recover without inventing a session identity", () => {
  const main = "agencychat" + "b".repeat(32);
  const catalogue = receiveCatalogue(EMPTY_CATALOGUE, { type: "viewers", viewers: [], mainViewers: [main] }, "agency-web");
  const state = add(initialAgencyState(), "main", "chrome-file__" + main + "_start");
  const checkpoint = captureRecovery(state, catalogue, "agency-web", "b".repeat(64), 0);
  expect(checkpoint.slots[0]!.route).toEqual({ kind: "web", server: "agency-web", tag: main });
});

test("planned-restart pins are explicit and invalid pin values are rejected", () => {
  const checkpoint = saved();
  expect(decodeRecovery(JSON.stringify({ ...checkpoint, pinned: true })).pinned).toBeTrue();
  expect(() => decodeRecovery(JSON.stringify({ ...checkpoint, pinned: "yes" }))).toThrow();
});

test("only the declared legacy Agency Web app migrates to a Chrome main viewer", () => {
  const browser = {id:"legacy",appId:"agency-web",url:"http://private.invalid/?token=secret",title:"PRIVATE",width:0,height:0,isApp:true,isPrivate:false,isCaptured:false,partition:"persist:fixture",popupWindow:undefined};
  let before = reduce(initialAgencyState(), A.BrowserWindowsListed([browser, {...browser,id:"ambient",appId:"agency-chat-ambient"}], ["agency-chat-ambient"]));
  before = reduce(reduce(before, A.WindowSelected("browser:legacy")), A.WindowSentToWorkspace("4"));
  before = reduce(before, A.WorkspaceSelected("4"));
  const snapshot = captureRecovery(before, EMPTY_CATALOGUE, "agency-web", "b".repeat(64), 0).snapshot;
  const enriched = {...snapshot,windows:snapshot.windows.map(w=>w.kind!=="browser"?w:{...w,appId:{kind:"browser-app" as const,value:w.browserId.value==="legacy"?"agency-web":"agency-chat-ambient"}})};
  const checkpoint = captureSnapshotRecovery(enriched, EMPTY_CATALOGUE, "agency-web", "b".repeat(64), 0);
  expect(decodeRecovery(JSON.stringify(checkpoint)).slots).toHaveLength(1);
  expect(checkpoint.slots[0]!.savedWindow).toBe("browser:legacy");
  expect(checkpoint.slots[0]!.route.kind).toBe("web");
  const current = add(initialAgencyState(), "new", "chrome-main");
  const rebound = rebindRecovery(checkpoint, current, [{savedWindow:"browser:legacy",window:"app:new"}], true);
  expect(workspaceHolding(restoreLayout(current,rebound),"app:new")?.name).toBe("4");
  expect(rebound.focus.nativeWindow).toEqual({kind:"native-window",value:"new"});
  const privateApp={...enriched,windows:enriched.windows.map(w=>w.kind==="browser"?{...w,isPrivate:true}:w)};
  expect(captureSnapshotRecovery(privateApp,EMPTY_CATALOGUE,"agency-web","b".repeat(64),0).slots).toHaveLength(0);
  expect(JSON.stringify(checkpoint)).not.toContain("secret");
});

test("full restart rebinds floating fullscreen and hidden scratchpad viewers", () => {
  const second="agencychat"+"c".repeat(32),terminalClass="dsh-terminal-"+"d".repeat(20);
  const fresh=()=>reduce(initialAgencyState(),A.ScreensDescribed([{name:"upper",box:{x:0,y:0,width:1400,height:900}},{name:"lower",box:{x:0,y:900,width:1400,height:900}}]));
  let before=reduce(fresh(),A.WorkspaceSelected("4"));
  before=add(before,"float", "chrome-"+tag);before=add(before,"hidden","chrome-"+second);
  before=reduce(reduce(before,A.WindowSelected("app:hidden")),A.WindowSentToScratchpad());
  before=add(before,"terminal",terminalClass);before=reduce(before,A.WindowSentToWorkspace("6"));
  before=reduce(reduce(before,A.WindowFloated("app:float")),A.WindowFullscreened("app:float"));
  const metadata={...EMPTY_CATALOGUE,viewers:[{sessionId:"session-a",tag},{sessionId:"session-b",tag:second}],terminals:[{title:"Terminal",route:{version:1 as const,server:"agency-web",epoch:"fixture",session:"session-a",terminal:"term-a",windowClass:terminalClass}}]};
  const checkpoint=captureRecovery(before,metadata,"agency-web","e".repeat(64),0);
  let now=add(fresh(),"new-float","chrome-"+tag);now=add(now,"new-hidden","chrome-"+second);now=add(now,"new-terminal",terminalClass);now=add(now,"float","unrelated-fresh-app");
  const restored=restoreLayout(now,rebindRecovery(checkpoint,now,[{savedWindow:"app:float",window:"app:new-float"},{savedWindow:"app:hidden",window:"app:new-hidden"},{savedWindow:"app:terminal",window:"app:new-terminal"}],true));
  const previous=before.workspaces.find(w=>w.name==="4")!,next=restored.workspaces.find(w=>w.name==="4")!;
  expect(next.floats.map(({root,...geometry})=>geometry)).toEqual(previous.floats.map(({root,...geometry})=>geometry));
  expect(next.fullscreen?.id).toBe("app:new-float");
  expect(restored.scratchpad).toContain("app:new-hidden");
  expect(workspaceHolding(restored,"app:new-terminal")?.name).toBe("6");
  expect(workspaceHolding(restored,"app:float")?.name).toBe("1");
});
