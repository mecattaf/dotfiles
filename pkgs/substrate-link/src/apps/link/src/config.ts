// conwip-link configuration from the environment (round 1, finding "config"). Every numeric key must be a plain
// non-negative integer inside its range and every enum key one of its literals; anything else is ConfigInvalid, which
// main.ts turns into exit 78 so systemd's RestartPreventExitStatus holds the unit down instead of letting it spin
// (Effect.sleep(NaN) is a zero sleep) or crash-loop. Errors name the key and the rule, never the value.

export class ConfigInvalid extends Error {
  readonly _tag = "ConfigInvalid"
  constructor(readonly key: string, readonly why: string) { super(`${key}: ${why}`) }
}

type Env = Readonly<Record<string, string | undefined>>

const str = (env: Env, key: string, d?: string): string => {
  const v = env[key]
  if (v !== undefined && v !== "") return v
  if (d !== undefined) return d
  throw new ConfigInvalid(key, "missing")
}

export const int = (env: Env, key: string, d: number, min: number, max = 1_000_000): number => {
  const v = str(env, key, String(d)).trim()
  if (!/^\d+$/.test(v)) throw new ConfigInvalid(key, "not a non-negative integer")
  const n = Number(v)
  if (n < min || n > max) throw new ConfigInvalid(key, `outside ${min}..${max}`)
  return n
}

export const literal = <const L extends string>(env: Env, key: string, d: L, allowed: ReadonlyArray<L>): L => {
  const v = str(env, key, d)
  if (!(allowed as ReadonlyArray<string>).includes(v)) throw new ConfigInvalid(key, `not one of ${allowed.join(", ")}`)
  return v as L
}

export const seatCommands = (env: Env, key: string, d: string): Record<string, Array<string>> => {
  let parsed: unknown
  try { parsed = JSON.parse(str(env, key, d)) } catch { throw new ConfigInvalid(key, "not JSON") }
  if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) throw new ConfigInvalid(key, "not a JSON object")
  const out: Record<string, Array<string>> = {}
  for (const [seat, cmd] of Object.entries(parsed)) {
    if (!Array.isArray(cmd) || cmd.length === 0 || !cmd.every((c) => typeof c === "string" && c !== ""))
      throw new ConfigInvalid(key, `seat ${JSON.stringify(seat)} is not a non-empty array of non-empty strings`)
    out[seat] = cmd as Array<string>
  }
  return out
}

export interface LinkEnv {
  readonly holder: string
  readonly maxInFlight: number
  readonly servedLabels: Array<string>
  readonly atespace: string
  readonly image: string
  readonly gateway: string
  readonly axServer: string
  readonly guestCompleteUrl: string | undefined
  readonly seatCommands: Record<string, Array<string>>
  readonly completion: "auto" | "p1" | "guest"
  readonly resyncSeconds: number
  readonly pendingTimeoutSeconds: number
  readonly deleteAfterSeconds: number
  readonly deadlineBackstopSeconds: number
  readonly createAttempts: number
  readonly outboxBackoffSeconds: readonly [number, number]
  readonly fenceTimeoutSeconds: number
  readonly resultReadTries: number
  readonly verdictAttempts: number // round 2
  readonly maxOutputBytes: number // round 2: below the floor's 2 MB DO row limit
  readonly internalHosts: Array<string> // round 2: single-label names a guest Complete URL may use
  readonly axProtoPath: string | undefined // round 2: the link's ax proto (must declare GetTaskResult)
}

/** Throws ConfigInvalid on the first bad key. Defaults are the NixOS module's. */
export const readLinkEnv = (env: Env): LinkEnv => {
  const outMin = int(env, "LINK_OUTBOX_BACKOFF_MIN_SECONDS", 60, 1, 86_400)
  const outMax = int(env, "LINK_OUTBOX_BACKOFF_MAX_SECONDS", 900, 1, 86_400)
  if (outMax < outMin) throw new ConfigInvalid("LINK_OUTBOX_BACKOFF_MAX_SECONDS", "below LINK_OUTBOX_BACKOFF_MIN_SECONDS")
  const servedLabels = str(env, "LINK_SERVED_LABELS", "seat:halogen,runtime:gvisor").split(",").map((l) => l.trim()).filter((l) => l !== "")
  if (servedLabels.length === 0) throw new ConfigInvalid("LINK_SERVED_LABELS", "empty")
  return {
    holder: str(env, "LINK_HOLDER", "nas-link-1"),
    maxInFlight: int(env, "LINK_MAX_IN_FLIGHT", 2, 1, 1000),
    servedLabels,
    atespace: str(env, "AX_ATESPACE", "fleet"),
    image: str(env, "LINK_IMAGE", "ax-agent"),
    gateway: str(env, "LINK_GATEWAY", "halogen"),
    axServer: str(env, "AX_SERVER", "10.201.0.80:8080"),
    guestCompleteUrl: env.LINK_GUEST_COMPLETE_URL ? env.LINK_GUEST_COMPLETE_URL : undefined,
    seatCommands: seatCommands(env, "LINK_SEAT_COMMANDS", '{"halogen":["ax-agent","pi"]}'),
    completion: literal(env, "LINK_COMPLETION", "auto", ["auto", "p1", "guest"]),
    resyncSeconds: int(env, "LINK_RESYNC_SECONDS", 15, 1, 3600),
    pendingTimeoutSeconds: int(env, "LINK_PENDING_TIMEOUT_SECONDS", 900, 1, 86_400),
    deleteAfterSeconds: int(env, "LINK_DELETE_AFTER_SECONDS", 600, 0, 604_800),
    deadlineBackstopSeconds: int(env, "LINK_DEADLINE_BACKSTOP_SECONDS", 300, 0, 86_400),
    createAttempts: int(env, "LINK_CREATE_ATTEMPTS", 7, 1, 100),
    outboxBackoffSeconds: [outMin, outMax],
    fenceTimeoutSeconds: int(env, "LINK_FENCE_TIMEOUT_SECONDS", 120, 1, 86_400),
    resultReadTries: int(env, "LINK_RESULT_READ_TRIES", 5, 1, 1000),
    verdictAttempts: int(env, "LINK_VERDICT_ATTEMPTS", 8, 1, 1000),
    maxOutputBytes: int(env, "LINK_MAX_OUTPUT_BYTES", 1_000_000, 1024, 2_000_000),
    internalHosts: (env.LINK_INTERNAL_HOSTS ?? "").split(",").map((h) => h.trim()).filter((h) => h !== ""),
    axProtoPath: env.LINK_AX_PROTO_PATH ? env.LINK_AX_PROTO_PATH : undefined
  }
}
