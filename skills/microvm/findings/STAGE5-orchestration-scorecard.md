# Stage 5 — Orchestration Scorecard (self-critique of the fix run)

Companion to [`STAGE5-fix-prompts.md`](STAGE5-fix-prompts.md) (the verbatim prompts).
This is an honest design retrospective of the orchestration that implemented the 25
`STAGE4-scrutiny.md` findings into `../sandbox.sh`, written for a reader learning to
reason about multi-agent decomposition. It rates the *design*, not the *results*.

## Shape that was run

- **Trunk:** one shared preamble ("COMMON") prepended to every editing agent.
- **5 implement agents, SEQUENTIAL** (A gen_id · B krun-blockers · C transport · D lifecycle · E mounts/usage). Serial because all 5 edit one file (`sandbox.sh`); concurrent edits clobber.
- **5 verify agents, PARALLEL** (one per cluster, read-only, adversarial).
- **1 correct+lint agent** (applies flagged corrections, final `bash -n` + `shellcheck`).
- **Tree depth = 3:** trunk → cluster ("chapter") → findings. **Leaf = cluster (~6 findings), NOT one-agent-per-finding.**
- **Model:** no override set → all agents inherited **Opus**. So this is effectively an all-Opus team.

## How the design actually arose (honesty about origin)

~70% **constraint obedience**, ~20% **inherited taxonomy**, ~10% **fresh judgment**.
- The single hard fact — *it is one file* — killed parallel implementation and forced the sequential spine. That decided the structure more than any insight.
- The cluster boundaries were lifted from `STAGE4-scrutiny.md`'s own "Top themes" grouping (bash / fidelity-isolation / lifecycle / doctor), not invented.
- Only the cluster *size* (~5–8 findings) was genuine intuition: "what one agent holds in focus while editing a 1500-line file," eyeballed, not computed.

## Scorecard (/10)

| Dimension | Score | Verdict |
|---|---|---|
| Specificity / context size | 8 | Mechanism + fix + gotcha per finding. Arguably *over*-specified — agents transcribe rather than solve, capping upside. |
| Split-ability | **5** | Weakest structural point. Split buys ~zero parallelism in the expensive (implement) phase — it is context-chunking for focus, not parallelization. |
| Thoroughness | 8 | All 25 covered + verify + correct. Capped only by the absence of a run-it-for-real regression agent (testbed gap: no krun on host yet), not by the design. |
| Redundancy | 6 | Single-pass implement (good); single verifier per cluster (thin). The annotation blocker already slipped once and deserved 2–3 independent verifiers. |
| Orthogonality of tests | **4–5** | The real weakness — see below. |
| Difficulty balance | 5 | Leaves range ~2/10 (A: one line) to ~8/10 (B: 3 blockers + invent doctor probes). Unbalanced. |

## The orthogonality miss (highest-leverage fix)

All 5 verifiers use the **same lens**: "re-read, check vs scrutiny, run `bash -n`."
That is redundant-*same*, not diverse. Genuinely orthogonal attack vectors would be
*different kinds of skepticism*:

1. **syntactic** — `bash -n` + `shellcheck`
2. **semantic-vs-source** — does `krun.cpus` match crun's exact-key lookup?
3. **adversarial-input** — does the base64 fix actually stop `echo a;rm` from running `rm`? (execute it)
4. **regression** — did fixing #2 break the doctor path?
5. **discipline-conformance** — still honors the BUILD-BRIEF accident-model?

Collapsing all five into one prompt per cluster is the design's biggest gap. A
**diverse-lens verify panel** is the single change that most raises confidence on the
exact bug class (silent fail-open) that already shipped once.

## Model-sensitivity (would Sonnet vs all-Opus change it?)

Capability scales tree shape **inversely**:
- **Sonnet sub-agents** → deeper & narrower: smaller clusters, spell out exact Edit `old`/`new`, *more* verification redundancy, lower per-leaf difficulty.
- **All-Opus** → shallower & wider: 2–3 bigger agents, less hand-holding, trust judgment; plausibly one Opus pass for all 25.

**The kicker:** the team ran on Opus, yet was built like a Sonnet plan (5+5+1, dictated
fixes). Conclusion: **over-split and over-specified for the model actually used.**
Defensible for a delicate, not-yet-runnable file — but belt-and-suspenders.

> **RECTIFICATION (added after deeper introspection).** Everything in this section is an
> *ex-post construct*. At design time there was **no model/capability consideration at all** —
> not "pick Opus," not "this is Sonnet-shaped." The model axis simply did not exist in the
> moment; the agents ran on Opus by **inheritance, not selection** (no override was set because
> the question never surfaced). The proof is in the artifact: the structure is **flat** —
> uniform cluster sizes, one verifier each, symmetric schemas. A mind actually tracking
> difficulty/capability emits a *gradient* (more verifiers on the hard cluster, the trivial one
> folded in); this emitted symmetry, which is the tell that difficulty was not a live variable.
> What *was* live while authoring: (1) don't let two agents clobber the same file → sequential;
> (2) land all 25 findings → completeness scan; (3) fit the tool's find→verify→correct template;
> (4) group findings by the functions they touch → code locality. Capability was not on that
> list. The "capability scales tree shape inversely" heuristic above is a useful *forward* rule,
> but it is reconstructed, not recovered. See [`COMPLEXITY-PREDICTION.md`](COMPLEXITY-PREDICTION.md)
> for the (honestly-labeled) hypothesis and the Sonnet experiment that tests it.

## What I would change on a rebuild

1. **Merge A** (gen_id) into another cluster — it never warranted its own agent.
2. **Split B** into B1 (annotation/network) + B2 (doctor-probes) — the only place difficulty justifies more depth.
3. **2–3 Opus implement agents, not 5**, trusted more (less dictation).
4. **Spend the saved budget on a diverse-lens verify panel** (the 5 vectors above) instead of 5 identical checkers — and give the two blockers 2–3 independent verifiers (perspective-diverse), not one.
5. Add a **run-it-for-real regression agent** once the krun stack is on a host (post fresh-boot).

## One-line grade

Competent and safe, **over-engineered for an all-Opus team, with under-diversified
verification on the exact bug that already bit once.** The structure was dictated by the
single-file constraint; the judgment that was mine to make (verifier diversity, difficulty
balance, depth uniformity) is where it is weakest.
