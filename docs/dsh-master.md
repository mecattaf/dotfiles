# The Master profiles

The master agency's superagent (the `dsh-superagent` fork, Claude Opus as
its brain through dsh-claude) runs from one configuration,
`programs.dsh.master` in `home/dsh-master.nix`. DSH composes its app from
the bundles a profile lists, and dshd takes one transport per profile, so
`pkgs/dsh-master` renders that one source as one folder per transport and
pair:

| Profile | App | `dsh-superagent.engine` | Runs |
|---|---|---|---|
| `master` | `dsh-web-app` | `true` | the `floor` dshd instance: the superagent, its main Session, the panel on 127.0.0.1:3082 |
| `master-opus` | `dsh-headless` | `false` | one worker per dshd unit, Claude Opus at medium effort (the default pair) |
| `master-gufo` | `dsh-headless` | `false` | one worker per dshd unit, Gufo `qwen3.8-flash-next`, one at a time |

The folders are `~/.dsh/profiles/master*`. No other profile folder and no
`~/.dsh/cordis.patch.yml` is written: that home layer would change every
profile of the home. Scheduled items, which wake this floor, are in
[scheduled.md](scheduled.md).

## The three folders

Rules the renderer keeps, each asserted by `checks.dsh-master`:

- Every folder lists the same dependencies and the same non-app bundles
  (base, dsh-claude, dsh-superagent). No folder lists both apps: the headless
  layer turns authorization off for the whole tree.
- The fleet policy (`pkgs/dsh/config.nix`) is in each folder's own
  `cordis.patch.yml`, because dshd runs the unwrapped dsh and never gets the
  wrapper's overlays. The sandbox, permission and approval rows are left out:
  workers run with full permissions, and the superagent needs the stock
  `danger-full-access` preset.
- The `dsh-superagent` row is the same in every folder but for `engine`
  ([The engine key](#the-engine-key)).
- Every Claude process goes through `llm-claude.executablePath`, a wrapper
  that sets `CLAUDE_CONFIG_DIR` to the cc2 seat
  (`programs.dsh.master.claudeConfigDir`). Workers get the same value in
  their dshd recipe (`dshd.env`), and Gufo workers get the public dummy
  `GUFO_API_KEY` from their pair row.
- dsh headless binds no agent preset, so a worker folder inserts the preset
  registry and, for a pair with a `preset` (`claude` for a Claude pair),
  dsh-claude's `headless-preset` binder. A pair of another provider binds
  none: the `claude` preset sends every request to Claude Code, and a Gufo
  worker under it fails its first turn.
- Both plugins are pinned to one release tag, `programs.dsh.master.tag`
  (`floor-v2.<n>`, first `floor-v2.1`). `superagent` or `claude` overrides
  one pin on its own.

## Pairs

A pair is a provider and a harness, and it is a folder: `dsh headless`
takes its model from the profile, not from a flag. Adding a pair is one
attribute in the host's Home Manager configuration:

```nix
programs.dsh.master.pairs.sonnet = {
  provider = "claude";
  model = "sonnet";          # a dsh-claude catalog id, so it is never rewritten
  reasoningEffort = "low";   # null for a model that declares none
  # env = { };               # public values only: each unit's recipe records them
  # maxWorkers = 2;          # at most this many units of this pair at once
};
```

After the switch, activation renders `~/.dsh/profiles/master-sonnet` and
prints `install needed: master-sonnet`; run `dsh-master install
master-sonnet`, then `dsh-master check`. The `master` folder's
`dsh-superagent.dshd.pairs` gains `sonnet`, so restart the floor
(`dshd restart floor`) for the superagent to know it.

How a Ticket picks its pair:

| Work | Pair |
|---|---|
| A scheduled occurrence | always `defaultPair`: an item has no pair key |
| A workflow run | the `pair` the start request names, for every node of the run; else the workflow row's `pair` (empty in Master); else `defaultPair` |
| A node's `agent(…, { model })` | recorded, not used: nodes run on their run's pair |

`defaultPair` (`opus`) is one option; changing it re-renders `master`
and every `agent-default-model` row that follows it. Pair names match
`^[a-z0-9][a-z0-9-]*$`, and `web` and `master` are not pair names.

## The engine key

The fork's own Schema has `engine` on the `dsh-superagent` row. The
renderer writes `engine: true` in `master` and `engine: false` in every
`master-<pair>`, and nothing else differs in that row. A worker mounts the
plugin with its extensions, so the extension set is the same everywhere,
but with the engine off it builds no orchestrator: no state, no lock, no
main Session, no environment change, and the fork's Sources never apply.
Only the floor turns the superagent on.
`programs.dsh.master.superagentConfig` adds fork Schema keys to the row of
every folder and may not set `engine` (an assertion says so).

## Commands

Activation runs `dsh-master render --quiet`. It copies the rendered files
into `~/.dsh/profiles/master*` when they differ, says when a copy was
changed by hand, and never runs pnpm. The three files are `package.json`,
`cordis.patch.yml` and `pnpm-workspace.yaml`. The last is the text dsh
writes for a new profile plus `allowBuilds` from
`programs.dsh.master.allowBuilds` (default `msgpackr-extract: false`). pnpm 11
otherwise ends every install with `ERR_PNPM_IGNORED_BUILDS` and exit 1, because
the fork's interpreter pulls in msgpackr's optional native build. A build
approval made in DSH's plugin manager is replaced at the next render, with the
"changed outside dsh-master" line: a build decision belongs in that option.
A failed render does not fail the switch, so check `dsh-master status`
after one; it adds `builds pending: <names>` for a build DSH's plugin
manager recorded as undecided. Until `install` has recorded the folder's
current `package.json`, every render prints `install needed: <p>`.
The other steps are by hand:

```sh
dsh-master render            # what activation does, with a line per file
dsh-master install [P...]    # pnpm install per folder, through the dsh dshd runs
dsh-master check [P...]      # --dump-config per folder: every rendered row, no patch warning
dsh-master status            # per folder: rendered current|stale, installed current|no, node_modules present|absent; exit 1 if not all current
dsh-master settings seed [FILE] [--url U]   # once, after the floor's first start; U defaults to http://127.0.0.1:<webPort> (3082)
```

Every verb takes `--from DIR`, a `nix build .#dsh-master` result, in
place of the installed build; `install` and `check` take `--dsh PATH` to
run another dsh than the one dshd runs.

`install` runs `/etc/dshd/releases/default/bin/dsh plugin --profile <p>
install` under a 600 s timeout, with pnpm and git on PATH, and then judges
the folder, not the exit: `package.json` unchanged, a lockfile whose
specifier for each dependency is the one in `package.json`, and a built
`lib/` for each dependency. An earlier install's lockfile and `lib/` do not
count, and a dsh that never ran (exit 125 to 127) fails whatever the folder
holds. Without the folder's `pnpm-workspace.yaml` pnpm would pull the
plugins' DSH peers from the registry, so install refuses a folder whose
three files are not the rendered ones. The fleet wrapper refuses `dsh
plugin`. Stop the floor before installing into `master` (`dshd stop floor`,
install, `dshd start floor`); a worker folder is read when each unit boots,
so install it while none of its units runs. install checks this: it asks
`dshd ls` and `dshd get` and refuses a profile that a running instance of
this DSH_HOME uses, unless `--force`.
Until every folder is installed at its rendered pins, `dsh-master status`
exits 1; it also lists `master*` folders no build renders (a removed pair)
as orphans, which fail nothing.

`settings seed` reads the floor's Store settings through its management API,
upserts the rules and admission cells of `home/dsh-master/settings.seed.json`
(the Scheduled and Workflow node rules), raises `eval.mode` to `auto`, and
saves each changed block with its revision. It never lowers a mode, and an
`eval.mode` of `off` stays off. It prints `unchanged` or `changed <blocks>`.
Settings live in `orchestrator.sqlite`, so a seeded floor keeps them across
restarts; seed again only after the state directory was replaced.

Each seeded rule has two readers. The floor's main Session assesses Triggers
by it, and dsh-superagent copies a matched rule verbatim into the worker's
brief, where its procedure takes precedence. A headless dshd worker has no
orchestrator tools, so each rule describes its Triggers, then says `If you
are assessing it:` what the main Session does, and ends with the same
sentence for the worker: do the task in the trigger text in the current
folder, and the final message is the result. The description also settles the
three direction facts that dsh-superagent requires before an accept
dispatches: whose implementation request the Trigger is, what its target is,
and that it needs no design decision. Without them an accept is recorded as
`ignore directionUnsettled`. `checks.dsh-master` asserts that shape and keeps
each rule within 1000 characters.

Before a switch, `nix build .#dsh-master -o result-dsh-master` gives the same
bytes activation will render, and `result-dsh-master/bin/dsh-master render`
installs them early. Keep that out-link until the switch: the rendered files
name the seat wrapper's store path.

## The floor instance

Created once, by hand, after `dsh-master install` and `check` pass:

```sh
env -i HOME=/home/tom USER=tom LOGNAME=tom LANG=C.UTF-8 \
  PATH=/run/current-system/sw/bin:/etc/profiles/per-user/tom/bin \
  XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
  DSH_TELEMETRY_DISABLED=1 CLAUDE_CONFIG_DIR=/home/tom/.claude-work \
  /run/current-system/sw/bin/dshd run --bg --json --name floor --cwd /home/tom \
    --label superagent.role=floor -- master
```

No `--patch`: the profile carries the policy. dshd needs the user bus
(`XDG_RUNTIME_DIR`, `DBUS_SESSION_BUS_ADDRESS`) to reach systemd and exits 7
`systemd-unavailable` without it; neither name is recorded in the instance's
`environmentNames`. The name stays `floor`, which the heartbeat addresses.

After that, the instance is driven by name:

| Command | When |
|---|---|
| `dshd start floor` | to open the panel or give it work; the heartbeat also starts it when records wait |
| `dshd stop floor` | to quiet it; running worker units go on, and the floor adopts them at its next start |
| `dshd restart floor` | after a render changed `master` (a new pair, a new tag after install) |
| `dshd enable floor` | to start it with the user manager after a reboot; off by default, since the heartbeat wakes it |
| `dshd get --json floor` | its state, recipe and last run |
| `journalctl --user -u dshd@floor.service` | its log |

The superagent's state is `programs.dsh.master.stateDir`
(`~/.agency/state/master`): `orchestrator.sqlite` with the Tickets,
Decisions, settings and workflow journals, the lock `master.lock` beside
the directory, and the Scheduled inbox `inbox/scheduled/`.

The panel's management API (`/orchestrator/api`) takes no token: its only
checks are the loopback bind, the `Host` header and
`x-orchestrator-request: 1`. Port 3082 therefore grants control equal to
the owner's own shell, to any local uid on the NAS and, through the panel
tunnel, to any local process on the Zenbook. That control can rewrite the
superagent's prompts and policy and retry or stop Tickets, and the
superagent launches full-permission workers.

## The panel

```sh
dshd start floor && dshd attach floor          # prints the origin, http://127.0.0.1:3082
dshd attach --print-url floor                  # the full URL with its token, for a new browser
```

From the Zenbook, `scheduled-panel-tunnel` (`home/scheduled.nix`) forwards
the NAS's 127.0.0.1:3082 to the Zenbook's 127.0.0.1:3082, so the same URL
opens there. Open **Superagent** in the sidebar:

| Tab | Read it for |
|---|---|
| Overview | what needs a person now, and the Executor's load |
| Trigger | one Thread per scheduled occurrence and per workflow node (`<workflow> · <label>`), with its Decisions |
| Eval | each Decision with its reason and the rule it matched |
| Execution | Tickets: open, pending, working, ended; each Assignment is one dshd unit |
| Settings | the rules and admission cells `settings seed` wrote, and Execution's `maxWorkers` |

The main Session is the DSH Session titled `dsh-superagent orchestrator`
in the web app's session list. Under the plugin renderer dsh-web shows
only its closing prose, not Claude's activity rows.

## Workflows

A workflow script is an ultracode-style JavaScript file anywhere on disk,
usually in the agency it works on. Each `agent()` call is a node, and
each node runs as one Ticket, one dshd unit in the run's directory:

```js
// ~/work/acme/release-notes.workflow.js
export const meta = {
  name: 'release-notes',
  description: 'Collect the week\'s merged changes, then write the notes',
  phases: [{ title: 'collect' }, { title: 'write' }],
}
phase('collect')
const [api, web] = await parallel([
  () => agent('List the pull requests merged this week in ./api, one line each. Change nothing.', { label: 'api' }),
  () => agent('List the pull requests merged this week in ./web, one line each. Change nothing.', { label: 'web' }),
])
phase('write')
const notes = await agent(`Write RELEASE-NOTES.md from these lists:\n${api}\n${web}\nReply with {"path": <the file>}.`, {
  label: 'notes',
  schema: { type: 'object', required: ['path'], properties: { path: { type: 'string' } } },
})
log(`release-notes: ${notes?.path}`)
return notes
```

- The builtins are `agent(prompt, { label, phase, schema })`,
  `parallel([...thunks])`, `pipeline(items, ...stages)`, `phase(title)`,
  `log(text)`, `args` (the start request's `args`) and `workflow(ref,
  args)`, one level deep.
- A node's result is its worker's final reply, verbatim; with a `schema`
  it is parsed as one JSON value. A node that fails, or replies without
  the JSON its schema asks for, is `null`, and the run goes on.
- `Date.now()`, argless `new Date()` and `Math.random()` throw: a resumed
  run must make the same calls. Pass a date in `args`.

**Start a run** by asking the superagent, naming the script and the
directory. Its main Session calls `orchestrator_workflow_start` with
`script` (absolute, or relative to `cwd`), `cwd` (absolute, an existing
directory every node works in), and optionally `args`, `pair` and
`trigger_id`. Two ways to ask:

- A scheduled item whose prompt is the request, run now with
  `scheduled run` or on its cron; the prompt pattern is in
  [scheduled.md](scheduled.md#starting-a-workflow-from-an-item). This is
  the path the live rehearsal exercises.
- A message to the main Session in the web app, such as "Run
  /home/tom/work/acme/release-notes.workflow.js in /home/tom/work/acme on
  the gufo pair". This path has not yet been exercised end to end.

**Check a run** by asking the main Session for its status:
`orchestrator_workflow_status` with a `run_id`, or none for the newest
runs, lists each node as `waiting`, `offered`, `held`, `ticket`, `done`
or `null`, with its Trigger and Ticket. The panel shows each node's
Thread and Ticket, and `dshd ls` its unit (labels `superagent.run` and
`superagent.node` in `dshd get --json <unit>`). The journal reads back
without writing:

```sh
sqlite3 -readonly ~/.agency/state/master/orchestrator.sqlite \
  "SELECT value FROM kv WHERE key LIKE 'workflow-journal:<run>:%' ORDER BY key"
```

**A window, not a gate.** The next node proceeds by default: the
`workflow-node` rule accepts it. When woken, the superagent may hold
pending nodes and choose what to accept now, but it never stops a running
Ticket to reorder work:

| To | Ask the superagent to | Mechanism |
|---|---|---|
| Let it run | nothing | the rule accepts each node; accepted work launches oldest first under `maxWorkers` |
| Hold a node | hold node `<label>` of run `<id>` | the node's Trigger is ignored with a reason that starts `hold:`; the node and its run wait, nothing is skipped |
| Release it | release node `<label>` | `orchestrator_trigger_requeue` puts the same Trigger in a fresh Eval |
| Put other work first | run that first and hold the rest | accept the other work now, hold the nodes |

A node whose Eval got no answer waits as a held one does, shown `held`,
until it is released. A floor restart resumes every unfinished run from
its journal: a finished node never runs again, and a running node's unit
goes on and is adopted.

Not supported: token budgets, a node's `model` or `effort` (the run's
pair decides), nesting deeper than one `workflow()`, and a `workflow`
key in a scheduled item.

## Starting state

As commissioned, the floor is stopped and not enabled, its settings are
seeded, and every item under `~/.agency/scheduled/` is `enabled: false`
(the items are placed by step 4 of the commissioning order in
[scheduled.md](scheduled.md#commissioning-order)).
Nothing runs until one of these:

```sh
scheduled run master:<item>                 # one item now; the heartbeat path starts the floor
scheduled set master:<item> enabled true    # arm an item
dshd start floor && dshd attach floor       # the panel, and the main Session to ask for a workflow
dshd enable floor                           # keep the floor across reboots
```
