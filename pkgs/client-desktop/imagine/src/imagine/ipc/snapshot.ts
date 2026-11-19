// Read-only projection of the public reducer and the final Stage geometry.
// No action callbacks, page contents, titles, URLs, frame counters or environments.
import type { WindowState } from "@domicile-desktop/manganese-window-management/window-state";
import { activeIdOf } from "@domicile-desktop/manganese-window-management/window-state";
import type { StageScreen } from "@domicile-desktop/manganese-window-management/screens/stage-screens";
import { WindowKind, appIdOf, browserIdOf } from "@domicile-desktop/manganese-window-management/window";
import type { BrowserWindow } from "@domicile-desktop/sdk/desktop/browser";
import type { Display } from "@domicile-desktop/component-library/display-source";

export type Id<K extends string> = { kind: K; value: string };
const id = <K extends string>(kind: K, value: string): Id<K> => ({kind,value});
const optional = <K extends string>(kind: K, value: string | undefined) => value === undefined ? null : id(kind,value);
export type SnapshotInput = {
  state: WindowState;
  screens: readonly StageScreen[];
  displays?: readonly Display[];
  browsers?: readonly BrowserWindow[];
};
export type Tree = {kind:"window";window:Id<"window">;focusedAt:number} | {
  kind:"container";path:readonly number[];layout:"split-horizontal"|"split-vertical"|"stacking"|"tabbed";
  focusedChild:number;fractions:readonly number[];children:readonly Tree[];
};
// tree/node is not a public package export. Derive its type from WindowState;
// these four enum values are the pinned stock tree's actual wire-independent tags.
type LayoutNode = NonNullable<WindowState["workspaces"][number]["tiling"]["root"]>;
const layoutNames = {0:"split-horizontal",1:"split-vertical",2:"stacking",3:"tabbed"} as const;
function tree(node:LayoutNode|undefined,path:readonly number[]=[]):Tree|null {
  if(node===undefined)return null;
  if("id" in node)return {kind:"window",window:id("window",node.id),focusedAt:node.focusedAt};
  return {kind:"container",path,layout:layoutNames[node.layout],focusedChild:node.focused,fractions:[...node.fractions],children:node.children.map((child,index)=>tree(child,[...path,index])!)};
}
const members = (node:LayoutNode|undefined):string[] => node===undefined?[]:"id" in node?[node.id]:node.children.flatMap(members);
const rect = ({x,y,width,height}:{x:number;y:number;width:number;height:number}) => ({x,y,width,height});
export function projectSnapshot({state,screens,displays,browsers}:SnapshotInput) {
  const held=new Set<string>();
  const workspaces=state.workspaces.map(workspace=>{
    const tiled=members(workspace.tiling.root);
    const floating=workspace.floats.flatMap(float=>members(float.root));
    for(const window of [...tiled,...floating])held.add(window);
    return {
      id:id("workspace",workspace.name),name:workspace.name,
      homeOutput:optional("output",state.homes[workspace.name]||undefined),
      visibleOn:state.screens.filter(s=>s.name!==""&&s.current===workspace.name).map(s=>id("output",s.name)),
      tiling:{depth:workspace.tiling.depth,root:tree(workspace.tiling.root)},
      floats:workspace.floats.map((float,index)=>({index,coordinates:"output-local-logical",rect:rect(float),bare:float.bare,scratchpad:float.scratchpad,depth:float.depth,root:tree(float.root)})),
      floatFocus:optional("window",workspace.floatFocus),
      fullscreen:workspace.fullscreen===undefined?null:{window:id("window",workspace.fullscreen.id),up:workspace.fullscreen.up,global:workspace.fullscreen.global,bare:workspace.fullscreen.bare===true,byPage:workspace.fullscreen.byPage===true},
      enclosedWindows:[...tiled,...floating].map(value=>id("window",value)),
    };
  });
  const hidden=new Set([...state.scratchpad,...state.background]);
  return {
    capabilities:{snapshot:true,workspaceQuery:true,pollSnapshots:true,eventReplay:false,focus:false,layout:false,closeViewer:false,terminateDshSession:false,windowTitles:false,windowUrls:false,windowContents:false},
    coordinates:"desktop-logical",
    containerIdentity:"epoch+revision+workspace+layer+floatIndex+path",
    outputs:state.screens.filter(s=>s.name!=="").map(screen=>({id:id("output",screen.name),logicalGeometry:rect(screen.box),scale:displays?.find(d=>d.name===screen.name)?.scale??null,visibleWorkspace:id("workspace",screen.current),focused:screen.name===state.focused})),
    focus:{output:optional("output",state.focused||undefined),workspace:optional("workspace",state.screens.find(s=>s.name===state.focused)?.current),shellWindow:optional("window",activeIdOf(state)),nativeWindow:optional("native-window",state.focusedId===undefined?undefined:appIdOf(state.focusedId)),replayed:state.replayed},
    workspaces,
    windows:state.windows.map(window=>{
      const placements=screens.flatMap(screen=>screen.screenful.placements.filter(p=>p.id===window.id).map(p=>({output:id("output",screen.geometry.name),frame:rect(p.frame),surface:p.surface===undefined?null:rect(p.surface),bar:rect(p.bar),bare:p.bare,depth:p.depth,selected:p.selected})));
      if(window.kind===WindowKind.App)return {id:id("window",window.id),kind:"native",nativeId:id("native-window",window.appId),desktopAppId:optional("desktop-app",window.desktopId||undefined),placements};
      const browserId=browserIdOf(window.id)!;
      const listed=browsers?.find(b=>b.id===browserId);
      return {id:id("window",window.id),kind:"browser",browserId:id("browser-window",browserId),appId:optional("browser-app",listed?.appId||undefined),isApp:window.isApp,isPrivate:window.isPrivate,placements};
    }),
    scratchpad:{semantics:"hidden queue; shown scratchpad windows are workspace floats with scratchpad=true",windows:state.scratchpad.map(value=>id("window",value))},
    background:state.background.map(value=>id("window",value)),
    unplaced:state.windows.filter(w=>!held.has(w.id)&&!hidden.has(w.id)).map(w=>id("window",w.id)),
    popups:state.popups.map(p=>({id:id("native-popup",p.appId),parent:id("native-window-or-popup",p.parent),position:[...p.position],size:[...p.size],coordinates:"parent-local-logical"})),
  };
}
export type Snapshot = ReturnType<typeof projectSnapshot>;
