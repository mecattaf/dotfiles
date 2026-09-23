// The puller: the coordinator-side interpreter host (LINK-DESIGN: a holder advertising runtime:interpreter).
//
// It speaks the link's wire, unchanged: Lease with a journaled requestKey (Forgejo request key; a restart re-sends
// it and the floor answers the same grants, rule 2b), Heartbeat with the complete set it holds (level-triggered,
// ARC; an omitted lease is released, L3), Complete from a durable verdict outbox (Temporal RespondActivityTask*; a
// verdict survives a kill and is resent until the floor accepts or refuses it for good).
//
// A grant is one run. The puller fetches the run's script from the floor, checks it against the grant's content
// address, and hands it to an Executor with the run's own directory. The directory is keyed by run id, not by
// lease, so attempt n+1 of a run (after a kill, a lost lease or a restart) finds attempt n's journal and resumes
// from it: finished agent() calls are cache hits and are never dispatched again.
import { randomUUID } from "node:crypto"
import { writeFileSync } from "node:fs"
import { join } from "node:path"
import { Effect } from "effect"
import type { SubstrateClient } from "@substrate/api"
import type { AgentJob, Grant } from "@substrate/link/contract.ts"
import type { CompletePayload, FloorApi, LeaseReply } from "@substrate/link/floor.ts"
import { CompleteRefused, FloorError } from "@substrate/link/floor.ts"
import { PullerState } from "./state.ts"

export const A = "ultracode.mecattaf.dev/"
export const INTERPRETER_LABEL = "runtime:interpreter"

/** The floor's three calls as promises; a failure rejects with the link's own FloorError or CompleteRefused. */
export interface FloorPort {
  lease(p: { holderIdentity: string; capacity: number; requestKey: string }): Promise<LeaseReply>
  heartbeat(p: { holderIdentity: string; leaseIds: ReadonlyArray<string>; pendingRequestKey?: string }): Promise<{ renewed: ReadonlyArray<string>; lost: ReadonlyArray<string>; cancelRequested: ReadonlyArray<string> }>
  complete(p: CompletePayload): Promise<{ duplicate: boolean }>
}
const settle = <A, E>(eff: Effect.Effect<A, E>): Promise<A> =>
  Effect.runPromise(Effect.match(eff, { onFailure: (e) => ({ e }), onSuccess: (a) => ({ a }) })).then((r) => { if ("e" in r) throw r.e; return r.a })
export const floorPort = (api: FloorApi): FloorPort => ({
  lease: (p) => settle(api.lease(p)),
  heartbeat: (p) => settle(api.heartbeat(p)),
  complete: (p) => settle(api.complete(p))
})

export interface RunTask {
  readonly runId: string
  readonly leaseId: string
  readonly attempt: number
  readonly job: AgentJob
  readonly workflowName: string
  readonly args: unknown
  /** The run's directory; `script.js` is written there before the executor starts. */
  readonly dir: string
  readonly scriptPath: string
  readonly script: string
  readonly signal: AbortSignal
}
export interface RunVerdict { readonly result: "success" | "failure" | "cancelled"; readonly output: unknown }
export type Executor = (t: RunTask) => Promise<RunVerdict>

export interface PullerConfig {
  readonly holder: string
  readonly maxRuns: number
  readonly stateDir: string
  readonly pollMs?: number
  readonly heartbeatMs?: number
  /** Verdict outputs above this are cut to a preview (the floor's row limit is 2 MB). */
  readonly maxOutputBytes?: number
}
export interface PullerDeps {
  readonly floor: FloorPort
  readonly client: Pick<SubstrateClient, "runScript">
  readonly execute: Executor
  readonly log?: (ev: string, f?: Record<string, unknown>) => void
}

type Why = "lost" | "cancel" | "stop" | "superseded"
interface Active { readonly grant: Grant; readonly ac: AbortController; why?: Why; readonly done: Promise<void> }

const sha256 = async (s: string) => [...new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s)))].map((b) => b.toString(16).padStart(2, "0")).join("")
const sleep = (ms: number, signal?: AbortSignal) => new Promise<void>((ok) => {
  const t = setTimeout(ok, ms)
  signal?.addEventListener("abort", () => { clearTimeout(t); ok() }, { once: true })
})

export class Puller {
  readonly state: PullerState
  readonly active = new Map<string, Active>()
  #held: Record<string, Grant>
  #stop = new AbortController()
  #hbMs: number
  #fatal: unknown
  readonly #log: NonNullable<PullerDeps["log"]>

  constructor(readonly cfg: PullerConfig, readonly deps: PullerDeps) {
    this.state = new PullerState(cfg.stateDir)
    this.#held = this.state.held()
    this.#hbMs = cfg.heartbeatMs ?? 10_000
    this.#log = deps.log ?? (() => undefined)
  }

  get held(): Readonly<Record<string, Grant>> { return this.#held }

  /** Runs until stop() or a fatal floor answer (bad token, second session, redirect, misroute), which it rethrows. */
  async run(): Promise<void> {
    const stop = this.#stop.signal
    await this.flushOutbox()
    await this.readopt()
    const hb = this.heartbeatLoop()
    while (!stop.aborted && this.#fatal === undefined) {
      await this.flushOutbox()
      const free = this.cfg.maxRuns - this.active.size
      if (free > 0 && !stop.aborted) await this.lease(free)
      await sleep(this.cfg.pollMs ?? 5_000, stop)
    }
    this.#stop.abort()
    await hb
    for (const a of this.active.values()) { a.why ??= "stop"; a.ac.abort() }
    await Promise.all([...this.active.values()].map((a) => a.done))
    if (this.#fatal !== undefined) throw this.#fatal
  }

  /** Stop leasing and abort every run; nothing is completed, so each lease is re-adopted by the next start. */
  stop() { this.#stop.abort() }

  private fatal(e: unknown) { if (e instanceof FloorError && e.fatal) { this.#fatal = e; this.#stop.abort() } }
  private persistHeld() { this.state.putHeld(this.#held) }

  /** After a restart: vouch for every held lease; relaunch the renewed ones (they resume from their journal). */
  private async readopt() {
    const ids = Object.keys(this.#held)
    const pendingRequestKey = this.state.pendingKey()
    if (ids.length === 0 && pendingRequestKey === undefined) return
    try {
      const r = await this.deps.floor.heartbeat({ holderIdentity: this.cfg.holder, leaseIds: ids, ...(pendingRequestKey ? { pendingRequestKey } : {}) })
      for (const id of r.lost) delete this.#held[id]
      this.persistHeld()
      for (const id of r.renewed) { const g = this.#held[id]; if (g && !this.active.has(id)) { this.#log("readopt", { leaseId: id }); this.launch(g) } }
      for (const id of r.cancelRequested) this.abort(id, "cancel")
    } catch (e) { this.#log("readopt-error", { message: String((e as Error)?.message ?? e) }); this.fatal(e) }
  }

  private async lease(capacity: number) {
    let key = this.state.pendingKey()
    if (key === undefined) { key = randomUUID(); this.state.setPendingKey(key) }
    let r: LeaseReply
    try { r = await this.deps.floor.lease({ holderIdentity: this.cfg.holder, capacity, requestKey: key }) } catch (e) {
      this.#log("lease-error", { kind: (e as FloorError)?.kind, message: String((e as Error)?.message ?? e) }); this.fatal(e); return
    }
    if (typeof r.heartbeatSeconds === "number" && r.heartbeatSeconds > 0) this.#hbMs = Math.min(this.cfg.heartbeatMs ?? Infinity, r.heartbeatSeconds * 1000)
    for (const g of r.grants) this.#held[g.leaseId] = g
    this.persistHeld()
    this.state.setPendingKey(undefined)
    for (const bad of r.invalid ?? []) {
      if (bad.leaseId !== undefined && bad.attempt !== undefined) this.queueVerdict({ leaseId: bad.leaseId, attempt: bad.attempt, result: "failure", output: { reason: "pre-start/invalid-spec", message: bad.message } })
    }
    for (const g of r.grants) {
      for (const old of g.supersedes ?? []) { // L3: the earlier attempt stops before this one starts
        const a = this.active.get(old)
        if (a) { this.abort(old, "superseded"); await a.done }
        delete this.#held[old]
      }
      this.persistHeld()
      if (!this.active.has(g.leaseId)) this.launch(g)
    }
  }

  private abort(leaseId: string, why: Why) {
    const a = this.active.get(leaseId)
    if (a) { a.why ??= why; a.ac.abort() }
    else if (why === "cancel" && this.#held[leaseId]) {
      const g = this.#held[leaseId]!
      this.queueVerdict({ leaseId, attempt: g.attempt, result: "cancelled", output: { reason: "cancelled" } })
    }
  }

  private launch(g: Grant) {
    const ac = new AbortController()
    const entry: Active = { grant: g, ac, done: undefined as never }
    const work = async (): Promise<RunVerdict> => {
      const ann = g.job.metadata.annotations ?? {}
      const runId = ann[A + "run-id-raw"]
      if (!g.job.spec["runs-on"].includes(INTERPRETER_LABEL) || runId === undefined)
        return { result: "failure", output: { reason: "pre-start/invalid-spec", message: "not a run: the puller takes runtime:interpreter jobs with a run-id-raw annotation" } }
      const script = await this.deps.client.runScript(runId)
      const want = g.job.spec.with.prompt_ref.sha256
      if (await sha256(script) !== want) return { result: "failure", output: { reason: "pre-start/script-mismatch", message: `the floor's script does not hash to ${want}` } }
      const dir = this.state.runDir(runId)
      const scriptPath = join(dir, "script.js")
      writeFileSync(scriptPath, script)
      let args: unknown
      try { args = ann[A + "args"] === undefined ? undefined : JSON.parse(ann[A + "args"]!) } catch { return { result: "failure", output: { reason: "pre-start/invalid-spec", message: "the args annotation is not JSON" } } }
      this.#log("run-start", { runId, leaseId: g.leaseId, attempt: g.attempt })
      return this.deps.execute({ runId, leaseId: g.leaseId, attempt: g.attempt, job: g.job, workflowName: ann[A + "workflow-name"] ?? runId, args, dir, scriptPath, script, signal: ac.signal })
    }
    const done = work().then((v) => v, (e: unknown): RunVerdict => {
      if (e instanceof FloorError) return { result: "failure", output: { reason: "infra/script-unreadable", message: e.message } }
      return { result: "failure", output: { reason: "infra/puller-defect", message: String((e as Error)?.message ?? e).slice(0, 2000) } }
    }).then((v) => {
      const why = entry.why
      this.#log("run-end", { leaseId: g.leaseId, result: v.result, ...(why ? { aborted: why } : {}) })
      if (why === "lost" || why === "stop" || why === "superseded") return // no verdict: the lease is the floor's again, or re-adopted on restart
      this.queueVerdict({ leaseId: g.leaseId, attempt: g.attempt, result: why === "cancel" ? "cancelled" : v.result, output: this.cap(v.output) })
    }).finally(() => this.active.delete(g.leaseId))
    Object.assign(entry, { done })
    this.active.set(g.leaseId, entry)
  }

  private cap(output: unknown): unknown {
    const text = JSON.stringify(output ?? null)
    const max = this.cfg.maxOutputBytes ?? 1_500_000
    return Buffer.byteLength(text) <= max ? output : { truncated: true, bytes: Buffer.byteLength(text), preview: text.slice(0, 4000) }
  }

  private queueVerdict(v: CompletePayload) { this.state.putVerdict(v); void this.flushOutbox() }

  #flushing: Promise<void> | undefined
  #flushGen = 0
  /** Sends every verdict in the outbox; a transient failure leaves it for the next pass. */
  flushOutbox(): Promise<void> {
    if (this.#flushing) return this.#flushing
    const gen = ++this.#flushGen
    const p = (async () => {
      await Promise.resolve() // the pass starts after #flushing is set, so its finally clears this pass and no other
      try {
        for (const v of this.state.outbox()) {
          try { await this.deps.floor.complete(v) } catch (e) {
            if (e instanceof CompleteRefused) this.#log("verdict-refused", { leaseId: v.leaseId, code: e.code })
            else if (e instanceof FloorError && e.kind === "rejected") this.#log("verdict-rejected", { leaseId: v.leaseId, message: e.message })
            else { this.#log("verdict-retry", { leaseId: v.leaseId, message: String((e as Error)?.message ?? e) }); this.fatal(e); continue }
          }
          this.state.dropVerdict(v.leaseId)
          delete this.#held[v.leaseId]
          this.persistHeld()
        }
      } finally { if (this.#flushGen === gen) this.#flushing = undefined }
    })()
    this.#flushing = p
    return p
  }

  private async heartbeatLoop() {
    const stop = this.#stop.signal
    while (!stop.aborted) {
      await sleep(this.#hbMs, stop)
      if (stop.aborted) break
      const ids = Object.keys(this.#held)
      const pendingRequestKey = this.state.pendingKey()
      if (ids.length === 0 && pendingRequestKey === undefined) continue
      try {
        const r = await this.deps.floor.heartbeat({ holderIdentity: this.cfg.holder, leaseIds: ids, ...(pendingRequestKey ? { pendingRequestKey } : {}) })
        for (const id of r.lost) {
          this.#log("lease-lost", { leaseId: id })
          this.abort(id, "lost")
          if (!this.state.outbox().some((v) => v.leaseId === id)) delete this.#held[id]
        }
        if (r.lost.length > 0) this.persistHeld()
        for (const id of r.cancelRequested) { this.#log("cancel-requested", { leaseId: id }); this.abort(id, "cancel") }
      } catch (e) { this.#log("heartbeat-error", { message: String((e as Error)?.message ?? e) }); this.fatal(e) }
    }
  }
}
