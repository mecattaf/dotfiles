# Monthly local-AI update bot

This workflow is a bounded monthly model census and source-pin update bot. Its
trust protocol follows `nixpkgs-update`: a bot proposes a pinned transition and
arrives with enough evidence to review it cheaply, but only a human merge can
make the transition accepted state.

The implementation does not import or fork `nixpkgs-update`. That project is a
Haskell application specialized to nixpkgs attributes, package update scripts,
derivation comparison, and `nixpkgs-review`. The reusable part here is its
protocol: pinned before/after state, disposable Git worktrees, mechanical
verification, evidence-rich PRs, and merge-only authority.

## One monthly walk

```text
Tally calendar: local-ai-review mutex
  -> clone dotfiles main into /run/user/$UID
  -> clone each enabled source without checkout or blobs
  -> prove old pin is an ancestor of the exact observed head
  -> capture watched paths, commits, diffs, pickaxe history, and package sets
  -> rescan bounded current-head candidate inventories, prioritizing Q8 paths
  -> GET /v1/models from the Halogen server; it must advertise the served model
  -> Nix build: prepare immutable evidence + exact HF request set
  -> fetch those HF metadata API responses (blobs=true metadata, never blobs)
  -> Nix build: validate and fold metadata into the evidence bundle
  -> Tally child waits for the registry's tally_pool (coordinator-gpu)
       -> invoke Pi once against the halogen provider, without tools
       -> write advisory PR commentary
  -> release that pool
  -> Nix build: validate commentary and render the complete PR body
  -> if source pins are unchanged, record a completed census without a PR
  -> disposable Git worktree: replace only sources.json, build, commit, push
  -> create or update the month's PR
  -> human review and merge advances the accepted pins
```

The calendar parent holds only the `local-ai-review` mutex. Deterministic Git,
Nix, HTTP, and publication work therefore does not reserve VRAM. The parent is
allowed one child enqueue; that low-priority child alone holds the pool named
by `inference.tally_pool` in `sources.json` (`coordinator-gpu`) for the Pi
process and releases it immediately afterward. The Pi process runs on the
coordinator; the model it talks to is the Halogen Flash server on the worker.
This uses the same Tally calendar-to-opaque-argv shape as the nightly fleet
updates, with a nested lease because only one stage consumes the scarce
resource.

## Deterministic preparation

`sources.json` is the reviewed data plane: exact accepted pins, categories,
watched, ignored, and inventory path globs, evidence bounds, HF bounds, fleet
hardware, the `inference` block (provider `halogen`, URL `http://worker:8731`,
model `halogen-qwen3.8-flash-next`, execution host `coordinator`, compute host
`worker`, Tally pool), and the mono-model selection policy with its list of
kept small Library artifacts. JSON remains the boundary because Git, `jq`,
the Nix builders, and the receipt all consume it directly.

Each enabled monthly or on-change Git source is cloned into a new directory
under `/run/user/$UID`; the workflow never runs a broad cleanup command. Clones
use `--filter=blob:none --no-checkout --no-tags`, so Git fetches only the trees
and watched blobs needed for the interval. A failed clone receives one second
attempt in another new directory. Every source records its own observation
time and exact head.

Preparation is fail-closed:

- a missing or non-ancestor accepted pin stops the run;
- watched-path selection happens before Pi exists;
- changed blobs and captured diffs have reviewed byte limits;
- bounded current-head inventory excerpts are collected even with no Git delta,
  with Q8/8-bit paths ranked before lower-bit alternatives;
- a source exceeding an evidence limit is `needs-split`, remains visible in
  the briefing, and retains its old accepted pin;
- the `llm-agents.nix` package before/after sets are computed mechanically;
- exact Hugging Face repository URLs in captured diffs, current-head inventory,
  and the accepted model catalog become the only metadata request set;
- request count, response size, repository identity, immutable HF revision,
  file sizes, LFS SHA-256 values, and Nix SRI values are validated before Pi.

The two Nix builds around the metadata fetch make the impurity explicit. The
first derivation consumes the captured Git bytes and emits the request set. The
host performs the bounded HTTP contacts. The second derivation consumes those
exact responses and emits the final immutable bundle. Neither evaluation nor a
builder contacts the network.

## The one Pi operation

Pi is retained as the standard local-agent harness, but this workflow adds no
task-specific Pi extension, loads no extension at all, and exposes no tools.
The provider is the plain `halogen` entry in Pi's declared `models.json`
(`home/pi.nix`): the worker's Halogen Flash server at `http://worker:8731/v1`,
OpenAI-compatible, no authentication. The judge checks that `models.json`
declares that provider with the registry's model id before Pi starts, and
copies the declaration into the run's private agent directory so the fresh
`PI_CODING_AGENT_DIR` can resolve it.

The invocation has a fresh `PI_CODING_AGENT_DIR`, no session, and disables
ambient extensions, skills, prompt templates, context files, approval, and all
tools. It receives only:

- the immutable Markdown prompt;
- the deterministic evidence bundle;
- the accepted local roster/rationale;
- the preloaded HF metadata.

Pi writes one bounded Markdown commentary file. It cannot see the publication
worktree and cannot call Git or GitHub. A final Nix derivation checks the output
shape and combines it with mechanical facts. Pi's prose is therefore an
unverified recommendation, never an instruction or state transition.

The accepted context (`context.md`) is rendered mechanically from
`sources.json`: the mono-model policy summary, the served-model line
(`halogen-qwen3.8-flash-next` through provider `halogen` at
`http://worker:8731` on `worker`), the kept small Library artifacts
(`qwen36-35b-a3b-mtp-ud-q8-k-xl`, `gemma4-12b-it-q8-0`,
`gemma4-12b-it-mtp-q8-0`, `fara15-9b-q8-0`, `fara15-9b-mmproj-bf16` — served
by hand, never declaratively), the runtime and change policies, and the fleet
hardware table with each host's policy string (the coordinator's reads `NPU
decommissioned 2026-08-29; IOMMU off (amd_iommu=off)`). Preparation refuses
if a kept artifact is missing from the typed catalogue. The prompt tells Pi to
respect that policy: a Halogen Flash server release or a change to its
runtime profile is the finding that matters most, other served-model
candidates are at most watch items, and any relevant model finding must
include an exact candidate/quant table.

The concrete model is named by the registry, not by the prompt or the code:
`inference.model` is `halogen-qwen3.8-flash-next`. Before any Tally slot is
spent, the supervisor fetches `/v1/models` from `inference.url` and the
preparation derivation refuses unless that id is advertised. The provider,
endpoint, compute host, and model id are written to `model.json` before
inference and carried into the receipt.

## PR and accepted state

The generated branch is `automation/local-ai-review-YYYY-MM`. A disposable Git
worktree starts from the current remote base and stages exactly one file:

```text
pkgs/local-ai-monthly/sources.json
```

The replacement registry is a Nix output. Only successfully bounded sources
advance to their observed heads; `needs-split` sources keep their previous
pins. The candidate must pass JSON validation, `git diff --check`, the exact
staged-path allowlist, and `nix build .#local-ai-monthly` before it is pushed.
A rerun updates the period branch with a force-with-lease and edits the existing
open PR when present.

The PR body contains the exact intervals, deterministic checks, and Pi's
advisory commentary. No generated commentary or hidden state is committed.
Abandoning the PR therefore leaves every accepted interval unchanged; merging
the registry change advances the next month's left edge. The workflow never
merges its own PR, edits `lib/local-models.nix`, changes a host allowlist,
downloads weights, or deploys a service. A no-delta month still runs the
bounded census and advisory review, then exits without manufacturing a
source-pin PR.

## Proof and lifetime

Raw clones, HTTP responses, evidence, Pi state, commentary, and worktrees stay
under the unique runtime directory and disappear with `/run/user`. Git and
Tally are the only durable ledgers. The fixed Tally artifact
`~/.local/state/local-ai-monthly/last-run.json` is rewritten on success and
failure with exact source intervals, selected model, Nix output paths,
commentary digest, PR URL, and the assertion `no_model_blobs: true`; Tally
hashes that receipt as job evidence.

`local-ai-monthly --prepare-only` exercises the complete no-GPU path through
HF enrichment and stops before the nested Tally/Pi job. The publishing entry
point is reserved for the declared Tally producer.
