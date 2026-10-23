// Unit test for index.js with fake exec objects; no dsh, no herdr.
import test from 'node:test'
import assert from 'node:assert/strict'
import { apply, decide } from './index.js'

const allow = async () => ({ kind: 'allow' })
const call = (tool, args) => ({ name: `_dsh_herdr_${tool}`, arguments: args })
const inPane = { HERDR_ENV: '1' }

function mount() {
  const on = {}
  const provided = {}
  apply({
    on(event, listener) { on[event] = listener },
    provide(name, value) { provided[name] = value },
  })
  return { on, provided }
}

test('a foreign pane_run or agent_start is denied, inside Herdr too', () => {
  const owned = new Set()
  assert.equal(decide(call('pane_run', { pane: 'w1:p1', command: 'ls' }), owned, inPane).kind, 'deny')
  assert.equal(decide(call('agent_start', { name: 'r', kind: 'codex', pane: 'w1:p1' }), owned, inPane).kind, 'deny')
})

test('a malformed id is denied, reads included', () => {
  const owned = new Set()
  for (const pane of ['--current', 'w1:p1 x', 'w1', 'p1', 'w1:p1\n', 'wI:p1', 7]) {
    assert.equal(decide(call('pane_read', { pane }), owned, inPane).kind, 'deny', String(pane))
  }
  assert.equal(decide(call('tab_get', { tab: 'w1:p1' }), owned, inPane).kind, 'deny')
  assert.equal(decide(call('agent_read', { agent: '--help' }), owned, inPane).kind, 'deny')
  assert.equal(decide(call('workspace_create', { cwd: 'relative' }), owned, inPane).kind, 'deny')
  assert.equal(decide(call('pane_list', 'w1'), owned, inPane).kind, 'deny')
})

test('a write without HERDR_ENV=1 is denied', () => {
  const owned = new Set(['w1:p2'])
  assert.equal(decide(call('pane_split', { pane: 'w1:p1', direction: 'right' }), owned, {}).kind, 'deny')
  assert.equal(decide(call('pane_run', { pane: 'w1:p2', command: 'ls' }), owned, { HERDR_ENV: '0' }).kind, 'deny')
})

test('reads pass on any pane; other writes ask; unknown herdr tools are denied', () => {
  const owned = new Set()
  assert.equal(decide(call('pane_read', { pane: 'wA:pZ', lines: 5 }), owned, {}), undefined)
  assert.equal(decide(call('agent_read', { agent: 'claude' }), owned, {}), undefined)
  assert.equal(decide(call('pane_list', {}), owned, {}), undefined)
  assert.equal(decide(call('agent_prompt', { agent: 'w1:p1', prompt: 'hi' }), owned, inPane).kind, 'ask')
  assert.equal(decide(call('pane_send_text', { pane: 'w1:p1', text: 'y\r' }), owned, inPane).kind, 'deny')
  assert.equal(decide({ name: 'bash', arguments: { pane: '--x' } }, owned, inPane), undefined)
})

test('a pane this process split becomes its own: pane_run then asks', async () => {
  const { on, provided } = mount()
  const exec = call('pane_run', { pane: 'w1:p3', command: 'ls' })
  const saved = process.env.HERDR_ENV
  process.env.HERDR_ENV = '1'
  try {
    assert.equal((await on['tools/pre-execute'](exec, allow)).kind, 'deny')
    on['tools/result'](call('pane_split', { pane: 'w1:p1', direction: 'down' }), {
      isError: false,
      value: { ok: true, data: { result: { type: 'pane_info', pane: { pane_id: 'w1:p3' } } } },
    })
    assert.deepEqual(provided.herdrGuard.owned(), ['w1:p3'])
    assert.equal((await on['tools/pre-execute'](exec, allow)).kind, 'ask')
    // A later listener's deny still wins over the guard's ask.
    const later = await on['tools/pre-execute'](exec, async () => ({ kind: 'deny', reason: 'later' }))
    assert.deepEqual(later, { kind: 'deny', reason: 'later' })
  } finally {
    if (saved === undefined) delete process.env.HERDR_ENV
    else process.env.HERDR_ENV = saved
  }
})

test('apply logs one ready line, and mounts without a logger', () => {
  const lines = []
  apply({ on() {}, provide() {}, logger: { info: (...args) => lines.push(args) } })
  assert.deepEqual(lines, [['herdr-guard ready']])
  assert.doesNotThrow(() => mount())
})
