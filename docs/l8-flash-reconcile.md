# `l8-flash`, reconciled

**What this page is.** The record of how the `l8-flash` branch reached `main`,
what the reconciliation is checked by, and which half of it is not a repository
act at all. It is a page about git topology and one deletion, not about the
branch's contents; those are `receipts/L8-FLASH/PR-BODY.md` in the research
notes and the thirty commit messages themselves.

Issue: [mecattaf/dotfiles#319](https://github.com/mecattaf/dotfiles/issues/319).

## The motion

Long-lived branches in this repository reach `main` by **merge**, not rebase and
not squash. `ad8a9119` — `herdr: merge herdr-clean-slate (11 commits) for
L8-FLASH` — is the pattern: the branch's own history is preserved, and the merge
commit names the count, the issues and the cross-repo reference. `l8-flash`
followed it.

The reconciliation, pinned:

| | |
|---|---|
| forked at | `88c7c755` (`ad8a9119`'s first parent) |
| head | `e549ba911e8d8c9ff1c19b4fa9b0b6df45244f7f` |
| commits | 30 — 18 on the first-parent line, 12 brought by the herdr merge |
| state | `git merge-base --is-ancestor e549ba91 main` answers yes; `git rev-list --count main..l8-flash` is 0 |

The branch is therefore only history. Nothing further is merged from it, and a
re-verification that comes back green is a re-verification, not an invitation to
merge again.

## Why the ORDER was the blocker, and still is

`home/home.nix:15`:

```nix
repoDir = "${config.home.homeDirectory}/mecattaf/dotfiles";
```

Every raw dotfile is an out-of-store symlink anchored **there** — at a hardcoded
path, not at the flake source a switch is taken from ([#313]). So a
`nixos-rebuild switch --flake <some worktree>#coordinator` delivers the STORE
half of a branch — packages, units, module options — and silently drops the RAW
half. The declared `claude-transcript-mirror` and `nightly-record` units render
and start with their `ExecStart` programs absent; `cleanupPeriodDays` never
reaches `~/.claude/settings.json`; `l8-flash-probe` is not on `PATH`.

The consequence for this unit is one sentence: **`/home/tom/mecattaf/dotfiles`
must carry the branch before any switch, and the switch is taken from that
path.** Reconciling first is not tidiness, it is the precondition. The switch
itself is U-D19's act, in the P05 walkthrough's order; this unit does not switch
either box and does not restart `llama-swap`.

[#313]: https://github.com/mecattaf/dotfiles/issues/313

## The hand-written mirror pair

Until this branch, the transcript mirror was two plain files owned by nothing:

```
~/.config/systemd/user/claude-transcript-mirror.service
~/.config/systemd/user/claude-transcript-mirror.timer
```

`home/harness-records.nix:70`/`:102` declares the replacement, and
`home/dot_local/bin/claude-transcript-mirror` is the script, tracked. The
declaration is on `main`.

**home-manager will not write over a plain file of the same name.** So while
those two files exist the switch reports success and the declaration is inert —
the mirror keeps running from the untracked pair, and nothing says so. The
deletion is therefore a real step, and it is split:

* **The repository half** is this unit's and is done: the declaration is on
  `main`, no plain unit file of either name is tracked, `l8-flash-probe` carries
  a row that reports whether the pair is still there, and that row is asserted
  in the flake in all four states that matter.
* **The shell half** — `systemctl --user disable --now
  claude-transcript-mirror.timer` and the two `rm`s — is Tom's own act
  (`scopes/clean-dotfiles.md:171` §6) and is step 4 of the P05 walkthrough. It
  must not happen before the switch that replaces it, because until then the
  hand-written pair is the only working mirror. It is carried as `DEFERRED.md`
  row **DF-U-D16-1** and sequenced inside U-D19.

So the probe's `[E] hand-written pair gone` row ships RED, deliberately, and
goes green when Tom takes step 4. It is switch-evidence, which is what `[E]`
means.

## The oracle

```
bash tools/u-d16-l8-flash-oracle.sh
```

Exit 0 iff every clause holds. One line per clause with the argv that produced
it, and no `set -e`, so a red run says everything that is wrong rather than the
first thing — the same shape as `l8-flash-probe` (#301).

| clause | what it establishes |
|---|---|
| 1 | ancestry: `e549ba91` is an ancestor of `HEAD`, `HEAD..head` is empty, the range is 30 commits, and `ad8a9119` is still a merge commit — the branch was not squashed or rebased into something the commit map no longer describes |
| 2 | content closure against `tools/u-d16/`, plus the coverage assertion that every one of the 30 commits touches at least one row |
| 3 | `nix flake check --offline --no-build` |
| 4 | `nix build --offline --dry-run` of the coordinator toplevel |
| 5 | the hand-written pair: the repository half gated, the shell half reported as `NOTE` |

Clause 5's split is the honest one. An oracle that gated on the box-side files
would be demanding that this unit break the mirror, so their state is printed
and does not count. `NOTE` rows never gate.

### Why clause 2 exists

Ancestry cannot see a revert. `git revert` of any of the thirty **adds** a
commit, so clause 1 stays green while the branch's content is undone. That is
precisely the mutation this unit is graded against, so the content is pinned as
well as the topology, in `tools/u-d16/`:

| file | rows | meaning |
|---|---|---|
| `closure-blobs.tsv` | 46 | exact blob sha, for paths `main` has not touched since `e549ba91` |
| `closure-absent.txt` | 22 | paths the branch DELETED, which must stay deleted |
| `lines/` + `closure-lines.tsv` | 5 files | for paths `main` HAS touched since: the lines the 30 commits added that still survive |

46 + 22 + 5 = 73, the number of paths `git diff --name-status 88c7c755
e549ba91` reports.

A line the 30 commits added and a later `main` commit legitimately rewrote is
**dropped** from the manifest rather than pinned; pinning it would make the
oracle red for something that is not a regression. Coverage is then asserted
rather than assumed: clause 2d walks all thirty commits and fails if any of them
— excepting the two internal merges whose diff against their first parent is
empty — touches no row, because such a commit could be reverted invisibly.

Regenerate after any commit that legitimately edits a manifested path, and say
in the commit message which row moved and why:

```
bash tools/u-d16/regenerate-closure.sh
```

It refuses if `88c7c755..e549ba91` is not 30 commits.

## Measured

At `020b2ad1`, in `/home/tom/mecattaf/dotfiles-rw-wt/U-D16`:

```
bash tools/u-d16-l8-flash-oracle.sh
  -> 15 passed, 0 failed, 1 noted; rc 0

git revert --no-edit 617ced65
  -> FAIL 2a 1 of 46 pinned blobs differ; rc 1

git rebase --onto 617ced65^ 617ced65
  -> FAIL 1b, FAIL 1c (HEAD..head = 12), FAIL 2a; rc 1
```

The two mutations are the two readings of the issue's `mutation_hint`
("revert one of the 30 commits in the worktree"): a revert commit, and dropping
the commit from history so `main..l8-flash` is genuinely non-empty. Both are
red, so the oracle does not depend on which was meant.

## What this unit did not do

No switch on either box; no `llama-swap` restart; no removal of the two
hand-written files. See `DEFERRED.md`.
