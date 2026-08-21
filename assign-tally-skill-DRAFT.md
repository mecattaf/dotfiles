---
name: assign-tally
description: Assign a body of coding work to tally as a forge-native campaign and shepherd it to completion — author the issue graph, arm, monitor, steer, recover from failures and escalations, and verify merges. Use when the user says assign to tally, run this through tally, tally campaign, dispatch via tally, or wants issues filed→merged with zero manual terminal starts. The orchestrating session never writes worker code; it files, arms, steers, and verifies.
---

# assign-tally — dispatch work through a tally campaign

You are the operator, not the coding worker. Workers are dispatched agents;
you author the graph, admit it, watch it, steer it, and verify what merges.
Proven end-to-end on the crm-call-drain campaign (dotfiles#163, 2026-08-09/10,
11/11 tasks, zero manual terminal starts). Doctrine source:
`~/mecattaf/tally.nix/doc/src/flows/campaigns.md`; operational evidence:
`~/mecattaf/tally.nix/AUGUST-10-LEARNINGS.md`.

## 1. Author the campaign issue graph

One master issue holds the manifest; each task is a native sub-issue labeled
`tally-campaign-task`.

Master issue body: prose summary + scope fences, then the manifest inside
`<!-- tally:campaign:v1 -->` … `<!-- tally:campaign:v1:end -->` fenced JSON,
then the worklist checklist inside `<!-- tally:campaign-worklist:v1 -->` …
`<!-- tally:campaign-worklist:v1:end -->` markers (one line per task:
`- [ ] <!-- tally:campaign-task:v1 id=<id> --> #<issue> — <title>`).
**Both `:end` closers are mandatory** — arm fails with "missing
tally:campaign:v1:end" otherwise; repeating the begin marker is not a closer.

Manifest essentials (see dotfiles#163 for a complete working example):
- `repository`: local checkout path, baseBranch, remote, `"forge": "github"`.
- `maxTasks` must be ≥ the task count — the arm error
  `campaign must contain 1..=N tasks` is THIS field echoed back, not a schema cap.
- `agent`: adapter (`codex` proven; `dangerously-bypass` sandbox), argv is the
  fixed brief-pointer sentence; keep `runtimeMaxSec` generous for GPU work.
- `gates`: always include a `forbidPaths` guard for data artifacts
  (`*.db`, `*.wav`, `*.sqlite*`, `*.age`, `secrets/**`) and a `command` gate
  that evals the relevant NixOS toplevel.
  **forbidPaths judges the lane's COMMIT HISTORY, not the final tree** — a file
  added then `git rm`'d in a later commit still fails; the only cure is
  rewriting the lane so the path never enters any commit. Corollary: before
  arming, sweep every tree you will VENDOR against the gate patterns (the dcal
  campaign lost ~40 min to an innocent upstream notification chime matching
  `*.wav`).
- `tasks[]`: `id`, `kind` (`implementation` needs `conflictDomains` — an
  enforced ownership boundary; `checkpoint` needs `argv` + `runtimeMaxSec`),
  `issue`, `dependencies`.

Task issue bodies start with `<!-- tally:campaign-task:v1 id=<id> -->` and use
house style: Goal, Steps, Acceptance criteria, Scope boundary, Eval expectation.

Hard rules learned live:
- **No PII in any public issue/PR text.** Put private paths/names in a pointer
  file inside the private notes repo and reference the pointer.
- Checkpoints verify; they cannot fix. Any deterministic defect a checkpoint
  finds becomes a new implementation task the checkpoint depends on.
- Bake worker survival guidance into task bodies: never `rm -f`/`rm -rf` in
  shell (codex safety layer kills the session); delete files in Python
  (`shutil`); commit lane checkpoints after every milestone; small patches.

## 2. Arm

```bash
tally campaign arm https://github.com/<owner>/<repo>/issues/<master>
tally campaign list   # verify registration + approvedGraphDigest
```

Arming admits the CURRENT graph digest. The campaign then self-continues;
the poll timer is only recovery. Daemon health: `systemctl --user status
tally-daemon`; pools: `tally query status`.

## 3. Monitor

Poll `tally query jobs` and the repo's PRs/issues on ~60s cadence; diff and
react to transitions (a background monitor emitting only changes works well).
Identify what a worker is doing via `.orchestration.nodeLabel`; read a failed
worker with:

```bash
tally query log --task <full-uuid>   # tail has exit + captured stderr
tally query job <full-uuid>          # finalMessage = worker's own last report
```

Verify every merged PR against its task scope (`gh pr view N --json files,additions`).
Empty 0-file PRs titled like completed tasks are **marker PRs** from stateless
reconcile after a graph change — benign, ignore them.

## 4. Steer

- **Human steering = issue comments** by an allowed actor on the task issue
  (or master for campaign-wide). They enter `steering.authorizedComments` in
  the next brief WITHOUT re-arm. Steer with concrete evidence: the command,
  expected vs actual, exact stderr lines.
- **Editing an issue BODY changes the executable graph digest** → polling
  halts with "explicit re-arm is required" → `tally campaign arm` again.
  Comments don't; bodies do.
- **Graph-edit tax**: after every re-arm on a changed digest, each completed
  task is re-walked by a no-op agent and an empty marker PR merges (~5 min per
  completed task). Batch graph edits; never edit mid-attempt.

## 5. Failure triage decision tree

Worker/checkpoint failed → read the log tail, then classify:

1. **Transient / worker-session death** (codex tool-router exit, adapter
   flake): post steering comment; the flow's diagnose→steer→retry gives 2
   steered attempts per task. Lane state survives across attempts.
2. **Deterministic workload defect** (same stderr twice, or obviously
   content-independent): do NOT let it burn the retry budget. File a new
   implementation task with the stderr as evidence, add it to the manifest
   (`maxTasks` +1, task entry, worklist line, `gh api graphql` addSubIssue),
   make the failing checkpoint depend on it, wait for the in-flight pass to
   settle, then recover per §6 and re-arm.
3. **Tally defect**: never modify tally mid-campaign. File in
   mecattaf/tally.nix with repro, work around operationally, report.

## 6. Escalation recovery ("frontier quiescent")

Escalation posts to the master issue after each directly blocked task fails
twice with steering; the campaign stops. Recovery is the **resume verb**
(proven 3x on the dcal campaign, dotfiles#210):

```bash
tally campaign resume --reason "<audit reason>" <master-url>
```

It pardons machine-diagnosis/machinery-retry/escalation counters WITHOUT
deleting the audit trail, posts a resume receipt, and admits a fresh pass.
(The old delete-receipts-and-re-arm dance is obsolete.)

**Re-arm does NOT pardon.** After graph surgery (§5.2) on a task that already
escalated, the amendment dispatches the NEW task but the escalated checkpoint
keeps its spent budget — the frontier goes quiescent again, silently. Always
follow post-escalation re-arm with `resume` once the fix has merged.
(tally.nix#456 asks for this to be automatic or warned about.)

Known tally bug (tally.nix#455, was #451): the steward's diagnoses are
systematically rejected by the literal-substring grammar ("diagnosis omits the
failing check id …") while still consuming machinery budget — expect ALL
effective steering to be your own human comments.

## 6b. Checkpoint argv doctrine (dcal campaign, dotfiles#210)

Checkpoint commands run in a **hardened transient unit**: minimal PATH,
`ProtectHome=read-only`, `PrivateTmp`, `ProtectSystem=strict`,
`NoNewPrivileges`, `RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6`.
Consequences, each learned the hard way:

- **Self-contained toolchains only.** `go`/`gofmt`/anything not in the unit's
  PATH → exit 127. Source tools via nix:
  `nix shell --inputs-from . nixpkgs#go -c sh -euc '…'`, and point caches at
  tmp (`GOCACHE`/`GOMODCACHE`/`GOPATH` under `/tmp`, HOME is read-only), and
  `export CGO_ENABLED=0` if no C compiler is provided.
- **Probe the condition, not a proxy.** A readiness loop on `dcal status`
  broke silently when a sibling task legitimately changed status's semantics.
  Wait for the actual resource (socket file exists) or accept that any
  behavior a checkpoint leans on must be named in the frozen contract of
  every task that could touch it.
- **The sandbox exposes races your shell hides** (slower start, colder
  caches). Before arming, validate every checkpoint argv under an equivalent
  `systemd-run --user` sandbox, not just interactively.
- **Steering comments race attempt-prep** (collected at prep time; a comment
  posted 71s late reaches only the NEXT attempt). Post steering the moment
  the diagnosis is solid; don't wait for the current attempt to finish.
- Failed checkpoint output is only in journald `TALLY_STDERR_TAIL` (last line)
  until tally.nix#457 lands — budget a sandbox reproduction per failure.

## 7. Completion and closeout

Completion posts `tally:campaign-complete:v1` on the master, closes every
sub-issue and the master itself. Then:

- Run the chapter's acceptance test yourself (query the deployed artifact,
  check files on disk) — merged ≠ verified.
- Merged machinery activates at the next ordinary deploy, not by the campaign.
- `tally campaign disarm <master-url>`; confirm `tally campaign list` → `[]`.
- Record dispatch metrics: issues filed, worker attempts, terminal-free
  merges, operator interventions.
