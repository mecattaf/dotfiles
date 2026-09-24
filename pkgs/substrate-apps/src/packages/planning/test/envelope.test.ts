/**
 * The envelope lease, and the one-directional invariant that makes admission
 * safe: a child can only reduce headroom, never mint it.
 */
import fc from "fast-check";
import { Option, Schema } from "effect";
import { describe, expect, it } from "vitest";
import {
  canSpawn,
  envelopeOf,
  grantChild,
  remaining,
  rootEnvelope,
  totalOutstanding,
  type Envelope
} from "../src/heuristics/envelope.ts";
import { TaskId } from "../src/schema/ids.ts";

const decodeTaskId = Schema.decodeUnknownSync(TaskId);
const task = (name: string) => decodeTaskId(name);

describe("envelope lease", () => {
  it("grants a child within the parent's allocation and debits the parent", () => {
    const parent = rootEnvelope(task("parent"), 100);
    const grant = grantChild(parent, task("child"), 40);

    expect(grant._tag).toBe("Granted");
    if (grant._tag !== "Granted") return;
    expect(remaining(grant.parent)).toBe(60);
    expect(grant.child.allocated).toBe(40);
    expect(remaining(grant.child)).toBe(40);
  });

  it("refuses a child past the allocation and names the shortfall", () => {
    const parent = rootEnvelope(task("parent"), 10);
    const grant = grantChild(parent, task("child"), 25);

    expect(grant._tag).toBe("Refused");
    if (grant._tag !== "Refused") return;
    expect(grant.shortfall).toBe(15);
  });

  it("never grants partially", () => {
    // A partially funded subtree falsifies its own estimate exactly as an
    // unbounded one does, so there is no partial grant to test for.
    const parent = rootEnvelope(task("parent"), 10);
    const grant = grantChild(parent, task("child"), 11);
    expect(grant._tag).toBe("Refused");
  });

  it("treats a zero envelope as the capability strip that removes child enqueue", () => {
    const stripped = rootEnvelope(task("fable"), 0);
    expect(canSpawn(stripped)).toBe(false);
    expect(grantChild(stripped, task("child"), 1)._tag).toBe("Refused");
  });

  it("clamps a negative allocation rather than minting headroom by arithmetic", () => {
    expect(rootEnvelope(task("parent"), -50).allocated).toBe(0);
  });

  it("returns None for an unknown parent rather than treating it as unbounded", () => {
    expect(Option.isNone(envelopeOf([], task("missing")))).toBe(true);
  });

  it("conserves the root allocation over any sequence of grants", () => {
    fc.assert(
      fc.property(
        fc.double({ min: 0, max: 1000, noNaN: true }),
        fc.array(fc.double({ min: 0, max: 300, noNaN: true }), { maxLength: 20 }),
        (allocation, requests) => {
          const root = rootEnvelope(task("root"), allocation);
          let parent: Envelope = root;
          const children: Array<Envelope> = [];

          for (const [index, request] of requests.entries()) {
            const grant = grantChild(parent, task(`child-${index}`), request);
            if (grant._tag === "Granted") {
              parent = grant.parent;
              children.push(grant.child);
            }
          }

          const outstanding = totalOutstanding([parent, ...children]);
          // Nothing minted: what the subtree holds plus what the parent still
          // has never exceeds what the root started with.
          return outstanding <= root.allocated + 1e-9;
        }
      ),
      { numRuns: 300 }
    );
  });

  it("never lets a grant increase the parent's remaining allocation", () => {
    fc.assert(
      fc.property(
        fc.double({ min: 0, max: 1000, noNaN: true }),
        fc.double({ min: 0, max: 1000, noNaN: true }),
        (allocation, request) => {
          const parent = rootEnvelope(task("root"), allocation);
          const before = remaining(parent);
          const grant = grantChild(parent, task("child"), request);
          const after = grant._tag === "Granted" ? remaining(grant.parent) : before;
          return after <= before + 1e-9;
        }
      ),
      { numRuns: 300 }
    );
  });
});
