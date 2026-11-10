#ifndef QWEN3_EMBEDDING_CONFIG_HPP_
#define QWEN3_EMBEDDING_CONFIG_HPP_

#include <cstdint>
#include <gufo/ext/gguf_reader.hpp>
#include <optional>
#include <string>

namespace qwen3_embedding {

/// The one geometry this extension runs: Qwen3-Embedding-8B.
inline constexpr std::uint32_t kLayers = 36;
inline constexpr std::uint32_t kHidden = 4096;
inline constexpr std::uint32_t kFeedForward = 12288;
inline constexpr std::uint32_t kHeads = 32;
inline constexpr std::uint32_t kKvHeads = 8;
inline constexpr std::uint32_t kHeadDim = 128;
inline constexpr std::uint32_t kVocab = 151665;
/// llama.cpp's LLAMA_POOLING_TYPE_LAST.
inline constexpr std::uint32_t kPoolingLast = 3;
/// The longest input, in tokens including the appended EOS.
inline constexpr std::size_t kMaxSequenceTokens = 8192;

/// The `qwen3.*` and `tokenizer.ggml.*` scalars of a GGUF. Missing keys stay
/// unset, so a check can say which one is absent.
struct Config {
  std::string architecture;
  std::optional<std::uint32_t> block_count;
  std::optional<std::uint32_t> context_length;
  std::optional<std::uint32_t> embedding_length;
  std::optional<std::uint32_t> feed_forward_length;
  std::optional<std::uint32_t> head_count;
  std::optional<std::uint32_t> head_count_kv;
  std::optional<std::uint32_t> key_length;
  std::optional<std::uint32_t> value_length;
  std::optional<std::uint32_t> pooling_type;
  std::optional<float> rope_freq_base;
  std::optional<float> rms_eps;
  /// Present only for RoPE scaling, which this model does not use.
  bool has_rope_scaling{false};
  /// `qwen3.attention.causal`; absent means causal (llama.cpp's default).
  std::optional<bool> causal;

  std::string tokenizer_model;
  std::string tokenizer_pre;
  std::optional<bool> add_eos;
  std::optional<bool> add_bos;
  std::optional<std::uint32_t> eos_token_id;
  std::optional<std::uint32_t> bos_token_id;
  std::optional<std::uint32_t> eot_token_id;
  std::size_t vocab_size{0};
  std::size_t merges{0};
};

/// Reads the config scalars. Never fails: absent keys stay unset.
[[nodiscard]] Config ReadConfig(const gufo::core::GgufReader& reader);

/// Empty when `config` is exactly Qwen3-Embedding-8B as this extension runs
/// it, else the first mismatch, in words.
[[nodiscard]] std::string CheckConfig(const Config& config);

}  // namespace qwen3_embedding

#endif  // QWEN3_EMBEDDING_CONFIG_HPP_
