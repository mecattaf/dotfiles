import dbus from 'dbus-next';
import {createServer,type Socket} from 'node:net';
import {mkdir,chmod,lstat,unlink} from 'node:fs/promises';
import {dirname} from 'node:path';
import {spawn} from 'node:child_process';
import {NotificationStore,parseNotificationCommand} from './notifications';
import {notificationSocket} from './notifications-client';

export async function serveNotifications(){
  const bus=dbus.sessionBus(); // No Unix FD negotiation; notifications carry no FDs.
  bus.on('error',error=>{console.error('Notification D-Bus failed:',error);process.exit(1)});
  const owner=await bus.requestName('org.freedesktop.Notifications',dbus.NameFlag.DO_NOT_QUEUE);
  if(owner!==dbus.RequestNameReply.PRIMARY_OWNER){bus.disconnect();throw new Error('Another notification daemon owns org.freedesktop.Notifications; refusing to replace it')}
  const clients=new Set<Socket>();
  let stopping=false;
  let toast:ReturnType<typeof spawn>|undefined;
  let toastTimer:ReturnType<typeof setTimeout>|undefined;
  let crashDelay=250;
  function ensureToasts(delay=150){
    if(stopping||toast||toastTimer||process.env.DESKTOP_SHELL_DISABLE_TOASTS==='1'||store.dnd||store.snapshot().items.length===0)return;
    toastTimer=setTimeout(()=>{
      toastTimer=undefined;
      if(stopping||store.dnd||store.snapshot().items.length===0)return;
      const child=spawn(process.env.DESKTOP_SHELL_EXECUTABLE??'desktop-shell',['toasts'],{stdio:['ignore','inherit','inherit']});
      toast=child;
      child.on('error',e=>console.error('Notification popup failed:',e.message));
      child.once('exit',(code,signal)=>{
        toast=undefined;
        if(stopping)return;
        if(code===0&&!signal)crashDelay=250;
        else {console.error(`Notification popup exited: code=${code} signal=${signal}`);crashDelay=Math.min(crashDelay*2,10000)}
        ensureToasts(code===0?30:crashDelay);
      });
      // Spawn failure emits close, not exit.
      child.once('close',()=>{if(toast===child){toast=undefined;crashDelay=Math.min(crashDelay*2,10000);ensureToasts(crashDelay)}});
    },delay);
  }
  const store=new NotificationStore(()=>{
    const message=JSON.stringify({type:'snapshot',snapshot:store.snapshot()})+'\n';
    for(const client of clients){if(client.writableLength>4*1024*1024)client.destroy();else client.write(message)}
    ensureToasts();
  },(id,reason)=>service.NotificationClosed(id,reason),(id,key)=>service.ActionInvoked(id,key));
  class Notifications extends dbus.interface.Interface {
    constructor(){super('org.freedesktop.Notifications')}
    GetCapabilities(){return ['actions','body']}
    GetServerInformation(){return ['Desktop shell','Tom','0.1.0','1.2']}
    Notify(app:string,replacesId:number,_icon:string,summary:string,body:string,actions:string[],hints:Record<string,dbus.Variant>,timeout:number){
      const id=store.notify({app,replacesId,summary,body,actions,urgency:hints.urgency?.value??1,timeout,resident:Boolean(hints.resident?.value),transient:Boolean(hints.transient?.value)});
      return id;
    }
    CloseNotification(id:number){store.close(id,3)}
    NotificationClosed(id:number,reason:number){return [id,reason]}
    ActionInvoked(id:number,key:string){return [id,key]}
  }
  Notifications.configureMembers({methods:{GetCapabilities:{outSignature:'as'},GetServerInformation:{outSignature:'ssss'},Notify:{inSignature:'susssasa{sv}i',outSignature:'u'},CloseNotification:{inSignature:'u'}},signals:{NotificationClosed:{signature:'uu'},ActionInvoked:{signature:'us'}}});
  const service=new Notifications();bus.export('/org/freedesktop/Notifications',service);
  const path=notificationSocket();await mkdir(dirname(path),{recursive:true,mode:0o700});
  const existing=await lstat(path).catch(e=>{if(e.code==='ENOENT')return undefined;throw e});
  // Owning the bus name proves no other instance of this service is running.
  if(existing){if(!existing.isSocket()||existing.uid!==process.getuid!())throw new Error('Unsafe notification socket path');await unlink(path)}
  const server=createServer(client=>{
    let buffer='',subscribed=false;
    client.setTimeout(3000,()=>client.destroy());
    client.on('data',data=>{
      buffer+=data.toString();if(buffer.length>16384){client.destroy();return}
      const lines=buffer.split('\n');buffer=lines.pop()!;
      for(const line of lines){try{
        const command=JSON.parse(line);
        if(command.type==='subscribe'&&!subscribed){subscribed=true;client.setTimeout(0);clients.add(client);client.write(JSON.stringify({type:'snapshot',snapshot:store.snapshot()})+'\n')}
        else {store.command(parseNotificationCommand(command));client.end('{"ok":true}\n')}
      }catch(error){client.end(JSON.stringify({ok:false,error:String(error)})+'\n')}}
    });
    client.on('error',()=>client.destroy());client.on('close',()=>clients.delete(client));
  });
  await new Promise<void>((resolve,reject)=>{server.once('error',reject);server.listen(path,resolve)});await chmod(path,0o600);
  async function shutdown(){if(stopping)return;stopping=true;clearTimeout(toastTimer);toast?.kill('SIGTERM');store.stop();for(const c of clients)c.destroy();server.close();await unlink(path).catch(()=>{});bus.disconnect()}
  process.once('SIGTERM',()=>void shutdown());process.once('SIGINT',()=>void shutdown());
  return shutdown;
}
