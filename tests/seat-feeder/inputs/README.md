# tests/seat-feeder/inputs — the fixture's two redirected sources

U-D12 DF-SEAT-FEEDER (dotfiles#315). `tools/feeder-fixture.sh` runs the real
`home/dot_local/bin/tally-seat-feeder`, unmodified, with only its two external
sources pointed here and its clock pinned by `TALLY_FEEDER_NOW`. Nothing in the
oracle touches a credential, a network socket, or a live rollout.

| file | replaces | why it can be a fixture |
|---|---|---|
| `stamp-receipt-fixture.py` | `$TALLY_STAMP_RECEIPT`, i.e. `research-methods/bin/stamp-receipt.py window` | the real reader opens `~/.claude*/.credentials.json` and calls the OAuth usage endpoint; an oracle may do neither. Its numbers are the MEASURED 11:39Z readings from DECISIONS.md D-B5. |
| `codex-sessions/` | `$TALLY_CODEX_SESSIONS`, i.e. `~/.codex/sessions` | the real rollouts are Nayla's session logs; the fixture carries three lines in the same schema, with the `rate_limits.primary` cells (`used_percent`, `window_minutes`, `resets_at`) the reader is coded against. `resets_at` is the epoch integer Codex actually writes. |

The `pi-qwencloud` writer has no source to redirect: it reads nothing, by
decision (D-B17 / TL-17 unset). That is the point of it.

The rollout fixture's shape was taken from a real record on this box on
2026-09-06 (`"rate_limits":{"limit_id":"codex",…,"primary":{"used_percent":52.0,
"window_minutes":10080,"resets_at":1785905021}…}`); the token-usage numbers
around it are illustrative and nothing reads them.
