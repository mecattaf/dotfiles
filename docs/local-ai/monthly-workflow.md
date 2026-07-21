# Monthly local-AI community workflow

The monthly tally is the first durable local-model appliance workflow in this
repository. A frontier model authors and tests a versioned procedure; a loaded
local model executes that procedure through Pi and llama-swap. Improvement lives
in the skill and deterministic tools, not in hidden state or transferred model
weights.

## Scheduled surface

`home/tally.nix` gives Tally one executable:

```nix
argv = [ "${pkgs.local-ai-monthly}/bin/local-ai-monthly-tally" ];
```

The Home Manager Tally module materializes the monthly systemd calendar unit.
Tally admits the job at low priority, holds `worker-gpu`, applies a 12-hour
runtime ceiling, and records `exit:0` plus the fixed local witness at
`~/.local/state/local-ai-monthly/last-run.json`.

The process itself runs on `coordinator`: Git inspection, Pi, validation,
rendering, Git commit/push, and `gh pr create --draft` stay there. Pi's declared
llama-swap provider calls `http://worker-tb:9292`, so inference runs on `worker`
under the lease. Tally does not know the content of the workflow.

## Distilled appliance boundary

The package in `pkgs/local-ai-monthly/` contains:

- `sources.json`: reviewed GitHub repositories, anchor SHAs, watched paths,
  partition rules, quotas, and abstract inference classes;
- `skill/SKILL.md`: the local model's procedural memory;
- `extension.ts`: one process-local Pi context hook and two narrow tools;
- `workflow.py`: ordinary Git/HF/validation/rendering/publication code;
- `schema/brief.schema.json`: the model-output contract;
- tests for deterministic and fail-closed behavior.

Each bounded repository slice receives a fresh Pi invocation. Its extension
injects the prepared bundle through `before_agent_start`; built-in Pi tools are
disabled and the skill can call only:

1. `local_ai_inspect_hf` within quota, and only for Hugging Face repositories
   already named by GitHub evidence; this reads metadata and never model blobs;
2. `local_ai_submit_review` once, recording a structured result and terminating
   the task.

Every attempt gets a fresh `PI_CODING_AGENT_DIR`. Pi extension, skill, prompt
template, and context-file discovery are disabled; the command loads only the
Nix-wrapped llama-swap provider, this explicit extension, and this explicit
skill for that process. It neither installs Pi resources nor mutates global Pi
settings.

The model judges significance, local relevance, and how a finding relates to
the accepted roster. Deterministic code owns source choice, Git ancestry and
diffs, path filtering, partitioning, provenance, validation, pin advancement,
Markdown, and publication. One failed contract receives one clean repair
attempt; there is no open-ended loop.

## Strong baseline and model independence

`lib/local-models.nix` is the machine-readable accepted roster. The newest
merged file under `docs/local-ai/tallies/` supplies its human rationale and
known rejected/additional options. Every proposal must be classified as a net
addition, additional option, technical upgrade, strict supersession, or no
roster change and must name comparison targets when applicable.

The procedure does not name a checkpoint. It asks for `strongest` or `fast`:

- `strongest` resolves loaded canonical `quality`, then `general`, deployments;
- `fast` resolves loaded canonical `utility`, then the smallest `general` row.

The concrete model advertised by llama-swap is recorded in Tally's witness.
Replacing a model does not rewrite the skill.

## Durable output

A successful scheduled run opens a draft PR containing only Markdown:

- `docs/local-ai/tallies/YYYY-MM.md`, the concise monthly briefing;
- zero or more proposal-only cards under
  `docs/local-ai/proposals/YYYY-MM/<stable-id>.md`.

Proposal cards contain mechanically resolved HF revision, filenames, byte
counts, LFS SHA-256 values, Nix SRI hashes, the proposed runtime tuple, evidence,
and unresolved gaps. They do not register a catalog row. Promotion remains a
separate human edit to `lib/local-models.nix`; the independent
`downloadAllModels = false` gate is never touched.

The briefing carries a hidden JSON state block with accepted source SHAs. Only a
merged briefing advances the next comparison interval. Failed or oversized
sources retain their prior pin and are reported explicitly. Raw diffs, Pi JSONL,
submissions, and clones remain under `/run/user/$UID/local-ai-monthly/` and die
with the runtime directory; Tally retains the compact proof and trace locally.

## Later pooling and swarms

The reusable fan-out, diversity, quorum, reduction, typed-swarm, and Tally
resource rules are specified in
[`pi-appliance-pattern.md`](pi-appliance-pattern.md). The monthly job uses one
`strongest` member because its evidence preparation is predominantly
deterministic; the academic-OCR workflow is the likely first pooled example.

For a non-publishing inspection run:

```bash
local-ai-monthly --prepare-only
```

`local-ai-monthly-tally` is the publishing entry point reserved for Tally.
