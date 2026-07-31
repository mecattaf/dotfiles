export const meta = {
  name: "crm-issue",
  description: "Implement one mecattaf/crm build issue: worktree prep, codex implementation, deterministic go gates, push + PR",
  pools: ["codex-window", "flow-build"],
  argsSchema: {
    type: "object",
    required: ["issue"],
    properties: {
      issue: { type: "integer", minimum: 1 }
    },
    additionalProperties: false
  },
  maxNodes: 8,
  selectors: []
};

(async () => {
  const issue = args.issue;
  const repo = "/home/tom/mecattaf/crm";
  const branch = `issue-${issue}`;
  const worktree = `/home/tom/.local/state/tally-worktrees/crm-issue-${issue}`;
  const workspace = {
    repo: "mecattaf/crm",
    baseRev: "main",
    branch,
    worktreePath: worktree
  };

  // Re-runs after a failed gate start from a fresh branch tip; --force -B
  // makes the prep idempotent across retries of the same issue.
  await sh(
    [
      "bash",
      "-lc",
      `set -euo pipefail; cd ${repo}; git fetch origin main; ` +
        `git worktree add --force -B ${branch} ${worktree} origin/main`
    ],
    {
      pools: ["flow-build"],
      key: `prep-${issue}`,
      evidence: ["exit:0"],
      label: "worktree-prep"
    }
  );

  const implementation = await codex(
    [
      `Your assignment is GitHub issue #${issue} of mecattaf/crm; your cwd is a`,
      `dedicated worktree on branch ${branch}. First read AGENTS.md at the`,
      `worktree root and follow its reading order (constitution, spec, data`,
      `model, style-transfer map). Then run: gh issue view ${issue} --repo`,
      "mecattaf/crm --comments — that issue text is your complete scope;",
      "implement exactly its acceptance criteria and nothing beyond it. Read",
      "the reference source files the issue and the style-transfer map point",
      "at before writing code. Run the three gates yourself (nix shell",
      "nixpkgs#go -c go build ./... / go vet ./... / go test ./...) until",
      "green. Commit atomically on the branch with imperative subjects; do",
      "not push and do not touch git config. Never create or commit a",
      "database file or -wal/-shm sidecar."
    ].join(" "),
    {
      key: `implement-${issue}`,
      label: "implement",
      runtimeMaxSec: 14400,
      workspace
    }
  );

  // Deterministic gates: codex's own runs prove nothing; these witnessed
  // nodes are what the PR merge waits on.
  const gates = [
    ["build", "go build ./..."],
    ["vet", "go vet ./..."],
    ["test", "go test ./..."]
  ];
  for (const [name, cmd] of gates) {
    await sh(
      ["bash", "-lc", `set -euo pipefail; cd ${worktree}; nix shell nixpkgs#go -c ${cmd}`],
      {
        pools: ["flow-build"],
        key: `gate-${name}-${issue}`,
        evidence: ["exit:0"],
        label: `gate-${name}`
      }
    );
  }

  // Push and open the PR only after every gate passed. Idempotent for
  // replayed runs: an existing PR for the branch is accepted as success.
  return sh(
    [
      "bash",
      "-lc",
      `set -euo pipefail; cd ${worktree}; git push -u origin ${branch}; ` +
        `gh pr create --repo mecattaf/crm --head ${branch} --base main ` +
        `--title "$(git log -1 --pretty=%s)" ` +
        `--body "Closes #${issue}. Implemented by codex under tally flow crm-issue; go build/vet/test passed as witnessed gate nodes." ` +
        `|| gh pr view ${branch} --repo mecattaf/crm --json url -q .url`
    ],
    {
      pools: ["flow-build"],
      key: `pr-${issue}`,
      brief: { issue, implementation: implementation.result },
      evidence: ["exit:0"],
      label: "push-pr"
    }
  );
})();
