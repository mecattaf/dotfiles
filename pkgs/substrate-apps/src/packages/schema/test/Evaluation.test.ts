import { describe, expect, it } from "vitest"
import * as X from "../src/index.ts"

const digest = (value: string) => `sha256:${value.repeat(64)}`

const evaluation = (): Record<string, any> => ({
  unit_id: "U-A17-FIXTURE",
  kind: "build",
  card_sha256: digest("1"),
  deliverable: { repo: "/fixture/repo", branch: "fixture", commit_sha: "1234567" },
  oracle_argv: ["sh -c true"],
  oracle_sha256: digest("2"),
  worktree_path: "/tmp/fresh-worktree",
  oracle_rc: 0,
  oracle_output_sha256: digest("3"),
  oracle_output_normalization: "shell-v1",
  mutation: { kind: "hint", description: "a fixture mutation", rc: 1 },
  identity: {
    harness: "fixture-harness",
    model: "fixture-model",
    seat: "fixture-seat",
    row: "fixture-row",
    thread_id: "fixture-thread",
    window_id: "none"
  },
  tokens: { in_uncached: 1, cache_read: 2, cache_write: 3, out: 4, reasoning: 1, total: 10 },
  tokens_source: { kind: "fixture-source", path: "/fixture/usage", first_event: 1, last_event: 2 },
  seconds: 2,
  context_window: 100,
  max_context_used: 6,
  artifact_sha256: "none",
  pins_sha256: "none",
  evaluator: {
    argv_sha256: digest("4"),
    lock: digest("5"),
    tokens: { in_uncached: 0, cache_read: 0, cache_write: 0, out: 0, reasoning: 0, total: 0 },
    seconds: 0.2,
    execution_id: "fixture-execution"
  },
  verdict: "PASS",
  disposition_proposed: "KEEP"
})

const fields = [
  "unit_id", "kind", "card_sha256", "deliverable", "oracle_argv", "oracle_sha256", "worktree_path",
  "oracle_rc", "oracle_output_sha256", "oracle_output_normalization", "mutation", "identity", "tokens",
  "tokens_source", "seconds", "context_window", "max_context_used", "load_seconds", "concurrent_requests",
  "crash_reason", "artifact_sha256", "pins_sha256", "evaluator", "verdict", "disposition_proposed"
]

describe("Evaluation §2.2d", () => {
  it("has the complete field list and decodes a build", () => {
    expect([...X.EVALUATION_FIELDS]).toEqual(fields)
    expect(X.decodeEvaluation(evaluation()).ok).toBe(true)
  })

  it("accepts replay with a receipt reference", () => {
    const value = evaluation()
    value.kind = "replay"
    value.mutation = { kind: "ref", ref: digest("6") }
    expect(X.decodeEvaluation(value).ok).toBe(true)
  })

  it("confines evaluation kind to build or replay", () => {
    expect(X.decodeEvaluation({ ...evaluation(), kind: "merge" }).ok).toBe(false)
  })

  it("confines normalization to B15's three rule ids", () => {
    for (const rule of ["cargo-test-v1", "vitest-json-v1", "shell-v1"]) {
      expect(X.decodeEvaluation({ ...evaluation(), oracle_output_normalization: rule }).ok).toBe(true)
    }
    expect(X.decodeEvaluation({ ...evaluation(), oracle_output_normalization: "guess" }).ok).toBe(false)
  })

  it("requires exactly one deliverable digest", () => {
    expect(X.decodeEvaluation({ ...evaluation(), deliverable: { repo: "r", branch: "b" } }).ok).toBe(false)
    expect(X.decodeEvaluation({
      ...evaluation(),
      deliverable: { repo: "r", branch: "b", commit_sha: "1234567", tree_sha256: digest("7") }
    }).ok).toBe(false)
  })

  it("matches mutation shape to kind and refuses a vacuous PASS", () => {
    expect(X.decodeEvaluation({ ...evaluation(), mutation: { kind: "hint", description: "x", rc: 0 } }).ok).toBe(false)
    expect(X.decodeEvaluation({ ...evaluation(), kind: "replay", mutation: { kind: "hint", description: "x", rc: 1 } }).ok).toBe(false)
  })

  it("requires every evaluator token cell to be integer zero", () => {
    const value = evaluation()
    value.evaluator.tokens.out = 1
    const decoded = X.decodeEvaluation(value)
    expect(decoded.ok).toBe(false)
    if (!decoded.ok) expect(decoded.why).toMatch(/evaluator.*out/)
  })
})
