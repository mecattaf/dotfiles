# Monthly local-AI update bot

This workflow is a narrow update bot for the local-model source roster. Its
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
  -> Nix build: prepare immutable evidence + exact HF request set
  -> fetch those HF metadata API responses (blobs=true metadata, never blobs)
  -> Nix build: validate and fold metadata into the evidence bundle
  -> Tally child waits for worker-gpu
       -> invoke Pi once through llama-swap, without tools
       -> write advisory PR commentary
  -> release worker-gpu
  -> Nix build: validate commentary and render the complete PR body
  -> disposable Git worktree: replace only sources.json, build, commit, push
  -> create or update the month's PR
  -> human review and merge advances the accepted pins
```

The calendar parent holds only the `local-ai-review` mutex. Deterministic Git,
Nix, HTTP, and publication work therefore does not reserve VRAM. The parent is
allowed one child enqueue; that low-priority child alone holds `worker-gpu` for
the Pi process and releases it immediately afterward. This uses the same Tally
calendar-to-opaque-argv shape as the nightly fleet updates, with a nested lease
because only one stage consumes the scarce resource.

## Deterministic preparation

`sources.json` is the reviewed data plane: exact accepted pins, categories,
watched and ignored path globs, evidence bounds, HF bounds, and abstract model
selection. JSON remains the boundary because Git, `jq`, the Nix builders, and
the receipt all consume it directly.

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
- a source exceeding an evidence limit is `needs-split`, remains visible in
  the briefing, and retains its old accepted pin;
- the `llm-agents.nix` package before/after sets are computed mechanically;
- exact Hugging Face repository URLs in the captured evidence become the only
  metadata request set;
- request count, response size, repository identity, immutable HF revision,
  file sizes, LFS SHA-256 values, and Nix SRI values are validated before Pi.

The two Nix builds around the metadata fetch make the impurity explicit. The
first derivation consumes the captured Git bytes and emits the request set. The
host performs the bounded HTTP contacts. The second derivation consumes those
exact responses and emits the final immutable bundle. Neither evaluation nor a
builder contacts the network.

## The one Pi operation

Pi is retained as the standard local-agent harness, but this workflow adds no
task-specific Pi extension and exposes no tools. The only extension loaded is
the existing, immutably pinned `pi-llama-swap` provider required to register
llama-swap as a Pi provider.

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

The concrete model is not hardcoded. The preparation derivation intersects the
configured `strongest`/fallback role order with the canonical typed catalog and
the model IDs currently advertised by llama-swap. The chosen class, deployment,
model, backend, and RAM tier are captured before inference and written to the
receipt.

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
merges its own PR, edits `lib/local-models.nix`, downloads weights, changes
`downloadAllModels`, or deploys a service.

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
