export const meta = {
  name: "issue-96-drain",
  description: "Pointer-run HANDOFF-PROMPT-B: implement the drain/handoff/pickup skills on the utility-model seam (#96)",
  pools: ["codex-window", "flow-build"],
  argsSchema: {
    type: "object",
    required: ["repository", "baseRev", "branch", "worktree", "promptPath", "notesRepo"],
    properties: {
      repository: { type: "string", minLength: 1 },
      baseRev: { type: "string", minLength: 1 },
      branch: { type: "string", minLength: 1 },
      worktree: { type: "string", pattern: "^/" },
      promptPath: { type: "string", pattern: "^/" },
      notesRepo: { type: "string", pattern: "^/" }
    },
    additionalProperties: false
  },
  maxNodes: 5,
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
      `Your prompt is the file at ${args.promptPath} — read it and execute it`,
      "faithfully in this worktree. It implements mecattaf/dotfiles issue 96",
      "(manual journal drain + handoff/pickup on the shared utility-model seam).",
      "Issue 96 is the settled spec: manual-only trigger, no Stop hook, no",
      "autosave, no cloud fallback, per-root-session files, exact session",
      "identity, two-word groups — do not re-litigate. The prompt's final",
      "on-device drain acceptance test is gated separately by this flow; if the",
      "notes cutover has not landed, complete everything else and report that the",
      "live drain step is held. Commit atomically on the branch; do not push."
    ].join(" "),
    { key: "implementation", workspace, label: "implementation" }
  );
  await sh(["nix", "flake", "check", "--no-build", args.worktree], {
    pools: ["flow-build"],
    key: "flake-check",
    evidence: ["exit:0"],
    label: "flake-check"
  });
  // Cutover gate for the final acceptance step: settle instead of fail-loud so
  // an early run still lands the implementation and reports the held step.
  const cutover = await sh(
    ["bash", "-c", 'test -d "$1/journal/2026/07" && git -C "$1" rev-parse --verify HEAD', "cutover-gate", args.notesRepo],
    {
      pools: ["flow-build"],
      key: "cutover-gate",
      settle: true,
      evidence: ["exit:0"],
      label: "cutover-gate"
    }
  );
  return sh(["git", "-C", args.worktree, "log", "--oneline", `${args.baseRev}..HEAD`], {
    pools: ["flow-build"],
    key: "commit-proof",
    brief: {
      implementation: implementation.result,
      drainAcceptance: cutover.verdict === "pass" ? "cutover present — run reflexive /drain test" : "HELD: notes cutover not landed"
    },
    evidence: ["exit:0"],
    label: "commit-proof"
  });
})();
