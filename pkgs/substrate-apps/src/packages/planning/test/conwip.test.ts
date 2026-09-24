/**
 * CONWIP caps, on all three axes at once.
 */
import fc from "fast-check";
import { Option, Schema } from "effect";
import { describe, expect, it } from "vitest";
import { conwipCaps, conwipVerdict, wipOn } from "../src/heuristics/conwip.ts";
import type { ConwipCap, ConwipContext } from "../src/heuristics/conwip.ts";
import { WipCount } from "../src/schema/backlog.ts";
import { familyName, item, levelName } from "./fixtures.ts";

const decodeWip = Schema.decodeUnknownSync(Schema.Array(WipCount));

const wip = (count: number) =>
  decodeWip([
    { level: "approved", namespace: "mecattaf/conwip", family: "build", count }
  ]);

describe("CONWIP", () => {
  it("admits when no cap is declared", () => {
    const verdict = conwipVerdict(item({ taskId: "t1" }), { caps: [], wip: [] }, []);
    expect(verdict.admissible).toBe(true);
  });

  it("blocks on the level cap and names it", () => {
    const context: ConwipContext = {
      caps: conwipCaps([[levelName("approved"), 2]], [], []),
      wip: wip(2)
    };
    const verdict = conwipVerdict(item({ taskId: "t1" }), context, []);

    expect(verdict.admissible).toBe(false);
    expect(Option.getOrNull(verdict.binding)?.axis).toBe("level");
    expect(Option.getOrNull(verdict.binding)?.subject).toBe("approved");
  });

  it("blocks on the family cap even when the level has slack", () => {
    const context: ConwipContext = {
      caps: conwipCaps([[levelName("approved"), 10]], [[familyName("build"), 1]], []),
      wip: wip(1)
    };
    const verdict = conwipVerdict(item({ taskId: "t1" }), context, []);

    expect(verdict.admissible).toBe(false);
    expect(Option.getOrNull(verdict.binding)?.axis).toBe("family");
  });

  it("counts admits already proposed in the same pass", () => {
    // The failure this prevents: one evaluation releasing past a cap because it
    // counted only what the kernel already holds.
    const context: ConwipContext = {
      caps: conwipCaps([[levelName("approved"), 1]], [], []),
      wip: []
    };
    const first = item({ taskId: "t1" });
    const second = item({ taskId: "t2" });

    expect(conwipVerdict(first, context, []).admissible).toBe(true);
    expect(conwipVerdict(second, context, [first]).admissible).toBe(false);
  });

  it("counts work in process on the requested axis only", () => {
    const counts = decodeWip([
      { level: "approved", namespace: "mecattaf/conwip", family: "build", count: 3 },
      { level: "approved", namespace: "mecattaf/dotfiles", family: "upkeep", count: 4 }
    ]);
    expect(wipOn(counts, "level", "approved")).toBe(7);
    expect(wipOn(counts, "namespace", "mecattaf/conwip")).toBe(3);
    expect(wipOn(counts, "family", "upkeep")).toBe(4);
  });

  it("never admits past a declared cap, for any cap and any count", () => {
    fc.assert(
      fc.property(
        fc.integer({ min: 0, max: 20 }),
        fc.integer({ min: 0, max: 20 }),
        (cap, held) => {
          const caps: ReadonlyArray<ConwipCap> = conwipCaps([[levelName("approved"), cap]], [], []);
          const verdict = conwipVerdict(item({ taskId: "t1" }), { caps, wip: wip(held) }, []);
          // Admissible exactly when adding one more stays within the cap.
          return verdict.admissible === held < cap;
        }
      ),
      { numRuns: 300 }
    );
  });
});
