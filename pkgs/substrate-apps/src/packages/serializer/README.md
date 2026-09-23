# @substrate/serializer

The deterministic serializer `TALLY-SPEC-2026-09-06.md` §2.2e names: **stable
key order** (sorted, not insertion), **LF**, a **trailing newline**, and every
timestamp normalised to **ISO-8601 UTC**.

It is the precondition for every `cmp`-identical oracle in this suite — U-A13,
U-A14, U-A20, U-E5, U-E6 all borrow this unit's property. Without it two runs
differ for reasons that carry no information.

Landed by **U-A12** on `lake/serializer`. The rules, the measurements over the
estate, and the oracle: `docs/serializer.md`.

## What is here

```
src/Serializer.ts   key order, line discipline, the refusals, and the readings
                    the fixture tool takes back over its own output
src/Iso8601.ts      the timestamp rule, stated in full before the code: what is
                    normalised, what is declined and why, and the fraction rule
src/KeyOrder.ts     withReversedKeyOrder — the input permutation the
                    stable-key-order claim is measured against
src/index.ts        the entry point
```

## The entry points

```ts
serializeValue(record)      // one record, canonical, no newline
serializeLine(record)       // the same, LF-terminated
serializeRecords(records)   // many, one per line, with the trailing newline
```

plus `normaliseIso8601` (the timestamp rule alone), `checkLineDiscipline` and
`checkRow` (the properties re-measured on the bytes rather than trusted to the
code), and `withReversedKeyOrder`.

## Two things worth knowing before reading the code

**Sorting is not a taste.** `Object.keys(JSON.parse('{"10":1,"2":1}'))` is
`["2", "10"]`: integer-like keys are enumerated in ascending numeric order ahead
of every other key, so a parsed object's key order is already not the source
order and depends on what the keys happen to spell. Insertion order is an
accident of the input's spelling.

**Every unsupported value throws.** `JSON.stringify` drops `undefined`, a
function and a symbol from an object silently, writes `NaN`, the infinities and
a sparse hole as `null`, and calls `toJSON` on a `Date`. Each is a place where
the output stops being a function of the input in a way nobody sees. This
package refuses all of them by name and by path (`$.a[0].b`).

## Verbs

```sh
sh tools/check-serializer.sh                                       # the unit's oracle, rc 0
sh tools/check-serializer.sh --negative-control insertion-order    # the mutation_hint, RED
sh scripts/test.sh --exec node node_modules/.bin/vitest run        # from this directory
```

This package reads no path and writes nothing. The tool that reads the estate is
`tools/serialize-fixture.mjs`, and it reads only.
