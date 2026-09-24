#!/usr/bin/env node
// apps/pusher/bin/seat-pusher.mjs: LEGACY. Kept for its tests; not the package bin. The pusher to run is
// bin/substrate-pusher.mjs (docs/pusher.md), which reads `seats --json` and never calls a usage endpoint itself.
//
// pushes seat capacity to the CONWIP floor.
//
//   node apps/pusher/bin/seat-pusher.mjs --url URL --token-file PATH [options]
//   node apps/pusher/bin/seat-pusher.mjs --dry-run [options]
//
// Each seat named under `usage` in the config is read through its own source
// (src/usageSource.mjs): "oauth" reads the usage endpoint directly with the
// seat's credentials file, under the gentle refresh policy
// (src/refreshPolicy.mjs: 120 s hard minimum, 900 s idle, 300 s active, 180 s
// near cap, a read at each reset + 90 s, 429 backoff, no call after an auth
// failure until the credentials change); "cache-file" reads a file another
// reader wrote. A legacy meters directory (--meters) is read only when named.
// The snapshot (`seat-capacity/2`) goes OUTBOUND to `<url>/capacity/seats`.
//
// Push policy: push when any seat's reading changed (a Claude seat's provider
// observed_at, grade, windows, dispatchability, slots, plan) and at least every
// --heartbeat seconds (default 1800), or every --slot-heartbeat seconds
// (default 600) while a dispatchable Halogen slot row is published, so the
// floor never grades a live slot row STALE; never twice within --min-interval
// seconds (default 60). A restamp with the same reading is not a change.
//
// Options:
//   --url URL            the floor's base URL (required unless --dry-run)
//   --token-file PATH    the floor's bearer, read from a file and never printed
//   --config PATH        default ~/.config/substrate/seat-capacity.json (optional; the
//                        dry run reads the same path, and the ruled seats cc3
//                        and gpu-coordinator are never dispatchable either way)
//   --state PATH         default ~/.local/state/substrate/pusher/state.json
//   --usage-dir DIR      the direct reader's cache and refresh state
//                        (default ~/.local/state/substrate/usage)
//   --demand-dir DIR     demand markers (default ~/.local/state/substrate/demand)
//   --meters DIR         a legacy meters directory; none by default
//   --capacity-dir DIR   a directory holding a feeder-written seats.json; none by default
//   --host NAME          overrides the config's host and the hostname
//   --watch SECONDS      loop, one pass every SECONDS (minimum 30); default: one pass
//   --heartbeat SECONDS  --slot-heartbeat SECONDS  --min-interval SECONDS
//   --force  --instance NAME
//   --pre-dispatch       treat this pass as a pre-dispatch read (reading older than 300 s)
//   --no-network         never call a usage endpoint (cached readings only)
//   --dry-run            print the snapshot and the decision; no network, no state
//
// Exit: 0 on a pass that pushed or had nothing due; 1 on a failed push; 2 usage.

import { readdirSync } from "node:fs"
import { join } from "node:path"
import { parseArgs } from "node:util"

import { tokenFromFile } from "../src/token.mjs"
import {
  DEFAULT_POLICY,
  defaultConfigPath,
  defaultPusherDir,
  readConfig,
  runOnce
} from "../src/seatCapacity.mjs"

const usage = (message) => {
  process.stderr.write(`seat-pusher: ${message}\n`)
  process.exit(2)
}

let args
try {
  args = parseArgs({
    options: {
      url: { type: "string" },
      "token-file": { type: "string" },
      meters: { type: "string" },
      "capacity-dir": { type: "string" },
      state: { type: "string" },
      config: { type: "string" },
      host: { type: "string" },
      watch: { type: "string" },
      heartbeat: { type: "string" },
      "slot-heartbeat": { type: "string" },
      "min-interval": { type: "string" },
      instance: { type: "string" },
      "usage-dir": { type: "string" },
      "demand-dir": { type: "string" },
      "pre-dispatch": { type: "boolean", default: false },
      "no-network": { type: "boolean", default: false },
      force: { type: "boolean", default: false },
      "dry-run": { type: "boolean", default: false }
    },
    strict: true
  }).values
} catch (error) {
  usage(error.message)
}

const seconds = (name, fallback, minimum = 0) => {
  const raw = args[name]
  if (raw === undefined) return fallback
  const value = Number(raw)
  if (!Number.isFinite(value) || value < minimum) usage(`--${name} must be a number of seconds >= ${minimum}`)
  return value
}

const dryRun = args["dry-run"]
if (!dryRun && (args.url === undefined || args["token-file"] === undefined)) {
  usage("--url and --token-file are required (or --dry-run)")
}
const metersDir = args.meters === undefined || args.meters === "" ? null : args.meters
const capacityDir = args["capacity-dir"] === undefined || args["capacity-dir"] === "" ? null : args["capacity-dir"]
const statePath = args.state ?? join(defaultPusherDir(), "state.json")
// The dry run reads the same config as the real run, so it previews what a
// real run would push.
const config = readConfig(args.config ?? defaultConfigPath())
if (!config.present) {
  process.stderr.write(
    "seat-pusher: no seat-capacity config; using built-in rulings only (cc3, gpu-coordinator not dispatchable)\n"
  )
}
if (args.host !== undefined) config.host = args.host
const policy = {
  heartbeatSeconds: seconds("heartbeat", DEFAULT_POLICY.heartbeatSeconds, 60),
  slotHeartbeatSeconds: seconds("slot-heartbeat", DEFAULT_POLICY.slotHeartbeatSeconds, 60),
  minIntervalSeconds: seconds("min-interval", DEFAULT_POLICY.minIntervalSeconds, 0)
}
const watch = args.watch === undefined ? null : seconds("watch", 300, 30)
let token = ""
if (!dryRun) {
  try {
    token = tokenFromFile(args["token-file"])
  } catch (error) {
    process.stderr.write(`seat-pusher: ${error.message}\n`)
    process.exit(1)
  }
}

const listMeters = () => {
  if (metersDir === null) return []
  try {
    return readdirSync(metersDir)
  } catch (error) {
    process.stderr.write(`seat-pusher: cannot list ${metersDir}: ${error.code ?? error.name}\n`)
    return []
  }
}

const pass = async () => {
  const result = await runOnce({
    metersDir,
    capacityDir,
    statePath,
    config,
    base: args.url ?? "",
    token,
    list: listMeters(),
    policy,
    force: args.force,
    dryRun,
    instance: args.instance ?? "",
    allowNetwork: !args["no-network"],
    preDispatch: args["pre-dispatch"],
    ...(args["usage-dir"] === undefined ? {} : { usageDir: args["usage-dir"] }),
    ...(args["demand-dir"] === undefined ? {} : { demandDir: args["demand-dir"] })
  })
  process.stdout.write(`${JSON.stringify(result)}\n`)
}

if (watch === null) {
  try {
    await pass()
  } catch (error) {
    process.stderr.write(`seat-pusher: ${error.message}\n`)
    process.exit(1)
  }
} else {
  for (;;) {
    try {
      await pass()
    } catch (error) {
      process.stderr.write(`seat-pusher: ${error.message}\n`)
    }
    await new Promise((resolve) => setTimeout(resolve, watch * 1000))
  }
}
