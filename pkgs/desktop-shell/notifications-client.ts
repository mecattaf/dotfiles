import {createConnection} from 'node:net';
import {join} from 'node:path';
import type {NotificationSnapshot,NotificationCommand} from './notifications';
export type {NotificationSnapshot,NotificationCommand,ShellNotification} from './notifications';
export function notificationSocket(){
  const root=process.env.XDG_RUNTIME_DIR;
  if(!root)throw new Error('XDG_RUNTIME_DIR is required');
  return join(root,'desktop-shell','notifications.sock');
}
export function followNotifications(changed:(snapshot:NotificationSnapshot)=>void):()=>void {
  let stopped=false,timer:ReturnType<typeof setTimeout>|undefined,delay=250;
  let socket:ReturnType<typeof createConnection>|undefined;
  let last:NotificationSnapshot={connected:false,error:'Connecting to notifications…',dnd:false,items:[],history:[]};
  const connect=()=>{
    let buffer='';socket=createConnection(notificationSocket());
    // A socket can accept connections while its owner never sends a snapshot.
    // Reconnect instead of leaving every shell view permanently "connecting".
    socket.setTimeout(3000,()=>socket?.destroy(new Error('Notification service did not provide a snapshot')));
    socket.on('connect',()=>{delay=250;socket!.write('{"type":"subscribe"}\n')});
    socket.on('data',data=>{
      buffer+=data.toString();if(buffer.length>4*1024*1024){socket!.destroy(new Error('Notification snapshot too large'));return}
      const lines=buffer.split('\n');buffer=lines.pop()!;
      for(const line of lines){try{const message=JSON.parse(line);if(message.type==='snapshot'){
        const value=message.snapshot;
        if(!value||value.connected!==true||typeof value.error!=='string'||typeof value.dnd!=='boolean'||!Array.isArray(value.items)||!Array.isArray(value.history))throw new Error('Invalid notification snapshot');
        socket!.setTimeout(0);last=value;changed(last)
      }}catch{socket!.destroy(new Error('Invalid notification snapshot'));}}
    });
    socket.on('error',e=>changed({...last,connected:false,error:e.message}));
    socket.on('close',()=>{if(!stopped){changed({...last,connected:false,error:'Notification service disconnected'});timer=setTimeout(connect,delay);delay=Math.min(delay*2,10000)}});
  };
  connect();return()=>{stopped=true;clearTimeout(timer);socket?.destroy()};
}
export function notificationCommand(command:NotificationCommand):Promise<void>{
  return new Promise((resolve,reject)=>{
    const socket=createConnection(notificationSocket());let buffer='',settled=false;
    const finish=(error?:Error)=>{if(settled)return;settled=true;socket.destroy();error?reject(error):resolve()};
    socket.setTimeout(3000,()=>finish(new Error('Notification service timed out')));
    socket.once('connect',()=>socket.write(JSON.stringify(command)+'\n'));
    socket.on('data',data=>{buffer+=data.toString();if(buffer.length>65536){finish(new Error('Invalid notification response'));return}if(buffer.includes('\n')){try{const reply=JSON.parse(buffer.split('\n')[0]!);finish(reply.ok?undefined:new Error(reply.error||'Notification command failed'))}catch{finish(new Error('Invalid notification response'))}}});
    socket.once('error',finish);socket.once('end',()=>{if(!settled)finish(new Error('Notification service closed without acknowledging'))});
  });
}
