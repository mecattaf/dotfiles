import { useCallback, useEffect, useLayoutEffect, useRef } from "react";
import type { Domicile } from "@domicile-desktop/sdk/desktop/desktop";
import { SystemErrorKind } from "@domicile-desktop/sdk/system";
import type { SnapshotInput } from "./snapshot";
import { parseRequest, REPLY_ROOT, SnapshotController } from "./protocol";
import type { SnapshotConfig } from "./protocol";

const diagnostic=(operation:string,kind?:number)=>console.error("Imagine snapshot failure",{operation,...(kind===undefined?{}:{kind})});

/** Optional privileged hook, driven by Imagine's ONE existing command owner.
 * Return handler accepts onAgency's words after the `imagine` prefix. Call it
 * before unrelated dispatch; true means precisely snapshot-v1 was recognized.
 * No separate command subscription, action callbacks, or process execution.
 */
export function useImagineSnapshot({domicile,config,...input}:SnapshotInput&{domicile:Domicile;config?:SnapshotConfig}) {
  const latest=useRef(input);
  const controller=useRef<SnapshotController|undefined>(undefined);
  const recent=useRef(new Set<string>());
  const writes=useRef(0);
  useLayoutEffect(()=>{
    latest.current=input;
    controller.current?.update({...input,browsers:domicile.browser.windows},domicile.session.locked);
  });
  useEffect(()=>{
    let disposed=false,starting=false;
    const start=async()=>{
      if(starting||controller.current!==undefined||disposed)return;
      starting=true;
      try {
        const local=config??await domicile.files.readText(".config/dsh-domicile/client.json").then(result=>result.match({
          Ok:text=>JSON.parse(text) as SnapshotConfig,
          Err:error=>{if(error.kind!==SystemErrorKind.NotFound)diagnostic("config-read",error.kind);return undefined;},
        }));
        if(disposed||local===undefined)return;
        const current=new SnapshotController(local);
        current.update({...latest.current,browsers:domicile.browser.windows},domicile.session.locked);
        controller.current=current;
      } finally {starting=false;}
    };
    const attempt=()=>{void start().catch(()=>{if(!disposed)diagnostic("configuration");});};
    const stopLock=domicile.session.on("lockchange",()=>{if(domicile.session.locked===false)attempt();});
    attempt();
    return()=>{disposed=true;stopLock();controller.current=undefined;recent.current.clear();};
  },[domicile,config]);
  return useCallback((args:readonly string[]):boolean=>{
    if(args[0]!=="snapshot-v1")return false;
    const request=parseRequest(["imagine",...args]);
    const current=controller.current;
    if(request===undefined){diagnostic("malformed-command");return true;}
    if(current===undefined){diagnostic("not-configured");return true;}
    if(recent.current.has(request.requestId)||writes.current>=4){diagnostic("duplicate-or-busy");return true;}
    recent.current.add(request.requestId);
    if(recent.current.size>128)recent.current.delete(recent.current.values().next().value!);
    current.update({...latest.current,browsers:domicile.browser.windows},domicile.session.locked);
    const reply=current.reply(request,domicile.session.locked);
    const path=`${current.config.replyRoot??REPLY_ROOT}/${request.requestId}/reply.json`;
    writes.current++;
    void domicile.files.write(path,JSON.stringify(reply),{atomic:true})
      .then(result=>result.match({Ok:()=>undefined,Err:error=>diagnostic("reply-write",error.kind)}))
      .catch(()=>diagnostic("reply-write-rejection")).finally(()=>{writes.current--;});
    return true;
  },[domicile]);
}
