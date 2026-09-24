#!/usr/bin/env node
// apps/pusher/bin/substrate-pusher.mjs: the gentle capacity pusher, a plain
// long-lived process. It asks the box's capacity oracle (`seats --json`,
// seat-capacity/1) under the repo's refresh policy, converts the answer to
// seat-capacity/2 and posts it to the floor's POST /capacity/snapshots. It
// never calls a provider's usage endpoint itself (src/seatsOracle.mjs,
// src/gentle.mjs).
//
//   substrate-pusher [--config PATH] [--url URL] [--token-file PATH] [options]
//   substrate-pusher --dry-run --once [--seats-json FILE]
//
// Options (each overrides the config file; see apps/pusher/pusher.example.json):
//   --config PATH       default ~/.config/substrate/pusher.json (optional)
//   --url URL           the floor's base URL (config floorUrl)
//   --token-file PATH   the floor's bearer, read from a file, never printed
//                       (config tokenFile; default ~/.local/state/substrate/pusher-token)
//   --seats-bin PATH    the oracle (config seatsBin; default ~/.local/bin/seats)
//   --seats-json FILE   read the oracle's answer from a file instead of running it
//   --peer-cache-dir D  the oracle's peer cache (config peerCacheDir; default
//                       ~/.local/state/substrate/seats-peer-cache; "inherit" keeps
//                       the oracle's own default)
//   --state PATH        default ~/.local/state/substrate/pusher/gentle-state.json
//   --pidfile PATH      default ~/.local/state/substrate/pusher.pid
//   --demand-dir DIR    default ~/.local/state/substrate/demand; a file touched here marks the box active
//   --once              one tick, then exit (the pidfile is still taken and released)
//   --dry-run           read and convert, print the snapshot, post nothing, keep no state
//
// Signals: SIGUSR1 asks for a pre-dispatch read (still never within 120 s of the
// last one); SIGTERM and SIGINT stop the loop and remove the pidfile.
// Exit: 0 stopped cleanly or --once done; 1 a failed --once tick; 2 usage;
// 3 another pusher holds the pidfile.

import { execFile } from "node:child_process"
import { closeSync, existsSync, mkdirSync, openSync, readFileSync, readdirSync, renameSync, statSync, unlinkSync, writeFileSync, writeSync } from "node:fs"
import { homedir } from "node:os"
import { dirname, join } from "node:path"
import { parseArgs } from "node:util"

import { initialGentleState, postSnapshot, tick } from "../src/gentle.mjs"
import { oracleEnv } from "../src/seatsOracle.mjs"
import { tokenFromFile } from "../src/token.mjs"

const home = homedir()
const expand = (p) => (typeof p !== "string" ? p : p === "~" ? home : p.startsWith("~/") ? join(home, p.slice(2)) : p)
const stateDir = join(home, ".local", "state", "substrate")
const fail = (code, message) => {
  process.stderr.write(`substrate-pusher: ${message}\n`)
  process.exit(code)
}

let args
try {
  args = parseArgs({
    options: {
      config: { type: "string" }, url: { type: "string" }, "token-file": { type: "string" },
      "seats-bin": { type: "string" }, "seats-json": { type: "string" }, state: { type: "string" },
      pidfile: { type: "string" }, "demand-dir": { type: "string" }, "peer-cache-dir": { type: "string" },
      once: { type: "boolean", default: false }, "dry-run": { type: "boolean", default: false }
    },
    strict: true
  }).values
} catch (error) {
  fail(2, error.message)
}

const configPath = expand(args.config ?? join(home, ".config", "substrate", "pusher.json"))
let config = {}
if (existsSync(configPath)) {
  try {
    config = JSON.parse(readFileSync(configPath, "utf8"))
  } catch (error) {
    fail(2, `cannot parse the pusher config ${configPath}: ${error.name}`)
  }
} else if (args.config !== undefined) {
  fail(2, `no pusher config at ${configPath}`)
}

const dryRun = args["dry-run"]
const url = args.url ?? config.floorUrl
const tokenFile = expand(args["token-file"] ?? config.tokenFile ?? join(stateDir, "pusher-token"))
const seatsBin = expand(args["seats-bin"] ?? config.seatsBin ?? join(home, ".local", "bin", "seats"))
let seatsEnv
try {
  const peer = args["peer-cache-dir"] ?? config.peerCacheDir
  seatsEnv = oracleEnv({ ...config, peerCacheDir: peer === undefined || peer === "inherit" ? peer : expand(peer) }, stateDir, process.env)
} catch (error) {
  fail(2, error.message)
}
const seatsJson = args["seats-json"] === undefined ? null : expand(args["seats-json"])
const statePath = expand(args.state ?? join(stateDir, "pusher", "gentle-state.json"))
const pidfile = expand(args.pidfile ?? join(stateDir, "pusher.pid"))
const demandDir = expand(args["demand-dir"] ?? join(stateDir, "demand"))
if (!dryRun && (typeof url !== "string" || !/^https?:\/\/[^/]/.test(url))) fail(2, "--url (or floorUrl in the config) must be http(s)://host")

let token = ""
if (!dryRun) {
  try {
    token = tokenFromFile(tokenFile)
  } catch (error) {
    fail(1, error.message)
  }
}

// ---- the pidfile: one pusher per box. A pidfile whose process is gone, or is not a pusher, is stale and replaced.
const alivePusher = (pid) => {
  try {
    process.kill(pid, 0)
  } catch {
    return false
  }
  try {
    return readFileSync(`/proc/${pid}/cmdline`, "utf8").includes("substrate-pusher")
  } catch {
    return true
  }
}
const takePidfile = () => {
  mkdirSync(dirname(pidfile), { recursive: true, mode: 0o700 })
  for (let tries = 0; tries < 2; tries++) {
    try {
      const fd = openSync(pidfile, "wx", 0o600)
      writeSync(fd, `${process.pid}\n`)
      closeSync(fd)
      return
    } catch (error) {
      if (error.code !== "EEXIST") fail(1, `cannot write the pidfile: ${error.code}`)
      const held = Number.parseInt(readFileSync(pidfile, "utf8").trim(), 10)
      if (Number.isInteger(held) && held !== process.pid && alivePusher(held)) fail(3, `another pusher (pid ${held}) holds ${pidfile}`)
      try { unlinkSync(pidfile) } catch { /* raced with its owner's exit */ }
    }
  }
  fail(3, `cannot take ${pidfile}`)
}
const releasePidfile = () => {
  try {
    if (readFileSync(pidfile, "utf8").trim() === String(process.pid)) unlinkSync(pidfile)
  } catch { /* already gone */ }
}

// ---- state, 0600 by atomic rename
const readState = () => {
  try {
    return { ...initialGentleState(), ...JSON.parse(readFileSync(statePath, "utf8")) }
  } catch {
    return initialGentleState()
  }
}
const writeState = (state) => {
  mkdirSync(dirname(statePath), { recursive: true, mode: 0o700 })
  const temporary = `${statePath}.tmp-${process.pid}`
  writeFileSync(temporary, `${JSON.stringify(state)}\n`, { mode: 0o600 })
  renameSync(temporary, statePath)
}

const newestDemandMs = () => {
  try {
    const times = readdirSync(demandDir).map((name) => statSync(join(demandDir, name)).mtimeMs)
    return times.length === 0 ? null : Math.max(...times)
  } catch {
    return null
  }
}

// ---- the oracle: `seats --json --no-spend` (no transcript scan); its own cache and 429 handling stand.
const runOracle = () =>
  seatsJson !== null
    ? Promise.resolve(JSON.parse(readFileSync(seatsJson, "utf8")))
    : new Promise((resolve, reject) => {
        execFile(seatsBin, ["--json", "--no-spend"], { timeout: 90_000, maxBuffer: 16 * 1024 * 1024, env: seatsEnv }, (error, stdout) => {
          if (error) return reject(new Error(`the oracle failed: ${error.code ?? error.signal ?? error.name}`))
          try {
            resolve(JSON.parse(stdout))
          } catch {
            reject(new Error("the oracle answered no JSON"))
          }
        })
      })

const post = (snapshot) => postSnapshot({ base: url, token, snapshot })

let stopping = false
let preDispatch = false
let wake = null
const sleep = (ms) => new Promise((resolve) => { const t = setTimeout(resolve, ms); wake = () => { clearTimeout(t); resolve() } })
const stop = () => { stopping = true; wake?.() }
process.on("SIGTERM", stop)
process.on("SIGINT", stop)
process.on("SIGUSR1", () => { preDispatch = true; wake?.() })
process.on("exit", releasePidfile)

takePidfile()
let state = dryRun ? initialGentleState() : readState()
let failedOnce = false
for (;;) {
  const nowMs = Date.now()
  const asked = preDispatch
  preDispatch = false
  const result = await tick(state, { nowMs, demandAtMs: newestDemandMs(), preDispatch: asked, config, runOracle, post, dryRun })
  state = result.state
  for (const event of result.events) {
    if (event.event === "wait" && !args.once) continue
    process.stdout.write(`${JSON.stringify(event)}\n`)
    if (event.event === "read-failed" || event.event === "push-failed") failedOnce = true
  }
  if (!dryRun) writeState(state)
  if (args.once || stopping) break
  // Wake at the next due instant, at most every 30 s (a demand marker or a signal can make a read due sooner).
  const next = result.events.map((event) => (event.event === "wait" && event.next_at ? Date.parse(event.next_at) : Number.NaN)).find(Number.isFinite)
  await sleep(Math.max(1_000, Math.min(30_000, Number.isFinite(next) ? next - Date.now() : 30_000)))
  if (stopping) break
}
releasePidfile()
process.exit(args.once && failedOnce ? 1 : 0)
