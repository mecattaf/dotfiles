// The link's view of ax: five calls over plain gRPC (h2c), no CreateTask (ax has none; UpdateTask is an upsert, so
// the link only ever calls it after GetTask answered NotFound: decision L4, create-only).
// ListTasks is paged: ax-server answers limit 0 with 50 rows, newest first (MEASURED upstream
// internal/server/server.go:91-104), so `listAll` walks pages until a short one (B1, critique C1).
import { createHash } from "node:crypto"
import { isIPv4, isIPv6 } from "node:net"
import { dirname, resolve } from "node:path"
import { fileURLToPath } from "node:url"
import * as grpc from "@grpc/grpc-js"
import * as protoLoader from "@grpc/proto-loader"
import { Effect } from "effect"
import type { AxTask } from "./contract.ts"

export class AxError {
  readonly _tag = "AxError"
  constructor(readonly code: number, readonly message: string) {}
  get unavailable() { return this.code === grpc.status.UNAVAILABLE || this.code === grpc.status.DEADLINE_EXCEEDED || this.code === grpc.status.INTERNAL }
  get resourceExhausted() { return this.code === grpc.status.RESOURCE_EXHAUSTED }
}
export const AX_PAGE = 50 // ax-server's own default page size

export interface Condition { readonly type?: string; readonly status?: string; readonly reason?: string; readonly message?: string }
export interface AxObserved {
  readonly name: string
  readonly phase: string // "" and Pending before the controller acts; Running; Completed/Failed (P1); Terminating
  readonly spec: { image?: string; command?: ReadonlyArray<string>; env?: ReadonlyArray<{ name?: string; value?: string }>; gateway?: { name?: string } | null }
  readonly conditions: ReadonlyArray<Condition>
  readonly usage?: { readonly promptTokens?: number; readonly completionTokens?: number; readonly toolCalls?: number } | null
}
/** `digestOk` is false when the server's sha256 does not match the bytes received, undefined when it sent none (B4). */
export interface AxResult { readonly content: string; readonly sha256: string; readonly digestOk?: boolean }
/** A Gateway's egress, as ax applies it (MEASURED upstream internal/controller/reconciler.go:188-198 and
 *  internal/substrate/client.go:450-462): no egress or no allowlist means `*:443`, an empty host list applies no
 *  policy, and a `*` or `0.0.0.0/0` host allows everything. */
export interface AxGateway { readonly hosts: ReadonlyArray<{ readonly host: string; readonly port: number }>; readonly hasAllowlist: boolean }
/** Round 2: ax sends every host containing "/" to Substrate as a CIDR rule (MEASURED upstream client.go:456-491), so an
 *  allowlist can be open by arithmetic (`::/0`, `0.0.0.0/1` + `128.0.0.0/1`). Fail closed: a CIDR that does not parse,
 *  or one at or wider than /8 (IPv4) or /16 (IPv6), counts as open. */
export const cidrIsOpen = (host: string): boolean => {
  const [addr = "", len, ...rest] = host.split("/")
  if (rest.length > 0 || len === undefined || !/^\d{1,3}$/.test(len)) return true
  const n = Number(len)
  if (isIPv4(addr)) return n > 32 || n <= 8
  if (isIPv6(addr)) return n > 128 || n <= 16
  return true
}
export const gatewayAllowsAll = (g: AxGateway) =>
  !g.hasAllowlist || g.hosts.length === 0 || g.hosts.some((x) => {
    const h = x.host.trim().toLowerCase()
    return h === "*" || h === "" || (h.includes("/") && cidrIsOpen(h))
  })

/** Round 2: the link's own runtime proto, P1 included (see its header). `LINK_AX_PROTO_PATH` overrides it. */
export const LINK_PROTO_PATH = resolve(dirname(fileURLToPath(import.meta.url)), "..", "proto", "ax-p1.proto")

export interface AxApi {
  readonly getTask: (name: string) => Effect.Effect<AxObserved | undefined, AxError> // NotFound -> undefined
  readonly createTask: (task: AxTask) => Effect.Effect<void, AxError> // UpdateTask, called only after NotFound
  /** One page of the executor's list (Buildkite informer); `limit` 0 means the server's 50. */
  readonly listTasks: (limit: number, offset: number) => Effect.Effect<ReadonlyArray<AxObserved>, AxError>
  readonly getGateway: (name: string) => Effect.Effect<AxGateway | undefined, AxError> // NotFound -> undefined
  readonly deleteTask: (name: string) => Effect.Effect<void, AxError> // NotFound counts as done
  /** P1's GetTaskResult. `unimplemented` means the server predates P1 (stock v0.3.0): completion is the guest's (L7). */
  readonly getTaskResult: (name: string) => Effect.Effect<AxResult | "unimplemented" | undefined, AxError>
}

/** Every page, until a short one. Rows can shift between pages while ax inserts or deletes; the link therefore
 *  confirms any "absent" Task with GetTask before acting on it (B1). */
export const listAll = (ax: AxApi, page = AX_PAGE, maxPages = 400): Effect.Effect<ReadonlyArray<AxObserved>, AxError> => Effect.gen(function*() {
  const out = new Map<string, AxObserved>()
  for (let i = 0; i < maxPages; i++) {
    const rows = yield* ax.listTasks(page, i * page)
    for (const t of rows) out.set(t.name, t)
    if (rows.length < page) return [...out.values()]
  }
  return yield* Effect.fail(new AxError(grpc.status.OUT_OF_RANGE, `more than ${maxPages * page} Tasks in the atespace`))
})

const observe = (t: any): AxObserved => ({
  name: t?.metadata?.name ?? "",
  phase: t?.status?.phase ?? "",
  spec: t?.spec ?? {},
  conditions: t?.status?.conditions ?? [],
  usage: t?.status?.usage ?? null
})

/** The production AxApi: `address` is ax-server's `host:port` (the ClusterIP 10.201.0.80:8080 on the NAS). */
export function grpcAx(address: string, atespace: string, deadlineMs = 10_000, protoPath: string = LINK_PROTO_PATH): AxApi & { close: () => void } {
  const def = protoLoader.loadSync(protoPath, { keepCase: false, longs: String, enums: String, defaults: true, oneofs: true })
  const Ctor = (grpc.loadPackageDefinition(def) as any).ax?.v1alpha1?.AX
  if (typeof Ctor !== "function") throw new Error(`ax.v1alpha1.AX not found in ${protoPath}`)
  // Round 2: a proto without GetTaskResult would answer the P1 probe "unimplemented" locally, never asking the server
  if (typeof Ctor.prototype?.GetTaskResult !== "function") throw new Error(`${protoPath} declares no GetTaskResult; the link needs its P1 proto`)
  const client = new Ctor(address, grpc.credentials.createInsecure())
  const unary = <T>(method: string, req: unknown) => Effect.callback<T, AxError>((resume) => {
    if (typeof client[method] !== "function") return resume(Effect.fail(new AxError(grpc.status.UNIMPLEMENTED, `${method} not in proto`)))
    client[method](req, { deadline: new Date(Date.now() + deadlineMs) }, (err: grpc.ServiceError | null, res: T) =>
      resume(err ? Effect.fail(new AxError(err.code ?? grpc.status.UNKNOWN, err.details ?? err.message)) : Effect.succeed(res)))
  })
  const notFound = <A>(e: Effect.Effect<A, AxError>, dflt: A) =>
    e.pipe(Effect.catchIf((x: AxError) => x.code === grpc.status.NOT_FOUND, () => Effect.succeed(dflt)))
  return {
    getTask: (name) => notFound(unary<any>("GetTask", { atespace, name }).pipe(Effect.map(observe)), undefined),
    createTask: (task) => unary<any>("UpdateTask", { task }).pipe(Effect.asVoid),
    listTasks: (limit, offset) => unary<any>("ListTasks", { atespace, limit, offset }).pipe(Effect.map((r) => (r?.tasks ?? []).map(observe))),
    getGateway: (name) => notFound(unary<any>("GetGateway", { atespace, name }).pipe(Effect.map((g): AxGateway => {
      const al = g?.spec?.egress?.allowlist
      return { hasAllowlist: al != null, hosts: (al?.hosts ?? []).map((h: any) => ({ host: String(h?.host ?? ""), port: Number(h?.port ?? 0) })) }
    })), undefined),
    deleteTask: (name) => notFound(unary<any>("DeleteTask", { atespace, name }).pipe(Effect.asVoid), undefined),
    getTaskResult: (name) => notFound(unary<any>("GetTaskResult", { atespace, name }).pipe(
      Effect.map((r): AxResult => {
        const bytes = Buffer.from(r?.content ?? "")
        const sha256 = String(r?.sha256 ?? "")
        return { content: bytes.toString("utf8"), sha256, ...(sha256 ? { digestOk: createHash("sha256").update(bytes).digest("hex") === sha256.toLowerCase() } : {}) }
      }),
      Effect.catchIf((x: AxError) => x.code === grpc.status.UNIMPLEMENTED, () => Effect.succeed("unimplemented" as const))
    ), undefined),
    close: () => client.close()
  }
}
