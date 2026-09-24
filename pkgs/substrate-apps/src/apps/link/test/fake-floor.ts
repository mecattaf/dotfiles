// Test double for the Cloudflare floor: the FloorLink group served by Effect's stock HTTP RPC server through a web
// handler (the same `RpcServer.layerHttp` + `HttpRouter.toWebHandler` pair the prototype DO runs), called in-process
// through the link's `fetch`. State is in memory. It implements the floor rules of LINK-DESIGN.md section 4 as amended
// by "Critique applied", section H (B16):
//   rule 1   states queued, leased, orphaned, done; WIP = leased + orphaned
//   rule 2   route by runs-on against the holder's labels, cap per label, an admission stub, refuse at enqueue a job
//            whose runs-on is empty or does not name exactly one seat: label
//   rule 2b  a replayed requestKey returns the same grants (kept for the life of the double, at least lease + grace)
//   rule 4   stale-attempt, unknown-lease, duplicate; rule 4b: a verdict for attempt n while n+1 is still queued is
//            accepted and n+1 withdrawn
//   round 1  rule 4c: the verdict applied is recorded per leaseId, and a repeat for the same (leaseId, attempt) answers
//            duplicate: true before rule 4b is considered (a lost reply or a second sender never spends a second
//            release); rule 4b also accepts n's verdict while n+1 is leased to the SAME holder, which does not create
//            n+1 while n's verdict is undelivered (link.ts dispatch)
//   round 2  rule 4b names the grant it withdrew in the answer (`withdrew`); the link never infers a withdrawal. Rule
//            4c's duplicate answer replays the original answer's `withdrew`, so a lost reply is answered the same way
//   round 3  rule 4b also names the generation withdrawn (`withdrewTransitions`: the leaseTransitions a grant of it
//            carried or would have carried); `sendWithdrewGen: false` is a floor that omits it
//   rule 5   a timer (the DO alarm): leased past renew + lease becomes orphaned, even with a cancel pending
//   rule 6   the holder's heartbeat renews and re-adopts; lost for anything else; cancelRequested
//   rule 7   an omitted orphan is released, so is one past the grace; supersedes lists EVERY earlier attempt
//   round 4  rule 6b: a Heartbeat's `pendingRequestKey` vouches for every lease granted under that key (renewed and
//            re-adopted, never released as omitted) while the holder has not seen that Lease answered
//   rule 8   two budgets: infrastructure releases and agent retries, each final reason naming its budget
//   rule 9   a per-lease token, minted only for guest-mode holders (A3), single use
//   rule 10  at the deadline the floor sets cancel with reason deadline
//   rule 11  holder = f(bearer): a payload holderIdentity that differs answers 403; Complete only for that holder's
//            leases; one live session per holder (409); pause per holder
// It is NOT the production floor.
import { randomUUID } from "node:crypto"
import { Effect, Layer } from "effect"
import { HttpRouter } from "effect/unstable/http"
import { RpcSerialization, RpcServer } from "effect/unstable/rpc"
import { FloorLink, FloorLinkClient } from "../src/contract.ts"
import type { AgentJob, FailureOutput } from "../src/contract.ts"

type Job = {
  name: string; job: AgentJob; state: "queued" | "leased" | "orphaned" | "done"; attempt: number
  leaseId?: string; holder?: string; acquire?: number; renew?: number; orphanedAt?: number; transitions: number
  cancel?: string; result?: string; output?: unknown; usage?: unknown; supersedes: Array<string>; token?: string; deadline?: number
  history: Array<string>; infraSpent: number; agentSpent: number; holders: Record<string, string>
  pin?: { holder: string; until: number } // rule 7b (red team double-run-r1-1)
}
export type TokenBinding = string | { holder: string; labels?: Array<string>; guest?: boolean }
export interface FloorConfig {
  cap: number; leaseSeconds: number; graceSeconds: number; pollSeconds: number; heartbeatSeconds: number
  maxAttempts: number // rule 8: agent retries (actor-crashed, result-unreadable)
  infraAttempts?: number // rule 8: infrastructure releases (default 5)
  secondMs: number
  tokens: Record<string, TokenBinding>
  labelCaps?: Record<string, number> // rule 2: cap per label
  timer?: boolean // rule 5: the DO alarm as a real timer (default true)
  overGrant?: number // a broken floor that grants this many more than asked (B11's test)
  skewedEncode?: boolean // round 1: a floor whose schema drifted from the link's; grants go out without validation
  sendWithdrewGen?: boolean // round 3: Complete names the generation withdrawn (default true)
  pinSeconds?: number // rule 7b: a grace release keeps n+1 for n's holder this long, or until it heartbeats (default graceSeconds)
}
const DEFAULT_LABELS = ["seat:halogen", "runtime:gvisor"]
const INFRA = new Set(["omitted", "grace", "infra/task-lost", "pre-start/pending-timeout", "pre-start/ax-unavailable", "pre-start/resource-exhausted", "pre-start/superseded-verdict-pending", "infra/link-defect"])
const AGENT = new Set(["infra/actor-crashed", "infra/result-unreadable"])

export class FakeFloor {
  readonly jobs = new Map<string, Job>()
  readonly grants = new Map<string, Array<string>>()
  readonly sessions = new Map<string, { id: string; until: number }>()
  readonly calls: Array<{ rpc: string; holder?: string; capacity?: number; granted?: number; leaseIds?: ReadonlyArray<string>; status?: number }> = []
  readonly paused = new Set<string>()
  readonly verdicts = new Map<string, { attempt: number; result: string; reason?: string; withdrew?: string; withdrewTransitions?: number }>() // rule 4c
  admit: (job: AgentJob) => boolean = () => true // rule 3 stub (seat readings)
  seq = 0
  down = false
  redeliver: Array<string> = [] // at-least-once: the next Lease hands these leases out again
  private readonly timer: ReturnType<typeof setInterval> | undefined
  constructor(readonly o: FloorConfig) {
    if (o.timer !== false) { this.timer = setInterval(() => this.sweep(), o.secondMs); this.timer.unref?.() }
  }
  close() { if (this.timer) clearInterval(this.timer) }
  private ms = (s: number) => s * this.o.secondMs
  private binding(token: string) {
    const b = this.o.tokens[token]
    if (b === undefined) return undefined
    return typeof b === "string" ? { holder: b, labels: DEFAULT_LABELS, guest: false } : { holder: b.holder, labels: b.labels ?? DEFAULT_LABELS, guest: b.guest ?? false }
  }
  private bindingOf(holder: string) {
    for (const t of Object.keys(this.o.tokens)) { const b = this.binding(t)!; if (b.holder === holder) return b }
    return undefined
  }

  /** Rule 2 (amended): refuses a job whose runs-on is empty or does not name exactly one seat: label. */
  enqueue(job: AgentJob): boolean {
    const seats = job.spec["runs-on"].filter((l) => l.startsWith("seat:"))
    if (job.spec["runs-on"].length === 0 || seats.length !== 1) return false
    this.enqueueUnchecked(job)
    return true
  }
  /** A floor without rule 2's enqueue check, to test the link's own defence (B7). */
  enqueueUnchecked(job: AgentJob) {
    if (!this.jobs.has(job.metadata.name)) this.jobs.set(job.metadata.name, { name: job.metadata.name, job, state: "queued", attempt: 1, transitions: 0, supersedes: [], history: [], infraSpent: 0, agentSpent: 0, holders: {} })
  }
  cancel(name: string, why = "tom") {
    const j = this.jobs.get(name)!
    if (j.state === "queued") this.finish(j, "cancelled", { reason: why })
    else if (j.state !== "done") j.cancel = why
  }
  wip(label?: string) { return [...this.jobs.values()].filter((j) => (j.state === "leased" || j.state === "orphaned") && (label === undefined || j.job.spec["runs-on"].includes(label))).length }
  stats() { return { seq: ++this.seq, cap: this.o.cap, wip: this.wip(), queued: [...this.jobs.values()].filter((j) => j.state === "queued").length, done: [...this.jobs.values()].filter((j) => j.state === "done").length } }
  private finish(j: Job, result: string, output?: unknown, usage?: unknown) {
    Object.assign(j, { state: "done", result, output, usage, token: undefined }); j.history.push(`done:${result}`)
  }
  /** An orphan the fleet side no longer vouches for: a cancelled job ends cancelled, any other goes back to the queue. */
  private release(j: Job, why: string) {
    if (j.cancel) { j.history.push(`released:${why}`); return this.finish(j, "cancelled", { reason: j.cancel }) }
    const h = j.holder
    this.requeue(j, why)
    const pin = this.o.pinSeconds ?? this.o.graceSeconds
    if (why === "grace" && h !== undefined && j.state === "queued" && pin > 0) j.pin = { holder: h, until: Date.now() + this.ms(pin) } // rule 7b
  }
  private requeue(j: Job, why: string) {
    j.history.push(`requeue:${why}`)
    const infra = INFRA.has(why) || !AGENT.has(why)
    if (infra) j.infraSpent++; else j.agentSpent++
    if (infra && j.infraSpent >= (this.o.infraAttempts ?? 5)) return this.finish(j, "failure", { reason: "infra/retry-budget-spent", message: why })
    if (!infra && j.agentSpent >= this.o.maxAttempts) return this.finish(j, "failure", { reason: "agent/retry-budget-spent", message: why })
    const old = j.leaseId!
    Object.assign(j, { state: "queued", attempt: j.attempt + 1, transitions: j.transitions + 1, supersedes: [...j.supersedes, old], leaseId: undefined, holder: undefined, token: undefined, orphanedAt: undefined })
  }
  /** The DO storage alarm's work (rules 5, 7 b and 10). Runs on the timer and on every request. */
  sweep(now = Date.now()) {
    for (const j of this.jobs.values()) {
      if (j.state === "leased" && j.deadline !== undefined && now >= j.deadline && !j.cancel) j.cancel = "deadline"
      if (j.state === "leased" && j.renew! + this.ms(this.o.leaseSeconds) <= now) { // L3: expiry never frees a live slot,
        j.state = "orphaned"; j.orphanedAt = now; j.history.push("orphaned") // even when a cancel is pending
      }
      if (j.state === "orphaned" && j.orphanedAt! + this.ms(this.o.graceSeconds) <= now) this.release(j, "grace") // L3 b
    }
  }
  private grantable(j: Job, labels: Array<string>, extra: Map<string, number>) {
    if (j.state !== "queued") return false
    if (!j.job.spec["runs-on"].every((l) => labels.includes(l))) return false // rule 2: routed by label
    for (const l of j.job.spec["runs-on"]) {
      const cap = this.o.labelCaps?.[l]
      if (cap !== undefined && this.wip(l) + (extra.get(l) ?? 0) >= cap) return false
    }
    return this.admit(j.job)
  }
  lease(p: { holderIdentity: string; capacity: number; requestKey: string }) {
    this.sweep()
    const b = this.bindingOf(p.holderIdentity)
    let rows: Array<Job>
    const prior = this.grants.get(p.requestKey)
    if (prior) rows = prior.map((id) => [...this.jobs.values()].find((j) => j.leaseId === id && j.state !== "done")).filter((j): j is Job => j !== undefined)
    else if (this.paused.has(p.holderIdentity) || b === undefined) rows = []
    else {
      const free = Math.max(0, Math.min(p.capacity, this.o.cap - this.wip())) + (this.o.overGrant ?? 0)
      const extra = new Map<string, number>()
      rows = []
      for (const j of this.jobs.values()) {
        if (rows.length >= free) break
        if (!this.grantable(j, b.labels, extra)) continue
        if (j.pin !== undefined && j.pin.holder !== p.holderIdentity && j.pin.until > Date.now()) continue // rule 7b
        rows.push(j)
        for (const l of j.job.spec["runs-on"]) extra.set(l, (extra.get(l) ?? 0) + 1)
      }
      const now = Date.now()
      for (const j of rows) {
        const tm = j.job.spec["timeout-minutes"]
        const leaseId = `${j.name}-a${j.attempt}`
        Object.assign(j, { pin: undefined, state: "leased", leaseId, holder: p.holderIdentity, acquire: now, renew: now, token: b.guest ? randomUUID() : undefined,
          deadline: tm === undefined ? undefined : now + this.ms(tm * 60) })
        j.holders[leaseId] = p.holderIdentity
        j.history.push(`leased:a${j.attempt}`)
      }
      this.grants.set(p.requestKey, rows.map((j) => j.leaseId!))
    }
    if (this.redeliver.length) {
      rows = [...rows, ...this.redeliver.map((id) => [...this.jobs.values()].find((j) => j.leaseId === id)).filter((j): j is Job => j !== undefined)]
      this.redeliver = []
    }
    this.calls.push({ rpc: "Lease", holder: p.holderIdentity, capacity: p.capacity, granted: rows.length })
    return {
      grants: rows.map((j) => ({
        leaseId: j.leaseId!, attempt: j.attempt, job: j.job,
        lease: { holderIdentity: j.holder!, leaseDurationSeconds: this.o.leaseSeconds, acquireTime: j.acquire!, renewTime: j.renew!, leaseTransitions: j.transitions },
        ...(j.supersedes.length ? { supersedes: [...j.supersedes] } : {}), ...(j.token ? { leaseToken: j.token } : {}), ...(j.deadline !== undefined ? { deadline: j.deadline } : {}), reassignSeconds: this.o.leaseSeconds + this.o.graceSeconds + (this.o.pinSeconds ?? this.o.graceSeconds)
      })),
      stats: this.stats(), nextPollSeconds: this.paused.has(p.holderIdentity) ? this.o.pollSeconds * 10 : this.o.pollSeconds, heartbeatSeconds: this.o.heartbeatSeconds
    }
  }
  vouchByKey = true // round 4 rule 6b; false is an L1-only floor that ignores pendingRequestKey
  heartbeat(p: { holderIdentity: string; leaseIds: ReadonlyArray<string>; pendingRequestKey?: string }) {
    this.sweep()
    this.calls.push({ rpc: "Heartbeat", holder: p.holderIdentity, leaseIds: p.leaseIds })
    for (const j of this.jobs.values()) if (j.pin?.holder === p.holderIdentity) j.pin = undefined // rule 7b: it hears lost now
    const byKey = new Set(this.vouchByKey && p.pendingRequestKey !== undefined ? this.grants.get(p.pendingRequestKey) ?? [] : [])
    for (const id of byKey) { // rule 6b: vouched for by key, not listed (the holder never saw these ids)
      if (p.leaseIds.includes(id)) continue
      const j = [...this.jobs.values()].find((x) => x.leaseId === id && (x.state === "leased" || x.state === "orphaned") && x.holder === p.holderIdentity)
      if (!j) continue
      if (j.state === "orphaned") { j.state = "leased"; j.history.push("re-adopted") }
      j.renew = Date.now()
    }
    const renewed: Array<string> = [], lost: Array<string> = [], cancelRequested: Array<string> = []
    for (const id of p.leaseIds) {
      const j = [...this.jobs.values()].find((x) => x.leaseId === id && (x.state === "leased" || x.state === "orphaned") && x.holder === p.holderIdentity)
      if (!j) { lost.push(id); continue }
      if (j.state === "orphaned") { j.state = "leased"; j.history.push("re-adopted") } // the holder vouches again
      j.renew = Date.now(); renewed.push(id)
      if (j.cancel) cancelRequested.push(id)
    }
    for (const j of this.jobs.values()) // L3 a: an orphaned lease its holder no longer lists is gone on the fleet side
      if (j.state === "orphaned" && j.holder === p.holderIdentity && !p.leaseIds.includes(j.leaseId!) && !byKey.has(j.leaseId!)) this.release(j, "omitted")
    return { renewed, lost, cancelRequested, stats: this.stats() }
  }
  /** `holder` is the bearer's holder (rule 11); undefined only for the guest path, which its lease token authorises. */
  complete(p: { leaseId: string; attempt: number; result: string; output?: unknown; usage?: unknown }, holder?: string) {
    this.sweep()
    this.calls.push({ rpc: "Complete", leaseIds: [p.leaseId] })
    const seen = this.verdicts.get(p.leaseId) // rule 4c: at most one verdict per (leaseId, attempt)
    if (seen !== undefined && seen.attempt === p.attempt) return { duplicate: true, stats: this.stats(), ...this.w(seen.withdrew, seen.withdrewTransitions) }
    const name = p.leaseId.replace(/-a\d+$/, "")
    let j = [...this.jobs.values()].find((x) => x.leaseId === p.leaseId)
    let withdrew: string | undefined, withdrewTransitions: number | undefined
    if (!j) {
      const q = this.jobs.get(name)
      if (!q) return { code: "unknown-lease" as const }
      // rule 4b: attempt n's verdict while n+1 is still queued: accept it and withdraw n+1
      // rule 4b (round 1): n+1 queued, or leased to the holder of n (that holder has not created it)
      const nHolder = q.holders[p.leaseId]
      const withdrawable = q.state === "queued" || (q.state === "leased" && q.holder === nHolder)
      if (withdrawable && q.attempt === p.attempt + 1 && q.supersedes.includes(p.leaseId) && (holder === undefined || nHolder === holder)) {
        q.history.push(`withdrawn:a${q.attempt}`)
        withdrew = `${q.name}-a${q.attempt}`; withdrewTransitions = q.transitions
        Object.assign(q, { state: "leased", attempt: p.attempt, leaseId: p.leaseId, holder: nHolder, token: undefined, renew: Date.now(), supersedes: q.supersedes.filter((x) => x !== p.leaseId) })
        j = q
      } else return { code: "stale-attempt" as const }
    }
    if (holder !== undefined && j.holders[p.leaseId] !== holder) return { code: "unknown-lease" as const } // rule 11 (red team auth r2-7: no oracle for a stranger)
    if (j.state === "done") return { duplicate: true, stats: this.stats() }
    if ((j.state !== "leased" && j.state !== "orphaned") || j.attempt !== p.attempt) return { code: "stale-attempt" as const }
    const reason = (p.output as FailureOutput | undefined)?.reason
    this.verdicts.set(p.leaseId, { attempt: p.attempt, result: p.result, ...(reason !== undefined ? { reason } : {}), ...(withdrew !== undefined ? { withdrew, withdrewTransitions } : {}) })
    const w = this.w(withdrew, withdrewTransitions)
    if (p.result === "failure" && reason !== undefined && (INFRA.has(reason) || AGENT.has(reason))) { this.requeue(j, reason); return { duplicate: false, stats: this.stats(), ...w } }
    this.finish(j, p.result, p.output ?? (j.cancel ? { reason: j.cancel } : null), p.usage ?? null)
    return { duplicate: false, stats: this.stats(), ...w }
  }
  private w(withdrew: string | undefined, t: number | undefined) {
    if (withdrew === undefined) return {}
    return this.o.sendWithdrewGen === false || t === undefined ? { withdrew } : { withdrew, withdrewTransitions: t }
  }
  /** L7: the guest's own Complete, authorised by its per-lease token alone (single use, bound to one lease). */
  guestComplete(leaseId: string, token: string, result: string, output?: unknown) {
    const j = [...this.jobs.values()].find((x) => x.leaseId === leaseId)
    if (!j || j.token === undefined || j.token !== token) return { refused: "token" as const }
    j.token = undefined // single use
    return this.complete({ leaseId, attempt: j.attempt, result, output })
  }

  private handlerCache: ((r: Request) => Promise<Response>) | undefined
  get handler(): (r: Request) => Promise<Response> { return this.handlerCache ??= this.skewed() ? this.lenientHandler() : this.strictHandler() }
  private skewed() { return this.o.skewedEncode === true }
  /** Round 1: the same handlers served through the link's lenient view of Lease, so a grant is sent as the floor
   *  holds it, without the strict encode (a floor whose contract drifted). */
  private lenientHandler() {
    return HttpRouter.toWebHandler(
      RpcServer.layerHttp({ group: FloorLinkClient, path: "/rpc", protocol: "http" }).pipe(
        Layer.provide(FloorLinkClient.toLayer({
          Lease: (p) => Effect.sync(() => this.lease(p)),
          Heartbeat: (p) => Effect.sync(() => this.heartbeat(p)),
          Complete: (p, o) => Effect.suspend(() => {
            const r = this.complete(p, String((o.headers as Record<string, string>)["x-link-holder"] ?? ""))
            return r.code !== undefined ? Effect.fail({ code: r.code }) : Effect.succeed({ duplicate: r.duplicate!, stats: r.stats!, ...(r.withdrew !== undefined ? { withdrew: r.withdrew } : {}), ...(r.withdrewTransitions !== undefined ? { withdrewTransitions: r.withdrewTransitions } : {}) })
          })
        })),
        Layer.provide(RpcSerialization.layerJson)), { disableLogger: true }).handler as (r: Request) => Promise<Response>
  }
  private strictHandler() { return HttpRouter.toWebHandler(
    RpcServer.layerHttp({ group: FloorLink, path: "/rpc", protocol: "http" }).pipe(
      Layer.provide(FloorLink.toLayer({
        Lease: (p) => Effect.sync(() => this.lease(p)),
        Heartbeat: (p) => Effect.sync(() => this.heartbeat(p)),
        Complete: (p, o) => Effect.suspend(() => {
          const r = this.complete(p, String((o.headers as Record<string, string>)["x-link-holder"] ?? ""))
          return r.code !== undefined ? Effect.fail({ code: r.code }) : Effect.succeed({ duplicate: r.duplicate!, stats: r.stats!, ...(r.withdrew !== undefined ? { withdrew: r.withdrew } : {}), ...(r.withdrewTransitions !== undefined ? { withdrewTransitions: r.withdrewTransitions } : {}) })
        })
      })),
      Layer.provide(RpcSerialization.layerJson)), { disableLogger: true }).handler as (r: Request) => Promise<Response> }

  /** The Worker entry: network, bearer (per-link token bound to a holder), holder binding (403), then one session per
   *  holder (409, L5). The resolved holder reaches the handlers as `x-link-holder`; a client's own copy is dropped. */
  readonly fetch: typeof globalThis.fetch = async (input, init) => {
    if (this.down) throw new TypeError("fetch failed")
    const req = new Request(input as string | URL | Request, init)
    const b = this.binding((req.headers.get("authorization") ?? "").replace(/^Bearer /, ""))
    const answer = (status: number, body: string) => { this.calls.push({ rpc: "entry", status }); return new Response(body, { status }) }
    if (b === undefined) return answer(401, "unauthorized")
    const body = await req.clone().text()
    let msgs: Array<any> = []
    try { const m = JSON.parse(body); msgs = Array.isArray(m) ? m : [m] } catch { /* not JSON: the RPC server answers */ }
    if (msgs.some((m) => m?.payload && typeof m.payload.holderIdentity === "string" && m.payload.holderIdentity !== b.holder)) return answer(403, "holder mismatch")
    const sid = req.headers.get("x-link-session") ?? ""
    const s = this.sessions.get(b.holder), now = Date.now()
    if (s && s.id !== sid && s.until > now) return answer(409, "session held")
    this.sessions.set(b.holder, { id: sid, until: now + this.ms(3 * this.o.heartbeatSeconds) })
    const u = new URL(req.url)
    if (u.pathname === "/rpc/") u.pathname = "/rpc" // Effect's client posts to "<url>/" (PROTO.md section 4)
    const h = new Headers(req.headers)
    h.set("x-link-holder", b.holder)
    return this.handler(new Request(u, { method: req.method, headers: h, body }))
  }
}
