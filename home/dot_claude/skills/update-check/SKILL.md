---
name: update-check
description: Run the dotfiles nightly update check on the strix and digest what each update brings. Use when the substrate update-check routine fires, when Tom asks for the update check, or to read an open update/<input> PR on mecattaf/dotfiles against the repo and propose the new features worth taking.
---

# Update check

The nightly update check has two halves (#550). The clock is a routine on the
substrate floor (substrate T-7); nothing in dotfiles schedules it. The logic
is here: `update-check` (home/dot_local/bin/update-check) does every
mechanical step, and this skill is the part that reads.

You never merge, switch, deploy, restart a unit, close an issue or touch the
`~/mecattaf/dotfiles` working tree. Merging is Tom's word, and so is every
switch.

## 1. Run the check

On the strix:

    update-check --json

The floor routine runs `update-check --if-idle --once-per-night --json`
instead: it answers `{"skipped": ...}` while the strix is busy or when this
night already ran, and that is a normal outcome, not an error. The nightly
routine stops after step 1; the digest (step 2) runs when Tom asks for it.

It fetches main, compares each input in `lib/update-watch.json` with upstream,
and for each one that moved it rebuilds the rolling branch `update/<input>`,
runs the gate and opens or refreshes one PR. Read the per-input `status`:

| status | meaning | your part |
|---|---|---|
| `opened`, `refreshed` | a PR now carries a new version | digest it (step 2) |
| `unchanged` | the open PR already carries the newest versions | nothing |
| `no-version-change` | upstream moved, nothing we use changed version | nothing |
| `current`, `closed` | main already carries upstream | nothing |
| `error` | the check itself could not finish | report the error line, do not retry in a loop |

A PR whose gate failed is a draft with the log tail in its body. Name it in
your report. Fix it only when the cause is plainly in this repo and small,
such as an option a new release renamed. Otherwise leave it for Tom.

## 2. Digest each opened or refreshed PR

The PR body holds the version table and the upstream release notes for
exactly the range between main and the PR. GitHub caps a PR body, so a long
release is cut and links its full notes: read every cut one in full
(`gh api repos/<owner>/<repo>/releases/tags/<tag> --jq .body`) before you
judge it. Read them against what this repo does with the program:

| input | where the repo uses it |
|---|---|
| llm-agents: claude-code | `home/dot_claude/settings.json` (the template), `home/claude-settings.py` (the initializer), the `cc`/`cc2` launchers and their env in `home/dot_config/fish/config.fish`, `home/dot_claude/skills/`, the `no-claude-code-hooks` flake check, the seats paragraph in AGENTS.md |
| llm-agents: codex | `home/home.nix` (`.codex` links), the codex runtimes in `modules/substrate.nix` and `hosts/strix/default.nix`, `seats` (`home/dot_local/bin/seats`) |
| llm-agents: pi | `home/pi.nix` (the wrapper and its extension roster), the pi runtimes in `modules/substrate.nix` |
| herdr | `home/herdr.nix`, `home/dot_config/herdr/`, the herdr pin comment in `flake.nix` |
| gufo | `modules/gufo.nix`, `lib/gufo-models.json`, `lib/local-models.nix`, and Gufo's own docs at the new tag (its model collection is the fleet's model set) |
| vicinae | `home/vicinae.nix` (client only) |
| nixpkgs-fresh | the kernels and Chrome; a new kernel is staged for the next reboot only |

Then leave exactly one comment on the PR that starts with
`<!-- update-digest <to_rev> -->` (the `to_rev` is in the PR body's
`update-check` marker). When an earlier digest comment exists on the PR,
edit it instead of adding a second. Write it for Tom: plain words, short,
no em-dashes. Three parts:

- **Worth taking**: a new feature or setting that improves something this
  repo does today, each with the exact change (file and line, the new value).
- **Touches us**: a change, removal or deprecation that affects our config,
  each with the file and line it hits.
- **Nothing for us**: one line naming what the rest of the notes cover.

For Gufo, also compare its model docs between the two tags and list any
model whose recommended revision or file changed, or any model it added or
dropped, against `lib/gufo-models.json`.

## 3. Take what needs no ruling

An item from "Worth taking" or "Touches us" goes onto the PR as its own commit
when it needs no ruling from Tom, for example:

- it replaces a workaround in this repo with the setting the release adds;
- it follows a rule already written in AGENTS.md or the dotfiles memory;
- it fixes our config for a rename or removal in this release.

Make the commit in a worktree of `update/<input>` under `~/.wt/dotfiles`
(never in `~/mecattaf/dotfiles`), with an ordinary message and **without** the
`Update-Check: bump` trailer: the next nightly run carries such commits onto
the rebuilt bump. Run the gate pieces the change touches (`nix fmt -- --check`
on the files, `nix flake check --no-build --keep-going`), push, then remove
the worktree and its local branch.

Anything else stays a proposal in the comment: a change of behavior Tom has
ruled on, a new program, model, timer, secret or service, or anything that
spends money or a subscription.

## 4. Report

One line per input: the status, the PR link, the versions, and either "digest
posted" or why not. For each item you committed, its short sha and one line.
