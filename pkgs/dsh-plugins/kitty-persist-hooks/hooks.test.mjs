// Unit tests for index.js: a fake Cordis context, a fake spawn, and one real
// stub hook program. No dsh, no kitty-persist, no holder.
//
// KP_DSH_DEFINITION names a generated dsh harness definition (the check phase
// passes ./definitions.nix for the `herdr` profile); the replay test runs the
// reported events through it and compares the states with those the
// specification gives Claude Code and Codex for the same scenario.
import test from 'node:test'
import assert from 'node:assert/strict'
import { chmodSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { EventEmitter } from 'node:events'
import {
  apply, createReporter, hookEnv, isRoot, turnEndEvent, validCommand, EVENTS, MAX_PENDING,
} from './index.js'

const sessionOf = (id, extra = {}) => ({ header: { id, cwd: '/work/project', ...extra } })
const agentOf = session => ({ session })
const baseEnv = {
  KITTY_PERSIST_ID: '7f9c1a2e-1111-4222-8333-944445555666',
  KITTY_PERSIST_SOCKET: '/run/kp/7f9c.sock',
  PATH: '/bin', HOME: '/home/u', XDG_RUNTIME_DIR: '/run/user/1',
  DSH_KITTY_PERSIST_HARNESS: 'dsh-herdr', DSH_HOME: '/home/u/.dsh', DSH_KEY_SLOT: '2',
  GEMINI_API_KEY: 'secret-1', CLOUDFLARE_API_TOKEN: 'secret-2', GUFO_API_KEY: 'local-no-auth',
  KITTY_PERSIST_TOKEN: 'secret-3', SSH_AUTH_SOCK: '/tmp/agent',
}

// A spawn double: records argv, env and the stdin payload; `hold` keeps the
// child running until released or killed.
function fakeSpawn({ hold = false } = {}) {
  const calls = []
  const spawnImpl = (command, argv, options) => {
    const child = new EventEmitter()
    const stdin = new EventEmitter()
    let written = ''
    stdin.end = chunk => {
      written += chunk ?? ''
      call.payload = JSON.parse(written)
      if (!hold) setImmediate(() => child.emit('close', 0))
    }
    child.stdin = stdin
    child.kill = signal => { call.killed = signal; setImmediate(() => child.emit('close', null)) }
    const call = { command, argv, env: options.env, stdio: options.stdio, child }
    calls.push(call)
    return child
  }
  return { calls, spawnImpl }
}

// A fake Cordis context: listeners by event, one effect, an optional
// persistence service.
function fakeCtx({ transcript } = {}) {
  const on = {}
  const effects = []
  const ctx = {
    on(event, listener) { on[event] = listener; return () => {} },
    effect(fn) { effects.push(fn) },
    get(name) {
      if (name !== 'sessionPersistence' || transcript === undefined) return undefined
      return { stat: async () => ({ location: { kind: 'jsonl', path: transcript } }) }
    },
    logger: { debug() {} },
  }
  return { ctx, on, effects }
}

const settle = () => new Promise(resolve => setTimeout(resolve, 20))
const words = calls => calls.map(c => c.argv[2])

test('the hook environment is an allowlist', () => {
  const env = hookEnv(baseEnv)
  assert.deepEqual(Object.keys(env).sort(), [
    'DSH_HOME', 'DSH_KEY_SLOT', 'HOME', 'KITTY_PERSIST_ID', 'KITTY_PERSIST_SOCKET', 'PATH', 'XDG_RUNTIME_DIR',
  ])
  assert.equal(env.DSH_KEY_SLOT, '2')
})

test('command, root session and turn-end words', () => {
  assert.ok(validCommand('kitty-persist'))
  assert.ok(validCommand('/nix/store/x-kitty-persist/bin/kitty-persist'))
  for (const bad of ['kp', './kitty-persist', '/bin/kp\n', 7, undefined]) assert.ok(!validCommand(bad), String(bad))
  assert.ok(isRoot(sessionOf('session-a')))
  assert.ok(!isRoot(sessionOf('session-b', { origin: 'subagent' })))
  assert.ok(!isRoot(sessionOf('session-c', { delegationDepth: 1 })))
  assert.ok(!isRoot({ header: { id: '' } }))
  assert.equal(turnEndEvent({ kind: 'completed' }), 'stop')
  assert.equal(turnEndEvent({ kind: 'max-tokens' }), 'stop')
  assert.equal(turnEndEvent({ kind: 'blocked' }), 'stop')
  assert.equal(turnEndEvent({ kind: 'error' }), 'stop-failure')
  assert.equal(turnEndEvent({ kind: 'aborted' }), 'turn-aborted')
  assert.equal(turnEndEvent({ kind: 'interrupted' }), undefined)
  assert.equal(turnEndEvent({ kind: 'forked' }), undefined)
})

test('outside a kitty-persist session nothing mounts', () => {
  const { ctx, on, effects } = fakeCtx()
  const { calls, spawnImpl } = fakeSpawn()
  const { KITTY_PERSIST_ID: _, ...outside } = baseEnv
  apply(ctx, { command: 'kitty-persist' }, outside, spawnImpl)
  assert.deepEqual(Object.keys(on), [])
  assert.equal(effects.length, 0)
  assert.equal(calls.length, 0)
})

test('no harness name, or a bad command: nothing mounts', () => {
  for (const [config, env] of [
    [{ command: 'kitty-persist' }, { ...baseEnv, DSH_KITTY_PERSIST_HARNESS: undefined }],
    [{ command: 'kitty-persist' }, { ...baseEnv, DSH_KITTY_PERSIST_HARNESS: 'Dsh Herdr' }],
    [{ command: 'kp' }, baseEnv],
  ]) {
    const { ctx, on } = fakeCtx()
    apply(ctx, config, env, fakeSpawn().spawnImpl)
    assert.deepEqual(Object.keys(on), [])
  }
})

test('a run reports in order, with identifiers only', async () => {
  const { ctx, on, effects } = fakeCtx({ transcript: '/home/u/.dsh/sessions/--work-project--/s/session.v4.jsonl' })
  const { calls, spawnImpl } = fakeSpawn()
  apply(ctx, { command: '/store/bin/kitty-persist' }, baseEnv, spawnImpl)
  const session = sessionOf('session-11111111-2222-4333-8444-555555555555')
  const agent = agentOf(session)
  // agent/created is serial and awaited by dsh: it must return at once.
  assert.equal(on['agent/created']({ agent, source: 'startup' }), undefined)
  on['session/event'](session, { type: 'turn/start', data: { turn: 1 } })
  on['session/event'](session, { type: 'user/message', data: { content: [{ type: 'text', text: 'PRIVATE PROMPT' }] } })
  on['session/event'](session, { type: 'tool/call', data: { name: 'read', arguments: '{"path":"/secret"}' } })
  on['session/event'](session, { type: 'tool/result', data: { turn: 1 } })
  on['session/event'](session, { type: 'tool/result', data: { turn: 1 } })
  on['session/event'](session, { type: 'approval/asked', data: { id: 'a1', toolName: 'bash' } })
  on['session/event'](session, { type: 'approval/decided', data: { id: 'a1', outcome: { kind: 'denied' } } })
  on['session/event'](session, { type: 'tool/result', data: { turn: 1 } })
  on['session/event'](session, { type: 'turn/end', data: { turn: 1, reason: { kind: 'completed' } } })
  on['agent/disposed']({ agent })
  await effects[0]()()
  assert.deepEqual(words(calls), ['session-start', 'turn-start', 'approval-asked', 'approval-decided', 'stop', 'session-end'])
  for (const call of calls) {
    assert.equal(call.command, '/store/bin/kitty-persist')
    assert.deepEqual(call.argv.slice(0, 2), ['hook', 'dsh-herdr'])
    assert.deepEqual(call.stdio, ['pipe', 'ignore', 'ignore'])
    assert.equal(call.env.GEMINI_API_KEY, undefined)
    assert.equal(call.env.GUFO_API_KEY, undefined)
    assert.equal(call.env.KITTY_PERSIST_TOKEN, undefined)
    assert.equal(call.env.KITTY_PERSIST_ID, baseEnv.KITTY_PERSIST_ID)
    const allowed = new Set(['hook_event_name', 'session_id', 'cwd', 'transcript_path', 'source', 'reason'])
    for (const key of Object.keys(call.payload)) assert.ok(allowed.has(key), key)
    assert.equal(call.payload.session_id, 'session-11111111-2222-4333-8444-555555555555')
    assert.equal(call.payload.cwd, '/work/project')
    assert.equal(call.payload.transcript_path, '/home/u/.dsh/sessions/--work-project--/s/session.v4.jsonl')
    assert.equal(call.payload.hook_event_name, call.argv[2])
    assert.doesNotMatch(JSON.stringify(call.payload), /PRIVATE|secret/)
  }
  assert.equal(calls[0].payload.source, 'startup')
  assert.equal(calls[4].payload.reason, 'completed')
})

test('subagent sessions and unknown sessions are ignored', async () => {
  const { ctx, on, effects } = fakeCtx()
  const { calls, spawnImpl } = fakeSpawn()
  apply(ctx, {}, baseEnv, spawnImpl)
  const child = sessionOf('session-child', { origin: 'subagent', parentSession: 'session-root' })
  on['agent/created']({ agent: agentOf(child), source: 'startup' })
  on['session/event'](child, { type: 'turn/end', data: { turn: 1, reason: { kind: 'completed' } } })
  on['session/event'](sessionOf('session-never-created'), { type: 'turn/start', data: { turn: 1 } })
  on['agent/disposed']({ agent: agentOf(child) })
  await effects[0]()()
  assert.equal(calls.length, 0)
})

test('turn ends: failure, cancellation, and the resume closer', async () => {
  const { ctx, on, effects } = fakeCtx()
  const { calls, spawnImpl } = fakeSpawn()
  apply(ctx, {}, baseEnv, spawnImpl)
  const session = sessionOf('session-r')
  on['agent/created']({ agent: agentOf(session), source: 'resume' })
  // dsh appends this closer when it adopts a session whose last turn crashed.
  on['session/event'](session, { type: 'turn/end', data: { turn: 3, reason: { kind: 'interrupted' } } })
  on['session/event'](session, { type: 'turn/start', data: { turn: 4 } })
  on['session/event'](session, { type: 'turn/end', data: { turn: 4, reason: { kind: 'error', error: { message: 'x' } } } })
  on['session/event'](session, { type: 'turn/start', data: { turn: 5 } })
  on['session/event'](session, { type: 'turn/end', data: { turn: 5, reason: { kind: 'aborted', reason: {} } } })
  await effects[0]()()
  assert.deepEqual(words(calls), ['session-start', 'turn-start', 'stop-failure', 'turn-start', 'turn-aborted', 'session-end'])
  assert.equal(calls[0].payload.source, 'resume')
  assert.equal(calls[2].payload.reason, 'error')
  // The command defaults to the bare name, found on PATH.
  assert.equal(calls[0].command, 'kitty-persist')
})

test('a question is reported around whoever answers it', async () => {
  const { ctx, on, effects } = fakeCtx()
  const { calls, spawnImpl } = fakeSpawn()
  apply(ctx, {}, baseEnv, spawnImpl)
  const session = sessionOf('session-q')
  const agent = agentOf(session)
  on['agent/created']({ agent, source: 'startup' })
  on['session/event'](session, { type: 'turn/start', data: { turn: 1 } })
  const answer = { answers: [{ id: 'q', value: 'yes' }] }
  assert.equal(await on['user-questions/request']({ agent, questions: [] }, async () => answer), answer)
  await assert.rejects(on['user-questions/request']({ agent, questions: [] }, async () => { throw new Error('no answerer') }))
  // Not ours: delegated untouched.
  assert.equal(await on['user-questions/request']({ questions: [] }, async () => 'other'), 'other')
  await effects[0]()()
  assert.deepEqual(words(calls), [
    'session-start', 'turn-start', 'question-asked', 'question-answered', 'question-asked', 'question-answered', 'session-end',
  ])
})

test('disposal reports the end once, whichever comes first', async () => {
  const { ctx, on, effects } = fakeCtx()
  const { calls, spawnImpl } = fakeSpawn()
  apply(ctx, {}, baseEnv, spawnImpl)
  const session = sessionOf('session-d')
  on['agent/created']({ agent: agentOf(session), source: 'startup' })
  const dispose = effects[0]()
  await dispose()
  on['agent/disposed']({ agent: agentOf(session) })
  await settle()
  assert.deepEqual(words(calls), ['session-start', 'session-end'])
})

test('a hung hook is killed; the queue keeps its order and disposal is bounded', async () => {
  const { calls, spawnImpl } = fakeSpawn({ hold: true })
  const reporter = createReporter({ command: 'kitty-persist', harness: 'dsh-herdr', env: {}, spawnImpl, timeoutMs: 30 })
  reporter.report('turn-start', () => ({}))
  reporter.report('stop', () => ({}))
  await new Promise(resolve => setTimeout(resolve, 150))
  assert.deepEqual(words(calls), ['turn-start', 'stop'])
  assert.equal(calls[0].killed, 'SIGKILL')
  assert.equal(calls[1].killed, 'SIGKILL')
  // Drain gives up after its bound and stops what still runs.
  const slow = createReporter({ command: 'kitty-persist', harness: 'dsh-herdr', env: {}, spawnImpl, timeoutMs: 10_000 })
  slow.report('session-end', () => ({}))
  const started = Date.now()
  await slow.drain(50)
  assert.ok(Date.now() - started < 1000)
  assert.equal(calls[2].killed, 'SIGKILL')
})

test('a full queue drops working reports, never an end', async () => {
  const { calls, spawnImpl } = fakeSpawn({ hold: true })
  const reporter = createReporter({ command: 'kitty-persist', harness: 'dsh-herdr', env: {}, spawnImpl, timeoutMs: 5 })
  for (let i = 0; i < MAX_PENDING; i++) assert.ok(reporter.report('tool-result', () => ({})))
  assert.equal(reporter.report('tool-result', () => ({})), false)
  assert.ok(reporter.report('session-end', () => ({})))
  await reporter.drain(5000)
  assert.equal(words(calls).at(-1), 'session-end')
})

test('a missing program is silent', async () => {
  const reporter = createReporter({ command: '/nonexistent/kitty-persist', harness: 'dsh-herdr', env: {} })
  reporter.report('session-start', () => ({ session_id: 'x' }))
  await reporter.drain(2000)
  assert.equal(reporter.pending, 0)
})

test('a real stub program gets argv, the minimal env and the JSON on stdin', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'kp-hooks-'))
  try {
    const log = join(dir, 'calls.jsonl')
    const stub = join(dir, 'stub.mjs')
    writeFileSync(stub, `
      import { appendFileSync } from 'node:fs'
      let input = ''
      for await (const chunk of process.stdin) input += chunk
      appendFileSync(${JSON.stringify(log)}, JSON.stringify({ argv: process.argv.slice(2), env: process.env, stdin: input }) + '\\n')
    `)
    const command = join(dir, 'kitty-persist')
    writeFileSync(command, `#!/bin/sh\nexec ${JSON.stringify(process.execPath)} ${JSON.stringify(stub)} "$@"\n`)
    chmodSync(command, 0o755)
    const { ctx, on, effects } = fakeCtx()
    apply(ctx, { command }, baseEnv)
    const session = sessionOf('session-real')
    on['agent/created']({ agent: agentOf(session), source: 'startup' })
    on['session/event'](session, { type: 'turn/end', data: { turn: 1, reason: { kind: 'completed' } } })
    await effects[0]()()
    const lines = readFileSync(log, 'utf8').trim().split('\n').map(line => JSON.parse(line))
    assert.deepEqual(lines.map(l => l.argv), [['hook', 'dsh-herdr', 'session-start'], ['hook', 'dsh-herdr', 'stop'], ['hook', 'dsh-herdr', 'session-end']])
    for (const line of lines) {
      // Only names of the allowlist reach the program (the shell may add PWD,
      // SHLVL and `_`).
      const extra = Object.keys(line.env).filter(k => !(k in hookEnv(baseEnv)) && !['PWD', 'SHLVL', '_', 'OLDPWD'].includes(k))
      assert.deepEqual(extra, [])
      assert.equal(JSON.parse(line.stdin).session_id, 'session-real')
    }
  } finally {
    rmSync(dir, { recursive: true, force: true })
  }
})

// --- Replay: the same scenario through each harness's event table. ---

// S22.11, for the two shipped definitions.
const CLAUDE = {
  SessionStart: 'idle', UserPromptSubmit: 'working', PostToolUse: 'working', PermissionRequest: 'waiting',
  Stop: 'done', StopFailure: 'done', SessionEnd: 'ended',
}
const CODEX = {
  SessionStart: 'idle', UserPromptSubmit: 'working', PostToolUse: 'working', PermissionRequest: 'waiting',
  Stop: 'done', SessionEnd: 'ended',
}
// The stand-in for the hook's lookup in a definition (draft field names).
const dshState = (definition, event) => {
  const entry = definition.events[event]
  if (entry === undefined) return undefined
  return entry.ended === true ? 'ended' : entry.state
}
const collapse = states => states.filter((s, i) => s !== undefined && s !== states[i - 1])

test('replay: dsh gives the same states as Claude Code and Codex', { skip: !process.env.KP_DSH_DEFINITION }, async () => {
  const definition = JSON.parse(readFileSync(process.env.KP_DSH_DEFINITION, 'utf8'))
  // Every event word the plugin can send has an entry, and nothing else does.
  assert.deepEqual(Object.keys(definition.events).sort(), Object.values(EVENTS).sort())
  assert.deepEqual(definition.resume.command, ['dsh', 'herdr', '--session-id', '{id}', '-'])
  assert.deepEqual(definition.recognize.commands, ['dsh'])

  // Start, a prompt, a tool, a permission question, the tool after it, the
  // end of the turn, the end of the agent.
  const { ctx, on, effects } = fakeCtx()
  const { calls, spawnImpl } = fakeSpawn()
  apply(ctx, {}, baseEnv, spawnImpl)
  const session = sessionOf('session-replay')
  const agent = agentOf(session)
  on['agent/created']({ agent, source: 'startup' })
  on['session/event'](session, { type: 'turn/start', data: { turn: 1 } })
  on['session/event'](session, { type: 'tool/result', data: { turn: 1 } })
  on['session/event'](session, { type: 'approval/asked', data: { id: 'a', toolName: 'bash' } })
  on['session/event'](session, { type: 'approval/decided', data: { id: 'a', outcome: { kind: 'allowed-once' } } })
  on['session/event'](session, { type: 'tool/result', data: { turn: 1 } })
  on['session/event'](session, { type: 'turn/end', data: { turn: 1, reason: { kind: 'completed' } } })
  on['agent/disposed']({ agent })
  await effects[0]()()
  const dsh = collapse(words(calls).map(word => dshState(definition, word)))
  const scenario = ['SessionStart', 'UserPromptSubmit', 'PostToolUse', 'PermissionRequest', 'PostToolUse', 'Stop', 'SessionEnd']
  const claude = collapse(scenario.map(e => CLAUDE[e]))
  const codex = collapse(scenario.map(e => CODEX[e]))
  assert.deepEqual(dsh, ['idle', 'working', 'waiting', 'working', 'done', 'ended'])
  assert.deepEqual(dsh, claude)
  assert.deepEqual(dsh, codex)

  // A failed turn: Claude's StopFailure and dsh's stop-failure both give done.
  assert.equal(dshState(definition, 'stop-failure'), CLAUDE.StopFailure)
})
