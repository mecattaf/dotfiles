# Archived documentation

This directory held a lossless copy of the documentation tree that predated the
2026-07-22 local-AI reset. It was kept so the material could be mined; that
mining is done, and on 2026-08-03 the files were removed rather than left to rot
as a second, non-normative description of a system that had moved on.

Nothing was lost. Every file is in Git history and this stub is the index. The
last commit that contained them all is `74d76a53`, so any of them can be read
back without checking anything out:

```console
git show 74d76a53:docs/old/<path>
```

## Where the material went

| Removed file | Disposition |
|---|---|
| `migration-journal/ds4-dual-node-lessons.md` | Mined into [`../local-ai/dual-node-inference-lessons.md`](../local-ai/dual-node-inference-lessons.md), which preserves the transferable operational lessons and the measured result. The full build report, appendix, and container invocations remain in history. |
| `local-ai/tallies/2026-07-22.md` | Superseded twice: by the 2026-07-26 Q8/two-node anchor and then by [`../local-ai/tallies/2026-07-29.md`](../local-ai/tallies/2026-07-29.md), the current anchor. |
| `local-ai/tallies/2026-07-26.md` | Superseded by the 2026-07-29 coordinator-only anchor after the `worker` host was retired. Its Q8 precision policy survives in the current roster and in a flake assertion. |
| `llm-agents-catalog.md` | Recorded the maximalist ~139-agent `llm-agents.nix` sweep. The conclusion — prune to an explicit allowlist — is implemented and explained inline in `home/home.nix`. |
| `strix-halo-llm.md` | Community watch doctrine and specialized-lane map from 2026-07-11. Its live successor is the monthly review in [`../local-ai/monthly-workflow.md`](../local-ai/monthly-workflow.md). |
| `strix-halo-community-digest.md` | The 2026-07-11 deep-pass baseline and delta-refresh protocol behind that doctrine. Same successor. |
| `zenbook-duo-flash.md` | Already self-marked superseded on 2026-07-05; its manual-USB path predates the nixos-anywhere + disko + `--extra-files` flow and delivers no offline ssh host key. Kept in history as a warning, not as a procedure. |
| `migration-journal/nvim-sweep.md` | The nvim → Nix migration plan. Completed; the live configuration under `home/nvim/` is the result and the authority. |
| `migration-journal/remote-access-mesh.md` | The 2026-07-05 wayvnc + Remmina + SSH mesh design that replaced the abandoned Sunshine/Moonlight plan. |

## Why this stub still exists

Two things outside `docs/` still name this path: the repository `README.md`
index and a comment in `home/home.nix` that cites the llm-agents sweep. Keeping
`docs/old/README.md` means those references resolve to an explanation instead
of a 404. Current truth lives in [`../local-ai/`](../local-ai/) and in the live
Nix modules.
