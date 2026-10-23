# Preserve live user sessions during tests

For tests that source shell-script fragments, clean runtime directories, or
launch test compositors, use `~/.local/bin/runtime-test -- command args...`.
It gives the test a private `/run/user` tree and PID/IPC namespaces while keeping
the checkout writable. If the wrapper or bubblewrap is unavailable, do not run
that experiment against the live runtime; install the declared wrapper first
or use a disposable VM. On SSH targets, invoke the wrapper on the target too.

Never source a script fragment selected by an unbounded text range. Extract
only the intended function and inspect it before execution. A September 2026
test accidentally sourced a cleanup command and deleted the live systemd and
D-Bus sockets, disrupting Herdr attachment and Tally.

The wrapper is runtime isolation, not a full filesystem sandbox. Home, source
files, `/tmp`, and networking remain accessible. Do not suppress unexpected
coredumps or service failures. Do not restart Herdr or the whole user manager
to repair a test incident while live agent sessions must be preserved.

# NAS agent host: send compute to the Strix pair

On `nas`, keep Herdr, Claude Code, Codex and dsh sessions and their credentials
local. Nix uses SSH builders `strix-coordinator` and `strix-worker` with zero
local build jobs. Do not override that setting or fall back to a NAS build.
Evaluate on NAS when useful; compile and run memory/GPU-intensive jobs on
compute. Before every `nix build`, check `df -h /` on the build host and stop
if it has less than 25 GB free.

For other heavy commands, use `fleet-exec strix-coordinator --cwd
/absolute/remote/checkout -- command args...` (or `strix-worker`). Stage the
needed checkout and non-secret inputs there first. The helper preserves argv,
requires a known SSH host key and never falls back locally. It does not copy
credentials, forward an SSH agent or make a remote checkout for you. Keep
interactive harness sessions on NAS; offload their commands. Run any remote
runtime-sensitive test through `~/.local/bin/runtime-test -- ...` on that
compute host too.

The local inference API is Gufo at `http://strix-coordinator:8731`, served model
`qwen3.8-flash-next`; `utility-model` forwards a request there. NAS runs no model
server. Dual-host Gufo/RDMA qualification and the shared control token belong
to the compute cutover; do not claim them from a successful client build.
