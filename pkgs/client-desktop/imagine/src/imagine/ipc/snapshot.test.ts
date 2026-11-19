import { test, expect } from "bun:test";
import { WindowAction as A } from "@domicile-desktop/manganese-window-management/window-state";
import type { WindowState } from "@domicile-desktop/manganese-window-management/window-state";
import { ShellWindow } from "@domicile-desktop/manganese-window-management/window";
import { initialAgencyState, agencyReducer } from "../policy";
import { parseRequest, SnapshotController } from "./protocol";
import { projectSnapshot } from "./snapshot";
const nonce="a".repeat(32),desktopId="private-fixture",epoch="11111111-1111-4111-8111-111111111111";
const request={requestId:nonce,desktopId};
const sdkSource="67c29a9906905bd5e1679803232c2f510b3fed9e";
type Node=NonNullable<WindowState["workspaces"][number]["tiling"]["root"]>;
const leaf=(id:string):Node=>({kind:1,id,focusedAt:0});
const group=(layout:0|1|2|3,children:Node[],focused=0):Node=>({kind:0,layout,children,focused,fractions:children.map(()=>1/children.length)});
const fresh=()=>agencyReducer(initialAgencyState(),A.ScreensDescribed([{name:"upper",box:{x:0,y:0,width:1440,height:900}},{name:"lower",box:{x:0,y:900,width:1440,height:900}}]));
function input(){
  const base=fresh();
  const root=group(0,[leaf("app:a"),group(3,[leaf("browser:b"),leaf("app:c")],1)]);
  return {state:{...base,windows:[ShellWindow.App("a","PRIVATE TITLE"),ShellWindow.Browser("b","https://secret.invalid/path?token=private","PRIVATE PAGE",undefined,false,true),ShellWindow.App("c","C"),ShellWindow.App("float","F"),ShellWindow.App("hidden","H")],workspaces:base.workspaces.map(w=>w.name!=="1"?w:{...w,tiling:{depth:2,root},floats:[{root:leaf("app:float"),depth:0,x:5,y:6,width:500,height:300,bare:false,scratchpad:true}]}),scratchpad:["app:hidden"]},screens:[],browsers:[{id:"b",appId:"agency-web",url:"https://secret.invalid",title:"PRIVATE PAGE",width:0,height:0,isApp:true,isPrivate:false,isCaptured:false,partition:"private",popupWindow:undefined}]};
}
test("projects actual nested tree, floats, workspace homes and scratchpad membership",()=>{
  const snapshot=projectSnapshot(input());const one=snapshot.workspaces.find(w=>w.name==="1")!;
  expect(one.enclosedWindows.map(w=>w.value)).toEqual(["app:a","browser:b","app:c","app:float"]);
  expect(one.tiling.root?.kind).toBe("container");expect(one.floats[0]?.scratchpad).toBe(true);
  expect(snapshot.scratchpad.windows).toEqual([{kind:"window",value:"app:hidden"}]);
  expect(snapshot.workspaces.find(w=>w.name==="10")?.homeOutput?.value).toBe("lower");
  expect(snapshot.windows.find(w=>w.kind==="browser")?.appId?.value).toBe("agency-web");
});
test("privacy allowlist excludes titles, URLs, descriptions, partitions and frame counters",()=>{
  const text=JSON.stringify(projectSnapshot(input()));for(const secret of ["PRIVATE","secret.invalid","token=","syncedFrame","partition"]){expect(text).not.toContain(secret);}
});
test("native focus unwraps the reducer window namespace into the native ID type",()=>{
  const data=input();const snapshot=projectSnapshot({...data,state:{...data.state,focusedId:"app:a"}});
  expect(snapshot.focus.nativeWindow).toEqual({kind:"native-window",value:"a"});
});
test("revisions ignore content repaint and titles, change for layout or focus",()=>{
  const data=input();const c=new SnapshotController({desktopId,imagineSource:"fixture",sdkSource},epoch);c.update(data,false);const first=c.reply(request,false);
  c.update({...data,state:{...data.state,windows:data.state.windows.map(w=>({...w,title:"new video title",syncedFrame:999}))}},false);
  expect(c.reply(request,false).revision).toBe(first.revision);
  c.update({...data,state:agencyReducer(data.state,A.WorkspaceSelected("2"))},false);
  expect(c.reply(request,false).revision).toBe(first.revision+1);
  expect(c.reply({...request,expected:{epoch,revision:first.revision}},false)).toMatchObject({ok:false,error:{code:"stale-revision"}});
});
test("reconnect starts a new epoch and old container references fail",()=>{
  const c=new SnapshotController({desktopId,imagineSource:"fixture",sdkSource});c.update(input(),false);
  expect(c.reply({...request,expected:{epoch,revision:1}},false)).toMatchObject({ok:false,error:{code:"epoch-changed"}});
});
test("lock unknown/true never returns a snapshot, including lock after capture",()=>{
  const c=new SnapshotController({desktopId,imagineSource:"fixture",sdkSource},epoch);c.update(input(),false);
  for(const lock of [undefined,true]){const reply=c.reply(request,lock);expect(reply.ok).toBe(false);expect(reply).not.toHaveProperty("snapshot");}
  c.update(input(),true);expect(c.reply(request,false)).toMatchObject({ok:false});
  c.update(input(),false);expect(c.reply(request,false).ok).toBe(true);
});
test("commands accept only canonical read-only verb, explicit identity and bounded nonce",()=>{
  expect(parseRequest(["imagine","snapshot-v1",nonce,desktopId,"-","-"])).toEqual(request);
  for(const words of [["imagine","close",nonce,desktopId,"-","-"],["imagine","snapshot-v1","../../escape",desktopId,"-","-"],["imagine","snapshot-v1",nonce,desktopId,"-","99"],["imagine","snapshot-v1",nonce,desktopId,"-","-","extra"]])expect(parseRequest(words)).toBeUndefined();
  const c=new SnapshotController({desktopId,imagineSource:"fixture",sdkSource},epoch);c.update(input(),false);expect(c.reply({...request,desktopId:"other"},false)).toMatchObject({ok:false,error:{code:"wrong-desktop"}});
});
test("cross-language fixture uses real reducer types and serializer",async()=>{
  const c=new SnapshotController({desktopId,imagineSource:"fixture",sdkSource},epoch);c.update(input(),false);
  const file=Bun.env.DSH_SNAPSHOT_FIXTURE;if(file)await Bun.write(file,JSON.stringify(c.reply(request,false)));
});

test("SDK provenance is explicitly configured, never defaulted to the stock pin",()=>{
  for(const sdkSource of ["67c29a9906905bd5e1679803232c2f510b3fed9e","965dea4077415691f7ad409d5d5b5df82115575c"]) {
    const c=new SnapshotController({desktopId,imagineSource:"fixture",sdkSource},epoch);
    c.update(input(),false);expect(c.reply(request,false).source.sdk).toBe(sdkSource);
    expect(c.reply(request,true).source.sdk).toBe(sdkSource);
  }
  for(const invalid of [undefined,null,"", "67c29a9", "A".repeat(40),"x".repeat(40)]) {
    expect(()=>new SnapshotController({desktopId,imagineSource:"fixture",sdkSource:invalid as string})).toThrow("invalid snapshot identity");
  }
});
