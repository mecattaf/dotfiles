import assert from 'node:assert/strict';
import { realpath } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';

const [install, generation, mode, controls] = process.argv.slice(2);
const nativeFetch = globalThis.fetch;
globalThis.fetch = (input, init) => {
  const url = new URL(typeof input === 'string' || input instanceof URL ? input : input.url);
  assert.ok(['127.0.0.1', '[::1]'].includes(url.hostname), `external HTTP denied: ${url.origin}`);
  return nativeFetch(input, init);
};
const { runProfile } = await import(pathToFileURL(`${install}/lib/profile-boot.js`).href);
const { loadLayeredEnv } = await import(pathToFileURL(`${install}/node_modules/@deepseek-ai/dsh-app-boot/lib/index.js`).href);
const patches = mode === 'new' ? [`${generation}/floor.patch.yml`, controls] : [controls];
const { ctx, shutdown } = await runProfile({ profile: 'master',
  environment: loadLayeredEnv('master-runtime-smoke', process.cwd()), patchFiles: patches, args: ['--no-open'] });
const rows = () => [...ctx.loader.entries()].filter(row => /dsh-superagent(?:-(?:scheduled|workflow))?(?:-runtime)?$/.test(row.options.id))
  .map(row => ({ id: row.options.id, name: row.options.name, disabled: row.options.disabled, state: row.fiber?.state }));
let reloads = 0;
ctx.on('app-boot/config-reload', () => { reloads++; });
let api;
if (mode === 'new') {
  assert.ok(ctx.orchestrator, 'the real v7 Runtime must be instantiated');
  await ctx.orchestrator.ready;
  const before = ctx.orchestrator.store.settings();
  ctx.orchestrator.store.saveSettings({ ...before, paused: true, eval: { ...before.eval, mode: 'off' } });
  const origin = ctx.webServer.getOrigin();
  const get = async path => {
    const response = await fetch(`${origin}/orchestrator/api/${path}`, { headers: { 'x-orchestrator-request': '1', origin } });
    assert.equal(response.status, 200, `${path}: ${await response.clone().text()}`);
    return response.json();
  };
  const state = await get('state');
  const settings = await get('settings');
  const models = await get('models');
  const pairs = Object.keys(ctx.orchestrator.machine.dshd.pairs).sort();
  const routes = Object.fromEntries(pairs.map(name => {
    const pair = ctx.orchestrator.machine.dshd.pairs[name];
    return [name, { profile: pair.profile, provider: pair.provider, model: pair.model, effort: pair.effort, maxWorkers: pair.maxWorkers }];
  }));
  const sourceKinds = ['scheduled', 'workflow'].map(name => ({ name, registered: !!ctx.orchestrator.sources.kind(name) }));
  assert.ok(sourceKinds.every(row => row.registered), 'both actual v7 Sources must register');
  assert.equal(ctx.orchestrator.store.settings().eval.mode, 'off');
  assert.equal(ctx.runtimeSmoke.calls, 0, 'startup and API reads must never send a model prompt');
  assert.deepEqual(ctx.llm.listProviders().map(row => row.id), ['runtime-trap']);
  api = { stateAvailable: !!state.masterId, settingsAvailable: !!settings, modelsAvailable: !!models,
    evalMode: 'off', pairs, routes, sourceKinds, promptCalls: ctx.runtimeSmoke.calls };
}
// The native watcher performs its initial no-op reconciliation after boot.
// Observe that baseline before measuring changes from the concurrent launch.
await new Promise(resolve => setTimeout(resolve, 2600));
const baselineReloads = reloads;
process.send({ event: 'ready', pid: process.pid, mode, rows: rows(), api, baselineReloads });
process.on('message', async message => {
  if (message.kind === 'inspect') {
    const old = `${process.env.DSH_HOME}/profiles/master/node_modules/dsh-superagent/lib/workflow.js`;
    const target = mode === 'new' ? `${generation}/node_modules/dsh-superagent/lib/workflow.js` : old;
    const lazy = await import(pathToFileURL(target).href);
    assert.equal(lazy.name, 'dsh-superagent-workflow');
    process.send({ id: message.id, pid: process.pid, mode, rows: rows(), lazyUrl: pathToFileURL(await realpath(target)).href,
      promptCalls: ctx.runtimeSmoke.calls, reloads: reloads - baselineReloads, pairs: mode === 'new' ? Object.keys(ctx.orchestrator.machine.dshd.pairs).sort() : undefined });
  } else if (message.kind === 'stop') {
    await shutdown.shutdown(0);
    process.disconnect();
  }
});
