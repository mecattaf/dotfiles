export const meta = {
  name: "parakeet-determinism",
  description: "Pin 2-3 parakeet models as deterministic Nix fetches and add the voxtype bootstrap gate (#107, then #84 acceptance)",
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
      "Make voxtype's parakeet weights nix-deterministic in this worktree. Today",
      "home/voxtype.nix relies on voxtype's own runtime download ('mutable user",
      "data outside Git and the Nix store') — that caused the #107 restart loop.",
      "Deliverables: (1) hash-pinned fixed-output fetches for 2-3 parakeet models",
      "(ruling 2026-07-25: two to three, not one). parakeet-unified-en-0.6b is the",
      "pinned streaming model; research which additional parakeet variants voxtype's",
      "parakeet engine actually accepts — note parakeet-tdt-0.6b-v3 is batch-only",
      "and REJECTED for streaming (see home/voxtype.nix:34-38 comment), so verify",
      "streaming compatibility before pinning; extend lib/local-models.nix or a",
      "sibling catalog so the artifacts ride the same declarative model-store path",
      "as the LLM roster. (2) Wire voxtype's model dir to the store-provided",
      "weights (symlink/option, whatever the HM module supports). (3) A bootstrap",
      "gate so a missing model dir yields a clear failed condition, not a systemd",
      "restart loop (closes #107). (4) Update issue #84's live-acceptance notes",
      "where automatable. Read gh issues 84 and 107 first. Commit atomically on",
      "the branch; do not push."
    ].join(" "),
    { key: "implementation", workspace, label: "implementation" }
  );
  await sh(["nix", "flake", "check", "--no-build", args.worktree], {
    pools: ["build"],
    key: "flake-check",
    evidence: ["exit:0"],
    label: "flake-check"
  });
  return sh(["git", "-C", args.worktree, "log", "--oneline", `${args.baseRev}..HEAD`], {
    pools: ["build"],
    key: "commit-proof",
    brief: { implementation: implementation.result },
    evidence: ["exit:0"],
    label: "commit-proof"
  });
})();
