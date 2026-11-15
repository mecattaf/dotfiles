import assert from 'node:assert/strict';
import test from 'node:test';
import { getBuiltinModels } from '@earendil-works/pi-ai/providers/all';
import { streamSimple } from '@earendil-works/pi-ai/api/openai-completions';
import { apply, freePayload, guardedOptions } from './index.mjs';

const id = 'nvidia/nemotron-3.5-lightning:free';
const model = getBuiltinModels('openrouter').find(candidate => candidate.id === id);

test('last payload hook forces all zero price dimensions after earlier hooks', async () => {
  const options = guardedOptions({ onPayload: payload => ({ ...payload,
    provider: { allow_fallbacks: true, max_price: { prompt: 999 } }, usage: { include: false },
  }) }, [id]);
  const payload = await options.onPayload({ model: id }, model);
  assert.deepEqual(payload.provider, {
    allow_fallbacks: false, max_price: { prompt: 0, completion: 0, request: 0, image: 0 },
  });
  assert.deepEqual(payload.usage, { include: true });
});

test('paid, unselected and fallback-array requests are refused', () => {
  assert.throws(() => freePayload({ model: 'paid' }, { id: 'paid' }, ['paid']), /:free/);
  assert.throws(() => freePayload({ model: id }, model, []), /:free/);
  assert.throws(() => freePayload({ model: 'other:free' }, model, [id]), /:free/);
  assert.throws(() => freePayload({ model: id, models: [id, 'paid'] }, model, [id]), /fallback array/);
});

test('native SDK sends the guarded request and preserves response usage', async () => {
  const requests = [];
  const fetch = async (_url, options) => {
    requests.push(JSON.parse(options.body));
    const chunks = [
      { id: 'fixture', choices: [{ index: 0, delta: { role: 'assistant', content: 'verified' }, finish_reason: null }] },
      { id: 'fixture', choices: [{ index: 0, delta: {}, finish_reason: 'stop' }], usage: { prompt_tokens: 7, completion_tokens: 2, total_tokens: 9 } },
    ];
    return new Response(chunks.map(chunk => `data: ${JSON.stringify(chunk)}\n\n`).join('') + 'data: [DONE]\n\n',
      { headers: { 'content-type': 'text/event-stream' } });
  };
  const events = [];
  for await (const event of streamSimple(model, { messages: [{ role: 'user', content: 'fixture', timestamp: 0 }] },
    guardedOptions({ apiKey: 'synthetic-local-only', fetch, maxTokens: 16 }, [id]))) events.push(event);
  assert.equal(requests.length, 1);
  assert.equal(requests[0].model, id);
  assert.equal(requests[0].provider.allow_fallbacks, false);
  assert.deepEqual(requests[0].provider.max_price, { prompt: 0, completion: 0, request: 0, image: 0 });
  const done = events.find(event => event.type === 'done');
  assert.ok(done, JSON.stringify(events));
  assert.equal(done.message.usage.totalTokens, 9);
});

test('bad last-hook model cannot reach native HTTP transport', async () => {
  let calls = 0;
  const events = [];
  for await (const event of streamSimple(model, { messages: [{ role: 'user', content: 'fixture', timestamp: 0 }] },
    guardedOptions({ apiKey: 'synthetic-local-only', fetch: async () => { calls++; throw Error('unexpected HTTP'); },
      onPayload: payload => ({ ...payload, model: 'paid' }) }, [id]))) events.push(event);
  assert.equal(calls, 0);
  assert.ok(events.some(event => event.type === 'error'));
});

test('plugin registers the native adapter and refuses a missing credential', async () => {
  let adapter;
  const ctx = {
    credentials: { resolve: async () => undefined }, get: () => undefined,
    llm: { registerAdapter: (routes, value) => { assert.deepEqual(routes, ['openrouter-free']); adapter = value; return () => {}; } },
    effect: fn => fn(),
  };
  apply(ctx, { models: [id] });
  assert.ok(adapter);
  await assert.rejects(async () => { for await (const _ of adapter.stream({ provider: 'openrouter-free', model: id, messages: [], signal: new AbortController().signal })) {} }, /no configured native credential/);
});
