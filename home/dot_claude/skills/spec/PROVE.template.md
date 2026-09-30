# PROVE

Receipts for the claims in `SPEC.md`. One row per proof run; append-only,
one file per repo. A `fail` row is never edited — a rerun adds a new row.

| id | claim | task | form | command | rc | result | evidence | commit | at |
|---|---|---|---|---|---|---|---|---|---|
| P1.1 | C1.1 | T1 | local | `pnpm -r typecheck` | 0 | pass | 3/3 projects, 0 `error TS` | a1b2c3d | 2026-10-01T08:12Z |

## Legend

- `form` is one of `local | wrangler-dev | live | human`.
- `result` is one of `pass | fail | pending | blocked(H<n>)`.
- A `fail` row is never edited. A rerun adds a new row, as email's A4 already does.
- `evidence` is counts, a path or a hash. Never a secret or an address.
- Every `[prove: Px]` in `SPEC.md` must have a row with id `Px` here (`result: pending`
  is allowed before the run; `spec-check.sh` refuses an unmatched `[prove: Px]`).
