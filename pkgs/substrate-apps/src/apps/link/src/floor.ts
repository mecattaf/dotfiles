// The link's view of the floor: the three L1 RPCs over Effect's stock HTTP RPC client (decision L2), outbound only.
// HTTP statuses the floor's Worker entry answers before any RPC runs are classified here (Buildkite's retry
// classifier, api/retryable.go): 401/403 fatal (token), 409 fatal (a second session for this identity, L5),
// 429 back off honouring Retry-After. Round 2: any 3xx is fatal (`redirect`: redirects are never followed, so the only
// way to another floor URL is the Lease `endpoint` checked against the Nix list, B18); 404 and 405 are fatal
// (`misrouted`: a wrong route answers every call so, and dropping verdicts for it would lose them); any other 4xx except 408 is
// `rejected` (permanent for these bytes: Complete drops the verdict); a 500, 501 or 505+ and an RPC Defect in the reply
// are `server-error` (the floor answered and refused these bytes; the outbox counts them per verdict); 502, 503, 504,
// 408, network errors and timeouts stay `transient`. Every call has a ceiling (B9).
import { Effect, Layer, Schema, Scope } from "effect"
import { FetchHttpClient, HttpClient, HttpClientRequest } from "effect/unstable/http"
import { RpcClient, RpcSerialization } from "effect/unstable/rpc"
import { Complete, FloorLinkClient, Grant } from "./contract.ts"
import type { Usage, Result } from "./contract.ts"

/** A grant the link could not decode. `leaseId` and `attempt` are set when they alone decode, so the lease can be
 *  failed back to the floor as pre-start/invalid-spec; otherwise the floor's own expiry is the only way out. */
export interface InvalidGrant { readonly leaseId?: string; readonly attempt?: number; readonly message: string }
/** Round 3: the reply as the link uses it, after the lenient envelope decode. Intervals and endpoint are kept only
 *  when they have the right JSON type; the link bounds the intervals (link.ts `boundedSeconds`). */
export type LeaseReply = {
  readonly grants: ReadonlyArray<Grant>; readonly invalid?: ReadonlyArray<InvalidGrant>
  readonly stats?: unknown; readonly nextPollSeconds?: number; readonly heartbeatSeconds?: number; readonly endpoint?: string
}
/** Round 4: the Heartbeat reply after the lenient decode: each list keeps only its strings, a missing one is []. */
type HeartbeatReply = { readonly renewed: ReadonlyArray<string>; readonly lost: ReadonlyArray<string>; readonly cancelRequested: ReadonlyArray<string>; readonly stats?: unknown }
const strings = (v: unknown): Array<string> => Array.isArray(v) ? v.filter((x): x is string => typeof x === "string") : []
const heartbeatReply = (r: { readonly renewed?: unknown; readonly lost?: unknown; readonly cancelRequested?: unknown; readonly stats?: unknown }): HeartbeatReply =>
  ({ renewed: strings(r.renewed), lost: strings(r.lost), cancelRequested: strings(r.cancelRequested), stats: r.stats })
type CompleteReply = { readonly duplicate: boolean; readonly withdrew?: string; readonly withdrewTransitions?: number; readonly stats?: unknown }
const num = (v: unknown) => typeof v === "number" ? v : undefined
const leaseReply = (r: { readonly grants: ReadonlyArray<unknown>; readonly nextPollSeconds?: unknown; readonly heartbeatSeconds?: unknown; readonly endpoint?: unknown; readonly stats?: unknown }): LeaseReply => {
  const s = splitGrants(r)
  const poll = num(r.nextPollSeconds), hb = num(r.heartbeatSeconds)
  return { grants: s.grants, invalid: s.invalid, stats: r.stats, ...(poll !== undefined ? { nextPollSeconds: poll } : {}),
    ...(hb !== undefined ? { heartbeatSeconds: hb } : {}), ...(typeof r.endpoint === "string" ? { endpoint: r.endpoint } : {}) }
}
const completeReply = (r: { readonly duplicate?: unknown; readonly withdrew?: unknown; readonly withdrewTransitions?: unknown; readonly stats?: unknown }): CompleteReply => {
  const wt = num(r.withdrewTransitions)
  return { duplicate: r.duplicate === true, stats: r.stats, ...(typeof r.withdrew === "string" ? { withdrew: r.withdrew } : {}),
    ...(wt !== undefined && Number.isInteger(wt) ? { withdrewTransitions: wt } : {}) }
}
const encodeComplete = Schema.encodeUnknownExit(Complete.payloadSchema)

export type FloorErrorKind = "transient" | "auth" | "session-conflict" | "rate-limited" | "redirect" | "misrouted" | "rejected" | "server-error"
export class FloorError {
  readonly _tag = "FloorError"
  constructor(readonly kind: FloorErrorKind, readonly message: string, readonly retryAfterMs?: number, readonly status?: number) {}
  get fatal() { return this.kind === "auth" || this.kind === "session-conflict" || this.kind === "redirect" || this.kind === "misrouted" }
}
/** The floor refused these bytes for good: one of its CompleteError codes (any string, round 2), or an HTTP 4xx. */
export class CompleteRefused {
  readonly _tag = "CompleteRefused"
  constructor(readonly code: string) {}
}

export interface CompletePayload { leaseId: string; attempt: number; result: Result; output?: unknown; usage?: Usage }
export interface FloorApi {
  readonly lease: (p: { holderIdentity: string; capacity: number; requestKey: string }) => Effect.Effect<LeaseReply, FloorError>
  readonly heartbeat: (p: { holderIdentity: string; leaseIds: ReadonlyArray<string>; pendingRequestKey?: string }) => Effect.Effect<HeartbeatReply, FloorError>
  readonly complete: (p: CompletePayload) => Effect.Effect<CompleteReply, FloorError | CompleteRefused>
}

export interface FloorOptions {
  readonly url: string // e.g. https://substrate.<account>.workers.dev (no trailing /rpc)
  readonly token: string // the per-link bearer, read from $CREDENTIALS_DIRECTORY; never logged
  readonly sessionId: string // stable per state directory: a restart is the same session, a second replica is not
  readonly fetch?: typeof globalThis.fetch // tests hand in an in-process handler; production uses globalThis.fetch
  /** B9: a ceiling on every call (Buildkite's 330 s on acquire, shortened): Lease and Heartbeat 20 s, Complete 60 s. */
  readonly timeoutsMs?: { readonly lease: number; readonly heartbeat: number; readonly complete: number }
}
export const DEFAULT_FLOOR_TIMEOUTS_MS = { lease: 20_000, heartbeat: 20_000, complete: 60_000 } as const

/** B9 (critique R9): a non-2xx answer is thrown by the fetch wrapper of the call that received it, so its status
 *  travels inside that call's own error chain; nothing is shared between concurrent calls. */
class HttpStatus extends Error {
  readonly linkHttpStatus = true
  constructor(readonly status: number, readonly retryAfterMs: number | undefined) { super(`floor answered ${status}`) }
}
const statusIn = (e: unknown): HttpStatus | undefined => {
  let x: any = e
  for (let i = 0; i < 10 && x != null && typeof x === "object"; i++) {
    if (x instanceof HttpStatus || x.linkHttpStatus === true) return x as HttpStatus
    x = x.reason ?? x.cause ?? x.error
  }
  return undefined
}
const decodeGrant = Schema.decodeUnknownExit(Grant)
const Envelope = Schema.decodeUnknownExit(Schema.Struct({ leaseId: Schema.String, attempt: Schema.Int }))
/** Decode each grant on its own: the good ones are dispatched, the bad ones are refused one by one. */
export const splitGrants = <R extends { readonly grants: ReadonlyArray<unknown> }>(r: R): Omit<R, "grants"> & { grants: Array<Grant>; invalid: Array<InvalidGrant> } => {
  const grants: Array<Grant> = [], invalid: Array<InvalidGrant> = []
  for (const raw of r.grants) {
    const g = decodeGrant(raw)
    if (g._tag === "Success") { grants.push(g.value); continue }
    const env = Envelope(raw)
    const message = String(g.cause).slice(0, 500)
    invalid.push(env._tag === "Success" ? { leaseId: env.value.leaseId, attempt: env.value.attempt, message } : { message })
  }
  return { ...r, grants, invalid }
}

export const classifyFloorError = (e: unknown): FloorError => {
  const st = statusIn(e)
  const s = st?.status ?? 0
  const msg = e instanceof Error ? e.message : String((e as any)?.message ?? e)
  if (s >= 300 && s < 400) return new FloorError("redirect", `floor answered ${s}: redirects are never followed; fix LINK_FLOOR_URL`, undefined, s)
  if (s === 401 || s === 403) return new FloorError("auth", `floor answered ${s}`, undefined, s)
  if (s === 409) return new FloorError("session-conflict", "floor answered 409: another session holds this link identity", undefined, s)
  if (s === 429) return new FloorError("rate-limited", "floor answered 429", st?.retryAfterMs, s)
  // 404/405: the route is wrong for every call, not these bytes; fatal (exit 78), so no verdict is dropped for it
  if (s === 404 || s === 405) return new FloorError("misrouted", `floor answered ${s}: fix LINK_FLOOR_URL or the Worker route`, undefined, s)
  if (s >= 400 && s < 500 && s !== 408) return new FloorError("rejected", `floor answered ${s}`, undefined, s)
  if (s >= 500 && s !== 502 && s !== 503 && s !== 504) return new FloorError("server-error", `floor answered ${s}`, undefined, s)
  return new FloorError("transient", s ? `floor answered ${s}` : msg, undefined, s || undefined)
}
/** Round 3: a defect raised by a call is always the reply's: the link encodes the Complete payload itself before it
 *  sends (a failure there is `transient`, the link's own bug), and the envelopes it decodes are lenient. A defect is
 *  then the floor's RPC `Defect` reply (e.g. SQLITE_TOOBIG) or a reply that is not the protocol at all: the server
 *  refusing these bytes (`server-error`), counted per verdict on Complete and per requestKey on Lease. */
export const rpcFloor = (o: FloorOptions): Effect.Effect<FloorApi, never, Scope.Scope> => Effect.gen(function*() {
  const base = o.fetch ?? globalThis.fetch
  const t = o.timeoutsMs ?? DEFAULT_FLOOR_TIMEOUTS_MS
  const observing: typeof globalThis.fetch = async (input, init) => {
    // Round 2: never follow a redirect. A followed 307 lands on an origin the Nix list never declared, and the link
    // would act on its replies (B18 bypass); an Access 302 to a login page would read as a transient decode error.
    const res = await base(input, { ...init, redirect: "manual" })
    if (res.type === "opaqueredirect") throw new HttpStatus(307, undefined)
    if (!res.ok) {
      const ra = Number(res.headers.get("retry-after"))
      throw new HttpStatus(res.status, Number.isFinite(ra) && ra > 0 ? ra * 1000 : undefined)
    }
    return res
  }
  const protocol = RpcClient.layerProtocolHttp({
    url: `${o.url.replace(/\/$/, "")}/rpc`,
    transformClient: HttpClient.mapRequest((r) => r.pipe(
      HttpClientRequest.bearerToken(o.token),
      HttpClientRequest.setHeader("x-link-session", o.sessionId)))
  }).pipe(Layer.provide([FetchHttpClient.layer, RpcSerialization.layerJson]),
    Layer.provide(Layer.succeed(FetchHttpClient.Fetch, observing)))
  const client = yield* RpcClient.make(FloorLinkClient).pipe(Effect.provide(protocol))
  // The timeout interrupts the call, which aborts its fetch (FetchHttpClient passes an AbortSignal).
  const within = (ms: number, what: string) => <A, E>(e: Effect.Effect<A, E>) =>
    e.pipe(Effect.timeoutOrElse({ duration: ms, orElse: () => Effect.fail(new FloorError("transient", `${what} timed out after ${ms} ms`)) }))
  return {
    // Round 1: a reply that does not decode is a typed transient failure, never a defect that kills the link.
    lease: (p) => client.Lease(p).pipe(Effect.catchDefect((d) => Effect.fail(new FloorError("server-error", `Lease reply undecodable: ${String(d).slice(0, 300)}`))),
      Effect.mapError((e) => e instanceof FloorError ? e : classifyFloorError(e)), Effect.map(leaseReply), within(t.lease, "Lease")),
    // Round 4: lenient like Lease and Complete; a reply that still does not decode is the server's (server-error).
    heartbeat: (p) => client.Heartbeat({ holderIdentity: p.holderIdentity, leaseIds: p.leaseIds, ...(p.pendingRequestKey !== undefined ? { pendingRequestKey: p.pendingRequestKey } : {}) }).pipe(
      Effect.catchDefect((d) => Effect.fail(new FloorError("server-error", `Heartbeat reply undecodable: ${String(d).slice(0, 300)}`))),
      Effect.mapError((e) => e instanceof FloorError ? e : classifyFloorError(e)), Effect.map(heartbeatReply), within(t.heartbeat, "Heartbeat")),
    // L9: omit absent optional keys; `usage: undefined` in an optionalKey field is an encode defect, not a failure.
    complete: (p) => {
      const payload = { leaseId: p.leaseId, attempt: p.attempt, result: p.result,
        ...(p.output !== undefined ? { output: p.output } : {}), ...(p.usage !== undefined ? { usage: p.usage } : {}) }
      const enc = encodeComplete(payload)
      if (enc._tag === "Failure") return Effect.fail(new FloorError("transient", `encode defect: ${String(enc.cause).slice(0, 300)}`))
      return client.Complete(payload).pipe(Effect.map(completeReply),
      Effect.catchDefect((d) => Effect.fail(new FloorError("server-error", `server defect: ${String((d as any)?.message ?? d).slice(0, 300)}`))),
      Effect.mapError((e: any) => e instanceof FloorError ? e
        : e && typeof e === "object" && "code" in e && !("_tag" in e) ? new CompleteRefused(String(e.code)) : classifyFloorError(e)),
      // Round 2: a 4xx other than 401/403/408/409/429 refuses these bytes for good (Buildkite: not retryable)
      Effect.mapError((e) => e instanceof FloorError && e.kind === "rejected" ? new CompleteRefused(`http-${e.status}`) : e),
      within(t.complete, "Complete"))
    }
  }
})
