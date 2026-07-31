export const meta = {
  name: "crm-campaign",
  description: "The whole mecattaf/crm build: for each issue in order — worktree prep, codex implementation, deterministic go gates, push + PR, merge on green — fail-fast, replay-resumable",
  pools: ["codex-window", "flow-build"],
  argsSchema: {
    type: "object",
    required: ["issues"],
    properties: {
      issues: {
        type: "array",
        minItems: 1,
        maxItems: 32,
        items: { type: "integer", minimum: 1 }
      }
    },
    additionalProperties: false
  },
  maxNodes: 168,
  iterationCap: 96,
  selectors: []
};

(async () => {
  const repo = "/home/tom/mecattaf/crm";
  const merged = [];

  for (const issue of args.issues) {
    const branch = `issue-${issue}`;
    const worktree = `/home/tom/.local/state/tally-worktrees/crm-issue-${issue}`;
    const workspace = {
      repo: "mecattaf/crm",
      baseRev: "main",
      branch,
      worktreePath: worktree
    };

    // Prep cuts the branch from the CURRENT origin/main — which, because the
    // previous iteration's merge node completed first, already contains every
    // earlier issue. --force -B makes a post-failure replay start clean.
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
        label: `prep-${issue}`
      }
    );

    const implementation = await codex(
      [
        `Your assignment is GitHub issue #${issue} of mecattaf/crm; your cwd is a`,
        `dedicated worktree on branch ${branch}. First read AGENTS.md at the`,
        "worktree root and follow its reading order (constitution, spec, data",
        `model, style-transfer map). Then run: gh issue view ${issue} --repo`,
        "mecattaf/crm --comments — that issue text is your complete scope;",
        "implement exactly its acceptance criteria and nothing beyond it. Read",
        "the reference source files the issue and the style-transfer map point",
        "at before writing code. Run the four gates from AGENTS.md yourself",
        "(go build, go vet, race-enabled go test, golangci-lint — exact nix",
        "invocations in AGENTS.md) until green. Commit atomically on the",
        "branch with imperative subjects; do not push and do not touch git",
        "config. Never create or commit a database file or -wal/-shm sidecar."
      ].join(" "),
      {
        key: `implement-${issue}`,
        label: `implement-${issue}`,
        runtimeMaxSec: 14400,
        workspace
      }
    );

    // Deterministic gates: codex's own runs prove nothing; a red gate here
    // rejects the whole campaign run (fail-fast) — fix via issue comment,
    // then replay; the witnessed prefix (all merged issues) is reused.
    const gates = [
      ["build", "nix shell nixpkgs#go -c go build ./..."],
      ["vet", "nix shell nixpkgs#go -c go vet ./..."],
      ["test", "nix shell nixpkgs#go nixpkgs#gcc -c go test -race ./..."],
      ["lint", "nix shell nixpkgs#golangci-lint -c golangci-lint run ./..."]
    ];
    for (const [name, cmd] of gates) {
      await sh(
        ["bash", "-lc", `set -euo pipefail; cd ${worktree}; ${cmd}`],
        {
          pools: ["flow-build"],
          key: `gate-${name}-${issue}`,
          evidence: ["exit:0"],
          label: `gate-${name}-${issue}`
        }
      );
    }

    // Push + PR, reached only with every gate green. Replay-idempotent: an
    // existing PR for the branch is success.
    await sh(
      [
        "bash",
        "-lc",
        `set -euo pipefail; cd ${worktree}; git push -u origin ${branch}; ` +
          `gh pr create --repo mecattaf/crm --head ${branch} --base main ` +
          `--title "$(git log -1 --pretty=%s)" ` +
          `--body "Closes #${issue}. Implemented by codex under tally flow crm-campaign; build, vet, race-enabled test, and lint passed as witnessed gate nodes." ` +
          `|| gh pr view ${branch} --repo mecattaf/crm --json url -q .url`
      ],
      {
        pools: ["flow-build"],
        key: `pr-${issue}`,
        brief: { issue, implementation: implementation.result },
        evidence: ["exit:0"],
        label: `pr-${issue}`
      }
    );

    // Merge on green is mechanical policy: the gates ARE the merge criterion.
    // "Closes #N" closes the issue; the closed check makes silent merge
    // failures impossible. Replay-idempotent: an already-merged PR passes.
    await sh(
      [
        "bash",
        "-lc",
        `set -euo pipefail; ` +
          `state=$(gh pr view ${branch} --repo mecattaf/crm --json state -q .state); ` +
          `if [ "$state" != "MERGED" ]; then ` +
          `gh pr merge ${branch} --repo mecattaf/crm --merge --delete-branch; fi; ` +
          `test "$(gh issue view ${issue} --repo mecattaf/crm --json state -q .state)" = CLOSED`
      ],
      {
        pools: ["flow-build"],
        key: `merge-${issue}`,
        evidence: ["exit:0"],
        label: `merge-${issue}`
      }
    );

    merged.push(issue);
    log({ merged: issue, progress: `${merged.length}/${args.issues.length}` });
  }

  return { merged, total: args.issues.length };
})();
