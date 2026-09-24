// Pure mapping AgentJob -> ax Task JSON (FIELD-MAP-2026-09-23.md 5a keys). Ported from the option-A prototype
// (arc/proto/jobs.ts) with ARC-DECISION X1 applied: atespace `fleet`, image `ax-agent`, Gateway `halogen`, the names
// ax-fleet DESIGN.md 10.2 uses. No I/O: the link and any converter call the same function.
import { createHash } from "node:crypto"
import type { AgentJob, AxTask, Grant } from "./contract.ts"

export const ENV_BUDGET = 16384 // FIELD-MAP 5a hard pre-dispatch check (stock v0.3.0, before P5)
const A = "ultracode.mecattaf.dev/"
const utf8Len = (s: string) => new TextEncoder().encode(s).length
/** FIELD-MAP 5a journal key: `<sha256 hex>:<occurrence>` (substrate taskspec.ts journalKey). */
export const JOURNAL_KEY = /^[0-9a-f]{64}:\d+$/

export interface TaskShape {
  readonly atespace: string // `fleet`
  readonly image: string // `localhost:5000/ax-agent@sha256:...` (ax-fleet-image-ref)
  readonly gateway: string // `halogen`
  readonly command: (job: AgentJob) => ReadonlyArray<string> | undefined // e.g. ["ax-agent", "pi"] for seat:halogen
  readonly completeUrl?: string // set only in guest-completion mode (L7, pre-P1)
  readonly holder?: string // round 1: AX_CONWIP_HOLDER, the ownership mark a journal-less link checks before a fence
}

/** B7: no default seat. `undefined` unless `runs-on` names exactly one `seat:` label. */
export const seatOf = (job: AgentJob): string | undefined => {
  const seats = job.spec["runs-on"].filter((l) => l.startsWith("seat:"))
  return seats.length === 1 ? seats[0]!.slice(5) : undefined
}

/** B7: `runs-on` must be non-empty, name exactly one `seat:` label, and be wholly served by this link. */
export const validRunsOn = (job: AgentJob, served: ReadonlyArray<string>): { reason: string; message: string } | undefined => {
  const on = job.spec["runs-on"]
  if (on.length === 0) return { reason: "pre-start/runs-on-invalid", message: "runs-on is empty" }
  const seats = on.filter((l) => l.startsWith("seat:"))
  if (seats.length !== 1) return { reason: "pre-start/runs-on-invalid", message: `runs-on names ${seats.length} seat: labels, not 1` }
  const unserved = on.filter((l) => !served.includes(l))
  if (unserved.length > 0) return { reason: "pre-start/label-not-served", message: unserved.join(",") }
  return undefined
}

export type Built = { readonly _tag: "ok"; readonly task: AxTask } | { readonly _tag: "refused"; readonly reason: string; readonly message: string }

export function axTaskFromGrant(g: Grant, shape: TaskShape): Built {
  const job = g.job
  // Round 1 (fail closed): a guest Task without its per-lease token has no completion route; never create it.
  if (shape.completeUrl !== undefined && (g.leaseToken === undefined || g.leaseToken === ""))
    return { _tag: "refused", reason: "pre-start/lease-token-missing", message: "guest completion needs a leaseToken; the floor's token binding for this holder is not guest" }
  const ann = job.metadata.annotations ?? {}
  const lab = job.metadata.labels ?? {}
  if (ann[A + "prompt-unresolved"] !== undefined) // L8: never dispatch an item whose prompt was not resolved
    return { _tag: "refused", reason: "pre-start/prompt-unresolved", message: ann[A + "prompt-unresolved"]! }
  // Round 4 (FIELD-MAP 5a): the journal key is sha256 of canonical [prompt, opts minus label] plus the occurrence, and
  // only the floor-side converter can compute it (it holds opts and the occurrence). It rides the AgentJob as an
  // annotation; without it the grant is refused, never replaced by the prompt digest (two calls sharing one prompt).
  const journalKey = ann[A + "journal-key"]
  if (journalKey === undefined || !JOURNAL_KEY.test(journalKey))
    return { _tag: "refused", reason: "pre-start/invalid-spec", message: journalKey === undefined ? `annotation ${A}journal-key is missing` : `annotation ${A}journal-key is not <sha256 hex>:<occurrence>` }
  const w = job.spec.with
  const seat = seatOf(job)
  if (seat === undefined) return { _tag: "refused", reason: "pre-start/runs-on-invalid", message: "runs-on does not name exactly one seat: label" }
  const command = shape.command(job)
  if (command === undefined || command.length === 0) return { _tag: "refused", reason: "pre-start/seat-command-missing", message: `no command for seat ${seat}` }
  const env: Array<{ name: string; value: string }> = [
    { name: "AX_CONWIP_RUN_ID", value: ann[A + "run-id-raw"] ?? "" },
    { name: "AX_CONWIP_LABEL", value: ann[A + "label"] ?? "" },
    { name: "AX_CONWIP_MODEL", value: w.model },
    { name: "AX_CONWIP_ITEM_KEY", value: ann[A + "item-key"] ?? "" },
    { name: "AX_CONWIP_JOURNAL_KEY", value: journalKey },
    { name: "AX_CONWIP_WORKFLOW", value: lab[A + "workflow"] ?? "" },
    { name: "AX_CONWIP_PHASE_INDEX", value: lab[A + "phase-index"] ?? "" },
    { name: "AX_CONWIP_PHASE_TITLE", value: ann[A + "phase-title"] ?? "" },
    { name: "AX_CONWIP_SEAT", value: seat },
    { name: "AX_CONWIP_ATTEMPT", value: String(g.attempt) },
    { name: "AX_CONWIP_LEASE_ID", value: g.leaseId },
    ...(shape.holder !== undefined ? [{ name: "AX_CONWIP_HOLDER", value: shape.holder }] : []),
    { name: "AX_CONWIP_PROMPT_SHA256", value: w.prompt_ref.sha256 },
    { name: "AX_CONWIP_RESULT_PATH", value: "/workspace/.ax/result.json" },
    { name: "AX_CONWIP_USAGE_PATH", value: "/workspace/.ax/usage.json" }
  ]
  if (w.effort !== undefined) env.push({ name: "AX_CONWIP_EFFORT", value: w.effort })
  if (w.schema !== undefined) env.push({ name: "AX_CONWIP_SCHEMA_JSON", value: JSON.stringify(w.schema) })
  if (w.isolation !== undefined) env.push({ name: "AX_CONWIP_ISOLATION", value: w.isolation })
  if (w["agent-type"] !== undefined) env.push({ name: "AX_CONWIP_AGENT_TYPE", value: w["agent-type"] })
  if (job.spec["timeout-minutes"] !== undefined)
    env.push({ name: "AX_CONWIP_TIMEOUT_MINUTES", value: String(job.spec["timeout-minutes"]) })
  if (shape.completeUrl !== undefined && g.leaseToken !== undefined) { // L7 (a missing token was refused above): a per-lease token, never the fleet bearer
    env.push({ name: "AX_CONWIP_COMPLETE_URL", value: shape.completeUrl })
    env.push({ name: "AX_CONWIP_LEASE_TOKEN", value: g.leaseToken })
  }
  const used = env.reduce((n, e) => n + utf8Len(e.value), 0)
  // B12 (critique R2): the file route (AX_CONWIP_PROMPT_FILE) needs a Workspace that writes the file, and the Task
  // carries none yet. Until that route exists a prompt that does not fit inline is refused, never sent to a dead path.
  if (used > ENV_BUDGET) // FIELD-MAP D4 and probe test 4: over budget ax falls back silently, so refuse here
    return { _tag: "refused", reason: "pre-start/env-over-budget", message: `env values ${used} B > ${ENV_BUDGET} B before the prompt` }
  if (w.prompt === undefined || used + utf8Len(w.prompt) > ENV_BUDGET)
    return { _tag: "refused", reason: "pre-start/prompt-file-route-missing",
      message: w.prompt === undefined ? "no inline prompt and no Workspace route" : `prompt ${utf8Len(w.prompt)} B does not fit the ${ENV_BUDGET - used} B left inline` }
  env.push({ name: "AX_CONWIP_PROMPT", value: w.prompt })
  const total = env.reduce((n, e) => n + utf8Len(e.value), 0)
  if (total > ENV_BUDGET) // FIELD-MAP D4 and probe test 4: over budget ax falls back silently, so refuse here
    return { _tag: "refused", reason: "pre-start/env-over-budget", message: `env values ${total} B > ${ENV_BUDGET} B` }
  return {
    _tag: "ok",
    task: {
      apiVersion: "ax.io/v1alpha1",
      kind: "Task",
      metadata: { name: g.leaseId, atespace: shape.atespace },
      spec: { image: shape.image, command: [...command], env, gateway: { name: shape.gateway } }
    }
  }
}

// The spec digest used by create-only adoption (L4): found with the same digest = adopt, another = conflict.
// Only the fields the link writes are hashed, in a fixed order, so ax defaults added on the server do not count.
export const specDigest = (spec: { image?: string; command?: ReadonlyArray<string>; env?: ReadonlyArray<{ name?: string; value?: string }>; gateway?: { name?: string } | null }) =>
  createHash("sha256").update(JSON.stringify([
    spec.image ?? "", [...(spec.command ?? [])],
    [...(spec.env ?? [])].map((e) => [e.name ?? "", e.value ?? ""]),
    spec.gateway?.name ?? ""
  ])).digest("hex")

export const envBytes = (t: AxTask) => t.spec.env.reduce((n, e) => n + utf8Len(e.value), 0)
