# Ultracode workflows: go light on verification

Standing rule from Tom (2026-10-20), for every Workflow script authored under
ultracode or on an explicit "use a workflow" request, on both Claude seats.

This restates ruling R7 of the 2026-10-13 ideal-state sheet. The reason is
measured, not assumed: Tom stopped critique waves by hand six times, and 77
refuter runs overnight refuted nothing, while the waves cost most of each run.
Retire this rule if a verify pass ever removes a finding that mattered. So:

- Keep the "verify", "adversarial refute", "critique and revise" and "judge
  panel" stages light. Default to a single verifier per finding, or none for
  low-stakes findings. No 3–5 vote refute panels, no multi-lens judges, no
  loop-until-dry on verification.
- At most one critique-and-revise pass, never iterated.
- Spend the agent budget on coverage (finders, readers, sweeps) and on
  synthesis, not on re-checking.
- Scale up only when that request itself says "thorough", "audit",
  "comprehensive" or names a vote count. The workflow-authoring reference's
  lean toward adversarial verification does not apply by default here.
- Still `log()` and report what was left unverified, so a light pass is not
  read as a checked one.
