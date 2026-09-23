# @substrate/planning

The planning heuristics, ported out of the sketch at
`/home/tom/Sept2/planning-engine/packages/planning`: 46 `src` modules
(`schema/` 16, `heuristics/` 18, `release/`, `objects/`) and 9 `test` files
carrying 86 `it(` calls — all MEASURED 2026-09-06, and the suite MEASURED green,
`numTotalTests 86`, `numFailedTests 0`.

**The test files are copied byte-identical**, so that "the 86 tests unchanged and
green" is provable by `diff -r` rather than by assertion. The sketch is not a git
repository and is read-only for this work.

Empty on `lake/skeleton` by design. `package.json`, `tsconfig.json`, the
dependency tree (U-A3, local copy with provenance, zero network) and the port
itself (U-A7) replace this placeholder.
