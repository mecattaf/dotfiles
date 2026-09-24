// The NAS link (LINK-DESIGN.md section 5): one outbound-only process between the Cloudflare floor and ax.
//   Lease (free capacity on every poll, ARC; the outbox drains first, B15; the requestKey is journaled, B8)
//   -> journal the grant (write-ahead) -> fence every superseded attempt: DeleteTask and wait for NotFound (L3, B2)
//   -> wait for a sandbox slot (B11) -> GetTask, UpdateTask only on NotFound (L4, create-only), read it back (B12)
//   -> resync by paging ListTasks (Buildkite: the executor's list is the ledger; B1) and confirming every absence with
//   GetTask -> read the outcome (P1: terminal phase + GetTaskResult, retried and digest-checked, B4; guest mode only
//   when configured, L7, B6) -> Complete through the journal's outbox (L6) -> DeleteTask after the floor acknowledged.
// One batched Heartbeat per session carries the COMPLETE held set; its reply carries cancel and lost (Temporal).
// Nothing is leased while ax is unreachable, the completion mode is unproven (B6) or the egress Gateway is missing or
// open (B10).
import { createHash, randomUUID } from "node:crypto"
import { isIPv4, isIPv6 } from "node:net"
import { Cause, Deferred, Effect, Schedule, Semaphore } from "effect"
import { gatewayAllowsAll, listAll } from "./ax.ts"
import type { AxApi, AxError, AxObserved } from "./ax.ts"
import type { FailureOutput, Grant, Result, Usage } from "./contract.ts"
import type { FloorApi, FloorError, LeaseReply } from "./floor.ts"
import { axTaskFromGrant, specDigest, validRunsOn } from "./jobs.ts"
import type { TaskShape } from "./jobs.ts"
import { genOf, Journal, laterGen, sameGen } from "./journal.ts"
import type { Gen, LeaseRec } from "./journal.ts"

export interface LinkConfig {
  readonly holder: string // holderIdentity; bound to this link's token on the floor
  readonly maxInFlight: number // sandbox cap: the WorkerPool replicas this link may fill
  readonly servedLabels: ReadonlyArray<string> // defence in depth: the floor already routes by holder
  readonly shape: TaskShape
  /** `p1` and `auto` both require P1 on the server, proven by a probe (B6); `auto` never selects guest. `guest` is
   *  the L7 reserve and needs a fleet-internal `shape.completeUrl` (critique A5). */
  readonly completion: "auto" | "p1" | "guest"
  readonly secondMs: number // 1000 in production; tests shrink every server-set interval with it
  readonly resyncMs: number // 15 s, the P1 --running-resync period
  readonly pendingTimeoutMs: number // 15 min, agent-stack-k8s: a Pod stuck Pending fails the job
  readonly deleteAfterMs: number // 10 min, agent-stack-k8s TTLSecondsAfterFinished
  readonly deadlineBackstopMs: number // local stop past the floor's deadline, if the floor cannot say cancel
  readonly createAttempts: number // UpdateTask tries while ax is unavailable before pre-start failure
  readonly outboxBackoffMs: readonly [number, number] // uplink shut-door backoff: min, max
  readonly fenceTimeoutMs?: number // B2: how long a superseded attempt may take to reach NotFound (default 120 s)
  readonly resultReadTries?: number // B4: resyncs a Completed Task's result may fail to read (default 5)
  readonly floorUrls?: ReadonlyArray<string> // B18: the only URLs a Lease `endpoint` may move this link to
  readonly initialPollSeconds?: number // until the first Lease reply sets them (defaults 15 and 30, section 3.7)
  readonly initialHeartbeatSeconds?: number
  /** Round 2: a result larger than this is refused `agent/output-too-large` before it is reported (the floor's DO row
   *  limit is 2 MB, MEASURED as SQLITE_TOOBIG at 2.2 MB; default 1 000 000 B). */
  readonly maxOutputBytes?: number
  /** Round 2: server errors one verdict may collect before it is replaced by `infra/verdict-undeliverable`, and that
   *  replacement before it is dead-lettered (journaled `dropped`). Default 8. */
  readonly verdictAttempts?: number
  /** Round 2: single-label hosts a guest Complete URL may name (fleet DNS names without a dot). Default none. */
  readonly internalHosts?: ReadonlyArray<string>
  /** Round 3: consecutive undecodable or server-error Lease replies for one journaled requestKey before the key is
   *  abandoned (its grants are then released by the floor's own expiry and requeued). Default 5. */
  readonly leaseKeyAttempts?: number
  /** Critique D.2 (DELETE-HANG ladder): a Task that stays Terminating after its journaled DeleteTask is asked again every
   *  `terminatingRetryMs` (default 60 s) up to `terminatingRetries` times (default 5), escalated by log (and a Substrate
   *  read, when one is wired) at `terminatingEscalateMs` (default 5 min) and journaled `delete-stuck` at
   *  `terminatingGiveUpMs` (default 15 min). All measured from `deletingAt`, which survives restarts and compaction. */
  readonly terminatingRetryMs?: number
  readonly terminatingEscalateMs?: number
  readonly terminatingGiveUpMs?: number
  readonly terminatingRetries?: number
}

/** Critique D.2: the optional read port the ladder uses to PROVE a stuck Task holds no Substrate worker (DELETE-HANG
 *  step 3). Absent in production until a Substrate read credential is granted; without it no slot is ever released. */
export interface SubstrateRead {
  readonly actor: (task: string, atespace: string) => Effect.Effect<"absent" | "deleting" | "present", unknown>
}

export type Log = (ev: string, fields?: Record<string, unknown>) => void
export interface LinkDeps {
  readonly ax: AxApi; readonly floor: FloorApi; readonly journal: Journal; readonly log: Log; readonly stop: Deferred.Deferred<void>
  /** G-BK4, Buildkite's graceful stop: once done, the link leases nothing more and stops by itself when no Task it
   *  holds is live and no verdict is undelivered, or after drainTimeoutMs; `stop` still stops it at once. */
  readonly drain?: Deferred.Deferred<void>
  readonly drainTimeoutMs?: number
  readonly floorUrl?: string // the URL in use, to tell a real endpoint switch from an echo
  readonly onEndpoint?: (url: string) => void // B18: called once for an allowed switch; main persists it and restarts
  readonly substrate?: SubstrateRead // critique D.2: optional; see SubstrateRead
}

const TERMINAL = new Set(["Completed", "Failed"])
const jitter = (ms: number) => Math.round(ms * (0.8 + 0.4 * Math.random()))
const NOT_FOUND = 5 // gRPC status: DeleteTask of a name that is already gone
const MAX_POLL_SECONDS = 300, MAX_HEARTBEAT_SECONDS = 300
/** Round 3: a server-driven interval (Buildkite: the agent falls back to its defaults). Missing, non-finite or not
 *  positive gives `def`; anything else is clamped to [1, hi]. `Effect.sleep(0)` would otherwise be a tight loop. */
export const boundedSeconds = (v: number | undefined, def: number, hi: number) =>
  v === undefined || !Number.isFinite(v) || v <= 0 ? Math.min(def, hi) : Math.max(1, Math.min(v, hi))

/** Critique A5 and N3: a guest's Complete URL must stay inside the fleet, never a public Workers host.
 *  Round 2: private ranges are matched only on IP literals (after WHATWG normalisation, so `10.evil.example` and
 *  `127.0.0.1.nip.io` are names, not addresses); a name must end in a non-public suffix; a single-label name only when
 *  it is listed. */
export const isFleetInternalUrl = (raw: string | undefined, internalHosts: ReadonlyArray<string> = []): boolean => {
  if (raw === undefined) return false
  let u: URL
  try { u = new URL(raw) } catch { return false }
  let h = u.hostname.toLowerCase()
  if (h.endsWith(".workers.dev") || h.endsWith(".pages.dev")) return false
  if (h.startsWith("[") && h.endsWith("]")) h = h.slice(1, -1)
  if (isIPv4(h)) {
    const [a, b] = h.split(".").map(Number) as [number, number]
    return a === 127 || a === 10 || (a === 192 && b === 168) || (a === 172 && b >= 16 && b <= 31) || (a === 100 && b >= 64 && b <= 127)
  }
  if (isIPv6(h)) return h === "::1" || /^f[cd][0-9a-f]{2}:/.test(h) // loopback, ULA fc00::/7 (the tailnet's fd7a:115c:a1e0::/48)
  if (h === "localhost" || internalHosts.map((x) => x.toLowerCase()).includes(h)) return true
  return /^([a-z0-9-]+\.)+(internal|lan|local|home\.arpa)$/.test(h)
}

export const runLink = (cfg: LinkConfig, deps: LinkDeps) => Effect.gen(function*() {
  const { ax, journal: j, log } = deps
  // Red team loss-and-wip r3-3 (critique pass KEEP-4): every floor reply that is not an error proves the floor serves
  // this link, so an HTTP 5xx that follows one is about the bytes of that call, not the whole floor.
  let floorAnswered = 0
  const answered = <A, E>(e: Effect.Effect<A, E>) => e.pipe(Effect.tap(() => Effect.sync(() => { floorAnswered++ })))
  const floor: FloorApi = { lease: (p) => answered(deps.floor.lease(p)), heartbeat: (p) => answered(deps.floor.heartbeat(p)), complete: (p) => answered(deps.floor.complete(p)) }
  const fatal = yield* Deferred.make<never, FloorError>()
  const fenceTimeoutMs = cfg.fenceTimeoutMs ?? 120_000
  const resultReadTries = cfg.resultReadTries ?? 5
  const maxOutputBytes = cfg.maxOutputBytes ?? 1_000_000
  const verdictAttempts = cfg.verdictAttempts ?? 8
  const defaultPoll = cfg.initialPollSeconds ?? 15, defaultHb = cfg.initialHeartbeatSeconds ?? 30
  let pollSeconds = defaultPoll, hbAsked: number | undefined // round 3: the floor's raw heartbeatSeconds, bounded at use
  let clampLogged = ""
  const leaseKeyAttempts = cfg.leaseKeyAttempts ?? 5
  const termRetryMs = cfg.terminatingRetryMs ?? 60_000
  const termEscalateMs = cfg.terminatingEscalateMs ?? 300_000
  const termGiveUpMs = cfg.terminatingGiveUpMs ?? 900_000
  const termRetries = cfg.terminatingRetries ?? 5
  const escalated = new Set<string>() // critique D.2: ax-delete-escalate is logged once per lease per process
  let leaseKeyFailures = 0
  let axUp = false, resynced = false
  let serverP1: boolean | undefined // the probe's answer; cleared on every ax-up transition (B6)
  let gatewayOk: boolean | undefined // B10
  let gatewayState: string | undefined // critique D.2 item 5: ok, open, missing (with the code); logged on change
  const guestUrlOk = cfg.completion !== "guest" || isFleetInternalUrl(cfg.shape.completeUrl, cfg.internalHosts)
  if (!guestUrlOk) log("guest-url-invalid", { completion: "guest" })
  /** Critique D.2 item 6: `auto` falls back to guest when a Complete URL is declared and fleet-internal. */
  const autoGuestOk = cfg.completion === "auto" && cfg.shape.completeUrl !== undefined && isFleetInternalUrl(cfg.shape.completeUrl, cfg.internalHosts)
  if (cfg.completion === "auto" && cfg.shape.completeUrl !== undefined && !autoGuestOk) log("guest-url-invalid", { completion: "auto" })
  let last = new Map<string, AxObserved>()
  let outboxWaitUntil = 0, outboxBackoff = cfg.outboxBackoffMs[0]
  let outboxNotBefore = 0 // round 3: the floor's own Retry-After on Complete; Lease does not cut it short (B15 does not)
  const dispatching = new Map<string, Grant>() // round 2: keyed by leaseId, valued by the grant generation it runs
  const admitted = new Set<string>() // B11: grants that passed the slot gate in this process
  const abandoned = new Map<string, "cancel" | "lost">() // B3: set by the Heartbeat reply, read by dispatch
  const absent = new Map<string, number>() // B1: consecutive resyncs a held Task answered NotFound
  const resultFailures = new Map<string, number>() // B4
  const verdictFailures = new Map<string, number>() // round 2: server errors per verdict (a restart grants a fresh budget)
  const verdictNotBefore = new Map<string, number>() // round 2: per-verdict backoff after a server error
  const verdictAnsweredMark = new Map<string, number>() // KEEP-4: floorAnswered when this verdict last failed with an HTTP 5xx
  // Critique pass 2026-09-24 (red team durability-r2-8): a server error is charged to a verdict only when the floor
  // answered a Lease or Heartbeat between two tries of it; a floor-wide outage charges nothing, so a success is never
  // replaced by infra/verdict-undeliverable because the whole floor was down. Since the 2026-09-24 integrate this
  // stands beside KEEP-4 (the same finding, fixed on two branches): a 5xx is charged only when both say the floor served.
  const verdictTriedAt = new Map<string, number>()
  let floorOkAt = 0
  const markFloorOk = () => Effect.sync(() => { floorOkAt = Date.now() })
  const pendingResume = new Set<string>() // B13: journaled, never created; resumed only once the floor renews them
  /** Round 4 (Buildkite reserve-with-expiry): the local time of the last call the floor answered by renewing this
   *  grant generation (the Lease that granted it, then every Heartbeat listing it in `renewed`). The send time is taken,
   *  so it is never later than the floor's own renewTime. Keyed by the grant object: a regrant starts afresh. */
  const renewedAt = new WeakMap<Grant, number>()
  /** Round 4: a create may start only while the floor still holds the lease: the last renewal is less than 3/4 of a
   *  lease old. A grant never renewed in this process (journaled by a previous one) is not live until a Heartbeat says so. */
  const leaseLive = (g: Grant) => {
    const at = renewedAt.get(g)
    if (at === undefined) return false
    const ms = g.lease.leaseDurationSeconds * cfg.secondMs
    return Date.now() < at + ms - ms / 4
  }
  const deadlinePassed = (g: Grant) => g.deadline !== undefined && Date.now() >= g.deadline
  /** Red team double-run-r1-1 (Kubernetes Lease, Temporal heartbeat timeout: the holder stops before the server may
   *  reassign). Past lease + grace the floor may requeue attempt n+1 to a holder whose own executor cannot see this
   *  one's Task, so its supersedes fence finds nothing and both attempts run. The floor sends that bound as the grant's
   *  reassignSeconds (lease + grace + the rule 7b pin); the link deletes a still-running Task it has not seen renewed
   *  for reassignSeconds less half a lease (a floor that sends no bound promises no grace: one lease), measured from the
   *  send time of the last renewing call, which is never later than the floor's own renewTime. */
  const renewedLocal = (id: string, g: Grant, at: number) => {
    renewedAt.set(g, Math.max(renewedAt.get(g) ?? 0, at))
    const r = j.recs.get(id)
    if (r?.grant !== g) return
    // journaled at most every half lease, so a restart measures from a recent renewal without one fsync per beat
    if ((r.renewedAt ?? 0) + (g.lease.leaseDurationSeconds * cfg.secondMs) / 2 <= at) j.append({ ev: "renewed", leaseId: id }, at)
  }
  const selfFenceAt = (r: LeaseRec) => {
    const g = r.grant
    const base = Math.max(renewedAt.get(g) ?? 0, r.renewedAt ?? 0) || (r.createdAt ?? r.at)
    const lease = g.lease.leaseDurationSeconds * cfg.secondMs
    const bound = g.reassignSeconds !== undefined && Number.isFinite(g.reassignSeconds) ? g.reassignSeconds * cfg.secondMs : lease
    return base + Math.max(lease / 2, bound - lease / 2)
  }
  /** A Task this link may have created, runs (no verdict read), and is still held: the ones a fence must stop. */
  const fenceable = (r: LeaseRec) => r.released === undefined && r.report === undefined && !r.reported && r.dropped === undefined
    && !r.notMine && r.deleting === undefined && !r.deleted && Journal.maybeCreated(r)
  /** Only a Task that still RUNS is fenced. A finished one (P1: suspended, holding no worker) has its verdict read
   *  and journaled by salvage and stays held with it in the outbox (rule 4b may still accept it); a Task ax cannot
   *  answer for is tried again at the next resync. */
  const fenceSelf = (id: string, why: string, fields: Record<string, unknown> = {}) => Effect.gen(function*() {
    const r = j.recs.get(id)
    if (!r || !fenceable(r)) return
    if ((yield* salvage(id)) !== "live") return
    j.append({ ev: "released", leaseId: id, why })
    abandoned.set(id, "lost")
    pendingResume.delete(id)
    log(why, { leaseId: id, ...fields })
    yield* del(id, why)
  })
  const selfFence = Effect.gen(function*() {
    const now = Date.now()
    for (const [id, r] of [...j.recs]) if (fenceable(r) && now >= selfFenceAt(r))
      yield* fenceSelf(id, "lease-expired", { lastRenewal: Math.max(renewedAt.get(r.grant) ?? 0, r.renewedAt ?? 0) || null })
  })
  let wake = yield* Deferred.make<void>() // B17: a verdict that frees a slot leases at once
  let hbWake = yield* Deferred.make<void>() // final pass (R3-1): a Lease reply re-times a heartbeat sleep already begun
  /** Red team double-run-r1-2: a 409 means another session holds this identity and may already run attempt n+1 of
   *  every lease held here; this process can never hear `lost` again. Every running Task is fenced before the exit. */
  const failFatal = (e: FloorError): Effect.Effect<void> => Effect.gen(function*() {
    if (e.kind === "session-conflict") for (const [id, r] of [...j.recs]) if (fenceable(r)) yield* fenceSelf(id, "session-lost")
    yield* Deferred.fail(fatal, e)
  })

  /** The mode the link may create in, or undefined while it is unproven (capacity 0). Critique D.2 item 6: `auto`
   *  is p1 when the probe proved P1, guest when the probe proved its absence and a fleet-internal Complete URL is
   *  declared, and undefined while the probe has not answered (an outage never flips the mode). */
  const mode = (): "p1" | "guest" | undefined => {
    if (cfg.completion === "guest") return guestUrlOk ? "guest" : undefined
    if (serverP1 === true) return "p1"
    if (serverP1 === false && autoGuestOk) return "guest"
    return undefined
  }
  const canCreate = () => axUp && resynced && gatewayOk === true && mode() !== undefined

  // ---------------------------------------------------------------- verdicts (write-ahead, then the outbox drains)
  /** `salvage` (round 2): the verdict was read from a Task whose lease is already released (lost, superseded). It is
   *  still owed to the floor, which accepts it by rule 4b or answers stale-attempt (then it is dropped). */
  /** Round 4: `g`, when given, is the grant generation the verdict is about; a record that holds another generation
   *  by now (a regrant of the same leaseId) is not given it. */
  const report = (id: string, result: Result, output?: unknown, usage?: Usage, salvage = false, g?: Grant) => Effect.gen(function*() {
    const r = j.recs.get(id)
    if (g !== undefined && r?.grant !== g) return log("stale-generation-verdict", { leaseId: id, result })
    if (!r || r.report || (r.released !== undefined && !salvage)) return
    j.append({ ev: "report", leaseId: id, attempt: r.grant.attempt, result, ...(output !== undefined ? { output } : {}), ...(usage !== undefined ? { usage } : {}) })
    log("verdict", { leaseId: id, result, ...(result === "failure" ? { reason: (output as FailureOutput | undefined)?.reason } : {}), ...(salvage ? { salvaged: r.released } : {}) })
    yield* Deferred.succeed(wake, undefined)
  })
  const fail = (id: string, o: FailureOutput) => report(id, "failure", o)
  const failG = (g: Grant, o: FailureOutput) => report(g.leaseId, "failure", o, undefined, false, g) // round 4

  // Round 1: single-flight. The main loop, the resync fiber and a dispatch waiting on a superseded verdict all drain;
  // two concurrent drains read the same outbox before either journals `reported` and send every verdict twice.
  const outboxLock = Semaphore.makeUnsafe(1)
  const drainOutbox = outboxLock.withPermit(Effect.gen(function*() {
    if (Date.now() < outboxWaitUntil || Date.now() < outboxNotBefore) return
    for (const p of j.outbox()) {
      if ((verdictNotBefore.get(p.leaseId) ?? 0) > Date.now()) continue
      // Round 4: the generation of attempt n+1 this link held when the verdict was SENT. A regrant of n+1 taken while
      // the reply is in flight is later than anything this Complete can have withdrawn.
      const succId = `${p.leaseId.replace(/-a\d+$/, "")}-a${p.attempt + 1}`
      const succAtSend = j.recs.get(succId)?.grant
      const r = yield* floor.complete({ leaseId: p.leaseId, attempt: p.attempt, result: p.result, ...(p.output !== undefined ? { output: p.output } : {}), ...(p.usage !== undefined ? { usage: p.usage } : {}) }).pipe(Effect.result)
      if (r._tag === "Success") {
        const withdrew = r.success.withdrew
        // Round 3: a withdrawal names a GENERATION, not a leaseId. The floor may requeue the withdrawn attempt under the
        // same leaseId (a retryable verdict of n), and that later grant is live. The generation is the floor's
        // `withdrewTransitions` when it sends one, else the one this link holds; a generation this link never received
        // (n+1 was still queued) matches no later grant.
        const w = withdrew !== undefined ? j.recs.get(withdrew) : undefined
        const withdrewGen: Gen | undefined = withdrew === undefined ? undefined
          : r.success.withdrewTransitions !== undefined ? { leaseTransitions: r.success.withdrewTransitions }
          : succAtSend !== undefined && withdrew === succId ? genOf(succAtSend)
          : w !== undefined ? genOf(w.grant) : undefined
        j.append({ ev: "reported", leaseId: p.leaseId, duplicate: r.success.duplicate, ...(withdrew !== undefined ? { withdrew } : {}), ...(withdrewGen !== undefined ? { withdrewGen } : {}) })
        log("complete", { leaseId: p.leaseId, result: p.result, duplicate: r.success.duplicate, ...(withdrew !== undefined ? { withdrew } : {}) })
        if (withdrew !== undefined && withdrewGen === undefined) log("withdrawn-unheld", { leaseId: withdrew, by: p.leaseId })
        if (w !== undefined && withdrewGen !== undefined && sameGen(genOf(w.grant), withdrewGen) && w.released === undefined && !Journal.maybeCreated(w)) {
          j.append({ ev: "released", leaseId: withdrew!, why: "withdrawn" }) // round 2: released at once, so a regrant
          log("withdrawn", { leaseId: withdrew, by: p.leaseId }) // of it is not taken for a duplicate
        }
        outboxBackoff = cfg.outboxBackoffMs[0]
        verdictFailures.delete(p.leaseId); verdictNotBefore.delete(p.leaseId); verdictAnsweredMark.delete(p.leaseId); verdictTriedAt.delete(p.leaseId)
      } else if (r.failure._tag === "CompleteRefused") { // done/keep/drop: the floor refused these bytes for good
        j.append({ ev: "dropped", leaseId: p.leaseId, code: r.failure.code })
        log("complete-dropped", { leaseId: p.leaseId, code: r.failure.code })
      } else if (r.failure.kind === "server-error" && r.failure.status !== undefined && (verdictAnsweredMark.get(p.leaseId) ?? -1) >= floorAnswered) {
        // KEEP-4: an HTTP 5xx with no floor reply since this verdict last failed is not evidence against these bytes
        // (a floor-wide 500 answers every call alike): the verdict waits with its own backoff and is not charged.
        const wait = jitter(cfg.outboxBackoffMs[1])
        verdictAnsweredMark.set(p.leaseId, floorAnswered); verdictNotBefore.set(p.leaseId, Date.now() + wait)
        log("outbox-keep", { leaseId: p.leaseId, kind: r.failure.kind, charged: false, waitMs: wait })
        continue
      } else if (r.failure.kind === "server-error") {
        if (r.failure.status !== undefined) verdictAnsweredMark.set(p.leaseId, floorAnswered)
        // Round 2: the floor answered and refused THESE bytes (a 500, an RPC Defect such as SQLITE_TOOBIG). Counted per
        // verdict; the rest of the outbox still goes out. At the ceiling the verdict is replaced by a small final
        // failure the floor can store; if that fails as well it is dead-lettered, so one verdict never gates Lease.
        const prevTry = verdictTriedAt.get(p.leaseId)
        verdictTriedAt.set(p.leaseId, Date.now())
        const charged = prevTry !== undefined && floorOkAt > prevTry // durability-r2-8
        const n = (verdictFailures.get(p.leaseId) ?? 0) + (charged ? 1 : 0)
        verdictFailures.set(p.leaseId, n)
        if (n < verdictAttempts) {
          const wait = jitter(Math.min(cfg.outboxBackoffMs[0] * 2 ** Math.max(0, n - 1), cfg.outboxBackoffMs[1]))
          verdictNotBefore.set(p.leaseId, Date.now() + wait)
          log("outbox-keep", { leaseId: p.leaseId, kind: r.failure.kind, try: n, charged, waitMs: wait })
          continue
        }
        verdictFailures.delete(p.leaseId); verdictNotBefore.delete(p.leaseId); verdictTriedAt.delete(p.leaseId)
        const rec = j.recs.get(p.leaseId)
        if (rec !== undefined && !p.replace) {
          const digest = createHash("sha256").update(JSON.stringify(p.output ?? null)).digest("hex")
          j.append({ ev: "report", leaseId: p.leaseId, attempt: p.attempt, result: "failure", replace: true,
            output: { reason: "infra/verdict-undeliverable", message: `${p.result} verdict (output sha256 ${digest}) refused ${n} times: ${r.failure.message.slice(0, 200)}` } })
          log("verdict-replaced", { leaseId: p.leaseId, result: p.result, tries: n, outputSha256: digest })
        } else {
          j.append({ ev: "dropped", leaseId: p.leaseId, code: "undeliverable" })
          log("verdict-dead-letter", { leaseId: p.leaseId, tries: n, message: r.failure.message.slice(0, 200) })
        }
      } else {
        if (r.failure.fatal) return yield* failFatal(r.failure)
        outboxWaitUntil = Date.now() + Math.min(r.failure.retryAfterMs ?? jitter(outboxBackoff), MAX_POLL_SECONDS * cfg.secondMs)
        if (r.failure.retryAfterMs !== undefined) outboxNotBefore = outboxWaitUntil
        outboxBackoff = Math.min(outboxBackoff * 2, cfg.outboxBackoffMs[1])
        log("outbox-keep", { leaseId: p.leaseId, kind: r.failure.kind, waitMs: outboxWaitUntil - Date.now() })
        return // keep: oldest first, stop at the first transient failure
      }
    }
  }))

  // ---------------------------------------------------------------- ax calls
  // Round 3 (token scope): a record that is only `creating` names a Task the link MAY have written. The floor chose
  // that name, so before anything reads or deletes it the Task must carry this link's write: the spec digest the
  // link built for this grant, or this lease id and this holder in its env. Anything else is someone else's Task.
  const envMarks = (id: string, t: AxObserved) => {
    const env = new Map((t.spec.env ?? []).map((e) => [e.name ?? "", e.value ?? ""]))
    return env.get("AX_CONWIP_LEASE_ID") === id && env.get("AX_CONWIP_HOLDER") === cfg.holder
  }
  const owns = (id: string, r: LeaseRec, t: AxObserved) =>
    r.created !== undefined || (r.creatingDigest !== undefined && specDigest(t.spec) === r.creatingDigest) || envMarks(id, t)
  /** Journal that the Task under this name is not the link's: nothing reads, deletes or reports it any more. A cancel
   *  already asked for is answered `cancelled`, since nothing of this lease runs in ax. */
  const markNotMine = (id: string) => Effect.gen(function*() {
    const r = j.recs.get(id)
    if (!r || r.notMine) return
    j.append({ ev: "not-mine", leaseId: id })
    log("not-mine", { leaseId: id })
    if (!r.report && r.released === undefined && (abandoned.get(id) === "cancel" || r.deleting === "cancel")) yield* report(id, "cancelled")
  })
  /** GetTask a `creating`-only record's name: owned, absent, foreign (journaled not-mine) or unknown (ax did not answer). */
  const ownership = (id: string, r: LeaseRec) => Effect.gen(function*() {
    const got = yield* ax.getTask(id).pipe(Effect.result)
    if (got._tag === "Failure") return "unknown" as const
    if (got.success === undefined) return "absent" as const
    if (owns(id, r, got.success)) return "owned" as const
    yield* markNotMine(id)
    return "foreign" as const
  })

  // Round 3: the intent is journaled BEFORE DeleteTask (`deleting`), so a DeleteTask that lands and whose reply is lost
  // (DEADLINE_EXCEEDED) still reads as a delete on the next resync (a cancel is reported `cancelled`, not task-lost),
  // and one that did not land is sent again by reconcile. NotFound means already gone.
  const del = (id: string, why: string): Effect.Effect<boolean> => Effect.gen(function*() {
    const rec = j.recs.get(id)
    if (rec?.notMine) return true
    if (rec !== undefined && rec.created === undefined && rec.creating) {
      const o = yield* ownership(id, rec)
      if (o === "unknown") { log("delete-deferred", { task: id, why, until: "ownership" }); return false }
      if (o === "foreign") return true
    }
    if (rec !== undefined && rec.deleting === undefined) j.append({ ev: "deleting", leaseId: id, why })
    return yield* ax.deleteTask(id).pipe(
      Effect.tap(() => Effect.sync(() => log("delete", { task: id, why }))),
      Effect.as(true),
      Effect.catch((e: AxError) => Effect.sync(() => {
        if (e.code === NOT_FOUND) { log("delete", { task: id, why, absent: true }); return true }
        log("delete-deferred", { task: id, why, code: e.code }); return false
      })))
  })

  /** B2: an old attempt is gone only when GetTask answers NotFound; until then attempt n+1 is not created.
   *  Critique D.2 (P2): a Task that stays Terminating is asked again every terminatingRetryMs, and a fence that times
   *  out on a Task ax still shows is `stuck` (infra/delete-stuck, final), not an ax outage: a retryable reason sent the
   *  job straight back to this holder, which fenced the same stuck name again until the attempts were spent. */
  const fence = (old: string) => Effect.gen(function*() {
    const until = Date.now() + fenceTimeoutMs
    let askedAt: number | undefined
    let seen: "terminating" | "other" = "other" // only a Task last SEEN Terminating is a stuck delete; a refused DeleteTask is an ax outage
    for (;;) {
      if (j.recs.get(old)?.notMine) return "gone" as const // round 3: not this link's Task; nothing of attempt n runs under it
      const r = yield* ax.getTask(old).pipe(Effect.result)
      if (r._tag === "Success" && r.success === undefined) {
        if (j.recs.has(old) && !j.recs.get(old)!.deleted) j.append({ ev: "deleted", leaseId: old })
        return "gone" as const
      }
      seen = r._tag === "Success" && r.success!.phase === "Terminating" ? "terminating" : "other"
      if (r._tag === "Success") {
        const terminating = r.success!.phase === "Terminating"
        if (askedAt === undefined || !terminating) { if (yield* del(old, "superseded")) askedAt ??= Date.now() }
        else if (Date.now() - askedAt >= termRetryMs) {
          askedAt = Date.now()
          const again = yield* ax.deleteTask(old).pipe(Effect.result)
          log("delete-retry", { task: old, where: "fence", ...(again._tag === "Failure" ? { code: again.failure.code } : {}) })
        }
      }
      if (Date.now() >= until) return seen === "terminating" ? "stuck" as const : "unanswered" as const
      yield* Effect.sleep(Math.min(cfg.resyncMs, 2 * cfg.secondMs))
    }
  })
  const fenceFailure = (old: string, f: "stuck" | "unanswered"): FailureOutput => f === "stuck"
    ? { reason: "infra/delete-stuck", message: `superseded attempt ${old} still Terminating in ax after the fence timeout` } // final
    : { reason: "pre-start/ax-unavailable", message: `superseded attempt ${old} not confirmed deleted` }

  /** B11: never more live Tasks than maxInFlight. Busy = live Tasks in the atespace (anyone's) U admitted leases
   *  not known finished. Synchronous, so two dispatch fibers cannot both take the last slot. */
  /** Critique D.2: a Task the ladder gave up on (delete-stuck) whose worker a Substrate read proved gone. Only such a
   *  name stops counting against maxInFlight; without the read port it counts until an operator clears it. */
  const provenFree = (name: string) => { const r = j.recs.get(name); return r?.deleteStuck === true && r.freeProven === true }
  const busy = () => {
    // HF link-ladder (VERIFY LL-4 M1 root cause): a finished admitted lease leaves `admitted`, but its name is not
    // removed from the set: while ax still lists its Task live (Running, or stuck Terminating) it holds a worker, and
    // only the provably-free exclusion above may stop it counting. Before, `b.delete(id)` dropped it for one call.
    const b = new Set<string>()
    for (const [name, t] of last) if (!TERMINAL.has(t.phase) && !provenFree(name)) b.add(name)
    for (const id of admitted) {
      const r = j.recs.get(id), t = last.get(id)
      if (!r || r.report || r.released !== undefined || r.dropped !== undefined || r.deleted || (t && TERMINAL.has(t.phase))) { admitted.delete(id); continue } // HF link-ladder: a live Task in the snapshot still counts
      b.add(id)
    }
    return b
  }
  const admit = (id: string) => Effect.sync(() => {
    if (!canCreate()) return false
    const b = busy()
    if (b.has(id) || b.size < cfg.maxInFlight) { admitted.add(id); return true }
    return false
  })

  /** A grant this link will not create any more (B3): a cancel is reported once any Task that may exist is gone. */
  const abandon = (id: string, why: "cancel" | "lost", where: string) => Effect.gen(function*() {
    log(where, { leaseId: id, why })
    const rec = j.recs.get(id)
    if (rec && Journal.maybeCreated(rec)) return yield* del(id, why) // round 1: reconcile reports cancelled on NotFound
    if (why === "cancel") yield* report(id, "cancelled")
  })

  let guestTokenWarned = false
  const createOnly = (g: Grant) => Effect.gen(function*() {
    const id = g.leaseId
    let waited = false
    let unconfirmed = false
    for (;;) { // round 1: the capacity gate is re-checked before every UpdateTask; a closed gate goes back to waiting
      // Round 4: and the lease must still be live (renewed within the lease) before the slot is taken
      while (!leaseLive(g) || !(yield* admit(id))) { // B11: journaled and heartbeated while it waits
        if (abandoned.has(id) || deadlinePassed(g)) break
        if (!leaseLive(g)) { if (!unconfirmed) { log("lease-unconfirmed", { leaseId: id }); unconfirmed = true } }
        else if (!waited) { log("waiting-for-slot", { leaseId: id }); waited = true }
        yield* Effect.sleep(cfg.resyncMs)
      }
      const early = abandoned.get(id)
      if (early !== undefined) return yield* abandon(id, early, "abandoned-before-create")
      const now = j.recs.get(id) // round 2: withdrawn, or replaced by a newer grant of the same leaseId: never create
      if (now?.grant !== g || now.released !== undefined) return log("grant-superseded-before-create", { leaseId: id })
      if (deadlinePassed(g)) return yield* failG(g, { reason: "deadline-exceeded", message: "the grant's deadline passed before its Task was created" }) // round 4
      const m = mode()
      const built = axTaskFromGrant(g, { ...cfg.shape, holder: cfg.holder, ...(m === "guest" ? {} : { completeUrl: undefined }) })
      if (built._tag === "refused") {
        if (built.reason === "pre-start/lease-token-missing" && !guestTokenWarned) {
          guestTokenWarned = true
          log("guest-token-missing", { leaseId: id, hint: "floor and link disagree: the link completes as guest, the floor mints no lease token for this holder" })
        }
        return yield* failG(g, { reason: built.reason, message: built.message })
      }
      const digest = specDigest(built.task.spec)
      for (let i = 1; ; i++) {
        const why = abandoned.get(id) // B3: checked before every UpdateTask
        if (why !== undefined) return yield* abandon(id, why, "abandoned-before-create")
        const cur = j.recs.get(id)
        if (cur?.grant !== g || cur.released !== undefined) return log("grant-superseded-before-create", { leaseId: id })
        if (!canCreate() || mode() !== m) { log("gate-closed-before-create", { leaseId: id, try: i }); break } // round 1
        if (deadlinePassed(g)) return yield* failG(g, { reason: "deadline-exceeded", message: "the grant's deadline passed before its Task was created" })
        if (!leaseLive(g)) { log("lease-unconfirmed-before-create", { leaseId: id, try: i }); break } // round 4: back to waiting
        if (!j.recs.get(id)?.creating) j.append({ ev: "creating", leaseId: id, digest }) // round 1: write-ahead; round 3: with the digest
        const r = yield* Effect.gen(function*() {
          const found = yield* ax.getTask(id)
          if (found === undefined) { yield* ax.createTask(built.task); return "created" as const }
          if (specDigest(found.spec) === digest) return "adopted" as const
          return envMarks(id, found) ? "conflict" as const : "foreign" as const
        }).pipe(Effect.result)
        if (r._tag === "Success") {
          // L4: never overwrite a Task this link did not write. Round 3: a Task without this link's marks is journaled
          // not-mine first, so no cleanup path (janitor, lost, cancel, salvage) ever reads or deletes it.
          if (r.success === "foreign") yield* markNotMine(id)
          if (r.success === "conflict" || r.success === "foreign")
            return yield* failG(g, { reason: "pre-start/name-conflict", message: "a Task with this name and another spec exists" })
          j.append({ ev: "created", leaseId: id, digest })
          log(r.success, { leaseId: id, attempt: g.attempt })
          const after = abandoned.get(id) // B3: and again once UpdateTask returned
          if (after !== undefined) { yield* del(id, after); return }
          const back = yield* ax.getTask(id).pipe(Effect.result) // B12: FIELD-MAP 5a read-back
          if (back._tag === "Success" && back.success !== undefined && specDigest(back.success.spec) !== digest) {
            yield* del(id, "pre-start")
            return yield* failG(g, { reason: "pre-start/readback-mismatch", message: "ax stored another spec than the link wrote" })
          }
          return
        }
        const e = r.failure
        if (e.resourceExhausted) return yield* failG(g, { reason: "pre-start/resource-exhausted", message: e.message }) // B5
        if (!e.unavailable) return yield* failG(g, { reason: "pre-start/invalid-spec", message: e.message })
        if (i >= cfg.createAttempts) {
          // Critique pass 2026-09-24 (red team double-run-r3-1): an UpdateTask whose reply was lost may have landed. A
          // retryable pre-start verdict lets the floor hand attempt n+1 to another holder at once, so it is sent only
          // once GetTask answers NotFound; otherwise the grant goes back to waiting, and the next try adopts a landed Task.
          const seen = yield* ax.getTask(id).pipe(Effect.result)
          if (seen._tag === "Success" && seen.success === undefined) return yield* failG(g, { reason: "pre-start/ax-unavailable", message: e.message })
          log("create-unconfirmed", { leaseId: id, try: i, code: e.code })
          yield* Effect.sleep(cfg.resyncMs)
          break
        }
        yield* Effect.sleep(jitter(2 ** i * 100))
      }
    }
  })

  /** Round 1: an unjournaled name may be fenced only if it is `<same job>-a<k>` with k < this attempt and the Task's own
   *  env says this lease id and this holder (AX_CONWIP_HOLDER, written by this link at create). */
  const ownEarlierAttempt = (old: string, g: Grant, t: AxObserved) => {
    const base = g.leaseId.replace(/-a\d+$/, ""), m = /^(.*)-a(\d+)$/.exec(old)
    if (m === null || m[1] !== base || Number(m[2]) >= g.attempt) return false
    return envMarks(old, t)
  }

  const dispatch = (g: Grant) => Effect.gen(function*() {
    if (j.recs.get(g.leaseId)?.grant === g) dispatching.set(g.leaseId, g) // round 2: only the current generation
    const bad = validRunsOn(g.job, cfg.servedLabels) // B7
    if (bad) return yield* failG(g, bad)
    // Final pass (VERIFY-LINK V1): the fence set is `supersedes` plus every earlier attempt of the same job this link
    // journaled, that may exist in ax and is not confirmed deleted. A floor that omits `supersedes` (or a Heartbeat
    // whose `lost` arrives after this grant) no longer lets attempt n+1 start beside a running attempt n.
    const olds = [...new Set([...(g.supersedes ?? []), ...[...j.recs.values()]
      .filter((r) => r.grant.leaseId !== g.leaseId && r.grant.job.metadata.name === g.job.metadata.name && r.grant.attempt < g.attempt
        && Journal.maybeCreated(r) && r.deleted !== true && !r.notMine)
      .map((r) => r.grant.leaseId)])]
    if (olds.length > (g.supersedes ?? []).length) log("fence-set-extended", { leaseId: g.leaseId, supersedes: g.supersedes ?? [], fence: olds })
    // Round 2: an earlier attempt that may exist and has no verdict yet is READ before anything fences it. A Task that
    // finished while its lease expired carries a result the floor can still accept (rule 4b); deleting it first loses
    // the success and runs the job again.
    for (const o of olds) {
      const until = Date.now() + fenceTimeoutMs
      for (;;) {
        const s = yield* salvage(o)
        if (s !== "unknown") break
        const why = abandoned.get(g.leaseId)
        if (why !== undefined) return yield* abandon(g.leaseId, why, "abandoned-before-create")
        if (Date.now() >= until)
          return yield* failG(g, { reason: "pre-start/ax-unavailable", message: `superseded attempt ${o} could not be read before its fence` })
        yield* Effect.sleep(Math.min(cfg.resyncMs, 2 * cfg.secondMs))
      }
    }
    // Round 1 (B15 at dispatch): an earlier attempt whose verdict is still in the outbox is delivered BEFORE it is
    // fenced. The floor accepts it (rule 4b: n+1 is queued, or leased to this holder and not created) and withdraws
    // this grant; deleting the finished Task first would throw its result away and rerun the job.
    const undelivered = () => olds.filter((o) => { const r = j.recs.get(o); return r?.report !== undefined && !r.reported && r.dropped === undefined })
    if (undelivered().length > 0) {
      log("supersede-waits-for-verdict", { leaseId: g.leaseId, old: undelivered() })
      const until = Date.now() + fenceTimeoutMs
      for (;;) {
        if (undelivered().length === 0) break // delivered (maybe by another fiber): decided below
        const mine = j.recs.get(g.leaseId)
        if (mine?.grant !== g || mine.released !== undefined) return log("grant-superseded-before-create", { leaseId: g.leaseId })
        const why = abandoned.get(g.leaseId)
        if (why !== undefined) return yield* abandon(g.leaseId, why, "abandoned-before-create")
        yield* drainOutbox
        if (undelivered().length === 0) break
        if (Date.now() >= until)
          return yield* failG(g, { reason: "pre-start/superseded-verdict-pending", message: `the verdict of ${undelivered().join(",")} is not delivered yet` })
        yield* Effect.sleep(Math.min(cfg.resyncMs, 2 * cfg.secondMs))
      }
    }
    // Round 2: withdrawn only when the floor SAID so (Complete.withdrew names this grant). A duplicate answer (rule 4c)
    // or a delivered retryable failure withdrew nothing: this grant is the retry, so fence the old attempt and create.
    // Round 3: and only for the generation it withdrew (see drainOutbox).
    const by = olds.find((o) => { const x = j.recs.get(o); return x?.withdrew === g.leaseId && x.withdrewGen !== undefined && sameGen(genOf(g), x.withdrewGen) })
    if (by !== undefined) {
      // Round 4: only this generation's record; a regrant taken meanwhile is the floor's newer word and stays live
      const cur = j.recs.get(g.leaseId)
      if (cur?.grant !== g) return log("grant-superseded-before-create", { leaseId: g.leaseId })
      if (cur.released === undefined) j.append({ ev: "released", leaseId: g.leaseId, why: "withdrawn" })
      return log("withdrawn", { leaseId: g.leaseId, by })
    }
    const self = j.recs.get(g.leaseId)
    if (self?.grant !== g || self.released !== undefined) return log("grant-superseded-before-create", { leaseId: g.leaseId })
    for (const old of olds) { // L3 and B2: the old attempt is gone before attempt n+1 is created
      const rec = j.recs.get(old)
      if (rec && rec.released === undefined) j.append({ ev: "released", leaseId: old, why: "superseded" })
      if (rec && Journal.maybeCreated(rec)) {
        const f = yield* fence(old)
        if (f !== "gone") {
          log("fence-failed", { leaseId: g.leaseId, old, why: f })
          return yield* failG(g, fenceFailure(old, f))
        }
        continue
      }
      // Round 1 (token scope): a name this link has no journal record for is never deleted on the floor's word alone.
      // Absent is fine. Present is fenced only when it is an earlier attempt of THIS job and the Task itself carries
      // this link's marks (the journal-lost case, F8); anything else is someone else's Task and this grant is refused.
      const r = yield* ax.getTask(old).pipe(Effect.result)
      if (r._tag === "Failure")
        return yield* failG(g, { reason: "pre-start/ax-unavailable", message: `superseded attempt ${old} not confirmed absent` })
      if (r.success !== undefined && ownEarlierAttempt(old, g, r.success)) {
        log("supersedes-unjournaled-own", { leaseId: g.leaseId, old })
        const f = yield* fence(old)
        if (f !== "gone") {
          log("fence-failed", { leaseId: g.leaseId, old, why: f })
          return yield* failG(g, fenceFailure(old, f))
        }
        continue
      }
      if (r.success !== undefined) {
        log("supersedes-foreign", { leaseId: g.leaseId, old })
        return yield* failG(g, { reason: "pre-start/supersedes-foreign", message: `supersedes names ${old}, a Task this link did not create` })
      }
    }
    yield* createOnly(g)
  }).pipe(
    Effect.ensuring(Effect.sync(() => { if (dispatching.get(g.leaseId) === g) dispatching.delete(g.leaseId) })),
    // L9. Round 4: a defect is not swallowed while the lease is held. The grant is failed back (infra/link-defect,
    // retryable: the floor requeues it and the next attempt fences anything this one may have created); if even that
    // cannot be journaled, the process dies (exit 1) and a restart resumes from the journal (B13).
    Effect.catchCause((c) => Cause.hasInterruptsOnly(c) ? Effect.interrupt : Effect.gen(function*() {
      log("job-fiber-died", { leaseId: g.leaseId, cause: Cause.pretty(c) })
      const rec = j.recs.get(g.leaseId)
      if (rec?.grant !== g || rec.report !== undefined || rec.released !== undefined || rec.notMine) return
      yield* failG(g, { reason: "infra/link-defect", message: Cause.pretty(c).slice(0, 300) })
    }).pipe(Effect.catchCause((c2) => Cause.hasInterruptsOnly(c2) ? Effect.interrupt
      : Effect.sync(() => log("link-defect-fatal", { leaseId: g.leaseId, cause: Cause.pretty(c2).slice(0, 300) })).pipe(
        Effect.andThen(Deferred.die(fatal, Cause.squash(c2))), Effect.asVoid)))))

  // ---------------------------------------------------------------- resync: the executor's list is the ledger
  const outcomeOf = (id: string, t: AxObserved, salvage = false) => Effect.gen(function*() {
    const fail = (id: string, o: FailureOutput) => report(id, "failure", o, undefined, salvage)
    if (t.phase === "Completed") {
      const res = yield* ax.getTaskResult(id).pipe(Effect.result)
      // Round 4: UNIMPLEMENTED is the server losing P1 (a rollout), not this Task's result: close the gate at once and
      // keep the Task, uncharged, to read it once P1 is back. Guest mode does not read results through ax.
      if (res._tag === "Success" && res.success === "unimplemented" && cfg.completion !== "guest") {
        setServerP1(false)
        return log("result-read-deferred", { leaseId: id, why: "server without P1" })
      }
      const unreadable = res._tag === "Failure" ? `GetTaskResult: ${res.failure.message}`
        : res.success === undefined ? "no result stored"
        : res.success === "unimplemented" ? "server without P1"
        : res.success.digestOk === false ? "sha256 mismatch" : undefined
      if (unreadable !== undefined) { // B4: a transient read is retried at the next resync, bounded
        const n = (resultFailures.get(id) ?? 0) + 1
        resultFailures.set(id, n)
        const permanent = res._tag === "Failure" && !res.failure.unavailable
        if (!permanent && n < resultReadTries) return log("result-read-retry", { leaseId: id, try: n, why: unreadable })
        return yield* fail(id, { reason: "infra/result-unreadable", phase: t.phase, message: unreadable })
      }
      const ok = (res as { success: { content: string; sha256: string } }).success
      const bytes = Buffer.byteLength(ok.content, "utf8")
      if (bytes > maxOutputBytes) // round 2: refused here, typed, before the floor answers SQLITE_TOOBIG for ever
        return yield* fail(id, { reason: "agent/output-too-large", phase: t.phase,
          message: `result ${bytes} B > ${maxOutputBytes} B (sha256 ${ok.sha256 || createHash("sha256").update(ok.content).digest("hex")})` })
      let output: unknown
      try { output = JSON.parse(ok.content) } catch { return yield* fail(id, { reason: "agent/result-not-json", phase: t.phase }) }
      const u = t.usage
      return yield* report(id, "success", output, u ? { prompt_tokens: u.promptTokens ?? 0, completion_tokens: u.completionTokens ?? 0, tool_calls: u.toolCalls ?? 0 } : undefined, salvage)
    }
    const ready = t.conditions.find((c) => c.type === "Ready")
    const why = `${ready?.reason ?? ""} ${ready?.message ?? ""}`
    const code = /ExitCode=(\d+)/.exec(why)
    const reason = /ResourceExhausted/i.test(why) ? "pre-start/resource-exhausted" // B5: a capacity race, retryable (#367)
      : /ActorTemplateRejected/.test(why) ? "pre-start/actor-template-rejected"
      : /CRASH/i.test(why) ? "infra/actor-crashed" : code ? "agent/exit-code" : "agent/failed"
    yield* fail(id, { reason, phase: t.phase, ...(ready?.message ? { message: ready.message } : {}), ...(code ? { exitCode: Number(code[1]) } : {}) })
  })

  /** B1: a Task missing from the list is confirmed with GetTask. `gone` is true only on NotFound. */
  const confirm = (id: string) => ax.getTask(id).pipe(Effect.map((t) => ({ t, gone: t === undefined })), Effect.orElseSucceed(() => undefined))

  /** Round 2: before any DeleteTask of a Task that may exist and whose verdict is not journaled (heartbeat `lost`, the
   *  janitor, a supersede fence), GetTask it; a terminal Task has its outcome read and journaled first. `unknown` means
   *  ax did not answer or the result read is being retried: delete nothing yet. */
  const salvage = (id: string) => Effect.gen(function*() {
    const r = j.recs.get(id)
    if (!r || r.report !== undefined || !Journal.maybeCreated(r) || r.deleting !== undefined || r.deleted) return "none" as const
    const t = yield* ax.getTask(id).pipe(Effect.result)
    if (t._tag === "Failure") return "unknown" as const
    if (t.success === undefined) return "gone" as const
    if (!owns(id, r, t.success)) { yield* markNotMine(id); return "foreign" as const } // round 3: never read another's result
    if (!TERMINAL.has(t.success.phase)) return "live" as const
    yield* outcomeOf(id, t.success, true)
    return j.recs.get(id)?.report !== undefined ? "read" as const : "unknown" as const
  })

  /** Critique D.2 (DELETE-HANG ladder). The Task's DeleteTask is journaled and ax still shows it Terminating (stock ax
   *  ACKs a delete event and may drop it). Every step is timed from `deletingAt`, so a restart or a compaction does not
   *  reset the clock: re-delete k is due at deletingAt + k * retry (k <= retries), the escalation at escalate, the
   *  give-up at giveUp. The slot is released only when a Substrate read proves the actor absent. */
  const classify = (id: string) => deps.substrate === undefined ? Effect.succeed(undefined)
    : deps.substrate.actor(id, cfg.shape.atespace).pipe(Effect.result, Effect.map((x) => x._tag === "Success" ? x.success : "unknown" as const))
  const terminatingStep = (id: string, now: number) => Effect.gen(function*() {
    const r = j.recs.get(id)
    if (!r || r.deleting === undefined || r.deleted) return
    const since = r.deletingAt ?? r.at
    const age = now - since
    if (r.deleteStuck) { // given up: only a newly proven-free actor changes anything
      if (!r.freeProven && deps.substrate !== undefined && (yield* classify(id)) === "absent") {
        j.append({ ev: "delete-stuck", leaseId: id, freeProven: true })
        log("delete-stuck", { task: id, freeProven: true, since })
        yield* Deferred.succeed(wake, undefined)
      }
      return
    }
    const n = r.deleteRetries ?? 0
    if (n < termRetries && age >= (n + 1) * termRetryMs) {
      j.append({ ev: "delete-retry", leaseId: id, n: n + 1 }) // write-ahead, like `deleting`
      const again = yield* ax.deleteTask(id).pipe(Effect.result)
      log("delete-retry", { task: id, n: n + 1, since, ...(again._tag === "Failure" ? { code: again.failure.code } : {}) })
    }
    if (age >= termEscalateMs && !escalated.has(id)) {
      escalated.add(id)
      const actor = yield* classify(id)
      log("ax-delete-escalate", { task: id, atespace: cfg.shape.atespace, since, retries: j.recs.get(id)?.deleteRetries ?? 0, actor: actor ?? "no-reader" })
    }
    if (age >= termGiveUpMs) {
      const freeProven = (yield* classify(id)) === "absent"
      j.append({ ev: "delete-stuck", leaseId: id, freeProven })
      log("delete-stuck", { task: id, why: r.deleting, since, retries: j.recs.get(id)?.deleteRetries ?? 0, freeProven })
      if (freeProven) yield* Deferred.succeed(wake, undefined)
    }
  })

  const reconcile = (id: string, r: LeaseRec, listed: AxObserved | undefined, now: number) => Effect.gen(function*() {
    if (!Journal.maybeCreated(r)) return // not created yet: dispatch owns it (or a restart resumes it)
    let t = listed
    let gone = false
    if (t === undefined && !r.deleted) {
      const c = yield* confirm(id)
      if (c === undefined) return // ax did not answer; decide nothing this round
      t = c.t; gone = c.gone
    }
    if (!gone) absent.delete(id)
    if (t !== undefined && !gone && !owns(id, r, t)) return yield* markNotMine(id) // round 3: token scope
    if (r.deleting !== undefined) {
      if (gone) {
        j.append({ ev: "deleted", leaseId: id })
        if (r.deleting === "cancel" && !r.report && r.released === undefined) yield* report(id, "cancelled")
        // double-run-r3-1b: a pending-timeout whose DeleteTask was deferred is reported once the Task is gone
        else if (r.deleting === "pre-start" && !r.report && !r.reported && r.released === undefined && r.dropped === undefined)
          yield* fail(id, { reason: "pre-start/pending-timeout", message: "deleted after the pending timeout" })
      } else if (t !== undefined && t.phase === "Terminating") {
        yield* terminatingStep(id, now)
      } else if (t !== undefined && t.phase !== "Terminating") { // round 3: a journaled DeleteTask that did not land
        if (r.released !== undefined && r.report === undefined && !r.reported && r.dropped === undefined && TERMINAL.has(t.phase)) {
          yield* outcomeOf(id, t, true) // a released lease's finished Task is read before it is deleted
          if (j.recs.get(id)?.report === undefined) return
        }
        yield* del(id, r.deleting)
      }
      return
    }
    if (r.reported || r.dropped !== undefined || r.released !== undefined) { // the floor is told: janitor only
      if (gone) return j.append({ ev: "deleted", leaseId: id })
      if (t === undefined) return
      if (r.released !== undefined && r.report === undefined && !r.reported && r.dropped === undefined && TERMINAL.has(t.phase)) {
        yield* outcomeOf(id, t, true) // round 2: a released lease's finished Task is read before the janitor deletes it
        if (j.recs.get(id)?.report === undefined) return // read retried at the next resync; nothing deleted before
      }
      const live = !TERMINAL.has(t.phase) // B3: a told lease's sandbox that still runs goes at once
      if (live || r.released !== undefined || r.dropped !== undefined || now - r.at >= cfg.deleteAfterMs)
        yield* del(id, r.released ? "released" : r.dropped ? "dropped" : live ? "told-still-running" : "janitor")
      return
    }
    if (r.created === undefined) return // round 1: `creating` only: cleanup above, otherwise dispatch or a resume owns it
    if (r.report) return // verdict written, waiting for the outbox
    if (gone) {
      const n = (absent.get(id) ?? 0) + 1
      absent.set(id, n)
      if (n < 2) return log("task-absent", { leaseId: id, resyncs: n }) // B1: two NotFound resyncs in a row
      return yield* fail(id, { reason: "infra/task-lost", message: "created by this link, NotFound on two resyncs" })
    }
    if (t === undefined) return
    if (TERMINAL.has(t.phase)) return yield* outcomeOf(id, t)
    if ((t.phase === "" || t.phase === "Pending") && now - (r.createdAt ?? r.at) > cfg.pendingTimeoutMs) {
      // Critique pass 2026-09-24 (red team double-run-r3-1b): a DeleteTask that did not land leaves a Task that may
      // still start; the retryable verdict waits until the delete lands (the `deleting` branch above reports it).
      if (!(yield* del(id, "pre-start"))) return log("pre-start-deferred", { leaseId: id, why: "delete-unconfirmed" })
      return yield* fail(id, { reason: "pre-start/pending-timeout", phase: t.phase || "Pending" })
    }
    const deadline = r.grant.deadline
    if (t.phase === "Running" && deadline !== undefined && now > deadline + cfg.deadlineBackstopMs) {
      yield* del(id, "deadline")
      return yield* fail(id, { reason: "deadline-exceeded", phase: t.phase })
    }
  })

  /** Round 4: "P1 proven" is a live condition. Logged on every change; p1-missing closes the gate (capacity 0). */
  const setServerP1 = (v: boolean) => {
    if (v === serverP1) return
    serverP1 = v
    log("completion-probe", { serverP1, completion: cfg.completion, mode: mode() ?? "none" })
    if (!v && cfg.completion !== "guest") log("p1-missing", { completion: cfg.completion })
  }
  const probe = Effect.gen(function*() { // P1 adds GetTaskResult; stock v0.3.0 answers UNIMPLEMENTED
    const p = yield* ax.getTaskResult("conwip-link-capability-probe").pipe(Effect.result)
    if (p._tag === "Failure") return // not answered: keep what is known (undefined after an outage: capacity 0)
    setServerP1(p.success !== "unimplemented")
  })

  const checkGateway = Effect.gen(function*() { // B10
    const g = yield* ax.getGateway(cfg.shape.gateway).pipe(Effect.result)
    const open = g._tag === "Success" && g.success !== undefined && gatewayAllowsAll(g.success)
    const ok = g._tag === "Success" && g.success !== undefined && !open
    // Critique D.2 item 5 (V2): three events. `gateway-ok` carries the allowlist size, an existing Gateway that
    // allows everything is `gateway-open`, and only an absent Gateway or a failed lookup is `gateway-missing`.
    const state = g._tag === "Failure" ? `missing:${g.failure.code}` : g.success === undefined ? "missing" : open ? "open" : "ok"
    if (ok !== gatewayOk || state !== gatewayState) {
      if (g._tag === "Failure") log("gateway-missing", { gateway: cfg.shape.gateway, code: g.failure.code })
      else if (g.success === undefined) log("gateway-missing", { gateway: cfg.shape.gateway, found: false })
      else if (open) log("gateway-open", { gateway: cfg.shape.gateway, allowsAll: true })
      else log("gateway-ok", { gateway: cfg.shape.gateway, hosts: g.success.hosts.length })
    }
    gatewayOk = ok; gatewayState = state
  })

  const resync = Effect.gen(function*() {
    const listed = yield* listAll(ax).pipe(Effect.result)
    if (listed._tag === "Failure") {
      if (axUp) log("ax-down", { code: listed.failure.code })
      axUp = false
      // Round 2: nothing read before the outage opens the gate after it. Guest mode does not depend on serverP1, so
      // the Gateway verdict and the resync flag are cleared too; canCreate() opens only after a full resync.
      resynced = false
      gatewayOk = undefined; gatewayState = undefined
      return
    }
    const wasDown = !axUp
    if (wasDown) serverP1 = undefined // B6: nothing proven before the outage holds after it
    yield* probe // round 4: on every resync, since a rollout replaces ax-server with no failed ListTasks
    yield* checkGateway
    last = new Map(listed.success.map((t) => [t.name, t]))
    if (wasDown) log("ax-up", { tasks: listed.success.length })
    axUp = true // round 2: only once probe, Gateway and the occupancy snapshot are all from this side of the outage
    const now = Date.now()
    for (const [id, r] of [...j.recs]) {
      if (dispatching.has(id)) continue
      yield* reconcile(id, r, last.get(id), now)
    }
    resynced = true
  })

  // Occupancy = |live Tasks in the atespace (ours or not) U leases held and not known terminal| (limiter rebuilt from
  // the executor's list, agent-stack-k8s limiter.go). A P1-terminal Task is suspended and holds no worker.
  const occupancy = () => {
    const b = new Set<string>()
    for (const [name, t] of last) if (!TERMINAL.has(t.phase) && !provenFree(name)) b.add(name)
    for (const id of j.held()) { const t = last.get(id); if (!(t && TERMINAL.has(t.phase))) b.add(id) }
    return b.size
  }

  // ---------------------------------------------------------------- heartbeat: level-triggered, complete held set
  const heartbeat = Effect.gen(function*() {
    const ids = j.held()
    // Round 4: the reply is about the generations this call vouched for. A reply that lands after a regrant of the
    // same leaseId (gen n+1) says nothing about it: `lost`, `cancelRequested` and `renewed` apply only while the record
    // still holds the grant object that was sent.
    const sent = new Map(ids.map((id) => [id, j.recs.get(id)?.grant]))
    const current = (id: string) => sent.has(id) && j.recs.get(id)?.grant === sent.get(id)
    const sentAt = Date.now()
    const pendingRequestKey = j.pendingLeaseKey // round 4: vouch for grants under a key whose reply never landed (B8)
    const r = yield* floor.heartbeat({ holderIdentity: cfg.holder, leaseIds: ids, ...(pendingRequestKey !== undefined ? { pendingRequestKey } : {}) }).pipe(Effect.tap(markFloorOk), Effect.result)
    if (r._tag === "Failure") {
      if (r.failure.fatal) { yield* failFatal(r.failure); return undefined }
      log("heartbeat-error", { kind: r.failure.kind })
      return undefined
    }
    for (const id of r.success.renewed) { const g = sent.get(id); if (g !== undefined && current(id)) renewedLocal(id, g, sentAt) }
    for (const id of r.success.lost) { // fencing: the lease is gone, so the Task goes; no report
      if (!current(id)) { log("stale-heartbeat-reply", { leaseId: id, about: "lost" }); continue }
      const rec = j.recs.get(id)
      pendingResume.delete(id)
      if (!rec) { const x = j.invalid.get(id); if (x && x.released === undefined) j.append({ ev: "released", leaseId: id, why: "lost" }); continue }
      if (rec.released !== undefined) continue
      j.append({ ev: "released", leaseId: id, why: "lost" })
      abandoned.set(id, "lost")
      log("lost", { leaseId: id })
      if (Journal.maybeCreated(rec)) { // round 1: `creating` counts; the janitor confirms NotFound
        const s = yield* salvage(id) // round 2: a finished Task's verdict is read and journaled before the delete
        if (s === "unknown") log("delete-deferred", { task: id, why: "lost", until: "verdict-read" }) // the janitor reads, then deletes
        else if (s !== "gone" && s !== "foreign") yield* del(id, "lost")
      }
    }
    for (const id of r.success.cancelRequested) { // Temporal cancel_requested; ax cancel is DeleteTask, two-phase
      if (!current(id)) { log("stale-heartbeat-reply", { leaseId: id, about: "cancel" }); continue }
      const rec = j.recs.get(id)
      if (!rec || rec.report || rec.deleting !== undefined) continue
      log("cancel", { leaseId: id })
      pendingResume.delete(id)
      abandoned.set(id, "cancel") // B3: a running dispatch reports or deletes; no later resume creates it
      if (dispatching.has(id)) continue
      // Round 1: a Task that may exist (`creating`) is deleted and seen NotFound before `cancelled` is reported
      if (Journal.maybeCreated(rec)) yield* del(id, "cancel")
      else yield* report(id, "cancelled")
    }
    const renewed = new Set(r.success.renewed)
    for (const id of [...pendingResume]) { // B13: resume only what the floor still says is ours
      if (!renewed.has(id) || !current(id)) continue
      pendingResume.delete(id)
      const rec = j.recs.get(id)
      if (rec && rec.created === undefined && !rec.report && rec.released === undefined && rec.dropped === undefined) {
        log("resume", { leaseId: id })
        yield* Effect.forkScoped(dispatch(rec.grant))
      }
    }
    return renewed
  })

  // ---------------------------------------------------------------- the loops
  const every = <R>(name: string, ms: () => number, body: Effect.Effect<unknown, never, R>) => Effect.forever(
    Effect.suspend(() => Effect.sleep(ms())).pipe(Effect.andThen(body), // re-read: the floor may change the interval
      Effect.catchCause((c) => Cause.hasInterruptsOnly(c) ? Effect.interrupt : Effect.sync(() => log(`${name}-died`, { cause: Cause.pretty(c) })))))

  /** Round 3: the heartbeat interval, at most a third of the shortest lease held, so a large floor value can never let
   *  a held lease expire between two heartbeats. */
  const hbSeconds = () => {
    let hi = MAX_HEARTBEAT_SECONDS
    for (const id of j.held()) {
      const d = j.recs.get(id)?.grant.lease.leaseDurationSeconds
      if (d !== undefined && Number.isFinite(d) && d > 0) hi = Math.min(hi, d / 3)
    }
    return boundedSeconds(hbAsked, defaultHb, Math.max(1, hi))
  }

  /** Final pass (VERIFY-LINK R3-1). The heartbeat sleep is measured from the last heartbeat and is cut short when a
   *  Lease reply shrinks the interval or journals a grant with a shorter lease: a sleep begun at the 30 s default while
   *  nothing was held no longer outlives a 12 s lease granted during it. */
  let lastBeatAt = Date.now()
  const heartbeatLoop = Effect.forever(Effect.gen(function*() {
    let target = jitter(hbSeconds() * cfg.secondMs)
    for (;;) {
      const left = lastBeatAt + target - Date.now()
      if (left <= 0) break
      const w = hbWake
      yield* Effect.raceFirst(Effect.sleep(left), Deferred.await(w))
      if (yield* Deferred.isDone(w)) {
        hbWake = yield* Deferred.make<void>()
        target = Math.min(target, jitter(hbSeconds() * cfg.secondMs))
      }
    }
    lastBeatAt = Date.now()
    yield* heartbeat
  }).pipe(Effect.catchCause((c) => Cause.hasInterruptsOnly(c) ? Effect.interrupt : Effect.sync(() => log("heartbeat-died", { cause: Cause.pretty(c) })))))

  let endpointSeen: string | undefined
  const leaseOnce = Effect.gen(function*() {
    outboxWaitUntil = Math.min(outboxWaitUntil, Date.now()) // B15: a verdict goes out before new work comes in
    yield* drainOutbox
    // Round 1 (B15): while any verdict is still undelivered, ask for nothing. A grant that arrived now could supersede
    // that verdict's attempt, and once n+1 is leased the floor answers n's verdict stale-attempt.
    // Round 2: a verdict the floor has answered with a server error is not an outage; it no longer gates Lease (its
    // own budget replaces or dead-letters it, and a grant that supersedes it waits at dispatch, bounded).
    const undelivered = j.outbox().filter((p) => !verdictFailures.has(p.leaseId)).length
    if (undelivered > 0) log("lease-gated-by-outbox", { undelivered })
    const draining = deps.drain !== undefined && (yield* Deferred.isDone(deps.drain))
    const free = !draining && undelivered === 0 && canCreate() ? Math.max(0, cfg.maxInFlight - occupancy()) : 0
    // B8: a key is journaled before the call and reused until a reply is journaled, so a lost reply is replayed,
    // not stranded. A capacity-0 call can grant nothing, so it is not journaled.
    let requestKey = j.pendingLeaseKey
    if (requestKey === undefined) {
      requestKey = randomUUID()
      if (free > 0) j.append({ ev: "lease-key", requestKey })
    }
    const sentAt = Date.now()
    const r = yield* callLease(free, requestKey)
    if (r._tag === "Failure") {
      if (r.failure.fatal) return yield* failFatal(r.failure)
      leaseFailed(r.failure, requestKey)
      // Round 3: bounded, and only this loop waits; the heartbeat and resync fibers run on their own intervals
      return yield* Effect.sleep(Math.min(r.failure.retryAfterMs ?? jitter(pollSeconds * cfg.secondMs), MAX_POLL_SECONDS * cfg.secondMs))
    }
    yield* applyLease(r.success, requestKey, sentAt)
  })

  const callLease = (capacity: number, requestKey: string) => floor.lease({ holderIdentity: cfg.holder, capacity, requestKey }).pipe(
    Effect.tap(markFloorOk), Effect.retry({ times: 2, while: (e: FloorError) => e.kind === "transient", schedule: Schedule.exponential(Math.max(1, cfg.secondMs / 5)).pipe(Schedule.jittered) }), Effect.result)
  const leaseFailed = (e: FloorError, requestKey: string) => {
    log("lease-error", { kind: e.kind, pendingKey: j.pendingLeaseKey !== undefined, message: e.message.slice(0, 200) })
    // Round 3: a journaled key is replayed through outages (B8), but not through replies the floor keeps answering
    // with a server error or that do not decode: those would strand the key's grants for ever. After
    // `leaseKeyAttempts` in a row the key is abandoned; the floor's expiry requeues what it granted under it.
    if (e.kind === "server-error" && j.pendingLeaseKey === requestKey) {
      if (++leaseKeyFailures >= leaseKeyAttempts) {
        j.append({ ev: "lease-replied", requestKey, abandoned: true })
        log("lease-key-abandoned", { tries: leaseKeyFailures, message: e.message.slice(0, 200) })
        leaseKeyFailures = 0
      }
    }
  }
  /** Round 4 (B8 at startup): a key journaled by a previous process whose reply never landed is replayed BEFORE the
   *  first Heartbeat, so its grants are journaled and in the held set when the Heartbeat re-adopts orphans; replayed
   *  after it, an orphan granted under the key is omitted and released (L3 a). Capacity 0: a key the floor never saw
   *  grants nothing new. A failed replay leaves the key pending; the Heartbeat then vouches for it. */
  const replayPendingLease = Effect.gen(function*() {
    const requestKey = j.pendingLeaseKey
    if (requestKey === undefined) return
    const sentAt = Date.now()
    const r = yield* callLease(0, requestKey)
    if (r._tag === "Failure") {
      if (r.failure.fatal) return yield* failFatal(r.failure)
      return leaseFailed(r.failure, requestKey)
    }
    log("lease-key-replayed", { grants: r.success.grants.length })
    yield* applyLease(r.success, requestKey, sentAt)
  })

  const applyLease = (reply: LeaseReply, requestKey: string, sentAt: number) => Effect.gen(function*() {
    leaseKeyFailures = 0
    // Round 3: the server-driven intervals are bounded (Buildkite falls back to its defaults): 0, a negative or a
    // missing value would make both loops tight loops of billed requests.
    pollSeconds = boundedSeconds(reply.nextPollSeconds, defaultPoll, MAX_POLL_SECONDS)
    hbAsked = reply.heartbeatSeconds
    const hbNow = hbSeconds()
    const clamp = `${reply.nextPollSeconds}->${pollSeconds} ${reply.heartbeatSeconds}->${hbNow}`
    if ((pollSeconds !== reply.nextPollSeconds || hbNow !== reply.heartbeatSeconds) && clamp !== clampLogged) {
      clampLogged = clamp
      log("interval-clamped", { nextPollSeconds: reply.nextPollSeconds ?? null, usedPoll: pollSeconds, heartbeatSeconds: reply.heartbeatSeconds ?? null, usedHeartbeat: hbNow })
    }
    for (const g of reply.grants) {
      const prior = j.recs.get(g.leaseId)
      // Round 3: a grant of a lease this link finished (compacted away since) is at-least-once redelivery, not work.
      const tomb = j.tombs.get(g.leaseId)
      if (prior === undefined && tomb !== undefined && !laterGen(genOf(g), tomb.gen)) { log("duplicate-grant", { leaseId: g.leaseId, finished: true }); continue }
      if (prior !== undefined) {
        // The floor already said it withdrew this generation (Complete.withdrew journaled on an earlier attempt) but its
        // dispatch has not run yet: release it now, so its regrant is not taken for a duplicate.
        const pg = genOf(prior.grant)
        if (prior.released === undefined && !Journal.maybeCreated(prior) && [...j.recs.values()].some((x) => x.withdrew === g.leaseId && x.withdrewGen !== undefined && sameGen(pg, x.withdrewGen))) {
          j.append({ ev: "released", leaseId: g.leaseId, why: "withdrawn" })
          log("withdrawn", { leaseId: g.leaseId, by: "journal" })
        }
        // Round 2: dedupe on the grant's identity, not its leaseId. A floor that withdrew n+1 (rule 4b) and then requeued
        // it for n's retryable verdict grants the same leaseId again with a new acquireTime and leaseTransitions; that
        // is a new grant generation, dispatched, when the old record is released and holds nothing in ax or the outbox.
        const newer = laterGen(genOf(g), pg) // round 3: strictly later, so a stale redelivery is never a regrant
        // Round 4: the floor's generation is authoritative. A strictly later grant means the floor already withdrew
        // the one held (its Complete reply may still be in flight, or lost). If the held one never reached ax and owes
        // no verdict, it is released now and the regrant taken; the floor does not redeliver it. Its dispatch sees the
        // record change and stops (grant-superseded-before-create).
        if (newer && prior.released === undefined && !Journal.maybeCreated(prior) && !Journal.pending(prior)) {
          j.append({ ev: "released", leaseId: g.leaseId, why: "superseded-by-regrant" })
          log("superseded-by-regrant", { leaseId: g.leaseId, was: pg.leaseTransitions, now: g.lease.leaseTransitions })
        }
        const reusable = prior.released !== undefined && !Journal.pending(prior) && (!Journal.maybeCreated(prior) || prior.deleted === true)
        if (!(newer && reusable)) { log("duplicate-grant", { leaseId: g.leaseId }); continue } // at-least-once delivery
        for (const m of [abandoned, absent, resultFailures, verdictFailures, verdictNotBefore, verdictTriedAt]) m.delete(g.leaseId)
        admitted.delete(g.leaseId); pendingResume.delete(g.leaseId)
        j.append({ ev: "grant", leaseId: g.leaseId, grant: g, regrant: true })
        log("regrant", { leaseId: g.leaseId, was: prior.released })
      } else j.append({ ev: "grant", leaseId: g.leaseId, grant: g })
      renewedLocal(g.leaseId, g, sentAt) // round 4: the floor acquired it no earlier than this call was sent
      log("leased", { leaseId: g.leaseId, attempt: g.attempt, supersedes: g.supersedes ?? [] })
      yield* Effect.forkScoped(dispatch(g))
    }
    for (const b of reply.invalid ?? []) { // round 1: refuse one bad grant, keep the rest of the reply
      if (b.leaseId === undefined || b.attempt === undefined) { log("grant-undecodable", { message: b.message }); continue } // the floor's expiry frees it
      if (j.recs.has(b.leaseId) || j.invalid.has(b.leaseId)) continue
      j.append({ ev: "grant-invalid", leaseId: b.leaseId, attempt: b.attempt, message: b.message })
      log("grant-invalid", { leaseId: b.leaseId, attempt: b.attempt })
      yield* Deferred.succeed(wake, undefined)
    }
    if (j.pendingLeaseKey === requestKey) j.append({ ev: "lease-replied", requestKey })
    yield* Deferred.succeed(hbWake, undefined) // final pass (R3-1): the interval or the held set may have shrunk
    const ep = reply.endpoint // B18: only an exact match in the Nix-declared list, and only once
    if (ep !== undefined && ep !== deps.floorUrl && ep !== endpointSeen) {
      endpointSeen = ep
      if ((cfg.floorUrls ?? []).includes(ep) && ep.startsWith("https://")) { log("endpoint-accepted", { endpoint: ep }); deps.onEndpoint?.(ep) }
      else log("endpoint-ignored", { endpoint: ep })
    }
  })

  const body = Effect.gen(function*() {
    yield* resync // limiter and outcomes rebuilt before the first heartbeat or lease
    yield* selfFence // red team double-run-r1-1: a Task left unrenewed past lease + grace by a down link goes first
    for (const [id, r] of j.recs) // grants journaled by a previous process but never created (B13: resumed on renewal)
      if (r.created === undefined && !r.report && r.released === undefined && r.dropped === undefined && !r.notMine) pendingResume.add(id)
    yield* replayPendingLease // round 4: a key left pending by a kill is answered before the first Heartbeat
    yield* heartbeat // vouch first: re-adopt or release orphans (L3), then resume only renewed grants
    lastBeatAt = Date.now()
    // Round 3: renewal and resync start now, before any Complete or Lease can stall (a 429 Retry-After, a timeout
    // chain): held leases keep being renewed whatever the first Lease does. Both re-read their interval every time.
    yield* Effect.forkScoped(heartbeatLoop)
    yield* Effect.forkScoped(every("resync", () => cfg.resyncMs, resync.pipe(Effect.andThen(selfFence), Effect.andThen(drainOutbox))))
    yield* drainOutbox // replay before new work (uplink)
    yield* Effect.raceFirst(leaseOnce, Deferred.await(deps.stop)) // its reply sets the server-driven intervals
    let drainDeadline: number | undefined
    while (!(yield* Deferred.isDone(deps.stop))) {
      const w = wake
      // G-BK4: while draining, look every resync (not every poll) for the moment nothing is held any more
      const draining = deps.drain !== undefined && (yield* Deferred.isDone(deps.drain))
      const nap = draining ? Math.min(cfg.resyncMs, pollSeconds * cfg.secondMs) : jitter(pollSeconds * cfg.secondMs)
      const drainWake = deps.drain !== undefined && !draining ? Deferred.await(deps.drain) : Effect.never
      yield* Effect.raceFirst(Effect.raceFirst(Effect.raceFirst(Effect.suspend(() => Effect.sleep(nap)), Deferred.await(w)), Deferred.await(deps.stop)), drainWake)
      if (yield* Deferred.isDone(deps.stop)) break
      if (deps.drain !== undefined && (yield* Deferred.isDone(deps.drain))) {
        drainDeadline ??= Date.now() + (deps.drainTimeoutMs ?? Infinity)
        const outbox = j.outbox().length
        if (occupancy() === 0 && outbox === 0) { log("drain-complete", {}); break }
        if (Date.now() >= drainDeadline) { log("drain-timeout", { occupancy: occupancy(), outbox }); break }
      }
      if (yield* Deferred.isDone(w)) wake = yield* Deferred.make<void>()
      yield* Effect.raceFirst(leaseOnce, Deferred.await(deps.stop))
    }
    // drain (Buildkite stop before disconnect): no more leases; ax Tasks keep running and are re-adopted on restart
    outboxWaitUntil = 0
    yield* drainOutbox
    log("drained", { held: j.held().length })
  })

  return yield* Effect.raceFirst(Effect.scoped(body), Deferred.await(fatal))
})
