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
import { createHash, randomUUID } from "node:crypto"
import { writeFileSync } from "node:fs"
import { join } from "node:path"
import { Effect } from "effect"
import type { SubstrateClient } from "@substrate/api"
import type { AgentJob, Grant } from "@substrate/link/contract.ts"
import type { CompletePayload, FloorApi, LeaseReply } from "@substrate/link/floor.ts"
import { CompleteRefused, FloorError } from "@substrate/link/floor.ts"
import { PullerState } from "./state.ts"
import { LogShipper } from "./logship.ts"
import type { AppendLog } from "./logship.ts"

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
  /**
   * G-BK4: honour the floor's nextPollSeconds (a paused holder is told 300 s) with +-10 % jitter, bounded below by
   * pollMs and above by maxPollMs (default 300000). Off: poll every pollMs, as before. A freed slot always wakes the loop.
   */
  readonly serverPoll?: boolean
  readonly maxPollMs?: number
  /** G-BK3: tail this file of the run's directory to the floor's live log while the run holds its lease (default
   *  events.jsonl). Needs deps.appendLog; false turns it off. */
  readonly logFile?: string | false
  readonly logIntervalMs?: number
  /** Red team loss-and-wip r2-2 (KEEP-3): server errors one verdict may collect before it is replaced by a small
   *  `infra/verdict-undeliverable` failure naming its output's sha256, and that replacement before it is dropped. Default 8. */
  readonly verdictAttempts?: number
}
export interface PullerDeps {
  readonly floor: FloorPort
  readonly client: Pick<SubstrateClient, "runScript">
  readonly execute: Executor
  readonly log?: (ev: string, f?: Record<string, unknown>) => void
  /** G-BK3: the floor's live-log append (SubstrateClient.appendLog). Absent: no live log. */
  readonly appendLog?: AppendLog
}

type Why = "lost" | "cancel" | "stop" | "superseded"

/** The run was aborted (lost, cancel, stop, superseded) while waiting on the floor. */
export class Aborted extends Error { constructor() { super("aborted") } }
/** Resolve with `p`, or reject with Aborted as soon as `signal` aborts (the request itself is left to settle). */
export const raceAbort = <T>(p: Promise<T>, signal: AbortSignal): Promise<T> => signal.aborted ? Promise.reject(new Aborted()) : new Promise<T>((ok, no) => {
  const on = () => no(new Aborted())
  signal.addEventListener("abort", on, { once: true })
  p.then((v) => { signal.removeEventListener("abort", on); ok(v) }, (e: unknown) => { signal.removeEventListener("abort", on); no(e) })
})
/** A failure worth retrying: the network, a 5xx, a 408 or 429; never a refusal (4xx) of the request itself. */
export const transient = (e: unknown): boolean => {
  const status = (e as { status?: unknown })?.status
  if (typeof status === "number") return status >= 500 || status === 408 || status === 429
  return !(e instanceof CompleteRefused)
}
/** Red team loss-and-wip r2-1 (KEEP-7): errnos of the host, not of the script or the puller's code. A run that dies of
 *  one is retried by the floor (`infra/puller-io` is an infra reason); any other executor exception stays final. */
export const HOST_ERRNOS: ReadonlySet<string> = new Set(["ENOSPC", "EDQUOT", "EIO", "EMFILE", "ENFILE", "ENOMEM", "EAGAIN", "EBUSY", "EROFS", "ETXTBSY"])
export const hostErrno = (e: unknown): string | undefined => {
  const code = (e as { code?: unknown })?.code
  if (typeof code === "string" && HOST_ERRNOS.has(code)) return code
  const m = /^(E[A-Z]+)\b/.exec(String((e as Error)?.message ?? ""))
  return m && HOST_ERRNOS.has(m[1]!) ? m[1] : undefined
}
const UNDELIVERABLE = "infra/verdict-undeliverable"
const isReplacement = (v: CompletePayload) => (v.output as { reason?: unknown; replaces?: unknown } | undefined)?.reason === UNDELIVERABLE
  && (v.output as { replaces?: unknown }).replaces !== undefined
interface Active { readonly grant: Grant; readonly ac: AbortController; why?: Why; readonly done: Promise<void>; readonly startedAt: number }

/** The puller's own view for a health endpoint (G-BK7): what it holds, runs, owes and when it last renewed. */
export interface PullerStatus {
  readonly holder: string; readonly state: "running" | "draining" | "stopping"; readonly held: number
  readonly active: ReadonlyArray<{ leaseId: string; attempt: number; runningMs: number; fenceInMs: number }>
  readonly outbox: number; readonly lastHeartbeatOkMs: number | null; readonly heartbeatFailures: number; readonly pollMs: number
  readonly counters: Readonly<Record<string, number>>
}

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
  #pollMs: number
  #draining = false
  #wake: (() => void) | undefined
  /** G-BK2: per lease, the send time of the last call the floor answered with it renewed (or its grant arrived). */
  readonly #renewedAt = new Map<string, number>()
  #lastHbOk: number | null = null
  #hbFailures = 0
  readonly counters: Record<string, number> = {}
  #fatal: unknown
  readonly #log: NonNullable<PullerDeps["log"]>
  readonly #floor: FloorPort
  /** KEEP-3: floor replies that were not errors; an HTTP 5xx after one of them is about that call's bytes. */
  #answered = 0
  readonly #verdictFailures = new Map<string, number>()
  readonly #failMark = new Map<string, number>()

  constructor(readonly cfg: PullerConfig, readonly deps: PullerDeps) {
    this.state = new PullerState(cfg.stateDir)
    this.#held = this.state.held()
    this.#hbMs = cfg.heartbeatMs ?? 10_000
    this.#pollMs = cfg.pollMs ?? 5_000
    this.#log = deps.log ?? (() => undefined)
    const seen = <T>(p: Promise<T>) => p.then((v) => { this.#answered++; return v })
    this.#floor = { lease: (p) => seen(deps.floor.lease(p)), heartbeat: (p) => seen(deps.floor.heartbeat(p)), complete: (p) => seen(deps.floor.complete(p)) }
  }

  get held(): Readonly<Record<string, Grant>> { return this.#held }

  /** Runs until stop() or a fatal floor answer (bad token, second session, redirect, misroute), which it rethrows. */
  async run(): Promise<void> {
    const stop = this.#stop.signal
    await this.flushOutbox()
    await this.readopt()
    const hb = this.heartbeatLoop()
    const fence = this.fenceLoop()
    while (!stop.aborted && this.#fatal === undefined) {
      await this.flushOutbox()
      // G-BK4: a draining puller leases nothing and stops once its runs have ended and their verdicts are sent
      if (this.#draining && this.active.size === 0 && this.state.outbox().length === 0) break
      // Red team loss-and-wip r2-2 (KEEP-3): no new run while a verdict is undelivered. Red team r3-1 (KEEP-12): a
      // held grant with no verdict waiting is a run of this puller whether or not it is running here yet.
      const waiting = new Set(this.state.outbox().map((v) => v.leaseId))
      const mine = new Set([...this.active.keys(), ...Object.keys(this.#held).filter((id) => !waiting.has(id))])
      const free = this.cfg.maxRuns - mine.size
      if (waiting.size === 0 && free > 0 && !stop.aborted && !this.#draining) await this.lease(free)
      await new Promise<void>((ok) => { this.#wake = ok; void sleep(this.pollDelay(), stop).then(ok) })
      this.#wake = undefined
    }
    this.#stop.abort()
    await hb
    await fence
    for (const a of this.active.values()) { a.why ??= "stop"; a.ac.abort(a.why) }
    await Promise.all([...this.active.values()].map((a) => a.done))
    if (this.#fatal !== undefined) throw this.#fatal
  }

  /** Stop leasing and abort every run; nothing is completed, so each lease is re-adopted by the next start. */
  stop() { this.#stop.abort() }

  /**
   * G-BK4, Buildkite's graceful stop: lease nothing more, keep heartbeating, let every run finish and its verdict go
   * out, and stop then. Past `timeoutMs` the remaining runs are aborted as by stop() (each harness gets its cancel
   * grace, G-BK1). Resolves when the stop has been requested (run() resolves when it is done).
   */
  drain(timeoutMs: number): void {
    if (this.#draining) return
    this.#draining = true
    this.#log("drain", { active: this.active.size, timeoutMs })
    this.#wake?.()
    if (timeoutMs <= 0) { this.stop(); return }
    const t = setTimeout(() => { this.#log("drain-timeout", { active: this.active.size }); this.stop() }, timeoutMs)
    t.unref?.()
    this.#stop.signal.addEventListener("abort", () => clearTimeout(t), { once: true })
  }
  get draining() { return this.#draining }

  status(now = Date.now()): PullerStatus {
    return {
      holder: this.cfg.holder, state: this.#stop.signal.aborted ? "stopping" : this.#draining ? "draining" : "running",
      held: Object.keys(this.#held).length,
      active: [...this.active.values()].map((a) => ({ leaseId: a.grant.leaseId, attempt: a.grant.attempt, runningMs: now - a.startedAt, fenceInMs: this.fenceAt(a.grant) - now })),
      outbox: this.state.outbox().length, lastHeartbeatOkMs: this.#lastHbOk, heartbeatFailures: this.#hbFailures, pollMs: this.#pollMs,
      counters: { ...this.counters }
    }
  }
  private count(k: string) { this.counters[k] = (this.counters[k] ?? 0) + 1 }

  private pollDelay(): number {
    if (!this.cfg.serverPoll) return this.#pollMs
    return Math.round(this.#pollMs * (0.9 + Math.random() * 0.2))
  }

  /**
   * G-BK2 (red team double-run-r1-1, ported from link.ts selfFenceAt): past reassignSeconds the floor may grant
   * attempt n+1 to another holder, so a run this puller has not seen renewed for reassignSeconds less half a lease
   * (one lease when the grant carries no bound) is aborted as lost: no verdict, its journal kept for the next attempt.
   */
  fenceAt(g: Grant): number {
    const lease = g.lease.leaseDurationSeconds * 1000
    const bound = g.reassignSeconds !== undefined && Number.isFinite(g.reassignSeconds) ? g.reassignSeconds * 1000 : lease
    const base = this.#renewedAt.get(g.leaseId) ?? Date.now()
    return base + Math.max(lease / 2, bound - lease / 2)
  }
  selfFence(now = Date.now()) {
    for (const [id, a] of this.active) {
      if (a.why !== undefined) continue
      if (now >= this.fenceAt(a.grant)) {
        this.#log("lease-expired", { leaseId: id, lastRenewal: this.#renewedAt.get(id) ?? null })
        this.count("self_fences")
        this.abort(id, "lost")
      }
    }
  }
  private async fenceLoop() {
    const stop = this.#stop.signal
    while (!stop.aborted) {
      await sleep(Math.min(1_000, this.#hbMs), stop)
      if (!stop.aborted) this.selfFence()
    }
  }

  private fatal(e: unknown) {
    if (e instanceof FloorError && e.fatal) {
      // Red team double-run-r1-2, as in the link: a 409 means another session holds this identity and may run
      // attempt n+1 of every lease held here; each run is fenced (lost, no verdict) before the exit.
      if (e.kind === "session-conflict") for (const id of [...this.active.keys()]) this.abort(id, "lost")
      this.#fatal = e; this.#stop.abort(); this.#wake?.()
    }
  }
  private persistHeld() { this.state.putHeld(this.#held) }

  /**
   * May this held grant start (or restart) here? Not while its own verdict waits in the outbox (codex review 3, C3-2:
   * a restart would run it again and overwrite that verdict), and not while a verdict of an attempt it supersedes
   * waits there (codex review 2, C2-2: the floor may still accept that verdict and withdraw this attempt, rule 4b).
   */
  private launchable(g: Grant): boolean {
    if (this.active.has(g.leaseId)) return false
    const pending = new Set(this.state.outbox().map((v) => v.leaseId))
    return !pending.has(g.leaseId) && !(g.supersedes ?? []).some((old) => pending.has(old))
  }

  /** After a restart: vouch for every held lease; relaunch the renewed ones (they resume from their journal). */
  private async readopt() {
    const ids = Object.keys(this.#held)
    const pendingRequestKey = this.state.pendingKey()
    if (ids.length === 0 && pendingRequestKey === undefined) return
    try {
      const sentAt = Date.now()
      const r = await this.#floor.heartbeat({ holderIdentity: this.cfg.holder, leaseIds: ids, ...(pendingRequestKey ? { pendingRequestKey } : {}) })
      for (const id of r.renewed) this.#renewedAt.set(id, sentAt)
      for (const id of r.lost) delete this.#held[id]
      this.persistHeld()
      for (const id of r.renewed) { const g = this.#held[id]; if (g && this.launchable(g)) { this.#log("readopt", { leaseId: id }); this.launch(g) } }
      for (const id of r.cancelRequested) this.abort(id, "cancel")
    } catch (e) { this.#log("readopt-error", { message: String((e as Error)?.message ?? e) }); this.fatal(e) }
  }

  private async lease(capacity: number) {
    let key = this.state.pendingKey()
    if (key === undefined) { key = randomUUID(); this.state.setPendingKey(key) }
    let r: LeaseReply
    const sentAt = Date.now()
    try { r = await this.#floor.lease({ holderIdentity: this.cfg.holder, capacity, requestKey: key }) } catch (e) {
      this.#log("lease-error", { kind: (e as FloorError)?.kind, message: String((e as Error)?.message ?? e) }); this.fatal(e); return
    }
    if (typeof r.heartbeatSeconds === "number" && r.heartbeatSeconds > 0) this.#hbMs = Math.min(this.cfg.heartbeatMs ?? Infinity, r.heartbeatSeconds * 1000)
    if (typeof r.nextPollSeconds === "number" && r.nextPollSeconds > 0 && this.cfg.serverPoll)
      this.#pollMs = Math.min(this.cfg.maxPollMs ?? 300_000, Math.max(this.cfg.pollMs ?? 5_000, r.nextPollSeconds * 1000))
    for (const g of r.grants) { this.#held[g.leaseId] = g; this.#renewedAt.set(g.leaseId, sentAt); this.count("grants") }
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
      if (this.launchable(g)) this.launch(g)
      else this.#log("launch-deferred", { leaseId: g.leaseId })
    }
  }

  private abort(leaseId: string, why: Why) {
    const a = this.active.get(leaseId)
    if (a) { a.why ??= why; a.ac.abort(why) }
    else if (why === "cancel" && this.#held[leaseId]) {
      const g = this.#held[leaseId]!
      this.queueVerdict({ leaseId, attempt: g.attempt, result: "cancelled", output: { reason: "cancelled" } })
    }
  }

  private launch(g: Grant) {
    const ac = new AbortController()
    const entry: Active = { grant: g, ac, done: undefined as never, startedAt: Date.now() }
    const work = async (): Promise<RunVerdict> => {
      const ann = g.job.metadata.annotations ?? {}
      const runId = ann[A + "run-id-raw"]
      if (!g.job.spec["runs-on"].includes(INTERPRETER_LABEL) || runId === undefined)
        return { result: "failure", output: { reason: "pre-start/invalid-spec", message: "not a run: the puller takes runtime:interpreter jobs with a run-id-raw annotation" } }
      const script = await this.fetchScript(runId, ac.signal)
      const want = g.job.spec.with.prompt_ref.sha256
      if (await sha256(script) !== want) return { result: "failure", output: { reason: "pre-start/script-mismatch", message: `the floor's script does not hash to ${want}` } }
      const dir = this.state.runDir(runId)
      const scriptPath = join(dir, "script.js")
      writeFileSync(scriptPath, script)
      let args: unknown
      try { args = ann[A + "args"] === undefined ? undefined : JSON.parse(ann[A + "args"]!) } catch { return { result: "failure", output: { reason: "pre-start/invalid-spec", message: "the args annotation is not JSON" } } }
      this.#log("run-start", { runId, leaseId: g.leaseId, attempt: g.attempt })
      const ship = this.deps.appendLog && this.cfg.logFile !== false
        ? new LogShipper({ append: this.deps.appendLog, name: g.job.metadata.name, leaseId: g.leaseId, attempt: g.attempt, dir, log: this.#log,
          ...(typeof this.cfg.logFile === "string" ? { file: this.cfg.logFile } : {}), ...(this.cfg.logIntervalMs !== undefined ? { intervalMs: this.cfg.logIntervalMs } : {}) })
        : undefined
      ship?.start()
      let v: RunVerdict
      try {
        v = await this.deps.execute({ runId, leaseId: g.leaseId, attempt: g.attempt, job: g.job, workflowName: ann[A + "workflow-name"] ?? runId, args, dir, scriptPath, script, signal: ac.signal })
      } finally { if (ship) { const failed = await ship.stop(); if (failed > 0) this.count("log_chunks_failed") } }
      return v
    }
    const done = work().then((v) => v, (e: unknown): RunVerdict => {
      if (e instanceof Aborted) return { result: "cancelled", output: { reason: "aborted" } }
      if (e instanceof FloorError) return { result: "failure", output: { reason: "infra/script-unreadable", message: e.message } }
      const errno = hostErrno(e)
      if (errno !== undefined) return { result: "failure", output: { reason: "infra/puller-io", errno, message: String((e as Error)?.message ?? e).slice(0, 2000) } }
      return { result: "failure", output: { reason: "infra/puller-defect", message: String((e as Error)?.message ?? e).slice(0, 2000) } }
    }).then((v) => {
      const why = entry.why
      this.#log("run-end", { leaseId: g.leaseId, result: v.result, ...(why ? { aborted: why } : {}) })
      this.count(`runs_ended_${why ?? v.result}`)
      if (why === "lost" || why === "stop" || why === "superseded") return // no verdict: the lease is the floor's again, or re-adopted on restart
      // G-BK1: a cancelled verdict names why the run was signalled (Buildkite's signal_reason)
      const output = why === "cancel" && typeof v.output === "object" && v.output !== null && !Array.isArray(v.output) ? { ...v.output, signal_reason: "cancel" } : v.output
      this.queueVerdict({ leaseId: g.leaseId, attempt: g.attempt, result: why === "cancel" ? "cancelled" : v.result, output: this.cap(output) })
    }).finally(() => { this.active.delete(g.leaseId); this.#wake?.() })
    Object.assign(entry, { done })
    this.active.set(g.leaseId, entry)
  }

  /**
   * The run's script, retried while the run is live (codex review 3, C3-10 and C3-13): a floor restart or a partition
   * is not a verdict, and an abort (lost, cancel, stop) ends the wait at once instead of pinning the active slot.
   */
  private async fetchScript(runId: string, signal: AbortSignal): Promise<string> {
    for (let wait = 250; ; wait = Math.min(wait * 2, 15_000)) {
      if (signal.aborted) throw new Aborted()
      try {
        return await raceAbort(this.deps.client.runScript(runId), signal)
      } catch (e) {
        if (e instanceof Aborted || signal.aborted) throw new Aborted()
        if (!transient(e)) throw e
        this.#log("script-retry", { runId, message: String((e as Error)?.message ?? e) })
        await sleep(wait, signal)
      }
    }
  }

  private cap(output: unknown): unknown {
    const text = JSON.stringify(output ?? null)
    const max = this.cfg.maxOutputBytes ?? 1_500_000
    return Buffer.byteLength(text) <= max ? output : { truncated: true, bytes: Buffer.byteLength(text), preview: text.slice(0, 4000) }
  }

  /** Red team loss-and-wip r2-2 (KEEP-3): the first verdict for a lease is the one delivered; a later one (a cancel
   *  that arrives while a success waits) never overwrites it. */
  private queueVerdict(v: CompletePayload) {
    if (this.state.hasVerdict(v.leaseId)) this.#log("verdict-kept", { leaseId: v.leaseId, ignored: v.result })
    else this.state.putVerdict(v)
    void this.flushOutbox()
  }

  /** KEEP-3: a server error is charged to the verdict when it is an RPC Defect reply, or an HTTP 5xx after the floor
   *  answered some other call since this verdict last failed; at the ceiling the verdict is replaced, then dropped. */
  private serverError(v: CompletePayload, e: FloorError) {
    const charged = e.status === undefined || (this.#failMark.get(v.leaseId) ?? -1) < this.#answered
    this.#failMark.set(v.leaseId, this.#answered)
    const n = (this.#verdictFailures.get(v.leaseId) ?? 0) + (charged ? 1 : 0)
    this.#verdictFailures.set(v.leaseId, n)
    if (n < (this.cfg.verdictAttempts ?? 8)) { this.#log("verdict-retry", { leaseId: v.leaseId, charged, try: n, message: e.message.slice(0, 200) }); return }
    this.#verdictFailures.delete(v.leaseId); this.#failMark.delete(v.leaseId)
    if (!isReplacement(v)) {
      const outputSha256 = createHash("sha256").update(JSON.stringify(v.output ?? null)).digest("hex")
      this.state.putVerdict({ leaseId: v.leaseId, attempt: v.attempt, result: "failure",
        output: { reason: UNDELIVERABLE, replaces: v.result, outputSha256, message: `${v.result} verdict refused ${n} times: ${e.message.slice(0, 200)}` } })
      this.#log("verdict-replaced", { leaseId: v.leaseId, result: v.result, tries: n, outputSha256 })
      return
    }
    this.state.dropVerdict(v.leaseId)
    delete this.#held[v.leaseId]
    this.persistHeld()
    this.#log("verdict-dead-letter", { leaseId: v.leaseId, tries: n })
  }

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
          try { await this.#floor.complete(v) } catch (e) {
            if (e instanceof CompleteRefused) this.#log("verdict-refused", { leaseId: v.leaseId, code: e.code })
            else if (e instanceof FloorError && e.kind === "rejected") this.#log("verdict-rejected", { leaseId: v.leaseId, message: e.message })
            else if (e instanceof FloorError && e.kind === "server-error") { this.serverError(v, e); continue }
            else { this.#log("verdict-retry", { leaseId: v.leaseId, message: String((e as Error)?.message ?? e) }); this.fatal(e); continue }
          }
          this.state.dropVerdict(v.leaseId)
          this.#verdictFailures.delete(v.leaseId); this.#failMark.delete(v.leaseId)
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
        const sentAt = Date.now()
        const r = await this.#floor.heartbeat({ holderIdentity: this.cfg.holder, leaseIds: ids, ...(pendingRequestKey ? { pendingRequestKey } : {}) })
        this.#lastHbOk = Date.now(); this.#hbFailures = 0
        for (const id of r.renewed) this.#renewedAt.set(id, sentAt)
        for (const id of r.lost) {
          this.#log("lease-lost", { leaseId: id })
          this.abort(id, "lost")
          if (!this.state.outbox().some((v) => v.leaseId === id)) delete this.#held[id]
        }
        if (r.lost.length > 0) this.persistHeld()
        for (const id of r.cancelRequested) { this.#log("cancel-requested", { leaseId: id }); this.abort(id, "cancel") }
        // codex review 3, C3-1: a renewed grant that runs nowhere here (the start-up re-adoption failed, or its launch
        // waited on an earlier attempt's verdict) starts now; level-triggered, so one failed call never strands it
        const cancelled = new Set(r.cancelRequested)
        for (const id of r.renewed) {
          const g = this.#held[id]
          if (g && !cancelled.has(id) && !stop.aborted && this.launchable(g) && this.active.size < this.cfg.maxRuns) { this.#log("readopt", { leaseId: id }); this.launch(g) }
        }
      } catch (e) { this.#hbFailures++; this.count("heartbeat_failures"); this.#log("heartbeat-error", { message: String((e as Error)?.message ?? e) }); this.fatal(e) }
      this.selfFence()
    }
  }
}
