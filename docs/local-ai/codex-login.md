# The Codex login on this fleet — paths only

**One sentence, and it is the whole page: `/home/tom/.codex/auth.json` is the
ONE Codex login on the coordinator, and since 2026-09-05 it is Nayla's, not
Tom's** (RULINGS.md R-2026-09-06-02).

Nothing in this repository said so until now, and everything about the wiring
reads the other way: an agenix secret with Tom's name on the machine, seeded
into Tom's home directory, restored on every rebuild. Anyone running `codex`
from this box — Tom at 5 a.m. included — spends Nayla's window and has no
reason to suspect it.

## What is where

| Path | What it is |
|---|---|
| `/home/tom/.codex/auth.json` | The live Codex CLI session. Nayla's. |
| `secrets/codex-auth.age` | The agenix secret it is seeded from. |
| `modules/secrets.nix` | The file that decides that seeding. Coordinator-only. |
| `/home/tom/.codex/sessions/` | Rollout transcripts. Not credentials; `nightly-record` reads them for token counts (dotfiles#298). |

`modules/secrets.nix` seeds the live file ONCE — only when it does not already
exist — because a read-only `/run` symlink cannot be the file the CLI writes
back to. So the live file is not managed after first seeding: rotating the
secret does not rotate what is on disk, and deleting the live file is what
makes the next activation re-seed it.

## The rule

- This file is **named by path and never opened** by anything in this
  repository, by any check, by any flow, and by any agent working in this tree
  (PROMPTS.md header, credential-file lock). No contents, no token shapes, no
  example values — here or anywhere.
- **Tom's own Codex login does not go in `/home/tom/.codex`.** It needs a
  `CODEX_HOME` he names, pointing somewhere else, so that the two subscriptions
  stay two subscriptions. Until he names one, every Codex run from this box is
  Nayla's spend.
- The `codex` pool in `home/tally.nix` (dotfiles#291) rations THIS login. That
  is the reason it has a cap at all.

## What this page is not

It is not a runbook for logging in, not a description of the credential
format, and not a record of which account is which beyond the one sentence at
the top. If the ownership changes, RULINGS.md is where it changes, and this
page follows.
