# add amd-quark package

**Filed 2026-09-03 from the flashnix container build.** Not yet acted on.

## What stopped

`substrate/container/Containerfile:264` — the editable engine install —

```
pip install -e /opt/vllm --no-build-isolation --extra-index-url ${ROCM_WHL}
ERROR: Could not find a version that satisfies the requirement amd-quark==0.12.post1
       (from versions: 0.1.0, 0.6.0)
```

The pin is upstream vLLM's own, at `requirements/rocm.txt:24` in the engine worktree
(`~/.cache/flashnix/vllm`). `ROCM_WHL` is `https://stable.repo.amd.com/rocm/whl-next/`.

## What is actually true

`amd-quark==0.12.post1` **exists on PyPI.** Measured, not remembered:

```
$ curl -s https://pypi.org/simple/amd-quark/ | grep -o 'amd_quark-[0-9][^-]*'
... 0.11.2  0.12.post1  0.12rc1  0.12rc2  0.12rc3  0.12rc4
```

So the pin is not wrong and the package is not missing. The resolver offered only
`0.1.0, 0.6.0` — the ROCm index's much older copy — which means **pip never reached
PyPI**, even though PyPI was its default primary index and only the ROCm index was
passed as `--extra-index-url`.

## The likely cause, and why it is familiar

This LAN publishes AAAA records with no IPv6 egress. That already broke apt inside the
same build, where every source line came back `Ign:` and the fix was
`Acquire::ForceIPv4 "true"` (flashnix commit `1f06120`). `pypi.org` has AAAA records.
A pip that tries IPv6 first, hangs, and quietly proceeds with whatever index it *could*
reach produces exactly the observed symptom: a real version, invisible.

**Therefore the first thing to try is a network fix, not a pin change** — force IPv4 for
pip the way we already do for apt. Relaxing or dropping the pin would "work" while
leaving the real fault in place, and the next package to live only on PyPI would fail
the same way with a different name.

## Why a nix package may still be wanted

Independent of the container: nothing in this repo packages `amd-quark`, and nixpkgs has
no `amd-quark` attribute. If Quark is ever wanted on the host side rather than only
inside the flashnix image, it needs a `pkgs/amd-quark.nix`. `pkgs/huggingface-cli.nix`
is the nearest existing shape for a Python tool from an upstream wheel.

Open question, deliberately not answered here: **do we need it at all?** Qwen is FP8,
DeepSeek-V4 is native MXFP4, GLM-5.3 is ciru's IU4 — none is Quark-quantized. If every
`quark` import in the engine is lazy and fires only for Quark checkpoints, the honest
answer may be that the dependency is dead weight on our serve paths and the correct fix
is upstream-shaped, not ours.

## Decides what

Nothing yet. No Nix file references amd-quark. When it does, it will be a new
`pkgs/amd-quark.nix` plus whichever host list pulls it in.
