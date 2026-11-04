# @substrate/runners

Where one agent() call (or one Worker-shaped job) actually runs. The interpreter
owns the script, the journal and retries; CONWIP owns admission; a runner owns
one attempt in one runtime and reports exit code, stdout and stderr, or a refusal.

## Configure (the whole user-facing surface)

One TOML file, `~/.config/substrate/runtimes.toml` (or `AX_CONWIP_RUNTIMES`).
No file means every call runs on `host`. `substrate-runners example` prints a
commented one (`runtimes.example.toml`); `substrate-runners check` says which
runtimes are ready here and why the others refuse.

```toml
default = "gvisor"                 # runtime for calls that name none
[phases]
"Review" = "herdr"                 # per-phase default, by phase title
[credentials]
claude = "~/.claude"               # mounted into sandboxes, never copied
mode = "rw"
[runtime.gvisor]
type = "gvisor"
runsc = "/nix/store/...-gvisor-20260406.0/bin/runsc"
```

Per call: `agent(prompt, { runtime: "gvisor" })`. Order: call, phase, default, `host`.
`ssh:<host>` needs no table.

**Models are runtime data** (2026-10-10). `models_file = "~/.config/substrate/models.toml"`
names a TOML file of `[[models]]` tables (id, harness, provider, aliases, default, ceilings,
and for pi an optional `[models.pi]` table describing a model pi's catalog does not know).
The runners re-read it on every call, so a model changes with an edit, no restart or rebuild.
A pi provider with no entry is parked: its runtime is refused at the route ("no model
configured"), and a route policy falls through at once. A file that stops parsing refuses every
call with the error. Precedence: `models_file`, inline `[[models]]`, the compiled default.
Host-side pi jobs save their session in the job's shadow (`--session-dir`), archived with the
transcripts so the seats oracle counts factory spend.

**DSH and Gufo** (2026-10-28). The fleet's local runtime is `type="host"`,
`harness="dsh"`, `provider="gufo"`, `seat="gufo"`. DSH runs locally and its
fleet launcher calls Gufo on compute. The runner generates a native headless composition,
keeps a private `dsh-home/` alongside the session cwd, requires its project MCP before
starting inference, and limits coordinator tools to read plus project operations. DSH
reports its own first id; `--session-id` adopts it on later turns. A missing pinned
history or an old session pinned to pi is refused. See [rollout](../../docs/dsh-rollout.md).

**Agent sessions** (2026-10-12). `agent(prompt, { session: {id, harnessSessionId, cwd?, role, harness?} })`
is one turn of an agent session: the harness session is resumed by id (claude `--session-id`, then
`--resume`; pi `--session-id`; codex `exec resume`, built and tested with a fake only) in
`<transcript root>/sessions/<id>/`, whose `cwd/` is the session's cwd on every turn, with the one
`project` MCP that `[sessions]` names (`project_bin`, `project_url`, `project_token_file`). The
session file stays where the harness writes it; the receipt and the outcome name its path.

| type | runs | notes |
|---|---|---|
| `host` | child process | baseline, no isolation |
| `herdr` | herdr plugin action (default) or a visible pane | only its own workspaces; `substrate-runners herdr-link` once per server |
| `gvisor` | `runsc run` on a generated OCI bundle, rootless | `--root` under `~/.local/state`; ro root and store; job dir rw at /work |
| `microvm` | microvm.nix `declaredRunner`, built per job shape | boots only with `/dev/kvm` inside runtime-test; else a clear refusal |
| `ssh` | `ssh <host>` | remote seat; `harness = "pi"` for pi on the remote host |
| `workerd` | `workerd test` | Worker-shaped jobs only; agent() is refused |
| `ax` | nothing | writes the FIELD-MAP Task it would send |

## Check

`pnpm test`, `pnpm typecheck`, `pnpm fences`; live: `scripts/live-checks.ts` (see its header).
