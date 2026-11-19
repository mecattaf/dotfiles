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
//   5. With KP_PROGRAM (the kitty-persist program): one more real turn run
//      inside a session held by that program, the plugin calling its real
//      `hook`; the holder's record then names the dsh-native agent, its
//      conversation, the carried variables and the finished turn.
//   The definition's conversation part (the program's published shape) finds
//   the real texts of the turn in the conversation file the hook was given.
import assert from 'node:assert/strict'
import { spawn } from 'node:child_process'
import { chmodSync, existsSync, mkdirSync, readFileSync, symlinkSync, writeFileSync } from 'node:fs'
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

const calls = () => (existsSync(log) ? readFileSync(log, 'utf8').trim().split('\n').filter(Boolean).map(l => JSON.parse(l)) : [])

// One real turn inside a session held by the kitty-persist program (S21.8,
// S22): the plugin runs the program's own `hook`, which reports to the
// holder; the holder's record is read back with `info --json`.
async function throughTheProgram (basePatch) {
  const program = process.env.KP_PROGRAM
  const holder = join(tmp, 'kp-bin', 'kitty-persist-holder')
  mkdirSync(join(tmp, 'kp-bin'), { recursive: true })
  symlinkSync(program, holder)
  const harnessDir = join(tmp, 'kp-config', 'kitty-persist', 'harness')
  mkdirSync(harnessDir, { recursive: true })
  writeFileSync(join(harnessDir, 'dsh-native.json'), JSON.stringify(definition))
  const env = {
    ...process.env,
    XDG_CONFIG_HOME: join(tmp, 'kp-config'),
    KITTY_PERSIST_RUNTIME_DIR: join(tmp, 'kp-rt'),
    KITTY_PERSIST_STATE_DIR: join(tmp, 'kp-state'),
    KITTY_PERSIST_CACHE_DIR: join(tmp, 'kp-cache'),
    KITTY_PERSIST_LAUNCH: 'setsid',
    KITTY_PERSIST_SHELL_INTEGRATION_DIR: '',
    SHELL: '/bin/sh',
    DSH_KEY_SLOT: '1',
  }
  delete env.KITTY_PERSIST_ID
  delete env.KITTY_PERSIST_SOCKET
  for (const d of ['kp-rt', 'kp-state', 'kp-cache']) mkdirSync(join(tmp, d), { recursive: true, mode: 0o700 })
  const patch = join(tmp, 'mock-real.json')
  const rows = JSON.parse(readFileSync(basePatch, 'utf8')).filter(r => r.id !== 'kitty-persist-hooks')
  writeFileSync(patch, JSON.stringify([...rows, { id: 'kitty-persist-hooks', config: { command: program } }]))
  const done = join(tmp, 'held.rc')
  const launcher = join(tmp, 'held.sh')
  const q = v => `'${String(v).replaceAll("'", "'\\''")}'`
  writeFileSync(launcher, [
    '#!/bin/sh',
    `cd ${q(process.cwd())}`,
    ...['XDG_CONFIG_HOME', 'DSH_HOME', 'DSH_KEY_SLOT', 'HOME', 'TMPDIR', 'PATH'].map(k => `export ${k}=${q(env[k])}`),
    `${q(process.env.DSH_BIN)} native --patch ${q(patch)} 'Use one tool, then reply KP_MOCK_DONE.' > ${q(done + '.out')} 2> ${q(done + '.err')}`,
    `echo $? > ${q(done)}`,
    'exec sleep 60',
  ].join('\n') + '\n')
  chmodSync(launcher, 0o755)
  const holderRun = args => new Promise((resolve, reject) => {
    const child = spawn(holder, args, { env, stdio: ['ignore', 'pipe', 'pipe'] })
    let stdout = '', stderr = ''
    child.stdout.on('data', c => { stdout += c })
    child.stderr.on('data', c => { stderr += c })
    child.once('error', reject)
    child.once('exit', code => resolve({ code, stdout, stderr }))
  })
  script = ['tool', 'answer']
  const made = await holderRun(['new', '--', '/bin/sh', launcher])
  assert.equal(made.code, 0, made.stderr)
  const sid = made.stdout.trim()
  try {
    const sleep = ms => new Promise(r => setTimeout(r, ms))
    for (let i = 0; i < 1200 && !existsSync(done); i++) await sleep(50)
    assert.ok(existsSync(done), 'the dsh run in the session did not finish')
    assert.equal(readFileSync(done, 'utf8').trim(), '0', readFileSync(done + '.err', 'utf8'))
    let agent
    for (let i = 0; i < 100; i++) {
      const got = await holderRun(['info', sid, '--json'])
      assert.equal(got.code, 0, got.stderr)
      agent = JSON.parse(got.stdout).agent
      if (agent?.ended) break
      await sleep(50)
    }
    assert.equal(agent.name, 'dsh-native', JSON.stringify(agent))
    assert.equal(agent.state, 'done', JSON.stringify(agent))
    assert.equal(agent.ended?.reason, 'reported', JSON.stringify(agent))
    assert.match(agent.session, /^session-[0-9a-f-]{36}$/)
    assert.equal(agent.cwd, process.cwd())
    assert.ok(agent.transcript.startsWith(process.env.DSH_HOME + '/sessions/'), agent.transcript)
    // The variables the definition carries over a resume, as the run had them.
    assert.equal(agent.env.DSH_HOME, process.env.DSH_HOME, JSON.stringify(agent.env))
    assert.equal(agent.env.DSH_KEY_SLOT, '1', JSON.stringify(agent.env))
    for (const k of Object.keys(agent.env)) assert.ok(definition.resume.env.includes(k), k)
    return `${agent.name} ${agent.state} ended ${agent.ended.reason}`
  } finally {
    await holderRun(['kill', sid, '--signal', 'KILL', '--forget'])
  }
}

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
  // The definition's conversation part, applied to that file as the
  // program's reader does: the session line names this conversation, each
  // line takes the first entry whose `when` holds, and the entry's paths find
  // the text the turn really had.
  const conv = definition.conversation
  assert.equal(conv.format, 'jsonl')
  const get = (v, path) => path.split('.').reduce((o, k) => (o !== null && typeof o === 'object' && k in o ? o[k] : undefined), v)
  const matches = (line, when) => Object.entries(when ?? {}).every(([k, v]) => get(line, k) === v)
  const shape = v => (Array.isArray(v) ? [v.length ? shape(v[0]) : []] : v && typeof v === 'object'
    ? Object.fromEntries(Object.entries(v).map(([k, x]) => [k, shape(x)])) : typeof v)
  const why = JSON.stringify(lines.map(shape)).slice(0, 4000)
  const header = lines.find(l => matches(l, conv.session.when))
  assert.equal(get(header, conv.session.field), id, `session line: ${why}`)
  const flat = v => (typeof v === 'string' ? v : Array.isArray(v)
    ? v.map(p => (typeof p === 'string' ? p : typeof p?.text === 'string' ? p.text : JSON.stringify(p))).join('\n')
    : JSON.stringify(v ?? null))
  const read = lines.flatMap(line => {
    const e = conv.entries.find(x => matches(line, x.when) && !(x.unless && matches(line, x.unless)))
    if (e === undefined) return []
    if (e.text) return [{ kind: 'turn', who: get(line, e.speaker ?? '') ?? e.role, text: flat(get(line, e.text)) }]
    if (e.tool_name) return [{ kind: 'call', name: get(line, e.tool_name), input: flat(get(line, e.tool_input ?? '')) }]
    return [{ kind: 'result', text: flat(get(line, e.tool_result)) }]
  })
  const turn = who => read.filter(r => r.kind === 'turn' && r.who === who).map(r => r.text).join('\n')
  assert.match(turn('user'), /Use one tool/, `user: ${why}`)
  assert.match(turn('assistant'), /KP_MOCK_DONE/, `assistant: ${why}`)
  assert.deepEqual(read.filter(r => r.kind === 'call').map(r => r.name), ['read'], `tool call: ${why}`)
  assert.match(read.filter(r => r.kind === 'call').map(r => r.input).join('\n'), /note\.txt/, `tool input: ${why}`)
  assert.match(read.filter(r => r.kind === 'result').map(r => r.text).join('\n'), /a note for the read tool/, `tool result: ${why}`)

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

  // 4. Parity of states with the two shipped harnesses (S22.11), through the
  // definition's rules (one rule or a list; `when` against the event data).
  const holds = (when, data) => Object.entries(when ?? {}).every(([k, v]) => {
    const got = data?.[k] ?? null
    return Array.isArray(v) ? v.includes(got) : v === got
  })
  const state = call => {
    const entry = definition.events[call.argv[2]]
    const data = JSON.parse(call.stdin)
    const rule = entry === undefined ? undefined
      : (Array.isArray(entry) ? entry : [entry]).find(r => holds(r.when, data) && !(r.unless && holds(r.unless, data)))
    return rule === undefined ? undefined : rule.ended === true ? 'ended' : rule.state
  }
  const collapse = states => states.filter((s, i) => s !== undefined && s !== states[i - 1])
  const claude = { SessionStart: 'idle', UserPromptSubmit: 'working', PostToolUse: 'working', Stop: 'done', SessionEnd: 'ended' }
  const scenario = ['SessionStart', 'UserPromptSubmit', 'PostToolUse', 'Stop', 'SessionEnd']
  assert.deepEqual(collapse(first.map(state)), collapse(scenario.map(e => claude[e])))
  assert.deepEqual(collapse(first.map(state)), ['idle', 'working', 'done', 'ended'])
  assert.deepEqual(collapse(second.map(state)), ['idle', 'working', 'done', 'ended'])
  const withPermission = ['SessionStart', 'UserPromptSubmit', 'PermissionRequest', 'PostToolUse', 'Stop', 'SessionEnd']
  const claudeAll = { ...claude, PermissionRequest: 'waiting' }
  assert.deepEqual(collapse(third.map(state)), collapse(withPermission.map(e => claudeAll[e])))

  // 5. The real program: a session held by it, the plugin calling its hook.
  let held = 'not run (no KP_PROGRAM)'
  if (process.env.KP_PROGRAM) held = await throughTheProgram(patch)
  console.log(`kitty-persist dsh hooks: ${words.join(' ')} | resume: ${second.map(c => c.argv[2]).join(' ')} | permission: ${asked.join(' ')} | parent argv0 dsh, comm ${first[0].parentComm} | held: ${held}`)
} finally {
  server.closeAllConnections()
  await new Promise(resolve => server.close(resolve))
}
