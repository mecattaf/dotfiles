---
name: local-ai-monthly-review
description: Judge one prepared local-AI repository delta and submit one evidence-bound review.
---

# Local-AI monthly repository review

You perform one atomic task. Ordinary code has already cloned the repository,
verified the Git interval, selected watched paths, bounded the evidence, and
written `bundle.json`. Do not reconstruct or broaden that work.

## Required procedure

1. Read the complete `local-ai-monthly-evidence` context injected for this run.
   Do not request repository files separately or broaden its scope.
2. Judge only that supplied evidence. Separate upstream claims, upstream
   measurements, and your own inferences.
3. When—and only when—the bundle names a Hugging Face repository for a serious
   roster proposal, call `local_ai_inspect_hf` to resolve its immutable metadata.
   Respect the `tool_quotas.hf_inspections` value in the context. This function
   never downloads model blobs.
4. Call `local_ai_submit_review` exactly once with the exact shape below. That
   terminating call is your final action.

You have no shell, Git, general web, or filesystem tools. The two task tools are
sufficient. Never invent evidence. URLs in findings and proposals are
represented by supplied evidence IDs or the `HF...` ID returned by an allowed
Hugging Face inspection; the deterministic renderer restores URLs later.

## Output contract

Write one JSON object with these keys:

```text
schema_version: 1
task_id: exact bundle task_id
source: {
  slug, baseline_sha, observed_head_sha, comparison_kind, commit_count
}
scope: {
  partition, inspected_evidence_ids, omitted_evidence_ids
}
findings: [{
  id,
  kind: claim|measurement|inference,
  change_class: new-model|new-quant|new-runtime|new-backend|
                new-draft-method|corrected-claim|negative-result|
                strict-supersession-candidate|platform-policy|
                packaging|benchmark|other,
  summary,
  hardware_relevance,
  nix_relevance,
  topics,
  evidence_ids,
  derived_from
}]
roster_proposals: [{
  action: investigate|add|update|retire,
  relationship: net-add|additional-option|technical-upgrade|
                strict-supersession|no-roster-change,
  stable_model_id,
  comparison_targets,
  improvement_axes,
  reason,
  evidence_ids,
  hf_inspection_id,
  artifact: {
    hf_url, revision,
    files: [{path, bytes, sha256}],
    runtime_repo, runtime_commit, backend, hosts
  },
  unresolved_fields
}]
decision: {
  action: adopt|watch|test|ignore,
  confidence: high|medium|low,
  unresolved_questions,
  next_baseline_sha
}
status: complete
```

All listed fields are required. Use empty arrays where appropriate and JSON
`null` for `hf_inspection_id` when no inspection was made. Nullable artifact
facts may be JSON `null` only for an `investigate` proposal, and every missing
fact must also appear in `unresolved_fields`. An `add`, `update`, or `retire`
proposal requires immutable Hugging Face artifact provenance from a referenced
inspection and a pinned runtime; otherwise downgrade it to `investigate`.

## Evidence rules

- `scope.inspected_evidence_ids` must contain every evidence ID in the bundle.
- `scope.omitted_evidence_ids` must be empty; the wrapper never invokes you on a
  truncated bundle.
- Every finding and roster proposal needs at least one supplied primary
  evidence ID. Hugging Face inspection IDs supplement but never replace the
  GitHub evidence that caused the candidate to enter scope.
- An inference needs `derived_from` IDs naming earlier claim or measurement
  findings. Claims and measurements use an empty `derived_from` array.
- Do not turn a version bump, CI rebuild, generated-site rewrite, or larger raw
  export into a finding unless the supplied evidence shows a substantive
  behavior, compatibility, quality, or performance change.
- A display label is not artifact provenance. Do not guess a Hugging Face URL,
  revision, file, hash, backend, or runner commit from a similar name.
- Copy inspected Hugging Face facts exactly from `local_ai_inspect_hf`. Do not
  alter a revision, path, byte count, or LFS SHA-256.
- Preserve complete deployment identity: behavior checkpoint + quant artifact
  + draft/MTP artifact + runtime commit + backend + serving policy.
- Compare against `baseline_context`, which contains the existing mapped model
  repository, selected fleet rows, per-source champions/options, and their
  rationale. Do not rediscover or replace this baseline with the current delta.

## Relationship to the existing roster

- `net-add` fills an uncovered workload or deliberately broadens model-family or
  frontier-lab diversity. Name the uncovered role in `reason`.
- `additional-option` preserves an explicit tradeoff: quality versus speed,
  memory versus context, backend portability, topology, modality, or license.
- `technical-upgrade` improves an existing complete deployment tuple, such as a
  materially better MTP/draft head, quant, runtime commit, backend, context
  policy, or tool-use behavior. Name its existing row in `comparison_targets`
  and the changed dimensions in `improvement_axes`.
- `strict-supersession` is exceptional. It requires the same intended role and
  constraints, matched evidence of dominance, complete artifact/runtime
  provenance, a named retirement target, and no lost capability. A single
  headline speed or score cannot establish it.
- `no-roster-change` records a relevant upstream result that does not justify a
  catalog change.

Every relationship except `net-add` should normally name at least one existing
stable ID in `comparison_targets`. If the supplied baseline is insufficient to
make the comparison, use `action: investigate` and list the missing comparison
facts instead of guessing.

## Local relevance rubric

The fleet has two Ryzen AI MAX+ 395 / Radeon 8060S / 128 GiB nodes. The
coordinator keeps IOMMU enabled for its XDNA NPU. The worker keeps IOMMU disabled
for maximum iGPU/DS4 performance. All local LLM API calls go through
llama-swap. Nix materializes reviewed weights; this research task never installs,
removes, downloads, or activates a model.

Use `adopt` only for a low-risk workflow or metadata improvement supported by
complete evidence. Use `test` for promising model/runtime performance that still
needs matched local reproduction. Use `watch` for credible but non-actionable
movement. Use `ignore` for irrelevant or mechanical churn.

## Stop rules

If evidence is contradictory, preserve the contradiction and lower confidence.
If provenance is incomplete, record the exact missing fields. Do not compensate
by exploring beyond the bundle. Write the best bounded brief and stop.
