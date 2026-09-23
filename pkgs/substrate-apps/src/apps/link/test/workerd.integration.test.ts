// Integration: the link against a REAL floor process and a REAL gRPC ax wire.
//   floor  the option-A prototype Durable Object (../arc/proto/floor, Effect's RpcServer.layerHttp inside a DO, DO
//          SQLite, a storage alarm) served by `wrangler dev --local` on loopback (workerd). Copied to a temp dir first,
//          so nothing is written into the prototype's own tree. It is NOT the floor port (FL1 to FL8 are not in it).
//   ax     a gRPC server on loopback built from the vendored ax.proto plus P1's GetTaskResult (fixtures/ax-p1.proto),
//          with ax's own ListTasks paging (50 rows, newest first) and a Gateway. The link uses its production grpcAx.
// Opt-in: LINK_WORKERD=1, run inside ~/.local/bin/runtime-test (it starts workerd). Skipped otherwise.
import { spawn } from "node:child_process"
import type { ChildProcess } from "node:child_process"
import { createHash } from "node:crypto"
import { cpSync, mkdtempSync, rmSync, symlinkSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import * as grpc from "@grpc/grpc-js"
import * as protoLoader from "@grpc/proto-loader"
import { Deferred, Effect, Exit, Fiber } from "effect"
import { afterAll, beforeAll, describe, expect, it } from "vitest"
import { grpcAx } from "../src/ax.ts"
import type { AgentJob } from "../src/contract.ts"
import { rpcFloor } from "../src/floor.ts"
import { Journal } from "../src/journal.ts"
import { runLink } from "../src/link.ts"
import type { LinkConfig } from "../src/link.ts"

const RUN = process.env.LINK_WORKERD === "1" && (process.env.LINK_PROTO_DIR ?? "") !== ""
// The ARC prototype floor directory (LINK_PROTO_DIR); the test is skipped without it.
const PROTO_DIR = process.env.LINK_PROTO_DIR ?? ""
const P1_PROTO = join(import.meta.dirname, "fixtures", "ax-p1.proto")
const TOKEN = "local-dev-only-not-a-secret" // the prototype's wrangler.jsonc var, a public test value
const PORT = 18000 + Math.floor(Math.random() * 900)
const F = `http://127.0.0.1:${PORT}`
const A = "ultracode.mecattaf.dev/"

const job = (n: string): AgentJob => ({
  apiVersion: "ultracode.mecattaf.dev/v1alpha1", kind: "AgentJob",
  metadata: { name: `wf-int-${n}`, labels: { [A + "workflow"]: "link-int", [A + "phase-index"]: "1" }, annotations: { [A + "run-id-raw"]: "wf_int", [A + "label"]: `int:${n}`, [A + "item-key"]: `wf_int#${n}`, [A + "journal-key"]: `${"cd".repeat(32)}:1`, [A + "phase-title"]: "Integration" } },
  spec: { "runs-on": ["seat:halogen", "runtime:gvisor"], with: { prompt: `say ${n}`, prompt_ref: { sha256: "cd".repeat(32), bytes: 5, uri: `journal://wf_int/${n}/prompt.md` }, model: "halogen-qwen3.8-flash-next" } }
})

// ---------------------------------------------------------------- the ax gRPC server (P1 wire)
const tasks = new Map<string, any>()
const results = new Map<string, Buffer>()
let axUnavailable = false
let axServer: grpc.Server
let axPort = 0
const unavailable = { code: grpc.status.UNAVAILABLE, details: "ax-server unavailable" }
const nf = (what: string) => ({ code: grpc.status.NOT_FOUND, details: `${what} not found` })
const guard = <T>(cb: grpc.sendUnaryData<T>, f: () => void) => axUnavailable ? cb(unavailable) : f()

async function startAx() {
  const def = protoLoader.loadSync(P1_PROTO, { keepCase: false, longs: String, enums: String, defaults: true, oneofs: true })
  const svc = (grpc.loadPackageDefinition(def) as any).ax.v1alpha1.AX.service
  axServer = new grpc.Server()
  axServer.addService(svc, {
    GetTask: (c: any, cb: any) => guard(cb, () => { const t = tasks.get(c.request.name); t ? cb(null, t) : cb(nf(c.request.name)) }),
    UpdateTask: (c: any, cb: any) => guard(cb, () => { tasks.set(c.request.task.metadata.name, { ...c.request.task, status: { phase: "Pending" } }); cb(null, c.request.task) }),
    ListTasks: (c: any, cb: any) => guard(cb, () => { const n = Number(c.request.limit) > 0 ? Number(c.request.limit) : 50, o = Number(c.request.offset) || 0; cb(null, { tasks: [...tasks.values()].reverse().slice(o, o + n) }) }),
    DeleteTask: (c: any, cb: any) => guard(cb, () => { tasks.delete(c.request.name); results.delete(c.request.name); cb(null, {}) }),
    GetGateway: (c: any, cb: any) => guard(cb, () => c.request.name === "halogen"
      ? cb(null, { apiVersion: "ax.io/v1alpha1", kind: "Gateway", metadata: { name: "halogen", atespace: "fleet" }, spec: { egress: { allowlist: { hosts: [{ host: "worker", port: 8731 }] } } } })
      : cb(nf("gateway"))),
    GetTaskResult: (c: any, cb: any) => guard(cb, () => { const b = results.get(c.request.name); b ? cb(null, { content: b, sha256: createHash("sha256").update(b).digest("hex") }) : cb(nf("result")) })
  })
  axPort = await new Promise<number>((res, rej) => axServer.bindAsync("127.0.0.1:0", grpc.ServerCredentials.createInsecure(), (e, p) => e ? rej(e) : res(p)))
}
const run = (name: string) => { tasks.get(name).status = { phase: "Running" } }
const finish = (name: string, out: unknown) => {
  results.set(name, Buffer.from(JSON.stringify(out)))
  tasks.get(name).status = { phase: "Completed", usage: { promptTokens: 5, completionTokens: 3, toolCalls: 1 }, conditions: [{ type: "Ready", status: "False", reason: "CommandExited", message: "ExitCode=0" }] }
}

// ---------------------------------------------------------------- the floor under wrangler dev --local
let work = "", wrangler: ChildProcess | undefined
const floorLog: Array<string> = []
async function floorUp() {
  wrangler = spawn("wrangler", ["dev", "--local", "--ip", "127.0.0.1", "--port", String(PORT), "--persist-to", join(work, "state"),
    "--var", "LEASE_SECONDS:30", "--show-interactive-dev-session=false"],
    { cwd: join(work, "floor"), env: { ...process.env, WRANGLER_SEND_METRICS: "false", CI: "1" }, detached: true, stdio: ["ignore", "pipe", "pipe"] })
  wrangler.stdout!.on("data", (d) => floorLog.push(String(d)))
  wrangler.stderr!.on("data", (d) => floorLog.push(String(d)))
  await until("floor up", async () => (await admin("GET", "/admin/state").catch(() => undefined)) !== undefined, 60_000)
}
async function floorDown() {
  if (wrangler?.pid) { try { process.kill(-wrangler.pid, "SIGTERM") } catch { /* gone */ } }
  await until("floor down", async () => (await admin("GET", "/admin/state").catch(() => undefined)) === undefined, 20_000)
}
async function admin(method: string, path: string, body?: unknown): Promise<any> {
  const r = await fetch(F + path, { method, headers: { authorization: `Bearer ${TOKEN}`, "content-type": "application/json" }, ...(body ? { body: JSON.stringify(body) } : {}), signal: AbortSignal.timeout(3000) })
  if (!r.ok) throw new Error(`admin ${path}: ${r.status}`)
  return r.json()
}
const jobRow = async (n: string) => ((await admin("GET", "/admin/state")).jobs as Array<any>).find((j) => j.name === `wf-int-${n}`)

async function until(what: string, pred: () => boolean | Promise<boolean>, ms = 30_000) {
  const t0 = Date.now()
  while (!(await pred())) { if (Date.now() - t0 > ms) throw new Error(`timeout waiting for: ${what}`); await new Promise((r) => setTimeout(r, 100)) }
}
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms))

function startLink(token = TOKEN) {
  const logs: Array<Record<string, unknown>> = []
  const dir = mkdtempSync(join(tmpdir(), "conwip-link-int-"))
  const stop = Effect.runSync(Deferred.make<void>())
  const ax = grpcAx(`127.0.0.1:${axPort}`, "fleet", 5_000, P1_PROTO)
  const cfg: LinkConfig = {
    holder: "nas-link-1", maxInFlight: 2, servedLabels: ["seat:halogen", "runtime:gvisor"],
    shape: { atespace: "fleet", image: "ax-agent", gateway: "halogen", command: () => ["ax-agent", "pi"] },
    completion: "p1", secondMs: 1000, resyncMs: 500, pendingTimeoutMs: 60_000, deleteAfterMs: 0, deadlineBackstopMs: 60_000,
    createAttempts: 3, outboxBackoffMs: [200, 1000], fenceTimeoutMs: 5_000, initialPollSeconds: 1, initialHeartbeatSeconds: 2
  }
  const fiber = Effect.runFork(Effect.scoped(Effect.gen(function*() {
    const floor = yield* rpcFloor({ url: F, token, sessionId: `s:${dir}`, timeoutsMs: { lease: 5_000, heartbeat: 5_000, complete: 10_000 } })
    return yield* runLink(cfg, { ax, floor, journal: Journal.open(dir), log: (ev, f) => logs.push({ ev, ...f }), stop, floorUrl: F })
  })))
  return {
    logs,
    has: (ev: string) => logs.some((l) => l.ev === ev),
    exit: () => Effect.runPromise(Fiber.await(fiber)),
    drain: async () => { Effect.runSync(Deferred.succeed(stop, undefined)); const e = await Effect.runPromise(Fiber.await(fiber)); ax.close(); rmSync(dir, { recursive: true, force: true }); return e }
  }
}

describe.skipIf(!RUN)("link against the prototype floor under wrangler dev --local and a P1 gRPC ax", () => {
  beforeAll(async () => {
    work = mkdtempSync(join(tmpdir(), "conwip-floor-int-"))
    cpSync(join(PROTO_DIR, "floor"), join(work, "floor"), { recursive: true, filter: (s) => !s.includes(".wrangler") })
    cpSync(join(PROTO_DIR, "contract.ts"), join(work, "contract.ts"))
    symlinkSync(join(PROTO_DIR, "node_modules"), join(work, "node_modules"))
    await startAx()
    await floorUp()
  }, 90_000)
  afterAll(async () => {
    await floorDown().catch(() => undefined)
    axServer?.forceShutdown()
    if (process.env.LINK_DEBUG) console.log(floorLog.join("").slice(-4000))
    if (work) rmSync(work, { recursive: true, force: true })
  }, 30_000)

  it("I1 happy path over real HTTP RPC and real gRPC: lease, create-only, P1 result with sha256, Complete, janitor delete", async () => {
    await admin("POST", "/admin/enqueue", job("1"))
    const l = startLink()
    await until("created", () => tasks.has("wf-int-1-a1"))
    expect(tasks.get("wf-int-1-a1").spec.env.find((e: any) => e.name === "AX_CONWIP_PROMPT").value).toBe("say 1")
    run("wf-int-1-a1"); finish("wf-int-1-a1", { answer: 42 })
    await until("floor done", async () => (await jobRow("1"))?.state === "done")
    const r = await jobRow("1")
    expect([r.result, JSON.parse(r.output), JSON.parse(r.usage), r.attempt]).toEqual(["success", { answer: 42 }, { prompt_tokens: 5, completion_tokens: 3, tool_calls: 1 }, 1])
    await until("janitor deleted the Task", () => !tasks.has("wf-int-1-a1"))
    expect(l.has("completion-probe") && l.has("gateway-ok")).toBe(true)
    expect(Exit.isSuccess(await l.drain())).toBe(true)
  }, 60_000)

  it("I2 floor process restarted while a verdict is pending: the outbox keeps it and it lands once, attempt 1", async () => {
    await admin("POST", "/admin/enqueue", job("2"))
    const l = startLink()
    await until("created", () => tasks.has("wf-int-2-a1"))
    run("wf-int-2-a1")
    await floorDown()
    finish("wf-int-2-a1", { restarted: true })
    await until("outbox keeps", () => l.has("outbox-keep"))
    await floorUp() // same --persist-to: the DO's SQLite and alarm survive
    await until("floor done", async () => (await jobRow("2"))?.state === "done", 45_000)
    const r = await jobRow("2")
    expect([r.result, JSON.parse(r.output), r.attempt, r.transitions]).toEqual(["success", { restarted: true }, 1, 0])
    expect(Exit.isSuccess(await l.drain())).toBe(true)
  }, 120_000)

  it("I3 ax answers UNAVAILABLE: every Lease asks for 0, the job stays queued; ax returns and the job runs", async () => {
    axUnavailable = true
    const l = startLink()
    await sleep(1_500) // the start-up resync fails; nothing is probed, capacity stays 0
    expect(l.has("completion-probe")).toBe(false)
    await admin("POST", "/admin/enqueue", job("3"))
    await sleep(6_000) // three polls at the floor's 2 s
    expect((await jobRow("3")).state).toBe("queued")
    axUnavailable = false
    await until("created", () => tasks.has("wf-int-3-a1"))
    run("wf-int-3-a1"); finish("wf-int-3-a1", { back: true })
    await until("floor done", async () => (await jobRow("3"))?.state === "done")
    expect((await jobRow("3")).result).toBe("success")
    expect(Exit.isSuccess(await l.drain())).toBe(true)
  }, 60_000)

  it("I4 the real Worker entry answers 401 to a wrong bearer: the link stops with kind auth (exit 78 in main)", async () => {
    const l = startLink("not-the-token")
    const exit = await l.exit()
    expect(Exit.isFailure(exit)).toBe(true)
    expect(JSON.stringify(exit)).toContain("\"kind\":\"auth\"")
    await l.drain()
  }, 30_000)
})
