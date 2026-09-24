/**
 * Local-first routing, and the only three grounds for escalation.
 *
 * Blueprint section 1.3(2) gives the sequential-testing argument. Trying the
 * free lane first costs `c_L + (1 - yhat_L) * gamma_C * c_C`; going straight to
 * the metered lane costs `gamma_C * c_C`. With `c_L = 0` the first is smaller
 * whenever `yhat_L > 0`, so local-first is optimal whenever the local model has
 * any chance at all. The classical slow-server threshold — idle the slow server
 * until the queue is deep — is backwards here, because the fast server is
 * metered against a perishable envelope and the slow one is free.
 *
 * Volume II Part III section 1 supplies the eligibility structure. This is not
 * general machine eligibility but the grade-of-service special case: each item
 * carries a capability floor and runs on any member at or above it. Nesting
 * removes the pathological instances and makes the assignment subproblem small,
 * structured and exactly solvable, which is why the plant should stop treating
 * "which lane" as a judgment call. What nesting does not do is order the
 * machines: capability is nested and cost is anti-nested, so the assignment is
 * genuinely two-dimensional and never collapses to "use the best available".
 *
 * Section 8 closes the case against dedication: tooling changeover is free, only
 * material state carries, so classes express capability floors and never
 * dedication, and any instinct toward a per-family lane imports an assumption
 * this plant does not satisfy.
 */
import { Option } from "effect";
import type { CatalogMember } from "../schema/catalog.ts";
import { estimateFor, type EstimateTable } from "../schema/estimate.ts";
import type { ClassName, MemberId } from "../schema/ids.ts";
import type { Estimate } from "../schema/estimate.ts";

/** Why a routing left the free lanes. */
export type EscalationReason =
  /** No free member declares the required class. */
  | "capabilityFloor"
  /** The deadline certificate says the free lane cannot make the date. */
  | "deadline"
  /** A previous attempt on a free lane returned a failed verdict. */
  | "failedVerdict";

/** A resolved routing. */
export interface Routing {
  /** The member chosen. */
  readonly member: MemberId;
  /** Its estimate on this item's class. */
  readonly estimate: Estimate;
  /** Whether the chosen member draws on a metered envelope. */
  readonly metered: boolean;
  /**
   * Why a metered member was chosen.
   *
   * `None` on a free lane. Escalation is permitted on exactly three grounds and
   * the routing records which one applied, so an escalation that had no ground
   * is visible in the release journal rather than invisible in a heuristic.
   */
  readonly escalation: Option.Option<EscalationReason>;
  /** Whether the chosen member is already resident, so a cold load is avoided. */
  readonly warm: boolean;
}

/** What the router needs beyond the catalog. */
interface RoutingContext {
  /** The capability class the item requires. */
  readonly needs: ClassName;
  /** Estimates over the pair-and-class matrix. */
  readonly estimates: EstimateTable;
  /** Members currently resident in local memory, from the capacity reading. */
  readonly residentMembers: ReadonlyArray<MemberId>;
  /** Whether a deadline certificate declares the free path infeasible. */
  readonly deadlinePressure: boolean;
  /** Whether a previous attempt on a free lane returned a failed verdict. */
  readonly priorFailure: boolean;
}

const preferWarm = (
  candidates: ReadonlyArray<readonly [CatalogMember, Estimate]>,
  resident: ReadonlyArray<MemberId>
): Option.Option<readonly [CatalogMember, Estimate]> => {
  let best: Option.Option<readonly [CatalogMember, Estimate]> = Option.none();
  for (const candidate of candidates) {
    const [member, estimate] = candidate;
    if (Option.isNone(best)) {
      best = Option.some(candidate);
      continue;
    }
    const [bestMember, bestEstimate] = best.value;
    const warm = resident.includes(member.id);
    const bestWarm = resident.includes(bestMember.id);
    // Warm beats cold; among equals, higher yield wins, then shorter service.
    if (warm !== bestWarm) {
      if (warm) best = Option.some(candidate);
      continue;
    }
    if (estimate.yieldRate > bestEstimate.yieldRate) {
      best = Option.some(candidate);
      continue;
    }
    if (
      estimate.yieldRate === bestEstimate.yieldRate &&
      estimate.p80Seconds < bestEstimate.p80Seconds
    ) {
      best = Option.some(candidate);
    }
  }
  return best;
};

/**
 * Routes one item, free lanes first.
 *
 * @param eligible - Members declaring the required class, in catalog order.
 *   Order is deterministic for a given catalog, which is what replay needs.
 * @param context - The class, the estimates, what is resident, and the two
 *   conditions that license escalation beyond a missing capability.
 * @returns The routing, or `None` when nothing declares the class at all, which
 *   makes the item unreleasable rather than silently escalated.
 */
export const routeLocalFirst = (
  eligible: ReadonlyArray<CatalogMember>,
  context: RoutingContext
): Option.Option<Routing> => {
  const withEstimates = eligible.map(
    (member) => [member, estimateFor(context.estimates, member, context.needs)] as const
  );

  const free = withEstimates.filter(
    ([member, estimate]) => !member.metered && estimate.yieldRate > 0
  );
  const metered = withEstimates.filter(([member]) => member.metered);

  const mustEscalate: Option.Option<EscalationReason> =
    free.length === 0
      ? Option.some<EscalationReason>("capabilityFloor")
      : context.priorFailure
        ? Option.some<EscalationReason>("failedVerdict")
        : context.deadlinePressure
          ? Option.some<EscalationReason>("deadline")
          : Option.none();

  if (Option.isNone(mustEscalate)) {
    const chosen = preferWarm(free, context.residentMembers);
    return Option.map(chosen, ([member, estimate]) => ({
      member: member.id,
      estimate,
      metered: false,
      escalation: Option.none<EscalationReason>(),
      warm: context.residentMembers.includes(member.id)
    }));
  }

  const chosen = preferWarm(metered, context.residentMembers);
  if (Option.isSome(chosen)) {
    const [member, estimate] = chosen.value;
    return Option.some({
      member: member.id,
      estimate,
      metered: true,
      escalation: mustEscalate,
      warm: context.residentMembers.includes(member.id)
    });
  }

  // Escalation was licensed but no metered member declares the class either.
  // Fall back to the free lanes rather than refusing outright: a positive yield
  // on a free lane still beats not running.
  const fallback = preferWarm(free, context.residentMembers);
  return Option.map(fallback, ([member, estimate]) => ({
    member: member.id,
    estimate,
    metered: false,
    escalation: Option.none<EscalationReason>(),
    warm: context.residentMembers.includes(member.id)
  }));
};
