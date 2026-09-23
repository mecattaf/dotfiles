/**
 * The ledger is the output. One append-only record per admission, dispatch,
 * release and refusal. Serialization is deterministic and load-bearing: stable
 * key order, LF endings, a trailing newline, ISO-8601 UTC timestamps that come
 * from the data and never from a clock read inside the release rule.
 */

/**
 * `outcome` is appended only by a run that supplies `LoopOptions.outcomeOf`,
 * so a run without one produces exactly the bytes it always did. The KEY ORDER
 * below is untouched: item 11's pinned sha256 is a format contract, and a new
 * event VALUE moves no byte of an existing line.
 */
export type LedgerEvent = "derive" | "admit" | "dispatch" | "outcome" | "release" | "refuse" | "abandon";

export interface LedgerEntry {
  readonly seq: number;
  readonly event: LedgerEvent;
  readonly at: string;
  readonly runId: string;
  readonly label: string;
  readonly taskName: string;
  readonly cap: number;
  readonly slotsInUse: number;
  readonly reason: string;
}

/** The key order every serialized entry uses, in full. */
export const LEDGER_KEYS = [
  "seq",
  "event",
  "at",
  "runId",
  "label",
  "taskName",
  "cap",
  "slotsInUse",
  "reason",
] as const;

/**
 * Deterministic bytes for a fixed input under a fixed key order: JSON Lines,
 * LF, trailing newline. Generic over the key list so that a second log with a
 * different shape (the seat dispatch log in `dispatch.ts`, which carries a
 * `seat` and an `argv` this one has no business knowing about) reuses these
 * bytes rather than reimplementing them. LEDGER_KEYS itself does not change:
 * the item 11 ledger's pinned sha256 is a format contract.
 */
export function serializeRecords<T extends object>(
  keys: readonly string[],
  entries: readonly T[],
): string {
  if (entries.length === 0) return "";
  const line = (e: T): string => {
    const parts: string[] = [];
    for (const k of keys) {
      // A-07 of the 2026-09-23 review. `JSON.stringify(undefined)` is the JS
      // value undefined, which template-interpolates to the bare token
      // `undefined`, so a key in the key list with no value on the entry emitted
      // `{"a":1,"b":undefined}`: a jsonl line no reader can parse. `null` is
      // written instead. For an entry whose keys are all defined, which is every
      // entry any log in this repository appends, not one byte moves: item 11's
      // pinned sha256 is unaffected.
      const v = (e as Record<string, unknown>)[k];
      parts.push(`${JSON.stringify(k)}:${JSON.stringify(v === undefined ? null : v)}`);
    }
    return `{${parts.join(",")}}`;
  };
  return entries.map(line).join("\n") + "\n";
}

/** Deterministic bytes for a fixed input: JSON Lines, LF, trailing newline. */
export function serializeLedger(entries: readonly LedgerEntry[]): string {
  return serializeRecords(LEDGER_KEYS, entries);
}

/**
 * An append-only log of records that carry their own `seq`. Entries are never
 * rewritten and never reordered; `append` is the only mutator.
 */
export class AppendOnlyLog<E extends { readonly seq: number; readonly event: string }> {
  readonly #entries: E[] = [];

  constructor(private readonly keys: readonly string[]) {}

  append(e: Omit<E, "seq">): E {
    // A-12 of the 2026-09-23 review. `{ seq, ...e }` let an entry that carried
    // its own `seq` overwrite the assigned one, breaking the one invariant an
    // append-only log has. The spread comes first and `seq` is assigned last, so
    // the log numbers its own entries. Key ORDER in the serialized line comes
    // from the key list, not from insertion order, so no byte moves.
    const entry = { ...e, seq: this.#entries.length } as unknown as E;
    this.#entries.push(entry);
    return entry;
  }

  get entries(): readonly E[] {
    return this.#entries;
  }

  count(event: E["event"]): number {
    return this.#entries.filter((e) => e.event === event).length;
  }

  serialize(): string {
    return serializeRecords(this.keys, this.#entries);
  }
}

/** An append-only ledger. Entries are never rewritten and never reordered. */
export class Ledger extends AppendOnlyLog<LedgerEntry> {
  constructor() {
    super(LEDGER_KEYS);
  }
}
