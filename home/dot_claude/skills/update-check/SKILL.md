---
name: update-check
description: Run the dotfiles nightly update check on the strix and digest what each update brings. Use when the substrate update-check routine fires, when Tom asks for the update check, or to read an open update/<input> PR on mecattaf/dotfiles against the repo and propose the new features worth taking.
---

# Update check

The nightly update check is mechanical by default (#550). The optional digest is comment-only. The clock is a routine on the
substrate floor (substrate T-7); nothing in dotfiles schedules it. The logic
is here: `update-check` (home/dot_local/bin/update-check) does every
mechanical step, and this skill is the part that reads.

You never merge, switch, deploy, restart a unit, close an issue or touch the
`~/mecattaf/dotfiles` working tree. Merging is Tom's word, and so is every
switch.

## 1. Run the check

On the strix:

    update-check --if-idle --background --json

The Projects routine fires at 01:17–06:17 Europe/Paris, giving the first idle
hour a chance. `--if-idle` defers for load, Nix builds or working/unknown Herdr
agents and checks again between inputs. It records one completed full attempt
per Paris night (noon to noon), including a failed attempt (no hourly rebuild loop). A deferred
run does not consume the night. The stamp and every skip/report live in
`~/.local/state/update-check`; failures return nonzero. Unreadable idleness
signals are errors, never permission to proceed. Manual `update-check --json`
bypasses admission and the nightly stamp, but still never activates anything.
If every opportunity is busy, the persisted deferred reports are the receipt;
there is no catch-up or forced start. No local timer is installed.

`--background` launches a separate process session so the checker survives
the Floor runtime's 30-minute turn limit. The parent transfers its held lock
to the worker: overlapping firings cannot launch a second run. A `launched`
receipt names its PID, durable job JSON and log; it proves launch, not success.
The job moves through `running` to `completed`/`error`. Later locked firings
report the active job; later completed-night firings include the previous full
result and return nonzero again if it failed. A worker that disappears without
a final result is surfaced as `interrupted` before another launch. Read these
receipts in the routine's report; never claim a check passed from launch alone.

It fetches main, compares each input in `lib/update-watch.json` with upstream,
and for each one that moved it rebuilds the rolling branch `update/<input>`,
runs the gate and opens or refreshes one PR. Read the per-input `status`:

| status | meaning | your part |
|---|---|---|
| `opened`, `refreshed` | a PR now carries a new version | report; digest only on explicit request |
| `unchanged` | the open PR already carries the newest versions | nothing |
| `no-version-change` | upstream moved, nothing we use changed version | nothing |
| `current`, `closed` | main already carries upstream | nothing |
| `issue-opened`, `issue-exists` | a new stable kernel series needs review | report the issue; no pin edit |
| `review-pending` | main carries the input but review commits remain | keep the PR open; report it |
| `error` | the check itself could not finish | report the error line, do not retry in a loop |

Top-level `deferred` or a successful `already-checked` is a normal scheduler
skip. An `already-checked` previous failure remains a failure to report. Do not
retry it, remove the stamp, override admission or start a build yourself.

A PR whose gate failed is a draft with the log tail in its body. Name it in
your report. Fix it only when the cause is plainly in this repo and small,
such as an option a new release renamed. Otherwise leave it for Tom.

## 2. Optional digest, only when Tom asks

The nightly routine does not invoke this section. An explicit request to
digest authorizes one PR comment only: no commits, pushes or config changes.

Imported upstream notes stay inside collision-safe literal text fences. The
checker links the original release page outside each excerpt. Keep this boundary
in digests too: never paste contributor mentions or upstream issue/PR references
as active Markdown into a body or comment. Attribute in plain text and link the
release page. Code examples and source text belong inside a literal fence.

The PR body holds the version table and the upstream release notes for
exactly the range between main and the PR. GitHub caps a PR body, so a long
release is cut and links its full notes: read every cut one in full
(`gh api repos/<owner>/<repo>/releases/tags/<tag> --jq .body`) before you
judge it. Read them against what this repo does with the program:

| input | where the repo uses it |
|---|---|
| llm-agents: claude-code | `home/dot_claude/settings.json` (the template), `home/claude-settings.py` (the initializer), the `cc`/`cc2` launchers and their env in `home/dot_config/fish/config.fish`, `home/dot_claude/skills/`, the `no-claude-code-hooks` flake check, the seats paragraph in AGENTS.md |
| llm-agents: codex | `home/home.nix` (`.codex` links), the codex runtimes in `modules/substrate.nix` and `hosts/strix/default.nix`, `seats` (`home/dot_local/bin/seats`) |
| llm-agents: dsh | `pkgs/dsh` (the wrapper, the policy overlays in `config.nix`, `sessions.patch.yml`, the `dsh-bwrap` runner), `home/dsh.nix`, `checks.dsh-config` and `tests/dsh-config/`, the dsh reader in `seats` (`dsh_qwen_usage`; its field names follow the session format). A row id the policy names that a release drops shows as stderr in the check |
| herdr | `home/herdr.nix`, `home/dot_config/herdr/`, the herdr pin comment in `flake.nix` |
| gufo | `modules/gufo.nix`, `lib/gufo-models.json`, `lib/local-models.nix`, and Gufo's own docs at the new tag (its model collection is the fleet's model set) |
| vicinae | `home/vicinae.nix` (client only) |
| nixpkgs-fresh | the kernels, Chrome, uv, fish, kitty and Wrangler; a new kernel is staged for the next reboot only |

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

## 3. Report

One line per input: status, PR or issue link, versions and any gate error.
State whether a digest was requested and posted. Leave every adoption as a
proposal in the comment. The checker preserves earlier review commits when
refreshing a PR; a conflict aborts the refresh and leaves the remote intact.

Fish, kitty and Wrangler follow the existing nixpkgs-fresh leaf overlay.
Linux watches kernel.org's stable releases, ignores release
candidates and compares major.minor against each host's configured kernel,
including the strix's nixpkgs-fresh kernel. Patch bumps stay in the ordinary
nixpkgs-fresh PR. Closed version issues remain closed and are not reopened.
