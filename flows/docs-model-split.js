export const meta = {
  name: "docs-model-split",
  description: "Refresh docs/local-ai to the allowlist reality, preserve retired DS4 evidence, sunset the stale set",
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
      "the post-allowlist reality: which deployments are materialized per host",
      "(allowlist), which are cataloged-only, the parakeet/voxtype entries, and",
      "the NPU utility model — one authoritative model-split table. Uncensored",
      "ruling: only qwen3.6-35b-heretic materializes. (2) Keep",
      "docs/old/migration-journal/ds4-dual-node-lessons.md as historical evidence",
      "for the retired deployment. Current docs may summarize its measured result",
      "but must not turn it back into an active runbook or materialization target.",
      "(3) Sunset docs/old/: it is already self-declared non-normative; collapse",
      "it to an archival README stub (or prune files whose content is now",
      "superseded and cited nowhere), and update docs/README.md's index. Do not",
      "invent history — where a fact is uncertain, point at the source commit.",
      "Commit atomically on the branch; do not push."
    ].join(" "),
    { key: "implementation", workspace, label: "implementation" }
  );
  return sh(
    ["bash", "-c", 'cd "$1" && ! grep -rn "docs/old/migration-journal/ds4-dual-node-lessons" lib/ modules/', "citation-check", args.worktree],
    {
      pools: ["flow-build"],
      key: "citation-check",
      brief: { implementation: implementation.result },
      evidence: ["exit:0"],
      label: "citation-check"
    }
  );
})();
