// Opt-in proof against actual installed old/v7 packages; no provider credentials.
// Invoke under runtime-test, preferably on compute. Four explicit paths only.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import { copyFile, cp, mkdir, readFile, realpath, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const [build, generation, oldModules, root] = process.argv.slice(2);
if (![build, generation, oldModules, root].every(path => path?.startsWith('/'))) throw new Error('build, generation, old node_modules, private proof root must be absolute');
const manifest = JSON.parse(await readFile(join(build, 'manifest.json'), 'utf8'));
const install = process.env.DSH_SMOKE_INSTALL || join(dirname(dirname(await realpath(manifest.dsh))), 'lib/node_modules/@deepseek-ai/dsh');
const home = join(root, 'dsh');
const profile = join(home, 'profiles/master');
await mkdir(profile, { recursive: true });
await mkdir(join(root, 'home'), { recursive: true });
await copyFile(join(build, 'profiles/master/package.json'), join(profile, 'package.json'));
await copyFile(join(build, 'profiles/master/cordis.patch.yml'), join(profile, 'cordis.patch.yml'));
await cp(oldModules, join(profile, 'node_modules'), { recursive: true, dereference: false });
const originalPatch = await readFile(join(profile, 'cordis.patch.yml'));
const originalPackage = await readFile(join(profile, 'package.json'));
const oldMain = join(profile, 'node_modules/dsh-superagent/lib/index.js');
const oldBytes = await readFile(oldMain);
const trap = join(root, 'trap.mjs');
await writeFile(trap, `import { LlmAdapter } from ${JSON.stringify(pathToFileURL(join(install, 'node_modules/@deepseek-ai/dsh-llm/lib/index.js')).href)};\nexport const name='runtime-smoke-trap'; export const inject=['llm'];\nexport function apply(ctx) { const counter={calls:0}; ctx.provide('runtimeSmoke',counter); class Trap extends LlmAdapter { providerInfo(id){return{id,name:'Local smoke trap'}} async listModels(){return[{id:'never-call',name:'Never call',contextWindow:8192,maxOutputTokens:64}]} async *stream(){counter.calls++; throw new Error('Unexpected model prompt in smoke')} } ctx.effect(()=>ctx.llm.registerAdapter(['runtime-trap'],new Trap())); }\n`);
const deniedDshd = join(root, 'never-dshd');
await writeFile(deniedDshd, '#!/bin/sh\necho "unexpected dshd launch" >&2\nexit 99\n', { mode: 0o700 });
const rows = manifest.profiles.master.expect;
const original = rows.find(row => row.id === 'dsh-superagent').config;
const expectedPairs = Object.keys(original.dshd.pairs).sort();
const common = [
  ...['llm-claude', 'llm-pi-ai', 'llm-deepseek-api-key', 'llm-deepseek-account', 'deepseek-account', 'session-title-llm', 'otel', 'session-telemetry-otel'].map(id => ({ id, disabled: true })),
  { id: 'agent-default-model', config: { provider: 'runtime-trap', model: 'never-call' } },
  { id: 'webserver', config: { host: '127.0.0.1', port: 0 } },
  { insert: [{ id: 'runtime-smoke-trap', name: trap }] },
];
const oldControl = join(root, 'old.patch.yml');
await writeFile(oldControl, JSON.stringify([...common,
  { id: 'dsh-superagent', disabled: false, config: { ...original, engine: false, stateDir: join(root, 'old-state') } },
  { id: 'dsh-superagent-scheduled', disabled: true }, { id: 'dsh-superagent-workflow', disabled: true },
]));
const newControl = join(root, 'new.patch.yml');
await writeFile(newControl, JSON.stringify([...common,
  { id: 'dsh-superagent-runtime', config: { ...original, engine: true, stateDir: join(root, 'new-state'), dshd: { ...original.dshd, command: deniedDshd, cwd: root, env: {} } } },
]));
const children = [];
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
async function boot(mode, controls) {
  const child = spawn(process.execPath, ['--expose-internals', join(dirname(fileURLToPath(import.meta.url)), 'runtime-smoke-child.mjs'), install, generation, mode, controls], {
    cwd: root,
    env: { HOME: join(root, 'home'), DSH_HOME: home, PATH: `${dirname(process.execPath)}:/run/current-system/sw/bin:/usr/bin:/bin`, DSH_TELEMETRY_DISABLED: '1', DSH_PERMISSION_MODE: 'workspace-write' },
    stdio: ['ignore', 'pipe', 'pipe', 'ipc'],
  });
  children.push(child);
  let log = '';
  const safeLog = () => log.replace(/([?&]token=)[^\s]+/g, '$1[redacted]');
  child.stdout.on('data', bytes => { log += bytes; });
  child.stderr.on('data', bytes => { log += bytes; });
  child.once('close', () => { void writeFile(join(root, `${mode}.log`), safeLog()); });
  let id = 0;
  const wait = match => new Promise((resolve, reject) => {
    const timer = setTimeout(() => { clear(); reject(new Error(`${mode} timeout: ${safeLog().slice(-12000)}`)); }, 45000);
    const receive = message => { if (match(message)) { clear(); resolve(message); } };
    const closed = code => { clear(); reject(new Error(`${mode} exited ${code}: ${safeLog().slice(-12000)}`)); };
    const clear = () => { clearTimeout(timer); child.off('message', receive); child.off('close', closed); };
    child.on('message', receive); child.once('close', closed);
  });
  const ready = await wait(message => message.event === 'ready');
  return { ready, ask: async () => { const request = ++id; const promise = wait(message => message.id === request); child.send({ kind: 'inspect', id: request }); return promise; } };
}
try {
  const old = await boot('old', oldControl);
  const current = await boot('new', newControl);
  assert.deepEqual(current.ready.api.pairs, expectedPairs);
  for (const name of expectedPairs) {
    const expected = original.dshd.pairs[name];
    for (const key of ['profile', 'provider', 'model', 'effort', 'maxWorkers']) assert.equal(current.ready.api.routes[name][key], expected[key], `${name}.${key}`);
  }
  assert.equal(Object.keys(manifest.profiles).length, expectedPairs.length + 1, 'one native Master plus its pair profiles');
  await delay(3000);
  const oldLater = await old.ask();
  const newLater = await current.ask();
  assert.equal(oldLater.pid, old.ready.pid);
  assert.equal(newLater.pid, current.ready.pid);
  assert.equal(oldLater.promptCalls, 0);
  assert.equal(newLater.promptCalls, 0);
  assert.equal(oldLater.reloads, 0);
  assert.equal(newLater.reloads, 0);
  assert.deepEqual(oldLater.rows, old.ready.rows);
  assert.deepEqual(newLater.rows, current.ready.rows);
  assert.ok(oldLater.lazyUrl.startsWith(pathToFileURL(join(profile, 'node_modules')).href));
  assert.ok(newLater.lazyUrl.startsWith(pathToFileURL(generation).href));
  assert.deepEqual(await readFile(join(profile, 'cordis.patch.yml')), originalPatch);
  assert.deepEqual(await readFile(join(profile, 'package.json')), originalPackage);
  assert.deepEqual(await readFile(oldMain), oldBytes);
  const result = { passed: true, nativeDsh: install, api: current.ready.api,
    old: oldLater, current: newLater, unchangedCanonicalBytes: true,
    oldMainSha256: createHash('sha256').update(oldBytes).digest('hex') };
  await writeFile(join(root, 'result.json'), JSON.stringify(result, null, 2));
  console.log(JSON.stringify(result));
} finally {
  for (const child of children) if (child.connected) child.send({ kind: 'stop' });
  await delay(500);
  for (const child of children) if (child.exitCode === null) child.kill('SIGTERM');
}
