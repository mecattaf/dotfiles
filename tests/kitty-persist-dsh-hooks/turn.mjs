// Real dsh turns with the kitty-persist-hooks plugin, against a mock OpenAI
// provider and a stub `kitty-persist` program that logs each call. Run by
// tests/kitty-persist-dsh-hooks/default.nix in the build sandbox.
//
//   1. Outside a kitty-persist session: the stub is never called.
//   2. Inside one: start, one tool call, the answer. The stub sees
//      session-start, turn-start, tool-result, stop and session-end, in that
//      order, as `hook dsh-native EVENT`, from a parent whose argv0 is `dsh`,
//      with the allowlisted environment only and identifiers only on stdin.
//   3. The typed resume (`dsh native --session-id ID -`, the instruction on
//      stdin): the same session id, source `resume`.
//   3b. A permission question (a write outside the workspace with a sandbox
//      escalation, which the fleet policy asks about and headless denies):
//      approval-asked and approval-decided before the tool result.
//   4. The states those events give through the generated definition are the
//      ones the specification gives Claude Code and Codex for the same turns.
//   The definition's draft conversation reader finds the real texts of the
//   turn in the conversation file the hook was given.
import assert from 'node:assert/strict'
import { spawn } from 'node:child_process'
import { chmodSync, existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { createServer } from 'node:http'
import { basename, join } from 'node:path'

const tmp = process.env.TMPDIR
const definition = JSON.parse(readFileSync(process.env.KP_DEFINITION, 'utf8'))
const log = join(tmp, 'hook-calls.jsonl')

// The stub program: argv, environment, stdin and the parent's identity.
const stubDir = join(tmp, 'stub')
mkdirSync(stubDir, { recursive: true })
writeFileSync(join(stubDir, 'stub.mjs'), `
  import { appendFileSync, readFileSync } from 'node:fs'
  let input = ''
  for await (const chunk of process.stdin) input += chunk
  const cmdline = readFileSync('/proc/' + process.ppid + '/cmdline', 'utf8').split('\\0')
  const comm = readFileSync('/proc/' + process.ppid + '/comm', 'utf8').trim()
  appendFileSync(${JSON.stringify(log)}, JSON.stringify({
    argv: process.argv.slice(2), env: process.env, stdin: input, parentArgv0: cmdline[0], parentComm: comm,
  }) + '\\n')
`)
const stub = join(stubDir, 'kitty-persist')
writeFileSync(stub, `#!/bin/sh\nexec ${JSON.stringify(process.execPath)} ${JSON.stringify(join(stubDir, 'stub.mjs'))} "$@"\n`)
chmodSync(stub, 0o755)

// The mock provider: a tool call first, then the answer; a resumed run gets
// the answer at once.
const requests = []
let script = []
const server = createServer(async (request, response) => {
  let body = ''
  for await (const chunk of request) body += chunk
  const parsed = JSON.parse(body)
  requests.push(parsed)
  const step = script.shift() ?? 'answer'
  const chunk = (delta, finish_reason = null) => ({
    id: 'kp-mock', object: 'chat.completion.chunk', created: 1, model: process.env.MOCK_MODEL_ID,
    choices: [{ index: 0, delta, finish_reason }],
  })
  response.writeHead(200, { 'content-type': 'text/event-stream' })
  const send = value => response.write(`data: ${JSON.stringify(value)}\n\n`)
  if (step === 'write-outside') {
    // A write outside the workspace with a sandbox escalation: the fleet
    // policy asks, and headless has no answerer, so the ask fails closed.
    const args = {
      file_path: join(process.env.HOME, 'outside.txt'), content: 'x\n',
      sandbox_permissions: 'danger-full-access', justification: 'The check needs one permission question.',
    }
    send(chunk({ role: 'assistant', tool_calls: [{ index: 0, id: 'call_kp_2', type: 'function', function: { name: 'write', arguments: '' } }] }))
    send(chunk({ tool_calls: [{ index: 0, function: { arguments: JSON.stringify(args) } }] }))
    send(chunk({}, 'tool_calls'))
  } else if (step === 'tool') {
    const names = (parsed.tools ?? []).map(t => t.function?.name).filter(Boolean)
    const preferred = ['read_file', 'fs_read', 'read', 'view', 'list_dir', 'ls', 'glob', 'grep']
    const name = preferred.find(n => names.includes(n)) ?? names.find(n => /read|list|glob|grep|view/.test(n)) ?? names[0]
    assert.ok(name, 'the request offers no tool')
    send(chunk({ role: 'assistant', tool_calls: [{ index: 0, id: 'call_kp_1', type: 'function', function: { name, arguments: '' } }] }))
    const args = name === 'read' ? { file_path: join(process.cwd(), 'note.txt') } : {}
    send(chunk({ tool_calls: [{ index: 0, function: { arguments: JSON.stringify(args) } }] }))
    send(chunk({}, 'tool_calls'))
  } else {
    send(chunk({ role: 'assistant', content: 'KP_MOCK_DONE' }))
    send(chunk({}, 'stop'))
  }
  response.end('data: [DONE]\n\n')
})
await new Promise((resolve, reject) => {
  server.once('error', reject)
  server.listen(0, '127.0.0.1', resolve)
})

function dsh(args, env, input) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.env.DSH_BIN, args, {
      cwd: process.cwd(), env, stdio: [input === undefined ? 'ignore' : 'pipe', 'pipe', 'pipe'],
    })
    let stdout = '', stderr = ''
    child.stdout.on('data', c => { stdout += c })
    child.stderr.on('data', c => { stderr += c })
    if (input !== undefined) child.stdin.end(input)
    const timer = setTimeout(() => child.kill('SIGKILL'), 60_000)
    child.once('error', reject)
    child.once('exit', code => { clearTimeout(timer); resolve({ code, stdout, stderr }) })
  })
}

// A reader path: `a.b[].c` (`[]` steps into every element of an array).
function pick(value, path) {
  let values = [value]
  for (const part of path.split('.')) {
    const many = part.endsWith('[]')
    const key = many ? part.slice(0, -2) : part
    values = values.flatMap(v => (v !== null && typeof v === 'object' && key in v ? [v[key]] : []))
    if (many) values = values.flatMap(v => (Array.isArray(v) ? v : []))
  }
  return values
}

const calls = () => (existsSync(log) ? readFileSync(log, 'utf8').trim().split('\n').filter(Boolean).map(l => JSON.parse(l)) : [])

try {
  writeFileSync(join(process.cwd(), 'note.txt'), 'a note for the read tool\n')
  const provider = JSON.parse(process.env.MOCK_GUFO_CONFIG)
  provider.baseURL = `http://127.0.0.1:${server.address().port}/v1`
  provider.retryPolicy = { mode: 'normal', maxRetries: 0 }
  const patch = join(tmp, 'mock.json')
  writeFileSync(patch, JSON.stringify([
    { id: 'llm-pi-ai', config: { providers: { gufo: provider } } },
    { id: 'agent-default-model', config: { provider: 'gufo', model: process.env.MOCK_MODEL_ID } },
    { id: 'kitty-persist-hooks', config: { command: stub, coalesce: false } },
  ]))
  const outside = { ...process.env, KP_TEST_API_KEY: 'must-not-leak' }
  delete outside.KITTY_PERSIST_ID
  const inside = {
    ...outside,
    KITTY_PERSIST_ID: '0b7e3c1a-5d2f-4e8a-9c6b-1f2e3d4c5b6a',
    KITTY_PERSIST_SOCKET: join(tmp, 'holder.sock'),
    DSH_KEY_SLOT: '1',
  }

  // 1. Outside a session.
  script = ['answer']
  let run = await dsh(['native', '--patch', patch, 'Reply KP_MOCK_DONE.'], outside)
  assert.equal(run.code, 0, run.stderr)
  assert.match(run.stdout, /KP_MOCK_DONE/)
  assert.deepEqual(calls(), [], 'the hook ran outside a kitty-persist session')

  // 2. Inside: one tool call, then the answer.
  script = ['tool', 'answer']
  run = await dsh(['native', '--patch', patch, 'Use one tool, then reply KP_MOCK_DONE.'], inside)
  assert.equal(run.code, 0, run.stderr)
  assert.match(run.stdout, /KP_MOCK_DONE/)
  const first = calls()
  const words = first.map(c => c.argv[2])
  assert.deepEqual(words, ['session-start', 'turn-start', 'tool-result', 'stop', 'session-end'], run.stderr)
  const id = JSON.parse(first[0].stdin).session_id
  assert.match(id, /^session-[0-9a-f-]{36}$/)
  const allowed = new Set([
    'PATH', 'HOME', 'USER', 'LOGNAME', 'LANG', 'LC_ALL', 'TZ', 'XDG_RUNTIME_DIR', 'XDG_CONFIG_HOME',
    'XDG_STATE_HOME', 'XDG_DATA_HOME', 'XDG_CACHE_HOME', 'DSH_HOME', 'DSH_KEY_SLOT', 'DSH_ROUTE',
    'KITTY_PERSIST_ID', 'KITTY_PERSIST_SOCKET', 'PWD', 'SHLVL', '_', 'OLDPWD',
  ])
  for (const call of first) {
    assert.deepEqual(call.argv.slice(0, 2), ['hook', 'dsh-native'])
    // The hook's parent is the dsh process itself: argv0 `dsh`, so a
    // definition that recognises `dsh` finds the agent in one step.
    assert.equal(basename(call.parentArgv0), 'dsh', `parent argv0 ${call.parentArgv0} (comm ${call.parentComm})`)
    for (const key of Object.keys(call.env)) assert.ok(allowed.has(key), `hook environment has ${key}`)
    assert.equal(call.env.KITTY_PERSIST_ID, inside.KITTY_PERSIST_ID)
    assert.equal(call.env.DSH_KEY_SLOT, '1')
    assert.equal(call.env.GUFO_API_KEY, undefined)
    const payload = JSON.parse(call.stdin)
    for (const key of Object.keys(payload)) {
      assert.ok(['hook_event_name', 'session_id', 'cwd', 'transcript_path', 'source', 'reason'].includes(key), key)
    }
    assert.equal(payload.session_id, id)
    assert.equal(payload.cwd, process.cwd())
    assert.doesNotMatch(call.stdin, /Use one tool|KP_MOCK_DONE/)
  }
  assert.equal(JSON.parse(first[0].stdin).source, 'startup')
  assert.equal(JSON.parse(first[3].stdin).reason, 'completed')
  // The conversation file, once dsh has written it: plain JSONL under DSH_HOME.
  const transcript = JSON.parse(first.at(-1).stdin).transcript_path
  assert.ok(transcript?.startsWith(process.env.DSH_HOME + '/sessions/'), `transcript ${transcript}`)
  const lines = readFileSync(transcript, 'utf8').trim().split('\n').map(l => JSON.parse(l))
  // The definition's draft conversation reader, applied to that file: each
  // path finds the text the turn really had.
  const conv = definition.conversation
  const shape = v => (Array.isArray(v) ? [v.length ? shape(v[0]) : []] : v && typeof v === 'object'
    ? Object.fromEntries(Object.entries(v).map(([k, x]) => [k, shape(x)])) : typeof v)
  const of = kind => lines.filter(l => pick(l, conv.kind)[0] === kind)
  const texts = (kind, path) => of(kind).flatMap(l => pick(l, path)).map(v => (typeof v === 'string' ? v : JSON.stringify(v))).join('\n')
  const why = kind => JSON.stringify(of(kind).map(shape))
  assert.match(texts(conv.user.kind, conv.user.text), /Use one tool/, `user: ${why(conv.user.kind)}`)
  assert.match(texts(conv.assistant.kind, conv.assistant.text), /KP_MOCK_DONE/, `assistant: ${why(conv.assistant.kind)}`)
  assert.match(texts(conv.toolCall.kind, conv.toolCall.name), /^read$/m, `tool call: ${why(conv.toolCall.kind)}`)
  assert.match(texts(conv.toolCall.kind, conv.toolCall.input), /note\.txt/, `tool input: ${why(conv.toolCall.kind)}`)
  assert.match(texts(conv.toolResult.kind, conv.toolResult.text), /a note for the read tool/, `tool result: ${why(conv.toolResult.kind)}`)
  assert.deepEqual(of(conv.toolResult.kind).flatMap(l => pick(l, conv.toolResult.error)).filter(v => v === true), [], `tool error: ${why(conv.toolResult.kind)}`)

  // 3. The typed resume from the definition, the instruction on stdin.
  const resume = definition.resume.command.map(word => (word === '{id}' ? id : word))
  assert.deepEqual(resume.slice(0, 2), ['dsh', 'native'])
  script = ['answer']
  run = await dsh([...resume.slice(1, 2), '--patch', patch, ...resume.slice(2)], inside, 'Reply KP_MOCK_DONE again.\n')
  assert.equal(run.code, 0, run.stderr)
  const second = calls().slice(first.length)
  assert.deepEqual(second.map(c => c.argv[2]), ['session-start', 'turn-start', 'stop', 'session-end'], run.stderr)
  assert.equal(JSON.parse(second[0].stdin).source, 'resume')
  for (const call of second) assert.equal(JSON.parse(call.stdin).session_id, id)

  // 3b. A permission question: dsh's approval events around the tool result.
  script = ['write-outside', 'answer']
  run = await dsh(['native', '--patch', patch, 'Write the file, then reply KP_MOCK_DONE.'], inside)
  const third = calls().slice(first.length + second.length)
  const asked = third.map(c => c.argv[2])
  assert.deepEqual(asked, ['session-start', 'turn-start', 'approval-asked', 'approval-decided', 'tool-result', 'stop', 'session-end'], run.stderr)
  assert.ok(!existsSync(join(process.env.HOME, 'outside.txt')), 'the denied write happened')

  // 4. Parity of states with the two shipped harnesses (S22.11).
  const state = word => (definition.events[word]?.ended ? 'ended' : definition.events[word]?.state)
  const collapse = states => states.filter((s, i) => s !== undefined && s !== states[i - 1])
  const claude = { SessionStart: 'idle', UserPromptSubmit: 'working', PostToolUse: 'working', Stop: 'done', SessionEnd: 'ended' }
  const scenario = ['SessionStart', 'UserPromptSubmit', 'PostToolUse', 'Stop', 'SessionEnd']
  assert.deepEqual(collapse(words.map(state)), collapse(scenario.map(e => claude[e])))
  assert.deepEqual(collapse(words.map(state)), ['idle', 'working', 'done', 'ended'])
  const withPermission = ['SessionStart', 'UserPromptSubmit', 'PermissionRequest', 'PostToolUse', 'Stop', 'SessionEnd']
  const claudeAll = { ...claude, PermissionRequest: 'waiting' }
  assert.deepEqual(collapse(asked.map(state)), collapse(withPermission.map(e => claudeAll[e])))
  console.log(`kitty-persist dsh hooks: ${words.join(' ')} | resume: ${second.map(c => c.argv[2]).join(' ')} | permission: ${asked.join(' ')} | parent argv0 dsh, comm ${first[0].parentComm}`)
} finally {
  server.closeAllConnections()
  await new Promise(resolve => server.close(resolve))
}
