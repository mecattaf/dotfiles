// Sessions chapter (2026-10-12, C2.13): `session` is a route option, so it enters a call's content id only when a call
// names it (every existing journal keeps its cids), and the call record keeps what the backend reported of the harness
// (its session id, usage, route and session file) in memory, never in the Claude-shaped record or the journal.
import { createHash } from "node:crypto";
import { describe, expect, it } from "vitest";
import { MemoryJournal } from "../src/journal.ts";
import { canonicalOpts, contentHash } from "../src/key.ts";
import { run } from "./helpers.ts";

const SESSION = { id: "01k7ab3c4d5e6f7g8h9jkmnpqs", harnessSessionId: "7a1c2d3e-4f50-4612-8a7b-9c0d1e2f3a4b", role: "thread" };

describe("agent({session}) in the interpreter", () => {
  it("a call without session keeps its content id; a session call gets its own", () => {
    const opts = { model: "m", schema: { type: "object" } };
    const before = createHash("sha256").update("p").update("\0").update(canonicalOpts(opts)).digest("hex");
    expect(contentHash("p", opts)).toBe(before);
    expect(contentHash("p", { ...opts, label: "x", phase: "A" })).toBe(before);
    const a = contentHash("p", { ...opts, session: SESSION });
    expect(a).not.toBe(before);
    expect(contentHash("p", { ...opts, session: { ...SESSION, id: "01k7ab3c4d5e6f7g8h9jkmnpqt" } })).not.toBe(a);
    // session is a route, not a keyed option: the harness's chained key is unchanged
    expect(canonicalOpts({ ...opts, session: SESSION })).toBe(canonicalOpts(opts));
  });

  it("the call record keeps the harness session id, usage summed over attempts, route and session file, and the record and journal carry none", async () => {
    const journal = new MemoryJournal();
    let attempt = 0;
    const r = await run(`return await agent("turn", { label: "turn", schema: { type: "object", required: ["ok"], properties: { ok: { type: "boolean" } } }, session: ${JSON.stringify(SESSION)} })`, {
      journal,
      mock: {
        respond: () => (++attempt === 1
          ? { object: { nope: 1 }, agentId: SESSION.harnessSessionId, usage: { inputTokens: 3, outputTokens: 2 }, route: { runtime: "opus", harness: "claude" } }
          : { object: { ok: true }, agentId: SESSION.harnessSessionId, usage: { inputTokens: 5, outputTokens: 1, costUsd: 0.5 } as never, route: { runtime: "opus", harness: "claude" }, sessionFile: "/s/x.jsonl" }),
      },
    });
    expect([r.status, r.error]).toEqual(["completed", undefined]);
    const [c] = r.calls;
    expect(c).toMatchObject({ state: "done", attempts: 2, harnessSessionId: SESSION.harnessSessionId, usage: { inputTokens: 8, outputTokens: 3, costUsd: 0.5 },
      route: { runtime: "opus", harness: "claude" }, sessionFile: "/s/x.jsonl" });
    expect(r.backendCalls[0]!.opts).toMatchObject({ session: SESSION });
    // the record's rows and the journal (the script source, which names its session, is the record's own field)
    const text = JSON.stringify(r.record.workflowProgress) + journal.text();
    for (const k of ["harnessSessionId", "sessionFile", "costUsd", "/s/x.jsonl", "\"route\""]) expect(text).not.toContain(k);
    const row = (r.record.workflowProgress as Array<Record<string, unknown>>).find((x) => x.type === "workflow_agent")!;
    expect(Object.keys(row).sort()).toEqual(["agentId", "attempt", "index", "label", "model", "phaseIndex", "phaseTitle", "promptPreview", "resultPreview", "state", "tokens", "type"]);
  });
});
