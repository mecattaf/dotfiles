import { spawn } from 'node:child_process';
import { isAbsolute } from 'node:path';

export const name = 'agency-kitty-native';
export const inject = ['tools'];
const uuid = /^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/;
const chat = /^[A-Za-z0-9_-]{1,128}$/;
const MAX_OUTPUT = 4 * 1024 * 1024;
const record = v => v && typeof v === 'object' && !Array.isArray(v);

function validRoute(row) {
  const direct = row?.mode === 'direct';
  const windowClass = direct ? row.windowClass === null || /^agencykitty-[a-f0-9]{32}$/.test(row.windowClass) :
    row?.windowClass === `agencykitty-${row?.terminalId?.replaceAll('-', '')}`;
  return record(row) && row.version === 1 && row.provider === 'agency-kitty' && row.host === 'nas' &&
    uuid.test(row.terminalId) && windowClass &&
    (row.mode === undefined || ['direct', 'persistent'].includes(row.mode)) &&
    (row.resumable === undefined || typeof row.resumable === 'boolean') &&
    (!direct || row.resumable === false && row.resume === null) &&
    (row.kittyWindowId === undefined || row.kittyWindowId === null || Number.isSafeInteger(row.kittyWindowId) && row.kittyWindowId > 0 && row.kittyWindowId < 2**31) &&
    typeof row.directory === 'string' && row.directory.startsWith('/') && !/[\x00-\x1f\x7f]/.test(row.directory) &&
    typeof row.title === 'string' && row.title.length <= 256 && !/[\x00-\x1f\x7f]/.test(row.title) &&
    Array.isArray(row.chatIds) && row.chatIds.length <= 128 && row.chatIds.every(id => typeof id === 'string' && chat.test(id)) &&
    (row.workspaceId === null || typeof row.workspaceId === 'string' && row.workspaceId.length <= 128 && !/[\x00-\x1f\x7f]/.test(row.workspaceId)) &&
    row.capabilities?.nativeRendering === true && row.capabilities?.contentIncluded === false && row.capabilities?.inputAuthority === false;
}

function validateReply(value, args) {
  if (!record(value) || value.version !== 1 || value.provider !== 'agency-kitty' || value.host !== 'nas' ||
      !Array.isArray(value.sessions) || value.sessions.length > 4096 || !value.sessions.every(validRoute)) throw Error('invalid native terminal catalogue');
  const ids = value.sessions.map(v => v.terminalId);
  if (new Set(ids).size !== ids.length) throw Error('duplicate native terminal id');
  if (args.chatId && value.sessions.some(v => !v.chatIds.includes(args.chatId))) throw Error('wrong chat catalogue');
  if (args.terminalId && value.sessions.some(v => v.terminalId !== args.terminalId)) throw Error('wrong terminal catalogue');
  // Do not execute, render as HTML, or trust command-looking fields from disk.
  return {version:1, provider:'agency-kitty', host:'nas', sessions:value.sessions.map(v => ({
    terminalId:v.terminalId, title:v.title, directory:v.directory, chatIds:v.chatIds,
    workspaceId:v.workspaceId, windowClass:v.windowClass, status:v.status, liveness:v.liveness ?? 'unverified',
    mode:v.mode ?? 'persistent', resumable:v.resumable ?? true,
    kittyWindowId:v.kittyWindowId ?? null,
    capabilities:{nativeRendering:true,contentIncluded:false,inputAuthority:false},
  }))};
}

function execute(command, args, signal) {
  return new Promise((resolve, reject) => {
    const argv = ['catalogue', '--local', '--json'];
    if (args.chatId) argv.push('--chat-id', args.chatId);
    if (args.terminalId) argv.push('--session-id', args.terminalId);
    const child = spawn(command, argv, {stdio:['ignore','pipe','ignore'], signal});
    const chunks = []; let bytes = 0; let settled = false;
    const fail = error => { if (settled) return; settled = true; child.kill(); reject(error); };
    const timer = setTimeout(() => fail(Error('native catalogue timeout')), 5000);
    child.stdout.on('data', chunk => {
      bytes += chunk.length;
      if (bytes > MAX_OUTPUT) fail(Error('native catalogue too large'));
      else chunks.push(chunk);
    });
    child.on('error', error => { clearTimeout(timer); fail(error); });
    child.on('close', code => {
      clearTimeout(timer);
      if (settled) return;
      settled = true;
      if (code !== 0) return reject(Error('native catalogue unavailable'));
      try { resolve(JSON.parse(Buffer.concat(chunks).toString('utf8'))); }
      catch { reject(Error('invalid native catalogue JSON')); }
    });
  });
}

export function createTools(config, run = execute) {
  if (!record(config) || typeof config.command !== 'string' || !isAbsolute(config.command) || /[\x00-\x1f\x7f]/.test(config.command))
    throw Error('kitty-native requires an installed absolute command');
  const command = config.command;
  return [{
    name:'kitty_native_sessions',
    description:'Read native Kitty terminal identities linked to DSH chats and Imagine workspaces on NAS. Metadata only, no screen or transcript content. Chat, terminal and desktop identities are distinct. This does not type, allocate, close, launch or move a window. An unavailable catalogue is not an empty desktop.',
    parameters:{type:'object',additionalProperties:false,properties:{chatId:{type:'string'},terminalId:{type:'string'}}},
    timeoutMs:6000,
    output:{schema:{type:'object',additionalProperties:false,required:['code','catalogueJson'],properties:{code:{type:'string',enum:['ok','invalid-arguments','unavailable','cancelled']},catalogueJson:{oneOf:[{type:'string'},{type:'null'}]}}},
      render:(_args,value) => [{type:'text',text:value.code === 'ok' ? value.catalogueJson : JSON.stringify({ok:false,code:value.code})}]},
    presentCall:() => ({card:'generic',title:'Read native Kitty sessions',kind:'read'}),
    async execute(args, context) {
      if (!record(args) || Object.keys(args).some(k => !['chatId','terminalId'].includes(k)) ||
          args.chatId !== undefined && (typeof args.chatId !== 'string' || !chat.test(args.chatId)) ||
          args.terminalId !== undefined && (typeof args.terminalId !== 'string' || !uuid.test(args.terminalId)))
        return {code:'invalid-arguments',catalogueJson:null};
      if (context.signal.aborted) return {code:'cancelled',catalogueJson:null};
      try {
        const result = validateReply(await run(command, args, context.signal), args);
        if (context.signal.aborted) return {code:'cancelled',catalogueJson:null};
        return {code:'ok',catalogueJson:JSON.stringify(result)};
      } catch { return {code:context.signal.aborted ? 'cancelled' : 'unavailable',catalogueJson:null}; }
    },
  }];
}

export function apply(ctx, config) {
  for (const tool of createTools(config))
    ctx.effect(() => ctx.tools.register(tool), `kitty-native: ${tool.name}`);
}
