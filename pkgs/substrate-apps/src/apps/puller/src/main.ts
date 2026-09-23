// substrate-puller: a plain long-lived process. Configuration is the [puller] table of
// ~/.config/substrate/config.toml (see deploy/client.config.example.toml); the operator bearer and the per-link
// token are files (mode 600), read once and never logged. Logs are JSON lines on stdout.
//
// Exit codes: 0 stopped on SIGTERM or SIGINT; 3 another puller holds the pidfile; 75 another session holds this
// holder identity (L5); 78 configuration invalid, or the floor refused the token or answered a redirect.
import { homedir } from "node:os"
import { join } from "node:path"
import { ConfigError, clientFromConfig, expandHome, loadClientConfig, readSecretFile } from "@substrate/api"
import { loadRuntimes } from "@substrate/runners"
import { CapacityGate } from "substrate/src/capacity/gate.ts"
import { defaultCapacitySource } from "substrate/src/capacity/config.ts"
import { killLiveGroups } from "@substrate/runners"
import { connectFloor } from "./connect.ts"
import { floorExecutor, localExecutor } from "./execute.ts"
import { acquirePidfile, PidfileHeld } from "./pidfile.ts"
import { Puller } from "./puller.ts"
import type { Executor } from "./puller.ts"
import { PullerState } from "./state.ts"

const log = (ev: string, f: Record<string, unknown> = {}) => process.stdout.write(JSON.stringify({ t: new Date().toISOString(), ev, ...f }) + "\n")

export const main = async (env: NodeJS.ProcessEnv = process.env): Promise<number> => {
  let release: (() => void) | undefined
  try {
    const cfg = loadClientConfig(env)
    const p = cfg.puller ?? {}
    if (!p.holder) throw new ConfigError("[puller] holder is required (the holder name its link token is bound to)")
    if (!p.link_token_file) throw new ConfigError("[puller] link_token_file is required")
    if (!cfg.floor_url) throw new ConfigError("floor_url is required")
    const stateDir = expandHome(p.state_dir ?? "~/.local/state/substrate/puller")
    const client = clientFromConfig(cfg)
    const linkToken = readSecretFile(expandHome(p.link_token_file), "[puller] link_token_file")
    release = acquirePidfile(expandHome(p.pidfile ?? join(homedir(), ".local/state/substrate/puller.pid")))
    const state = new PullerState(stateDir)
    let execute: Executor
    if ((p.node_dispatch ?? "local") === "floor") {
      execute = floorExecutor({ client, defaultRunsOn: p.node_runs_on ?? ["seat:halogen", "runtime:gvisor"], defaultModel: p.default_model ?? "claude-opus-5-5", pollMs: 5000 })
    } else {
      if (!p.seat) throw new ConfigError("[puller] seat is required for node_dispatch = \"local\" (the seat the capacity gate reads)")
      const runtimes = loadRuntimes(p.runtimes ? expandHome(p.runtimes) : undefined)
      let capacity: CapacityGate
      try { capacity = new CapacityGate(defaultCapacitySource(), p.seat) } catch (e) { throw new ConfigError(String((e as Error).message)) }
      execute = localExecutor({ runtimes, seat: p.seat, defaultModel: p.default_model ?? "claude-opus-5-5", cap: p.cap ?? 2, capacity, ...(p.ax_server ? { axServer: p.ax_server } : {}) })
    }
    const floor = await connectFloor({ url: cfg.floor_url, token: linkToken, sessionId: state.sessionId() })
    const puller = new Puller({ holder: p.holder, maxRuns: p.max_runs ?? 1, stateDir, pollMs: 5000, heartbeatMs: 10_000 }, { floor: floor.port, client, execute, log })
    let signalled = false
    for (const sig of ["SIGTERM", "SIGINT", "SIGHUP"] as const) process.on(sig, () => {
      if (signalled) { killLiveGroups("SIGKILL"); process.exit(130) }
      signalled = true; log("stop-requested", { signal: sig }); puller.stop()
    })
    log("start", { holder: p.holder, stateDir, nodeDispatch: p.node_dispatch ?? "local", maxRuns: p.max_runs ?? 1, held: Object.keys(puller.held).length })
    try { await puller.run() } finally { await floor.close() }
    log("stopped")
    return 0
  } catch (e) {
    if (e instanceof PidfileHeld) { log("pidfile-held", { pid: e.pid }); return 3 }
    if (e instanceof ConfigError) { log("config-invalid", { why: e.message }); return 78 }
    const kind = (e as { kind?: string })?.kind
    log("fatal", { kind: kind ?? "defect", message: String((e as Error)?.message ?? e) })
    return kind === "session-conflict" ? 75 : kind === "auth" || kind === "redirect" || kind === "misrouted" ? 78 : 1
  } finally { release?.() }
}
