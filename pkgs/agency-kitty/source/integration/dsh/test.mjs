import assert from 'node:assert/strict';
import test from 'node:test';
import { createTools } from './index.mjs';

const terminalId = 'b53c68a5-70ec-4315-b51f-8d63f2f26ec8';
const row = () => ({version:1,provider:'agency-kitty',host:'nas',terminalId,
  windowClass:'agencykitty-'+terminalId.replaceAll('-',''), directory:'/home/tom/project',title:'Shell',
  chatIds:['chat-a','chat-b'],workspaceId:'workspace-124',status:'active',
  capabilities:{nativeRendering:true,contentIncluded:false,inputAuthority:false}});
const reply = () => ({version:1,provider:'agency-kitty',host:'nas',sessions:[row()]});
const context = () => ({signal:new AbortController().signal});
const tool = execute => createTools({command:'/immutable/bin/agency-kitty'}, execute)[0];

test('returns native identities for multiple linked chats with no mutation authority', async () => {
  const result = await tool(async () => reply()).execute({chatId:'chat-b'}, context());
  assert.equal(result.code,'ok');
  const session = JSON.parse(result.catalogueJson).sessions[0];
  assert.equal(session.terminalId,terminalId);
  assert.equal(session.workspaceId,'workspace-124');
  assert.equal(session.capabilities.inputAuthority,false);
});

test('model arguments cannot change executable or request a command', async () => {
  let executed=false;
  const result=await tool(async()=>{executed=true;return reply();}).execute({command:'/bin/sh'},context());
  assert.equal(result.code,'invalid-arguments');assert.equal(executed,false);
});

test('wrong chat, forged window class, duplicate ids and foreign host fail closed', async () => {
  for(const mutate of [v=>v.sessions[0].chatIds=['other'],v=>v.sessions[0].windowClass='other',
    v=>v.sessions.push(v.sessions[0]),v=>v.sessions[0].host='client']) {
    const value=reply();mutate(value);
    assert.equal((await tool(async()=>value).execute({chatId:'chat-b'},context())).code,'unavailable');
  }
});

test('unavailable or cancelled transport is never reported as an empty catalogue', async () => {
  const value=await tool(async()=>{throw Error('down');}).execute({},context());
  assert.deepEqual(value,{code:'unavailable',catalogueJson:null});
  const c=new AbortController();c.abort();
  assert.equal((await tool(async()=>reply()).execute({}, {signal:c.signal})).code,'cancelled');
});

test('command-looking metadata is stripped and never treated as an action', async () => {
  const value=reply();value.sessions[0].resume={program:'/bin/sh',args:['-c','bad']};
  const result=await tool(async()=>value).execute({},context());
  assert.equal(result.code,'ok');
  assert.equal(Object.hasOwn(JSON.parse(result.catalogueJson).sessions[0],'resume'),false);
});

test('direct terminals preserve mode and cannot claim resumption or an invented OS class', async () => {
  for (const windowClass of [null, 'agencykitty-' + 'a'.repeat(32)]) {
    const value=reply();Object.assign(value.sessions[0], {mode:'direct',resumable:false,resume:null,windowClass});
    const result=await tool(async()=>value).execute({},context());
    assert.equal(result.code,'ok');
    const saved=JSON.parse(result.catalogueJson).sessions[0];
    assert.equal(saved.mode,'direct');assert.equal(saved.resumable,false);assert.equal(saved.windowClass,windowClass);
    value.sessions[0].resumable=true;
    assert.equal((await tool(async()=>value).execute({},context())).code,'unavailable');
  }
});

test('only typed verified foreground agent status can report working', async () => {
  const value=reply();
  value.sessions[0].agentStatus={version:1,harness:'codex',state:'working',foreground:true,verified:true};
  let result=await tool(async()=>value).execute({},context());
  assert.deepEqual(JSON.parse(result.catalogueJson).sessions[0].agentStatus,value.sessions[0].agentStatus);
  for(const mutate of [v=>v.foreground=false,v=>v.verified=false,v=>v.transcript='/PRIVATE',v=>v.state='invented']) {
    const broken=structuredClone(value);mutate(broken.sessions[0].agentStatus);
    result=await tool(async()=>broken).execute({},context());assert.equal(result.code,'unavailable');
  }
  value.sessions[0].agentStatus={version:1,harness:'claude',state:'unverified',foreground:null,verified:false};
  assert.equal((await tool(async()=>value).execute({},context())).code,'ok');
});
