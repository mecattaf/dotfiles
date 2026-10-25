export interface ShellNotification {
  id: number; app: string; summary: string; body: string;
  urgency: 0 | 1 | 2; actions: {key: string; label: string}[]; createdAt: number;
}
export interface NotificationSnapshot {
  connected: boolean; error: string; dnd: boolean;
  items: ShellNotification[]; history: ShellNotification[];
}
export type NotificationCommand = {type:'dismiss';id:number}|{type:'dismiss-latest'}|{type:'action';id:number;key:string}|{type:'dnd';enabled:boolean}|{type:'clear'};
export interface NotificationInput {
  app: string; replacesId: number; summary: string; body: string;
  actions: string[]; urgency: number; timeout: number; resident: boolean; transient: boolean;
}
type Entry = {item:ShellNotification;resident:boolean;transient:boolean;timer?:ReturnType<typeof setTimeout>};
export class NotificationStore {
  private active = new Map<number,Entry>();
  private history: ShellNotification[] = [];
  private nextId = 1;
  dnd = false;
  constructor(private changed:()=>void, private closed:(id:number,reason:number)=>void,
    private invoked:(id:number,key:string)=>void, private now=Date.now) {}
  snapshot():NotificationSnapshot {
    return {connected:true,error:'',dnd:this.dnd,items:[...this.active.values()].map(e=>e.item).reverse(),history:[...this.history]};
  }
  notify(input:NotificationInput) {
    const old=this.active.get(input.replacesId);
    if(old)clearTimeout(old.timer);
    let id=old?.item.id;
    if(!id){do{id=this.nextId++;if(this.nextId>0xffffffff)this.nextId=1}while(this.active.has(id))}
    const actions:ShellNotification['actions']=[];
    // Action keys are opaque sender tokens. Never truncate a key and then
    // signal a different token back to the application.
    for(let i=0;i+1<input.actions.length&&i<32;i+=2){
      const key=input.actions[i]!;
      if(key.length<=256&&!actions.some(a=>a.key===key))actions.push({key,label:input.actions[i+1]!.slice(0,256)});
    }
    const item:ShellNotification={id,app:input.app.slice(0,256),summary:input.summary.slice(0,1024),body:input.body.slice(0,8192),actions,urgency:input.urgency===2?2:input.urgency===0?0:1,createdAt:this.now()};
    const entry:Entry={item,resident:input.resident,transient:input.transient};
    // A replacement is the newest notification too: Map.set alone leaves its
    // old insertion position, causing dismiss-latest to target the wrong item.
    this.active.delete(id);
    this.active.set(id,entry);
    // A bounded store prevents a sender from exhausting the shell indefinitely.
    while(this.active.size>100)this.close(this.active.keys().next().value!,4);
    const timeout=item.urgency===2?0:input.timeout<0?6000:Math.min(input.timeout,2_147_483_647);
    if(timeout>0)entry.timer=setTimeout(()=>this.close(id!,1),timeout);
    this.history=this.history.filter(e=>e.id!==id);
    if(!input.transient)this.history.unshift(item);
    this.history=this.history.slice(0,100);
    this.changed();return id;
  }
  close(id:number,reason:number) {
    const entry=this.active.get(id);if(!entry)return;
    clearTimeout(entry.timer);this.active.delete(id);this.closed(id,reason);this.changed();
  }
  command(command:NotificationCommand) {
    if(command.type==='dismiss-latest'){const id=[...this.active.keys()].at(-1);if(id)this.close(id,2)}
    else if(command.type==='dismiss')this.close(command.id,2);
    else if(command.type==='action'){
      const entry=this.active.get(command.id);
      if(!entry||!entry.item.actions.some(a=>a.key===command.key))throw new Error('Notification action is no longer available');
      this.invoked(command.id,command.key);
      if(!entry.resident)this.close(command.id,2);
    } else if(command.type==='dnd'){this.dnd=command.enabled;this.changed()}
    else if(command.type==='clear'){
      for(const id of [...this.active.keys()])this.close(id,2);
      this.history=[];this.changed();
    }
  }
  stop(){for(const e of this.active.values())clearTimeout(e.timer);this.active.clear()}
}
export function parseNotificationCommand(value:unknown):NotificationCommand {
  if(!value||typeof value!=='object')throw new Error('Invalid notification command');
  const c=value as Record<string,unknown>;
  if(c.type==='clear')return {type:'clear'};
  if(c.type==='dismiss-latest')return {type:'dismiss-latest'};
  if(c.type==='dnd'&&typeof c.enabled==='boolean')return {type:'dnd',enabled:c.enabled};
  if((c.type==='dismiss'||c.type==='action')&&typeof c.id==='number'&&Number.isSafeInteger(c.id)&&c.id>0&&c.id<=0xffffffff){
    if(c.type==='dismiss')return {type:'dismiss',id:c.id};
    if(typeof c.key==='string'&&c.key.length<=256)return {type:'action',id:c.id,key:c.key};
  }
  throw new Error('Invalid notification command');
}
