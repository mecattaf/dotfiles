# @substrate/schema

Effect Schema for `{receipt, rung, card}` — `README.md` §5 of the register, plus
the `PROMPTS.md` header's rung fields **minus `predicted_wallclock`**
(**R-2026-09-05-16** removes it from the type, not only from the prose), plus
`RAWA-FLOW.md` §5's receipt line.

Landed by **U-A8** on `lake/schema`. Field-by-field sources, the two divergences
the type found, and what does not decode: `docs/schema.md`.

Extended by **U-A16** on `lake/receipt-strict` with §2.3's **strict** `Receipt` —
every measured cell required, no nullable cell anywhere, and the nine ciru fields
of `DECISIONS.md` D-B22. It is a second type beside the banked one, and
`docs/receipt-strict.md` says why, field by field.

## What is here

```
src/Frontmatter.ts   the YAML subset the register's front matter uses, and a
                     refusal for everything else — not a YAML implementation
src/Common.ts        the shared vocabularies, each marked SOURCED or MEASURED,
                     and WALLCLOCK_FIELDS, the R-2026-09-05-16 denylist
src/Card.ts          Card, and the structs under it
src/Rung.ts          Rung and Shenanigan
src/Receipt.ts       BankedReceipt (RAWA-FLOW §5, as the estate has already
                     banked it), DetectorReceipt (P12's ledger row),
                     AttemptReceipt (the box's line, a tagged union on `kind`)
src/ReceiptStrict.ts Receipt — §2.3's line, strict: every measured cell required,
                     `tokens` not nullable (TL-7 / D-B7), D-B22's ciru fields
src/index.ts         the decoders, and the one parse posture they run under
test/                106 tests
```

`decodeReceipt` is §2.3's strict decoder; `decodeBankedReceipt` reads the corpus
shape. The two are different types because 19 banked lines carry `tokens: null`
and they are the evidence the rule is enforced — see `docs/receipt-strict.md` §1.

## The one parse posture

Every decoder is built with `{ onExcessProperty: "error", errors: "all" }`, and
that is not a parameter a caller can drop. It is where R-2026-09-05-16 lives: an
unknown key is a decode failure, so a card carrying `predicted_wallclock` is
**rejected** rather than quietly stripped. `assertNoWallclockField` runs over
every struct's declared keys as the module loads, so the field cannot come back
without an import-time throw.

Predicted tokens are a usage quantity and stay; measured seconds on a receipt
are an outcome and stay.

## What is NOT here

The wire types generated from the kernel's three Rust constants
(`ENQUEUE_PAYLOAD_FIELDS`, `WireErrorCode`, `TallyEvent`) — `LAKE-WIRE`'s, and
read-only against `/home/tom/mecattaf/tally.nix` at `e89ffdf` (hazard H-1).
The deterministic serializer and the projection — `U-A12` and `U-A13`. This
package decodes and never encodes.

Nothing here writes to `/home/tom/research-methods` or to
`/home/tom/.local/state/tally`, and nothing here changes a card's status
(**R-2026-09-05-03**). The lake is a mirror and never a ledger.
