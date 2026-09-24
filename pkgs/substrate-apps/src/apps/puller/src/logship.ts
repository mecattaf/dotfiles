// G-BK3, Buildkite's log chunk upload: while a run holds its lease, the puller tails a file of the run's directory
// (the interpreter's events.jsonl by default) and appends it to the floor in chunks, so the CLI, MCP and the operator
// see progress before the verdict. Each chunk names its lease and attempt; the floor takes it only while that attempt
// is live (a fenced puller cannot write), and (leaseId, seq) makes a resend a duplicate, never a second copy.
// Progress is persisted per lease, so a restart of the same attempt continues where it stopped.
import { closeSync, existsSync, openSync, readFileSync, readSync, statSync, writeFileSync } from "node:fs"
import { join } from "node:path"

export type AppendLog = (name: string, c: { leaseId: string; attempt: number; seq: number; data: string }) => Promise<unknown>

export interface LogShipperOptions {
  readonly append: AppendLog
  readonly name: string
  readonly leaseId: string
  readonly attempt: number
  readonly dir: string
  readonly file?: string
  readonly intervalMs?: number
  readonly maxChunkBytes?: number
  readonly log?: (ev: string, f?: Record<string, unknown>) => void
}

export class LogShipper {
  #seq = 0
  #offset = 0
  #timer: ReturnType<typeof setInterval> | undefined
  #busy: Promise<void> | undefined
  #stopped: string | undefined
  failures = 0
  readonly #state: string
  constructor(readonly o: LogShipperOptions) {
    this.#state = join(o.dir, `log-ship.${o.leaseId}.json`)
    try { const s = JSON.parse(readFileSync(this.#state, "utf8")) as { seq: number; offset: number }; this.#seq = s.seq; this.#offset = s.offset } catch { /* fresh */ }
  }
  get stoppedWhy() { return this.#stopped }
  get shipped() { return { seq: this.#seq, offset: this.#offset } }
  start() { this.#timer = setInterval(() => void this.tick(), this.o.intervalMs ?? 2_000); this.#timer.unref?.() }

  /** Ship what is new, one chunk at a time, cut at the last newline (a line is never split across chunks). */
  tick(final = false): Promise<void> {
    if (this.#busy) return this.#busy
    const run = async () => {
      await Promise.resolve() // #busy is set before the body runs, so its finally clears this pass and no other
      try {
        for (;;) {
          if (this.#stopped !== undefined) return
          const data = this.read(final)
          if (data === undefined) return
          try {
            await this.o.append(this.o.name, { leaseId: this.o.leaseId, attempt: this.o.attempt, seq: this.#seq, data: data.toString("utf8") })
          } catch (e) {
            const status = (e as { status?: number })?.status, code = (e as { code?: string })?.code
            if (status === 409 || status === 413) { this.#stopped = code ?? `http-${status}`; this.o.log?.("log-ship-stopped", { leaseId: this.o.leaseId, code: this.#stopped }); return }
            this.failures++
            return // transient: the next tick sends the same seq again
          }
          this.#seq++; this.#offset += data.length
          writeFileSync(this.#state, JSON.stringify({ seq: this.#seq, offset: this.#offset }))
        }
      } finally { this.#busy = undefined }
    }
    this.#busy = run()
    return this.#busy
  }

  private read(final: boolean): Buffer | undefined {
    const path = join(this.o.dir, this.o.file ?? "events.jsonl")
    if (!existsSync(path)) return undefined
    const size = statSync(path).size
    if (size <= this.#offset) return undefined
    const max = this.o.maxChunkBytes ?? 64_000
    const n = Math.min(max, size - this.#offset)
    const buf = Buffer.alloc(n)
    const fd = openSync(path, "r")
    try { readSync(fd, buf, 0, n, this.#offset) } finally { closeSync(fd) }
    const nl = buf.lastIndexOf(0x0a)
    if (nl >= 0) return buf.subarray(0, nl + 1)
    // no newline: a line longer than a chunk goes whole-chunk; a short partial line waits unless this is the last pass
    return n === max || final ? buf : undefined
  }

  /** The run ended: ship the rest (bounded), then stop. Returns how many sends failed transiently. */
  async stop(): Promise<number> {
    if (this.#timer) clearInterval(this.#timer)
    for (let i = 0; i < 3 && this.#stopped === undefined; i++) {
      const before = this.#seq
      await this.tick(true)
      if (this.#seq === before) break
    }
    this.#stopped ??= "stopped"
    return this.failures
  }
}
