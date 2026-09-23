/**
 * ReceiptStrict.test.ts — U-A16 LAKE-RECEIPT-STRICT.
 *
 * The subject is one file: `fixtures/receipt-strict-full.json`, a receipt line
 * carrying every field TALLY-SPEC-2026-09-06.md §2.3 names plus the nine ciru
 * fields of DECISIONS.md D-B22. It names no card, no run and no register entry.
 *
 * `tools/decode-estate.mjs` reads the SAME file for its `--check-strict-fixture`
 * green and its `prior-without-cell` control, so the tool and the suite cannot
 * disagree about what the fixture is.
 *
 * Nothing here reads a corpus. The corpus readings — the 19 banked lines that
 * carry `tokens: null` — are the tool's, because they are measurements of disk
 * and disk is another lane's (CONTRIBUTING.md §2 rule 8).
 */
import { readFileSync } from "node:fs"
import { fileURLToPath } from "node:url"
import { describe, expect, it } from "vitest"
import * as X from "../src/index.ts"

const FIXTURE = fileURLToPath(new URL("./fixtures/receipt-strict-full.json", import.meta.url))

const full = (): Record<string, any> => JSON.parse(readFileSync(FIXTURE, "utf8"))

const clone = <T>(v: T): T => JSON.parse(JSON.stringify(v))

const without = (path: string) => {
  const c = full()
  const parts = path.split(".")
  let node: any = c
  for (const p of parts.slice(0, -1)) node = node[p]
  delete node[parts[parts.length - 1]!]
  return c
}

const withValue = (path: string, value: unknown) => {
  const c = full()
  const parts = path.split(".")
  let node: any = c
  for (const p of parts.slice(0, -1)) node = node[p]
  node[parts[parts.length - 1]!] = value
  return c
}

const isPlainObject = (v: unknown): v is Record<string, unknown> =>
  v !== null && typeof v === "object" && !Array.isArray(v)

/** `shape{}` is an open block (§7 amendment 4); its contents are not schema fields. */
const OPEN_BLOCKS = ["shape"]

const fieldPaths = (value: Record<string, unknown>, prefix = "", out: Array<string> = []): Array<string> => {
  for (const k of Object.keys(value)) {
    const path = prefix === "" ? k : `${prefix}.${k}`
    out.push(path)
    const v = value[k]
    if (isPlainObject(v) && !OPEN_BLOCKS.includes(path)) fieldPaths(v, path, out)
  }
  return out
}

/** §2.3's `?` fields, as paths in the fixture. Mirrors decode-estate's own list. */
const OPTIONAL_PATHS = [
  "tok_per_s",
  "load_seconds",
  "concurrent_requests",
  "gpu_seconds",
  "sampling",
  "outcome_ruled",
  "difficulty_scoped",
  "prior.thompson",
  "prior_gap.tokens_in_declared_cell"
]

// §2.3's field list, transcribed in the order the section writes it. This array
// is the spec's sentence; `RECEIPT_FIELDS` is the type. The test below is what
// keeps them the same list, so a field cannot be dropped from the type by an
// edit that nobody reads.
const SPEC_2_3_FIELDS = [
  "id",
  "kind",
  "attempt",
  "card_sha256",
  "prior_lock_commit",
  "repo",
  "seat",
  "row",
  "harness",
  "model",
  "arm",
  "thread_id",
  "session_id",
  "window_id",
  "started_at",
  "finished_at",
  // §2.2d's deterministic-replay clause adds this receipt timestamp.
  "observed_at",
  "seconds",
  "tokens",
  "tokens_source",
  "context_window",
  "max_context_used",
  "tok_per_s",
  "load_seconds",
  "concurrent_requests",
  "gpu_seconds",
  "sampling",
  "commit_sha",
  "branch",
  "oracle_argv",
  "oracle_sha256",
  "oracle_rc",
  "oracle_output_sha256",
  "oracle_output_normalization",
  "mutation",
  "artifact_sha256",
  "pins_sha256",
  "evaluator",
  "cost_at_release",
  "runtime_cap_seconds",
  "disposition",
  "crash_reason",
  "outcome_for_calibration",
  "outcome_ruled",
  "prior",
  "difficulty_scoped",
  "prior_gap",
  "notes"
]

// DECISIONS.md D-B22, verbatim: "`control_receipt_id`, `baseline`,
// `disposition_class`, `not_evidence_for`, `confirmation_of`, `setup_seconds`,
// `post_conditions`, `population`, `supersedes`/`superseded_by`, `shape`".
const D_B22_FIELDS = [
  "control_receipt_id",
  "baseline",
  "disposition_class",
  "not_evidence_for",
  "confirmation_of",
  "setup_seconds",
  "post_conditions",
  "population",
  "supersedes",
  "superseded_by",
  "shape"
]

describe("the §2.3 field list is the type's field list", () => {
  it("carries every field §2.3 names, and no other", () => {
    expect([...X.RECEIPT_FIELDS].sort()).toEqual([...SPEC_2_3_FIELDS, ...D_B22_FIELDS].sort())
  })
  it("carries D-B22's nine ciru fields under their own name", () => {
    expect([...X.CIRU_FIELDS].sort()).toEqual([...D_B22_FIELDS].sort())
  })
  it("marks exactly §2.3's `?` fields optional", () => {
    // `crash_reason` and `thread_id` are `optionalKey` in the type and yet are
    // NOT removable from this fixture: the fixture is a CRASH line carrying no
    // session_id, and two struct filters make each one required in that case.
    // §2.3's `?` is about the field; the filter is about the line.
    expect([...X.RECEIPT_OPTIONAL_FIELDS].sort()).toEqual(
      ["thread_id", "session_id", "crash_reason", ...OPTIONAL_PATHS.filter((p) => !p.includes("."))].sort()
    )
  })
  it("names no wall-clock field (R-2026-09-05-16)", () => {
    for (const f of X.RECEIPT_FIELDS) expect(X.WALLCLOCK_FIELDS).not.toContain(f)
  })
})

describe("the fixture carrying every field of §2.3 plus the ciru fields", () => {
  it("decodes", () => {
    const r = X.decodeReceipt(full())
    expect(r.ok, r.ok ? "" : r.why).toBe(true)
  })

  const paths = fieldPaths(full())

  it(`covers every field of the type (${paths.length} paths)`, () => {
    for (const f of X.RECEIPT_FIELDS) {
      if (f === "session_id") continue // §2.3's other name for thread_id; tested below
      expect(paths).toContain(f)
    }
  })

  it("refuses each required field, one removed at a time, BY NAME", () => {
    const survived: Array<string> = []
    for (const path of paths) {
      const leaf = path.split(".").pop()!
      const r = X.decodeReceipt(without(path))
      if (r.ok) {
        survived.push(path)
        continue
      }
      expect(r.why, `removing ${path} was refused without naming it: ${r.why}`).toContain(leaf)
    }
    expect(survived.sort()).toEqual([...OPTIONAL_PATHS].sort())
  })

  it("refuses each field set to null, BY NAME — §2.3 admits no null cell", () => {
    for (const path of paths) {
      const leaf = path.split(".").pop()!
      const r = X.decodeReceipt(withValue(path, null))
      expect(r.ok, `${path} set to null decoded`).toBe(false)
      if (!r.ok) expect(r.why, `${path} nulled without being named: ${r.why}`).toContain(leaf)
    }
  })

  it("requires the mechanical evaluator's own token cells to be zero", () => {
    const r = X.decodeReceipt(withValue("evaluator.tokens.out", 1))
    expect(r.ok).toBe(false)
    if (!r.ok) expect(r.why).toMatch(/evaluator.*out/)
  })

  it("represents a missing mutation hint without fabricating an rc", () => {
    const value = full()
    value.mutation = { kind: "none", reason: "no-mutation-hint" }
    value.crash_reason = "no-mutation-hint"
    value.outcome_for_calibration = "excluded"
    expect(X.decodeReceipt(value).ok).toBe(true)
    value.disposition = "DISCARD"
    expect(X.decodeReceipt(value).ok).toBe(false)
  })

  it("refuses a field no source names", () => {
    const r = X.decodeReceipt({ ...full(), invented_field: 1 })
    expect(r.ok).toBe(false)
    if (!r.ok) expect(r.why).toContain("invented_field")
  })
})

describe("tokens may not be null (TL-7 / D-B7)", () => {
  it("refuses the whole cell nulled", () => {
    const r = X.decodeReceipt(withValue("tokens", null))
    expect(r.ok).toBe(false)
    if (!r.ok) expect(r.why).toContain("tokens")
  })
  it("refuses one cell nulled", () => {
    for (const cell of ["in_uncached", "cache_read", "cache_write", "out", "reasoning", "total"]) {
      const r = X.decodeReceipt(withValue(`tokens.${cell}`, null))
      expect(r.ok, `tokens.${cell} nulled decoded`).toBe(false)
      if (!r.ok) expect(r.why).toContain(cell)
    }
  })
  it("refuses one cell missing", () => {
    const r = X.decodeReceipt(without("tokens.out"))
    expect(r.ok).toBe(false)
    if (!r.ok) expect(r.why).toContain("out")
  })
  it("refuses a cell that is not an integer — §2.3: every cell an integer", () => {
    expect(X.decodeReceipt(withValue("tokens.out", 15306.5)).ok).toBe(false)
    expect(X.decodeReceipt(withValue("tokens.out", "15306")).ok).toBe(false)
    expect(X.decodeReceipt(withValue("tokens.out", -1)).ok).toBe(false)
  })
  it("refuses tokens made optional by omission", () => {
    expect(X.decodeReceipt(without("tokens")).ok).toBe(false)
  })
  it("accepts a zero cell — measured zero is a measurement, absence is not", () => {
    expect(X.decodeReceipt(withValue("tokens.reasoning", 0)).ok).toBe(true)
  })
})

describe("the banked line and the strict line are different types", () => {
  // The 19 banked lines carry `tokens: null` and no `kind`, `arm`, `evaluator`,
  // `prior` or ciru block. If one type decoded both, the tokens-null control
  // would be vacuous.
  const banked = () => ({
    id: "TEST-B",
    seat: "a-seat",
    thread_id: "t",
    started_at: "2026-09-06T01:41:00+02:00",
    finished_at: "2026-09-06T01:45:25+02:00",
    seconds: 265,
    tokens: null,
    commit_sha: "0bcc82e",
    branch: "main",
    oracle_argv: [["sh", "-c", "true"]],
    oracle_rc: 0,
    output_sha256: "a".repeat(64),
    disposition: "DISCARD",
    notes: "n"
  })
  it("decodes the banked shape as BankedReceipt", () => {
    expect(X.decodeBankedReceipt(banked()).ok).toBe(true)
  })
  it("refuses the banked shape as the §2.3 Receipt, naming tokens", () => {
    const r = X.decodeReceipt(banked())
    expect(r.ok).toBe(false)
    if (!r.ok) expect(r.why).toContain("tokens")
  })
  it("refuses the §2.3 line as a banked line", () => {
    expect(X.decodeBankedReceipt(full()).ok).toBe(false)
  })
})

describe("the prior declares which token cell it predicts (D-B19)", () => {
  it("refuses a prior with no predicted_tokens_cell", () => {
    const r = X.decodeReceipt(without("prior.predicted_tokens_cell"))
    expect(r.ok).toBe(false)
    if (!r.ok) expect(r.why).toContain("predicted_tokens_cell")
  })
  it("admits the four cells §2.3 names and no other word", () => {
    for (const cell of ["out", "in_uncached+out", "total", "unruled"]) {
      expect(X.decodeReceipt(withValue("prior.predicted_tokens_cell", cell)).ok, cell).toBe(true)
    }
    expect(X.decodeReceipt(withValue("prior.predicted_tokens_cell", "output")).ok).toBe(false)
  })
  it("admits §2.3's three prior_source words and no other", () => {
    for (const s of ["card-text", "scoping-node", "band"]) {
      expect(X.decodeReceipt(withValue("prior.prior_source", s)).ok, s).toBe(true)
    }
    expect(X.decodeReceipt(withValue("prior.prior_source", "a guess")).ok).toBe(false)
  })
  it("keeps the gap in every cell (D-B19), so prior_gap.tokens_by_cell has three", () => {
    for (const cell of ["out", "in_uncached+out", "total"]) {
      expect(X.decodeReceipt(without(`prior_gap.tokens_by_cell.${cell}`)).ok, cell).toBe(false)
    }
  })
  it("holds difficulty to D-B9's 1–5 scale", () => {
    expect(X.decodeReceipt(withValue("prior.difficulty", 0)).ok).toBe(false)
    expect(X.decodeReceipt(withValue("prior.difficulty", 6)).ok).toBe(false)
    expect(X.decodeReceipt(withValue("prior.difficulty", "low")).ok).toBe(false)
  })
})

describe("the ciru fields (D-B22): required, and 'none' where inapplicable", () => {
  it("requires all eleven names D-B22 lists", () => {
    for (const f of D_B22_FIELDS) {
      const r = X.decodeReceipt(without(f))
      expect(r.ok, `${f} was removable`).toBe(false)
      if (!r.ok) expect(r.why).toContain(f)
    }
  })
  it("accepts the string 'none' in every one of them", () => {
    for (const f of D_B22_FIELDS) {
      expect(X.decodeReceipt(withValue(f, "none")).ok, f).toBe(true)
    }
  })
  it("refuses null in every one of them — 'none' never null", () => {
    for (const f of D_B22_FIELDS) {
      expect(X.decodeReceipt(withValue(f, null)).ok, f).toBe(false)
    }
  })
  it("refuses an empty list where 'none' is the word for nothing", () => {
    expect(X.decodeReceipt(withValue("not_evidence_for", [])).ok).toBe(false)
    expect(X.decodeReceipt(withValue("post_conditions", [])).ok).toBe(false)
  })
  it("holds baseline to D-B20's three cells", () => {
    for (const cell of ["metric", "value", "receipt_id"]) {
      expect(X.decodeReceipt(without(`baseline.${cell}`)).ok, cell).toBe(false)
    }
  })
  it("holds population to its three counts", () => {
    for (const cell of ["cards", "schema_valid", "tests_passing"]) {
      expect(X.decodeReceipt(without(`population.${cell}`)).ok, cell).toBe(false)
    }
  })
  it("holds a post-condition to {name, rc}", () => {
    expect(X.decodeReceipt(withValue("post_conditions", [{ name: "x" }])).ok).toBe(false)
    expect(X.decodeReceipt(withValue("post_conditions", [{ name: "x", rc: 0 }])).ok).toBe(true)
  })
})

describe("thread_id | session_id — one cell, two names, non-empty", () => {
  it("decodes with thread_id", () => {
    expect(X.decodeReceipt(full()).ok).toBe(true)
  })
  it("decodes with session_id instead", () => {
    const c = without("thread_id")
    expect(X.decodeReceipt({ ...c, session_id: "0199c0de-...-1" }).ok).toBe(true)
  })
  it("refuses a line carrying neither, naming both", () => {
    const r = X.decodeReceipt(without("thread_id"))
    expect(r.ok).toBe(false)
    if (!r.ok) {
      expect(r.why).toContain("thread_id")
      expect(r.why).toContain("session_id")
    }
  })
  it("refuses an empty one", () => {
    expect(X.decodeReceipt(withValue("thread_id", "")).ok).toBe(false)
  })
})

describe("a stamp that failed is named, never nulled (§2.3)", () => {
  it("requires a crash_reason on a CRASH", () => {
    const r = X.decodeReceipt(without("crash_reason"))
    expect(r.ok).toBe(false)
    if (!r.ok) expect(r.why).toContain("crash_reason")
  })
  it("admits only §2.3's six reasons", () => {
    for (
      const [reason, outcome] of [
        ["serve", "excluded"],
        ["oom", "excluded"],
        ["context_overflow", "fail"],
        ["runtime_cap", "fail"],
        ["measurement", "excluded"],
        ["no-mutation-hint", "excluded"]
      ] as const
    ) {
      const c = full()
      c.crash_reason = reason
      c.outcome_for_calibration = outcome
      if (reason === "no-mutation-hint") c.mutation = { kind: "none", reason }
      expect(X.decodeReceipt(c).ok, reason).toBe(true)
    }
    expect(X.decodeReceipt(withValue("crash_reason", "it broke")).ok).toBe(false)
  })
  it("fixes outcome_for_calibration from the crash reason (§2.3's own mapping)", () => {
    const r = X.decodeReceipt(withValue("outcome_for_calibration", "excluded"))
    expect(r.ok).toBe(false)
    if (!r.ok) expect(r.why).toContain("runtime_cap")
  })
  it("lets a KEEP line carry no crash_reason", () => {
    const c = clone(full())
    delete c.crash_reason
    c.disposition = "KEEP"
    c.outcome_for_calibration = "pass"
    expect(X.decodeReceipt(c).ok).toBe(true)
  })
  it("admits only KEEP | DISCARD | CRASH as the executor's word", () => {
    expect(X.decodeReceipt(withValue("disposition", "FINE")).ok).toBe(false)
  })
})

describe("the measurement rules §2.3 states as rules", () => {
  it("refuses tok_per_s when concurrent_requests > 0", () => {
    const r = X.decodeReceipt(withValue("concurrent_requests", 1))
    expect(r.ok).toBe(false)
    if (!r.ok) expect(r.why).toContain("tok_per_s")
  })
  it("admits the line without tok_per_s when the device was shared", () => {
    const c = without("tok_per_s")
    c.concurrent_requests = 1
    expect(X.decodeReceipt(c).ok).toBe(true)
  })
  it("holds mutation to {kind: hint, rc} or {kind: ref, ref}", () => {
    expect(X.decodeReceipt(withValue("mutation", { kind: "hint", rc: 1 })).ok).toBe(true)
    expect(X.decodeReceipt(withValue("mutation", { kind: "ref", ref: `sha256:${"a".repeat(64)}` })).ok).toBe(true)
    expect(X.decodeReceipt(withValue("mutation", { kind: "hint" })).ok).toBe(false)
    expect(X.decodeReceipt(withValue("mutation", { kind: "hint", ref: `sha256:${"a".repeat(64)}` })).ok).toBe(false)
    expect(X.decodeReceipt(withValue("mutation", { kind: "guess", rc: 1 })).ok).toBe(false)
  })
  it("admits §2.3's three window_id forms and no other", () => {
    expect(X.decodeReceipt(withValue("window_id", "none")).ok).toBe(true)
    expect(X.decodeReceipt(withValue("window_id", "unknown")).ok).toBe(true)
    expect(X.decodeReceipt(withValue("window_id", "2026-09-06T13:39:59Z")).ok).toBe(true)
    expect(X.decodeReceipt(withValue("window_id", "in five hours")).ok).toBe(false)
  })
  it("admits build, replay and merge as the receipt kind (§2.3, D-B20)", () => {
    for (const k of ["build", "replay", "merge"]) {
      expect(X.decodeReceipt(withValue("kind", k)).ok, k).toBe(true)
    }
    expect(X.decodeReceipt(withValue("kind", "review")).ok).toBe(false)
  })
  it("requires the evaluator's own block, with its own token cells", () => {
    for (const cell of ["argv_sha256", "lock", "tokens", "seconds", "execution_id"]) {
      expect(X.decodeReceipt(without(`evaluator.${cell}`)).ok, cell).toBe(false)
    }
    expect(X.decodeReceipt(withValue("evaluator.tokens", null)).ok).toBe(false)
  })
  it("states cost_at_release in the row's unit, never in raw tokens", () => {
    for (const cell of ["row", "price_hash", "unit", "value"]) {
      expect(X.decodeReceipt(without(`cost_at_release.${cell}`)).ok, cell).toBe(false)
    }
  })
  it("requires an identifiable usage source (GROUND-bayes §0.1's join)", () => {
    for (const cell of ["kind", "path", "first_event", "last_event"]) {
      expect(X.decodeReceipt(without(`tokens_source.${cell}`)).ok, cell).toBe(false)
    }
  })
  it("keeps measured seconds, which are an outcome (R-2026-09-05-16)", () => {
    expect(X.decodeReceipt(withValue("seconds", 0)).ok).toBe(true)
    expect(X.decodeReceipt(withValue("seconds", -1)).ok).toBe(false)
    expect(X.decodeReceipt({ ...full(), predicted_wallclock: 3600 }).ok).toBe(false)
  })
})
