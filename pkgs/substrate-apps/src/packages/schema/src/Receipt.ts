/**
 * Receipt.ts — U-A8 LAKE-SCHEMA. The `receipt` of {receipt, rung, card}.
 *
 * Three receipt shapes live on this estate, and the type says which source each
 * one comes from.
 *
 * 1. `Receipt` — /home/tom/research-methods/RAWA-FLOW.md §5's receipt line,
 *    quoted verbatim from the common preamble every dispatch prompt carries:
 *
 *      "Receipt: append one JSON line to /home/tom/rawa/receipts/<id>.jsonl
 *       with {id, seat:"nayla-codex", thread_id, started_at, finished_at,
 *       seconds, tokens (null if unknown), commit_sha, branch, oracle_argv,
 *       oracle_rc, test_output_sha256 (sha256 of the sorted `fullName:status`
 *       lines of vitest's JSON reporter), artifact_sha256 (sha256 of the sorted
 *       path+sha256 list of app/dist), pins_sha256, disposition
 *       KEEP|DISCARD|CRASH, notes}"
 *
 *    A FINDING this unit measured: the four receipts the estate has actually
 *    banked under /home/tom/research-methods/receipts/ (W-BOOT, and W-DRV's
 *    three) carry ONE hash field, `output_sha256`, where §5's line names three:
 *    `test_output_sha256`, `artifact_sha256`, `pins_sha256`. All four hash
 *    fields are therefore optional keys here, with a filter requiring at least
 *    one of them — a receipt with no output hash is not a receipt — and the
 *    divergence is written up in docs/schema.md. Reconciling the two is Tom's
 *    or the owning lane's, not this unit's.
 *
 * 2. `DetectorReceipt` — the ledger line P12's shenanigan cards declare in
 *    their own front matter, cards/SH/SH-01.md:32 verbatim:
 *      `receipt: /home/tom/research-methods/receipts/CFOS-LEDGER/<id>.jsonl
 *       # P12's ledger; one line per detector run {sha, rc, output_sha256}`
 *    MEASURED: 72 lines across 70 files, one shape.
 *
 * 3. `AttemptReceipt` — the box's own attempt-receipt line under
 *    /home/tom/.local/state/tally/campaigns/attempt-receipts/. This is the
 *    projection's INPUT, and the lake is a mirror and never a ledger
 *    (/home/tom/Sept2/factory-components.md §5): the schema reads it and
 *    nothing here writes it back. MEASURED: 160 lines, 6 campaigns, a tagged
 *    union on `kind` with five arms.
 *
 * `seconds`, `started_at` and `finished_at` are measurements of a run that
 * happened, not predictions of one that has not: R-2026-09-05-16 strikes
 * predicted wall-clock and keeps measured seconds. No field below is a
 * prediction of duration.
 */
import * as S from "effect/Schema"
import { assertNoWallclockField, Disposition, fieldsOf, Grade, Id, Iso8601, Sha256, Sha256Ref, Tokens } from "./Common.ts"

/** One argv, or a list of argvs. MEASURED: all four banked receipts use the list. */
const OracleArgv = S.Union([S.Array(S.String), S.Array(S.Array(S.String))])

const HASH_FIELDS = ["test_output_sha256", "artifact_sha256", "pins_sha256", "output_sha256"] as const

/**
 * RAWA-FLOW.md §5's receipt line, AS THE ESTATE HAS ALREADY BANKED IT.
 *
 * U-A16 note: this is not §2.3's `Receipt`. §2.3's is strict — every measured
 * cell required, `tokens` not nullable (TL-7 / D-B7) — and it lives in
 * `ReceiptStrict.ts`. The two are different types because the corpora are
 * different corpora: 19 lines on disk carry `tokens: null` and they are the
 * evidence the strict type is enforced (`decode-estate --negative-control
 * tokens-null`), so the type that decodes them may not be the type that refuses
 * them. `EstateReceipt` below reads what is banked; `ReceiptStrict.Receipt`
 * governs what is ingested from now on.
 */
export const BankedReceipt = S.Struct({
  id: Id,
  seat: S.String,
  thread_id: S.String,
  started_at: Iso8601,
  finished_at: Iso8601,
  seconds: S.Number.check(S.isGreaterThanOrEqualTo(0)),
  tokens: S.NullOr(Tokens),
  commit_sha: S.NullOr(S.String),
  branch: S.NullOr(S.String),
  oracle_argv: OracleArgv,
  oracle_rc: S.Int,
  disposition: Disposition,
  notes: S.String,
  // §5 names three hash fields; the banked receipts carry one. See the header.
  test_output_sha256: S.optionalKey(S.NullOr(Sha256)),
  artifact_sha256: S.optionalKey(S.NullOr(Sha256)),
  pins_sha256: S.optionalKey(S.NullOr(Sha256)),
  output_sha256: S.optionalKey(S.NullOr(Sha256))
}).check(
  S.makeFilter((r: Record<string, unknown>) =>
    HASH_FIELDS.some((f) => typeof r[f] === "string")
      ? undefined
      : `a receipt must carry at least one output hash: one of ${HASH_FIELDS.join(", ")}`
  )
)
assertNoWallclockField("BankedReceipt", [
  "id",
  "seat",
  "thread_id",
  "started_at",
  "finished_at",
  "seconds",
  "tokens",
  "commit_sha",
  "branch",
  "oracle_argv",
  "oracle_rc",
  "disposition",
  "notes",
  ...HASH_FIELDS
])

export type BankedReceipt = typeof BankedReceipt.Type

/** P12's ledger line: one per detector run. */
export const DetectorReceipt = S.Struct({
  row_id: S.String,
  sh_id: S.String,
  sha: S.Record(S.String, S.String),
  rc: S.Int,
  grade: Grade,
  output_sha256: Sha256,
  detector_sha256: Sha256
})
assertNoWallclockField("Receipt.DetectorReceipt", fieldsOf(DetectorReceipt))

export type DetectorReceipt = typeof DetectorReceipt.Type

// --- the box's attempt-receipt line ------------------------------------------

/**
 * The fields every attempt-receipt line carries. MEASURED: 160 of 160.
 * `schemaVersion` is 1 (60 lines) or 2 (100 lines).
 */
const attemptBase = {
  schemaVersion: S.Int.check(S.isBetween({ minimum: 1, maximum: 2 })),
  sequence: S.Int.check(S.isGreaterThanOrEqualTo(0)),
  campaign: S.String,
  issueNumber: S.String
}

/** The v2 provenance block. MEASURED: present together or not at all. */
const attemptProvenance = {
  actor: S.optionalKey(S.String),
  armSerial: S.optionalKey(S.Int),
  worklistSha256: S.optionalKey(Sha256Ref),
  writtenAt: S.optionalKey(Iso8601),
  inputEpoch: S.optionalKey(Sha256Ref)
}

/** A worklist task proposed inside a diagnosis. MEASURED: 25 lines. */
const Proposal = S.Struct({
  kind: S.String,
  goal: S.String,
  paths: S.Array(S.String),
  dependencies: S.Array(S.String),
  acceptanceCriteria: S.Array(S.Unknown)
})

export const Diagnosis = S.Struct({
  kind: S.Literal("diagnosis"),
  ...attemptBase,
  ...attemptProvenance,
  attempt: S.Int,
  taskId: S.String,
  diagnosis: S.String,
  redaction: S.String,
  verdict: S.optionalKey(S.String),
  proposal: S.optionalKey(Proposal)
})

export const Retry = S.Struct({
  kind: S.Literal("retry"),
  ...attemptBase,
  ...attemptProvenance,
  attempt: S.Int,
  taskId: S.String,
  reason: S.String,
  redaction: S.String
})

export const Pardon = S.Struct({
  kind: S.Literal("pardon"),
  ...attemptBase,
  ...attemptProvenance,
  actor: S.String,
  reason: S.String,
  tasks: S.NullOr(S.Array(S.String)),
  nonce: S.optionalKey(S.String)
})

export const Escalation = S.Struct({
  kind: S.Literal("escalation"),
  ...attemptBase,
  ...attemptProvenance,
  body: S.String
})

export const WorkerOutcome = S.Struct({
  kind: S.Literal("worker-outcome"),
  ...attemptBase,
  ...attemptProvenance,
  taskId: S.String,
  taskUuid: S.String,
  taskRevision: S.String,
  outcome: S.String,
  reason: S.NullOr(S.String),
  paths: S.Array(S.String)
})

/** The tagged union on `kind`. MEASURED counts: 83, 31, 32, 13, 1 = 160. */
export const AttemptReceipt = S.Union([Diagnosis, Retry, Pardon, Escalation, WorkerOutcome])

export type AttemptReceipt = typeof AttemptReceipt.Type

for (
  const [name, s] of [
    ["Diagnosis", Diagnosis],
    ["Retry", Retry],
    ["Pardon", Pardon],
    ["Escalation", Escalation],
    ["WorkerOutcome", WorkerOutcome]
  ] as const
) {
  assertNoWallclockField(`Receipt.${name}`, fieldsOf(s))
}

/**
 * Any receipt line the estate banks under a receipts root. A line decodes when
 * it decodes as one of the shapes above.
 */
export const EstateReceipt = S.Union([BankedReceipt, DetectorReceipt])
