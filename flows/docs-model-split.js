export const meta = {
  name: "docs-model-split",
  description: "Refresh docs/local-ai to the Gufo model collection and per-host wanted sets",
  pools: ["flow-build"],
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
  maxNodes: 3,
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
      "Documentation wave in this worktree, three moves. (1) Refresh",
      "docs/local-ai/model-roster.md (and local-ai/README.md where affected) to",
      "the declared reality: Gufo on Strix at http://strix-coordinator:8731 (model id",
      "qwen3.8-flash-next, served by modules/gufo.nix); the catalogue is in",
      "lib/local-models.nix and lib/gufo-models.json; wanted sets are",
      "services.local-models.artifacts and bytes move only through",
      "local-models-borrow. Describe operator-switched Gufo alternates and",
      "on-demand speech separately from the resident text model.",
      "(2) Describe the current state only: no history sections, no",
      "commented-out prose, no retired engines named as if they could return.",
      "(3) Keep docs/README.md's index in step with the pages. Where a fact is",
      "uncertain, point at the Nix file that decides it. Commit atomically on",
      "the branch; do not push."
    ].join(" "),
    { key: "implementation", workspace, label: "implementation" }
  );
  return sh(
    ["bash", "-c", 'cd "$1" && ! grep -rniE "llama-swap|flashnext|ds4" docs/local-ai/README.md docs/local-ai/model-roster.md', "citation-check", args.worktree],
    {
      pools: ["flow-build"],
      key: "citation-check",
      brief: { implementation: implementation.result },
      evidence: ["exit:0"],
      label: "citation-check"
    }
  );
})();
