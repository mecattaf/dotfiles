// conwip-link: the NAS-side process. Configuration is environment only (the NixOS module sets it); the bearer is a
// file under $CREDENTIALS_DIRECTORY (systemd LoadCredential from the agenix secret), read once and never logged.
// Exit codes: 0 drained on SIGTERM; 75 another session holds this identity (L5), or an allowed endpoint switch (B18)
// was persisted and the unit should restart onto it; 78 the floor refused the token, answered a redirect (round 2), or
// the configuration is invalid.
import { randomUUID } from "node:crypto"
import { existsSync, readFileSync, writeFileSync } from "node:fs"
import { join } from "node:path"
import { Deferred, Effect } from "effect"
import { grpcAx } from "./ax.ts"
import { ConfigInvalid, readLinkEnv } from "./config.ts"
import type { LinkEnv } from "./config.ts"
import { rpcFloor } from "./floor.ts"
import { seatOf } from "./jobs.ts"
import { Journal } from "./journal.ts"
import { runLink } from "./link.ts"

const env = (k: string, d?: string) => {
  const v = process.env[k]
  if (v !== undefined && v !== "") return v
  if (d !== undefined) return d
  console.error(JSON.stringify({ ev: "config-missing", key: k }))
  process.exit(78)
}
const log = (ev: string, f: Record<string, unknown> = {}) => console.log(JSON.stringify({ t: new Date().toISOString(), ev, ...f }))
// Round 1: every numeric and enum key is validated up front; a bad one is exit 78 naming the key, never the value.
let c: LinkEnv
try { c = readLinkEnv(process.env) } catch (e) {
  if (e instanceof ConfigInvalid) { console.error(JSON.stringify({ ev: "config-invalid", key: e.key, why: e.why })); process.exit(78) }
  throw e
}

const stateDir = env("LINK_STATE_DIR", process.env.STATE_DIRECTORY ?? "/var/lib/conwip-link")
const tokenPath = env("LINK_TOKEN_FILE", join(process.env.CREDENTIALS_DIRECTORY ?? "/nonexistent", "floor-link-token"))
if (!existsSync(tokenPath)) { log("token-missing", { path: tokenPath }); process.exit(78) }
const token = readFileSync(tokenPath, "utf8").trim()
const sessionPath = join(stateDir, "session-id") // stable across restarts of this unit, distinct for a second replica
const journal = Journal.open(stateDir)
if (!existsSync(sessionPath)) writeFileSync(sessionPath, randomUUID() + "\n", { mode: 0o600 })
const sessionId = readFileSync(sessionPath, "utf8").trim()

// B18: the floor URLs this link may use, declared in Nix. A switch the floor asked for is persisted here and used on
// the next start only while it is still in the declared list.
const declaredUrl = env("LINK_FLOOR_URL")
const floorUrls = (process.env.LINK_FLOOR_URLS ?? declaredUrl).split(",").map((u) => u.trim()).filter((u) => u !== "")
const endpointPath = join(stateDir, "floor-endpoint")
const persisted = existsSync(endpointPath) ? readFileSync(endpointPath, "utf8").trim() : ""
const floorUrl = persisted !== "" && floorUrls.includes(persisted) ? persisted : declaredUrl
let restartForEndpoint = false

// Round 2: the link loads its own P1 proto (apps/link/proto/ax-p1.proto), never the stock one: with the stock proto
// GetTaskResult is answered "unimplemented" locally and completion auto/p1 would lease nothing for ever.
let ax: ReturnType<typeof grpcAx>
try { ax = grpcAx(c.axServer, c.atespace, undefined, c.axProtoPath) } catch (e) {
  console.error(JSON.stringify({ ev: "config-invalid", key: "LINK_AX_PROTO_PATH", why: String((e as Error)?.message ?? e).slice(0, 200) }))
  process.exit(78)
}
const program = Effect.gen(function*() {
  const stop = yield* Deferred.make<void>()
  for (const sig of ["SIGTERM", "SIGINT"] as const)
    process.once(sig, () => { log("stop-requested", { signal: sig }); Effect.runFork(Deferred.succeed(stop, undefined)) })
  const floor = yield* rpcFloor({ url: floorUrl, token, sessionId })
  yield* runLink({
    holder: c.holder,
    maxInFlight: c.maxInFlight,
    servedLabels: c.servedLabels,
    shape: {
      atespace: c.atespace,
      image: c.image,
      gateway: c.gateway,
      command: (job) => { const seat = seatOf(job); return seat === undefined ? undefined : c.seatCommands[seat] }, // B7: no default seat
      ...(c.guestCompleteUrl !== undefined ? { completeUrl: c.guestCompleteUrl } : {})
    },
    completion: c.completion,
    secondMs: 1000,
    resyncMs: c.resyncSeconds * 1000,
    pendingTimeoutMs: c.pendingTimeoutSeconds * 1000,
    deleteAfterMs: c.deleteAfterSeconds * 1000,
    deadlineBackstopMs: c.deadlineBackstopSeconds * 1000,
    createAttempts: c.createAttempts,
    outboxBackoffMs: [c.outboxBackoffSeconds[0] * 1000, c.outboxBackoffSeconds[1] * 1000],
    fenceTimeoutMs: c.fenceTimeoutSeconds * 1000,
    resultReadTries: c.resultReadTries,
    verdictAttempts: c.verdictAttempts,
    maxOutputBytes: c.maxOutputBytes,
    internalHosts: c.internalHosts,
    floorUrls
  }, {
    ax, floor, journal, log, stop, floorUrl,
    onEndpoint: (url) => { // B18: persist, drain, exit 75 so systemd restarts onto the new URL
      writeFileSync(endpointPath, url + "\n", { mode: 0o600 })
      restartForEndpoint = true
      Effect.runFork(Deferred.succeed(stop, undefined))
    }
  })
})

Effect.runPromise(Effect.scoped(program)).then(
  () => { ax.close(); process.exit(restartForEndpoint ? 75 : 0) },
  (e) => {
    ax.close()
    const kind = (e as { kind?: string })?.kind
    log("fatal", { kind: kind ?? "defect", message: String((e as { message?: string })?.message ?? e) })
    process.exit(kind === "session-conflict" ? 75 : kind === "auth" || kind === "redirect" || kind === "misrouted" ? 78 : 1)
  })
