/**
 * The tally planning engine.
 *
 * The factory's production-planning and scheduling logic: pure heuristics over
 * object state and one capacity reading, the release evaluator that composes
 * them, and the Durable Object services that hold the state and carry the
 * messages.
 *
 * The package imports no Node API, touches no filesystem, reads no clock and
 * draws no random number. Elapsed intervals, window counts, sequence numbers and
 * the attended flag all arrive as fields on the values the caller supplies,
 * which is what lets the whole engine run inside a Durable Object and what makes
 * a fabricated capacity reading a complete test fixture.
 */
export * from "./schema/index.ts";
export * from "./heuristics/index.ts";
export * from "./release/index.ts";
export * from "./objects/index.ts";
export * from "./capacity/index.ts";
