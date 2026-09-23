// One puller per state directory and holder: a pidfile, taken at start and removed at exit. A pidfile whose pid is
// gone, or is no longer a substrate-puller, is stale and replaced.
import { existsSync, readFileSync, rmSync, writeFileSync, mkdirSync } from "node:fs"
import { dirname } from "node:path"

export class PidfileHeld extends Error { constructor(readonly pid: number, path: string) { super(`another puller (pid ${pid}) holds ${path}`) } }

const alive = (pid: number, marker: string): boolean => {
  try { process.kill(pid, 0) } catch (e) { return (e as NodeJS.ErrnoException).code === "EPERM" }
  try { return readFileSync(`/proc/${pid}/cmdline`, "utf8").includes(marker) } catch { return true }
}

export const acquirePidfile = (path: string, marker = "substrate-puller", self = process.pid): (() => void) => {
  mkdirSync(dirname(path), { recursive: true })
  if (existsSync(path)) {
    const pid = Number(readFileSync(path, "utf8").trim())
    if (Number.isInteger(pid) && pid > 0 && pid !== self && alive(pid, marker)) throw new PidfileHeld(pid, path)
  }
  writeFileSync(path, `${self}\n`, { mode: 0o644 })
  return () => { try { if (readFileSync(path, "utf8").trim() === String(self)) rmSync(path) } catch { /* gone */ } }
}
