// PT-01 (2026-09-24): the pusher runs the `seats` oracle with a substrate-owned peer cache, never a tally-rewrite path.
import { execFileSync } from "node:child_process"
import { chmodSync, mkdtempSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join, resolve } from "node:path"
import { describe, expect, it } from "vitest"
import { oracleEnv, SeatsFormatError } from "../src/seatsOracle.mjs"

describe("oracleEnv", () => {
  it("defaults the peer cache under the substrate state directory", () => {
    expect(oracleEnv({}, "/s/state/substrate/", { PATH: "/bin" })).toEqual({ PATH: "/bin", SEATS_PEER_CACHE_DIR: "/s/state/substrate/seats-peer-cache" })
    expect(oracleEnv({ peerCacheDir: undefined }, "/s").SEATS_PEER_CACHE_DIR).toBe("/s/seats-peer-cache")
  })
  it("takes a configured directory, and \"inherit\" leaves the oracle's own default alone", () => {
    expect(oracleEnv({ peerCacheDir: "/x/cache" }, "/s").SEATS_PEER_CACHE_DIR).toBe("/x/cache")
    expect(oracleEnv({ peerCacheDir: "inherit" }, "/s", { SEATS_PEER_CACHE_DIR: "/pre" })).toEqual({ SEATS_PEER_CACHE_DIR: "/pre" })
    expect("SEATS_PEER_CACHE_DIR" in oracleEnv({ peerCacheDir: "inherit" }, "/s", {})).toBe(false)
  })
  it("refuses a tally-rewrite path and an empty value", () => {
    expect(() => oracleEnv({ peerCacheDir: "/home/u/.local/state/tally-rewrite/meters" }, "/s")).toThrow(SeatsFormatError)
    expect(() => oracleEnv({ peerCacheDir: "" }, "/s")).toThrow(/non-empty/)
  })
})

describe("substrate-pusher passes the peer cache to the oracle", () => {
  const bin = resolve(import.meta.dirname, "../bin/substrate-pusher.mjs")
  // A stand-in oracle that reports the directory it was given, as a seat-capacity/1 document is not needed:
  // --dry-run --once prints the converted snapshot or fails, and the stand-in writes its env to a file first.
  const fake = (dir) => {
    const seen = join(dir, "seen")
    const path = join(dir, "seats")
    writeFileSync(path, `#!/bin/sh\nprintf '%s' "\${SEATS_PEER_CACHE_DIR-UNSET}" > "${seen}"\necho '{}'\n`)
    chmodSync(path, 0o755)
    return { path, seen }
  }
  const runOnce = (dir, extra) => {
    const f = fake(dir)
    try {
      execFileSync(process.execPath, [bin, "--dry-run", "--once", "--config", join(dir, "none.json"), "--seats-bin", f.path, "--pidfile", join(dir, "pid"), "--state", join(dir, "st.json"), "--demand-dir", join(dir, "d"), ...extra], { stdio: "pipe", env: { PATH: process.env.PATH, HOME: dir } })
    } catch { /* '{}' is not a seat-capacity/1 document; only the env the oracle saw matters here */ }
    return execFileSync("cat", [f.seen], { encoding: "utf8" })
  }
  it("defaults to $HOME/.local/state/substrate/seats-peer-cache, and --peer-cache-dir inherit leaves it unset", () => {
    const dir = mkdtempSync(join(tmpdir(), "pusher-env-"))
    writeFileSync(join(dir, "none.json"), "{}")
    expect(runOnce(dir, [])).toBe(join(dir, ".local/state/substrate/seats-peer-cache"))
    expect(runOnce(dir, ["--peer-cache-dir", "inherit"])).toBe("UNSET")
    expect(runOnce(dir, ["--peer-cache-dir", "~/pc"])).toBe(join(dir, "pc"))
  })
})
