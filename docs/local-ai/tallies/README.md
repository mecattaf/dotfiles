# Local-AI roster rationale

[`2026-07-22.md`](2026-07-22.md) is the reviewed anchor for the current typed
model roster. Add another file here only when a human-approved roster decision
needs durable rationale alongside `lib/local-models.nix`.

The monthly source-review bot does not generate files in this directory. It
commits only mechanically advanced pins in
`pkgs/local-ai-monthly/sources.json`; exact intervals, checks, and Pi's advisory
recommendations live in the pull-request body. Rejecting or abandoning that PR
therefore leaves the next comparison interval unchanged.

Any future roster edit remains a separate human change. It must preserve exact
artifact identity, immutable HF revision, selected files and sizes, LFS
SHA-256/Nix SRI, runtime provenance, evidence class, and the independent
`downloadAllModels = false` gate.
