#ifndef QWEN3_EMBEDDING_HIP_ENCODER_RUNTIME_HPP_
#define QWEN3_EMBEDDING_HIP_ENCODER_RUNTIME_HPP_

#include <cstddef>
#include <cstdint>
#include <functional>
#include <memory>
#include <string>
#include <string_view>
#include <vector>

namespace qwen3_embedding::hip {

/// How activations enter the Q8_0 matmuls.
enum class Activations {
  /// FP32 activations, split into two FP16 planes on the matrix cores (about
  /// 22 significant bits): the most exact arithmetic.
  kExact,
  /// Rounded first to the 8-bit q8_1 blocks llama.cpp's HIP backend
  /// multiplies (MMQ for ubatch chunks of more than eight rows, MMVQ for up
  /// to eight). Closer to llama.cpp on average, but the rounding amplifies
  /// tiny differences, so packed and single inputs drift apart as they do
  /// in llama.cpp itself; diagnostic only.
  kLlamaCppQ8,
};

/// "exact" or "llamacpp-q8".
[[nodiscard]] std::string_view ToString(Activations activations);
/// Parses ToString's names; false for anything else.
bool ParseActivations(std::string_view text, Activations* activations);

struct EncoderOptions {
  /// Tokens per device batch (one sequence is at most 8192 tokens).
  std::size_t max_batch_tokens{8192};
  /// kExact passes every parity gate (tests/golden_hip_test.cpp); kLlamaCppQ8
  /// is a diagnostic that inherits llama.cpp's batching noise.
  Activations activations{Activations::kExact};
  /// llama-server's ubatch: a sequence's tokens are processed in chunks of
  /// this many, and a chunk of at most eight takes MMVQ's rounding.
  std::size_t llama_ubatch{512};
};

/// What Create did, for the load log and the reports.
struct LoadReport {
  double open_seconds{0};
  double upload_seconds{0};
  double warmup_seconds{0};
  std::size_t weight_bytes{0};
  std::size_t scratch_bytes{0};
  std::size_t attention_scratch_bytes{0};
  /// True when some allocation fell back to managed memory.
  bool managed_fallback{false};
};

/// The Qwen3-Embedding-8B forward pass on one HIP device: Q8_0 weights
/// resident as stored, causal attention per sequence, last-token pooling,
/// L2-normalized 4096-wide FP32 embeddings.
class EncoderRuntime {
public:
  /// Loads the Q8_0 GGUF at `model_path` onto the device, allocates scratch
  /// for `options.max_batch_tokens` and warms every kernel up. Fails (null,
  /// with `error`) when the file is not this model, the weights do not fit
  /// or the device is unusable.
  static std::unique_ptr<EncoderRuntime> Create(
      const std::string& model_path, std::string* error,
      const EncoderOptions& options = {});

  EncoderRuntime(const EncoderRuntime&) = delete;
  EncoderRuntime& operator=(const EncoderRuntime&) = delete;
  ~EncoderRuntime();

  /// One device batch: the sequences (EOS last, each non-empty and at most
  /// 8192 ids) packed in order, at most max_batch_tokens in all. One
  /// embedding per sequence, in order. Not thread-safe: the batch scheduler
  /// serializes calls. False with `error` on failure.
  bool RunBatch(const std::vector<const std::vector<std::uint32_t>*>& sequences,
                std::vector<std::vector<float>>* embeddings,
                std::string* error);

  /// For tools and tests: greedy batches of whole sequences, one thread.
  bool Embed(const std::vector<std::vector<std::uint32_t>>& sequences,
             std::vector<std::vector<float>>* embeddings, std::string* error,
             const std::function<bool()>& is_cancelled = {});

  [[nodiscard]] bool device_lost() const noexcept;
  [[nodiscard]] const EncoderOptions& options() const noexcept;
  /// Switches the activation rounding between batches. Tools and tests
  /// only: not safe while another thread runs a batch.
  void set_activations(Activations activations) noexcept;
  [[nodiscard]] const LoadReport& load_report() const noexcept;

private:
  struct Impl;
  explicit EncoderRuntime(std::unique_ptr<Impl> impl);
  std::unique_ptr<Impl> impl_;
};

}  // namespace qwen3_embedding::hip

#endif  // QWEN3_EMBEDDING_HIP_ENCODER_RUNTIME_HPP_
