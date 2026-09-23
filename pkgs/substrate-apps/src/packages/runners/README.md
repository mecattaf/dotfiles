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

| type | runs | notes |
|---|---|---|
| `host` | child process | baseline, no isolation |
| `herdr` | herdr plugin action (default) or a visible pane | only its own workspaces; `substrate-runners herdr-link` once per server |
| `gvisor` | `runsc run` on a generated OCI bundle, rootless | `--root` under `~/.local/state`; ro root and store; job dir rw at /work |
| `microvm` | microvm.nix `declaredRunner`, built per job shape | boots only with `/dev/kvm` inside runtime-test; else a clear refusal |
| `ssh` | `ssh <host>` | remote seat; `harness = "pi"` for Halogen on the worker |
| `workerd` | `workerd test` | Worker-shaped jobs only; agent() is refused |
| `ax` | nothing | writes the FIELD-MAP Task it would send |

## Check

`pnpm test`, `pnpm typecheck`, `pnpm fences`; live: `scripts/live-checks.ts` (see its header).
