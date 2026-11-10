// Checks the provider probe on synthetic GGUFs (full-size but sparse, so
// they cost no disk): the Qwen3-Embedding-8B layout is accepted; a
// directory, another extension, a language-model head, a missing pooling
// key, other geometry and a wrong tensor type are refused, each with the
// reason. With QWEN3_EMBEDDING_MODEL set, the real file is accepted too.

#include <cstdint>
#include <filesystem>
#include <iostream>
#include <map>
#include <string>
#include <string_view>
#include <vector>

#include "src/probe.hpp"
#include "tests/support.hpp"

namespace {

using qwen3_embedding::testing::Check;
using qwen3_embedding::testing::GgufWriter;

constexpr std::uint32_t kF32 = 0;
constexpr std::uint32_t kF16 = 1;
constexpr std::uint32_t kQ8_0 = 8;

/// A writer holding the metadata and tensor table of Qwen3-Embedding-8B
/// Q8_0, with a placeholder vocabulary of the right size.
GgufWriter Qwen3Embedding8B() {
  GgufWriter writer;
  writer.Set("general.architecture", std::string("qwen3"));
  writer.Set("general.alignment", std::uint32_t{32});
  writer.Set("qwen3.block_count", std::uint32_t{36});
  writer.Set("qwen3.context_length", std::uint32_t{40960});
  writer.Set("qwen3.embedding_length", std::uint32_t{4096});
  writer.Set("qwen3.feed_forward_length", std::uint32_t{12288});
  writer.Set("qwen3.attention.head_count", std::uint32_t{32});
  writer.Set("qwen3.attention.head_count_kv", std::uint32_t{8});
  writer.Set("qwen3.attention.key_length", std::uint32_t{128});
  writer.Set("qwen3.attention.value_length", std::uint32_t{128});
  writer.Set("qwen3.rope.freq_base", 1.0e6F);
  writer.Set("qwen3.attention.layer_norm_rms_epsilon", 1.0e-6F);
  writer.Set("qwen3.pooling_type", std::uint32_t{3});
  writer.Set("tokenizer.ggml.model", std::string("gpt2"));
  writer.Set("tokenizer.ggml.pre", std::string("qwen2"));
  GgufWriter::StringArray tokens;
  tokens.values.reserve(151665);
  for (std::uint32_t id = 0; id < 151665; ++id) {
    tokens.values.push_back("t" + std::to_string(id));
  }
  writer.Set("tokenizer.ggml.tokens", std::move(tokens));
  writer.Set("tokenizer.ggml.token_type",
             GgufWriter::Int32Array{std::vector<std::int32_t>(151665, 1)});
  writer.Set("tokenizer.ggml.merges", GgufWriter::StringArray{{"t 1", "t1 2"}});
  writer.Set("tokenizer.ggml.eos_token_id", std::uint32_t{151643});
  writer.Set("tokenizer.ggml.padding_token_id", std::uint32_t{151643});
  writer.Set("tokenizer.ggml.add_eos_token", true);
  writer.Set("tokenizer.ggml.add_bos_token", false);

  writer.AddTensor({"token_embd.weight", kQ8_0, {4096, 151665}});
  for (int layer = 0; layer < 36; ++layer) {
    const std::string p = "blk." + std::to_string(layer) + ".";
    writer.AddTensor({p + "attn_norm.weight", kF32, {4096}});
    writer.AddTensor({p + "attn_q.weight", kQ8_0, {4096, 4096}});
    writer.AddTensor({p + "attn_k.weight", kQ8_0, {4096, 1024}});
    writer.AddTensor({p + "attn_v.weight", kQ8_0, {4096, 1024}});
    writer.AddTensor({p + "attn_q_norm.weight", kF32, {128}});
    writer.AddTensor({p + "attn_k_norm.weight", kF32, {128}});
    writer.AddTensor({p + "attn_output.weight", kQ8_0, {4096, 4096}});
    writer.AddTensor({p + "ffn_norm.weight", kF32, {4096}});
    writer.AddTensor({p + "ffn_gate.weight", kQ8_0, {4096, 12288}});
    writer.AddTensor({p + "ffn_up.weight", kQ8_0, {4096, 12288}});
    writer.AddTensor({p + "ffn_down.weight", kQ8_0, {12288, 4096}});
  }
  writer.AddTensor({"output_norm.weight", kF32, {4096}});
  return writer;
}

void ExpectAccepted(const std::filesystem::path& path) {
  const std::string problem = qwen3_embedding::ExplainModel(path.string());
  Check(problem.empty(), path.string() + " refused: " + problem);
  Check(qwen3_embedding::ProbeQwen3Embedding(path.string()),
        path.string() + " not probed");
}

void ExpectRefused(const std::filesystem::path& path, std::string_view mention) {
  const std::string problem = qwen3_embedding::ExplainModel(path.string());
  Check(!problem.empty(), path.string() + " accepted, expected a refusal "
                                          "mentioning " + std::string(mention));
  Check(problem.find(mention) != std::string::npos,
        path.string() + " refused as '" + problem + "', expected a mention of " +
            std::string(mention));
  Check(!qwen3_embedding::ProbeQwen3Embedding(path.string()),
        path.string() + " probed true");
  std::cout << "probe_test: refused " << path.filename() << ": " << problem
            << '\n';
}

void Synthetic(const std::filesystem::path& dir) {
  ExpectRefused(dir, "not a .gguf file");
  ExpectRefused(dir / "absent.gguf", "not a .gguf file");

  const auto good = dir / "good.gguf";
  Qwen3Embedding8B().Write(good);
  ExpectAccepted(good);

  // The same bytes under another extension.
  std::filesystem::copy_file(good, dir / "good.bin");
  ExpectRefused(dir / "good.bin", "not a .gguf file");

  {
    auto writer = Qwen3Embedding8B();
    writer.AddTensor({"output.weight", kQ8_0, {4096, 151665}});
    writer.Write(dir / "lm_head.gguf");
    ExpectRefused(dir / "lm_head.gguf", "output.weight is present");
  }
  {
    auto writer = Qwen3Embedding8B();
    writer.Erase("qwen3.pooling_type");
    writer.Write(dir / "no_pooling.gguf");
    ExpectRefused(dir / "no_pooling.gguf", "qwen3.pooling_type is missing");
  }
  {
    auto writer = Qwen3Embedding8B();
    writer.Set("qwen3.pooling_type", std::uint32_t{1});
    writer.Write(dir / "mean_pooling.gguf");
    ExpectRefused(dir / "mean_pooling.gguf", "qwen3.pooling_type is 1");
  }
  {
    auto writer = Qwen3Embedding8B();
    writer.Set("general.architecture", std::string("llama"));
    writer.Write(dir / "llama.gguf");
    ExpectRefused(dir / "llama.gguf", "general.architecture");
  }
  {
    auto writer = Qwen3Embedding8B();
    writer.Set("qwen3.block_count", std::uint32_t{28});
    writer.Write(dir / "small.gguf");
    ExpectRefused(dir / "small.gguf", "qwen3.block_count is 28");
  }
  {
    auto writer = Qwen3Embedding8B();
    Check(writer.SetTensorType("blk.0.attn_q.weight", kF16), "no attn_q");
    writer.Write(dir / "f16_matrix.gguf");
    ExpectRefused(dir / "f16_matrix.gguf", "blk.0.attn_q.weight (F16");
  }
  {
    auto writer = Qwen3Embedding8B();
    writer.AddTensor({"rope_freqs.weight", kF32, {64}});
    writer.Write(dir / "extra_tensor.gguf");
    ExpectRefused(dir / "extra_tensor.gguf", "399 tensors");
  }
}

}  // namespace

int main() {
  qwen3_embedding::testing::TestName() = "probe_test";
  {
    std::map<std::string, std::string> prompts{{"query", "x"}};
    std::string error;
    Check(qwen3_embedding::ResolveQwen3Embedding("/nonexistent", &prompts, &error),
          "resolve failed");
    Check(prompts.empty(), "resolve left prompts");
  }
  {
    qwen3_embedding::testing::TempDir dir("probe");
    Synthetic(dir.path());
  }
  std::cout << "probe_test: synthetic GGUFs probed as expected\n";

  const auto model = qwen3_embedding::testing::ModelPath();
  if (!model.has_value()) {
    std::cout << "probe_test: QWEN3_EMBEDDING_MODEL unset; real GGUF check "
                 "skipped\n";
    return qwen3_embedding::testing::kSkip;
  }
  ExpectAccepted(*model);
  qwen3_embedding::testing::TempDir links("probe_links");
  std::filesystem::create_symlink(*model, links.path() / "renamed.bin");
  ExpectRefused(links.path() / "renamed.bin", "not a .gguf file");
  std::filesystem::create_symlink(*model, links.path() / "linked.gguf");
  ExpectAccepted(links.path() / "linked.gguf");
  std::cout << "probe_test: real GGUF accepted: " << *model << '\n';
  return 0;
}
