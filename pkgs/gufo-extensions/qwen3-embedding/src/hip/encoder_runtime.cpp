// The Qwen3-Embedding-8B forward pass. Structure (DeviceBuffer, OnDevice,
// DeviceUsable, Create = upload + allocate + drop the mapping + warm up)
// adapted from Gufo's EmbeddingGemma 2 encoder runtime (v0.33.0,
// src/models/embedding_gemma2/hip/encoder_runtime.cpp, MIT, gufo
// contributors); the kernels are the LFM3 extension's (see ops.hip).
#include "encoder_runtime.hpp"

#include <hip/hip_runtime.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstring>
#include <exception>
#include <filesystem>
#include <gufo/ext/experimental/hip_utils.hpp>
#include <gufo/ext/experimental/managed_alloc.hpp>
#include <gufo/ext/gguf_reader.hpp>
#include <span>
#include <stdexcept>
#include <string>
#include <utility>

#include "../config.hpp"
#include "../weights.hpp"
#include "ops.hpp"

namespace qwen3_embedding::hip {
namespace {

constexpr const char* kDeviceLostMessage =
    "qwen3-embedding: GPU device lost; restart the server";

using Clock = std::chrono::steady_clock;

double Seconds(Clock::time_point since) {
  return std::chrono::duration<double>(Clock::now() - since).count();
}

/// Owning device allocation: hipMalloc, or managed memory when the device
/// heap is full (both are the same DRAM on gfx1151).
class DeviceBuffer {
public:
  DeviceBuffer() = default;
  DeviceBuffer(std::size_t bytes, bool* managed) : bytes_(bytes) {
    if (bytes == 0) {
      return;
    }
    hipError_t status = hipMalloc(&data_, bytes);
    if (status == hipErrorOutOfMemory) {
      (void)hipGetLastError();
      status = gufo::hip::AllocateManaged(&data_, bytes);
      if (status == hipSuccess && managed != nullptr) {
        *managed = true;
      }
    }
    if (status != hipSuccess) {
      data_ = nullptr;
      throw std::runtime_error("cannot allocate " + std::to_string(bytes) +
                               " device bytes: " + hipGetErrorString(status));
    }
  }
  ~DeviceBuffer() {
    if (data_ != nullptr) {
      gufo::hip::LogCleanupError(hipFree(data_));
    }
  }
  DeviceBuffer(const DeviceBuffer&) = delete;
  DeviceBuffer& operator=(const DeviceBuffer&) = delete;
  DeviceBuffer(DeviceBuffer&& other) noexcept
      : data_(std::exchange(other.data_, nullptr)),
        bytes_(std::exchange(other.bytes_, 0)) {}
  DeviceBuffer& operator=(DeviceBuffer&& other) noexcept {
    if (this != &other) {
      if (data_ != nullptr) {
        gufo::hip::LogCleanupError(hipFree(data_));
      }
      data_ = std::exchange(other.data_, nullptr);
      bytes_ = std::exchange(other.bytes_, 0);
    }
    return *this;
  }
  template<typename T = void>
  [[nodiscard]] T* get() const {
    return static_cast<T*>(data_);
  }
  [[nodiscard]] std::size_t bytes() const { return bytes_; }

private:
  void* data_{nullptr};
  std::size_t bytes_{0};
};

}  // namespace

std::string_view ToString(Activations activations) {
  return activations == Activations::kExact ? "exact" : "llamacpp-q8";
}

bool ParseActivations(std::string_view text, Activations* activations) {
  if (text == "exact") {
    *activations = Activations::kExact;
    return true;
  }
  if (text == "llamacpp-q8") {
    *activations = Activations::kLlamaCppQ8;
    return true;
  }
  return false;
}

struct EncoderRuntime::Impl {
  EncoderOptions options;
  LoadReport report;
  hipStream_t stream{nullptr};
  float eps{1e-6F};
  float rope_theta{1e6F};

  // Weights: one device buffer per tensor, bound as views.
  std::vector<DeviceBuffer> weight_buffers;
  Weights weights;

  // Scratch for options.max_batch_tokens rows.
  DeviceBuffer ids, positions, last_rows, styles;
  DeviceBuffer state, normed, q, k, v, ctx, attn_out, ffn_out;
  DeviceBuffer k16, v16, hidden, up_scratch;
  DeviceBuffer quantized, row_max, partial, tickets, attn_scratch;
  DeviceBuffer frequencies, pooled;
  // Target of the device probe that runs after a failed batch.
  DeviceBuffer probe;
  std::atomic<bool> lost{false};

  // Host staging for the per-batch uploads; asynchronous copies read them
  // until the stream is synchronized.
  std::vector<std::uint32_t> host_ids, host_positions, host_last;
  std::vector<std::uint8_t> host_styles;
  std::vector<float> host_pooled;

  ~Impl() {
    if (stream != nullptr) {
      gufo::hip::LogCleanupError(hipStreamSynchronize(stream));
      gufo::hip::LogCleanupError(hipStreamDestroy(stream));
    }
  }

  DeviceBuffer Alloc(std::size_t bytes) {
    return DeviceBuffer(bytes, &report.managed_fallback);
  }

  void Upload(const std::string& model_path);
  void Allocate();
  void Warmup();
  void Run(const std::vector<const std::vector<std::uint32_t>*>& sequences,
           std::vector<std::vector<float>>* embeddings);
  bool OnDevice(const std::function<void()>& work, std::string* error);
  [[nodiscard]] bool DeviceUsable();
};

void EncoderRuntime::Impl::Upload(const std::string& model_path) {
  const auto opened = Clock::now();
  std::string error;
  auto reader = gufo::core::GgufReader::OpenFile(
      std::filesystem::path(model_path), &error);
  if (!reader) {
    throw std::runtime_error("cannot read " + model_path + ": " + error);
  }
  const Config config = ReadConfig(*reader);
  if (auto problem = CheckConfig(config); !problem.empty()) {
    throw std::runtime_error(problem);
  }
  eps = *config.rms_eps;
  rope_theta = *config.rope_freq_base;
  auto bound = Weights::Bind(*reader, &error);
  if (!bound) {
    throw std::runtime_error(error);
  }
  report.open_seconds = Seconds(opened);

  const auto uploaded = Clock::now();
  weight_buffers.reserve(2 + kLayers * 11);
  const auto upload = [&](Tensor& tensor) {
    DeviceBuffer buffer = Alloc(tensor.bytes);
    HIP_CHECK(hipMemcpy(buffer.get(), tensor.data, tensor.bytes,
                        hipMemcpyHostToDevice));
    report.weight_bytes += tensor.bytes;
    tensor.data = buffer.get();
    weight_buffers.push_back(std::move(buffer));
  };
  weights = std::move(*bound);
  upload(weights.token_embd);
  upload(weights.output_norm);
  for (LayerWeights& layer : weights.layers) {
    for (Tensor* tensor :
         {&layer.attn_norm, &layer.q, &layer.k, &layer.v, &layer.q_norm,
          &layer.k_norm, &layer.attn_output, &layer.ffn_norm, &layer.gate,
          &layer.up, &layer.down}) {
      upload(*tensor);
    }
  }
  // The device now holds every weight; closing the reader unmaps the file.
  reader.reset();
  report.upload_seconds = Seconds(uploaded);
}

void EncoderRuntime::Impl::Allocate() {
  const std::size_t rows = options.max_batch_tokens;
  const std::size_t hidden_width = kHidden;
  const std::size_t q_width = std::size_t(kHeads) * kHeadDim;
  const std::size_t kv_width = std::size_t(kKvHeads) * kHeadDim;
  const std::size_t f32 = sizeof(float);
  const auto scratch = [&](std::size_t bytes) {
    report.scratch_bytes += bytes;
    return Alloc(bytes);
  };
  ids = scratch(rows * sizeof(std::uint32_t));
  positions = scratch(rows * sizeof(std::uint32_t));
  last_rows = scratch(rows * sizeof(std::uint32_t));
  styles = scratch(rows);
  state = scratch(rows * hidden_width * f32);
  normed = scratch(rows * hidden_width * f32);
  q = scratch(rows * q_width * f32);
  k = scratch(rows * kv_width * f32);
  v = scratch(rows * kv_width * f32);
  ctx = scratch(rows * q_width * f32);
  attn_out = scratch(rows * hidden_width * f32);
  ffn_out = scratch(rows * hidden_width * f32);
  k16 = scratch(rows * kv_width * sizeof(gpu::Half));
  v16 = scratch(rows * kv_width * sizeof(gpu::Half));
  hidden = scratch(rows * kFeedForward * f32);
  up_scratch = scratch(rows * kFeedForward * f32);
  // The widest input a projection may split is the FFN down input.
  quantized = scratch(gpu::DenseWorkspaceBytes(rows, kFeedForward));
  row_max = scratch(rows * sizeof(unsigned));
  partial = scratch(gpu::SplitPartialBytes());
  tickets = scratch(gpu::kMaxSplitUnits * sizeof(unsigned));
  report.attention_scratch_bytes = gpu::AttentionScratchBytes(
      int(kHeads), int(kHeadDim), int(rows), int(rows));
  attn_scratch = scratch(report.attention_scratch_bytes);
  frequencies = scratch(kHeadDim / 2 * f32);
  pooled = scratch(rows * hidden_width * f32);
  probe = scratch(sizeof(std::uint32_t));
  HIP_CHECK(hipMemsetAsync(tickets.get(), 0, tickets.bytes(), stream));
  gpu::RopeFrequencies(frequencies.get<float>(), int(kHeadDim), rope_theta,
                       stream);
  HIP_CHECK(hipStreamSynchronize(stream));
}

void EncoderRuntime::Impl::Warmup() {
  // One batch per projection path: one row (GEMV and decode attention),
  // a few rows (the FP32 small-batch GEMM) and a prompt (matrix cores).
  for (const std::size_t length : {std::size_t(1), std::size_t(7),
                                   std::size_t(64)}) {
    std::vector<std::uint32_t> tokens(length, 220);
    tokens.back() = 151643;
    std::vector<std::vector<float>> out;
    Run({&tokens}, &out);
  }
}

void EncoderRuntime::Impl::Run(
    const std::vector<const std::vector<std::uint32_t>*>& sequences,
    std::vector<std::vector<float>>* embeddings) {
  const bool q8 = options.activations == Activations::kLlamaCppQ8;
  const std::size_t count = sequences.size();
  host_ids.clear();
  host_positions.clear();
  host_last.clear();
  host_styles.clear();
  std::vector<std::size_t> starts;
  starts.reserve(count);
  for (const auto* sequence : sequences) {
    const std::size_t length = sequence->size();
    if (length == 0 || length > kMaxSequenceTokens) {
      throw std::invalid_argument("a sequence must have 1 to 8192 tokens");
    }
    starts.push_back(host_ids.size());
    for (std::size_t p = 0; p < length; ++p) {
      const std::uint32_t id = (*sequence)[p];
      if (id >= kVocab) {
        throw std::invalid_argument("token id " + std::to_string(id) +
                                    " is outside the vocabulary");
      }
      host_ids.push_back(id);
      host_positions.push_back(static_cast<std::uint32_t>(p));
      const std::size_t chunk = p / options.llama_ubatch * options.llama_ubatch;
      const std::size_t chunk_rows =
          std::min(options.llama_ubatch, length - chunk);
      host_styles.push_back(chunk_rows <= 8 ? gpu::kQ8Mmvq : gpu::kQ8Mmq);
    }
    host_last.push_back(static_cast<std::uint32_t>(host_ids.size() - 1));
  }
  const std::size_t n_rows = host_ids.size();
  if (n_rows > options.max_batch_tokens) {
    throw std::invalid_argument("batch of " + std::to_string(n_rows) +
                                " tokens exceeds the batch limit");
  }
  embeddings->clear();
  if (count == 0) {
    return;
  }
  const int n = static_cast<int>(n_rows);
  hipStream_t s = stream;
  HIP_CHECK(hipMemcpyAsync(ids.get(), host_ids.data(), n_rows * 4,
                           hipMemcpyHostToDevice, s));
  HIP_CHECK(hipMemcpyAsync(positions.get(), host_positions.data(), n_rows * 4,
                           hipMemcpyHostToDevice, s));
  HIP_CHECK(hipMemcpyAsync(last_rows.get(), host_last.data(), count * 4,
                           hipMemcpyHostToDevice, s));
  HIP_CHECK(hipMemcpyAsync(styles.get(), host_styles.data(), n_rows,
                           hipMemcpyHostToDevice, s));
  const std::uint8_t* style = q8 ? styles.get<std::uint8_t>() : nullptr;

  const int H = int(kHidden), heads = int(kHeads), kv_heads = int(kKvHeads),
            D = int(kHeadDim);
  const std::size_t q_stride = std::size_t(heads) * D,
                    kv_stride = std::size_t(kv_heads) * D;
  float* x = state.get<float>();
  float* z = normed.get<float>();
  float* qf = q.get<float>();
  float* kf = k.get<float>();
  float* vf = v.get<float>();
  float* cf = ctx.get<float>();
  float* af = attn_out.get<float>();
  float* ff = ffn_out.get<float>();
  auto* k16p = k16.get<gpu::Half>();
  auto* v16p = v16.get<gpu::Half>();
  const gpu::DenseWorkspace ws{quantized.get(), row_max.get<unsigned>(),
                               partial.get<float>(), tickets.get<unsigned>()};

  gpu::Embed(weights.token_embd, ids.get<std::uint32_t>(), x, n, s);
  const float* branch = nullptr;
  for (const LayerWeights& layer : weights.layers) {
    // Attention block.
    const gpu::Output qkv[] = {{&layer.q, qf}, {&layer.k, kf}, {&layer.v, vf}};
    const bool split = !q8 && gpu::SharesSplit(qkv, n, ws);
    if (!gpu::ResidualNorm(branch, nullptr, x, &layer.attn_norm, z, n, H, eps,
                           split, s, ws)) {
      throw std::runtime_error("unsupported hidden width");
    }
    gpu::QuantizeQ8Rows(z, n, H, style, s);
    gpu::Project(qkv, z, n, s, ws, split);
    gpu::PromptHeads(qf, kf, vf, static_cast<const float*>(layer.q_norm.data),
                     static_cast<const float*>(layer.k_norm.data),
                     frequencies.get<float>(), positions.get<std::uint32_t>(),
                     k16p, v16p, n, heads, kv_heads, D, eps, s);
    for (std::size_t j = 0; j < count; ++j) {
      const std::size_t t0 = starts[j];
      const int length = static_cast<int>(sequences[j]->size());
      gpu::Attention(qf + t0 * q_stride, k16p + t0 * kv_stride,
                     v16p + t0 * kv_stride, nullptr, k16p + t0 * kv_stride,
                     v16p + t0 * kv_stride, cf + t0 * q_stride, length, heads,
                     kv_heads, D, 0, length, 0, s,
                     attn_scratch.get<float>());
    }
    gpu::QuantizeQ8Rows(cf, n, int(q_stride), style, s);
    const gpu::Output output[] = {{&layer.attn_output, af}};
    gpu::Project(output, cf, n, s, ws);
    // FFN block.
    const gpu::Output gate_up[] = {{&layer.gate, hidden.get<float>()},
                                   {&layer.up, nullptr}};
    const bool split2 = !q8 && gpu::SharesSplit(gate_up, n, ws);
    gpu::ResidualNorm(af, nullptr, x, &layer.ffn_norm, z, n, H, eps, split2, s,
                      ws);
    gpu::QuantizeQ8Rows(z, n, H, style, s);
    gpu::ProjectFfn(layer.gate, layer.up, layer.down, z, hidden.get<float>(),
                    up_scratch.get<float>(), ff, n, s, ws, split2, style);
    branch = ff;
  }
  gpu::ResidualNorm(branch, nullptr, x, &weights.output_norm, z, n, H, eps,
                    false, s, ws);
  gpu::GatherRows(z, last_rows.get<std::uint32_t>(), pooled.get<float>(),
                  int(count), H, s);
  HIP_CHECK(hipGetLastError());
  host_pooled.resize(count * kHidden);
  HIP_CHECK(hipMemcpyAsync(host_pooled.data(), pooled.get(),
                           host_pooled.size() * sizeof(float),
                           hipMemcpyDeviceToHost, s));
  HIP_CHECK(hipStreamSynchronize(s));
  // L2 as llama.cpp's common_embd_normalize (mode 2): the sum of squares in
  // double, one float factor.
  embeddings->reserve(count);
  for (std::size_t j = 0; j < count; ++j) {
    const float* row = host_pooled.data() + j * kHidden;
    double sum = 0.0;
    for (std::size_t i = 0; i < kHidden; ++i) {
      sum += row[i] * row[i];
    }
    sum = std::sqrt(sum);
    const float norm = sum > 0.0 ? static_cast<float>(1.0 / sum) : 0.0F;
    std::vector<float> out(kHidden);
    for (std::size_t i = 0; i < kHidden; ++i) {
      out[i] = row[i] * norm;
    }
    embeddings->push_back(std::move(out));
  }
}

bool EncoderRuntime::Impl::OnDevice(const std::function<void()>& work,
                                    std::string* error) {
  if (lost.load(std::memory_order_acquire)) {
    if (error != nullptr) {
      *error = kDeviceLostMessage;
    }
    return false;
  }
  try {
    work();
    return true;
  } catch (const std::exception& failure) {
    // Kernels of the failed batch may still be queued and read the staging
    // the next batch overwrites; drain the stream first.
    gufo::hip::LogCleanupError(hipStreamSynchronize(stream));
    if (!DeviceUsable()) {
      lost.store(true, std::memory_order_release);
      if (error != nullptr) {
        *error = std::string(kDeviceLostMessage) + ": " + failure.what();
      }
      return false;
    }
    if (error != nullptr) {
      *error = std::string("qwen3-embedding: ") + failure.what();
    }
    return false;
  }
}

bool EncoderRuntime::Impl::DeviceUsable() {
  (void)hipGetLastError();
  return hipMemsetAsync(probe.get(), 0, probe.bytes(), stream) == hipSuccess &&
         hipStreamSynchronize(stream) == hipSuccess;
}

EncoderRuntime::EncoderRuntime(std::unique_ptr<Impl> impl)
    : impl_(std::move(impl)) {}

EncoderRuntime::~EncoderRuntime() = default;

std::unique_ptr<EncoderRuntime> EncoderRuntime::Create(
    const std::string& model_path, std::string* error,
    const EncoderOptions& options) {
  auto impl = std::make_unique<Impl>();
  impl->options = options;
  try {
    if (options.max_batch_tokens < kMaxSequenceTokens ||
        options.llama_ubatch == 0) {
      throw std::invalid_argument(
          "max_batch_tokens must hold one 8192-token sequence");
    }
    HIP_CHECK(hipStreamCreateWithFlags(&impl->stream, hipStreamNonBlocking));
    impl->Upload(model_path);
    impl->Allocate();
    const auto warm = Clock::now();
    impl->Warmup();
    impl->report.warmup_seconds = Seconds(warm);
    return std::unique_ptr<EncoderRuntime>(new EncoderRuntime(std::move(impl)));
  } catch (const std::exception& failure) {
    if (impl->stream != nullptr) {
      gufo::hip::LogCleanupError(hipStreamSynchronize(impl->stream));
    }
    if (error != nullptr) {
      *error = std::string("qwen3-embedding: ") + failure.what();
    }
    return nullptr;
  }
}

bool EncoderRuntime::RunBatch(
    const std::vector<const std::vector<std::uint32_t>*>& sequences,
    std::vector<std::vector<float>>* embeddings, std::string* error) {
  return impl_->OnDevice([&] { impl_->Run(sequences, embeddings); }, error);
}

bool EncoderRuntime::Embed(
    const std::vector<std::vector<std::uint32_t>>& sequences,
    std::vector<std::vector<float>>* embeddings, std::string* error,
    const std::function<bool()>& is_cancelled) {
  embeddings->clear();
  embeddings->reserve(sequences.size());
  std::size_t next = 0;
  while (next < sequences.size()) {
    if (is_cancelled && is_cancelled()) {
      if (error != nullptr) {
        *error = "cancelled";
      }
      return false;
    }
    std::vector<const std::vector<std::uint32_t>*> batch;
    std::size_t tokens = 0;
    while (next < sequences.size() &&
           (batch.empty() || tokens + sequences[next].size() <=
                                 impl_->options.max_batch_tokens)) {
      tokens += sequences[next].size();
      batch.push_back(&sequences[next++]);
    }
    std::vector<std::vector<float>> out;
    if (!RunBatch(batch, &out, error)) {
      return false;
    }
    for (auto& vector : out) {
      embeddings->push_back(std::move(vector));
    }
  }
  return true;
}

bool EncoderRuntime::device_lost() const noexcept {
  return impl_->lost.load(std::memory_order_acquire);
}

const EncoderOptions& EncoderRuntime::options() const noexcept {
  return impl_->options;
}

void EncoderRuntime::set_activations(Activations activations) noexcept {
  impl_->options.activations = activations;
}

const LoadReport& EncoderRuntime::load_report() const noexcept {
  return impl_->report;
}

}  // namespace qwen3_embedding::hip
