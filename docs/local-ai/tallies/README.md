# Local-AI roster rationale

[`2026-07-29.md`](2026-07-29.md) is the reviewed anchor for the current typed
model roster. Add another file here only when a human-approved roster decision
needs durable rationale alongside `lib/local-models.nix`.

Any future roster edit remains a separate human change. It must preserve exact
artifact identity, immutable HF revision, selected files and sizes, LFS
SHA-256/Nix SRI, runtime provenance, evidence class, Q8 precision policy, and
explicit coordinator allowlist.

The superseded topology-era tallies (2026-07-22 and 2026-07-26) were removed on
2026-08-03 and are readable from Git history; [`../../old/README.md`](../../old/README.md)
indexes them. They are evidence only.
