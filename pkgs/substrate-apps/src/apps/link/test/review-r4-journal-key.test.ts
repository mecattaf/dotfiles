// Round 4 regression test for finding 8 (repro: /home/tom/today/evals-2026-09-23/link/scratch-r4-2/journal-key.repro.ts).
// AX_CONWIP_JOURNAL_KEY must be the FIELD-MAP 5a journal key ("sha256 of canonical [prompt, opts minus label] plus the
// occurrence"), carried on the AgentJob as the `ultracode.mecattaf.dev/journal-key` annotation, never the prompt
// digest. The expected values are pinned from the substrate taskspec (journalKey in
// /home/tom/mecattaf/ax-conwip-wt-integration/src/taskspec.ts at b42b310, run 2026-09-23), so this test does not
// import another worktree.
import { createHash } from "node:crypto"
import { expect, it } from "vitest"
import { axTaskFromGrant } from "../src/jobs.ts"
import { job } from "./review-r4-harness.ts"

const TASKSPEC = {
  halogen1: "29a9c6cb8956c07073345109161d0e7eaa08708f4c2039f4e4af7a09d212ee07:1", // journalKey("same prompt", {model: halogen}, 1)
  opus1: "bd381a2d66f7a1d93c7df296954218de4c9749a0feb9d94719b9c484f8c06718:1", // journalKey("same prompt", {model: opus}, 1)
  halogen2: "29a9c6cb8956c07073345109161d0e7eaa08708f4c2039f4e4af7a09d212ee07:2" // the same call, second occurrence
}
const sha = (s: string) => createHash("sha256").update(s).digest("hex")
const A = "ultracode.mecattaf.dev/"
const grant = (n: string, model: string, key: string | undefined) => {
  const j: any = job(n)
  j.spec.with.prompt = "same prompt"
  j.spec.with.prompt_ref = { sha256: sha("same prompt"), bytes: 11, uri: `journal://wf_test/${n}/prompt.md` }
  j.spec.with.model = model
  if (key === undefined) delete j.metadata.annotations[A + "journal-key"]
  else j.metadata.annotations[A + "journal-key"] = key
  return { leaseId: `wf-test-${n}-a1`, attempt: 1, job: j, lease: { holderIdentity: "h", leaseDurationSeconds: 90, acquireTime: 1, renewTime: 1, leaseTransitions: 0 } }
}
const shape = { atespace: "fleet", image: "ax-agent", gateway: "halogen", command: () => ["ax-agent", "pi"] }
const env = (g: any) => { const b: any = axTaskFromGrant(g, shape); expect(b._tag).toBe("ok"); return Object.fromEntries(b.task.spec.env.map((e: any) => [e.name, e.value])) }

it("R4-8a: AX_CONWIP_JOURNAL_KEY is the taskspec journal key for two calls that share a prompt", () => {
  const a = env(grant("1", "halogen-qwen3.8-flash-next", TASKSPEC.halogen1))
  const b = env(grant("2", "claude-opus-5-5", TASKSPEC.opus1))
  const c = env(grant("3", "halogen-qwen3.8-flash-next", TASKSPEC.halogen2))
  expect(a.AX_CONWIP_JOURNAL_KEY).toBe(TASKSPEC.halogen1)
  expect(b.AX_CONWIP_JOURNAL_KEY).toBe(TASKSPEC.opus1)
  expect(c.AX_CONWIP_JOURNAL_KEY).toBe(TASKSPEC.halogen2)
  expect(a.AX_CONWIP_JOURNAL_KEY).not.toBe(a.AX_CONWIP_PROMPT_SHA256)
  expect(a.AX_CONWIP_PROMPT_SHA256).toBe(b.AX_CONWIP_PROMPT_SHA256) // the prompt digest is shared; the journal key is not
})

it("R4-8b: a grant without the annotation, or with a malformed one, is refused pre-start/invalid-spec", () => {
  for (const key of [undefined, "", sha("same prompt"), `${sha("x")}:`, `${sha("x").toUpperCase()}:1`]) {
    const b = axTaskFromGrant(grant("4", "halogen-qwen3.8-flash-next", key) as any, shape)
    expect(b._tag).toBe("refused")
    if (b._tag === "refused") expect(b.reason).toBe("pre-start/invalid-spec")
  }
})
