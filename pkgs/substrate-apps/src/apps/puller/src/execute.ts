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
import { existsSync, readFileSync } from "node:fs"
import { join } from "node:path"
import type { SubstrateClient, AgentJob } from "@substrate/api"
import { FileJournal, parseJournal, runWorkflow } from "@substrate/interpreter"
import type { AgentCall, AgentOutcome, Backend } from "@substrate/interpreter"
import { refusal } from "@substrate/runners"
import type { Runner, RuntimesConfig } from "@substrate/runners"
import type { CapacityGate } from "substrate/src/capacity/gate.ts"
import { runIntegrated } from "substrate/src/integrated.ts"
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
  /** Runner overrides by runtime name (tests). */
  readonly runners?: Readonly<Record<string, Runner>>
}

export const localExecutor = (o: LocalOptions): Executor => async (t) => {
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
    runners: { ...axRunners, ...(o.runners ?? {}) },
    runIdPrefix: `${t.runId}-`,
    signal: t.signal
  })
  return {
    result: run.result.status === "completed" ? "success" : "failure",
    output: {
      runId: t.runId, interpreterRunId: run.runId, resumed: run.resumed, outcome: run.outcome, callCounts: run.callCounts, dispatched: run.dispatched,
      status: run.result.status, result: run.result.result ?? null, error: run.result.error ?? null,
      ...(run.result.status === "completed" ? {} : { reason: "agent/script-failed", message: run.result.error ?? "the workflow failed" })
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
  readonly pollMs?: number
  readonly signal: AbortSignal
}

const sha = (s: string) => createHash("sha256").update(s).digest("hex")
const str = (v: unknown) => (typeof v === "string" && v !== "" ? v : undefined)

/** One agent() call as an AgentJob. The name is fixed by (index, attempt, run), so a resumed call re-enqueues the
 *  same job (idempotent by name) and reads the verdict the floor may already hold. */
export const nodeJob = (call: AgentCall, o: Pick<FloorBackendOptions, "runId" | "workflow" | "defaultRunsOn" | "defaultModel">): AgentJob => {
  const opts = call.opts as Record<string, unknown>
  const runsOn = Array.isArray(opts.runsOn) ? opts.runsOn.map(String)
    : str(opts.seat) || str(opts.runtime) ? [`seat:${str(opts.seat) ?? o.defaultRunsOn.find((l) => l.startsWith("seat:"))?.slice(5) ?? "unknown"}`, ...(str(opts.runtime) ? [`runtime:${str(opts.runtime)}`] : o.defaultRunsOn.filter((l) => !l.startsWith("seat:")))]
    : [...o.defaultRunsOn]
  const digest = sha(call.prompt)
  const w: Record<string, unknown> = { prompt: call.prompt, prompt_ref: { sha256: digest, bytes: Buffer.byteLength(call.prompt), uri: `journal://${o.runId}/${call.index}/prompt.md` }, model: str(opts.model) ?? o.defaultModel }
  if (str(opts.effort)) w.effort = opts.effort
  if (opts.schema !== undefined) w.schema = opts.schema
  if (str(opts.isolation)) w.isolation = opts.isolation
  if (str(opts.agentType)) w["agent-type"] = opts.agentType
  return {
    apiVersion: "ultracode.mecattaf.dev/v1alpha1", kind: "AgentJob",
    metadata: {
      name: `n${call.index}-a${call.attempt}-${o.runId}`.toLowerCase(),
      labels: { [A + "run-id"]: o.runId, [A + "workflow"]: o.workflow.toLowerCase().replace(/[^a-z0-9.-]+/g, "-").slice(0, 63), [A + "kind"]: "agent" },
      annotations: { [A + "run-id-raw"]: o.runId, [A + "journal-key"]: `${call.key}:${call.index}`, ...(call.opts.label ? { [A + "label"]: String(call.opts.label) } : {}), ...(call.phase ? { [A + "phase"]: call.phase } : {}) }
    },
    spec: { "runs-on": runsOn, with: w as AgentJob["spec"]["with"] }
  }
}

/** The verdict as the interpreter's AgentOutcome. A failure is the call's error; the interpreter owns retries. */
export const outcomeOf = (o: { result: string; output: unknown; usage: unknown }, wantObject: boolean): AgentOutcome => {
  const u = o.usage as { prompt_tokens?: number; completion_tokens?: number } | null
  const usage = u && typeof u.prompt_tokens === "number" ? { usage: { inputTokens: u.prompt_tokens, outputTokens: u.completion_tokens ?? 0 } } : {}
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
  async run(call: AgentCall): Promise<AgentOutcome> {
    const job = nodeJob(call, this.o)
    const name = job.metadata.name
    await this.o.client.enqueue(this.o.runId, [job])
    this.enqueued.push(name)
    for (;;) {
      if (this.o.signal.aborted) return new Promise<never>(() => undefined) // in flight at the kill: journaled started-only, as a real kill leaves it
      const v = await this.o.client.job(name)
      if (v.state === "done") return outcomeOf(await this.o.client.output(name), call.opts.schema !== undefined)
      await new Promise((ok) => { const t = setTimeout(ok, this.o.pollMs ?? 2000); this.o.signal.addEventListener("abort", () => { clearTimeout(t); ok(undefined) }, { once: true }) })
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
  const backend = new FloorBackend({ ...o, runId: t.runId, workflow: t.workflowName, signal: t.signal })
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
  return {
    result: r.status === "completed" ? "success" : "failure",
    output: { runId: t.runId, resumed, status: r.status, result: r.result ?? null, error: r.error ?? null, calls: { total: calls.length, done: calls.filter((s) => s === "done").length, cached: calls.filter((s) => s === "cached").length, null: calls.filter((s) => s === "null").length }, enqueued: backend.enqueued.length,
      ...(r.status === "completed" ? {} : { reason: "agent/script-failed", message: r.error ?? "the workflow failed" }) }
  }
}
