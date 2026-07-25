export const meta = {
  name: "docs-model-split",
  description: "Refresh docs/local-ai to the allowlist reality, mine ds4 lessons out of docs/old, sunset the stale set",
  pools: ["codex-window", "build"],
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
      "ruling: only qwen3.6-35b-heretic materializes. (2) Mine",
      "docs/old/migration-journal/ds4-dual-node-lessons.md into a current",
      "docs/local-ai/ runbook page BEFORE sunsetting — it is still cited from",
      "lib/local-models.nix:730-739; update that citation to the new location.",
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
      pools: ["build"],
      key: "citation-check",
      brief: { implementation: implementation.result },
      evidence: ["exit:0"],
      label: "citation-check"
    }
  );
})();
