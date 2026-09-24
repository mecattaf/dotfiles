// The puller's durable state, all under one directory, written before the act it records:
//   session-id              stable per directory: a restart is the same session (L5), a second copy is not
//   held.json               leaseId -> the grant, written when a Lease answer arrives, removed when its verdict lands
//   pending-request-key     the Lease requestKey in flight; a restart re-sends it and gets the same grants (rule 2b)
//   outbox/<leaseId>.json   a verdict not yet accepted by the floor; resent until it is
//   runs/<runId>/           the run's own directory: script.js, journal.jsonl, events, jobs, result.json
import { randomUUID } from "node:crypto"
import { existsSync, mkdirSync, readdirSync, readFileSync, renameSync, rmSync, writeFileSync } from "node:fs"
import { join } from "node:path"
import type { Grant } from "@substrate/link/contract.ts"
import type { CompletePayload } from "@substrate/link/floor.ts"

const atomic = (path: string, text: string) => { const tmp = `${path}.tmp-${process.pid}`; writeFileSync(tmp, text, { mode: 0o600 }); renameSync(tmp, path) }

export class PullerState {
  constructor(readonly dir: string) { mkdirSync(join(dir, "outbox"), { recursive: true }); mkdirSync(join(dir, "runs"), { recursive: true }) }
  sessionId(): string {
    const p = join(this.dir, "session-id")
    if (!existsSync(p)) writeFileSync(p, randomUUID() + "\n", { mode: 0o600 })
    return readFileSync(p, "utf8").trim()
  }
  held(): Record<string, Grant> {
    const p = join(this.dir, "held.json")
    return existsSync(p) ? JSON.parse(readFileSync(p, "utf8")) as Record<string, Grant> : {}
  }
  putHeld(h: Record<string, Grant>) { atomic(join(this.dir, "held.json"), JSON.stringify(h)) }
  pendingKey(): string | undefined { const p = join(this.dir, "pending-request-key"); return existsSync(p) ? readFileSync(p, "utf8").trim() || undefined : undefined }
  setPendingKey(k: string | undefined) { const p = join(this.dir, "pending-request-key"); if (k === undefined) rmSync(p, { force: true }); else atomic(p, k) }
  outbox(): Array<CompletePayload> {
    return readdirSync(join(this.dir, "outbox")).filter((f) => f.endsWith(".json")).sort().map((f) => JSON.parse(readFileSync(join(this.dir, "outbox", f), "utf8")) as CompletePayload)
  }
  putVerdict(v: CompletePayload) { atomic(join(this.dir, "outbox", `${v.leaseId}.json`), JSON.stringify(v)) }
  hasVerdict(leaseId: string) { return existsSync(join(this.dir, "outbox", `${leaseId}.json`)) }
  dropVerdict(leaseId: string) { rmSync(join(this.dir, "outbox", `${leaseId}.json`), { force: true }) }
  runDir(runId: string) { const d = join(this.dir, "runs", runId); mkdirSync(d, { recursive: true }); return d }
}
