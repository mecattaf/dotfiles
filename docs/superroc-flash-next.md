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
being forced into anonymous RAM. Hardware inference qualification is required
before calling the deployment usable.

Downloads are explicit, never service startup or activation. The user
authorized direct public acquisition on Strix followed by a SHA-256 verified
NAS Library copy. Normal borrowing and pruning continue to use the catalog
artifact and the declared wanted set.

Sources:

- [Pinned model card](https://huggingface.co/kingjones777/Qwen3.8-Flash-Next-Uncensored-ROCmFP4-STRIX_LEAN-imatrix-GGUF/blob/737fae2f5ab92c55fde2f4e1da94ad3d17d3d5bb/README.md)
- [Pinned runtime](https://github.com/kingjones30/superroc/tree/5c2b07abd7c432e81180ed70edfa62ed7be4c105)
- [Pinned MTP files](https://huggingface.co/kingjones777/Qwen3.8-Flash-Next-MTP-Heads-GGUF/tree/72805b661c4af3ef63f0ed11e6dafcfdaba33982)
