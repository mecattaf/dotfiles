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

# Harness push rule (R5 as broadened by R11, 2026-09-20)

The claude and codex harnesses, and the tally jobs they run, may push and use
`gh` (branches, PRs, issues, comments) in `mecattaf/dotfiles`, `mecattaf/tally`,
`mecattaf/tally-ts-sdk` and `mecattaf/notes`. Every push is receipted with its
sha in the session log, so a push is always traceable to the session that made
it. Merges and the switch remain Tom's: a harness opens the PR, Tom merges it,
and `nixos-rebuild switch` is never a harness's act. No force-push and no history
rewrite without his word.
