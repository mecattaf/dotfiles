// The typed client over the floor's operator routes. Promise-based so a CLI verb, an MCP tool and a code-mode
// snippet all call it the same way; every answer is decoded with the schema api.ts publishes, so a drifted floor
// fails here, loudly, rather than in a table three layers up.
import { Schema } from "effect"
import * as S from "./schema.ts"

export class SubstrateError extends Error {
  override readonly name = "SubstrateError"
  constructor(readonly status: number, readonly code: string, message: string) { super(`${status} ${code}: ${message}`) }
}

export interface ClientOptions {
  /** The floor's base URL, e.g. https://substrate.example.dev (no trailing path). */
  readonly url: string
  /** The operator bearer (FLOOR_TOKEN). Never logged. */
  readonly token?: string
  /** A Cloudflare Access service token pair, sent instead of or beside the bearer. */
  readonly access?: { readonly clientId: string; readonly clientSecret: string }
  readonly fetch?: typeof globalThis.fetch
  readonly timeoutMs?: number
}

export interface SeatRow {
  readonly seat: string; readonly grade: string; readonly staleness: string; readonly headroom_pct: number | null
  readonly next_reset_at: string | null; readonly wip: number; readonly admit: boolean | null; readonly reason: string | null
}

const decode = <A>(schema: Schema.Codec<A, unknown>, v: unknown, what: string): A => {
  try { return Schema.decodeUnknownSync(schema as never)(v) as A } catch (e) {
    throw new SubstrateError(0, "decode", `${what}: the floor's answer does not match the published schema: ${String((e as Error).message).slice(0, 600)}`)
  }
}

const RunsReply = Schema.Struct({ runs: Schema.Array(S.RunView) })
const RunReply = Schema.Struct({ run: S.RunView })
const JobsReply = Schema.Struct({ jobs: Schema.Array(S.JobSummary) })
const JobReply = Schema.Struct({ job: S.JobView })
const EventsReply = Schema.Struct({ events: Schema.Array(S.FloorEvent) })
const HoldersReply = Schema.Struct({ holders: Schema.Array(S.Holder) })
const PauseReply = Schema.Struct({ holder: Schema.String, paused: Schema.Boolean })

export class SubstrateClient {
  readonly url: string
  readonly #o: ClientOptions
  constructor(o: ClientOptions) { this.url = o.url.replace(/\/+$/, ""); this.#o = o }

  private headers(extra: Record<string, string> = {}): Headers {
    const h = new Headers(extra)
    if (this.#o.token) h.set("authorization", `Bearer ${this.#o.token}`)
    if (this.#o.access) { h.set("cf-access-client-id", this.#o.access.clientId); h.set("cf-access-client-secret", this.#o.access.clientSecret) }
    return h
  }

  /** One request; a non-2xx answer becomes a SubstrateError carrying the floor's own code. */
  async request(method: string, path: string, body?: { json?: unknown; text?: string; contentType?: string }): Promise<{ status: number; text: string }> {
    const f = this.#o.fetch ?? globalThis.fetch
    const init: RequestInit = { method, headers: this.headers(body?.json !== undefined ? { "content-type": "application/json" } : body?.text !== undefined ? { "content-type": body.contentType ?? "text/plain" } : {}) }
    if (body?.json !== undefined) init.body = JSON.stringify(body.json)
    else if (body?.text !== undefined) init.body = body.text
    if (this.#o.timeoutMs) init.signal = AbortSignal.timeout(this.#o.timeoutMs)
    const res = await f(`${this.url}${path}`, init)
    const text = await res.text()
    if (!res.ok) {
      let code = `http-${res.status}`, message = text.slice(0, 500)
      try {
        const e = (JSON.parse(text) as { error?: unknown }).error
        if (typeof e === "string") { code = e; message = e } else if (e && typeof e === "object") { code = String((e as { code?: unknown }).code ?? code); message = String((e as { message?: unknown }).message ?? message) }
      } catch { /* not JSON */ }
      throw new SubstrateError(res.status, code, message)
    }
    return { status: res.status, text }
  }
  private async json(method: string, path: string, json?: unknown): Promise<unknown> {
    const r = await this.request(method, path, json === undefined ? undefined : { json })
    try { return JSON.parse(r.text) } catch { throw new SubstrateError(r.status, "not-json", `${method} ${path} answered a non-JSON body`) }
  }
  private p = (s: string) => encodeURIComponent(s)

  // ---- runs
  /** Submit a workflow script (source text) or AgentJobs. Idempotent when `id` is given. */
  async submit(req: S.SubmitRequest): Promise<S.SubmitReply> { return decode(S.SubmitReply, await this.json("POST", "/runs", req), "submit") }
  submitScript(script: string, o: { args?: unknown; id?: string } = {}): Promise<S.SubmitReply> { return this.submit({ script, ...o }) }
  submitJobs(jobs: ReadonlyArray<S.AgentJob>, o: { name?: string; id?: string } = {}): Promise<S.SubmitReply> { return this.submit({ jobs, ...o }) }
  async runs(o: { limit?: number } = {}): Promise<ReadonlyArray<S.RunView>> { return decode(RunsReply, await this.json("GET", `/runs?limit=${o.limit ?? 50}`), "runs").runs }
  async run(id: string): Promise<S.RunView> { return decode(RunReply, await this.json("GET", `/runs/${this.p(id)}`), "run").run }
  async runJobs(id: string): Promise<ReadonlyArray<S.JobSummary>> { return decode(JobsReply, await this.json("GET", `/runs/${this.p(id)}/jobs`), "runJobs").jobs }
  async runScript(id: string): Promise<string> { return (await this.request("GET", `/runs/${this.p(id)}/script`)).text }
  async runEvents(id: string, after = 0): Promise<ReadonlyArray<S.FloorEvent>> { return decode(EventsReply, await this.json("GET", `/runs/${this.p(id)}/events?after=${after}`), "runEvents").events }
  async cancelRun(id: string): Promise<S.RunView> { return decode(RunReply, await this.json("POST", `/runs/${this.p(id)}/cancel`), "cancelRun").run }
  /** The interpreter host's call: enqueue agent() nodes of a script run as AgentJobs (idempotent by name). */
  async enqueue(id: string, jobs: ReadonlyArray<S.AgentJob>): Promise<S.Enqueued> { return decode(S.Enqueued, await this.json("POST", `/runs/${this.p(id)}/jobs`, jobs), "enqueue") }
  /** Poll a run until it is done or the timeout passes; answers the last view either way. */
  async waitRun(id: string, o: { timeoutMs?: number; pollMs?: number } = {}): Promise<S.RunView> {
    const until = Date.now() + (o.timeoutMs ?? 60_000)
    for (;;) {
      const r = await this.run(id)
      if (r.state === "done" || Date.now() >= until) return r
      await new Promise((ok) => setTimeout(ok, o.pollMs ?? 2000))
    }
  }

  // ---- jobs
  async job(name: string): Promise<S.JobView> { return decode(JobReply, await this.json("GET", `/jobs/${this.p(name)}`), "job").job }
  async output(name: string): Promise<S.JobOutput> { return decode(S.JobOutput, await this.json("GET", `/jobs/${this.p(name)}/output`), "output") }
  async cancelJob(name: string): Promise<S.JobView> { return decode(JobReply, await this.json("POST", `/jobs/${this.p(name)}/cancel`), "cancelJob").job }
  async events(after = 0): Promise<ReadonlyArray<S.FloorEvent>> { return decode(EventsReply, await this.json("GET", `/events?after=${after}`), "events").events }

  // ---- capacity and seats
  async capacity(o: { model?: string; minHeadroomPct?: number } = {}): Promise<S.CapacityView> {
    const q = new URLSearchParams()
    if (o.model) q.set("model", o.model)
    if (o.minHeadroomPct !== undefined) q.set("min_headroom_pct", String(o.minHeadroomPct))
    const qs = q.toString()
    return decode(S.CapacityView, await this.json("GET", `/capacity${qs ? `?${qs}` : ""}`), "capacity")
  }
  async admit(seat: string, o: { model?: string } = {}): Promise<Record<string, unknown>> {
    const q = new URLSearchParams({ seat, ...(o.model ? { model: o.model } : {}) })
    return decode(S.AdmitAnswer, await this.json("GET", `/capacity/admit?${q}`), "admit") as Record<string, unknown>
  }
  /** One row per seat: the `seats` view of GET /capacity. */
  async seats(o: { model?: string } = {}): Promise<ReadonlyArray<SeatRow>> {
    const v = await this.capacity(o)
    return v.seats.map((s) => {
      const a = (s.admit ?? {}) as { admit?: unknown; reason?: unknown }
      return { seat: s.seat, grade: s.grade, staleness: s.staleness, headroom_pct: s.headroom_pct, next_reset_at: s.next_reset_at, wip: s.wip,
        admit: typeof a.admit === "boolean" ? a.admit : null, reason: typeof a.reason === "string" ? a.reason : null }
    })
  }

  // ---- pullers (holders)
  async pullers(): Promise<ReadonlyArray<S.Holder>> { return decode(HoldersReply, await this.json("GET", "/holders"), "pullers").holders }
  async pausePuller(holder: string): Promise<{ holder: string; paused: boolean }> { return decode(PauseReply, await this.json("POST", `/holders/${this.p(holder)}/pause`), "pause") }
  async resumePuller(holder: string): Promise<{ holder: string; paused: boolean }> { return decode(PauseReply, await this.json("POST", `/holders/${this.p(holder)}/resume`), "resume") }

  // ---- floor
  async floorState(): Promise<S.FloorState> { return decode(S.FloorState, await this.json("GET", "/floor/state"), "floorState") }
  async openapi(): Promise<Record<string, unknown>> { return await this.json("GET", "/openapi.json") as Record<string, unknown> }
}
