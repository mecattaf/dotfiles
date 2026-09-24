// One puller per state directory and holder: a pidfile, taken at start and removed at exit. A pidfile whose pid is
// gone, or is no longer a substrate-puller, is stale and replaced.
import { linkSync, readFileSync, rmSync, writeFileSync, mkdirSync } from "node:fs"
import { dirname } from "node:path"

export class PidfileHeld extends Error { constructor(readonly pid: number, path: string) { super(`another puller (pid ${pid}) holds ${path}`) } }

const alive = (pid: number, marker: string): boolean => {
  try { process.kill(pid, 0) } catch (e) { return (e as NodeJS.ErrnoException).code === "EPERM" }
  try { return readFileSync(`/proc/${pid}/cmdline`, "utf8").includes(marker) } catch { return true }
}

export const acquirePidfile = (path: string, marker = "substrate-puller", self = process.pid): (() => void) => {
  mkdirSync(dirname(path), { recursive: true })
  // codex review 3, C3-3: the pid is written to a private file and hard-linked into place. link(2) fails with EEXIST
  // when the pidfile exists, so two starts racing past a missing or stale pidfile cannot both win, and a reader
  // never sees a pidfile without its pid. A stale pidfile is removed and the link is tried again.
  const tmp = `${path}.${self}.tmp`
  writeFileSync(tmp, `${self}\n`, { mode: 0o644 })
  try {
    for (let tries = 0; ; tries++) {
      try { linkSync(tmp, path); break } catch (e) {
        if ((e as NodeJS.ErrnoException).code !== "EEXIST" || tries >= 5) throw e
        let text: string
        try { text = readFileSync(path, "utf8").trim() } catch { continue } // removed meanwhile: race again
        const pid = Number(text)
        if (pid === self) break
        if (Number.isInteger(pid) && pid > 0 && alive(pid, marker)) throw new PidfileHeld(pid, path)
        try { if (readFileSync(path, "utf8").trim() === text) rmSync(path) } catch { /* gone */ }
      }
    }
  } finally { rmSync(tmp, { force: true }) }
  return () => { try { if (readFileSync(path, "utf8").trim() === String(self)) rmSync(path) } catch { /* gone */ } }
}
