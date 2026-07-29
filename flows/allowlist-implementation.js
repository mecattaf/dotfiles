export const meta = {
  name: "allowlist-implementation",
  description: "Replace downloadAllModels with a per-host/deployment allowlist (#95 prereq) and ship the declarative hf CLI (#90)",
  pools: ["codex-window", "flow-build"],
  argsSchema: {
    type: "object",
    required: ["repository", "baseRev", "branch", "worktree"],
    properties: {
      repository: { type: "string", minLength: 1 },
      baseRev: { type: "string", minLength: 1 },
      branch: { type: "string", minLength: 1 },
      worktree: { type: "string", pattern: "^/" }
    },
    additionalProperties: false
  },
  maxNodes: 4,
  selectors: []
};

(async () => {
  const workspace = {
    repo: args.repository,
    baseRev: args.baseRev,
    branch: args.branch,
    worktreePath: args.worktree
  };
  const implementation = await codex(
    [
      "Implement dotfiles issue #95's prerequisite in this worktree: replace the",
      "all-or-nothing services.local-models.downloadAllModels flag with a per-host,",
      "per-deployment allowlist (e.g. services.local-models.allow = [ <deployment ids> ]).",
      "Enabling a deployment materializes only its artifacts into",
      "system.extraDependencies and its llama-swap row; everything else stays",
      "metadata-only. Keep the standing invariants: no runtime -hf downloads ever",
      "(preserve the assertion), weights never in git, catalog JSON still emitted.",
      "Update the flake.nix:713-717 assertions to the new option shape. Ruling in",
      "force: the allowlist REPLACES the flag — do not keep both. Populate the",
      "initial allowlist per docs/local-ai/model-roster.md with ALL deployments",
      "EXCEPT uncensored, where only qwen3.6-35b-heretic is allowed (ruling",
      "2026-07-25). Also fold in issue #90: package the Hugging Face `hf` CLI",
      "declaratively (pinned), with noninteractive auth via the secrets layer and",
      "a smoke check; neither activation nor tally jobs may run `hf download`.",
      "Read gh issues 95 and 90 for full acceptance criteria. Commit atomically",
      "on the branch; do not push."
    ].join(" "),
    { key: "implementation", workspace, label: "implementation" }
  );
  await sh(["nix", "flake", "check", "--no-build", args.worktree], {
    pools: ["flow-build"],
    key: "flake-check",
    evidence: ["exit:0"],
    label: "flake-check"
  });
  return sh(["git", "-C", args.worktree, "log", "--oneline", `${args.baseRev}..HEAD`], {
    pools: ["flow-build"],
    key: "commit-proof",
    brief: { implementation: implementation.result },
    evidence: ["exit:0"],
    label: "commit-proof"
  });
})();
