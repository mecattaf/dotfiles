import { useEffectEvent, useRef } from "react";
import type { Domicile } from "@domicile-desktop/sdk/desktop/desktop";
import { WindowAction as A, activeIdOf, workspaceHolding } from "@domicile-desktop/manganese-window-management/window-state";
import type { WindowAction, WindowState } from "@domicile-desktop/manganese-window-management/window-state";
import { appWindowId } from "@domicile-desktop/manganese-window-management/window";
import type { Windows } from "./useAgencyWindows";
import type { ChatPlacement } from "./ChatWindow";

const ROOT = ".local/state/kitty-dsh/agent-windows";
export const isAgentDesktopId = (value: string) => /agencyagent[0-9a-f]{32}|agencychata6e17a11[0-9a-f]{24}/.test(value);

/** Runs inside the existing native-announcement reducer transaction. Never
 * render a frame with the new window holding focus on Tom's workspace. */
export function placeAgentWindow(original: WindowState, state: WindowState, placement: ChatPlacement,
  reduce: (s: WindowState, a: WindowAction) => WindowState): WindowState {
  const shown = new Set(original.screens.map(s => s.current));
  const target = !shown.has(placement.workspace) ? placement.workspace :
    original.workspaces.find(w => w.name !== "10" && !shown.has(w.name))?.name;
  let next = reduce(state, A.WindowSelected(placement.id));
  if (target !== undefined) next = reduce(next, A.WindowSentToWorkspace(target));
  const active = activeIdOf(original);
  if (active !== undefined && next.windows.some(w => w.id === active)) next = reduce(next, A.WindowSelected(active));
  return { ...next, screens: original.screens, focused: original.focused,
    focusedId: original.focusedId, pressed: original.pressed, replayed: original.replayed };
}

function valid(value: any, nonce: string, desktop: string): boolean {
  if (!value || typeof value !== "object" || value.desktop !== desktop ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(value.requestId) ||
    value.requestId.replaceAll("-", "") !== nonce || !isAgentDesktopId(value.tag)) return false;
  if (value.kind === "terminal") return Object.keys(value).sort().join() === "cwd,desktop,kind,requestId,tag" &&
    typeof value.cwd === "string" && value.cwd.startsWith("/") && !/[\x00-\x1f\x7f]/.test(value.cwd) &&
    value.tag === "agencyagent" + nonce;
  return value.kind === "chat" && Object.keys(value).sort().join() === "desktop,kind,requestId,sessionId,tag" &&
    /^session-[A-Za-z0-9-]{1,100}$/.test(value.sessionId) && /^agencychata6e17a11[0-9a-f]{24}$/.test(value.tag);
}

export function useAgentWindows({ domicile, windows, blocked }: {domicile: Domicile; windows: Windows; blocked: boolean}) {
  const latest = useRef({ windows, blocked }); latest.current = { windows, blocked };
  const busy = useRef(false);
  return useEffectEvent((args: readonly string[]): boolean => {
    if (args[0] !== "agent-window-v1") return false;
    if (args.length !== 3 || !/^[0-9a-f]{32}$/.test(args[1]!) || !/^[a-z][a-z0-9-]{0,63}$/.test(args[2]!)) return true;
    const path = `${ROOT}/${args[1]}`;
    const work = async () => {
      const read = async (name: string) => (await domicile.files.readText(name)).match({Ok: (s) => JSON.parse(s), Err: () => undefined});
      const value = await read(`${path}/request.json`);
      if (!valid(value, args[1]!, args[2]!)) return;
      const base = {desktop:value.desktop, requestId:value.requestId, kind:value.kind,
        windowId:null as string|null, workspace:null as string|null, focusChanged:false, workspaceChanged:false, retryAutomatically:false};
      const write = async (name: string, data: unknown) => (await domicile.files.write(`${path}/${name}`,JSON.stringify(data),{atomic:true}))
        .match({Ok:()=>undefined,Err:()=>{throw Error("Agent-window receipt write failed");}});
      const fail = (code: string) => write("reply.json", {...base,ok:false,code});
      if (busy.current) return fail("busy");
      if (await read(`${path}/reply.json`) || await read(`${path}/accepted.json`)) return;
      busy.current = true;
      try {
        const identity = await read(".config/dsh-domicile/client.json");
        if (identity?.desktopId !== value.desktop) return fail("not-ready");
        const local = await read(".config/kitty-dsh/agent-windows.json");
        if (typeof local?.launcher !== "string" || !local.launcher.startsWith("/") || /[\s\0]/u.test(local.launcher)) return fail("not-ready");
        if (latest.current.blocked || domicile.session.locked !== false) return fail("locked-or-modal");
        const state = latest.current.windows;
        const shown = new Set(state.screens.map(s => s.current));
        const target = state.workspaces.find(w=>w.name!=="10" && !shown.has(w.name) && w.tiling.root===undefined && w.floats.length===0);
        const screen = state.screens.find(s=>s.name===state.focused);
        if (target===undefined || screen===undefined) return fail("no-workspace");
        // Persistent before spawning: uncertain/reloaded requests never launch
        // twice. No command runs unless the atomic placement is reserved.
        await write("accepted.json",{requestId:value.requestId});
        latest.current.windows.reserveChat(value.tag, {chatPlacement:true, workspace:target.name,
          origin:{screen:screen.name,workspace:screen.current},reveal:false,agent:true});
        const launched = (await domicile.processes.spawn([local.launcher,"--launch"],{stdin:true})).match({Ok:p=>p,Err:()=>undefined});
        if (launched===undefined) return fail("outcome-unknown");
        const collect = async (stream: ReadableStream<Uint8Array>) => {
          const reader=stream.getReader();let text="";
          for(;;){const {done,value}=await reader.read();if(done)return text;text+=new TextDecoder().decode(value);if(text.length>16384)throw Error("Agent-window helper output limit");}
        };
        const output=collect(launched.stdout), errors=collect(launched.stderr);
        launched.write(JSON.stringify(value));launched.closeStdin();
        const timer=setTimeout(()=>launched.kill(),103000);
        let receipt:any;
        try {
          const [text,,exit]=await Promise.all([output,errors,launched.exited]);
          if (!exit.match({Ok:v=>v.code===0&&v.signal===undefined,Err:()=>false})) return fail("outcome-unknown");
          receipt=JSON.parse(text);
        } finally {clearTimeout(timer);}
        const until=Date.now()+12000;
        while(Date.now()<until){
          const matches=domicile.windows.list.filter(w=>typeof receipt.tag==="string"&&w.desktopId.includes(receipt.tag));
          if(matches.length===1){
            const id=appWindowId(matches[0]!.appId), held=workspaceHolding(latest.current.windows,id);
            if(held!==undefined)return write("reply.json",{...base,ok:true,code:"ok",windowId:id,workspace:held.name});
          }
          await new Promise(resolve=>setTimeout(resolve,25));
        }
        return fail("outcome-unknown");
      } catch {await fail("outcome-unknown");}
      finally {latest.current.windows.reserveChat(value.tag,undefined);busy.current=false;}
    };
    void work().catch(()=>console.error("Imagine agent-window request failed"));
    return true;
  });
}
