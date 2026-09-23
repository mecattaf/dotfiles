// The link's crash-safe local state: one append-only JSONL file, fsynced per line, written BEFORE the action it
// records (the tally uplink's "offline is a queue" outbox, kept verbatim in spirit: done / keep / drop). The ax
// store is the ledger of Tasks (Buildkite: the cluster is the ledger); this file only covers what ax cannot know:
// grants not yet created, and Complete reports not yet acknowledged by the floor.
import { appendFileSync, closeSync, existsSync, fsyncSync, mkdirSync, openSync, readFileSync, renameSync, writeSync } from "node:fs"
import { join } from "node:path"
import type { Grant, Result, Usage } from "./contract.ts"

export type Entry =
  | { ev: "grant"; leaseId: string; grant: Grant; regrant?: true } // round 2: `regrant` replaces a released record
  | { ev: "creating"; leaseId: string; digest?: string } // round 1: written BEFORE the first UpdateTask; the Task may exist from here on. Round 3: the spec digest the link will write, so a cleanup can tell its own Task from a foreign one
  | { ev: "not-mine"; leaseId: string } // round 3: a Task of this name exists and is not the link's; `creating` no longer holds
  | { ev: "created"; leaseId: string; digest: string }
  | { ev: "grant-invalid"; leaseId: string; attempt: number; message: string } // round 1: a grant that did not decode
  | { ev: "report"; leaseId: string; attempt: number; result: Result; output?: unknown; usage?: Usage; replace?: true } // outbox; round 2: `replace` swaps an undeliverable verdict
  | { ev: "reported"; leaseId: string; duplicate: boolean; withdrew?: string; withdrewGen?: Gen } // done: 2xx from the floor; round 2: what rule 4b withdrew; round 3: which generation of it
  | { ev: "dropped"; leaseId: string; code: string } // drop: the floor refused these bytes for good
  | { ev: "released"; leaseId: string; why: string } // no longer held (lost, cancelled, superseded)
  | { ev: "deleting"; leaseId: string; why: string } // DeleteTask accepted; waiting for NotFound (ax deletes in two phases)
  | { ev: "deleted"; leaseId: string }
  | { ev: "lease-key"; requestKey: string } // B8: a Lease is in flight with this key; reuse it until its reply lands
  | { ev: "lease-replied"; requestKey: string; abandoned?: true } // the reply's grants are journaled; the next Lease draws a new key
  | { ev: "tomb"; leaseId: string; gen: Gen } // round 3: written by compaction for a finished lease; refuses its redelivery

/** Round 3: a grant generation. `acquireTime` is absent when only the floor's `withdrewTransitions` is known. */
export interface Gen { readonly leaseTransitions: number; readonly acquireTime?: number }
export const genOf = (g: Grant): Gen => ({ leaseTransitions: g.lease.leaseTransitions, acquireTime: g.lease.acquireTime })
/** `g` is a strictly later generation than `than` (leaseTransitions first, then acquireTime). */
export const laterGen = (g: Gen, than: Gen) => g.leaseTransitions > than.leaseTransitions ||
  (g.leaseTransitions === than.leaseTransitions && g.acquireTime !== undefined && than.acquireTime !== undefined && g.acquireTime > than.acquireTime)
/** `g` is the generation `w` names: equal leaseTransitions, and equal acquireTime when both are known. */
export const sameGen = (g: Gen, w: Gen) => g.leaseTransitions === w.leaseTransitions &&
  (g.acquireTime === undefined || w.acquireTime === undefined || g.acquireTime === w.acquireTime)

export interface LeaseRec {
  grant: Grant
  created?: string // spec digest
  creating?: boolean // an UpdateTask may have landed (write-ahead); cleanup must DeleteTask by name and see NotFound
  creatingDigest?: string // round 3: the spec digest the link was about to write
  notMine?: boolean // round 3: the Task under this name is someone else's; never read, delete or report it
  createdAt?: number
  report?: Extract<Entry, { ev: "report" }>
  reported?: boolean
  duplicate?: boolean // round 2: the floor answered this verdict as a duplicate (rule 4c)
  withdrew?: string // round 2: the leaseId the floor withdrew when it accepted this verdict (rule 4b), never inferred
  withdrewGen?: Gen // round 3: the generation withdrawn; undefined when this link never held it (it then matches nothing)
  dropped?: string
  released?: string
  deleting?: string // why: cancel, lost, dropped, janitor, pre-start, deadline, superseded
  deleted?: boolean
  at: number // when this record was last touched (ms)
}

export class Journal {
  readonly path: string
  readonly recs = new Map<string, LeaseRec>()
  /** Grants that did not decode: refused to the floor as pre-start/invalid-spec through the same outbox. */
  readonly invalid = new Map<string, { attempt: number; message: string; reported?: boolean; dropped?: string; released?: string; at: number }>()
  pendingLeaseKey: string | undefined
  /** Round 3: finished leases, kept through compaction for TOMB_MS so a redelivered grant of one is never run again. */
  readonly tombs = new Map<string, { gen: Gen; at: number }>()
  static TOMB_MS = 24 * 3600_000 // well past the floor's replay window (rule 2b: lease + grace, 390 s in production)
  private readonly dir: string
  private constructor(dir: string) { this.dir = dir; this.path = join(dir, "journal.jsonl") }

  static open(dir: string, now = Date.now()): Journal {
    mkdirSync(dir, { recursive: true, mode: 0o700 })
    const j = new Journal(dir)
    if (existsSync(j.path)) {
      for (const line of readFileSync(j.path, "utf8").split("\n")) {
        if (line.trim() === "") continue
        let e: Entry & { t?: number }
        try { e = JSON.parse(line) } catch { continue } // a torn last line from a crash mid-write is skipped
        j.apply(e, e.t ?? now)
      }
      j.compact()
    }
    return j
  }

  private apply(e: Entry, t: number) {
    if (e.ev === "lease-key") { this.pendingLeaseKey = e.requestKey; return }
    if (e.ev === "lease-replied") { if (this.pendingLeaseKey === e.requestKey) this.pendingLeaseKey = undefined; return }
    if (e.ev === "tomb") { this.tombs.set(e.leaseId, { gen: e.gen, at: t }); return }
    if (e.ev === "grant") {
      if (this.recs.has(e.leaseId) && !e.regrant) return
      this.recs.set(e.leaseId, { grant: e.grant, at: t })
      // round 2: the withdrawal recorded against the previous generation of this leaseId does not apply to the new one
      if (e.regrant) for (const x of this.recs.values()) if (x.withdrew === e.leaseId) { delete x.withdrew; delete x.withdrewGen }
      return
    }
    if (e.ev === "grant-invalid") { if (!this.recs.has(e.leaseId) && !this.invalid.has(e.leaseId)) this.invalid.set(e.leaseId, { attempt: e.attempt, message: e.message, at: t }); return }
    const r = this.recs.get(e.leaseId)
    if (!r) {
      const x = this.invalid.get(e.leaseId)
      if (x && e.ev === "reported") x.reported = true
      if (x && e.ev === "dropped") x.dropped = e.code
      if (x && e.ev === "released") x.released ??= e.why
      return
    }
    r.at = t
    switch (e.ev) {
      case "creating": r.creating = true; delete r.notMine; if (e.digest !== undefined) r.creatingDigest = e.digest; break
      case "not-mine": r.notMine = true; delete r.creating; break
      case "created": r.created = e.digest; r.createdAt ??= t; break
      case "report": if (!r.report || e.replace) r.report = e; break // first verdict wins (the floor dedupes as well), unless replaced
      case "reported": r.reported = true; r.duplicate = e.duplicate; if (e.withdrew !== undefined) { r.withdrew = e.withdrew; if (e.withdrewGen !== undefined) r.withdrewGen = e.withdrewGen } break
      case "dropped": r.dropped = e.code; break
      case "released": r.released ??= e.why; break
      case "deleting": r.deleting ??= e.why; break
      case "deleted": r.deleted = true; break
    }
  }

  append(e: Entry, t = Date.now()) {
    appendFileSync(this.path, JSON.stringify({ t, ...e }) + "\n", { mode: 0o600 })
    const fd = openSync(this.path, "r")
    try { fsyncSync(fd) } finally { closeSync(fd) }
    this.apply(e, t)
    if (++this.appends >= Journal.COMPACT_EVERY) this.compact() // idle Lease keys must not grow the file for ever
  }
  static COMPACT_EVERY = 2000
  private appends = 0

  /** Finished = nothing left to tell the floor and nothing left in ax. */
  static finished(r: LeaseRec) {
    // Round 2: a verdict read after the lease was released (lost, superseded) is still owed to the floor
    if (Journal.pending(r)) return false
    const toldFloor = r.reported === true || r.dropped !== undefined || r.released !== undefined
    const axClean = !Journal.maybeCreated(r) || r.deleted === true
    return toldFloor && axClean
  }
  /** Round 1: a Task may exist in ax once `creating` is journaled, even if `created` never was (a crash, or a
   *  DEADLINE_EXCEEDED after the write landed). Every cleanup path treats such a record as created. */
  static maybeCreated(r: LeaseRec) { return r.created !== undefined || r.creating === true }
  /** A verdict is journaled and neither acknowledged nor dropped. */
  static pending(r: LeaseRec) { return r.report !== undefined && !r.reported && r.dropped === undefined }

  /** Rewrite the file with only unfinished leases (atomic rename), so it never grows without bound. */
  compact() {
    const tmp = this.path + ".tmp"
    const fd = openSync(tmp, "w", 0o600)
    try {
      if (this.pendingLeaseKey !== undefined) writeSync(fd, JSON.stringify({ t: Date.now(), ev: "lease-key", requestKey: this.pendingLeaseKey }) + "\n")
      for (const [id, r] of this.recs) {
        if (Journal.finished(r)) { this.recs.delete(id); this.tombs.set(id, { gen: genOf(r.grant), at: r.at }); continue }
        const lines: Array<Entry> = [{ ev: "grant", leaseId: id, grant: r.grant }]
        if (r.creating) lines.push({ ev: "creating", leaseId: id, ...(r.creatingDigest !== undefined ? { digest: r.creatingDigest } : {}) })
        if (r.notMine) lines.push({ ev: "not-mine", leaseId: id })
        if (r.created !== undefined) lines.push({ ev: "created", leaseId: id, digest: r.created })
        if (r.report) lines.push(r.report)
        if (r.reported) lines.push({ ev: "reported", leaseId: id, duplicate: r.duplicate ?? false, ...(r.withdrew !== undefined ? { withdrew: r.withdrew } : {}), ...(r.withdrewGen !== undefined ? { withdrewGen: r.withdrewGen } : {}) })
        if (r.dropped !== undefined) lines.push({ ev: "dropped", leaseId: id, code: r.dropped })
        if (r.released !== undefined) lines.push({ ev: "released", leaseId: id, why: r.released })
        if (r.deleting !== undefined) lines.push({ ev: "deleting", leaseId: id, why: r.deleting })
        for (const l of lines) writeSync(fd, JSON.stringify({ t: l.ev === "created" || l.ev === "grant" ? (r.createdAt ?? r.at) : r.at, ...l }) + "\n")
      }
      const now = Date.now()
      for (const [id, x] of this.tombs) {
        if (now - x.at > Journal.TOMB_MS) { this.tombs.delete(id); continue }
        writeSync(fd, JSON.stringify({ t: x.at, ev: "tomb", leaseId: id, gen: x.gen }) + "\n")
      }
      for (const [id, x] of this.invalid) { // never created, so finished once the floor is told
        if (x.reported || x.dropped !== undefined || x.released !== undefined) { this.invalid.delete(id); continue }
        writeSync(fd, JSON.stringify({ t: x.at, ev: "grant-invalid", leaseId: id, attempt: x.attempt, message: x.message }) + "\n")
      }
      fsyncSync(fd)
    } finally { closeSync(fd) }
    renameSync(tmp, this.path)
    this.appends = 0
    const d = openSync(this.dir, "r") // B20: make the rename itself durable
    try { fsyncSync(d) } finally { closeSync(d) }
  }

  /** The complete set this holder believes it holds: sent in every Heartbeat (level-triggered). A lease whose
   *  verdict is still in the outbox stays held, so a heartbeat that races the outbox drain cannot orphan it. */
  held(): Array<string> {
    return [...[...this.recs].filter(([, r]) => !r.reported && r.dropped === undefined && r.released === undefined).map(([id]) => id),
      ...[...this.invalid].filter(([, x]) => !x.reported && x.dropped === undefined && x.released === undefined).map(([id]) => id)]
  }
  /** Leases whose verdict is written but not yet acknowledged; they are still held until the floor says done. */
  outbox(): Array<Extract<Entry, { ev: "report" }>> {
    return [...[...this.recs.values()].filter(Journal.pending).map((r) => r.report!),
      ...[...this.invalid].filter(([, x]) => !x.reported && x.dropped === undefined && x.released === undefined)
        .map(([leaseId, x]) => ({ ev: "report" as const, leaseId, attempt: x.attempt, result: "failure" as const, output: { reason: "pre-start/invalid-spec", message: x.message } }))]
  }
}
