export const meta = {
  name: "docs-model-split",
  description: "Refresh docs/local-ai to the halogen mono-model reality: one server, fifteen catalogue rows, per-host wanted sets",
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
      "the current reality: the one inference server is Halogen Flash on the",
      "worker at http://worker:8731 (model id halogen-qwen3.8-flash-next, served",
      "by modules/halogen.nix); the catalogue is the fifteen rows in",
      "lib/local-models.nix; each twin's wanted set is services.local-models.artifacts",
      "and bytes move only through local-models-borrow; the coordinator's small",
      "GGUF rows, the embedders, VibeVoice and Mage have no declared server and",
      "an operator runs llama-server by hand — one authoritative catalogue table.",
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
