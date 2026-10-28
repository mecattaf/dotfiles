import { describe, expect, it } from "vitest";
import { TURN_PROGRAM } from "../../floor/src/link/turn.ts";
import { floorSessionProvenance } from "../src/execute.ts";

describe("maintenance provenance outside the workflow realm", () => {
  it("takes a copy of explicit Floor turn provenance, never prompt or agent session metadata", () => {
    const p = { id: "routine-123", project: "dotfiles", thread: "T-69", role: "thread" };
    const args = { session: { id: p.id, role: p.role }, session_provenance: p, envelopes: ["project=somebody-else"] };
    const read = floorSessionProvenance("turn", args, TURN_PROGRAM);
    expect(read).toEqual(p);
    expect(floorSessionProvenance("turn", args, "fake turn program")).toBeUndefined();
    p.thread = "T-99";
    expect(read!.thread).toBe("T-69");
    expect(floorSessionProvenance("custom-script", args)).toBeUndefined();
    expect(floorSessionProvenance("turn", { session: { ...p } })).toBeUndefined();
    expect(floorSessionProvenance("turn", { ...args, session: { id: "spoofed", role: "thread" } })).toBeUndefined();
  });
});
