/**
 * The Durable Objects, as Effect services.
 *
 * Each is a contextual service over a storage interface that a Durable Object's
 * SQLite Layer implements. This package writes the interface and a
 * behaviourally faithful in-memory Layer; the binding itself belongs in the host
 * package, because a binding is a composition-root concern and a library that
 * reaches for one stops running on the hermetic bench.
 *
 * The objects hold state and carry messages. They do not decide: the whole
 * release rule is the pure function in `release`, which they call and whose
 * result they act on.
 *
 * `campaign.ts` — the Campaign object and its worklist reconciler — was cleared
 * by FOLD-2L: every name it exported was imported by nothing, here or in any
 * test or tool. The sketch's copy and its `docs/port-manifest.tsv` row keep the
 * record; `docs/dead-code.md` names it and the rule that found it.
 */
export * from "./storage.ts";
export * from "./hasher.ts";
export * from "./factory.ts";
export * from "./kernel.ts";
export * from "./mirror.ts";
