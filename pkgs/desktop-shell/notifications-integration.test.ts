import {test,expect} from 'bun:test';
import dbus from 'dbus-next';
import {spawn} from 'node:child_process';
import {notificationCommand,followNotifications} from './notifications-client';
import type {NotificationSnapshot} from './notifications';

// Only opt in inside runtime-test + a private dbus-run-session. Pure Nix
// package checks never attach to a caller's session bus.
test.skipIf(process.env.DESKTOP_SHELL_DBUS_TEST!=='1')('real private D-Bus notification lifecycle, signals, IPC and name ownership',async()=>{
 const child=spawn(process.execPath,['main.ts','daemon'],{env:{...process.env,DESKTOP_SHELL_DISABLE_TOASTS:'1'},stdio:['ignore','pipe','pipe']});
 let logs='';child.stderr.on('data',b=>logs+=b);const bus=dbus.sessionBus();
 let unsubscribe=()=>{};
 try{
  const control=await bus.getProxyObject('org.freedesktop.DBus','/org/freedesktop/DBus');const daemon=control.getInterface('org.freedesktop.DBus');
  let owned=false;for(let i=0;i<100;i++){owned=await daemon.NameHasOwner('org.freedesktop.Notifications');if(owned)break;if(child.exitCode!==null)throw new Error(logs);await Bun.sleep(25)}
  expect(owned).toBe(true);
  const proxy=await bus.getProxyObject('org.freedesktop.Notifications','/org/freedesktop/Notifications');const api=proxy.getInterface('org.freedesktop.Notifications');
  expect(await api.GetCapabilities()).toEqual(['actions','body']);
  expect(await api.GetServerInformation()).toEqual(['Desktop shell','Tom','0.1.0','1.2']);
  const closes:number[][]=[],actions:unknown[][]=[];api.on('NotificationClosed',(id,reason)=>closes.push([id,reason]));api.on('ActionInvoked',(id,key)=>actions.push([id,key]));
  let snapshot:NotificationSnapshot|undefined;unsubscribe=followNotifications(s=>snapshot=s);
  const id=await api.Notify('Fixture',0,'','First','Text',['open','Open'],{urgency:new dbus.Variant('y',1)},0);
  expect(await api.Notify('Fixture',id,'','Updated','Text',['open','Open'],{},0)).toBe(id);
  for(let i=0;i<50&&snapshot?.items[0]?.summary!=='Updated';i++)await Bun.sleep(20);
  expect(snapshot?.items[0]?.summary).toBe('Updated');
  await notificationCommand({type:'action',id,key:'open'});
  for(let i=0;i<50&&closes.length===0;i++)await Bun.sleep(20);
  expect(actions).toEqual([[id,'open']]);expect(closes).toEqual([[id,2]]);
  await notificationCommand({type:'dnd',enabled:true});
  for(let i=0;i<50&&!snapshot?.dnd;i++)await Bun.sleep(20);expect(snapshot?.dnd).toBe(true);
  const next=await api.Notify('Fixture',0,'','Dismiss me','',[],{},0);await api.CloseNotification(next);
  for(let i=0;i<50&&closes.length<2;i++)await Bun.sleep(20);expect(closes[1]).toEqual([next,3]);
  const competing=Bun.spawn([process.execPath,'main.ts','daemon'],{env:{...process.env,DESKTOP_SHELL_DISABLE_TOASTS:'1'},stdout:'pipe',stderr:'pipe'});
  expect(await competing.exited).not.toBe(0);expect(await new Response(competing.stderr).text()).toContain('refusing to replace it');
  expect(await daemon.NameHasOwner('org.freedesktop.Notifications')).toBe(true);
 }finally{unsubscribe();bus.disconnect();child.kill('SIGTERM');await new Promise(resolve=>child.once('exit',resolve));}
},10000);
