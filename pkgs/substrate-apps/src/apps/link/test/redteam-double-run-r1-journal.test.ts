// Red team double-run-r1-1 (2026-09-24): the self-fence clock survives a restart. A `renewed` entry keeps the send
// time of the last renewal without touching the record's `at`, and compaction carries it.
import { mkdtempSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { expect, it } from "vitest"
import { Journal } from "../src/journal.ts"
import { job } from "./review-r4-harness.ts"

it("a journaled renewal is read back after a reopen and after compaction", () => {
  const dir = mkdtempSync(join(tmpdir(), "rt-renewed-"))
  try {
    const j = Journal.open(dir)
    const grant = { leaseId: "wf-test-r-a1", attempt: 1, job: job("r"), lease: { holderIdentity: "h", leaseDurationSeconds: 90, acquireTime: 1, renewTime: 1, leaseTransitions: 0 }, reassignSeconds: 690 }
    j.append({ ev: "grant", leaseId: grant.leaseId, grant } as never, 1_000)
    j.append({ ev: "created", leaseId: grant.leaseId, digest: "d" }, 2_000)
    j.append({ ev: "renewed", leaseId: grant.leaseId }, 50_000)
    j.append({ ev: "renewed", leaseId: grant.leaseId }, 40_000) // an older send time never moves it back
    expect(j.recs.get(grant.leaseId)).toMatchObject({ renewedAt: 50_000, at: 2_000 })
    const k = Journal.open(dir) // reopen compacts
    expect(k.recs.get(grant.leaseId)).toMatchObject({ renewedAt: 50_000 })
    expect(Journal.open(dir).recs.get(grant.leaseId)!.renewedAt).toBe(50_000)
  } finally { rmSync(dir, { recursive: true, force: true }) }
})
