# Pi appliance workflow pattern

This is the reusable mechanism behind durable local-model workflows in these
dotfiles. A frontier model authors and refines inspectable procedural memory;
replaceable local models execute it through Pi and llama-swap. Tally sees one
top-level executable and contributes scheduling, resource admission, and proof.

The monthly source-review bot is the deliberately smaller first implementation:
one tool-less Pi judgment over fully prepared evidence. The patterns below are
design guidance for future workflows that genuinely require tools, repair, or
multiple model members; they are not complexity the monthly bot carries.

## One atomic member

Every model task has five versioned parts:

1. an immutable, bounded input bundle prepared by ordinary code;
2. one self-contained Pi skill describing the judgment procedure;
3. a selective list of task-specific tools with hard quotas;
4. a structured result schema plus deterministic semantic validation;
5. one repair attempt in a fresh Pi process when validation fails.

Pi is the agent harness. A workflow executable may invoke Pi repeatedly, but it
must not recreate Pi's agent loop, provider layer, sessions, or tool protocol.
Built-in general-purpose tools are disabled when narrow tools suffice.

The trace for a member records at least the task ID, concrete provider/model ID,
skill and workflow revision, input digest, tool-call outcome, output digest,
validation errors, repair count, and terminal status. Raw context may remain in
the runtime directory; the compact lineage belongs in Tally's local witness.

## Abstract model selectors

Workflow procedure names a capability class, never a checkpoint. Current
single-member classes are `strongest` and `fast`, resolved against the accepted
catalog and the models currently advertised by llama-swap.

A pool selector extends that vocabulary without changing the task contract:

```text
pooled-fast(4, diversity=base-family)
pooled-strongest(3, diversity=maker)
```

`count` is the required number of independent members. `diversity` prevents a
pool from becoming several nearly identical quants or fine-tunes when the goal
is broader hypothesis coverage. Useful keys include base checkpoint family,
maker/frontier lab, architecture, fine-tune lineage, backend, and modality.
Resolution is deterministic and its concrete member list is written to the
witness before inference begins.

## Pool: map, validate, reduce

A pool explores the latent space of several small models over the same facts:

```text
immutable task bundle
  ├─ Pi member A ─ validate ─ candidate A
  ├─ Pi member B ─ validate ─ candidate B
  ├─ Pi member C ─ validate ─ candidate C
  └─ Pi member D ─ validate ─ candidate D
                         ↓
               typed reducer input
                         ↓
                 one final result
```

Each member gets a fresh Pi process, the same immutable evidence, the same skill
revision, the same narrow tools, and no other member's answer. This preserves
independence. Each candidate must pass the task schema and provenance rules
before it can enter reduction.

The reducer is explicit:

- `identity` for one member;
- `deterministic` for union, keyed deduplication, voting over exact enums,
  numeric aggregation, or other semantics ordinary code can own;
- `pi-aggregate(<class>)` when synthesis itself requires judgment. The
  aggregator receives only the original task identity, validated candidate
  outputs, their model IDs/digests, and stable evidence handles. It does not
  receive hidden transcripts and may not invent evidence.

An aggregator must preserve dissent. It records which candidates support each
conclusion, which conflict, and which were excluded by validation. “Majority” is
not evidence and does not erase a minority result backed by stronger primary
provenance.

## Swarm: typed stages, not free-form delegation

A swarm composes the same primitive as a small declared DAG. Each stage has its
own skill, input schema, output schema, tool list, selector, quota, and reducer.
For example, academic OCR might use:

```text
document partition
  → pooled-fast visual extractors
  → deterministic layout/table normalization
  → pooled-fast discrepancy critics
  → strongest reconciliation aggregator
  → deterministic page/result validation
```

Stages communicate only through validated artifacts. A parent does not expose a
child's specialist tools to itself, and a child does not inherit general shell
or network access. This is procedural fan-out/fan-in, not an unconstrained chat
between agents.

## Quorum, repair, and failure

Every fan-out declares `required_members`, `minimum_valid`, and whether partial
reduction is allowed. A missing or invalid member is visible in the reducer
input and witness. It is never silently replaced by duplicated output from a
surviving model.

Each member receives at most one clean contract-repair attempt. Reducers follow
the same rule. If quorum is not met, the stage fails closed and durable state
does not advance. A task-specific workflow may still render a degraded human
briefing, but it must say which members or stages failed.

## Tally and compute ownership

Tally still schedules one executable. A workflow that consumes one fixed
resource set declares it before admission. A linear workflow with substantial
non-GPU work may instead hold its own workflow mutex and enqueue a declared,
bounded child for the GPU-only stage, as the monthly source review does. The
parent identity, dedup key, depth/fanout caps, and `noEnqueue` capability make
that child explicit; an inner Pi agent never receives Tally access or enqueues
surprise work.

Git, deterministic transforms, Pi processes, validation, and publication run on
the coordinator unless a workflow explicitly declares another execution host.
Model calls cross only the llama-swap boundary to the selected compute host.

## Durable versus transient state

Durable Git output contains only the final human artifact and any explicitly
reviewable proposal inputs. Member answers, aggregator inputs, raw evidence,
clones, and Pi JSONL are transient. Tally retains compact local proof: the plan,
resolved models, member/reducer digests, repairs, quorum, final artifact digest,
and external publication handle.

This separation is what makes skill distillation operational: a future frontier
model can inspect failures and witnesses, improve the versioned skill/tools and
RED/GREEN fixtures, and leave the local model weights untouched.
