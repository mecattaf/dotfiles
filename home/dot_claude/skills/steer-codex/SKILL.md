---
name: steer-codex
description: Orchestrate codex CLI agents as the sole writer on a multi-wave build while you act as judge, not implementer. Use when driving a long build/refactor sequence through codex exec, when a handoff says "codex writes all code", when running detached codex sessions that outlive a tool timeout, or when you need to objectively accept/reject work an AI agent claims is done. Covers yolo mode (--dangerously-bypass-approvals-and-sandbox), reasoning-effort tiers, brief authoring, stall recovery via resume, and cross-model audits.
---

# Steering codex agents

You are the orchestrator. **Codex writes all code. You write none.** Your job is to brief
precisely, judge objectively, and drive a sequence to completion. Your value is being a
*different model* reading the same artifacts — not being a second implementer.

## 1. Mechanism

Use `codex exec` directly. Never the Codex plugin for Claude Code — it speaks JSON-RPC to
`codex app-server` and hardcodes `sandbox: workspace-write | read-only` with no bypass, so
network-dependent and remote-builder gates fail.

```bash
setsid nohup codex exec --dangerously-bypass-approvals-and-sandbox "$(cat brief.md)" \
  > run.log 2>&1 < /dev/null &
```

**Yolo mode.** `--dangerously-bypass-approvals-and-sandbox` gives full disk + network with
no approval prompts. It is correct here and not a shortcut: gates like
`nix flake check --builders 'ssh://host'`, remote builds, and live multi-host scenarios
cannot run sandboxed. The user's machine is the sandbox. Confirm the user already runs
codex this way before assuming the authority.

Always `setsid nohup ... < /dev/null &`. A foreground call caps at ~10 minutes; heavy waves
run 1–2 hours. Redirect stdin from `/dev/null` or codex may block reading it.

**Verify cwd.** `codex exec` runs where it is invoked. Shell cwd persists between tool
calls — check the log's `workdir:` line rather than assuming. Kill by exact PID, never
`pkill -f "codex"`; the user likely has interactive codex sessions running.

## 2. Reasoning effort and model

Valid `model_reasoning_effort` values (confirmed from the API's own enum error):
`none, minimal, low, medium, high, xhigh, max`.

Check `~/.codex/config.toml` first. If it already pins e.g. `model = "gpt-5.6-sol"` and
`model_reasoning_effort = "max"`, **keep briefs lean and pass no `-m` or effort flags** —
the config already selects the strongest configuration and flags only risk overriding it
downward. Override per-run only to go *cheaper* on mechanical work:
`-c model_reasoning_effort=low`.

Also check `[projects."<path>"] trust_level = "trusted"` for the repo.

## 3. Polling

Poll coarsely. Never sit in a tight loop watching a log — that is pure wasted budget.
Prefer a process-exit watcher over timed polling:

```bash
while kill -0 <PID> 2>/dev/null; do sleep 60; done; echo EXITED; git log --oneline -3
```

## 4. Briefs

One brief per genuinely new unit of work. A good brief carries:

- **The spec by reference**, not retyped: "your spec is `SPEC.md` §4, implement exactly that".
- **A resume check**: `git log --oneline`, `git status`, then the state file — "assume no
  conversational context survived."
- **Precedence**: which file wins when documents disagree.
- **Explicit negative scope.** Name what must *not* be built and say **absence is the
  correct implementation** — no placeholder branches, feature flags, or reserved enum
  slots. "Rejecting an unknown option because it was never declared is the mechanism."
- **Protected files by hash**, so drift is detectable.
- **The exact evidence gate**, command by command.
- **The honesty law**: "a gate you could not run is recorded as NOT RUN, never as passed."
- **The exact commit subject.**

**Never ask codex whether it finished, and never mention handoffs or context limits in a
brief.** Prompting about them invites them.

**Inoculate against contaminated prose.** If the repo contains frozen docs that predate a
scope cut, enumerate the contaminated lines *in the brief*. Also check what codex reads
*first* — a stale "next-session handoff" paragraph at the bottom of a state file is read
during the resume check, before it ever reaches your correction. Name it explicitly.

## 5. Judging — the crux

**Completion is judged from artifacts. Codex's closing prose is not evidence.** A wave is
done only when: the commit exists under the prescribed subject, the state file marks it DONE
with pasted evidence, and **you re-ran the cheap gates yourself**.

Re-run them. Do not trust pasted output — not because codex lies, but because a run can get
a *lucky pass*. A test that fails 50% of the time will paste a genuine PASS.

Cheap and worth always re-running: `fmt --check`, `clippy -D warnings`, the test suite,
no-stubs greps, protected-file hashes, and any golden/regression oracle.

**Repetition for flakes.** A flaky test is only proven fixed by repetition — demand 10
consecutive clean full-suite runs, and verify them yourself.

**Interrogate green gates.** A gate can pass vacuously: a remote-builder check that builds
nothing on a cache hit (`running 0 flake checks`) proves only that the store was warm. A
VM test that manually starts the unit it claims fires automatically proves nothing. Ask of
every passing gate: *would this fail if the behavior were absent?*

## 6. Cross-model audit — where your tokens belong

Spend Claude tokens in three places only:

1. **A scope-law audit after the highest-risk wave.** Do this with a Claude subagent, never
   codex — codex auditing its own transcription of forbidden prose is exactly the blind spot.
2. **Verifying pasted evidence at gates.**
3. **Work outside codex's context fence** (e.g. a separate dotfiles repo).

Make the audit subagent **read-only** and adversarial. Give it: the exact diff range, the
struck list, the required surface, and explicit "verify against code, not against comments,
commit messages, or the state file." Ask for a PASS/FAIL verdict with file:line citations.

Expect two flavors of contamination. A scope-correction list catches forbidden *features*.
It does **not** catch prose prescribing *mechanisms that don't work* — those transcribe in
good faith and pass every scope check. Audits must test behavior, not just scope.

## 7. Rejection and stalls

- **On a stall, resume — never re-brief.** `codex exec resume --last "<pointed note>"`
  continues the thread with context intact. Re-briefing a half-finished wave causes
  double-applied edits and a dirty tree.
- **On a rejection, resume with the findings**, itemized and prioritized, marked BLOCKING vs
  MUST FIX vs RECORD-DO-NOT-BUILD.
- **Some findings must not be fixed.** If closing a finding requires building deferred or
  forbidden scope, say so explicitly and have it *recorded as a known limitation* instead.
  Fixing an audit finding by violating the scope law is the failure the audit exists to
  prevent.
- If nothing is pushed, amend to keep one-commit-per-wave. Check with
  `git merge-base --is-ancestor origin/main HEAD` before assuming.

## 8. Hard rules

- **Sole writer. No wave parallelism, ever.** One codex writer at a time; review agents are
  read-only.
- Respect the context fence — anything outside it (other repos, notes, issues) is *yours*.
- Report honestly to the user: a gate that passed vacuously is not a pass, and say so.
- Before an irreversible step (publishing a repo, force-push, deletion), verify yourself and
  confirm with the user. Check for secrets *and* infrastructure topology — hostnames, user
  accounts, key paths, and builder configs are a map of the user's fleet even when no
  credential leaks.
