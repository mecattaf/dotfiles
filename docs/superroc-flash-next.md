# Abliterated Flash-Next ROCmFP4

Tom selected the specific screenshot model on 2026-11-04:
`kingjones777/Qwen3.8-Flash-Next-Uncensored-ROCmFP4-STRIX_LEAN-imatrix-GGUF`,
using its newer `hcq8-ssmf32` files. This is OrcaRouter's directional refusal
edit, quantized by kingjones777; it is not a Heretic 2.0 ARA checkpoint.

The three trunk shards are 98.846 GiB. Together with the Q8 MTP head and
vision projector, the catalog artifact is 103.544 GiB. Exact revisions,
sizes, and SHA-256 hashes live in `lib/coding-comparison-models.json` under
`qwen38-flash-next-abliterated-rocmfp4-gguf`.

These files use custom GGUF types 100/101. The pinned Gufo cannot load them.
`pkgs/superroc` pins the publisher's SuperROC fork at
`5c2b07abd7c432e81180ed70edfa62ed7be4c105`; `modules/superroc.nix`
registers this separate backend with the existing llama-swap supervisor.
The default supervisor group unloads every other large backend before loading
it. The endpoint remains `http://strix-coordinator:8731/v1`, with model ID
`qwen3.8-flash-next-abliterated`.

The initial deployment is text only: one session, 32,768 context, thinking
enabled with low effort, MTP depth three, a fixed 1 GiB retained cache,
and a ten-minute idle timeout. The projector is retained in the Library;
this route does not advertise vision. PLE stays mmap-backed rather than
being forced into anonymous RAM.

Hardware qualification passed on the single 128 GB Strix Halo on 2026-11-04,
through the public supervisor route. The model returned correct arithmetic
with a separate reasoning field, a correct `stable_unique` Python function,
and an exact required function call with JSON arguments. Reported decode
rates were 46.69, 58.04 and 56.42 tokens/s respectively; these are short
smoke requests, not a coding benchmark. The cold arithmetic request took
21.1 seconds including model loading. GTT use was 71.94 GiB with about
48 GiB of host memory available, with the 32K session reserved.

The full DSH Web harness also passed two conversation turns. The first
processed 16,275 prompt tokens in 11.14 seconds end to end. The continuation
reused 16,300 tokens, prefilled only 23, and completed in 0.52 seconds.
Both turns retained separate reasoning output and correct final responses.

The retained request/response evidence is under
`~/.local/state/model-acquisitions/2026-11-04-flash-abliterated/qualification-*.json`
on NAS. The scoped runtime activation preserves all previous routes,
including ARA and D3, and records the previous configuration, content hashes,
and idle-before-restart evidence in
`/var/lib/llama-swap-local-models/flash-route-receipt.json` on Strix.
The launcher has an explicit `local-flash-abliterated` Nix GC root.

Downloads are explicit, never service startup or activation. The user
authorized direct public acquisition on Strix followed by a SHA-256 verified
NAS Library copy. Normal borrowing and pruning continue to use the catalog
artifact and the declared wanted set.

Sources:

- [Pinned model card](https://huggingface.co/kingjones777/Qwen3.8-Flash-Next-Uncensored-ROCmFP4-STRIX_LEAN-imatrix-GGUF/blob/737fae2f5ab92c55fde2f4e1da94ad3d17d3d5bb/README.md)
- [Pinned runtime](https://github.com/kingjones30/superroc/tree/5c2b07abd7c432e81180ed70edfa62ed7be4c105)
- [Pinned MTP files](https://huggingface.co/kingjones777/Qwen3.8-Flash-Next-MTP-Heads-GGUF/tree/72805b661c4af3ef63f0ed11e6dafcfdaba33982)
