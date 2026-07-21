# Monthly local-AI tallies

This directory is an append-only record of model, runtime, and Strix Halo
changes. [`2026-07-22.md`](2026-07-22.md) is the one-time anchor; later files
should report deltas against the previous accepted catalog rather than
rediscovering the field.

A future deterministic scheduler may prepare one bounded repository delta at a
time and render a proposed tally here. It may not download weights, change
`downloadAllModels`, promote a row, or mutate installed services. Acceptance is
a human-reviewed catalog change.

Each report must include:

1. cutoff, previous pins, and reviewed source commits;
2. exact model tuple changes: checkpoint, artifact, auxiliaries, runtime,
   backend, topology, and serving policy;
3. immutable HF revision, every selected filename, bytes, LFS OID, and SRI;
4. benchmark run ID and evidence class, or an explicit provenance gap;
5. additions, removals, unchanged champions, and negative results;
6. gate state and a statement that no model blob was downloaded by the tally.
