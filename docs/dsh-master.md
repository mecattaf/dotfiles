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

Rules the renderer keeps, each asserted by `checks.dsh-master`:

- Every folder lists the same dependencies and the same non-app bundles
  (base, dsh-claude, dsh-superagent). No folder lists both apps: the headless
  layer turns authorization off for the whole tree.
- The fleet policy (`pkgs/dsh/config.nix`) is in each folder's own
  `cordis.patch.yml`, because dshd runs the unwrapped dsh and never gets the
  wrapper's overlays. The sandbox, permission and approval rows are left out:
  workers run with full permissions, and the superagent needs the stock
  `danger-full-access` preset.
- The `dsh-superagent` row is the same in every folder but for `engine`. A
  worker mounts the plugin without its orchestrator: no state, lock, Session
  or environment change, and the fork's Sources never apply.
- Every Claude process goes through `llm-claude.executablePath`, a wrapper
  that sets `CLAUDE_CONFIG_DIR` to the cc2 seat. Workers get the same value in
  their dshd recipe (`dshd.env`), and Gufo workers get the public dummy
  `GUFO_API_KEY` from their pair row.
- A pair is a folder: add one to `programs.dsh.master.pairs` and it renders
  `master-<name>`. `defaultPair` picks the pair of a Ticket whose Trigger
  names none.
- dsh headless binds no agent preset, so a worker folder inserts the preset
  registry and, for a pair with a `preset` (`claude` for a Claude pair),
  dsh-claude's `headless-preset` binder. A pair of another provider binds
  none: the `claude` preset sends every request to Claude Code, and a Gufo
  worker under it fails its first turn.
- Both plugins are pinned to one release tag, `programs.dsh.master.tag`
  (`floor-v2.<n>`, first `floor-v2.1`). `superagent` or `claude` overrides
  one pin on its own.

## Commands

Activation runs `dsh-master render --quiet`. It copies the rendered files
into `~/.dsh/profiles/master*` when they differ, says when a copy was
changed by hand, and never runs pnpm. A folder without `pnpm-workspace.yaml`
also gets the one dsh writes for a new profile; render never replaces it.
In that file render sets each `programs.dsh.master.allowBuilds` decision
(default `msgpackr-extract: false`) whose key is absent or that dsh left as
`set this to true or false` after a failed install. A decision already made
there, and every other key, stays. Until `install` has recorded the folder's
current `package.json`, every render prints `install needed: <p>`.
The other steps are by hand:

```sh
dsh-master render            # what activation does, with a line per file
dsh-master install           # pnpm install per folder, through the dsh dshd runs
dsh-master check             # --dump-config per folder: every rendered row, no patch warning
dsh-master status            # rendered current? installed current? node_modules?
dsh-master settings seed     # once, after the floor's first start
```

`install` runs `/etc/dshd/releases/default/bin/dsh plugin --profile <p>
install` under a 600 s timeout, with pnpm and git on PATH, and then judges
the folder, not the exit: `package.json` unchanged, a lockfile whose
specifier for each dependency is the one in `package.json`, and a built
`lib/` for each dependency. An earlier install's lockfile and `lib/` do not
count, and a dsh that never ran (exit 125 to 127) fails whatever the folder
holds. Without the folder's `pnpm-workspace.yaml` pnpm would pull the
plugins' DSH peers from the registry, so install refuses it. pnpm replaces
`lib/` and the served `client.js` in place, so install also refuses a
profile that a running dshd instance of this DSH_HOME uses (it asks
`dshd ls` and `dshd get`): stop the floor before installing into `master`.
`--force` skips that check. The fleet wrapper refuses `dsh plugin`.
`status` adds `builds pending: <names>` for a build dsh left undecided.

`settings seed` reads the floor's Store settings through its management API,
upserts the rules and admission cells of `home/dsh-master/settings.seed.json`
(the Scheduled and Workflow node rules), raises `eval.mode` to `auto`, and
saves each changed block with its revision. It never lowers a mode, and an
`eval.mode` of `off` stays off. It prints `unchanged` or `changed <blocks>`.

Before a switch, `nix build .#dsh-master -o result-dsh-master` gives the same
bytes activation will render, and `result-dsh-master/bin/dsh-master render`
installs them early. Keep that out-link until the switch: the rendered files
name the seat wrapper's store path.

## The floor instance

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
