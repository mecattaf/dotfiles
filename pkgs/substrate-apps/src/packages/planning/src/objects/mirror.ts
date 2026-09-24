/**
 * The mirror: witness records copied, verified for continuity, never authored.
 *
 * The lake is a mirror and never a ledger. It holds what is safe to copy —
 * witness records verbatim with their sequence and hash, capacity readings, plan
 * hashes — and it verifies chaining on arrival, records any gap and never fills
 * one. The box keeps proof; the lake keeps the record that planning reads.
 *
 * There is one chain per executor and they are verified separately. A kernel is
 * anything with its own single-writer ledger, so two executors produce two
 * chains whose sequences and hashes have nothing to do with one another;
 * folding them into one would manufacture gaps that do not exist and hide gaps
 * that do.
 *
 * The discipline is tally's own, stated for watch cursors and adopted here
 * verbatim: fresh snapshot, explicit gap, never pretend continuity. A collector
 * disconnected for a stretch has lost that stretch permanently, and the honest
 * response is to open a fresh interval and mark it, never to interpolate.
 *
 * Nothing here derives a verdict: what this module holds is the continuity
 * reading over records that arrived already parsed by their owning schema, and
 * nothing in the heuristics or the release evaluator can construct one. The
 * parse-and-mirror entry point itself was cleared by FOLD-2L — the Worker's own
 * mirror in `packages/factory` is what runs, and nothing imported this one.
 */
import { Option } from "effect";
import type { ExecutorId } from "../schema/ids.ts";
import { Verdict } from "../schema/records.ts";
import type { ContinuityGap } from "../schema/records.ts";

/** The state of one executor's mirrored chain. */
interface ChainState {
  /** The last record accepted, or `None` before the first. */
  readonly last: Option.Option<Verdict>;
  /** Gaps observed, in the order they were observed. Never removed. */
  readonly gaps: ReadonlyArray<ContinuityGap>;
}

/** What accepting one record did to the chain. */
interface ChainAdvance {
  /** The chain after the record. */
  readonly state: ChainState;
  /**
   * Whether the record continued the chain.
   *
   * A false value does not reject the record: the record is still mirrored,
   * because refusing to mirror a record because its predecessor is missing would
   * turn one gap into a permanent stall. The gap is recorded beside it.
   */
  readonly continuous: boolean;
}

/** An empty chain. */
const emptyChain: ChainState = { last: Option.none(), gaps: [] };

/**
 * Accepts one mirrored record, verifying continuity.
 *
 * @param state - The chain so far.
 * @param verdict - The record that arrived, already parsed by its owning schema.
 * @returns The advanced chain and whether the record continued it. A record
 *   whose predecessor hash does not match, or whose sequence skips, records a
 *   gap; the gap is never filled and never interpolated over.
 */
const advanceChain = (state: ChainState, verdict: Verdict): ChainAdvance => {
  if (Option.isNone(state.last)) {
    return { state: { last: Option.some(verdict), gaps: state.gaps }, continuous: true };
  }
  const previous = state.last.value;
  const continuous =
    verdict.prevHash === previous.hash && verdict.seq === previous.seq + 1;
  if (continuous) {
    return { state: { last: Option.some(verdict), gaps: state.gaps }, continuous: true };
  }
  const gap: ContinuityGap = {
    executor: verdict.executor,
    after: previous.seq,
    before: verdict.seq
  };
  return {
    state: { last: Option.some(verdict), gaps: [...state.gaps, gap] },
    continuous: false
  };
};

/**
 * The mirror across every executor: one chain each, verified separately.
 *
 * Keyed by executor id, because a kernel is anything with its own single-writer
 * ledger and two ledgers share nothing. An executor the mirror has not seen
 * before starts a fresh chain rather than continuing anyone else's.
 */
export type MirrorState = ReadonlyMap<ExecutorId, ChainState>;

/** An empty mirror, with no executor yet seen. */
export const emptyMirror: MirrorState = new Map<ExecutorId, ChainState>();

/**
 * Accepts one record into the chain of the executor that witnessed it.
 *
 * @param mirror - The mirror so far.
 * @param verdict - The record that arrived, already parsed.
 * @returns The mirror with that one executor's chain advanced, and whether the
 *   record continued *that* chain. A record from an unseen executor is
 *   continuous by definition: it is the first link, not a break in someone
 *   else's.
 */
export const advanceMirror = (
  mirror: MirrorState,
  verdict: Verdict
): { readonly mirror: MirrorState; readonly continuous: boolean } => {
  const chain = mirror.get(verdict.executor) ?? emptyChain;
  const advanced = advanceChain(chain, verdict);
  const next = new Map(mirror);
  next.set(verdict.executor, advanced.state);
  return { mirror: next, continuous: advanced.continuous };
};

/**
 * Every gap the mirror holds, across every executor.
 *
 * @returns The gaps, each naming the executor whose chain has it. Gaps are
 *   recorded and never filled, and one executor's gap says nothing about
 *   another's.
 */
export const mirrorGaps = (mirror: MirrorState): ReadonlyArray<ContinuityGap> => {
  const gaps: Array<ContinuityGap> = [];
  for (const chain of mirror.values()) gaps.push(...chain.gaps);
  return gaps;
};
