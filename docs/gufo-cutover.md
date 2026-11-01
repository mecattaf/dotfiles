# Gufo provider cutover

Current utility contract (1 November): NAS keeps agent sessions and the
`utility-model` client; Gufo on `http://strix-coordinator:8731` serves
`qwen3.8-flash-next`. Print rendering runs on that coordinator with its own
renderer/fonts closure, while NAS owns the print queue and receipts. The monthly
evidence judge also calls `utility-model` directly and has no agent tools.
DSH is the agent harness; these utility calls do not invoke it. The worker is
dormant and receives no compute or inference work. The migration table below
records the earlier provider cutover, including retired Pi/Tally interfaces;
it is historical context, not the current harness configuration.

Tom, 2026-10-23: "just read in previous output of yours also: halogen is OUT fullly as inference provider (moving to gufo-rdma) and as models (we use the gufo-specific ones)"

PR #605 retires the provider and model formats as well as the service. The
local provider/runtime/seat is `gufo`; the local HTTP model IDs are
`qwen3.8-flash-next`, `qwen3.8-27b` and `deepseek-v4-flash`, exactly as
`lib/local-model.nix` and Gufo declare. The default remains Flash-Next
UD-Q4_K_XL with its MTP predictor and vision projector. The `utility` wrapper
is a stable application model ID, forwarded to the exact Gufo ID; it is not
an inference provider.

This PR keeps upstream Gufo v0.20.0 on `strix:8731`. The gufo-rdma fork,
paired compute-host setup and host rename are separate changes. The provider
name is independent of that transport change.

## Contracts that must move together

| Boundary | Change carried here | Required outside this branch |
| --- | --- | --- |
| pi and sandbox catalogs | `providers.gufo`, `--provider gufo`; sandbox catalog uses 102400 context, 16384 output limit, vision and thinking off | Any separately managed pi/DSH catalog or remote caller must use `gufo` and the exact served Gufo ID. The old IDs receive no alias. |
| Mutable Substrate catalog | Compiled defaults and seed name `qwen3.8-flash-next`; omitted pi provider now means `gufo` | Inspect `~/.config/substrate/models.toml`: replace explicit `provider = "halogen"` with `provider = "gufo"`, remove old model IDs, and update the local model metadata. Preserve unrelated cloud rows. Nix only seeds a missing file and never rewrites an existing one. |
| Runtime routing | `runtime.gufo`, `[seats].pi = "gufo"`, `seat = "gufo"`, `seat:gufo`; the explicit `ssh:strix` runtime keeps its name and spends `gufo` | Update external workflows, floor routines, session defaults and submitted `runsOn`/`runtime` values. Existing queued or resumable work naming the old seat/runtime needs an explicit reviewed reissue or metadata migration; do not silently translate history. |
| Capacity | The oracle's `gpu-strix` row has provider `gufo`; the pusher maps it to floor seat `gufo`; the shared planner recognizes Gufo slot capacity | Carry the vendored source delta into agency-agency/substrate and deploy its Cloudflare floor/planning code before publishing the new seat. A floor using the original projector recognizes only the old provider as a slot seat; merely accepting a provider slug is insufficient. Retire the old capacity row or let it expire; publish a fresh Gufo snapshot rather than relabeling cached evidence. |
| Link and gateway | Defaults become `LINK_SERVED_LABELS=seat:gufo,runtime:gvisor`, `LINK_GATEWAY=gufo`, `LINK_SEAT_COMMANDS={"gufo":["ax-agent","pi"]}`; AgentJobs use the exact Gufo model ID | The NAS no longer declares the retired ax/link service. Any external use of this link still requires its gateway, egress endpoint, agent image/catalog and producer labels to move together. This source update neither recreates nor deploys ax. |
| Legacy live-dispatch gate | Source opt-in variable becomes `AX_CONWIP_LIVE_GUFO`; helper exports and allowed-seat list use Gufo | External invocations/importers must adopt `GUFO_PROVIDER`, `GUFO_MODEL`, `GUFO_BASE_URL`, `piGufoModels`, `gufoAdapter` and `makeGufoOutcomeOf` in place of their retired-name exports, as well as the new environment variable. The old opt-in does not enable the new path. These legacy tools remain opt-in. |
| Vendoring | `pkgs/substrate-apps/src` carries a local patch over upstream base `200767b`; its lockfile is unchanged | Upstream the same contract changes before a future `sync.sh`, or the resync will restore the removed provider. `SYNC.md` records the local delta. |

No old provider alias is kept. The remote floor and separately managed
callers are not changed by a Nix build or this PR's creation. Coordinate
their updates before enabling new dispatch. The puller deliberately has
`restartIfChanged = false`; running sessions keep their loaded code until a
planned drain/relaunch. Do not restart Herdr, the user manager or live jobs
to perform this migration.

## Weights and historical material

The two `.hgn` catalog rows and their wanted-set entries are removed. Tom
approved deletion of their leased Strix copies on 2026-10-23. Historical
Library copies remain under `/mnt/nas/models/weights/halogen-*`; no supported
server or active catalog row uses them. Their eventual Library retirement is
an explicit transaction under [the model archive runbook](nas/model-archive.md),
not activation or a directory cleanup in this PR.

The obsolete handwriting/OCR experiment programs and topology probes are
removed, rather than relabeled as Gufo benchmarks. Their Markdown research
and original `source-manifest.json` remain provenance. That immutable
manifest contains four path references to two historical Markdown reports;
it is not a model catalog or runnable backend. Rejection assertions also
retain the retired name to prevent its return. The telemetry sampler no
longer reads the old engine's log format: Gufo token counts remain explicitly
UNKNOWN until calibrated, while generic offline token-window replay is
still supported.

Existing call-cleanup evidence, agent transcripts, archived records and
capacity history are not rewritten. New cleanup output uses `cleanup/gufo/`.
