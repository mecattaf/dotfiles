# qwen3-embedding-gufo-extension

A community [Gufo](https://github.com/gufo-org/gufo) extension that serves
[Qwen3-Embedding-8B](https://huggingface.co/Qwen/Qwen3-Embedding-8B-GGUF)
from its Q8_0 GGUF through `gufo serve embedding` and `POST /v1/embeddings`.

Status: in development. Built against Gufo v0.33.0
(`77dff828be02a498e9951694f31b024e7ac87119`, extension API 0.2.21) on
gfx1151 (Strix Halo), Linux only. Vectors match llama.cpp b9925 at cosine
0.999508 or better on the 128 reference texts; see `docs/QUALITY.md`.

- Extension `qwen3_embedding`, provider `qwen3-embedding`, served model id
  `qwen3-embedding-8b`.
- `--model` takes the `.gguf` file. The probe accepts only the Qwen3
  embedding geometry (36 layers, hidden 4096, 32/8 heads of 128, FFN 12288,
  last-token pooling, EOS appended, no LM head) with Q8_0 matrices.
- Tokenization is a port of llama.cpp's Qwen2 byte-level BPE (build 9925),
  so token ids match llama.cpp's `llama-server`.

Install as a module into an installed Gufo with its SDK:

```sh
gufo extension install /path/to/qwen3-embedding-gufo-extension --yes
gufo diagnose --section extensions   # provider qwen3-embedding: available
```

Licensed MIT; see `LICENSE` and `THIRD_PARTY_NOTICES.md`.
