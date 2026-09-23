import { describe, expect, it } from "vitest"
import { decodeRunRecord, RUN_RECORD_FIELDS } from "../src/index.ts"
import { serializeLine as serialize } from "@substrate/serializer"

const record = (overrides: Record<string, unknown> = {}): Record<string, unknown> => ({
  run_id: "wf_0001",
  task: "wf-0001-3",
  harness: "pi",
  model: "halogen-flash",
  runtime: { class: "gvisor", declared_by: "floor-default" },
  placement: { node: "worker", decided_by: "puller", reason: "seat-less box goes to the worker" },
  egress: { policy: "allowlist", allow: [{ host: "worker:8731", purpose: "model endpoint" }] },
  credential: { lane: "none" },
  ...overrides
})

const why = (input: unknown): string => {
  const r = decodeRunRecord(input)
  if (r.ok) throw new Error("expected a failure")
  return r.why
}

describe("RunRecord (ES-6)", () => {
  it("carries runtime, placement, egress and credential", () => {
    expect(RUN_RECORD_FIELDS).toEqual(
      expect.arrayContaining(["runtime", "placement", "egress", "credential"])
    )
    const r = decodeRunRecord(record())
    expect(r.ok).toBe(true)
    if (r.ok) expect(r.value).toEqual(record())
  })

  it("decodes every runtime class and the three credential lanes", () => {
    for (const cls of ["herdr", "gvisor", "microvm"]) {
      expect(decodeRunRecord(record({ runtime: { class: cls, declared_by: "item" } })).ok).toBe(true)
    }
    expect(
      decodeRunRecord(record({ credential: { lane: "seat-config-mount", seat: "cc", mode: "rw" } })).ok
    ).toBe(true)
    expect(decodeRunRecord(record({ credential: { lane: "credential-file", ref: "halogen-api-key" } })).ok).toBe(
      true
    )
  })

  it("refuses a host runtime the floor filled in (host is declared, never inferred)", () => {
    expect(why(record({ runtime: { class: "host", declared_by: "floor-default" } }))).toMatch(/host/)
    expect(decodeRunRecord(record({ runtime: { class: "host", declared_by: "item" } })).ok).toBe(true)
  })

  it("refuses a credential value smuggled in beside the lane", () => {
    expect(why(record({ credential: { lane: "credential-file", ref: "k", value: "s3cr3t" } }))).toMatch(/value/)
    expect(why(record({ token: "s3cr3t" }))).toMatch(/token/)
  })

  it("refuses egress to the executor's control plane", () => {
    for (const host of ["ax-server", "ax-server:8099", "ateapi", "ateapi.svc"]) {
      expect(
        decodeRunRecord(record({ egress: { policy: "allowlist", allow: [{ host, purpose: "x" }] } })).ok
      ).toBe(false)
    }
  })

  it("an allowlist needs a host; none and open take none", () => {
    expect(decodeRunRecord(record({ egress: { policy: "allowlist", allow: [] } })).ok).toBe(false)
    expect(decodeRunRecord(record({ egress: { policy: "none", allow: [] } })).ok).toBe(true)
    expect(
      decodeRunRecord(record({ egress: { policy: "none", allow: [{ host: "github.com", purpose: "x" }] } })).ok
    ).toBe(false)
  })

  it("a workerd runtime carries no credential lane", () => {
    const workerd = { runtime: { class: "workerd", declared_by: "item" } }
    expect(decodeRunRecord(record({ ...workerd, credential: { lane: "none" } })).ok).toBe(true)
    expect(
      decodeRunRecord(record({ ...workerd, credential: { lane: "seat-config-mount", seat: "cc", mode: "ro" } })).ok
    ).toBe(false)
  })

  it("refuses an unknown runtime class and a non-slug node", () => {
    expect(decodeRunRecord(record({ runtime: { class: "k8s", declared_by: "item" } })).ok).toBe(false)
    expect(
      decodeRunRecord(record({ placement: { node: "Worker Box", decided_by: "puller", reason: null } })).ok
    ).toBe(false)
  })

  it("serializes deterministically through @substrate/serializer", () => {
    const r = decodeRunRecord(record())
    if (!r.ok) throw new Error(r.why)
    const a = serialize(r.value)
    const b = serialize(JSON.parse(JSON.stringify(r.value)))
    expect(a).toBe(b)
    expect(a.endsWith("\n")).toBe(true)
  })
})
