import {test,expect} from 'bun:test';
import {createServer} from 'node:net';
import {mkdtemp,mkdir,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {followNotifications} from './notifications-client';

test('an accepting notification socket without snapshots times out and reconnects',async()=>{
  const root=await mkdtemp(join(tmpdir(),'desktop-notification-client-'));
  const previous=process.env.XDG_RUNTIME_DIR;
  process.env.XDG_RUNTIME_DIR=root;
  await mkdir(join(root,'desktop-shell'));
  let attempts=0;
  const connections=new Set<import('node:net').Socket>();
  const server=createServer(socket=>{attempts++;connections.add(socket);socket.on('data',()=>{});socket.on('close',()=>connections.delete(socket));});
  await new Promise<void>(resolve=>server.listen(join(root,'desktop-shell','notifications.sock'),resolve));
  const errors:string[]=[];
  const stop=followNotifications(snapshot=>{if(!snapshot.connected)errors.push(snapshot.error)});
  try{
    const deadline=Date.now()+4500;
    while(attempts<2&&Date.now()<deadline)await Bun.sleep(25);
    expect(attempts).toBeGreaterThanOrEqual(2);
    expect(errors.some(error=>error.includes('did not provide a snapshot'))).toBe(true);
  }finally{
    stop();for(const socket of connections)socket.destroy();
    await new Promise<void>(resolve=>server.close(()=>resolve()));
    if(previous===undefined)delete process.env.XDG_RUNTIME_DIR;else process.env.XDG_RUNTIME_DIR=previous;
    await rm(root,{recursive:true,force:true});
  }
},6000);
