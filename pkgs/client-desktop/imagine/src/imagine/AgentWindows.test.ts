import {expect,test} from "bun:test";
import {WindowAction as A,activeIdOf,workspaceHolding} from "@domicile-desktop/manganese-window-management/window-state";
import {agencyReducer as reduce,initialAgencyState} from "./policy";
import {reduceChatNativeBatch} from "./ChatWindow";
import {isAgentDesktopId} from "./AgentWindows";
const fresh=()=>reduce(initialAgencyState(),A.ScreensDescribed([
  {name:"upper",box:{x:0,y:0,width:1440,height:900}},
  {name:"lower",box:{x:0,y:900,width:1440,height:900}},
]));
for(const occupied of [false,true])for(const navigated of [false,true])test(`agent first-frame placement keeps both views and focus; occupied=${occupied}, navigation=${navigated}`,()=>{
  let state=reduce(fresh(),A.AppAppeared("old","old"));
  if(occupied){state=reduce(state,A.WorkspaceSelected("2"));state=reduce(state,A.AppAppeared("other","other"));state=reduce(state,A.WorkspaceSelected("1"));}
  if(navigated){state=reduce(state,A.WorkspaceSelected("2"));state=reduce(state,A.AppAppeared("user","user"));}
  const before=state;
  const after=reduceChatNativeBatch(before,{chatNativeBatch:true,actions:[A.AppAppeared("agent","agent")],
    placements:[{chatPlacement:true,agent:true,id:"app:agent",workspace:"2",origin:{screen:"upper",workspace:"1"},reveal:false}]},reduce);
  expect(after.screens).toBe(before.screens);expect(after.focused).toBe(before.focused);
  expect(activeIdOf(after)).toBe(activeIdOf(before));
  expect(before.screens.map(s=>s.current)).not.toContain(workspaceHolding(after,"app:agent")?.name);
  expect(after.pressed).toBe(before.pressed);
});
test("quiet native identities survive shell reload without an in-memory reservation",()=>{
  expect(isAgentDesktopId('agencyagent'+'a'.repeat(32))).toBe(true);
  expect(isAgentDesktopId('chrome_agencychata6e17a11'+'b'.repeat(24))).toBe(true);
  expect(isAgentDesktopId('domicile-terminal')).toBe(false);
  expect(isAgentDesktopId('agencychat'+'c'.repeat(32))).toBe(false);
});
