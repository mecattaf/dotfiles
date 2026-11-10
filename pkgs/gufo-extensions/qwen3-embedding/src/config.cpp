#include "config.hpp"

#include <cmath>
#include <string_view>

namespace qwen3_embedding {
namespace {

std::string Field(std::string_view key) { return std::string(key); }

/// "<key> is <value>, expected <expected>" or "<key> is missing".
std::string Mismatch(std::string_view key, std::optional<std::uint32_t> value,
                     std::uint32_t expected) {
  if (!value.has_value()) {
    return Field(key) + " is missing";
  }
  return Field(key) + " is " + std::to_string(*value) + ", expected " +
         std::to_string(expected);
}

}  // namespace

Config ReadConfig(const gufo::core::GgufReader& reader) {
  Config config;
  config.architecture =
      std::string(reader.GetMetadataString("general.architecture").value_or(""));
  config.block_count = reader.GetMetadataUint32("qwen3.block_count");
  config.context_length = reader.GetMetadataUint32("qwen3.context_length");
  config.embedding_length = reader.GetMetadataUint32("qwen3.embedding_length");
  config.feed_forward_length =
      reader.GetMetadataUint32("qwen3.feed_forward_length");
  config.head_count = reader.GetMetadataUint32("qwen3.attention.head_count");
  config.head_count_kv =
      reader.GetMetadataUint32("qwen3.attention.head_count_kv");
  config.key_length = reader.GetMetadataUint32("qwen3.attention.key_length");
  config.value_length = reader.GetMetadataUint32("qwen3.attention.value_length");
  config.pooling_type = reader.GetMetadataUint32("qwen3.pooling_type");
  config.rope_freq_base = reader.GetMetadataFloat32("qwen3.rope.freq_base");
  config.rms_eps =
      reader.GetMetadataFloat32("qwen3.attention.layer_norm_rms_epsilon");
  config.has_rope_scaling =
      reader.FindMetadata("qwen3.rope.scaling.type") != nullptr ||
      reader.FindMetadata("qwen3.rope.scaling.factor") != nullptr ||
      reader.FindMetadata("qwen3.rope.dimension_count") != nullptr;
  config.causal = reader.GetMetadataBool("qwen3.attention.causal");

  config.tokenizer_model =
      std::string(reader.GetMetadataString("tokenizer.ggml.model").value_or(""));
  config.tokenizer_pre =
      std::string(reader.GetMetadataString("tokenizer.ggml.pre").value_or(""));
  config.add_eos = reader.GetMetadataBool("tokenizer.ggml.add_eos_token");
  config.add_bos = reader.GetMetadataBool("tokenizer.ggml.add_bos_token");
  config.eos_token_id = reader.GetMetadataUint32("tokenizer.ggml.eos_token_id");
  config.bos_token_id = reader.GetMetadataUint32("tokenizer.ggml.bos_token_id");
  config.eot_token_id = reader.GetMetadataUint32("tokenizer.ggml.eot_token_id");
  if (const auto* tokens = reader.FindMetadata("tokenizer.ggml.tokens")) {
    if (const auto* list =
            std::get_if<std::vector<std::string_view>>(&tokens->value)) {
      config.vocab_size = list->size();
    }
  }
  if (const auto* merges = reader.FindMetadata("tokenizer.ggml.merges")) {
    if (const auto* list =
            std::get_if<std::vector<std::string_view>>(&merges->value)) {
      config.merges = list->size();
    }
  }
  return config;
}

std::string CheckConfig(const Config& config) {
  if (config.architecture != "qwen3") {
    return "general.architecture is '" + config.architecture +
           "', expected 'qwen3'";
  }
  if (config.pooling_type != kPoolingLast) {
    return Mismatch("qwen3.pooling_type", config.pooling_type, kPoolingLast);
  }
  if (config.add_eos != true) {
    return "tokenizer.ggml.add_eos_token is not true";
  }
  if (config.add_bos.value_or(false)) {
    return "tokenizer.ggml.add_bos_token is true";
  }
  if (config.tokenizer_model != "gpt2") {
    return "tokenizer.ggml.model is '" + config.tokenizer_model +
           "', expected 'gpt2'";
  }
  if (config.tokenizer_pre != "qwen2") {
    return "tokenizer.ggml.pre is '" + config.tokenizer_pre +
           "', expected 'qwen2'";
  }
  const struct {
    std::string_view key;
    std::optional<std::uint32_t> value;
    std::uint32_t expected;
  } geometry[] = {
      {"qwen3.block_count", config.block_count, kLayers},
      {"qwen3.embedding_length", config.embedding_length, kHidden},
      {"qwen3.feed_forward_length", config.feed_forward_length, kFeedForward},
      {"qwen3.attention.head_count", config.head_count, kHeads},
      {"qwen3.attention.head_count_kv", config.head_count_kv, kKvHeads},
      {"qwen3.attention.key_length", config.key_length, kHeadDim},
      {"qwen3.attention.value_length", config.value_length, kHeadDim},
  };
  for (const auto& field : geometry) {
    if (field.value != field.expected) {
      return Mismatch(field.key, field.value, field.expected);
    }
  }
  if (config.has_rope_scaling) {
    return "RoPE scaling or partial rotary keys are present";
  }
  if (config.causal.has_value() && !*config.causal) {
    return "qwen3.attention.causal is false";
  }
  if (!config.rope_freq_base.has_value() ||
      std::fabs(*config.rope_freq_base - 1.0e6F) > 1.0F) {
    return "qwen3.rope.freq_base is not 1e6";
  }
  if (!config.rms_eps.has_value() ||
      std::fabs(*config.rms_eps - 1.0e-6F) > 1.0e-9F) {
    return "qwen3.attention.layer_norm_rms_epsilon is not 1e-6";
  }
  if (config.vocab_size != kVocab) {
    return "tokenizer.ggml.tokens has " + std::to_string(config.vocab_size) +
           " entries, expected " + std::to_string(kVocab);
  }
  if (config.merges == 0) {
    return "tokenizer.ggml.merges is missing";
  }
  if (!config.eos_token_id.has_value() || *config.eos_token_id >= kVocab) {
    return "tokenizer.ggml.eos_token_id is missing or out of range";
  }
  return {};
}

}  // namespace qwen3_embedding
