// Prove lane 2026-09-23: an idle pusher reads every 900 s, past the gate's 360 s dispatch bound, so the first node
// after a quiet spell was refused stale-for-dispatch. The puller now marks demand while it holds a run.
import { mkdtempSync, statSync, utimesSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { describe, expect, it } from "vitest"
import { touchDemand } from "../src/execute.ts"

describe("demand marker", () => {
  it("creates the marker, then refreshes its mtime", () => {
    const dir = join(mkdtempSync(join(tmpdir(), "demand-")), "nested")
    touchDemand(dir, "substrate-puller")
    const f = join(dir, "substrate-puller")
    const old = new Date(Date.now() - 3_600_000)
    utimesSync(f, old, old)
    touchDemand(dir, "substrate-puller")
    expect(Date.now() - statSync(f).mtimeMs).toBeLessThan(60_000)
  })
  it("never throws when the dir cannot be made (its parent is a file)", () => {
    const file = join(mkdtempSync(join(tmpdir(), "demand-")), "plain")
    writeFileSync(file, "")
    expect(() => touchDemand(join(file, "sub"), "x")).not.toThrow()
  })
})
