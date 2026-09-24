import { describe, expect, it } from "vitest"
import * as X from "../src/index.ts"

// A card that decodes, built from README §5's own field list. Every value here
// is a shape, not a register fact: this fixture is not a card, it names no
// card, and nothing in this file writes a state onto one (R-2026-09-05-03).
const card = () => ({
  id: "TEST-0",
  title: "a fixture",
  status: "DRAFT",
  class: "seam",
  created: "2026-09-06",
  armed_at: null,
  armed_commit: null,
  depends_on: [],
  data_already_collected: false,
  problem: "p",
  theory: "t",
  hypotheses: [{ id: "H1", statement: "s" }],
  signal: { metric: "m", instrument: "i", sample_target: 1, receipt: "/r" },
  decision_rule: { comparator: "gte", if_pass: "a", if_fail: "b", abort_on: [] },
  prior: { basis: "flat", p_pass: 0.5 },
  arm: null,
  result: {
    observed: null,
    sample_actual: null,
    receipt_path: null,
    receipt_sha256: null,
    grade: null,
    outcome: null,
    action_taken: null
  },
  posterior: { p_pass: null, learning: null, spec_shrunk: null, next: null },
  supervisory: { wip_max: 1, interventions: [] },
  use_case_class: "benchmark-harness"
})

const rung = () => ({
  id: "TEST-1",
  title: "a fixture",
  status: "DRAFT",
  class: "ladder",
  use_case_class: "typescript-on-workers",
  tenant: "conwip",
  t_type: "T4",
  created: "2026-09-06",
  drafted_by: "a session",
  armed_at: null,
  armed_commit: null,
  depends_on: [],
  executor: "opus-ultracode",
  prior: {
    difficulty: 4,
    difficulty_basis: "b",
    p_pass: 0.4,
    p_pass_basis: "text",
    p_pass_reason: "r",
    predicted_tokens: 220000,
    tokens_basis: "b"
  },
  oracle: { marker: "mechanical", kind: "chained-argv", argv: "a", proposed: true, source: "s", dispatch: "d" },
  replicable: "yes",
  receipt: "/r.jsonl",
  rul01_consulted: [{ line: "A1", how: "default, unruled" }],
  default_unruled: ["A1"],
  grade: "CLAIMED",
  sources: [{ path: "/p", locator: "l" }],
  actuals: { tokens: null, seconds: null, outcome: null, receipt_sha256: null, prior_gap: null }
})

const hex = (c: string) => c.repeat(64)

const receipt = () => ({
  id: "TEST-2",
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
  output_sha256: hex("a"),
  disposition: "DISCARD",
  notes: "n"
})

describe("R-2026-09-05-16, in the type", () => {
  it("rejects a card carrying predicted_wallclock", () => {
    const r = X.decodeCard({ ...card(), predicted_wallclock: "<a value struck by R-2026-09-05-16>" })
    expect(r.ok).toBe(false)
    if (!r.ok) {
      expect(r.why).toContain("excess property")
      expect(r.why).toContain("predicted_wallclock")
    }
  })
  it("rejects a rung carrying predicted_wallclock, where the intake draft put it", () => {
    const r = X.decodeRung({ ...rung(), predicted_wallclock: 3600 })
    expect(r.ok).toBe(false)
  })
  it("rejects one hidden inside the prior", () => {
    const c = card()
    const r = X.decodeCard({ ...c, prior: { ...c.prior, predicted_wallclock: 1 } })
    expect(r.ok).toBe(false)
  })
  it("keeps predicted_tokens, which is a usage quantity and stays", () => {
    expect(X.decodeCard({ ...card(), predicted_tokens: 220000 }).ok).toBe(true)
    expect(X.decodeRung(rung()).ok).toBe(true)
  })
  it("keeps measured seconds on a receipt, which are an outcome", () => {
    // The banked line: U-A16 split §2.3's strict `Receipt` off from the shape
    // the estate has already written, so this fixture decodes as the banked one.
    expect(X.decodeBankedReceipt(receipt()).ok).toBe(true)
  })
  it("names every struck field so the guard cannot be edited away quietly", () => {
    expect(X.WALLCLOCK_FIELDS).toContain("predicted_wallclock")
    expect(() => X.assertNoWallclockField("t", ["predicted_tokens"])).not.toThrow()
    expect(() => X.assertNoWallclockField("t", ["predicted_wallclock"])).toThrow(/R-2026-09-05-16/)
  })
})

describe("Card", () => {
  it("decodes README §5's field set", () => {
    expect(X.decodeCard(card()).ok).toBe(true)
  })
  it("hands back the decoded value, not just a verdict", () => {
    const r = X.decodeCard(card())
    expect(r.ok).toBe(true)
    if (r.ok) {
      expect(r.value.id).toBe("TEST-0")
      expect(r.value.prior.p_pass).toBe(0.5)
      expect(r.value.hypotheses[0]?.statement).toBe("s")
    }
  })
  it("refuses an unknown key rather than stripping it", () => {
    const r = X.decodeCard({ ...card(), invented_field: 1 })
    expect(r.ok).toBe(false)
    if (!r.ok) expect(r.why).toContain("invented_field")
  })
  it("refuses a status outside README §5's vocabulary", () => {
    expect(X.decodeCard({ ...card(), status: "MAYBE" }).ok).toBe(false)
  })
  it("refuses a grade outside MEASURED | CLAIMED | UNKNOWN", () => {
    const c = card()
    expect(X.decodeCard({ ...c, result: { ...c.result, grade: "MEASURED-ish" } }).ok).toBe(false)
  })
  it("refuses a basis outside flat | history | text", () => {
    expect(X.decodeCard({ ...card(), prior: { basis: "vibes" } }).ok).toBe(false)
  })
  it("refuses a p_pass outside [0,1]", () => {
    expect(X.decodeCard({ ...card(), prior: { basis: "flat", p_pass: 1.5 } }).ok).toBe(false)
  })
  it("refuses a created that is not YYYY-MM-DD", () => {
    expect(X.decodeCard({ ...card(), created: "the sixth" }).ok).toBe(false)
  })
  it("takes data_already_collected as a boolean or the word partial", () => {
    expect(X.decodeCard({ ...card(), data_already_collected: "partial" }).ok).toBe(true)
    expect(X.decodeCard({ ...card(), data_already_collected: "maybe" }).ok).toBe(false)
  })
  it("refuses an arm key README §5 does not name — the REPORT-KIT defect", () => {
    const r = X.decodeCard({ ...card(), arm: { model: "opus", "~/.claude; prompt names cc3)": null } })
    expect(r.ok).toBe(false)
  })

  it("decodes the evaluator's optional ladder fields and a runnable mutation hint", () => {
    const value = {
      ...card(),
      repo: "mecattaf/substrate",
      executor: "mechanical",
      oracle: {
        marker: "mechanical",
        kind: "shell",
        argv: "sh scripts/test.sh",
        proposed: false,
        source: "fixture",
        dispatch: "fixture"
      },
      actuals: { tokens: null, seconds: null, outcome: null, receipt_sha256: null, prior_gap: null },
      mutation_hint: { kind: "patch", description: "change one tracked byte", patch: "diff --git a/a b/a" },
      prior_lock_commit: "1234567"
    }
    expect(X.decodeCard(value).ok).toBe(true)
  })
})

describe("Rung", () => {
  it("decodes a rung", () => {
    expect(X.decodeRung(rung()).ok).toBe(true)
  })
  it("requires the whole prior R-09 asks for", () => {
    const r = rung()
    const { p_pass, ...rest } = r.prior
    expect(X.decodeRung({ ...r, prior: rest }).ok).toBe(false)
  })
  it("requires the oracle's marker to be one of the four measured words", () => {
    const r = rung()
    expect(X.decodeRung({ ...r, oracle: { ...r.oracle, marker: "NO-ORACLE" } }).ok).toBe(true)
    expect(X.decodeRung({ ...r, oracle: { ...r.oracle, marker: "probably-fine" } }).ok).toBe(false)
  })
  it("takes a rung's p_pass_basis as the word only, not the word plus prose", () => {
    const r = rung()
    expect(X.decodeRung({ ...r, prior: { ...r.prior, p_pass_basis: "text — because" } }).ok).toBe(false)
  })
  it("decodes a shenanigan, whose basis line may carry its reasoning", () => {
    const sh = {
      id: "SH-00",
      title: "a fixture",
      status: "DRAFT",
      class: "shenanigan",
      created: "2026-09-06",
      drafted_by: "a session",
      discovered_in: ["/p:1-2"],
      detector: { marker: "mechanical", argv: "a", runs_against: "r", proposed: true },
      tenants_affected: ["meta"],
      first_unit: "u",
      rerun_prior: 0.85,
      rerun_prior_basis: "text — the reason",
      grade: "CLAIMED",
      sources: [{ path: "/p", locator: "l" }],
      receipt: "/r.jsonl",
      met_by: []
    }
    expect(X.decodeShenanigan(sh).ok).toBe(true)
    expect(X.decodeShenanigan({ ...sh, rerun_prior_basis: "because I said so" }).ok).toBe(false)
  })
})

describe("BankedReceipt", () => {
  it("decodes RAWA-FLOW §5's line as the estate banks it", () => {
    expect(X.decodeBankedReceipt(receipt()).ok).toBe(true)
  })
  it("decodes it with §5's own three hash fields instead", () => {
    const { output_sha256, ...rest } = receipt()
    expect(X.decodeBankedReceipt({ ...rest, test_output_sha256: hex("b"), pins_sha256: hex("c") }).ok).toBe(true)
  })
  it("refuses a receipt with no output hash at all", () => {
    const { output_sha256, ...rest } = receipt()
    const r = X.decodeBankedReceipt(rest)
    expect(r.ok).toBe(false)
    if (!r.ok) expect(r.why).toContain("at least one output hash")
  })
  it("refuses a disposition outside KEEP | DISCARD | CRASH", () => {
    expect(X.decodeBankedReceipt({ ...receipt(), disposition: "FINE" }).ok).toBe(false)
  })
  it("refuses a started_at that is not ISO-8601", () => {
    expect(X.decodeBankedReceipt({ ...receipt(), started_at: "this morning" }).ok).toBe(false)
  })
  it("decodes P12's detector row", () => {
    const row = {
      row_id: "L-24",
      sh_id: "SH-43",
      sha: { "cloudflare-os": "0eaec6c" },
      rc: 0,
      grade: "MEASURED",
      output_sha256: hex("e"),
      detector_sha256: hex("f")
    }
    expect(X.decodeDetectorReceipt(row).ok).toBe(true)
    expect(X.decodeEstateReceipt(row).ok).toBe(true)
    expect(X.decodeDetectorReceipt({ ...row, output_sha256: "not-a-hash" }).ok).toBe(false)
  })
})

describe("AttemptReceipt", () => {
  const base = { schemaVersion: 1, sequence: 1, campaign: "epsilon", issueNumber: "1" }
  it("decodes each of the five kinds the box has written", () => {
    expect(X.decodeAttemptReceipt({ ...base, kind: "diagnosis", attempt: 1, taskId: "t", diagnosis: "d", redaction: "conservative-v2" }).ok).toBe(true)
    expect(X.decodeAttemptReceipt({ ...base, kind: "retry", attempt: 2, taskId: "t", reason: "r", redaction: "conservative-v2" }).ok).toBe(true)
    expect(X.decodeAttemptReceipt({ ...base, kind: "pardon", actor: "uid:1000", reason: "r", tasks: null }).ok).toBe(true)
    expect(X.decodeAttemptReceipt({ ...base, kind: "escalation", body: "b" }).ok).toBe(true)
    expect(
      X.decodeAttemptReceipt({
        ...base,
        kind: "worker-outcome",
        taskId: "t",
        taskUuid: "u",
        taskRevision: "r",
        outcome: "needs-authority",
        reason: null,
        paths: ["a"]
      }).ok
    ).toBe(true)
  })
  it("refuses a kind the box has never written", () => {
    expect(X.decodeAttemptReceipt({ ...base, kind: "invented", body: "b" }).ok).toBe(false)
  })
  it("takes the v2 provenance block, and refuses a worklist hash that is not one", () => {
    const v2 = { ...base, schemaVersion: 2, kind: "escalation", body: "b", actor: "a", armSerial: 1, worklistSha256: `sha256:${hex("a")}`, writtenAt: "2026-08-15T19:42:19.691Z" }
    expect(X.decodeAttemptReceipt(v2).ok).toBe(true)
    expect(X.decodeAttemptReceipt({ ...v2, worklistSha256: "sha256:short" }).ok).toBe(false)
  })
})

describe("routing by the register layout", () => {
  it("reads the directory PROMPTS.md's header declares, not the file's own class", () => {
    expect(X.kindOf("EXP-000.md")).toBe("card")
    expect(X.kindOf("ladder/T-LAKE.md")).toBe("rung")
    expect(X.kindOf("SH/SH-01.md")).toBe("shenanigan")
  })
  it("routes a rung placed among the cards to the card schema, and it fails there", () => {
    expect(X.decodeByKind(X.kindOf("T-LAKE.md"), rung()).ok).toBe(false)
  })
})
