# demo: a light-format spec fixture

Status: proposed
Repos: agency-agency/demo (primary)
Consumers: Claude via CLI, factory routine
Inputs: none
Toolchain: cloudflare-os 0bfefa7 pin (Node 24.19.0, TS 7.0.2, pnpm 11.17.0, wrangler ^4.138.0, vitest ^4.1, Vite+)

## Outcome
The demo service builds and its tests pass locally. A fresh checkout runs
`pnpm install` and `pnpm -r typecheck` without error. This is the smallest
slice that proves the spec-check fixture harness end to end.

## Rulings
- "keep the fixture tiny" (2026-09-30 12:00Z, spec-skill-pr)

## Claims
### Stage A: toolchain (no external gate)
C1.1 the repo has a package.json at the root → `pnpm -r typecheck` exits 0 (given). [prove: P1.1]
C1.2 (tree) wrangler.jsonc pins the compatibility date named in SPEC.md's Toolchain line → the pin matches. [prove: P1.2]
C1.3 the changelog at docs/CHANGELOG.md names the release → the file exists. [prove: P1.3]

## Open questions
Q1 does this fixture need a second stage? default: no (GUESS)
H1 [HUMAN] none; this is a lint fixture.

## Out of scope
- extend this fixture into a real service
