// The production AxApi against a real gRPC server loaded from the vendored ax.proto (v0.3.0 d8ed0fe), on loopback.
// Proves the wire mapping the doubles skip: protojson field names survive UpdateTask, NotFound maps to undefined,
// DeleteTask NotFound is success. Round 2: the link loads its own P1 proto (apps/link/proto/ax-p1.proto), so the
// capability probe is decided by the SERVER: a stock server answers UNIMPLEMENTED over the wire (pre-P1), a P1 server
// answers; a proto without GetTaskResult is refused at construction instead of answering "unimplemented" locally.
import { createHash } from "node:crypto"
import * as grpc from "@grpc/grpc-js"
import * as protoLoader from "@grpc/proto-loader"
import { Effect } from "effect"
import { afterAll, beforeAll, expect, it } from "vitest"
import { resolveProtoPath, VENDORED_PROTO_PATH } from "../../../src/axclient.ts"
import { gatewayAllowsAll, grpcAx, LINK_PROTO_PATH, listAll } from "../src/ax.ts"
import { axTaskFromGrant } from "../src/jobs.ts"

const stored = new Map<string, any>()
const gateways = new Map<string, any>([
  ["halogen", { apiVersion: "ax.io/v1alpha1", kind: "Gateway", metadata: { name: "halogen", atespace: "fleet" }, spec: { egress: { allowlist: { hosts: [{ host: "worker", port: 8731 }] } } } }],
  ["open", { apiVersion: "ax.io/v1alpha1", kind: "Gateway", metadata: { name: "open", atespace: "fleet" }, spec: {} }]
])
let server: grpc.Server, port = 0
const nf = (name: string) => ({ code: grpc.status.NOT_FOUND, details: `task "${name}" not found` })

beforeAll(async () => {
  const def = protoLoader.loadSync(resolveProtoPath(), { keepCase: false, longs: String, enums: String, defaults: true, oneofs: true })
  const svc = (grpc.loadPackageDefinition(def) as any).ax.v1alpha1.AX.service
  server = new grpc.Server()
  const impl: Record<string, grpc.handleUnaryCall<any, any>> = {
    GetTask: (c, cb) => { const t = stored.get(c.request.name); t ? cb(null, t) : cb(nf(c.request.name)) },
    UpdateTask: (c, cb) => { stored.set(c.request.task.metadata.name, { ...c.request.task, status: { phase: "Pending" } }); cb(null, c.request.task) },
    // upstream server.go:91-104: limit <= 0 means 50, newest first (store.go ZRevRange)
    ListTasks: (c, cb) => { const n = Number(c.request.limit) > 0 ? Number(c.request.limit) : 50, o = Number(c.request.offset) || 0; cb(null, { tasks: [...stored.values()].reverse().slice(o, o + n) }) },
    GetGateway: (c, cb) => { const g = gateways.get(c.request.name); g ? cb(null, g) : cb({ code: grpc.status.NOT_FOUND, details: "gateway not found" }) },
    DeleteTask: (c, cb) => stored.delete(c.request.name) ? cb(null, {}) : cb(nf(c.request.name))
  }
  server.addService(svc, impl)
  port = await new Promise<number>((res, rej) => server.bindAsync("127.0.0.1:0", grpc.ServerCredentials.createInsecure(), (e, p) => e ? rej(e) : res(p)))
})
afterAll(() => { server.forceShutdown() })

it("G1 grpcAx speaks ax.proto: create-only round trip, NotFound as undefined, a stock server answers GetTaskResult UNIMPLEMENTED", async () => {
  const ax = grpcAx(`127.0.0.1:${port}`, "fleet", 3000)
  const job = {
    apiVersion: "ultracode.mecattaf.dev/v1alpha1" as const, kind: "AgentJob" as const,
    metadata: { name: "wf-g-1-abababab", annotations: { "ultracode.mecattaf.dev/item-key": "wf_g#1", "ultracode.mecattaf.dev/journal-key": `${"cd".repeat(32)}:1` } },
    spec: { "runs-on": ["seat:halogen"], with: { prompt: "hi", prompt_ref: { sha256: "ab".repeat(32), bytes: 2, uri: "journal://wf_g/1/prompt.md" }, model: "halogen-qwen3.8-flash-next" } }
  }
  const built = axTaskFromGrant({ leaseId: "wf-g-1-abababab-a1", attempt: 1, job, lease: { holderIdentity: "nas-link-1", leaseDurationSeconds: 90, acquireTime: 0, renewTime: 0, leaseTransitions: 0 } },
    { atespace: "fleet", image: "localhost:5000/ax-agent@sha256:00", gateway: "halogen", command: () => ["ax-agent", "pi"] })
  if (built._tag !== "ok") throw new Error(built.reason)
  const run = <A, E>(e: Effect.Effect<A, E>) => Effect.runPromise(e)
  expect(await run(ax.getTask("wf-g-1-abababab-a1"))).toBeUndefined()
  await run(ax.createTask(built.task))
  const back = stored.get("wf-g-1-abababab-a1")
  expect([back.apiVersion, back.metadata.atespace, back.spec.gateway.name, back.spec.command]).toEqual(["ax.io/v1alpha1", "fleet", "halogen", ["ax-agent", "pi"]])
  expect(back.spec.env.find((e: any) => e.name === "AX_CONWIP_ITEM_KEY").value).toBe("wf_g#1")
  const seen = await run(ax.getTask("wf-g-1-abababab-a1"))
  expect(seen?.phase).toBe("Pending")
  expect((await run(ax.listTasks(0, 0))).map((t) => t.name)).toEqual(["wf-g-1-abababab-a1"])
  for (let i = 0; i < 120; i++) stored.set(`bulk-${i}`, { apiVersion: "ax.io/v1alpha1", kind: "Task", metadata: { name: `bulk-${i}`, atespace: "fleet" }, spec: {}, status: { phase: "Completed" } })
  expect((await run(ax.listTasks(0, 0))).length).toBe(50) // B1: one call is one 50-row page
  const all = await run(listAll(ax))
  expect([all.length, all.some((t) => t.name === "wf-g-1-abababab-a1")]).toEqual([121, true])
  for (let i = 0; i < 120; i++) stored.delete(`bulk-${i}`)
  const gw = await run(ax.getGateway("halogen")) // B10 wire mapping
  expect([gw?.hasAllowlist, gw?.hosts, gatewayAllowsAll(gw!)]).toEqual([true, [{ host: "worker", port: 8731 }], false])
  const open = await run(ax.getGateway("open"))
  expect([open?.hasAllowlist, gatewayAllowsAll(open!)]).toEqual([false, true]) // no egress: ax applies *:443
  expect(await run(ax.getGateway("missing"))).toBeUndefined()
  await run(ax.deleteTask("wf-g-1-abababab-a1"))
  await run(ax.deleteTask("wf-g-1-abababab-a1")) // NotFound is success: delete is idempotent for the janitor
  expect(await run(ax.getTaskResult("anything"))).toBe("unimplemented") // v0.3.0 server has no GetTaskResult: pre-P1 mode
  ax.close()
})

it("R2-10 the packaged link (default proto) proves P1 against a P1 server and reads a result; a stock proto is refused", async () => {
  let calls = 0
  const def = protoLoader.loadSync(LINK_PROTO_PATH, { keepCase: false, longs: String, enums: String, defaults: true, oneofs: true })
  const svc = (grpc.loadPackageDefinition(def) as any).ax.v1alpha1.AX.service
  const p1 = new grpc.Server()
  const body = Buffer.from('{"ok":true}')
  p1.addService(svc, {
    GetTaskResult: (c: any, cb: any) => { calls++; c.request.name === "t1" ? cb(null, { content: body, sha256: createHash("sha256").update(body).digest("hex") }) : cb({ code: grpc.status.NOT_FOUND, details: "nf" }) }
  })
  const p1Port = await new Promise<number>((res, rej) => p1.bindAsync("127.0.0.1:0", grpc.ServerCredentials.createInsecure(), (e, p) => e ? rej(e) : res(p)))
  const ax = grpcAx(`127.0.0.1:${p1Port}`, "fleet", 3000) // exactly what main.ts builds when LINK_AX_PROTO_PATH is unset
  expect(await Effect.runPromise(ax.getTaskResult("conwip-link-capability-probe"))).toBeUndefined() // NotFound: P1 present
  expect(await Effect.runPromise(ax.getTaskResult("t1"))).toEqual({ content: '{"ok":true}', sha256: createHash("sha256").update(body).digest("hex"), digestOk: true })
  expect(calls).toBe(2)
  ax.close(); p1.forceShutdown()
  expect(() => grpcAx("127.0.0.1:1", "fleet", 1000, resolveProtoPath({ AX_CONWIP_PROTO_PATH: VENDORED_PROTO_PATH }))).toThrow(/GetTaskResult/)
})
