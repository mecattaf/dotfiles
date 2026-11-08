# Pending input belongs to one harness invocation

A final source review found a real replacement race. The captured target used
the terminal UUID and harness conversation ID. If Codex A exited while an image
upload was pending, then Codex B resumed the same conversation in the same Kitty
window and retained shell, those identifiers could match again. Checking that
the current occupant was foreground did not prove it was the original occupant.

Fix `471169f` adds the launcher's exact process generation to the typed hooks,
saved NAS binding, explicit validity query, native Kitty user variable and
captured callback target. It is derived from the existing boot/PID/start/group/
session identity. An old invocation's pending callback, SessionEnd or attention
event cannot target or clear its replacement. Bound legacy targets without a
generation refuse input. Before the first harness hook, generic terminal
gesture semantics remain unchanged; ordinary native text paste also remains.
The NAS check still precedes GUI insertion and is not an atomic cross-host
compare-and-swap.

Functional qualification on November 8, 2026:

- A focused private-PTY test first reproduced the bug on the previous source:
  the old pending worker delivered to the same-conversation replacement.
  After the fix, old and legacy targets refuse while the fresh target succeeds.
- All 154 aggregate tests passed through `runtime-test` on Strix.
- Actual managed Codex 0.167.0 and Claude 2.1.319 passed their private offline
  hook, image, transcript and foreground suspend/resume gates. Codex hook trust
  was not bypassed in these managed launcher tests; existing user hooks remain.
- At 04:59:56–05:00:16 UTC, the real native Kitty fixture staged an image and
  paused only the private NAS validity endpoint. Codex A (PID 2173) quit; Codex
  B (PID 3721) resumed the exact same conversation in the same Kitty window and
  SSH child. Releasing the pending worker refused input. Independently sending
  the old captured target to the native custom-kitten callback also refused.
  A fresh gesture attached the image to B without Enter or another request.

The native fixture used activated Kitty 0.50.0 (`d0565fa5…`), the mapped official
Domicile 63db244 engine (`43f0dc75…`) and the earlier frozen stable holder binary
(`6a217563…`), not a newly rebuilt holder. It also retained the preceding actual
fresh-Kitty same-PID Codex thumbnail, unsent draft and 300-line semantic history
checks. The fixture's mock provider and home/network namespaces are private;
no real credentials, live user windows, latency samples or Nix builds were used.
The native restart fixture uses explicitly trusted test hooks; it is separate
from the managed launcher trust qualification above.

Evidence is retained under
`/home/tom/.wt/kitty-consolidation/artifacts/invocation-generation/`:
`regression-before.*`, `aggregate.*`, both `managed-*/receipt.json`, and
`native-race-2/receipt.json`, logs and screenshot. The first native attempt
refused the fixture's old hardcoded holder-version assumption before starting
the desktop; its failure logs remain. The successful run passes the allowlisted
holder version explicitly. These are candidate-source proofs, not evidence
that the later rebuilt NAS/seat packages have already run this gate.

Reproduction uses [the native fixture](../tests/native_codex_graphics.py)
with `--offline-codex --invocation-race`, an exact in-checkout holder binary,
`--expected-zmx-sha` and `--holder-version`. The bounded
[orchestrator](../tests/run_invocation_race.py) records exact argv and owns only
its private SSH supervisor and fixture children.

A [small committed receipt set](evidence/invocation-generation/SHA256.json)
travels with this source. The full artifact manifest and logs remain at the NAS
root above; copied receipts do not claim those raw files are all embedded here.
