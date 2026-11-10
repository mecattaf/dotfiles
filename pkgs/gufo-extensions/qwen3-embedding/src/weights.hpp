#ifndef QWEN3_EMBEDDING_WEIGHTS_HPP_
#define QWEN3_EMBEDDING_WEIGHTS_HPP_

#include <cstddef>
#include <cstdint>
#include <gufo/ext/gguf_reader.hpp>
#include <optional>
#include <string>
#include <vector>

namespace qwen3_embedding {

namespace core = gufo::core;

/// One weight as stored in the GGUF: `data` points at its encoded bytes (the
/// reader's mapping on the host, a device buffer after upload). `cols` is the
/// GGUF ne[0] (the input width of a matrix), `rows` is ne[1] (1 for vectors).
struct Tensor {
  const void* data{};
  core::GgmlType type{};
  std::uint32_t cols{}, rows{};
  std::size_t bytes{};
};

struct LayerWeights {
  Tensor attn_norm, q, k, v, q_norm, k_norm, attn_output;
  Tensor ffn_norm, gate, up, down;
};

struct Weights {
  Tensor token_embd, output_norm;
  std::vector<LayerWeights> layers;

  /// Views into the reader's mapping. Fails, with `error`, when any tensor
  /// CheckTensors would refuse is met.
  static std::optional<Weights> Bind(const core::GgufReader& reader,
                                     std::string* error = nullptr);
};

/// Empty when the file holds exactly the 398 tensors of Qwen3-Embedding-8B
/// with Q8_0 matrices, F32 norms and no `output.weight`, else the first
/// problem, in words.
[[nodiscard]] std::string CheckTensors(const core::GgufReader& reader);

}  // namespace qwen3_embedding

#endif  // QWEN3_EMBEDDING_WEIGHTS_HPP_
