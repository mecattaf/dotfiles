# demo2: bad claim grammar fixture

Status: proposed
Repos: agency-agency/demo2 (primary)
Consumers: Claude via CLI
Inputs: none
Toolchain: cloudflare-os 0bfefa7 pin (Node 24.19.0, TS 7.0.2, pnpm 11.17.0, wrangler ^4.138.0, vitest ^4.1, Vite+)

## Outcome
The demo2 fixture exists only to trip the linter's claim-grammar rules: a
banned lexicon word, a model name, a missing binding, a doubled binding,
and a bare numeral with no (given)/(GUESS) tag.

## Rulings
- "break every claim-grammar rule on purpose" (2026-09-30 12:00Z, spec-skill-pr)

## Claims
### Stage A: broken (no external gate)
C1.1 the service should handle retries gracefully → it works properly. [prove: P1.1]
C1.2 opus reviews the diff → the PR gets two approvals. [prove: P1.2] [human: H1]
C1.3 the queue never overflows → nothing is dropped.
C1.4 the queue depth is 40 → the worker drains in time. [prove: P1.4]

## Open questions
Q1 [BLOCKING] does this ever get fixed? default: no (GUESS)
H1 [HUMAN] none; this is a lint fixture.

## Out of scope
- fixing any of the above
