// The provider entry: metadata always, and with HIP the embeddings runner.
// The runner tokenizes the way llama.cpp does for this model, packs
// concurrent callers into shared device batches (BatchScheduler) and runs
// the forward pass (hip::EncoderRuntime).
#include <atomic>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <functional>
#include <gufo/ext/embeddings.hpp>
#include <gufo/ext/gguf_reader.hpp>
#include <gufo/ext/generated/qwen3_embedding_constants.hpp>
#include <gufo/ext/registry.hpp>
#include <memory>
#include <optional>
#include <string>
#include <utility>
#include <vector>

#include "batch_scheduler.hpp"
#include "config.hpp"
#include "hip/encoder_runtime.hpp"
#include "inputs.hpp"
#include "probe.hpp"
#include "tokenizer/tokenizer.hpp"

namespace qwen3_embedding {

#if defined(ENGINE_ENABLE_HIP)
namespace {

namespace ext = gufo::ext;

class Qwen3EmbeddingRunner : public ext::EmbeddingRunner {
public:
  Qwen3EmbeddingRunner(Tokenizer tokenizer,
                       std::unique_ptr<hip::EncoderRuntime> encoder)
      : tokenizer_(std::move(tokenizer)),
        encoder_(std::move(encoder)),
        scheduler_(encoder_->options().max_batch_tokens,
                   [this](const std::vector<const EncoderSequence*>& sequences,
                          std::vector<std::vector<float>>* embeddings,
                          std::string* error) {
                     std::vector<const std::vector<std::uint32_t>*> tokens;
                     tokens.reserve(sequences.size());
                     for (const EncoderSequence* sequence : sequences) {
                       tokens.push_back(&sequence->tokens);
                     }
                     return encoder_->RunBatch(tokens, embeddings, error);
                   }) {}

  ext::EmbeddingStatus EmbedInputs(
      const std::vector<ext::EmbeddingInput>& inputs,
      const std::function<bool()>& is_cancelled, ext::EmbeddingBatch* batch,
      std::string* error = nullptr,
      const ext::EmbeddingRequestOptions& request = {}) override {
    if (device_lost()) {
      if (error != nullptr) {
        *error = "qwen3-embedding: GPU device lost";
      }
      return ext::EmbeddingStatus::kDeviceLost;
    }
    PreparedInputs prepared;
    std::size_t failed_index = 0;
    switch (PrepareInputs(tokenizer_, inputs, request.truncate, &prepared,
                          &failed_index, error)) {
      case PrepareStatus::kOk:
        break;
      case PrepareStatus::kInputTooLong:
        batch->failed_index = failed_index;
        return ext::EmbeddingStatus::kInputTooLong;
      case PrepareStatus::kInvalidInput:
        return ext::EmbeddingStatus::kInvalidInput;
    }
    if (is_cancelled && is_cancelled()) {
      return ext::EmbeddingStatus::kCancelled;
    }
    std::vector<EncoderSequence> sequences;
    sequences.reserve(prepared.sequences.size());
    for (auto& tokens : prepared.sequences) {
      sequences.push_back({std::move(tokens), is_cancelled});
    }
    std::string run_error;
    switch (scheduler_.Run(sequences, is_cancelled, &batch->embeddings,
                           &run_error)) {
      case BatchScheduler::Outcome::kOk:
        batch->token_counts = std::move(prepared.token_counts);
        return ext::EmbeddingStatus::kOk;
      case BatchScheduler::Outcome::kCancelled:
        return ext::EmbeddingStatus::kCancelled;
      case BatchScheduler::Outcome::kFailed:
        break;
    }
    if (error != nullptr) {
      *error = std::move(run_error);
    }
    if (encoder_->device_lost()) {
      device_lost_.store(true);
      return ext::EmbeddingStatus::kDeviceLost;
    }
    if (is_cancelled && is_cancelled()) {
      return ext::EmbeddingStatus::kCancelled;
    }
    return ext::EmbeddingStatus::kFailed;
  }

  bool device_lost() const noexcept override {
    return device_lost_.load() || encoder_->device_lost();
  }

private:
  Tokenizer tokenizer_;
  std::unique_ptr<hip::EncoderRuntime> encoder_;
  BatchScheduler scheduler_;
  std::atomic<bool> device_lost_{false};
};

}  // namespace

std::unique_ptr<gufo::ext::EmbeddingRunner> CreateQwen3EmbeddingRunner(
    const std::string& model_root, std::string* error) {
  const std::string problem = ExplainModel(model_root);
  if (!problem.empty()) {
    if (error != nullptr) {
      *error = "qwen3-embedding cannot serve " + model_root + ": " + problem;
    }
    return nullptr;
  }
  // QWEN3_EMBEDDING_ACTIVATIONS=exact|llamacpp-q8 picks the matmul input
  // rounding (default exact; llamacpp-q8 is a diagnostic, see
  // docs/QUALITY.md). `gufo serve embedding` takes no provider options.
  hip::EncoderOptions options;
  if (const char* value = std::getenv("QWEN3_EMBEDDING_ACTIVATIONS");
      value != nullptr && *value != '\0') {
    if (!hip::ParseActivations(value, &options.activations)) {
      if (error != nullptr) {
        *error = std::string("QWEN3_EMBEDDING_ACTIVATIONS must be exact or "
                             "llamacpp-q8, not ") +
                 value;
      }
      return nullptr;
    }
  }
  std::string load_error;
  std::optional<Tokenizer> tokenizer;
  {
    const auto reader = gufo::core::GgufReader::OpenFile(
        std::filesystem::path(model_root), &load_error);
    if (!reader) {
      if (error != nullptr) {
        *error = "qwen3-embedding: cannot read " + model_root + ": " + load_error;
      }
      return nullptr;
    }
    tokenizer = Tokenizer::Load(*reader, &load_error);
  }
  if (!tokenizer.has_value()) {
    if (error != nullptr) {
      *error = "qwen3-embedding tokenizer failed to load: " + load_error;
    }
    return nullptr;
  }
  auto encoder = hip::EncoderRuntime::Create(model_root, &load_error, options);
  if (!encoder) {
    if (error != nullptr) {
      *error = "qwen3-embedding encoder failed to load: " + load_error;
    }
    return nullptr;
  }
  const hip::LoadReport& report = encoder->load_report();
  std::fprintf(stderr,
               "qwen3-embedding: loaded %.2f GB of Q8_0 weights in %.2f s "
               "(open %.2f s), %.2f GB scratch for %zu tokens, warm-up %.2f "
               "s, activations %s%s\n",
               double(report.weight_bytes) / 1e9, report.upload_seconds,
               report.open_seconds, double(report.scratch_bytes) / 1e9,
               encoder->options().max_batch_tokens, report.warmup_seconds,
               std::string(hip::ToString(encoder->options().activations)).c_str(),
               report.managed_fallback ? ", managed-memory fallback used" : "");
  return std::make_unique<Qwen3EmbeddingRunner>(std::move(*tokenizer),
                                                std::move(encoder));
}
#endif

}  // namespace qwen3_embedding

void qwen3_embedding_provider_register(gufo::ext::Registry& registry) {
  registry.AddProvider(gufo::ext::generated::extension_qwen3_embedding::
                           kProvider_qwen3_embedding);
#if defined(ENGINE_ENABLE_HIP)
  registry.AddEmbeddingProvider({
      .id = "qwen3-embedding",
      .probe = &qwen3_embedding::ProbeQwen3Embedding,
      .resolve = &qwen3_embedding::ResolveQwen3Embedding,
      .create = &qwen3_embedding::CreateQwen3EmbeddingRunner,
  });
#endif
}
