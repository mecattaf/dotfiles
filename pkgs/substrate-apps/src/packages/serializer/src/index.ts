/**
 * @substrate/serializer — U-A12 LAKE-SERIALIZER.
 *
 * The deterministic serializer §2.2e names: stable key order (sorted, not
 * insertion), LF, a trailing newline, and every timestamp normalised to
 * ISO-8601 UTC. It is the precondition for every `cmp`-identical oracle in this
 * suite (U-A13, U-A14, U-A20, U-E5, U-E6): without it two runs differ for
 * reasons that carry no information.
 *
 * One entry point per property, and one for a whole corpus:
 *
 *   serializeValue(record)     one record, canonical, no newline
 *   serializeLine(record)      the same, LF-terminated
 *   serializeRecords(records)  many, one per line, trailing newline
 *
 * plus the readings the fixture tool takes over its own output
 * (`checkLineDiscipline`, `checkRow`), the timestamp rule on its own
 * (`normaliseIso8601`), and the permutation the stable-key-order assertion is
 * measured against (`withReversedKeyOrder`).
 *
 * This package writes nothing and reads no path. The corpora belong to other
 * lanes and to a running daemon (CONTRIBUTING.md §2 rule 8); the tool that
 * reads them is `tools/serialize-fixture.mjs`, and it reads only.
 */
export {
  canonicalFraction,
  carriesNonUtcZone,
  normaliseIso8601,
  normaliseTimestamps
} from "./Iso8601.ts"
export { keyOrderOf, withReversedKeyOrder } from "./KeyOrder.ts"
export {
  checkLineDiscipline,
  checkRow,
  compareKeys,
  SerializeError,
  serializeLine,
  serializeRecords,
  serializeValue,
  stringsOf
} from "./Serializer.ts"
