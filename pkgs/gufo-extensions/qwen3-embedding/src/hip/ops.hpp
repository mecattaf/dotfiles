// Adapted from the LFM3 Gufo extension (gufo-org/lfm3-gufo-extension 23efc07,
// hip/ops.hpp, MIT, gufo contributors); see ops.hip. Added for
// Qwen3-Embedding: a null attention gate, per-row RoPE positions for packed
// sequences, the pooled-row gather and llama.cpp's q8_1 activation rounding.
#ifndef QWEN3_EMBEDDING_HIP_OPS_HPP_
#define QWEN3_EMBEDDING_HIP_OPS_HPP_
#include <hip/hip_runtime.h>

#include <cstddef>
#include <cstdint>
#include <span>

#include "../weights.hpp"

namespace qwen3_embedding::gpu {
// Per-row activation rounding before a Q8_0 matmul (see QuantizeQ8Rows).
inline constexpr std::uint8_t kQ8None = 0, kQ8Mmq = 1, kQ8Mmvq = 2;
void Embed(const Tensor& weight, const std::uint32_t* tokens, float* out, int n,
           hipStream_t stream);
// Prompt projections of n rows need SplitActivationBytes(n, K) here.
// row_max (one word per prompt row) lets the FFN down projection split its
// input while staging.
// With partial (SplitPartialBytes) and zeroed tickets (kMaxSplitUnits
// words), projections whose tiles leave the last wave of resident blocks
// partly idle split those tiles across K.
struct DenseWorkspace {
  void* quantized{};
  unsigned* row_max{};
  float* partial{};
  unsigned* tickets{};
};
std::size_t DenseWorkspaceBytes(std::size_t rows, std::size_t K);
inline constexpr int kMaxSplitParts = 8, kMaxSplitUnits = 192;
std::size_t SplitPartialBytes();
struct Output {
  const Tensor* weight;
  float* out;
};
// True when these projections of n rows read one split prompt input.
bool SharesSplit(std::span<const Output> outputs, int n,
                 DenseWorkspace workspace);
// Projects one input through up to four weights with the same column count.
// Q8_0 prompts split the input once and share one launch. split_ready means
// the workspace already holds this input's split (see ResidualNorm).
void Project(std::span<const Output> outputs, const float* x, int n,
             hipStream_t stream, DenseWorkspace workspace,
             bool split_ready = false);
// silu(gate x) * (up x) into out; up_scratch holds up x when the projections
// cannot share the fused prompt launch.
void ProjectSwiGLU(const Tensor& gate, const Tensor& up, const float* x,
                   float* out, float* up_scratch, int n, hipStream_t stream,
                   DenseWorkspace workspace, bool split_ready = false);
// down(silu(gate x) * (up x)) into out, with the activation in hidden.
// q8_style (one byte per row, or null) rounds the activation before the
// down projection as QuantizeQ8Rows does.
void ProjectFfn(const Tensor& gate, const Tensor& up, const Tensor& down,
                const float* x, float* hidden, float* up_scratch, float* out,
                int n, hipStream_t stream, DenseWorkspace workspace,
                bool split_ready = false,
                const std::uint8_t* q8_style = nullptr);
// x += post_norm(branch) (branch may be null, post_norm may be null), then
// z = norm(x) unless norm is null. With split, z goes to the workspace as a
// split prompt input instead. Returns false when the width is unsupported.
bool ResidualNorm(const float* branch, const Tensor* post_norm, float* x,
                  const Tensor* norm, float* z, int n, int hidden, float eps,
                  bool split, hipStream_t stream, DenseWorkspace workspace);
void Dense(const Tensor& weight, const float* x, float* out, int n,
           hipStream_t stream, DenseWorkspace workspace = {});
// Writes the dim / 2 RoPE frequencies of theta for Rope.
void RopeFrequencies(float* out, int dim, float theta, hipStream_t stream);
void Rope(float* x, const float* frequencies, const float* factors, int n,
          int heads, int dim, int position, hipStream_t stream);
// IEEE binary16 bits. Attention K/V caches and chunk rows are F16.
using Half = std::uint16_t;
// Causal attention of n query rows at position. gate may be null (no output
// gate); otherwise out is divided by 1 + exp(-gate) per row and head. Key rows at or after
// position come from k and v (n F16 rows), earlier rows from the ring
// (slot t % capacity), so a sliding ring is written after this launch. Prompt
// rows run on the matrix cores with F16 Q and probabilities; decode (n == 1)
// keeps Q and probabilities in FP32. Both accumulate in FP32. Long histories
// split their keys across blocks through scratch of
// AttentionScratchBytes(heads, dim, context, rows) bytes, where rows bounds
// the queries of one call.
void Attention(const float* q, const Half* k, const Half* v, const float* gate,
               const Half* cache_k, const Half* cache_v, float* out, int n,
               int heads, int kv_heads, int dim, int position, int capacity,
               int window, hipStream_t stream, float* scratch);
std::size_t AttentionScratchBytes(int heads, int dim, int context, int rows);
// Rounds count values of k and v to F16.
void PackKV(const float* k, const float* v, Half* k16, Half* v16,
            std::size_t count, hipStream_t stream);
// Per-head Q/K RMSNorm and RoPE of n prompt rows at position in one launch,
// packing the K and V rows into k16 and v16 (n F16 rows each).
void PromptHeads(float* q, float* k, const float* v, const float* q_norm,
                 const float* k_norm, const float* frequencies,
                 const float* factors, Half* k16, Half* v16, int n, int heads,
                 int kv_heads, int dim, int position, float eps,
                 hipStream_t stream);
// The same for rows of several packed sequences: row r takes RoPE position
// positions[r] (device memory) and its K/V go to row r of k16 and v16.
void PromptHeads(float* q, float* k, const float* v, const float* q_norm,
                 const float* k_norm, const float* frequencies,
                 const std::uint32_t* positions, Half* k16, Half* v16, int n,
                 int heads, int kv_heads, int dim, float eps,
                 hipStream_t stream);
// out[i][:] = x[rows[i]][:] for count rows of width floats (rows on device).
void GatherRows(const float* x, const std::uint32_t* rows, float* out,
                int count, int width, hipStream_t stream);
// Rounds n rows of K floats in place to llama.cpp's q8_1 blocks of 32, per
// row style (kQ8Mmq, kQ8Mmvq or kQ8None, device bytes); null style does
// nothing. K must be a multiple of 32.
void QuantizeQ8Rows(float* x, int n, int K, const std::uint8_t* style,
                    hipStream_t stream);

void LaunchBatchedRMSNorm(const float* x, const float* weight, float* out,
                          void* out_bf16, std::size_t batch_size,
                          std::size_t dim, float eps, hipStream_t stream);
void LaunchBatchedPerHeadRMSNorm(const float* x, const float* weight,
                                 float* out, std::size_t batch_size,
                                 std::uint32_t num_heads,
                                 std::uint32_t head_dim, float eps,
                                 hipStream_t stream);
void LaunchBatchedResidualAdd(const float* a, const float* b, float* out,
                              std::size_t batch_size, std::size_t dim,
                              hipStream_t stream);
void LaunchBatchedSwiGLUActivation(const float* gate, const float* up,
                                   float* out, void* out_bf16,
                                   std::size_t num_elements,
                                   hipStream_t stream);
void LaunchGEMV(const void* A, core::GgmlType a_type, const float* x, float* y,
                std::size_t M, std::size_t K, hipStream_t stream);
void LaunchBatchedQuantGEMMFp32(core::GgmlType type, const void* w,
                                const float* fp32_x, float* y,
                                std::size_t batch, std::size_t m, std::size_t k,
                                hipStream_t stream);
}  // namespace qwen3_embedding::gpu
#endif
