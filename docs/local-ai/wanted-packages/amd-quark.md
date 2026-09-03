# amd-quark: cp314 outruns the pin — RESOLVED in flashnix, open question for us

**Filed 2026-09-03 from the flashnix container build. Resolved the same evening.**
The first version of this page blamed the network and was wrong; the corrected
diagnosis is below, because the wrong one is an easy mistake to make twice.

## What stopped

`substrate/container/Containerfile` — the editable engine install —

```
pip install -e /opt/vllm --no-build-isolation --extra-index-url ${ROCM_WHL}
ERROR: Could not find a version that satisfies the requirement amd-quark==0.12.post1
       (from versions: 0.1.0, 0.6.0)
```

## The actual cause: Python 3.14, not the index

The image runs `PYTHON_VERSION=3.14.3`. Every amd-quark release caps
`Requires-Python` below cp314:

| version | Requires-Python |
|---|---|
| 0.12.post1 | `>=3.11,<3.14` |
| 0.11.2 (and 0.9-0.11.x) | `>=3.9.0,<3.13` |
| 0.6.0 | `>=3.9.0` |
| 0.1.0 | `>=3.6` |

pip discarded every capped release and offered exactly the two with **no upper
bound** — which is the entire `from versions: 0.1.0, 0.6.0`. The pin was correct,
the package was present, and pip was reading PyPI the whole time.

**What I got wrong, and why it looked right.** I saw `0.12.post1` on
`pypi.org/simple/amd-quark/`, saw only `0.1.0, 0.6.0` in the resolver's list, and
concluded pip had never reached PyPI — the same AAAA-with-no-IPv6-egress trap that
had genuinely broken apt inside this same image an hour earlier (flashnix `1f06120`).
A recent real fault is a seductive explanation for the next symptom. The tell I
missed: `/simple/` lists filenames and hides `Requires-Python`, so "the version is
listed" and "the version is installable" are different claims, and only the JSON API
distinguishes them. Checking `pypi.org/pypi/amd-quark/0.12.post1/json` would have
shown `<3.14` immediately.

Second correction: **the ROCm index carries no amd-quark at all** — its project URL
404s where torch, rocm and triton all 301. So the two offered versions came from
PyPI, not from "the ROCm index's older copy" as the first version of this page said.

## How flashnix fixed it

A dedicated step ahead of the engine install (`Containerfile:277`, flashnix `e6873a9`)
installs the same pinned version with `--ignore-requires-python` scoped to that one
step; the engine then finds the pin already satisfied. `ARG QUARK_PIN` holds the
version and the engine-extract step asserts it still matches the engine's own
`requirements/rocm.txt:24`, so the two cannot drift silently. The engine worktree was
not touched.

Verified in throwaway containers rather than by a full rebuild: the failure reproduces
byte-for-byte, the new step exits 0, all 57 deps resolve to cp314 wheels with no
sdist, and the exact command that died now passes `--dry-run`.

## What is still open for this repo

**Do we need amd-quark at all?** Qwen is FP8, DeepSeek-V4 is native MXFP4, GLM-5.3 is
ciru's IU4 — none is Quark-quantized. If every `quark` import in the engine is lazy,
the dependency is dead weight on our serve paths and the upstream-shaped fix is to
drop it, not to bypass its metadata. Unanswered.

**cp314 will do this again.** Running a 3.14 interpreter ahead of the ecosystem means
any pure-Python dependency whose maintainer caps `Requires-Python` disappears from
resolution with a message that looks like a missing package. Worth knowing as a class
of failure before the next one costs an hour.

**Startup cost, for whoever watches a first serve:** quark JIT-compiles a stable-ABI
C++ `hw_emulation` extension on first import — ~2.8s on gfx1151, needs the GPU and
hipcc, both present at serve time. Fast, but a real compile in the startup path. Do
not mistake it for a hang.

**A nix package is not currently wanted.** Nothing here packages amd-quark and nothing
needs it host-side; it lives inside the flashnix image. If that changes,
`pkgs/huggingface-cli.nix` is the nearest existing shape.

## Decides what

Nothing in this repo. The fix lives in flashnix `substrate/container/Containerfile`.
