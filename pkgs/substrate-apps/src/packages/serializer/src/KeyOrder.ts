/**
 * KeyOrder.ts — U-A12 LAKE-SERIALIZER. The input transform the stable-key-order
 * assertion is measured against.
 *
 * "Stable key order" is a claim about two runs over inputs that DIFFER only in
 * the order their keys were written. Running the same generator twice over the
 * same bytes cannot see it: `JSON.parse` is deterministic, so an insertion-order
 * serializer produces the same file twice as happily as a sorted one does. The
 * property only becomes measurable when one of the two runs is fed a record
 * whose keys arrive in a different order.
 *
 * `withReversedKeyOrder` is that permutation: a deep rebuild of every object
 * with its keys in DESCENDING code-unit order — the exact reverse of the
 * contract — leaving arrays, strings, numbers and nulls untouched. Feed one run
 * the record and the other its reversal:
 *
 *   sorted     both runs emit the same bytes            (the green)
 *   insertion  the two runs emit reversed key orders    (the mutation, RED)
 *
 * The reversal is the strongest single permutation available: if any key pair
 * can be swapped, it is swapped. It is also its own inverse in the sense that
 * matters — applying it twice returns the original key order — which the suite
 * asserts, so a permutation that silently did nothing could not pass for one
 * that did.
 */
import { compareKeys } from "./Serializer.ts"

/** Deep-rebuild `value`, ordering every object's keys in descending code-unit order. */
export const withReversedKeyOrder = (value: unknown): unknown => {
  if (value === null || typeof value !== "object") return value
  if (Array.isArray(value)) return value.map(withReversedKeyOrder)
  const proto = Object.getPrototypeOf(value)
  if (proto !== Object.prototype && proto !== null) return value
  const rec = value as Record<string, unknown>
  const out: Record<string, unknown> = {}
  // Object literals keep integer-like keys in ascending numeric order whatever
  // the assignment order, so `out` cannot always carry the reversal literally.
  // That is not a defect of this function: it is the same host rule that makes
  // "insertion order" a property of the key SPELLING rather than of the source
  // text, which is precisely why the contract is `sorted`.
  //
  // `defineProperty` rather than assignment, because `JSON.parse` gives
  // `__proto__` as an ordinary own data property and a plain `out[k] = v` on
  // that key would set the prototype instead of copying the field — the
  // permutation would then silently drop data it was only meant to reorder.
  for (const k of Object.keys(rec).sort(compareKeys).reverse()) {
    Object.defineProperty(out, k, {
      value: withReversedKeyOrder(rec[k]),
      enumerable: true,
      writable: true,
      configurable: true
    })
  }
  return out
}

/** The key order an object enumerates in, at the top level. For the suite. */
export const keyOrderOf = (value: unknown): Array<string> =>
  value !== null && typeof value === "object" && !Array.isArray(value)
    ? Object.keys(value as Record<string, unknown>)
    : []
