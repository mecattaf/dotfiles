// kitty-persist-hooks: a dsh run's agent state, reported to kitty-persist.
//
// dsh has no external hook command of its own; its lifecycle exists only as
// in-process Cordis events. This plugin turns those events into the one hook
// call every kitty-persist harness uses, `kitty-persist hook NAME EVENT`, with
// the event data as one JSON object on stdin. It is the dsh half of the
// harness definitions home/kitty-persist-agents.nix installs as
// ~/.config/kitty-persist/harness/dsh-<profile>.json.
//
// Why not upstream's Claude-Code hook bridge (@deepseek-ai/dsh-hooks-claude-code,
// MIT; its event wiring in src/index.ts is the donor for the listeners below):
// it runs hooks through dsh's sandboxed shell, which masks the runtime
// directory and unshares the pid namespace, so a hook there can neither reach
// the session holder nor name the agent process; it has no approval, end or
// conversation-file event; and its protocol package is not installed.
//
// Rules, from the kitty-persist hook contract:
//   - Outside a kitty-persist session (KITTY_PERSIST_ID unset) nothing mounts.
//   - The hook is spawned directly from this dsh process (so the agent process
//     is the hook's parent), never through dsh's shell or sandbox.
//   - Its environment is a short allowlist, never process.env: the fleet
//     wrapper exports provider keys into this process.
//   - It never blocks dsh: listeners return at once; one ordered queue runs
//     the hooks, each killed after HOOK_TIMEOUT_MS (kitty-persist itself gives
//     up after 1.5 s), and disposal waits at most DRAIN_MS for the queue.
//   - Only identifiers and state reach the hook: the session id, the
//     conversation file, the working directory, a turn's end reason and the
//     session-start source. Never a prompt, an answer or tool content.
//   - Only top-level agents report; subagent sessions are ignored.
// Plain ESM; the only import is a Node builtin.
import { spawn } from 'node:child_process'
import { isAbsolute } from 'node:path'

export const name = '@mecattaf/kitty-persist-hooks'

export const HOOK_TIMEOUT_MS = 2000
export const DRAIN_MS = 3000
export const STAT_TIMEOUT_MS = 300
export const MAX_PENDING = 64

// The event words this plugin passes as EVENT. The harness definitions map
// each to a state (S22.1) or to the agent's end; keep both in step
// (./definitions.nix).
export const EVENTS = Object.freeze({
  sessionStart: 'session-start', // agent/created: startup, resume, clear, compact
  turnStart: 'turn-start', // session/event turn/start
  toolResult: 'tool-result', // session/event tool/result
  approvalAsked: 'approval-asked', // session/event approval/asked
  approvalDecided: 'approval-decided', // session/event approval/decided
  questionAsked: 'question-asked', // user-questions/request, before next()
  questionAnswered: 'question-answered', // user-questions/request, after next()
  stop: 'stop', // turn/end completed, max-tokens, blocked
  stopFailure: 'stop-failure', // turn/end error
  turnAborted: 'turn-aborted', // turn/end aborted (a cancellation)
  sessionEnd: 'session-end', // agent/disposed, or this plugin's disposal
})

// Reports that change nothing after one of these: a tool result while the
// agent already reported `working` is not sent again.
const WORKING = new Set([EVENTS.turnStart, EVENTS.toolResult, EVENTS.approvalDecided, EVENTS.questionAnswered])
// Never dropped when the queue is full.
const TERMINAL = new Set([EVENTS.stop, EVENTS.stopFailure, EVENTS.turnAborted, EVENTS.sessionEnd])

const HARNESS = /^[a-z0-9]+(?:-[a-z0-9]+)*$/
const CONTROL = /[\x00-\x1f\x7f]/
// The environment a hook gets. kitty-persist's own variables, the few the
// hook needs to find its configuration and the holder, and the variables the
// dsh definitions carry over a resume (DSH_KEY_SLOT is an account number,
// not a key).
const PASS = new Set([
  'PATH', 'HOME', 'USER', 'LOGNAME', 'LANG', 'LC_ALL', 'TZ',
  'XDG_RUNTIME_DIR', 'XDG_CONFIG_HOME', 'XDG_STATE_HOME', 'XDG_DATA_HOME', 'XDG_CACHE_HOME',
])
export const CARRIED = Object.freeze(['DSH_HOME', 'DSH_KEY_SLOT', 'DSH_ROUTE'])
const OWN = /^KITTY_PERSIST_[A-Z0-9_]+$/
const SECRET = /KEY|TOKEN|SECRET|PASSWORD|CREDENTIAL/i

/** The hook's whole environment, built from an allowlist of `env`. */
export function hookEnv(env) {
  const out = {}
  for (const [k, v] of Object.entries(env ?? {})) {
    if (typeof v !== 'string') continue
    if (PASS.has(k) || CARRIED.includes(k) || (OWN.test(k) && !SECRET.test(k))) out[k] = v
  }
  return out
}

/** The command to run: an absolute path, or the bare program name on PATH. */
export function validCommand(command) {
  return typeof command === 'string' && !CONTROL.test(command) &&
    (command === 'kitty-persist' || isAbsolute(command))
}

/** A top-level session this plugin may report for (not a subagent child). */
export function isRoot(session) {
  const header = session?.header
  return typeof header?.id === 'string' && header.id !== '' &&
    header.origin !== 'subagent' && !(header.delegationDepth > 0)
}

/** The hook word for a turn's end, or undefined for closers dsh never emits live. */
export function turnEndEvent(reason) {
  switch (reason?.kind) {
    case 'error': return EVENTS.stopFailure
    case 'aborted': return EVENTS.turnAborted
    // Synthesized on resume or fork, never by a live turn.
    case 'interrupted':
    case 'forked': return undefined
    default: return EVENTS.stop
  }
}

const delay = ms => new Promise(resolve => { setTimeout(resolve, ms).unref?.() })

function withTimeout(promise, ms) {
  return Promise.race([promise, delay(ms).then(() => undefined)])
}

/**
 * One ordered, bounded queue of hook runs.
 * @param options.command - the kitty-persist program.
 * @param options.harness - the harness name the definitions use.
 * @param options.env - the hook's whole environment.
 * @param options.spawnImpl - node:child_process spawn, or a test double.
 */
export function createReporter({ command, harness, env, spawnImpl = spawn, timeoutMs = HOOK_TIMEOUT_MS }) {
  let chain = Promise.resolve()
  let pending = 0
  const children = new Set()

  function run(event, payload) {
    return new Promise(resolve => {
      let child
      try {
        child = spawnImpl(command, ['hook', harness, event], {
          env, stdio: ['pipe', 'ignore', 'ignore'], windowsHide: true,
        })
      } catch {
        resolve()
        return
      }
      children.add(child)
      let done = false
      const finish = () => {
        if (done) return
        done = true
        clearTimeout(timer)
        children.delete(child)
        resolve()
      }
      const timer = setTimeout(() => {
        try { child.kill('SIGKILL') } catch {}
        finish()
      }, timeoutMs)
      child.on('error', finish)
      child.on('close', finish)
      if (child.stdin) {
        child.stdin.on('error', () => {})
        child.stdin.end(JSON.stringify(payload))
      }
    })
  }

  /**
   * Queue one report; `build` makes its payload when its turn comes. Returns
   * false when the report was dropped because the queue is full.
   */
  function report(event, build) {
    if (pending >= MAX_PENDING && !TERMINAL.has(event)) return false
    pending++
    chain = chain
      .then(async () => run(event, await build()))
      .catch(() => {})
      .finally(() => { pending-- })
    return true
  }

  /** Wait for the queue, at most `ms`; then stop what still runs. */
  async function drain(ms = DRAIN_MS) {
    await withTimeout(chain, ms)
    for (const child of children) {
      try { child.kill('SIGKILL') } catch {}
    }
  }

  return { report, drain, get pending() { return pending } }
}

/**
 * Mount the listeners.
 * @param ctx - the Cordis context.
 * @param config - `{ command, harness?, coalesce? }` from the bundle row;
 *   `harness` defaults to DSH_KITTY_PERSIST_HARNESS, which the fleet wrapper
 *   exports per hand-run profile (`dsh-<profile>`).
 * @param env - the process environment (a test passes its own).
 * @param spawnImpl - node:child_process spawn, or a test double.
 */
export function apply(ctx, config = {}, env = process.env, spawnImpl = spawn) {
  // Outside a kitty-persist session the hook would exit at once: spawn nothing.
  if (!env.KITTY_PERSIST_ID) return
  const harness = config?.harness ?? env.DSH_KITTY_PERSIST_HARNESS
  const command = config?.command ?? 'kitty-persist'
  if (typeof harness !== 'string' || !HARNESS.test(harness) || !validCommand(command)) {
    ctx.logger?.debug?.('kitty-persist-hooks: no valid harness name or command; not reporting')
    return
  }
  // `coalesce: false` sends every tool result (checks.kitty-persist-dsh-hooks
  // uses it to see each event dsh emits).
  const coalesce = config?.coalesce !== false
  const reporter = createReporter({ command, harness, env: hookEnv(env), spawnImpl })
  // session id -> { session, transcript, last, ended }
  const sessions = new Map()

  async function transcriptOf(entry) {
    if (entry.transcript !== undefined) return entry.transcript
    try {
      const persistence = ctx.get?.('sessionPersistence')
      const snapshot = await withTimeout(persistence?.stat?.(entry.session.header.id), STAT_TIMEOUT_MS)
      const path = snapshot?.location?.path
      if (typeof path === 'string' && isAbsolute(path)) entry.transcript = path
    } catch {}
    return entry.transcript
  }

  function send(entry, event, extra = {}) {
    if (entry.ended) return
    if (coalesce && event === EVENTS.toolResult && WORKING.has(entry.last)) return
    entry.last = event
    if (event === EVENTS.sessionEnd) entry.ended = true
    const header = entry.session.header
    reporter.report(event, async () => {
      const payload = {
        hook_event_name: event,
        session_id: header.id,
        cwd: typeof header.cwd === 'string' ? header.cwd : process.cwd(),
        ...extra,
      }
      const transcript = await transcriptOf(entry)
      if (transcript !== undefined) payload.transcript_path = transcript
      return payload
    })
  }

  const entryOf = session => (isRoot(session) ? sessions.get(session.header.id) : undefined)

  // Serial and awaited by dsh: return at once, never a pending promise.
  ctx.on('agent/created', ({ agent, source } = {}) => {
    const session = agent?.session
    if (!isRoot(session)) return undefined
    const entry = { session, transcript: undefined, last: undefined, ended: false }
    sessions.set(session.header.id, entry)
    send(entry, EVENTS.sessionStart, typeof source === 'string' ? { source } : {})
    return undefined
  })

  ctx.on('session/event', (session, event) => {
    const entry = entryOf(session)
    if (entry === undefined) return
    switch (event?.type) {
      case 'turn/start': send(entry, EVENTS.turnStart); break
      case 'tool/result': send(entry, EVENTS.toolResult); break
      case 'approval/asked': send(entry, EVENTS.approvalAsked); break
      case 'approval/decided': send(entry, EVENTS.approvalDecided); break
      case 'turn/end': {
        const word = turnEndEvent(event.data?.reason)
        if (word !== undefined) send(entry, word, { reason: String(event.data?.reason?.kind ?? 'completed') })
        break
      }
    }
  })

  // A pass-through answerer: it reports around whoever answers, and answers
  // nothing itself.
  ctx.on('user-questions/request', async (request, next) => {
    const entry = entryOf(request?.agent?.session)
    if (entry === undefined) return next()
    send(entry, EVENTS.questionAsked)
    try {
      return await next()
    } finally {
      send(entry, EVENTS.questionAnswered)
    }
  })

  ctx.on('agent/disposed', ({ agent } = {}) => {
    const entry = entryOf(agent?.session)
    if (entry !== undefined) send(entry, EVENTS.sessionEnd)
  })

  // A one-task run ends by disposing the whole tree; whichever of
  // agent/disposed and this disposer comes first, the end is reported once,
  // and the queue gets DRAIN_MS to finish.
  ctx.effect(() => () => {
    for (const entry of sessions.values()) send(entry, EVENTS.sessionEnd)
    return reporter.drain()
  }, 'kitty-persist-hooks: report the end and drain')
}
