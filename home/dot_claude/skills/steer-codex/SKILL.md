---
name: steer-codex
description: Orchestrate long-running, fully autonomous Codex CLI workers from Claude, including one worker per GitHub issue, detached execution, full-access mode, parallel isolated worktrees, exact-session resume, monitoring, and outcome verification. Use when Codex should own the complete task and its external prompt already defines the scope; this skill must not add task-level constraints.
---

# Steer Codex without taking away its steering

## Operating contract

Codex owns the task from investigation through delivery. Claude is the control plane: launch
the worker, preserve its session, observe it, and return concrete outcomes or blockers. Claude
does not implement the task or prescribe how Codex must implement it.

The external task prompt, user instructions, and repository instructions are the complete task
contract. Pass the task prompt materially unchanged. Do not silently narrow it, expand it, or
wrap it in another project-management framework.

Within that contract, leave Codex free to:

- inspect the repository, issue tracker, documentation, history, and relevant external systems;
- choose its own plan, tools, files, architecture, commands, and debugging strategy;
- run whatever validation it considers appropriate;
- self-review and correct its work;
- commit, push, open or update a PR, update an issue, or perform other delivery steps when the
  task prompt authorizes them;
- continue until it has completed the task or reached a genuine external blocker.

Full machine access does not expand the task's scope. Conversely, do not add confirmation gates
for actions the prompt already authorizes.

## Launch with full capability

Use `codex exec` directly, not the Codex plugin for Claude Code. Preserve the user's configured
model and reasoning effort: do not pass `-m` or an effort override unless the user asks for one.
Do not use `--ephemeral`, because the session must remain resumable.

Use full-access mode for these workers:

```bash
setsid nohup codex exec \
  --dangerously-bypass-approvals-and-sandbox \
  --dangerously-bypass-hook-trust \
  --json \
  -C /absolute/path/to/worktree \
  - \
  < /absolute/path/to/task-prompt.md \
  > /absolute/path/to/run.jsonl \
  2> /absolute/path/to/run.stderr &
run_pid=$!
```

Feeding the prompt on stdin avoids shell argument limits and gives Codex EOF after the prompt.
Use a unique run directory and log files for every worker. Record the task or issue key,
worktree, branch, PID, prompt path, log paths, and the thread ID emitted by the JSONL
`thread.started` event.

The two bypass flags grant unrestricted disk and network access and allow configured repository
hooks without an additional trust prompt. If the user has already authorized full-capability
Codex orchestration for the requested sequence, treat that as standing authority and do not ask
again for every worker or resume. Otherwise confirm it once before the first launch.

Verify the worktree path before launch and set it explicitly with `-C`; never assume shell cwd.
Never stop workers with a broad command such as `pkill -f codex`; target the recorded PID.

## One worker per task, parallel when useful

Parallel workers are allowed. Do not serialize independent issues merely because this skill is
active.

For concurrent writers in one repository, give every worker its own branch, git worktree,
session, and run directory. Never point two writers at the same working tree. Serialize only
tasks with a real dependency or a shared external resource that cannot safely be used
concurrently.

Maintain this mapping for each task:

```text
issue/task -> worktree -> branch -> thread ID -> PID -> logs
```

Codex may complete the entire issue workflow allowed by its prompt. If completed branches need
integration or conflict resolution, make that another Codex-owned task rather than editing the
implementation from Claude.

## Observe without micromanaging

Let long workers run. A foreground tool timeout is not a task deadline, which is why workers are
detached. Poll coarsely or wait for the recorded PID to exit; do not consume context by tailing
the log continuously. Do not impose an artificial turn, token, or wall-clock budget unless the
user or external prompt supplies one.

When a worker exits:

1. Read its final response, exit status, repository state, and produced artifacts.
2. Judge completion only against the external task prompt and applicable repository rules.
3. If complete, report the outcome. Do not reject it for omitting rituals the prompt never
   required.
4. If incomplete, resume the same thread with concise, evidence-based observations. State the
   missing outcome or failure, not a replacement implementation plan, and let Codex choose the
   repair.
5. Continue until the requested outcome exists or Codex identifies a genuine blocker requiring
   user input or new authority.

Independent verification is useful when proportional to the task, but it must not become an
invented acceptance contract. Codex's prose alone is not proof of a code change, and a diff alone
is not proof of runtime behavior; inspect the evidence relevant to what the prompt requested.

## Resume the exact worker

Resume by recorded thread ID, especially when more than one worker exists:

```bash
setsid nohup codex exec resume \
  --dangerously-bypass-approvals-and-sandbox \
  --dangerously-bypass-hook-trust \
  --json \
  "$codex_thread_id" \
  - \
  < /absolute/path/to/follow-up.md \
  > /absolute/path/to/resume.jsonl \
  2> /absolute/path/to/resume.stderr &
resume_pid=$!
```

Invoke the resume from the same worktree and give it its own output log. Do not use `--last` in a
multi-worker sequence. Prefer resuming for follow-up, failures, review findings, and new user
instructions so the worker retains its reasoning and discoveries. Start over only when the
existing session is unusable or the user requests a fresh agent.

## Do not inject these constraints

Unless the external task prompt or repository instructions require them, do not impose:

- a state file, handoff document, prescribed plan, or spec-by-reference format;
- protected-file hashes, a fixed command list, exact test repetitions, or an exact commit subject;
- one commit per task, a mandatory commit, or a mandatory PR;
- negative-scope lists, context fences, or restrictions on reading issues and related repositories;
- a Claude subagent audit or any other fixed review ceremony;
- a global one-writer rule when workers have isolated worktrees;
- extra stopping points, approval checks, or delivery restrictions.

Those choices belong to the task prompt or to Codex's own execution judgment. This skill exists
to keep Codex capable, durable, and steerable—not to decide the work for it.
