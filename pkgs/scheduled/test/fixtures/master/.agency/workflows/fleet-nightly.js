// The midnight sequence of the master agency (Tom, 2026-09-20 R6/R7): "a midnight sequence full archival
// followed by a dedicated dotfiles operation: check if open gh issues that were filed today are closed otherwise
// cc opus works on them (culminating in a clean tree); then does the atomic fleet update so that the morning is
// fresh".
//
// Started by the superagent on the start nudge .agency/scheduled/fleet-nightly.jsonc (enabled: false), or on a
// request that names this script and the agency. Every agent() call is one Ticket; the next node proceeds by
// default, and a failed node is null. The run never stops on a node: only a tree that is not clean, or a
// clean-tree check that failed, skips the fleet update.
//
// args: { night: "YYYY-MM-DD" (required: the night key), repo?: "owner/name" (default mecattaf/dotfiles),
//         checkout?: path of its working tree relative to the agency folder (default mecattaf/dotfiles),
//         maxIssues?: integer >= 0 (default 3), capture?: the closed-chat capture command (default none) }
export const meta = {
  "name": "fleet-nightly",
  "description": "Midnight sequence: archival, then today's open dotfiles issues one Ticket each, then a clean-tree check, then the atomic fleet update.",
  "phases": [
    { "title": "archival", "detail": "journal-day rollover; closed-chat capture only when args.capture names it" },
    { "title": "issues", "detail": "issues filed on the night key and still open, one Ticket each, capped by args.maxIssues" },
    { "title": "clean-tree", "detail": "the checkout is on main with no local changes, then fast-forwarded" },
    { "title": "fleet-update", "detail": "fleet-update-start, only after a clean tree; never activates nas" }
  ]
};

const night = args && args.night;
if (typeof night !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(night)) {
  throw new Error("fleet-nightly: args.night must be the night key, YYYY-MM-DD");
}
const repo = typeof args.repo === "string" && args.repo !== "" ? args.repo : "mecattaf/dotfiles";
const checkout = typeof args.checkout === "string" && args.checkout !== "" ? args.checkout : "mecattaf/dotfiles";
const maxIssues = Number.isInteger(args.maxIssues) && args.maxIssues >= 0 ? args.maxIssues : 3;
const capture = typeof args.capture === "string" && args.capture.trim() !== "" ? args.capture.trim() : "";
const head = `Nightly sequence ${night} (night key ${night}).`;

phase("archival");
const archival = await agent([
  `${head} Step 1 of 3: archival. You work in the agency folder.`,
  "1. Run ~/.local/bin/journal-day once, with no arguments. It is idempotent, takes its own lock and rotates only the ~/today link; it never moves, copies or deletes day contents and never touches running sessions. Quote the path it prints. If it exits non-zero, quote its stderr word for word and go on.",
  capture
    ? `2. Run exactly: ${capture}. Quote its receipt line. It copies closed sessions only; never point it at a session that is still open.`
    : "2. No closed-chat capture command is configured (args.capture is empty). Say so; do not look for one or improvise one.",
  "Change nothing else: no notes edits, no summaries, no Projects item, no commit.",
  "End with one line: the today path, and the capture result or \"capture not configured\".",
].join("\n"), { label: "archival" });

phase("issues");
const listed = await agent([
  `${head} Step 2 of 3: the dotfiles issues filed on ${night}. Read-only.`,
  `Run: gh issue list --repo ${repo} --state open --search "created:${night}" --json number,title --limit 50`,
  `An issue filed on ${night} that is already closed needs nothing. Reply with the open ones only, an empty list when there are none.`,
  "Change nothing: no comment, label, edit or close.",
].join("\n"), {
  label: "issues-open",
  schema: {
    type: "object",
    properties: {
      issues: {
        type: "array",
        items: {
          type: "object",
          properties: { number: { type: "integer" }, title: { type: "string" } },
          required: ["number", "title"],
        },
      },
    },
    required: ["issues"],
  },
});
const open = (listed && Array.isArray(listed.issues) ? listed.issues : [])
  .filter((i) => i && Number.isInteger(i.number) && i.number > 0);
if (listed === null) log("the issue list failed; no issue is worked tonight");
const worked = open.slice(0, maxIssues);
const deferred = open.slice(maxIssues).map((i) => i.number);
if (deferred.length > 0) log(`over the cap of ${maxIssues}, left for tomorrow: ${deferred.map((n) => `#${n}`).join(" ")}`);

const issues = [];
for (const issue of worked) {
  const n = issue.number;
  const result = await agent([
    `${head} Step 2 of 3: work on ${repo} issue #${n} ("${String(issue.title)}"), filed on ${night} and still open.`,
    "- Read the issue and its comments with gh. If it needs Tom's decision, a secret, a host switch or anything outside the repo, do not start: say what it needs and end.",
    `- Work in a fresh clone or worktree under $TMPDIR (default /tmp), named nightly-${night}-issue-${n}, cut from origin/main. Never edit, reset or clean the checkout at ~/${checkout}.`,
    "- Make the smallest change the repo's maintainer would accept, with the regression test first where the repo has tests for that area.",
    "- Evaluate on this host when useful. Every nix build goes to the strix-coordinator builder (this host builds nothing locally), and only after `ssh strix-coordinator df -h /` shows at least 25 GB free; with less, stop and say so. Heavier commands go through `fleet-exec strix-coordinator --cwd <staged checkout> -- ...`. Never use strix-worker.",
    `- Push one branch, nightly/${night}-issue-${n}, and open one draft PR whose body says "Refs #${n}". Never force-push, never push main, never merge, approve or close a PR, and never close the issue.`,
    "- Never run nixos-rebuild, switch-to-configuration or a deploy, and never start, stop or restart a unit.",
    "- Remove your worktree or clone once the branch is pushed, so no tree is left behind.",
    "End with one line: the PR link, or why nothing was pushed.",
  ].join("\n"), { label: `issue-${n}` });
  issues.push({ number: n, title: String(issue.title), result });
}

phase("clean-tree");
const tree = await agent([
  `${head} The clean-tree check before the fleet update.`,
  `In ~/${checkout}: run git status --porcelain=v1 --branch and git worktree list.`,
  `The tree is clean when no tracked file is modified or staged, the branch is main, and no worktree of a nightly/${night}-issue-* branch is left. Untracked files are named in the detail but do not make it unclean, and they stay.`,
  "If it is clean: git fetch origin, then git pull --ff-only origin main, and quote the new head. A refused pull means it is not clean.",
  "Never stash, reset, clean, checkout, rebase or commit in it, and never force-push.",
  "Reply with clean true or false and a one-line detail: the new head, or what is in the way.",
].join("\n"), {
  label: "clean-tree",
  schema: {
    type: "object",
    properties: { clean: { type: "boolean" }, detail: { type: "string" } },
    required: ["clean", "detail"],
  },
});
const clean = tree !== null && tree.clean === true;
const detail = tree === null ? "the clean-tree check failed" : String(tree.detail);

let fleet;
if (!clean) {
  fleet = tree === null ? "skipped: the clean-tree check failed" : `skipped: the tree is not clean (${detail})`;
  log(fleet);
} else {
  phase("fleet-update");
  fleet = await agent([
    `${head} Step 3 of 3: the atomic fleet update.`,
    "If /run/current-system/sw/bin/fleet-update-start is not an executable file, say so and end: the launcher is not installed yet.",
    `If ~/.local/state/fleet-update/completions/${night}.json exists and has ok: true, quote it and end.`,
    "Run `ssh strix-coordinator df -h /` and quote the line. With less than 25 GB free, do not launch: say so and end. Builds happen on strix-coordinator only; never use strix-worker.",
    `Read the targets fleet-update acts on: git -C ~/${checkout} show origin/main:lib/fleet-update.json. If nas is an activation target, do not launch, and end with: not launched: nas is an activation target, and no nightly job switches nas.`,
    "1. Run: fleet-update-start --json. Quote the receipt. A launch receipt has ok: false and proves launch only.",
    "2. Run: fleet-update --status --json. Say which stage the job is in and which targets are pending, and why.",
    "3. If ~/.local/state/fleet-update/completions/ holds a receipt for the previous night, list what it installed and what stayed pending.",
    `Do not run nixos-rebuild, switch, reboot, start, stop or restart a unit, merge a PR, or edit ~/${checkout}: fleet-update owns those steps. Never force-push.`,
    "End with one line: launched, already running, not launched (why), or the error, quoted.",
  ].join("\n"), { label: "fleet-update" });
}

return { night, archival, issues, deferred, clean, detail, fleet };
