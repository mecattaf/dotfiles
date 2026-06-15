# Stage 5 — Workflow Run Log (telemetry)

Machine record of the code-fix run that implemented `STAGE4-scrutiny.md` into `../sandbox.sh`.
Companion to [`STAGE5-fix-prompts.md`](STAGE5-fix-prompts.md) (the prompts) and
[`STAGE5-orchestration-scorecard.md`](STAGE5-orchestration-scorecard.md) (the design critique).

## Run identity

| Field | Value |
|---|---|
| Workflow name | `microvm-sandbox-fix` |
| Run ID | `wf_ed12f040-145` |
| Task ID | `w2jptcbg2` |
| Date | 2026-05-30, 20:48 → 21:05 UTC |
| Status | completed |
| Transcript dir | `…/subagents/workflows/wf_ed12f040-145/` (11 `agent-*.jsonl` + `journal.jsonl`) |
| Target file | `skills/microvm/sandbox.sh` (1566 → **1844** lines; **402 lines touched** vs the draft) |

## Headline counts (harness-reported)

- **11 agents** · **115 tool-uses** · **wall-clock ~16.5 min** (987,328 ms)
- **633,107 "subagent_tokens"** — the harness's own aggregate metric. NOTE: this does not
  reconcile cleanly to any single component I can measure in the transcripts (see below);
  its exact definition is undocumented, so the transcript-measured breakdown is the
  verifiable record and the 633k is recorded as-reported.

## Token components (measured from the 11 transcripts)

> **Do NOT sum these into a "total."** `cache_read` is reported *per API call* and re-counts
> the **same** cached context on **every** turn. Across **212 assistant turns** the cache_read
> field sums to 9.1M — but that is the same ~43k context (9,095,537 ÷ 212 ≈ 42,900/turn) read
> over and over, not 9.1M distinct tokens. An earlier draft of this file headlined a bogus
> "10.4M total token movement"; that figure was the per-turn cache re-count and is retracted.

| Component | Tokens | Meaning |
|---|---:|---|
| Output (generated) | **42,788** | the actual work product — small, because the agents mostly *edit*, not *write* |
| Input, non-cached (fresh) | 72,776 | genuinely new prompt text sent |
| **Genuinely new (output + fresh input)** | **~115,564** | the real generative footprint of the whole run |
| Cache creation | 1,207,199 | distinct context written to cache — itself inflated (11 agents each re-cache the same source files) |
| Cache read | 9,095,537 | re-reads of already-cached context across 212 turns — a **re-count**, served cheaply (~0.1× billing), not a total |
| Harness headline | **633,107** | the harness's own aggregate ("subagent_tokens", ≈57k effective context/agent) — counts cache closer to once-per-agent, so it is the more meaningful single number |

The honest lesson: the run *generated* only ~43k tokens and *sent* ~73k fresh — about **115k of
genuinely new work**. Everything above that is **context being re-presented each turn**: the
same `sandbox.sh` + `STAGE4-scrutiny.md` re-read ~212 times, served from cache. The cost of a
fan-out is dominated by *context re-loading*, not by what the agents produce — which is exactly
the price of "split for focus" (each of 11 agents re-ingests the file; one bigger agent would
have paid that ingest far fewer times). The 633k headline ≈ 57k effective context × 11 agents
captures this honestly; the 9.1M cache_read sum does not.

## Per-agent breakdown

Output tokens + assistant turns per agent, in execution order. Implement = sequential;
Verify = parallel (all 5 finished within a 19-second window); Correct = last.

### Phase 1 — Implement (sequential, ~12.5 min total)

| # | Agent ID | Cluster | Findings | Out tok | Turns | ~Duration |
|---|---|---|---|---:|---:|---|
| 1 | `ac8ae381…` | A — gen_id SIGPIPE | #1, #21 | 426 | 10 | ~1.3 min |
| 2 | `a36bafaa…` | B — krun annotations/network/doctor | #2 #3 #4 #12 #13 #18 | 8,875 | 26 | ~2.9 min |
| 3 | `a7bc3005…` | C — transport + exec/keep flags | #5 #6 #14 #15 #19 #20 | 8,407 | 26 | ~2.75 min |
| 4 | `ace75ec7…` | D — lifecycle/teardown/reap/traps | #7 #8 #11 #16 #17 #22 #23 #25 | 11,315 | 46 | ~4.1 min |
| 5 | `a0bc10a7…` | E — mounts/usage/logging | #9 #10 #24 | 2,143 | 22 | ~1.65 min |

### Phase 2 — Verify (parallel, ~1.8 min wall)

| # | Agent ID | Verifies cluster | Out tok | Turns |
|---|---|---|---:|---:|
| 6 | `afef20d2…` | A (gen_id) | 2,550 | 13 |
| 7 | `ace29eb3…` | B (krun blockers) | 570 | 12 |
| 8 | `ad226a4b…` | C (transport) | 3,109 | 17 |
| 9 | `a52fe5f4…` | D (lifecycle) | 1,009 | 9 |
| 10 | `a30ba35c…` | E (mounts/usage) | 2,198 | 11 |

### Phase 3 — Correct + lint (~2.7 min)

| # | Agent ID | Role | Out tok | Turns |
|---|---|---|---:|---:|
| 11 | `a4d9cb23…` | correct + final `bash -n`/shellcheck | 2,186 | 20 |

**Output-token total across all 11: 42,788** (implement 31,166 · verify 9,436 · correct 2,186).

Observations the table makes visible:
- **Difficulty was unbalanced** (the scorecard's claim, now in data): cluster D burned 11.3k
  output / 46 turns; cluster A burned 426 / 10. A 26× spread. D was overloaded, A trivial.
- **Verifier B emitted the FEWEST tokens (570) on the MOST important cluster** (the two
  fail-open blockers). The verification was thinnest exactly where the stakes were highest —
  the orthogonality miss, quantified.

## Findings outcome (all 25 punch-list items from STAGE4)

| Cluster | Findings | Fixes applied | Verify verdict |
|---|---|---:|---|
| A | #1 (CRITICAL), #21 (audit-only) | 1 + audit-confirm | fixed |
| B | #2 #3 #4 (BLOCKERS), #12 #13 #18 | 6 | fixed |
| C | #5 #6 (HIGH), #14 #15 #19 #20 | 8 | fixed |
| D | #7 #8 #11 (MED), #16 #17 #22 #23 #25 | 8 | fixed |
| E | #9 #10 (MED), #24 | 3 | fixed |

**verifyNeededWork: 0** · **correct-phase corrections applied: 0** · **final `bash -n`: clean** ·
**shellcheck: NOT run** (binary absent on the current host — coming in the harness image).

### Judgment-call deviations the agents made (the real review surface)

These are where agents chose among options or invented detail the prescription left open —
*not* covered by the same-lens verifiers:

- **#18 (B):** doctor framework has only PASS/FAIL, no WARN state. Agent faked "downgrade to
  WARN" as a non-fatal PASS row with a `WARN:` message prefix + a `warn()` log line.
- **#4 (B):** the in-guest clamp tolerances are the agent's invention — vCPU exact-match,
  `MemTotal` band 256–899 MiB. **Need real krun output to validate; wrong band = false fail/pass.**
- **#6 (C):** opaque-script trigger chosen as `-- -c <script>`.
- **#15 (C):** chose parse-time rejection of `-it` on `keep` (vs silent drop).
- **#20 (C):** implemented the stronger Tty/OpenStdin inspect-and-warn (vs a comment).
- **#7 (D):** branch name derived from worktree basename + a `.repo` sidecar for the parent path.
- **#23 (D):** hard-fail birth on sidecar write failure; skipped the optional `LBL_BASE` read-back.

## What this run did and did NOT establish

- **Established (verifiable here):** all 25 fixes present at the source level; `bash -n` clean;
  `gen_id` empirically SIGPIPE-immune (0/200 failures); bare `krun.*` keys everywhere (no
  `run.oci.` on any real `--annotation`); base64 argv-preservation functional-tested.
- **NOT established (needs the krun host):** that caps actually bind in-guest (#2), that
  loopback yields a NIC (#3), that the new doctor probes (#4) pass/fail correctly against a
  real microVM (they are valid-but-unrun code), and the #4 tolerance bands. That is the
  "Stage 6 = run-it-for-real" work, gated on the fresh-boot device.
