// herdr-guard: the dotfiles gate in front of @dsh-external/dsh-herdr-toolkit.
// Plain ESM, no imports. dsh-herdr injects the `herdrGuard` service this
// plugin provides, so its tools stay pending unless this guard is mounted.
//
// Policy, checked in this order:
// - any id that is not a herdr public id, or a cwd that is not absolute: deny
//   (stops flag injection such as pane: "--current");
// - reads and waits: allow, on any pane (the CLI timeout bounds the waits);
// - writes need HERDR_ENV=1 (dsh itself inside a Herdr pane), else deny;
// - pane_run and agent_start: only on panes this process created, else deny;
// - every other write: ask, which headless (no answerer) turns into a deny;
// - an unknown _dsh_herdr_ tool: deny.
export const name = 'herdr-guard'
export const inject = ['tools']

const PREFIX = '_dsh_herdr_'
const READS = new Set(['workspace_list', 'workspace_get', 'tab_list', 'tab_get', 'pane_list', 'pane_get',
  'pane_read', 'pane_wait_output', 'pane_layout', 'pane_process_info', 'pane_edges', 'doctor',
  'agent_list', 'agent_get', 'agent_explain', 'agent_read', 'agent_wait'])
const ASKS = new Set(['workspace_create', 'tab_create', 'pane_split', 'agent_prompt'])
const OWN_ONLY = new Set(['pane_run', 'agent_start'])
const CREATES = new Set(['workspace_create', 'tab_create', 'pane_split'])

// herdr 0.9.3 numbers ids in a 32-symbol alphabet (src/workspace.rs), so w9 is
// followed by wA, not w10.
const N = '[0-9A-HJKMNP-TV-Z]+'
const IDS = {
  workspace: new RegExp(`^w${N}$`),
  tab: new RegExp(`^w${N}:t${N}$`),
  pane: new RegExp(`^w${N}:p${N}$`),
}
const AGENT = /^[a-z][a-z0-9_-]{0,31}$/
const ok = (value, test) => value === undefined || (typeof value === 'string' && test(value))

function malformed(args) {
  for (const key of Object.keys(IDS)) if (!ok(args[key], (v) => IDS[key].test(v))) return key
  if (!ok(args.agent, (v) => AGENT.test(v) || IDS.pane.test(v))) return 'agent'
  if (!ok(args.name, (v) => AGENT.test(v))) return 'name'
  if (!ok(args.cwd, (v) => v.startsWith('/'))) return 'cwd'
  return undefined
}

/** The guard's verdict for one call; undefined means "not ours, or allowed". */
export function decide(exec, owned, env = process.env) {
  if (typeof exec.name !== 'string' || !exec.name.startsWith(PREFIX)) return undefined
  const tool = exec.name.slice(PREFIX.length)
  const deny = (why) => ({ kind: 'deny', reason: `herdr-guard: ${exec.name}: ${why}` })
  const args = exec.arguments
  if (args === null || typeof args !== 'object' || Array.isArray(args)) return deny('arguments are not an object')
  const bad = malformed(args)
  if (bad !== undefined) return deny(`malformed ${bad}`)
  if (READS.has(tool)) return undefined
  if (!ASKS.has(tool) && !OWN_ONLY.has(tool)) return deny('not a tool this guard knows')
  if (env.HERDR_ENV !== '1') return deny('herdr writes need dsh running inside a Herdr pane (HERDR_ENV=1)')
  if (OWN_ONLY.has(tool) && !owned.has(args.pane)) return deny(`only on a pane this dsh created, not ${args.pane}`)
  return { kind: 'ask', reason: `herdr-guard: ${exec.name} changes Herdr state` }
}

export function apply(ctx) {
  const owned = new Set()
  ctx.on('tools/pre-execute', async (exec, next) => {
    const verdict = decide(exec, owned)
    if (verdict === undefined) return next()
    if (verdict.kind === 'deny') return verdict
    // An ask never overrides a later listener's deny or cancel.
    const downstream = await next()
    return downstream.kind === 'allow' ? verdict : downstream
  }, { prepend: true })
  // Panes this process created: herdr's `workspace_created` and `tab_created`
  // carry `root_pane`, a split's `pane_info` carries `pane`.
  ctx.on('tools/result', (exec, result) => {
    const tool = typeof exec.name === 'string' && exec.name.startsWith(PREFIX) ? exec.name.slice(PREFIX.length) : ''
    if (result.isError || !CREATES.has(tool)) return
    const created = result.value?.data?.result
    for (const pane of [created?.pane, created?.root_pane]) {
      if (typeof pane?.pane_id === 'string' && IDS.pane.test(pane.pane_id)) owned.add(pane.pane_id)
    }
  })
  ctx.provide('herdrGuard', { owned: () => [...owned] })
}
