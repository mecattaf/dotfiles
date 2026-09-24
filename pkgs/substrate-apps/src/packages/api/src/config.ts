// The operator config every interface reads: ~/.config/substrate/config.toml (SUBSTRATE_CLIENT_CONFIG overrides the
// path). It names the floor and WHERE the credential is, never the credential itself. Environment overrides:
// SUBSTRATE_URL, SUBSTRATE_TOKEN_FILE. A deployment's own values (domain, paths) live only in that file; the repo
// carries deploy/client.config.example.toml.
import { existsSync, readFileSync, statSync } from "node:fs"
import { homedir } from "node:os"
import { parse } from "smol-toml"
import { SubstrateClient } from "./client.ts"

export interface PullerSection {
  readonly holder?: string
  readonly link_token_file?: string
  readonly state_dir?: string
  readonly runtimes?: string
  readonly max_runs?: number
  readonly seat?: string
  readonly default_model?: string
  readonly cap?: number
  readonly node_dispatch?: "local" | "floor"
  readonly ax_server?: string
  readonly pidfile?: string
  readonly node_runs_on?: ReadonlyArray<string>
  /** The capacity pusher's demand dir: a marker here while a run is held makes the pusher read at its active cadence. */
  readonly demand_dir?: string
  /** How long a node waits for capacity (a stale or refused reading) before it fails, in seconds. Default 600. */
  readonly capacity_wait_s?: number
  /** G-BK4: on the first SIGTERM, how long in-flight runs may finish before they are aborted (with their cancel grace). Default 60; 0 aborts at once. */
  readonly drain_timeout_s?: number
  /** G-BK7: loopback host:port serving GET /status.json and /metrics (Prometheus text). Absent: no endpoint. */
  readonly health_addr?: string
}
export interface ClientConfig {
  readonly floor_url?: string
  readonly token_file?: string
  /** TX4: the read-only bearer (FLOOR_READ_TOKEN) file; `substrate watch` runs on it. */
  readonly read_token_file?: string
  readonly access_client_id_file?: string
  readonly access_client_secret_file?: string
  readonly puller?: PullerSection
  /** Where it was read from, or undefined when no file exists. */
  readonly source?: string
}

export class ConfigError extends Error { override readonly name = "ConfigError" }

export const expandHome = (p: string, home = homedir()) => (p === "~" ? home : p.startsWith("~/") ? home + p.slice(1) : p)
export const DEFAULT_CONFIG_PATH = "~/.config/substrate/config.toml"

export const loadClientConfig = (env: NodeJS.ProcessEnv = process.env, home = homedir()): ClientConfig => {
  const path = expandHome(env.SUBSTRATE_CLIENT_CONFIG ?? DEFAULT_CONFIG_PATH, home)
  let file: Record<string, unknown> = {}
  if (existsSync(path)) {
    try { file = parse(readFileSync(path, "utf8")) as Record<string, unknown> } catch (e) { throw new ConfigError(`${path}: ${(e as Error).message}`) }
  }
  const str = (k: string) => (typeof file[k] === "string" ? (file[k] as string) : undefined)
  const url = env.SUBSTRATE_URL ?? str("floor_url")
  const tokenFile = env.SUBSTRATE_TOKEN_FILE ?? str("token_file")
  const readTokenFile = env.SUBSTRATE_READ_TOKEN_FILE ?? str("read_token_file")
  return {
    ...(readTokenFile !== undefined ? { read_token_file: expandHome(readTokenFile, home) } : {}),
    ...(url !== undefined ? { floor_url: url } : {}),
    ...(tokenFile !== undefined ? { token_file: expandHome(tokenFile, home) } : {}),
    ...(str("access_client_id_file") !== undefined ? { access_client_id_file: expandHome(str("access_client_id_file")!, home) } : {}),
    ...(str("access_client_secret_file") !== undefined ? { access_client_secret_file: expandHome(str("access_client_secret_file")!, home) } : {}),
    ...(typeof file.puller === "object" && file.puller !== null ? { puller: file.puller as PullerSection } : {}),
    ...(existsSync(path) ? { source: path } : {})
  }
}

/** Reads a secret file. Refuses a group- or world-readable one; the value never enters an error message. */
export const readSecretFile = (path: string, what: string): string => {
  if (!existsSync(path)) throw new ConfigError(`${what}: ${path} does not exist`)
  const mode = statSync(path).mode & 0o077
  if (mode !== 0) throw new ConfigError(`${what}: ${path} is readable by group or others (chmod 600 it)`)
  const v = readFileSync(path, "utf8").trim()
  if (v === "") throw new ConfigError(`${what}: ${path} is empty`)
  return v
}

/** TX4: a client on the read-only credential only (never the operator bearer or the Access pair). */
export const readClientFromConfig = (c: ClientConfig, o: { fetch?: typeof globalThis.fetch } = {}): SubstrateClient => {
  if (!c.floor_url) throw new ConfigError("no floor_url")
  if (!c.read_token_file) throw new ConfigError("no read-only credential: set read_token_file (or SUBSTRATE_READ_TOKEN_FILE) to a file holding FLOOR_READ_TOKEN")
  return new SubstrateClient({ url: c.floor_url, token: readSecretFile(c.read_token_file, "read_token_file"), ...(o.fetch ? { fetch: o.fetch } : {}) })
}
export const clientFromConfig = (c: ClientConfig, o: { fetch?: typeof globalThis.fetch; home?: string } = {}): SubstrateClient => {
  if (!c.floor_url) throw new ConfigError(`no floor_url: set it in ${DEFAULT_CONFIG_PATH} or SUBSTRATE_URL`)
  const token = c.token_file ? readSecretFile(c.token_file, "token_file") : undefined
  const access = c.access_client_id_file && c.access_client_secret_file
    ? { clientId: readSecretFile(c.access_client_id_file, "access_client_id_file"), clientSecret: readSecretFile(c.access_client_secret_file, "access_client_secret_file") }
    : undefined
  if (token === undefined && access === undefined) throw new ConfigError("no credential: set token_file (or the Access pair files)")
  return new SubstrateClient({ url: c.floor_url, ...(token ? { token } : {}), ...(access ? { access } : {}), ...(o.fetch ? { fetch: o.fetch } : {}) })
}
