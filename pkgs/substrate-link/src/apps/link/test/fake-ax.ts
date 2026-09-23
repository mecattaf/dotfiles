// Test double for ax-server, with stock v0.3.0 semantics where they matter to the link (MEASURED in ax d8ed0fe:
// internal/server/server.go UpdateTask is a blind upsert that also overwrites status; DeleteTask is two-phase;
// FIELD-MAP D3: a save re-runs the reconcile and resumes the actor). `p1` switches on the carried patch P1:
// a terminal phase is written by the controller and GetTaskResult exists. ListTasks pages like ax's Redis store
// (ZRevRange: newest first, limit 0 means 50; MEASURED upstream server.go:91-104, store.go:209-212). GetGateway
// answers from `gateways`; the default `halogen` Gateway allows one host, as ax-fleet's does.
import { createHash } from "node:crypto"
import { Effect } from "effect"
import { AxError } from "../src/ax.ts"
import type { AxApi, AxGateway, AxObserved, AxResult } from "../src/ax.ts"
import type { AxTask } from "../src/contract.ts"

const NOT_FOUND = 5, UNAVAILABLE = 14
type T = { task: AxTask; phase: string; conditions: Array<{ type: string; status: string; reason: string; message: string }>; result?: string; usage?: { promptTokens: number; completionTokens: number; toolCalls: number }; exited?: boolean }

export class FakeAx implements AxApi {
  readonly tasks = new Map<string, T>()
  readonly updates = new Map<string, number>() // UpdateTask calls per name
  upsertsOnExisting = 0 // the hazard: an UpdateTask on a name that already existed (re-runs the actor on v0.3.0)
  resumedAfterExit = 0 // how many times that hazard restarted a finished agent
  deletes: Array<string> = []
  events: Array<string> = [] // update:<name> and delete:<name>, in call order
  up = true
  p1 = true
  blockCreate = false // createTask never returns (a crash window before the Task exists)
  hangAfterCreate = false // createTask writes the Task, then never returns (a crash window after it exists)
  holdPending = new Set<string>() // names the controller never starts
  gateways = new Map<string, AxGateway>([["halogen", { hasAllowlist: true, hosts: [{ host: "worker", port: 8731 }] }]])
  listCalls = 0

  private guard = (): Effect.Effect<void, AxError> => this.up ? Effect.void : Effect.fail(new AxError(UNAVAILABLE, "connection refused"))
  private obs = (name: string, t: T): AxObserved => ({ name, phase: t.phase, spec: t.task.spec, conditions: t.conditions, usage: t.usage ?? null })

  /** The controller's work between two resyncs: start Pending Tasks, finish two-phase deletes. */
  tick() {
    for (const [name, t] of this.tasks) {
      if (t.phase === "Terminating") this.tasks.delete(name)
      else if (t.phase === "Pending" && !this.holdPending.has(name)) t.phase = "Running"
    }
  }
  /** The agent exits. With P1 the controller writes the terminal phase; without it the Task stays Running. */
  finish(name: string, exitCode: number, result?: unknown, usage = { promptTokens: 11, completionTokens: 7, toolCalls: 3 }) {
    const t = this.tasks.get(name)
    if (!t) throw new Error(`no task ${name}`)
    t.exited = true
    if (!this.p1) return
    t.phase = exitCode === 0 ? "Completed" : "Failed"
    t.conditions = [{ type: "Ready", status: "False", reason: "CommandExited", message: `ExitCode=${exitCode}` }]
    if (result !== undefined) t.result = JSON.stringify(result)
    t.usage = usage
  }
  put(task: AxTask, phase = "Running") { this.tasks.set(task.metadata.name, { task, phase, conditions: [] }) }
  live(name: string) { const t = this.tasks.get(name); return t !== undefined && t.phase !== "Terminating" }

  getTask = (name: string) => this.guard().pipe(Effect.map(() => { const t = this.tasks.get(name); return t ? this.obs(name, t) : undefined }))
  createTask = (task: AxTask) => this.guard().pipe(Effect.andThen(() => {
    if (this.blockCreate) return Effect.never
    const name = task.metadata.name
    this.updates.set(name, (this.updates.get(name) ?? 0) + 1)
    this.events.push(`update:${name}`)
    const prior = this.tasks.get(name)
    if (prior) { this.upsertsOnExisting++; if (prior.exited) this.resumedAfterExit++ } // v0.3.0: status reset, actor resumed
    this.tasks.set(name, { task, phase: "Pending", conditions: [] })
    return this.hangAfterCreate ? Effect.never : Effect.void
  }))
  listTasks = (limit: number, offset: number) => this.guard().pipe(Effect.map(() => {
    if (offset === 0) { this.tick(); this.listCalls++ }
    const n = limit > 0 ? limit : 50
    return [...this.tasks].reverse().slice(offset, offset + n).map(([name, t]) => this.obs(name, t))
  }))
  getGateway = (name: string) => this.guard().pipe(Effect.map(() => this.gateways.get(name)))
  deleteTask = (name: string) => this.guard().pipe(Effect.map(() => {
    const t = this.tasks.get(name)
    if (t) { t.phase = "Terminating"; this.deletes.push(name); this.events.push(`delete:${name}`) }
  }))
  getTaskResult = (name: string) => this.guard().pipe(Effect.andThen((): Effect.Effect<AxResult | "unimplemented" | undefined> => {
    if (!this.p1) return Effect.succeed("unimplemented" as const)
    const t = this.tasks.get(name)
    if (!t) return Effect.succeed(undefined)
    const content = t.result ?? "null"
    return Effect.succeed({ content, sha256: createHash("sha256").update(content).digest("hex"), digestOk: true })
  }))
  static notFound = NOT_FOUND
}
