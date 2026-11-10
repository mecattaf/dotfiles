#include "weights.hpp"

#include <string_view>

#include "config.hpp"

namespace qwen3_embedding {
namespace {

struct Expected {
  std::string name;
  core::GgmlType type;
  std::uint64_t cols;
  std::uint64_t rows;  // 0 for a vector
};

std::vector<Expected> ExpectedTensors() {
  using core::GgmlType;
  std::vector<Expected> expected = {
      {"token_embd.weight", GgmlType::kQ8_0, kHidden, kVocab},
      {"output_norm.weight", GgmlType::kF32, kHidden, 0},
  };
  const std::uint64_t q_rows = static_cast<std::uint64_t>(kHeads) * kHeadDim;
  const std::uint64_t kv_rows = static_cast<std::uint64_t>(kKvHeads) * kHeadDim;
  for (std::uint32_t layer = 0; layer < kLayers; ++layer) {
    const std::string prefix = "blk." + std::to_string(layer) + ".";
    expected.push_back({prefix + "attn_norm.weight", GgmlType::kF32, kHidden, 0});
    expected.push_back({prefix + "attn_q.weight", GgmlType::kQ8_0, kHidden, q_rows});
    expected.push_back({prefix + "attn_k.weight", GgmlType::kQ8_0, kHidden, kv_rows});
    expected.push_back({prefix + "attn_v.weight", GgmlType::kQ8_0, kHidden, kv_rows});
    expected.push_back({prefix + "attn_q_norm.weight", GgmlType::kF32, kHeadDim, 0});
    expected.push_back({prefix + "attn_k_norm.weight", GgmlType::kF32, kHeadDim, 0});
    expected.push_back({prefix + "attn_output.weight", GgmlType::kQ8_0, q_rows, kHidden});
    expected.push_back({prefix + "ffn_norm.weight", GgmlType::kF32, kHidden, 0});
    expected.push_back({prefix + "ffn_gate.weight", GgmlType::kQ8_0, kHidden, kFeedForward});
    expected.push_back({prefix + "ffn_up.weight", GgmlType::kQ8_0, kHidden, kFeedForward});
    expected.push_back({prefix + "ffn_down.weight", GgmlType::kQ8_0, kFeedForward, kHidden});
  }
  return expected;
}

std::string Describe(const core::GgufTensorInfo& info) {
  std::string shape;
  for (const auto dimension : info.dimensions) {
    shape += (shape.empty() ? "" : "x") + std::to_string(dimension);
  }
  return std::string(info.name) + " (" + std::string(core::ToString(info.type)) +
         " " + shape + ")";
}

/// Empty when `info` has the expected type and shape.
std::string CheckOne(const core::GgufTensorInfo* info, const Expected& want) {
  if (info == nullptr) {
    return "tensor " + want.name + " is missing";
  }
  const bool vector = want.rows == 0;
  const bool shape_ok =
      vector ? (info->dimensions.size() == 1 && info->dimensions[0] == want.cols)
             : (info->dimensions.size() == 2 &&
                info->dimensions[0] == want.cols &&
                info->dimensions[1] == want.rows);
  if (info->type != want.type || !shape_ok) {
    return "tensor " + Describe(*info) + " is not " +
           std::string(core::ToString(want.type)) + " " +
           std::to_string(want.cols) +
           (vector ? "" : "x" + std::to_string(want.rows));
  }
  if (!info->sized || info->data == nullptr) {
    return "tensor " + want.name + " has no sized data";
  }
  return {};
}

Tensor View(const core::GgufTensorInfo& info) {
  Tensor tensor;
  tensor.data = info.data;
  tensor.type = info.type;
  tensor.cols = static_cast<std::uint32_t>(info.dimensions[0]);
  tensor.rows = info.dimensions.size() > 1
                    ? static_cast<std::uint32_t>(info.dimensions[1])
                    : 1U;
  tensor.bytes = info.size_bytes;
  return tensor;
}

}  // namespace

std::string CheckTensors(const core::GgufReader& reader) {
  if (reader.HasTensor("output.weight")) {
    return "tensor output.weight is present (a language-model head, not an "
           "embedding checkpoint)";
  }
  const auto expected = ExpectedTensors();
  for (const Expected& want : expected) {
    if (auto problem = CheckOne(reader.FindTensor(want.name), want);
        !problem.empty()) {
      return problem;
    }
  }
  if (reader.GetTensorCount() != expected.size()) {
    return "the file has " + std::to_string(reader.GetTensorCount()) +
           " tensors, expected " + std::to_string(expected.size());
  }
  return {};
}

std::optional<Weights> Weights::Bind(const core::GgufReader& reader,
                                     std::string* error) {
  if (auto problem = CheckTensors(reader); !problem.empty()) {
    if (error != nullptr) {
      *error = std::move(problem);
    }
    return std::nullopt;
  }
  const auto get = [&](const std::string& name) {
    return View(*reader.FindTensor(name));
  };
  Weights weights;
  weights.token_embd = get("token_embd.weight");
  weights.output_norm = get("output_norm.weight");
  weights.layers.resize(kLayers);
  for (std::uint32_t index = 0; index < kLayers; ++index) {
    const std::string prefix = "blk." + std::to_string(index) + ".";
    LayerWeights& layer = weights.layers[index];
    layer.attn_norm = get(prefix + "attn_norm.weight");
    layer.q = get(prefix + "attn_q.weight");
    layer.k = get(prefix + "attn_k.weight");
    layer.v = get(prefix + "attn_v.weight");
    layer.q_norm = get(prefix + "attn_q_norm.weight");
    layer.k_norm = get(prefix + "attn_k_norm.weight");
    layer.attn_output = get(prefix + "attn_output.weight");
    layer.ffn_norm = get(prefix + "ffn_norm.weight");
    layer.gate = get(prefix + "ffn_gate.weight");
    layer.up = get(prefix + "ffn_up.weight");
    layer.down = get(prefix + "ffn_down.weight");
  }
  return weights;
}

}  // namespace qwen3_embedding
