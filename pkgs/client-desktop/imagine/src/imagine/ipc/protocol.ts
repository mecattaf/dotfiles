import { projectSnapshot } from "./snapshot";
import type { Snapshot, SnapshotInput } from "./snapshot";

export const PROTOCOL = "agency.domicile.snapshot";
export const VERSION = 1;
export const REPLY_ROOT = ".local/state/dsh-domicile/replies";
export type SnapshotConfig = {desktopId:string;imagineSource:string;sdkSource:string;replyRoot?:string};
export type Request = {requestId:string;desktopId:string;expected?:{epoch:string;revision:number}};
export function parseRequest(args:readonly string[]):Request|undefined {
  if(args.length!==6||args[0]!=="imagine"||args[1]!=="snapshot-v1"||!/^[a-f0-9]{32}$/.test(args[2]!)||!/^[a-z][a-z0-9-]{0,63}$/.test(args[3]!))return;
  const base={requestId:args[2]!,desktopId:args[3]!};
  if(args[4]==="-"&&args[5]==="-")return base;
  if(!/^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/.test(args[4]!)||!/^\d{1,15}$/.test(args[5]!))return;
  return {...base,expected:{epoch:args[4]!,revision:Number(args[5])}};
}
export class SnapshotController {
  readonly epoch:string;
  private revision=0;
  private signature="";
  private snapshot:Snapshot|undefined;
  private locked=true;
  constructor(readonly config:SnapshotConfig,epoch=crypto.randomUUID()) {
    if(!/^[a-z][a-z0-9-]{0,63}$/.test(config.desktopId)||typeof config.imagineSource!=="string"||!config.imagineSource||typeof config.sdkSource!=="string"||!/^[a-f0-9]{40}$/.test(config.sdkSource))throw Error("invalid snapshot identity");
    this.epoch=epoch;
  }
  update(input:SnapshotInput,locked:boolean|undefined) {
    const snapshot=locked===false?projectSnapshot(input):undefined;
    const signature=JSON.stringify({locked:locked!==false,snapshot});
    if(signature!==this.signature){this.signature=signature;this.revision++;this.snapshot=snapshot;this.locked=locked!==false;}
  }
  reply(request:Request,currentlyLocked:boolean|undefined) {
    const common={protocol:PROTOCOL,version:VERSION,requestId:request.requestId,desktopId:this.config.desktopId,epoch:this.epoch,revision:this.revision,capturedAt:new Date().toISOString(),source:{shell:"Imagine",adapter:"0.1.0",imagine:this.config.imagineSource,sdk:this.config.sdkSource}};
    const error=(code:string)=>({...common,ok:false as const,error:{code}});
    if(request.desktopId!==this.config.desktopId)return error("wrong-desktop");
    if(this.locked||currentlyLocked!==false)return error("locked-or-unavailable");
    if(request.expected?.epoch!==undefined&&request.expected.epoch!==this.epoch)return error("epoch-changed");
    if(request.expected?.revision!==undefined&&request.expected.revision!==this.revision)return error("stale-revision");
    if(this.snapshot===undefined)return error("not-ready");
    return {...common,ok:true as const,snapshot:this.snapshot};
  }
}
