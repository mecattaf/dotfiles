// Checks the config reader and the tensor binding: CheckConfig on edited
// configs (no file needed), then, with QWEN3_EMBEDDING_MODEL set, the real
// Q8_0 GGUF's scalars and the shape, type and size of every bound weight.

#include <cstdint>
#include <gufo/ext/gguf_reader.hpp>
#include <iostream>
#include <string>

#include "src/config.hpp"
#include "src/weights.hpp"
#include "tests/support.hpp"

namespace {

using qwen3_embedding::Config;
using qwen3_embedding::testing::Check;

Config GoodConfig() {
  Config config;
  config.architecture = "qwen3";
  config.block_count = 36;
  config.context_length = 40960;
  config.embedding_length = 4096;
  config.feed_forward_length = 12288;
  config.head_count = 32;
  config.head_count_kv = 8;
  config.key_length = 128;
  config.value_length = 128;
  config.pooling_type = 3;
  config.rope_freq_base = 1.0e6F;
  config.rms_eps = 1.0e-6F;
  config.tokenizer_model = "gpt2";
  config.tokenizer_pre = "qwen2";
  config.add_eos = true;
  config.add_bos = false;
  config.eos_token_id = 151643;
  config.vocab_size = 151665;
  config.merges = 151387;
  return config;
}

void CheckRejects(const Config& config, std::string_view mention) {
  const std::string problem = qwen3_embedding::CheckConfig(config);
  Check(!problem.empty(), "config accepted, expected a mention of " +
                              std::string(mention));
  Check(problem.find(mention) != std::string::npos,
        "problem '" + problem + "' does not mention " + std::string(mention));
}

void EditedConfigs() {
  Check(qwen3_embedding::CheckConfig(GoodConfig()).empty(),
        "the reference config is refused: " +
            qwen3_embedding::CheckConfig(GoodConfig()));
  {
    auto config = GoodConfig();
    config.architecture = "qwen2";
    CheckRejects(config, "general.architecture");
  }
  {
    auto config = GoodConfig();
    config.pooling_type.reset();
    CheckRejects(config, "qwen3.pooling_type is missing");
  }
  {
    auto config = GoodConfig();
    config.pooling_type = 1;  // mean
    CheckRejects(config, "qwen3.pooling_type is 1");
  }
  {
    auto config = GoodConfig();
    config.add_eos = false;
    CheckRejects(config, "add_eos_token");
  }
  {
    auto config = GoodConfig();
    config.add_bos = true;
    CheckRejects(config, "add_bos_token");
  }
  {
    auto config = GoodConfig();
    config.tokenizer_pre = "llama3";
    CheckRejects(config, "tokenizer.ggml.pre");
  }
  {
    auto config = GoodConfig();
    config.block_count = 28;  // Qwen3-Embedding-0.6B
    CheckRejects(config, "qwen3.block_count is 28");
  }
  {
    auto config = GoodConfig();
    config.embedding_length = 2560;  // Qwen3-Embedding-4B
    CheckRejects(config, "qwen3.embedding_length");
  }
  {
    auto config = GoodConfig();
    config.head_count_kv = 4;
    CheckRejects(config, "head_count_kv");
  }
  {
    auto config = GoodConfig();
    config.has_rope_scaling = true;
    CheckRejects(config, "RoPE scaling");
  }
  {
    auto config = GoodConfig();
    config.causal = false;
    CheckRejects(config, "causal");
  }
  {
    auto config = GoodConfig();
    config.causal = true;
    Check(qwen3_embedding::CheckConfig(config).empty(),
          "an explicit causal=true is refused");
  }
  {
    auto config = GoodConfig();
    config.rope_freq_base = 10000.0F;
    CheckRejects(config, "freq_base");
  }
  {
    auto config = GoodConfig();
    config.rms_eps = 1.0e-5F;
    CheckRejects(config, "epsilon");
  }
  {
    auto config = GoodConfig();
    config.vocab_size = 151669;
    CheckRejects(config, "tokenizer.ggml.tokens");
  }
  {
    auto config = GoodConfig();
    config.merges = 0;
    CheckRejects(config, "merges");
  }
  {
    auto config = GoodConfig();
    config.eos_token_id = 151665;
    CheckRejects(config, "eos_token_id");
  }
}

void CheckTensor(const qwen3_embedding::Tensor& tensor, std::string_view name,
                 gufo::core::GgmlType type, std::uint32_t cols,
                 std::uint32_t rows) {
  const std::string what(name);
  Check(tensor.data != nullptr, what + " has no data");
  Check(tensor.type == type, what + " has the wrong type");
  Check(tensor.cols == cols, what + " has " + std::to_string(tensor.cols) +
                                 " columns, expected " + std::to_string(cols));
  Check(tensor.rows == rows, what + " has " + std::to_string(tensor.rows) +
                                 " rows, expected " + std::to_string(rows));
  const std::size_t elements = static_cast<std::size_t>(cols) * rows;
  const std::size_t bytes = type == gufo::core::GgmlType::kQ8_0
                                ? elements / 32 * 34
                                : elements * 4;
  Check(tensor.bytes == bytes, what + " spans " + std::to_string(tensor.bytes) +
                                   " bytes, expected " + std::to_string(bytes));
}

int RealFile(const std::filesystem::path& path) {
  std::string error;
  const auto reader = gufo::core::GgufReader::OpenFile(path, &error);
  Check(reader != nullptr, "cannot open " + path.string() + ": " + error);
  const Config config = qwen3_embedding::ReadConfig(*reader);
  Check(config.architecture == "qwen3", "architecture is " + config.architecture);
  Check(config.block_count == 36U, "block_count");
  Check(config.embedding_length == 4096U, "embedding_length");
  Check(config.feed_forward_length == 12288U, "feed_forward_length");
  Check(config.head_count == 32U, "head_count");
  Check(config.head_count_kv == 8U, "head_count_kv");
  Check(config.key_length == 128U && config.value_length == 128U,
        "key/value length");
  Check(config.pooling_type == 3U, "pooling_type is not last (3)");
  Check(config.rope_freq_base.has_value() && *config.rope_freq_base == 1.0e6F,
        "rope freq_base");
  Check(config.rms_eps.has_value() && *config.rms_eps == 1.0e-6F, "rms eps");
  Check(!config.has_rope_scaling, "RoPE scaling keys present");
  Check(config.tokenizer_model == "gpt2" && config.tokenizer_pre == "qwen2",
        "tokenizer is " + config.tokenizer_model + "/" + config.tokenizer_pre);
  Check(config.add_eos == true, "add_eos_token is not true");
  Check(!config.add_bos.value_or(false), "add_bos_token is true");
  Check(config.eos_token_id == 151643U, "eos_token_id is not 151643");
  Check(config.vocab_size == 151665, "vocab is " + std::to_string(config.vocab_size));
  Check(config.merges > 0, "no merges");
  Check(qwen3_embedding::CheckConfig(config).empty(),
        "CheckConfig: " + qwen3_embedding::CheckConfig(config));
  Check(qwen3_embedding::CheckTensors(*reader).empty(),
        "CheckTensors: " + qwen3_embedding::CheckTensors(*reader));
  Check(reader->GetTensorCount() == 398, "tensor count");

  const auto weights = qwen3_embedding::Weights::Bind(*reader, &error);
  Check(weights.has_value(), "Weights::Bind failed: " + error);
  using gufo::core::GgmlType;
  CheckTensor(weights->token_embd, "token_embd", GgmlType::kQ8_0, 4096, 151665);
  Check(weights->token_embd.bytes == 660046080, "token_embd bytes");
  CheckTensor(weights->output_norm, "output_norm", GgmlType::kF32, 4096, 1);
  Check(weights->layers.size() == 36, "layer count");
  for (std::size_t index = 0; index < weights->layers.size(); ++index) {
    const auto& layer = weights->layers[index];
    const std::string prefix = "blk." + std::to_string(index) + ".";
    CheckTensor(layer.attn_norm, prefix + "attn_norm", GgmlType::kF32, 4096, 1);
    CheckTensor(layer.q, prefix + "attn_q", GgmlType::kQ8_0, 4096, 4096);
    CheckTensor(layer.k, prefix + "attn_k", GgmlType::kQ8_0, 4096, 1024);
    CheckTensor(layer.v, prefix + "attn_v", GgmlType::kQ8_0, 4096, 1024);
    CheckTensor(layer.q_norm, prefix + "attn_q_norm", GgmlType::kF32, 128, 1);
    CheckTensor(layer.k_norm, prefix + "attn_k_norm", GgmlType::kF32, 128, 1);
    CheckTensor(layer.attn_output, prefix + "attn_output", GgmlType::kQ8_0, 4096,
                4096);
    CheckTensor(layer.ffn_norm, prefix + "ffn_norm", GgmlType::kF32, 4096, 1);
    CheckTensor(layer.gate, prefix + "ffn_gate", GgmlType::kQ8_0, 4096, 12288);
    CheckTensor(layer.up, prefix + "ffn_up", GgmlType::kQ8_0, 4096, 12288);
    CheckTensor(layer.down, prefix + "ffn_down", GgmlType::kQ8_0, 12288, 4096);
  }
  std::cout << "config_test: real GGUF " << path << " matches: 398 tensors, "
            << "36 layers, vocab 151665, pooling last\n";
  return 0;
}

}  // namespace

int main() {
  qwen3_embedding::testing::TestName() = "config_test";
  EditedConfigs();
  std::cout << "config_test: edited configs refused with the right reason\n";
  const auto model = qwen3_embedding::testing::ModelPath();
  if (!model.has_value()) {
    std::cout << "config_test: QWEN3_EMBEDDING_MODEL unset; real GGUF checks "
                 "skipped\n";
    return qwen3_embedding::testing::kSkip;
  }
  return RealFile(*model);
}
