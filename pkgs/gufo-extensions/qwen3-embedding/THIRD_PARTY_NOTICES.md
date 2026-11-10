# Third-party notices

This extension adapts code from the projects below. Each is MIT licensed; the
full text of each license follows its entry. The extension's own code is MIT
licensed too (see `LICENSE`).

## Gufo (EmbeddingGemma 2 extension)

Source: `github.com/gufo-org/gufo` at v0.33.0
(`77dff828be02a498e9951694f31b024e7ac87119`), `src/models/embedding_gemma2/`.

Adapted here:

- `src/batch_scheduler.{hpp,cpp}` from `batch_scheduler.{hpp,cpp}`: the
  cross-request batch scheduler, with the image and audio paths removed.
- `tests/batch_scheduler_test.cpp` from
  `tests/models/embedding_gemma2/batch_scheduler_test.cpp`, with the image
  cases removed.
- The runtime shape of `src/hip/encoder_runtime.{hpp,cpp}` (device buffers,
  `OnDevice`, `DeviceUsable`) and the registration pattern of
  `src/extension.cpp` and `src/provider.cpp`.

```
MIT License

Copyright (c) 2026 gufo contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## lfm3-gufo-extension (HIP kernels)

Source: `github.com/gufo-org/lfm3-gufo-extension` at `23efc07`.

Adapted here:

- `src/hip/q8_prefill.hpp` from `hip/q8_prefill.hpp` (Q8_0 x split-FP16
  WMMA prompt GEMM), namespace renamed.
- `src/hip/ops.{hpp,hip}` from `hip/ops.{hpp,hip}`: the embedding gather,
  residual RMS norm, Q8_0 projections, fused SwiGLU FFN, RoPE, per-head
  Q/K norm and causal attention launchers, namespace renamed and the kernels
  this model does not use removed.

```
MIT License

Copyright (c) 2026 gufo contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## llama.cpp (tokenizer)

Source: `github.com/ggml-org/llama.cpp` at
`ed8c26150e6b0ed6e2635cab75ace5ed121482ca` (build 9925).

Adapted here:

- `src/tokenizer/unicode.{hpp,cpp}` from `src/unicode.{h,cpp}`: UTF-8
  decoding, code point flags, the GPT-2 byte-to-unicode map and the
  hand-written Qwen2 pre-tokenizer `unicode_regex_split_custom_qwen2`.
- `src/tokenizer/unicode_data.cpp` from `src/unicode-data.cpp`: the code point
  flag ranges, the whitespace set and the lowercase map, copied verbatim.
- `src/tokenizer/tokenizer.cpp` from `src/llama-vocab.cpp`: the special-token
  partition (`tokenizer_st_partition`), the byte-level BPE merge
  (`llm_tokenizer_bpe_session::tokenize`) and the text rules that mark
  special tokens.

```
MIT License

Copyright (c) 2023-2026 The ggml authors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
