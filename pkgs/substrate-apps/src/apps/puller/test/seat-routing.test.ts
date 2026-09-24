// Critique pass 2026-09-24, RG-3: floor dispatch labels agent({runtime: X}) with the seat X's table spends, never
// node_runs_on's seat, and refuses a runtime with no resolvable seat; the refusal is the call's error, nothing enqueued.
import { describe, expect, it } from "vitest"
import { parseRuntimesToml } from "@substrate/runners"
import { FloorBackend, nodeJob } from "../src/execute.ts"

const runtimes = parseRuntimesToml(`default = "halogen"
[seats]
pi = "halogen"
codex = "codex"
[runtime.halogen]
type = "host"
harness = "pi"
[runtime.codex]
type = "host"
harness = "codex"
[runtime.bare]
type = "host"
harness = "pi"
seat = "worker-pi"
`, "t", "/home/u")
const call = (opts: Record<string, unknown>) => ({ index: 1, key: "k", prompt: "p", opts, phase: undefined, attempt: 1, occurrence: 1, cid: undefined }) as never
const o = { runId: "r", workflow: "w", defaultRunsOn: ["seat:halogen", "runtime:gvisor"], defaultModel: "m" }

describe("RG-3: floor runs-on carries the seat the runtime spends", () => {
  it("runtime codex is labelled seat:codex (it was seat:halogen), runtime halogen seat:halogen, a seat alone keeps the default runtime labels", () => {
    expect(nodeJob(call({ runtime: "codex" }), { ...o, runtimes }).spec["runs-on"]).toEqual(["seat:codex", "runtime:codex"])
    expect(nodeJob(call({ runtime: "halogen" }), { ...o, runtimes }).spec["runs-on"]).toEqual(["seat:halogen", "runtime:halogen"])
    expect(nodeJob(call({ runtime: "bare" }), { ...o, runtimes }).spec["runs-on"]).toEqual(["seat:worker-pi", "runtime:bare"])
    expect(nodeJob(call({ seat: "codex" }), { ...o, runtimes }).spec["runs-on"]).toEqual(["seat:codex", "runtime:gvisor"])
    expect(nodeJob(call({ runsOn: ["seat:x", "runtime:y"] }), o).spec["runs-on"]).toEqual(["seat:x", "runtime:y"])
    expect(nodeJob(call({}), o).spec["runs-on"]).toEqual(["seat:halogen", "runtime:gvisor"])
  })

  it("a runtime with no resolvable seat, or a seat its table contradicts, is refused as the call's error and nothing is enqueued", async () => {
    expect(() => nodeJob(call({ runtime: "codex" }), o)).toThrow(/the puller has no runtimes file/)
    expect(() => nodeJob(call({ runtime: "nope" }), { ...o, runtimes })).toThrow(/no seat is resolvable for runtime nope/)
    expect(() => nodeJob(call({ runtime: "codex", seat: "halogen" }), { ...o, runtimes })).toThrow(/runtime codex spends seat codex/)
    const enq: unknown[] = []
    const b = new FloorBackend({ ...o, runtimes, signal: new AbortController().signal, client: { enqueue: async (...a: unknown[]) => { enq.push(a); return {} as never }, job: async () => ({}) as never, output: async () => ({}) as never } })
    expect(await b.run(call({ runtime: "nope" }))).toMatchObject({ error: expect.stringMatching(/no seat is resolvable/) })
    expect(enq).toHaveLength(0)
  })
})
