import { describe, expect, it } from "vitest";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { localFloor } from "@substrate/floor/local.ts";
import { connectFloor } from "../src/connect.ts";
import { Puller } from "../src/puller.ts";
import type { FloorPort } from "../src/puller.ts";

const scope = [{ project: "dotfiles", thread: "T-69" }];

describe("scoped interpreter admission over RPC", () => {
  it("uses persisted Floor metadata over the full scoped RPC without leasing old queues", async () => {
    const f = localFloor({ floorToken: "op", links: [{ token: "scoped", holder: "coord", labels: ["runtime:interpreter"] }], vars: { FLOOR_UNGATED_SEATS: "*" } });
    const a = "01scope00000000000000000001", b = "01scope00000000000000000002";
    f.floor.engine.receive([
      { id: "wake-scope-1", seq: 1, session: a, envelope: "old", start: { project: "dotfiles", thread: "T-15", model: "old-pi" } },
      { id: "wake-scope-2", seq: 2, session: b, envelope: "nightly", start: { project: "dotfiles", thread: "T-69", model: "local" } },
    ], 2);
    const conn = await connectFloor({ url: "http://floor.test", token: "scoped", sessionId: "scope-client", fetch: f.fetch });
    try {
      const r = await conn.port.lease({ holderIdentity: "coord", capacity: 8, requestKey: "wire-scope", sessionScope: scope });
      expect(r.grants.map(g => g.job.metadata.name)).toEqual([`run-s${b}r1`]);
      expect(f.floor.engine.job(`run-s${a}r1`)!.state).toBe("queued");
    } finally { await conn.close(); f.close(); }
  });
  it("fails closed against an old RPC server, with no unscoped fallback", async () => {
    const bodies: string[] = [];
    const conn = await connectFloor({ url: "http://old-floor.test", token: "t", sessionId: "scope-client", fetch: async (input, init) => {
      const req = new Request(input, init); bodies.push(await req.text()); return new Response("unknown RPC", { status: 501 });
    } });
    try { await expect(conn.port.lease({ holderIdentity: "coord", capacity: 1, requestKey: "wire-old", sessionScope: scope })).rejects.toThrow(); }
    finally { await conn.close(); }
    expect(bodies).toHaveLength(1);
    expect(bodies[0]).toContain("LeaseScoped");
  });
  it("the puller passes its scope and uses a scope-specific durable request key", async () => {
    const requests: unknown[] = [];
    let p: Puller;
    const floor: FloorPort = { lease: async req => { requests.push(req); p.stop(); return { grants: [] }; }, heartbeat: async () => ({ renewed: [], lost: [], cancelRequested: [] }), complete: async () => ({ duplicate: false }) };
    p = new Puller({ holder: "coord", maxRuns: 1, stateDir: mkdtempSync(join(tmpdir(), "scope-puller-")), sessionScope: scope, pollMs: 1 },
      { floor, client: { runScript: async () => "" }, execute: async () => ({ result: "success", output: {} }) });
    await p.run();
    expect(requests).toHaveLength(1);
    expect(requests[0]).toMatchObject({ sessionScope: scope, requestKey: expect.stringMatching(/^scope-v1-[0-9a-f]{24}-/) });
  });
});
