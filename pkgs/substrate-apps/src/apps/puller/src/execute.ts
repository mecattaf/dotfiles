// What a leased run becomes. Two executors, one contract (puller.ts Executor):
//
//   local  the interpreter with the repo's runners on this host (src/integrated.ts runIntegrated): host,
//          runtime-test, herdr, gvisor, ssh:worker for pi on Halogen, microvm, workerd, as runtimes.toml names them.
//          The run directory is the puller's runs/<runId>/, so a second attempt resumes from the first one's journal.
//          An ax runtime is refused with the reason: ax Tasks are rendered and dispatched by the link on the NAS,
//          which this host is not; use node_dispatch = "floor" to send nodes there.
//   floor  the interpreter here, every agent() node back to the floor as an AgentJob (POST /runs/:id/jobs), leased
//          by whichever link serves its runs-on labels (the NAS link renders and dispatches it to ax) and read back
//          from GET /jobs/:name/output. The journal stays here, so resume works the same way.
import { createHash } from "node:crypto"
import { connect } from "node:net"
import { existsSync, lstatSync, mkdirSync, readdirSync, readFileSync, utimesSync, writeFileSync } from "node:fs"
import { join } from "node:path"
import type { SubstrateClient, AgentJob } from "@substrate/api"
import { FileJournal, parseJournal, runWorkflow } from "@substrate/interpreter"
import type { AgentCall, AgentOutcome, Backend } from "@substrate/interpreter"
import { lookupRuntime, refusal, seatOf, seatShadowRoot, transcriptRootFor } from "@substrate/runners"
import type { Runner, RuntimesConfig } from "@substrate/runners"
import type { CapacityGate } from "substrate/src/capacity/gate.ts"
import { runIntegrated } from "substrate/src/integrated.ts"
import { runOutcome } from "substrate/src/run-outcome.ts"
import { Aborted, raceAbort, transient } from "./puller.ts"
import type { Executor, RunVerdict } from "./puller.ts"

const A = "ultracode.mecattaf.dev/"

/** Can a TCP connection to host:port open within the timeout? */
export const reachable = (hostPort: string, timeoutMs = 1500): Promise<boolean> => new Promise((ok) => {
  const i = hostPort.lastIndexOf(":")
  const s = connect({ host: hostPort.slice(0, i), port: Number(hostPort.slice(i + 1)) })
  const t = setTimeout(() => { s.destroy(); ok(false) }, timeoutMs)
  s.once("connect", () => { clearTimeout(t); s.destroy(); ok(true) })
  s.once("error", () => { clearTimeout(t); ok(false) })
})

export const axRefusal = (axServer: string | undefined, isReachable: boolean | undefined): string =>
  `ax runtime: this puller does not dispatch ax Tasks; the NAS link renders and dispatches them (create-only, durable verdict outbox). ` +
  (axServer === undefined ? "No ax_server is configured here. " : isReachable ? `ax-server ${axServer} is reachable, but dispatch from the coordinator is not its path. ` : `ax-server ${axServer} is not reachable. `) +
  `Run with node_dispatch = "floor" so the node is enqueued for the link that serves its runs-on labels.`

export interface LocalOptions {
  readonly runtimes: RuntimesConfig
  readonly seat: string
  readonly defaultModel: string
  readonly cap: number
  readonly capacity?: CapacityGate
  readonly concurrency?: number
  readonly maxAttempts?: number
  readonly axServer?: string
  /**
   * The capacity pusher's demand dir (apps/pusher --demand-dir). While a run executes, a marker there is touched
   * every minute, so the pusher reads at its active cadence (300 s), inside the gate's dispatch bound (360 s).
   * Without it an idle pusher reads every 900 s and the first node after a quiet spell is refused as stale.
   */
  readonly demandDir?: string
  /** How long a node waits for capacity before it fails (the CONWIP's capacityWait). Default: no wait. */
  readonly capacityWait?: { readonly delayMs: number; readonly maxWaitMs: number }
  /** Runner overrides by runtime name (tests). */
  readonly runners?: Readonly<Record<string, Runner>>
  /**
   * AUDIT-transcripts TX2 for local runs: after the run and before its verdict, every node's archived transcript
   * (runners' transcript root, <runId>/<jobId>/<file>) is uploaded to the floor under the run's own job, one part
   * per file named `<jobId>__<file>`. Best effort: a failure is named in the verdict, never fails the run; the local
   * archive stays the long-term copy.
   */
  readonly transcripts?: { readonly client: Pick<SubstrateClient, "uploadTranscript">; readonly root?: string; readonly maxBytes?: number }
}

export interface TranscriptUpload { readonly uploaded: number; readonly bytes: number; readonly skipped: ReadonlyArray<string>; readonly failed: ReadonlyArray<{ part: string; error: string }> }

/** A floor part name for one archived file: one segment of [A-Za-z0-9_.-], at most 200 characters. */
export const transcriptPartName = (jobId: string, file: string): string => {
  const p = `${jobId}__${file}`.replace(/[^A-Za-z0-9_.-]/g, "_").replace(/^[^A-Za-z0-9_]/, "_")
  return p.length <= 200 ? p : `${p.slice(0, 120)}~${p.slice(p.length - 79)}`
}

/** Upload `<dir>/<jobId>/<file>` (regular files only, never through a link) under job `name`, up to `maxBytes`. */
export const uploadRunTranscripts = async (client: Pick<SubstrateClient, "uploadTranscript">, name: string, dir: string, maxBytes = 30_000_000): Promise<TranscriptUpload> => {
  const files: Array<{ part: string; path: string; size: number }> = []
  const ls = (d: string) => { try { return readdirSync(d).sort() } catch { return [] } }
  for (const job of ls(dir)) {
    const jd = join(dir, job)
    if (!lstatSync(jd).isDirectory()) continue
    for (const f of ls(jd)) {
      const st = lstatSync(join(jd, f))
      if (st.isFile()) files.push({ part: transcriptPartName(job, f), path: join(jd, f), size: st.size })
    }
  }
  let bytes = 0, uploaded = 0
  const skipped: Array<string> = [], failed: Array<{ part: string; error: string }> = []
  for (const f of files) {
    if (bytes + f.size > maxBytes) { skipped.push(f.part); continue }
    try {
      const r = await client.uploadTranscript(name, f.part, readFileSync(f.path, "utf8"))
      bytes += r.bytes; uploaded++
    } catch (e) {
      failed.push({ part: f.part, error: String((e as Error).message ?? e).slice(0, 200) })
    }
  }
  return { uploaded, bytes, skipped, failed }
}

/** Touch `<dir>/<name>` now; never throws (demand is a hint, never a reason to fail a run). */
export const touchDemand = (dir: string, name: string): void => {
  try {
    mkdirSync(dir, { recursive: true })
    const f = join(dir, name)
    if (existsSync(f)) { const now = new Date(); utimesSync(f, now, now) } else writeFileSync(f, "")
  } catch { /* a hint only */ }
}

export const localExecutor = (o: LocalOptions): Executor => async (t) => {
  let demand: ReturnType<typeof setInterval> | undefined
  if (o.demandDir !== undefined) {
    const dir = o.demandDir
    touchDemand(dir, "substrate-puller")
    demand = setInterval(() => touchDemand(dir, "substrate-puller"), 60_000)
  }
  try { return await runLocal(o, t) } finally { if (demand !== undefined) clearInterval(demand) }
}

const runLocal = async (o: LocalOptions, t: Parameters<Executor>[0]): ReturnType<Executor> => {
  const axNames = Object.entries(o.runtimes.runtimes).filter(([, r]) => r.type === "ax").map(([n]) => n)
  const up = axNames.length > 0 && o.axServer !== undefined ? await reachable(o.axServer) : undefined
  const why = axRefusal(o.axServer, up)
  const axRunners = Object.fromEntries(axNames.map((n): [string, Runner] => [n, { name: n, type: "ax", refuses: () => why, run: async (job) => refusal(n, job, why) }]))
  const run = await runIntegrated({
    scriptPath: t.scriptPath, dir: t.dir, runtimes: o.runtimes, seat: o.seat, defaultModel: o.defaultModel, cap: o.cap,
    ...(t.args !== undefined ? { args: t.args } : {}),
    ...(o.capacity ? { capacity: o.capacity } : {}),
    ...(o.concurrency !== undefined ? { concurrency: o.concurrency } : {}),
    ...(o.maxAttempts !== undefined ? { maxAttempts: o.maxAttempts } : {}),
    ...(o.capacityWait !== undefined ? { capacityWait: o.capacityWait } : {}),
    runners: { ...axRunners, ...(o.runners ?? {}) },
    runIdPrefix: `${t.runId}-`,
    signal: t.signal
  })
  let transcripts: TranscriptUpload | undefined
  if (o.transcripts !== undefined) {
    const root = transcriptRootFor(seatShadowRoot(o.runtimes), o.transcripts.root)
    const dir = join(root, run.runId.replace(/[^A-Za-z0-9_.-]/g, "_").slice(0, 128))
    try { transcripts = await uploadRunTranscripts(o.transcripts.client, t.job.metadata.name, dir, o.transcripts.maxBytes) } catch (e) {
      transcripts = { uploaded: 0, bytes: 0, skipped: [], failed: [{ part: "*", error: String((e as Error).message ?? e).slice(0, 200) }] }
    }
  }
  // codex review 3, C3-9: success is conwip-run's exit 0 (every call done or cached), not "the script returned":
  // a refused, failed or nulled call makes the run partial, all-failed or refused, and the verdict says failure
  const ok = run.exitCode === 0
  return {
    result: ok ? "success" : "failure",
    output: {
      runId: t.runId, interpreterRunId: run.runId, resumed: run.resumed, outcome: run.outcome, callCounts: run.callCounts, dispatched: run.dispatched,
      status: run.result.status, result: run.result.result ?? null, error: run.result.error ?? null,
      ...(transcripts !== undefined ? { transcripts } : {}),
      ...(ok ? {} : { reason: "agent/script-failed", message: run.result.error ?? `the run ended ${run.outcome}` })
    }
  }
}

// ---------------------------------------------------------------- floor dispatch

export interface FloorBackendOptions {
  readonly client: Pick<SubstrateClient, "enqueue" | "job" | "output">
  readonly runId: string
  readonly workflow: string
  /** runs-on for a node that names none (opts.runsOn, or opts.seat and opts.runtime). */
  readonly defaultRunsOn: ReadonlyArray<string>
  readonly defaultModel: string
  /**
   * The puller's runtimes file, when it has one: agent({runtime: X}) is labelled with the seat X's table spends
   * (critique pass 2026-09-24, RG-3: it borrowed node_runs_on's seat, so {runtime:'codex'} became seat:halogen).
   */
  readonly runtimes?: RuntimesConfig
  readonly pollMs?: number
  readonly signal: AbortSignal
}

const sha = (s: string) => createHash("sha256").update(s).digest("hex")
const str = (v: unknown) => (typeof v === "string" && v !== "" ? v : undefined)

/**
 * The call's content identity: `<sha256 hex>:<occurrence>`, from the interpreter's cid (prompt, keyed opts and route,
 * plus the occurrence among identical calls). It does not depend on the order earlier calls were invoked or finished,
 * so a resume that releases a pipeline in another order names the same node (codex review 3, C3-7). It is also the
 * form the NAS link requires of the journal-key annotation (apps/link jobs.ts JOURNAL_KEY).
 */
export const contentKey = (call: AgentCall): string => {
  const m = /^c1:([0-9a-f]{64})#([1-9][0-9]*)$/.exec(call.cid ?? "")
  return m ? `${m[1]}:${m[2]}` : `${sha(`${call.key}\0${call.index}`)}:1`
}

/** One agent() call as an AgentJob. The name is fixed by (content identity, attempt, run), so a resumed call
 *  re-enqueues the same job (idempotent by name) and reads the verdict the floor may already hold. */
export class RouteRefused extends Error {}

/**
 * The seat label a node spends. A named seat is taken as named. A named runtime takes the seat its table spends in the
 * puller's runtimes file; with no file, or a runtime the file cannot bind to a seat, it is refused rather than given
 * node_runs_on's seat, so local and floor dispatch never disagree on what a node spends (RG-3).
 */
const seatLabelFor = (opts: Record<string, unknown>, o: Pick<FloorBackendOptions, "defaultRunsOn" | "runtimes">): string => {
  const seat = str(opts.seat), runtime = str(opts.runtime)
  if (runtime !== undefined) {
    const r = o.runtimes !== undefined ? lookupRuntime(o.runtimes, runtime) : undefined
    const spends = r !== undefined && o.runtimes !== undefined ? seatOf(o.runtimes, r) : undefined
    if (seat !== undefined) {
      if (spends !== undefined && spends !== seat) throw new RouteRefused(`agent({runtime: ${runtime}, seat: ${seat}}) refused: runtime ${runtime} spends seat ${spends}`)
      return seat
    }
    if (spends === undefined) throw new RouteRefused(`agent({runtime: ${runtime}}) refused: no seat is resolvable for runtime ${runtime} (${o.runtimes === undefined ? "the puller has no runtimes file" : "its table binds no seat"}); name agent({seat}) or bind one`)
    return spends
  }
  return seat ?? o.defaultRunsOn.find((l) => l.startsWith("seat:"))?.slice(5) ?? "unknown"
}

// Critique pass 2026-09-24 (red team durability-r1-1): nothing in a node's body depends on its invocation index, so a
// resumed run whose calls land in another order re-enqueues the same body under the same name.
export const nodeJob = (call: AgentCall, o: Pick<FloorBackendOptions, "runId" | "workflow" | "defaultRunsOn" | "defaultModel" | "runtimes">): AgentJob => {
  const opts = call.opts as Record<string, unknown>
  const runsOn = Array.isArray(opts.runsOn) ? opts.runsOn.map(String)
    : str(opts.seat) || str(opts.runtime) ? [`seat:${seatLabelFor(opts, o)}`, ...(str(opts.runtime) ? [`runtime:${str(opts.runtime)}`] : o.defaultRunsOn.filter((l) => !l.startsWith("seat:")))]
    : [...o.defaultRunsOn]
  const digest = sha(call.prompt)
  const w: Record<string, unknown> = { prompt: call.prompt, prompt_ref: { sha256: digest, bytes: Buffer.byteLength(call.prompt), uri: `journal://${o.runId}/${contentKey(call)}/prompt.md` }, model: str(opts.model) ?? o.defaultModel }
  if (str(opts.effort)) w.effort = opts.effort
  if (opts.schema !== undefined) w.schema = opts.schema
  if (str(opts.isolation)) w.isolation = opts.isolation
  if (str(opts.agentType)) w["agent-type"] = opts.agentType
  return {
    apiVersion: "ultracode.mecattaf.dev/v1alpha1", kind: "AgentJob",
    metadata: {
      name: `n${contentKey(call).slice(0, 16)}-o${contentKey(call).split(":")[1]}-a${call.attempt}-${o.runId}`.toLowerCase(),
      labels: { [A + "run-id"]: o.runId, [A + "workflow"]: o.workflow.toLowerCase().replace(/[^a-z0-9.-]+/g, "-").slice(0, 63), [A + "kind"]: "agent" },
      annotations: { [A + "run-id-raw"]: o.runId, [A + "journal-key"]: contentKey(call), ...(call.opts.label ? { [A + "label"]: String(call.opts.label) } : {}), ...(call.phase ? { [A + "phase"]: call.phase } : {}) }
    },
    spec: { "runs-on": runsOn, with: w as AgentJob["spec"]["with"] }
  }
}

/** The verdict as the interpreter's AgentOutcome. A failure is the call's error; the interpreter owns retries. */
export const outcomeOf = (o: { result: string; output: unknown; usage: unknown }, wantObject: boolean): AgentOutcome => {
  const u = o.usage as { prompt_tokens?: number; completion_tokens?: number } | null
  // TX3: the harness session id, when the executor reported one, is journaled as the call's agentId
  const sid = (o.output as { sessionId?: unknown } | null)?.sessionId
  const usage = { ...(u && typeof u.prompt_tokens === "number" ? { usage: { inputTokens: u.prompt_tokens, outputTokens: u.completion_tokens ?? 0 } } : {}),
    ...(typeof sid === "string" && sid !== "" ? { agentId: sid } : {}) }
  if (o.result !== "success") {
    const f = (o.output ?? {}) as { reason?: string; message?: string }
    return { error: `${o.result}: ${f.reason ?? "no reason"}${f.message ? `: ${f.message}` : ""}`, ...usage }
  }
  const v = o.output as { object?: unknown; text?: unknown } | string | null
  if (wantObject) return { object: v !== null && typeof v === "object" && "object" in v ? v.object : v, ...usage }
  return { text: typeof v === "string" ? v : v !== null && typeof v === "object" && typeof v.text === "string" ? v.text : JSON.stringify(v), ...usage }
}

export class FloorBackend implements Backend {
  readonly name = "floor"
  readonly enqueued: Array<string> = []
  constructor(readonly o: FloorBackendOptions) {}
  /**
   * After an abort nothing more happens: no enqueue, no read, no answer, so the interpreter journals nothing more and
   * dispatches no continuation (codex review 3, C3-11). The call stays started-only, as a real kill leaves it.
   */
  private parked = <T>(): Promise<T> => new Promise<never>(() => undefined)
  /** One floor request, retried while the run lives when it fails transiently (codex review 3, C3-10). */
  private async req<T>(f: () => Promise<T>): Promise<T> {
    for (let wait = this.o.pollMs ?? 2000; ; wait = Math.min(wait * 2, 30_000)) {
      if (this.o.signal.aborted) return this.parked()
      try { return await raceAbort(f(), this.o.signal) } catch (e) {
        if (e instanceof Aborted || this.o.signal.aborted) return this.parked()
        // the floor refuses nodes for a run that ended or is being cancelled (C2-13): the heartbeat brings the cancel
        // or the loss that aborts this run, so the call waits for it instead of failing the script first
        const code = (e as { code?: unknown })?.code
        if (code === "run-cancelling" || code === "run-done") return this.parked()
        if (!transient(e)) throw e
        await new Promise((ok) => { const t = setTimeout(ok, wait); this.o.signal.addEventListener("abort", () => { clearTimeout(t); ok(undefined) }, { once: true }) })
      }
    }
  }
  async run(call: AgentCall): Promise<AgentOutcome> {
    let job: AgentJob
    try { job = nodeJob(call, this.o) } catch (e) { if (e instanceof RouteRefused) return { error: e.message }; throw e }
    const name = job.metadata.name
    await this.req(() => this.o.client.enqueue(this.o.runId, [job])) // idempotent by name: a lost answer is resent safely
    this.enqueued.push(name)
    for (;;) {
      const v = await this.req(() => this.o.client.job(name))
      if (v.state === "done") { const out = await this.req(() => this.o.client.output(name)); return outcomeOf(out, call.opts.schema !== undefined) }
      await new Promise((ok) => { const t = setTimeout(ok, this.o.pollMs ?? 2000); this.o.signal.addEventListener("abort", () => { clearTimeout(t); ok(undefined) }, { once: true }) })
      if (this.o.signal.aborted) return this.parked()
    }
  }
}

export interface FloorExecOptions extends Omit<FloorBackendOptions, "runId" | "workflow" | "signal"> {
  readonly concurrency?: number
  readonly maxAttempts?: number
  /** Observe each run's backend (tests). */
  readonly onBackend?: (b: FloorBackend) => void
}

export const floorExecutor = (o: FloorExecOptions): Executor => async (t) => {
  // G-BK5: every node is enqueued under this run's live lease, so a fenced or superseded attempt cannot add nodes
  const client = typeof (o.client as { underLease?: unknown }).underLease === "function"
    ? (o.client as unknown as { underLease: (l: string, a: number) => FloorBackendOptions["client"] }).underLease(t.leaseId, t.attempt) : o.client
  const backend = new FloorBackend({ ...o, client, runId: t.runId, workflow: t.workflowName, signal: t.signal })
  o.onBackend?.(backend)
  const journalPath = join(t.dir, "journal.jsonl")
  const resumed = existsSync(journalPath) && readFileSync(journalPath, "utf8").trim() !== ""
  const aborted = new Promise<"aborted">((ok) => { if (t.signal.aborted) ok("aborted"); else t.signal.addEventListener("abort", () => ok("aborted"), { once: true }) })
  const r = await Promise.race([runWorkflow(t.script, {
    backend, runId: `wf_${t.runId}`, scriptPath: t.scriptPath, journal: new FileJournal(journalPath), cacheIdentity: "content", defaultModel: o.defaultModel,
    ...(resumed ? { resumeFrom: parseJournal(readFileSync(journalPath, "utf8")) } : {}),
    ...(t.args !== undefined ? { args: t.args } : {}),
    ...(o.concurrency !== undefined ? { concurrency: o.concurrency } : {}),
    ...(o.maxAttempts !== undefined ? { maxAttempts: o.maxAttempts } : {})
  }), aborted])
  if (r === "aborted") return { result: "cancelled", output: { runId: t.runId, reason: "aborted" } } satisfies RunVerdict
  const calls = r.calls.map((c) => c.state)
  const oc = runOutcome(r.status, r.calls, r.events, r.result) // codex review 3, C3-9: success only when every call is done or cached
  return {
    result: oc.code === 0 ? "success" : "failure",
    output: { runId: t.runId, resumed, status: r.status, result: r.result ?? null, error: r.error ?? null, calls: { total: calls.length, done: calls.filter((s) => s === "done").length, cached: calls.filter((s) => s === "cached").length, null: calls.filter((s) => s === "null").length }, enqueued: backend.enqueued.length,
      outcome: oc.outcome, ...(oc.code === 0 ? {} : { reason: "agent/script-failed", message: r.error ?? `the run ended ${oc.outcome}` }) }
  }
}
