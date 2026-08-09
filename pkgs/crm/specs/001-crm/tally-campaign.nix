# ARCHIVED 2026-08-02 — the declarative crm build campaign, removed from
# dotfiles/home/tally.nix (estate step E1 of the tally.nix wave-3 close-out).
#
# Why removed: the tally module now requires `kind` and `preflightArgv` on
# every campaign gate (tally.nix#318 line of work); this block predates that
# schema, so Home Manager evaluation would fail on the next tally pin advance.
# Acceptance is forge-native now — the campaign attrset is no longer the
# mechanism of record.
#
# What this was: the first consumer of tally.nix#235. One attrset rendered
# everything the hand-rolled prototype needed six pieces for: the shipped
# spec-build flow, the scoped gh mention producer, the capacity-1 runner
# mutex, the campaign node lanes, and the driver adapter. The work graph was
# specs/001-crm/tasks.json in this repo, witnessed by the flow's first node.
# Doctrine and the role split: JULY31-LEARNINGS.md in tally.nix.
#
# To revive: re-add under services.tally.campaigns in home/tally.nix, adding
# the now-mandatory `kind` and `preflightArgv` per gate (see the tally
# campaigns doc for the current schema), and re-check every inline rationale
# below against the current module — the codex-exec sandbox findings were
# reported upstream as tally.nix#244 and the adapter smoke probe has since
# been fixed (#244 → PR #324/#330).
#
# The companion pools note that lived beside it in home/tally.nix:
#   crm-campaign was NOT declared in services.tally.pools:
#   services.tally.campaigns.crm rendered it as the capacity-1 runner mutex,
#   together with the campaign-agent and campaign-control node lanes.

{
  campaigns = {
    crm = {
      enable = true;

      repositories."mecattaf/crm" = {
        checkout = "/home/tom/mecattaf/crm";
        baseBranch = "main";
        remote = "origin";
      };

      # Deliberately NOT "build": issues #1–#19 carry that label and are
      # public anchors for the decomposition, never triggers. Exactly one
      # open issue carries "campaign", and it is the doorbell.
      label = "campaign";
      # NOT "@tally ..." — @tally is a real, unrelated GitHub user and the
      # mention token is a live ping on a public repo (tally.nix#246). The
      # operator's own handle pings only themselves.
      mention = "@mecattaf build";
      # The operator posts the mention from the account gh is authenticated
      # as, so the trigger actor and tally's own identity are the same and
      # the default loop-breaker would filter every mention as
      # self-trigger-disabled. Opt in (tally.nix#240); allowedActors still
      # applies independently.
      allowSelfTriggered = true;
      allowedActors = [ "mecattaf" ];

      worklist = "specs/001-crm/tasks.json";
      # The frozen graph is 19 tasks; the cap refuses a worklist that grew.
      maxTasks = 19;

      agent = "codex";

      # The module's defaults (workspace-write + on-request) do not work for
      # a codex *exec* agent, proven by hand against the real binary:
      #   - `--ask-for-approval` is a top-level codex flag, not an exec flag;
      #     the adapter's approvalPolicies render it anyway and exec exits 2
      #     with "unexpected argument". null omits it. A non-interactive run
      #     has nobody to approve an escalation regardless.
      #   - under `--sandbox workspace-write` codex writes files fine but
      #     `.git` is mounted read-only, so `git add`/`git commit` fail on
      #     .git/index.lock. The publish node requires at least one commit
      #     descended from the prepared base, so a campaign agent that cannot
      #     commit is useless. `danger-full-access` writes and commits
      #     cleanly.
      # This grants codex unsandboxed access inside its assigned worktree,
      # which is the same capability this estate already gives every codex
      # session it dispatches. The gates remain independent witnessed nodes.
      # Reported upstream as tally.nix#244.
      agentSandboxPolicy = "danger-full-access";
      agentApprovalPolicy = null;

      # The four AGENTS.md gates, as direct argv. Go is not on PATH; every
      # command goes through nix. nixpkgs' go defaults to CGO_ENABLED=1
      # with CC=gcc, so on a gcc-less host every gate that compiles must
      # either pin CGO_ENABLED=0 (build/vet/lint — the shipped binary is
      # pure Go) or bring gcc (test, where the race detector is
      # cgo-backed). All four verified live in the t01 worktree 2026-07-31
      # before this shape landed. These are the merge criterion — witnessed
      # here, not re-reviewed by an agent.
      gates = [
        {
          id = "build";
          argv = [ "nix" "shell" "nixpkgs#go" "-c" "env" "CGO_ENABLED=0" "go" "build" "./..." ];
        }
        {
          id = "vet";
          argv = [ "nix" "shell" "nixpkgs#go" "-c" "env" "CGO_ENABLED=0" "go" "vet" "./..." ];
        }
        {
          id = "test";
          argv = [ "nix" "shell" "nixpkgs#go" "nixpkgs#gcc" "-c" "go" "test" "-race" "./..." ];
        }
        {
          id = "lint";
          argv = [ "nix" "shell" "nixpkgs#golangci-lint" "nixpkgs#go" "-c" "env" "CGO_ENABLED=0" "golangci-lint" "run" "./..." ];
        }
      ];

      # Held by the runner for the whole campaign, so a second accepted
      # mention queues instead of interleaving two task chains against the
      # same base.
      pool.name = "crm-campaign";
    };
  };
}
