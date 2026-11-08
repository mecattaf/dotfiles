# Everyday Claude and Codex launchers

`agency-kitty harness claude|codex -- ORIGINAL_ARGUMENTS` adds lifecycle hooks
to one managed NAS terminal invocation and exits through exec. There is no
keyboard relay, terminal output watcher or recurring status timer. In an
unmanaged terminal it invokes the original binary with the original arguments.
A stale managed PTY fails before the harness starts.

The dotfiles fish launchers select this path only when a managed session and
the installed helper are present. `cc`, `cac`, `cc2`, `cac2`, `cx` and `cax`
retain their existing arguments. Personal Claude explicitly clears inherited
`CLAUDE_CONFIG_DIR`; work Claude retains its separate directory. Starting
Claude from home still moves into the configured desk envelope. Model, effort,
credential locations and existing permission choices remain the caller's.

Claude receives additional `--settings` JSON containing only hook arrays.
These compose with its seat and project settings. Codex receives an additional
session-flag layer containing its own hook declarations and exact trust hashes
for those four declarations. It does not write user/project configuration,
replace their hook arrays, trust other hooks or use
`--dangerously-bypass-hook-trust`. The current official documentation describes
[additive hook layers and declaration trust](https://learn.chatgpt.com/docs/hooks),
and [Claude's settings composition](https://code.claude.com/docs/en/settings#lists-merge-instead-of-overriding).

The hash algorithm is source-qualified against actual Codex0.167.0 and the
earlier0.163.0 implementation: normalized command, event, three-second timeout
and synchronous mode become canonical sorted JSON through TOML, then SHA-256.
Only the exact invocation-layer source keys receive those hashes. In Nix,
changing the helper changes its immutable store path and therefore changes its
declaration hash. All existing user/project hook trust and explicit enablement
settings still participate in Codex's normal policy.

There are two deliberately distinct kinds of state. `SessionStart` binds the
exact transcript and `SessionEnd` unbinds it. `UserPromptSubmit` reports
`working`; `Stop` reports `done`; Claude's relevant permission/idle/elicitation
notifications report `waiting`. Terminal exit never means a completed turn.
These events contain identities and state only. They do not copy the prompt,
model response or tool output. Imagine/DSH owns notification and sound policy.

Actual offline TUI proofs on Strix use Codex0.167.0 and Claude2.1.319 with
private credential/config bindings, private loopback model fixtures and no
provider calls. Both preserve existing user lifecycle hooks while the scoped
launcher adds its own start/working/stop/end signals. Image pasting attaches
without submitting, actual mock-model requests contain the image, and exact
saved transcripts export beyond the viewport. The Codex fixture also keeps a
deliberately unrelated hook untrusted: the private test explicitly skips its
review, and the marker it would write never appears. This does not automate
trust review for a user's unrelated hooks.

The real fish routing gate executes only extracted, inspected functions under
`runtime-test`. All twelve managed/unmanaged launcher cases preserve argument
boundaries, home-directory behavior, seat isolation and continuation flags.
No full shell configuration is sourced. Receipts are in
`docs/evidence/harness-launch/`; original private fixture directories remain
on compute for inspection. These gates measure behavior, not physical latency.
