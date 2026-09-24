/**
 * The heuristic inventory.
 *
 * Every mechanical heuristic the production-planning and scheduling canon
 * supplies, each as one pure function over object state and a capacity reading.
 * None of them performs input or output, resolves a service, reads a clock or
 * draws a random number, which is what makes each of them separately testable
 * against a fabricated reading.
 *
 * These are pure functions rather than Effect services on purpose: the coding
 * standard reserves contextual services for capabilities and runtime state, and
 * keeps genuinely pure construction local to its owning module. The services in
 * `objects` compose these; nothing here depends on anything there.
 *
 * Four of the seventeen are no longer here. `protectionLevel.ts`,
 * `shrinkage.ts`, `cpmFloat.ts` and `leastCostLast.ts` exported names that
 * nothing imported — not this barrel's consumers, not a test, not a tool — and
 * FOLD-2L cleared them under R-2026-09-06-21. A re-export is not a use, which
 * is the whole reason a barrel could hide them for as long as it did. See
 * `docs/dead-code.md`.
 */
export * from "./conwip.ts";
export * from "./valueDensity.ts";
export * from "./lengthTermFlip.ts";
export * from "./paceLine.ts";
export * from "./envelope.ts";
export * from "./localFirst.ts";
export * from "./redundancy.ts";
export * from "./eddCertificate.ts";
export * from "./killRedispatch.ts";
export * from "./runtimeCap.ts";
export * from "./subassemblyBatching.ts";
export * from "./namespaceRoundRobin.ts";
export * from "./fillerLane.ts";
export * from "./bufferAndon.ts";
