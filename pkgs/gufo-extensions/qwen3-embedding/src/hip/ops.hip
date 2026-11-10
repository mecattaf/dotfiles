// Adapted from the LFM3 Gufo extension (gufo-org/lfm3-gufo-extension 23efc07,
// hip/ops.hip, MIT, gufo contributors): namespace renamed; the short
// convolution, bidirectional attention, row selection, KV ring store, decode
// heads and BF16 small-batch GEMM entry points removed, since Qwen3-Embedding
// runs only causal Q8_0 prompts.
#include <hip/hip_bfloat16.h>
#include <hip/hip_fp16.h>

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <gufo/ext/experimental/ggml_dequant.hpp>
#include <stdexcept>
#include <type_traits>
#include <utility>

#include "ops.hpp"
#include "q8_prefill.hpp"

namespace qwen3_embedding::gpu {
namespace {

constexpr std::size_t kQ8_0BlockSize = 32;

struct Q8_0Block {
  __half d;
  std::int8_t qs[kQ8_0BlockSize];
};
static_assert(sizeof(Q8_0Block) == 34);

template<std::size_t CachedDim = 0>
__global__ void BatchedRMSNormKernel(const float* __restrict__ x,
                                     const float* __restrict__ weight,
                                     float* __restrict__ out,
                                     hip_bfloat16* __restrict__ out_bf16,
                                     std::size_t batch_size, std::size_t dim,
                                     float eps) {
  const std::size_t b = blockIdx.x;
  if (b >= batch_size)
    return;

  const std::size_t tid = threadIdx.x;
  const std::size_t block_size = blockDim.x;
  const float* in_row = x + (b * dim);
  float* out_row = (out != nullptr) ? out + (b * dim) : nullptr;
  hip_bfloat16* out_bf16_row =
      (out_bf16 != nullptr) ? out_bf16 + (b * dim) : nullptr;

  static_assert(CachedDim % 256 == 0);
  constexpr std::size_t cached_items = CachedDim == 0 ? 1 : CachedDim / 256;
  float values[cached_items];
  float weights[cached_items];
  float sum_sq = 0.0F;
  if constexpr (CachedDim != 0) {
#pragma unroll
    for (std::size_t item = 0; item < cached_items; ++item) {
      const std::size_t i = tid + item * 256;
      const float val = in_row[i];
      values[item] = val;
      weights[item] = weight != nullptr ? weight[i] : 1.0F;
      sum_sq = __fmaf_rn(val, val, sum_sq);
    }
  } else {
    for (std::size_t i = tid; i < dim; i += block_size) {
      const float val = in_row[i];
      sum_sq += val * val;
    }
  }

  __shared__ float s_sum[256];
  s_sum[tid] = sum_sq;
  __syncthreads();

  for (std::size_t stride = block_size / 2;
       stride > (CachedDim != 0 ? 16U : 0U); stride /= 2) {
    if (tid < stride)
      s_sum[tid] += s_sum[tid + stride];
    __syncthreads();
  }
  if constexpr (CachedDim != 0) {
    if (tid < 32) {
      float sum = s_sum[tid];
#pragma unroll
      for (unsigned offset = 16; offset > 0; offset /= 2)
        sum += __shfl_down(sum, offset);
      if (tid == 0)
        s_sum[0] = sum;
    }
    __syncthreads();
  }

  const float mean_sq = s_sum[0] / static_cast<float>(dim);
  const float inv_rms = rsqrtf(mean_sq + eps);

  if constexpr (CachedDim != 0) {
#pragma unroll
    for (std::size_t item = 0; item < cached_items; ++item) {
      const std::size_t i = tid + item * 256;
      const float normed = (values[item] * inv_rms) * weights[item];
      if (out_row != nullptr)
        out_row[i] = normed;
      if (out_bf16_row != nullptr)
        out_bf16_row[i] = hip_bfloat16(normed);
    }
  } else {
    for (std::size_t i = tid; i < dim; i += block_size) {
      const float w = (weight != nullptr) ? weight[i] : 1.0F;
      const float normed = (in_row[i] * inv_rms) * w;
      if (out_row != nullptr)
        out_row[i] = normed;
      if (out_bf16_row != nullptr)
        out_bf16_row[i] = hip_bfloat16(normed);
    }
  }
}

__global__ void BatchedPerHeadRMSNormKernel(const float* __restrict__ x,
                                            const float* __restrict__ weight,
                                            float* __restrict__ out,
                                            std::size_t batch_size,
                                            std::uint32_t num_heads,
                                            std::uint32_t head_dim, float eps) {
  const std::size_t b = blockIdx.y;
  const std::uint32_t h = blockIdx.x;
  if (b >= batch_size || h >= num_heads)
    return;

  const std::size_t tid = threadIdx.x;
  const std::size_t head_total = static_cast<std::size_t>(num_heads) * head_dim;
  const float* x_head =
      x + (b * head_total) + (static_cast<std::size_t>(h) * head_dim);
  float* out_head =
      out + (b * head_total) + (static_cast<std::size_t>(h) * head_dim);

  float sum_sq = 0.0F;
  for (std::size_t i = tid; i < head_dim; i += blockDim.x) {
    const float val = x_head[i];
    sum_sq += val * val;
  }

  __shared__ float s_sum[256];
  s_sum[tid] = sum_sq;
  __syncthreads();

  for (std::size_t stride = blockDim.x / 2; stride > 0; stride /= 2) {
    if (tid < stride)
      s_sum[tid] += s_sum[tid + stride];
    __syncthreads();
  }

  const float mean_sq = s_sum[0] / static_cast<float>(head_dim);
  const float inv_rms = rsqrtf(mean_sq + eps);

  for (std::size_t i = tid; i < head_dim; i += blockDim.x) {
    const float w = (weight != nullptr) ? weight[i] : 1.0F;
    out_head[i] = (x_head[i] * inv_rms) * w;
  }
}

__global__ void BatchedResidualAddKernel(const float* __restrict__ a,
                                         const float* __restrict__ b,
                                         float* __restrict__ out,
                                         std::size_t total_elements) {
  const std::size_t idx = (blockIdx.x * blockDim.x) + threadIdx.x;
  if (idx < total_elements)
    out[idx] = a[idx] + b[idx];
}

__global__ void BatchedSwiGLUActivationKernel(
    const float* __restrict__ gate, const float* __restrict__ up,
    float* __restrict__ out, hip_bfloat16* __restrict__ out_bf16,
    std::size_t num_elements) {
  const std::size_t idx = (blockIdx.x * blockDim.x) + threadIdx.x;
  if (idx < num_elements) {
    const std::size_t source = idx + blockIdx.y * 2 * num_elements;
    const std::size_t destination = idx + blockIdx.y * num_elements;
    const float g = gate[source];
    const float u = up[source];
    const float sig_g = 1.0F / (1.0F + expf(-g));
    const float val = (g * sig_g) * u;
    if (out != nullptr)
      out[destination] = val;
    if (out_bf16 != nullptr)
      out_bf16[destination] = hip_bfloat16(val);
  }
}

template<std::uint32_t WavesPerBlock>
__launch_bounds__(WavesPerBlock * 32, 4) __global__
    void Wave32GEMVKernel_1Row(const hip_bfloat16* __restrict__ A,
                               const float* __restrict__ x,
                               float* __restrict__ y, std::size_t M,
                               std::size_t K) {
  const std::size_t tid = threadIdx.x;
  const std::size_t lane_id = tid & 31u;
  const std::size_t warp_id = tid >> 5u;
  const std::size_t m = (blockIdx.x * WavesPerBlock) + warp_id;
  if (m >= M)
    return;

  const auto* row = A + (m * K);
  const auto* row_vec = reinterpret_cast<const uint4*>(row);
  const std::size_t K_vec = K / 8;

  float dot = 0.0F;
  for (std::size_t vi = lane_id; vi < K_vec; vi += 32) {
    const uint4 v = row_vec[vi];
    const auto* vals = reinterpret_cast<const hip_bfloat16*>(&v);
    const std::size_t k = vi * 8;
    const float4 x0 = *reinterpret_cast<const float4*>(&x[k + 0]);
    const float4 x1 = *reinterpret_cast<const float4*>(&x[k + 4]);

    dot += (static_cast<float>(vals[0]) * x0.x) +
           (static_cast<float>(vals[1]) * x0.y) +
           (static_cast<float>(vals[2]) * x0.z) +
           (static_cast<float>(vals[3]) * x0.w) +
           (static_cast<float>(vals[4]) * x1.x) +
           (static_cast<float>(vals[5]) * x1.y) +
           (static_cast<float>(vals[6]) * x1.z) +
           (static_cast<float>(vals[7]) * x1.w);
  }
  for (std::size_t k = (K_vec * 8) + lane_id; k < K; k += 32)
    dot += static_cast<float>(row[k]) * x[k];

  for (int offset = 16; offset > 0; offset >>= 1)
    dot += __shfl_xor(dot, offset);

  if (lane_id == 0) {
    const float r = 0.0F;
    y[m] = dot + r;
  }
}

__global__ void FastGEMVBlockKernel(const void* __restrict__ A,
                                    core::GgmlType a_type,
                                    const float* __restrict__ x,
                                    float* __restrict__ y, std::size_t M,
                                    std::size_t K) {
  const std::size_t m = blockIdx.x;
  if (m >= M)
    return;

  const std::size_t tid = threadIdx.x;
  const std::size_t lane_id = tid & 31u;
  const std::size_t warp_id = tid >> 5u;
  const std::size_t block_threads = blockDim.x;

  float dot = 0.0F;

  if (a_type == core::GgmlType::kBF16) {
    const auto* row = static_cast<const hip_bfloat16*>(A) + (m * K);
    const std::size_t K_vec = K / 8;
    const auto* row_vec = reinterpret_cast<const uint4*>(row);

    for (std::size_t vi = tid; vi < K_vec; vi += block_threads) {
      const uint4 v = row_vec[vi];
      const auto* vals = reinterpret_cast<const hip_bfloat16*>(&v);
      const std::size_t k = vi * 8;
      const float4 x0 = *reinterpret_cast<const float4*>(&x[k + 0]);
      const float4 x1 = *reinterpret_cast<const float4*>(&x[k + 4]);

      dot += (static_cast<float>(vals[0]) * x0.x) +
             (static_cast<float>(vals[1]) * x0.y) +
             (static_cast<float>(vals[2]) * x0.z) +
             (static_cast<float>(vals[3]) * x0.w) +
             (static_cast<float>(vals[4]) * x1.x) +
             (static_cast<float>(vals[5]) * x1.y) +
             (static_cast<float>(vals[6]) * x1.z) +
             (static_cast<float>(vals[7]) * x1.w);
    }
    for (std::size_t k = (K_vec * 8) + tid; k < K; k += block_threads)
      dot += static_cast<float>(row[k]) * x[k];
  } else {
    const auto* row = static_cast<const float*>(A) + (m * K);
    const std::size_t K_vec = K / 4;
    const auto* row_vec = reinterpret_cast<const float4*>(row);

    for (std::size_t vi = tid; vi < K_vec; vi += block_threads) {
      const float4 v = row_vec[vi];
      const std::size_t k = vi * 4;
      const float4 xv = *reinterpret_cast<const float4*>(&x[k]);
      dot += (v.x * xv.x) + (v.y * xv.y) + (v.z * xv.z) + (v.w * xv.w);
    }
    for (std::size_t k = (K_vec * 4) + tid; k < K; k += block_threads)
      dot += row[k] * x[k];
  }

  for (int offset = 16; offset > 0; offset >>= 1)
    dot += __shfl_xor(dot, offset);

  __shared__ float s_warp_sums[16];
  if (lane_id == 0)
    s_warp_sums[warp_id] = dot;
  __syncthreads();

  if (warp_id == 0) {
    const std::size_t num_warps = block_threads >> 5u;
    float block_sum = (lane_id < num_warps) ? s_warp_sums[lane_id] : 0.0F;
    for (int offset = static_cast<int>(num_warps / 2); offset > 0; offset >>= 1)
      block_sum += __shfl_xor(block_sum, offset);
    if (lane_id == 0) {
      const float r = 0.0F;
      y[m] = block_sum + r;
    }
  }
}

// Two Q8_0 rows dotted with x by one wave; row1_blocks may be null. Every
// GEMV entry point shares this reduction order.
__device__ __forceinline__ void Q8_0Dot2(
    const Q8_0Block* __restrict__ row0_blocks,
    const Q8_0Block* __restrict__ row1_blocks, const float* __restrict__ x,
    std::size_t num_blocks, std::size_t lane_id, float& out0, float& out1) {
  float sum0 = 0.0F;
  float sum1 = 0.0F;

  for (std::size_t b = lane_id; b < num_blocks; b += 32) {
    const float* xb = x + (b * kQ8_0BlockSize);
    const Q8_0Block& wblk0 = row0_blocks[b];
    const float d0 = __half2float(wblk0.d);
    float blk_dot0 = 0.0F;
#pragma unroll
    for (int i = 0; i < 32; ++i)
      blk_dot0 += static_cast<float>(wblk0.qs[i]) * xb[i];
    sum0 += d0 * blk_dot0;

    if (row1_blocks != nullptr) {
      const Q8_0Block& wblk1 = row1_blocks[b];
      const float d1 = __half2float(wblk1.d);
      float blk_dot1 = 0.0F;
#pragma unroll
      for (int i = 0; i < 32; ++i)
        blk_dot1 += static_cast<float>(wblk1.qs[i]) * xb[i];
      sum1 += d1 * blk_dot1;
    }
  }

  for (int off = 16; off > 0; off >>= 1) {
    sum0 += __shfl_xor(sum0, off);
    sum1 += __shfl_xor(sum1, off);
  }
  out0 = sum0;
  out1 = sum1;
}
template<std::uint32_t WavesPerBlock>
__launch_bounds__(WavesPerBlock * 32, 4) __global__
    void Q8_0GEMVKernel_2Rows(const void* __restrict__ A,
                              const float* __restrict__ x,
                              float* __restrict__ y, std::size_t M,
                              std::size_t K) {
  const std::size_t tid = threadIdx.x;
  const std::size_t lane_id = tid & 31u;
  const std::size_t warp_id = tid >> 5u;
  const std::size_t pair_idx = (blockIdx.x * WavesPerBlock) + warp_id;
  const std::size_t m0 = pair_idx * 2;
  const std::size_t m1 = m0 + 1;
  if (m0 >= M)
    return;
  const std::size_t num_blocks = K / kQ8_0BlockSize;
  const auto* blocks = static_cast<const Q8_0Block*>(A);
  float sum0, sum1;
  Q8_0Dot2(blocks + m0 * num_blocks,
           m1 < M ? blocks + m1 * num_blocks : nullptr, x, num_blocks, lane_id,
           sum0, sum1);
  if (lane_id == 0) {
    y[m0] = sum0;
    if (m1 < M)
      y[m1] = sum1;
  }
}
// Up to four Q8_0 GEMVs of one input in a single launch, each owning a
// contiguous range of blocks. With kSwiGLU, a wave dots row m of job 0 (gate)
// and of job 1 (up) and writes silu(gate) * up to job 0's output.
template<std::uint32_t WavesPerBlock, bool kSwiGLU>
__launch_bounds__(WavesPerBlock * 32, 4) __global__
    void Q8_0MultiGEMV(Projections jobs, const float* __restrict__ x,
                       std::size_t K) {
  int job = 0;
  for (int j = 1; j < jobs.count; ++j)
    if (int(blockIdx.x) >= jobs.first_block[j])
      job = j;
  const std::size_t lane_id = threadIdx.x & 31u;
  const std::size_t unit =
      (blockIdx.x - jobs.first_block[job]) * WavesPerBlock +
      (threadIdx.x >> 5u);
  const std::size_t M = jobs.job[job].rows;
  const std::size_t num_blocks = K / kQ8_0BlockSize;
  const auto* blocks = static_cast<const Q8_0Block*>(jobs.job[job].weight);
  float sum0, sum1;
  if constexpr (kSwiGLU) {
    if (unit >= M)
      return;
    Q8_0Dot2(
        blocks + unit * num_blocks,
        static_cast<const Q8_0Block*>(jobs.job[1].weight) + unit * num_blocks,
        x, num_blocks, lane_id, sum0, sum1);
    if (lane_id == 0) {
      // BatchedSwiGLUActivationKernel's formula.
      const float sig_g = 1.0F / (1.0F + expf(-sum0));
      jobs.job[0].out[unit] = (sum0 * sig_g) * sum1;
    }
    return;
  }
  const std::size_t m0 = unit * 2, m1 = m0 + 1;
  if (m0 >= M)
    return;
  Q8_0Dot2(blocks + m0 * num_blocks,
           m1 < M ? blocks + m1 * num_blocks : nullptr, x, num_blocks, lane_id,
           sum0, sum1);
  float* y = jobs.job[job].out;
  if (lane_id == 0) {
    y[m0] = sum0;
    if (m1 < M)
      y[m1] = sum1;
  }
}

template<int Offset = 16>
__device__ __forceinline__ float ReduceKQuantWave(float value) {
  const int other = __builtin_amdgcn_ds_swizzle(__builtin_bit_cast(int, value),
                                                (Offset << 10) | 31);
  const float sum = value + __builtin_bit_cast(float, other);
  if constexpr (Offset > 1)
    return ReduceKQuantWave<Offset / 2>(sum);
  else
    return sum;
}

template<std::size_t Columns, int Offset>
__device__ __forceinline__ float ReduceKQuantColumns(
    const float (&values)[Columns]) {
  static_assert(Columns > 0 && (Columns & (Columns - 1)) == 0);
  static_assert(Offset >= 0);
  static_assert(Columns == 1 ||
                Columns <= 2 * static_cast<std::size_t>(Offset));
  if constexpr (Columns > 1) {
    constexpr std::size_t kHalf = Columns / 2;
    const bool high = (threadIdx.x & static_cast<unsigned>(Offset)) != 0;
    float next[kHalf];
#pragma unroll
    for (std::size_t j = 0; j < kHalf; ++j) {
      const float own = high ? values[j + kHalf] : values[j];
      const float other = high ? values[j] : values[j + kHalf];
      const int partner = __builtin_amdgcn_ds_swizzle(
          __builtin_bit_cast(int, other), (Offset << 10) | 31);
      next[j] = own + __builtin_bit_cast(float, partner);
    }
    return ReduceKQuantColumns<kHalf, Offset / 2>(next);
  } else if constexpr (Offset > 0) {
    return ReduceKQuantWave<Offset>(values[0]);
  } else {
    return values[0];
  }
}

__device__ __forceinline__ __attribute__((convergent)) void SyncKQuantTile() {
  asm volatile("s_waitcnt lgkmcnt(0)" ::: "memory");
  __builtin_amdgcn_s_barrier();
  asm volatile("" ::: "memory");
}

template<std::uint32_t WavesPerBlock, std::size_t Batch,
         std::size_t RowsPerWave, bool StreamWeights = true,
         std::uint32_t HardwareWaveSize = 32, std::size_t TokenGroups = 1,
         bool GroupedGrid = false>
__launch_bounds__(WavesPerBlock * 32, 1) __global__
    void BatchedExactBf16GEMMFp32VecKernel(const hip_bfloat16* __restrict__ A,
                                           const float* __restrict__ X,
                                           float* __restrict__ Y, std::size_t M,
                                           std::size_t K) {
  static_assert(HardwareWaveSize == 32 || HardwareWaveSize == 64);
  static_assert(TokenGroups > 0);
  const auto group = GroupedGrid ? blockIdx.x : blockIdx.x % TokenGroups;
  const auto row_block = GroupedGrid ? blockIdx.y : blockIdx.x / TokenGroups;
  X += group * Batch * K;
  Y += group * Batch * M;
  constexpr std::size_t kValuesPerVector = 8;
  constexpr std::size_t kVectorsPerTile = 32;
  constexpr std::size_t kStride = kValuesPerVector + 4;
  constexpr std::size_t kTileStride = kVectorsPerTile * kStride;
  __shared__ float staged_x[Batch * kTileStride];

  const std::size_t lane = threadIdx.x & 31u;
  const std::size_t warp_id = threadIdx.x >> 5u;
  const std::size_t row_base =
      ((row_block * WavesPerBlock) + warp_id) * RowsPerWave;
  const std::size_t vector_count = K / kValuesPerVector;
  float sums[RowsPerWave][Batch] = {};

  for (std::size_t tile_base = 0; tile_base < vector_count;
       tile_base += kVectorsPerTile) {
    constexpr std::size_t kTileHalves = Batch * kVectorsPerTile * 2;
    for (std::size_t flat = threadIdx.x; flat < kTileHalves;
         flat += blockDim.x) {
      const std::size_t token = flat / (kVectorsPerTile * 2);
      const std::size_t within = flat % (kVectorsPerTile * 2);
      const std::size_t vector = within >> 1U;
      const std::size_t half = within & 1U;
      const std::size_t source_vector = tile_base + vector;
      float4 value = {0.0F, 0.0F, 0.0F, 0.0F};
      if (source_vector < vector_count) {
        value = *reinterpret_cast<const float4*>(
            X + (token * K) + (source_vector * kValuesPerVector) + (half * 4));
      }
      *reinterpret_cast<float4*>(staged_x + (token * kTileStride) +
                                 (vector * kStride) + (half * 4)) = value;
    }
    if constexpr (Batch == 16)
      SyncKQuantTile();
    else
      __syncthreads();

    const std::size_t vector = tile_base + lane;
    if (vector < vector_count) {
      uint4 packed[RowsPerWave];
#pragma unroll
      for (std::size_t r = 0; r < RowsPerWave; ++r) {
        const std::size_t row = row_base + r;
        const std::size_t safe_row = row < M ? row : M - 1;
        if constexpr (!StreamWeights) {
          packed[r] =
              reinterpret_cast<const uint4*>(A + (safe_row * K))[vector];
        } else {
          typedef std::uint32_t PackedWeights
              __attribute__((ext_vector_type(4), may_alias));
          const auto words = __builtin_nontemporal_load(
              reinterpret_cast<const PackedWeights*>(A + (safe_row * K)) +
              vector);
          packed[r] = {words[0], words[1], words[2], words[3]};
        }
      }
#pragma unroll
      for (std::size_t token = 0; token < Batch; ++token) {
        const float* input =
            staged_x + (token * kTileStride) + (lane * kStride);
        const float4 x0 = *reinterpret_cast<const float4*>(input);
        const float4 x1 = *reinterpret_cast<const float4*>(input + 4);
#pragma unroll
        for (std::size_t r = 0; r < RowsPerWave; ++r) {
          const auto* weights =
              reinterpret_cast<const hip_bfloat16*>(&packed[r]);
          sums[r][token] += (static_cast<float>(weights[0]) * x0.x) +
                            (static_cast<float>(weights[1]) * x0.y) +
                            (static_cast<float>(weights[2]) * x0.z) +
                            (static_cast<float>(weights[3]) * x0.w) +
                            (static_cast<float>(weights[4]) * x1.x) +
                            (static_cast<float>(weights[5]) * x1.y) +
                            (static_cast<float>(weights[6]) * x1.z) +
                            (static_cast<float>(weights[7]) * x1.w);
        }
      }
    }
    if constexpr (Batch == 16)
      SyncKQuantTile();
    else
      __syncthreads();
  }

  for (std::size_t k = (vector_count * kValuesPerVector) + lane; k < K;
       k += 32) {
#pragma unroll
    for (std::size_t r = 0; r < RowsPerWave; ++r) {
      const std::size_t row = row_base + r;
      const std::size_t safe_row = row < M ? row : M - 1;
      const float weight = static_cast<float>(A[(safe_row * K) + k]);
#pragma unroll
      for (std::size_t token = 0; token < Batch; ++token)
        sums[r][token] += weight * X[(token * K) + k];
    }
  }

  if constexpr (Batch == 16) {
#pragma unroll
    for (std::size_t r = 0; r < RowsPerWave; ++r) {
      const float value = ReduceKQuantColumns<Batch, 16>(sums[r]);
      const std::size_t row = row_base + r;
      if ((lane & 1U) == 0 && row < M)
        Y[(lane / 2) * M + row] = value;
    }
  } else {
#pragma unroll
    for (std::size_t r = 0; r < RowsPerWave; ++r) {
#pragma unroll
      for (std::size_t token = 0; token < Batch; ++token) {
        for (int offset = 16; offset > 0; offset >>= 1)
          sums[r][token] += __shfl_xor(sums[r][token], offset);
      }
    }
    if (lane == 0) {
#pragma unroll
      for (std::size_t r = 0; r < RowsPerWave; ++r) {
        const std::size_t row = row_base + r;
        if (row >= M)
          continue;
#pragma unroll
        for (std::size_t token = 0; token < Batch; ++token)
          Y[(token * M) + row] = sums[r][token];
      }
    }
  }
}

template<std::uint32_t WavesPerBlock, std::size_t Batch,
         std::size_t RowsPerWave, bool NarrowIndex = false,
         bool XorStage = false, std::uint32_t HardwareWaveSize = 32,
         std::size_t TokenGroups = 1, std::size_t TokensPerStep = Batch,
         bool DistributedOutput = false, bool Ragged = false>
__launch_bounds__(WavesPerBlock * 32, 1) __global__
    void SmallBatchQ8_0ExactFp32VecGEMMKernel(const void* __restrict__ w,
                                              const float* __restrict__ x,
                                              float* __restrict__ y,
                                              std::size_t wide_m,
                                              std::size_t wide_k,
                                              std::size_t valid_rows = 0) {
  static_assert(HardwareWaveSize == 32 || HardwareWaveSize == 64);
  static_assert(TokenGroups > 0 && TokensPerStep > 0 &&
                Batch % TokensPerStep == 0);
  using Index = std::conditional_t<NarrowIndex, std::uint32_t, std::size_t>;
  const Index m = static_cast<Index>(wide_m);
  const Index k = static_cast<Index>(wide_k);
  const Index token_group =
      static_cast<Index>(blockIdx.y) * TokenGroups + blockIdx.x % TokenGroups;
  x += token_group * Batch * k;
  y += token_group * Batch * m;
  constexpr Index kBlocksPerTile = 32;
  constexpr Index kVectorsPerBlock = kQ8_0BlockSize / 4;
  constexpr Index kStride = kQ8_0BlockSize + (XorStage ? 0 : 4);
  constexpr Index kTileStride = kBlocksPerTile * kStride;
  __shared__ float staged_x[Batch * kTileStride];

  const Index lane = threadIdx.x & 31u;
  const Index warp_id = threadIdx.x >> 5u;
  const Index row_base =
      (((blockIdx.x / TokenGroups) * WavesPerBlock) + warp_id) * RowsPerWave;
  const Index num_blocks = k / kQ8_0BlockSize;
  const auto* base = static_cast<const Q8_0Block*>(w);
  float sums[RowsPerWave][Batch] = {};

  for (Index tile_base = 0; tile_base < num_blocks;
       tile_base += kBlocksPerTile) {
    constexpr Index kTileVectors = Batch * kBlocksPerTile * kVectorsPerBlock;
    for (Index flat = threadIdx.x; flat < kTileVectors; flat += blockDim.x) {
      const Index token = flat / (kBlocksPerTile * kVectorsPerBlock);
      const Index within = flat % (kBlocksPerTile * kVectorsPerBlock);
      const Index block = within / kVectorsPerBlock;
      const Index vector = within % kVectorsPerBlock;
      const Index source_block = tile_base + block;
      float4 value = {0.0F, 0.0F, 0.0F, 0.0F};
      if ((!Ragged || token_group * Batch + token < valid_rows) &&
          source_block < num_blocks) {
        value = *reinterpret_cast<const float4*>(
            x + (token * k) + (source_block * kQ8_0BlockSize) + (vector * 4));
      }
      *reinterpret_cast<float4*>(staged_x + (token * kTileStride) +
                                 (XorStage ? vector * 128 + (block ^ vector) * 4
                                           : block * kStride + vector * 4)) =
          value;
    }
    if constexpr (NarrowIndex)
      SyncKQuantTile();
    else
      __syncthreads();

    const Index block = tile_base + lane;
    if (block < num_blocks) {
      const Q8_0Block* rows[RowsPerWave];
      float scale[RowsPerWave];
#pragma unroll
      for (Index r = 0; r < RowsPerWave; ++r) {
        const Index row = row_base + r;
        const Index safe_row = row < m ? row : m - 1;
        rows[r] = &base[(safe_row * num_blocks) + block];
        scale[r] = __half2float(rows[r]->d);
      }
      constexpr bool kPreloadWeights = TokensPerStep < Batch;
      constexpr Index kPackedGroups = kPreloadWeights ? kVectorsPerBlock : 1;
      std::uint32_t packed[RowsPerWave][kPackedGroups];
      if constexpr (kPreloadWeights) {
#pragma unroll
        for (Index r = 0; r < RowsPerWave; ++r) {
#pragma unroll
          for (Index group = 0; group < kVectorsPerBlock; ++group) {
            __builtin_memcpy(&packed[r][group], rows[r]->qs + group * 4,
                             sizeof(std::uint32_t));
          }
        }
      }
#pragma unroll
      for (Index token_base = 0; token_base < Batch;
           token_base += TokensPerStep) {
        if constexpr (kPreloadWeights)
          __builtin_amdgcn_sched_barrier(0);
        float block_dots[RowsPerWave][TokensPerStep] = {};
#pragma unroll
        for (Index group = 0; group < kVectorsPerBlock; ++group) {
          if constexpr (DistributedOutput && TokensPerStep == Batch)
            __builtin_amdgcn_sched_barrier(0);
          if constexpr (!kPreloadWeights) {
#pragma unroll
            for (Index r = 0; r < RowsPerWave; ++r) {
              __builtin_memcpy(&packed[r][0], rows[r]->qs + group * 4,
                               sizeof(std::uint32_t));
            }
          }
#pragma unroll
          for (Index local_token = 0; local_token < TokensPerStep;
               ++local_token) {
            const Index token = token_base + local_token;
            const float4 xv = *reinterpret_cast<const float4*>(
                staged_x + token * kTileStride +
                (XorStage ? group * 128 + (lane ^ group) * 4
                          : lane * kStride + group * 4));
#pragma unroll
            for (Index r = 0; r < RowsPerWave; ++r) {
              const std::uint32_t p = packed[r][kPreloadWeights ? group : 0];
              block_dots[r][local_token] +=
                  static_cast<float>(static_cast<std::int8_t>(p & 0xFFU)) *
                  xv.x;
              block_dots[r][local_token] +=
                  static_cast<float>(
                      static_cast<std::int8_t>((p >> 8U) & 0xFFU)) *
                  xv.y;
              block_dots[r][local_token] +=
                  static_cast<float>(
                      static_cast<std::int8_t>((p >> 16U) & 0xFFU)) *
                  xv.z;
              block_dots[r][local_token] +=
                  static_cast<float>(
                      static_cast<std::int8_t>((p >> 24U) & 0xFFU)) *
                  xv.w;
            }
          }
        }
#pragma unroll
        for (Index r = 0; r < RowsPerWave; ++r) {
#pragma unroll
          for (Index local_token = 0; local_token < TokensPerStep;
               ++local_token) {
            sums[r][token_base + local_token] +=
                scale[r] * block_dots[r][local_token];
          }
        }
      }
    }
    if constexpr (NarrowIndex)
      SyncKQuantTile();
    else
      __syncthreads();
  }

  if constexpr (DistributedOutput) {
    static_assert(Batch == 16);
#pragma unroll
    for (Index r = 0; r < RowsPerWave; ++r) {
      const float value = ReduceKQuantColumns<Batch, 16>(sums[r]);
      const Index row = row_base + r;
      if ((lane & 1U) == 0 && row < m &&
          (!Ragged || token_group * Batch + lane / 2 < valid_rows))
        y[(lane / 2) * m + row] = value;
    }
  } else {
#pragma unroll
    for (Index r = 0; r < RowsPerWave; ++r) {
#pragma unroll
      for (Index token = 0; token < Batch; ++token) {
        if constexpr (NarrowIndex) {
          sums[r][token] = ReduceKQuantWave(sums[r][token]);
        } else {
          for (int offset = 16; offset > 0; offset >>= 1)
            sums[r][token] += __shfl_xor(sums[r][token], offset);
        }
      }
    }
    if (lane == 0) {
#pragma unroll
      for (Index r = 0; r < RowsPerWave; ++r) {
        const Index row = row_base + r;
        if (row >= m)
          continue;
#pragma unroll
        for (Index token = 0; token < Batch; ++token) {
          if (!Ragged || token_group * Batch + token < valid_rows)
            y[(token * m) + row] = sums[r][token];
        }
      }
    }
  }
}

__device__ float Value(const Tensor& w, std::size_t i) {
  if (w.type == core::GgmlType::kF32)
    return static_cast<const float*>(w.data)[i];
  if (w.type == core::GgmlType::kF16)
    return __half2float(static_cast<const __half*>(w.data)[i]);
  if (w.type == core::GgmlType::kBF16)
    return float(static_cast<const hip_bfloat16*>(w.data)[i]);
  if (w.type == core::GgmlType::kQ8_0) {
    const auto& b = static_cast<const Q8_0Block*>(w.data)[i / 32];
    return __half2float(b.d) * b.qs[i % 32];
  }
  return NAN;  // The host binder rejects unsupported formats.
}
__global__ void Embedding(Tensor w, const std::uint32_t* ids, float* y, int n) {
  const auto i = std::size_t(blockIdx.x) * blockDim.x + threadIdx.x;
  if (i < std::size_t(n) * w.cols)
    y[i] = Value(w, std::size_t(ids[i / w.cols]) * w.cols + i % w.cols);
}
__global__ void F16Dense(Tensor w, const float* x, float* y, int n) {
  int row = blockIdx.x * 4 + threadIdx.x / 32, lane = threadIdx.x % 32,
      token = blockIdx.y;
  if (row >= int(w.rows) || token >= n)
    return;
  float sum = 0;
  for (int k = lane; k < int(w.cols); k += 32)
    sum = fmaf(Value(w, std::size_t(row) * w.cols + k),
               x[std::size_t(token) * w.cols + k], sum);
  for (int d = 16; d; d /= 2)
    sum += __shfl_down(sum, d, 32);
  if (!lane)
    y[std::size_t(token) * w.rows + row] = sum;
}
// Block-wide sum in the shared RMSNorm's order: a per-thread FMA chain over
// strided elements, then a halving tree in LDS.
__device__ float RowSquares(float sum, float* scratch) {
  const int tid = threadIdx.x;
  scratch[tid] = sum;
  __syncthreads();
  for (int stride = 128; stride > 0; stride /= 2) {
    if (tid < stride)
      scratch[tid] += scratch[tid + stride];
    __syncthreads();
  }
  sum = scratch[0];
  __syncthreads();
  return sum;
}
constexpr int kNormItems = 16;
// One block per row: x += post_norm(branch), then z = norm(x) as FP32 rows
// or as split prompt activations. A null branch only normalizes x; a null
// norm weight only updates x. Each step keeps the separate kernels' rounding.
__global__ void ResidualNormKernel(const float* __restrict__ branch,
                                   const float* __restrict__ post_weight,
                                   float* __restrict__ x,
                                   const float* __restrict__ weight, float* z,
                                   SplitActivations split, int H, float eps) {
  __shared__ float scratch[256];
  const int row = blockIdx.x, tid = threadIdx.x, items = H / 256;
  float* xr = x + std::size_t(row) * H;
  // Every load is issued before the first reduction.
  float v[kNormItems], pw[kNormItems], nw[kNormItems];
  for (int i = 0; i < items; ++i) {
    v[i] = xr[tid + 256 * i];
    pw[i] = branch && post_weight ? post_weight[tid + 256 * i] : 0;
    nw[i] = weight ? weight[tid + 256 * i] : 0;
  }
  if (branch) {
    float b[kNormItems], squares = 0;
    for (int i = 0; i < items; ++i) {
      b[i] = branch[std::size_t(row) * H + tid + 256 * i];
      squares = __fmaf_rn(b[i], b[i], squares);
    }
    if (post_weight) {
      const float inv = rsqrtf(RowSquares(squares, scratch) / float(H) + eps);
      for (int i = 0; i < items; ++i)
        b[i] = (b[i] * inv) * pw[i];
    }
    for (int i = 0; i < items; ++i) {
      v[i] = v[i] + b[i];
      xr[tid + 256 * i] = v[i];
    }
  }
  if (!weight)
    return;
  float squares = 0;
  for (int i = 0; i < items; ++i)
    squares = __fmaf_rn(v[i], v[i], squares);
  const float inv = rsqrtf(RowSquares(squares, scratch) / float(H) + eps);
  float maximum = 0;
  for (int i = 0; i < items; ++i) {
    v[i] = (v[i] * inv) * nw[i];
    maximum = fmaxf(maximum, fabsf(v[i]));
  }
  if (z) {
    for (int i = 0; i < items; ++i)
      z[std::size_t(row) * H + tid + 256 * i] = v[i];
    return;
  }
  for (int d = 16; d; d /= 2)
    maximum = fmaxf(maximum, __shfl_xor(maximum, d, 32));
  if (!(tid % 32))
    scratch[tid / 32] = maximum;
  __syncthreads();
  maximum = 0;
  for (int w = 0; w < 8; ++w)
    maximum = fmaxf(maximum, scratch[w]);
  const int e = maximum > 0 ? 14 - ilogbf(maximum) : 0;
  if (!tid)
    split.scale[row] = ldexpf(1.0F, -e);
  for (int i = 0; i < items; ++i) {
    const float scaled = ldexpf(v[i], e);
    const __half h = __float2half_rn(scaled);
    const auto at = std::size_t(row) * H + tid + 256 * i;
    split.high[at] = h;
    split.low[at] = __float2half_rn(scaled - __half2float(h));
  }
}
// Frequencies use a double-precision power rounded to FP32, computed once.
__global__ void Frequencies(float* out, int D, float theta) {
  int pair = threadIdx.x;
  if (pair < D / 2)
    out[pair] = float(pow(double(theta), double(-2.0F * pair / D)));
}
// Each thread owns one frequency pair and rotates kRopeRows (token, head) rows.
constexpr int kRopeRows = 8;
__global__ void Rotary(float* x, const float* frequencies, const float* factors,
                       int n, int heads, int D, int position) {
  int pair = threadIdx.x % (D / 2), slots = blockDim.x / (D / 2);
  int first = blockIdx.x * slots * kRopeRows + threadIdx.x / (D / 2);
  float frequency = frequencies[pair];
  for (int i = 0; i < kRopeRows; ++i) {
    int head = first + i * slots, token = head / heads;
    if (head >= n * heads)
      return;
    float angle = (position + token) * frequency;
    if (factors)
      angle /= factors[pair];
    float sn, cs;
    sincosf(angle, &sn, &cs);
    float a = x[head * D + pair], b = x[head * D + pair + D / 2];
    x[head * D + pair] = a * cs - b * sn;
    x[head * D + pair + D / 2] = b * cs + a * sn;
  }
}
// Per-head Q/K RMSNorm, RoPE and the F16 K/V store of rows in one launch.
// A block of D / 2 threads owns a head of row blockIdx.y and a thread owns
// one RoPE pair, which are also the two elements it normalizes. The
// squares, their tree reduction and every later expression repeat
// BatchedPerHeadRMSNormKernel and Rotary exactly, so results are unchanged.
// With capacity, the one decode row goes to ring slot position % capacity;
// without, row r goes to row r of ck and cv.
template<int D>
__launch_bounds__(D / 2) __global__ void DecodeHeadsKernel(
    float* __restrict__ q, float* __restrict__ k, const float* __restrict__ v,
    const float* __restrict__ q_norm, const float* __restrict__ k_norm,
    const float* __restrict__ frequencies, const float* __restrict__ factors,
    Half* __restrict__ ck, Half* __restrict__ cv, int heads, int kv_heads,
    int position, int capacity, float eps,
    const std::uint32_t* __restrict__ positions = nullptr) {
  const int head = blockIdx.x, pair = threadIdx.x, row = blockIdx.y;
  const bool is_key = head >= heads;
  const int kvh = head - heads;
  q += std::size_t(row) * heads * D;
  k += std::size_t(row) * kv_heads * D;
  v += std::size_t(row) * kv_heads * D;
  position = positions ? int(positions[row]) : position + row;
  float* x = is_key ? k + kvh * D : q + head * D;
  const float* weight = is_key ? k_norm : q_norm;
  const float x0 = x[pair], x1 = x[pair + D / 2];
  // The original 256-thread tree: stride 128 adds zeros, stride 64 pairs
  // element i with i + 64, then halves down to one.
  __shared__ float s_sum[D / 2];
  {
    // Both squares round before the add, as two separate threads did.
#pragma clang fp contract(off)
    s_sum[pair] = x0 * x0 + x1 * x1;
  }
  __syncthreads();
  for (int stride = D / 4; stride > 0; stride /= 2) {
    if (pair < stride)
      s_sum[pair] += s_sum[pair + stride];
    __syncthreads();
  }
  const float mean_sq = s_sum[0] / static_cast<float>(D);
  const float inv_rms = rsqrtf(mean_sq + eps);
  const float a = (x0 * inv_rms) * weight[pair],
              b = (x1 * inv_rms) * weight[pair + D / 2];
  float angle = position * frequencies[pair];
  if (factors)
    angle /= factors[pair];
  float sn, cs;
  sincosf(angle, &sn, &cs);
  const float r0 = a * cs - b * sn, r1 = b * cs + a * sn;
  x[pair] = r0;
  x[pair + D / 2] = r1;
  if (!is_key)
    return;
  const std::size_t slot =
      std::size_t(capacity ? position % capacity : row) * kv_heads * D +
      kvh * D;
  const auto f16 = [](float x) {
    return __builtin_bit_cast(Half, static_cast<_Float16>(x));
  };
  ck[slot + pair] = f16(r0);
  ck[slot + pair + D / 2] = f16(r1);
  cv[slot + pair] = f16(v[kvh * D + pair]);
  cv[slot + pair + D / 2] = f16(v[kvh * D + pair + D / 2]);
}
template<class F, int... I>
__device__ __forceinline__ void Unroll(F f, std::integer_sequence<int, I...>) {
  (f(std::integral_constant<int, I>{}), ...);
}
// acc += (lane N of this 16-lane row's x) * y, as one DPP row_share FMA.
template<int N>
__device__ __forceinline__ float FmaRowShare(float x, float y, float acc) {
  asm("v_fmac_f32_dpp %0, %1, %2 row_share:%3 row_mask:0xf bank_mask:0xf"
      : "+v"(acc)
      : "v"(x), "v"(y), "n"(N));
  return acc;
}
using v16h = __attribute__((__vector_size__(16 * sizeof(_Float16)))) _Float16;
using v8f = __attribute__((__vector_size__(8 * sizeof(float)))) float;
// 16 contiguous halves; every fragment row starts on a 16-byte boundary.
__device__ __forceinline__ v16h Fragment(const Half* p) {
  union {
    v16h f;
    uint4 u[2];
  } c;
  c.u[0] = reinterpret_cast<const uint4*>(p)[0];
  c.u[1] = reinterpret_cast<const uint4*>(p)[1];
  return c.f;
}
// The same lane of the other 16-lane half of the wave.
__device__ __forceinline__ unsigned OtherHalf(unsigned x) {
  return __builtin_amdgcn_permlanex16(x, x, 0x76543210u, 0xfedcba98u, false,
                                      false);
}
__device__ __forceinline__ float OtherHalf(float x) {
  return __builtin_bit_cast(float, OtherHalf(__builtin_bit_cast(unsigned, x)));
}
__device__ __forceinline__ Half ToHalf(float x) {
  return __builtin_bit_cast(Half, static_cast<_Float16>(x));
}
__device__ __forceinline__ float4 Widen(uint2 h) {
  const auto* x = reinterpret_cast<const _Float16*>(&h);
  return make_float4(float(x[0]), float(x[1]), float(x[2]), float(x[3]));
}
// Rows at or after position come from the current chunk, earlier rows from
// the ring.
__device__ __forceinline__ const Half* KeyRow(const Half* chunk,
                                              const Half* ring, int t,
                                              int position, int capacity,
                                              int stride) {
  return t >= position ? chunk + std::size_t(t - position) * stride
                       : ring + std::size_t(t % capacity) * stride;
}
// Causal prompt attention on the matrix cores: FP16 Q, K, V and
// probabilities, FP32 accumulation and softmax. A block owns 128 query rows
// of one KV group (16 queries of one head per wave) and streams 32-key tiles
// of the F16 cache through LDS, prefetching the next tile into registers.
//
// Each wave computes S^T = K Q^T and O^T = V^T P^T. In the WMMA accumulator
// layout lane L then holds query L % 16 and keys (or dimensions) 2i + L / 16,
// so a query's softmax state lives in one lane pair: the row maximum and sum
// need one cross-half exchange and the rescale is a per-lane scalar. Scores
// are kept in base-2 units. Long histories split keys across blockIdx.y; each
// split stores its maximum, sum and unnormalized output for PromptCombine.
template<int D, int kGroup>
__launch_bounds__(256) __global__
    void WmmaAttn(const float* __restrict__ q, const Half* __restrict__ k,
                  const Half* __restrict__ v, const float* __restrict__ gate,
                  const Half* __restrict__ ck, const Half* __restrict__ cv,
                  float* __restrict__ y, float* __restrict__ partial, int n,
                  int heads, int kh, int position, int capacity, int window,
                  int span) {
  static_assert(D == 128 && 8 % kGroup == 0);
  constexpr int kKeys = 32, kQueries = 128 / kGroup, kSteps = D / 16;
  constexpr int kKStride = D + 8, kVStride = kKeys + 8;
  __shared__ __attribute__((aligned(16))) Half sk[kKeys * kKStride];
  __shared__ __attribute__((aligned(16))) Half svt[D * kVStride];
  const int tid = threadIdx.x, lane = tid % 32, wave = tid / 32;
  const int col = lane % 16, half = lane / 16;
  const int g = blockIdx.z, split = blockIdx.y, q0 = blockIdx.x * kQueries;
  const int h = g * kGroup + wave % kGroup, w0 = q0 + wave / kGroup * 16;
  const int row = w0 + col, stride = kh * D;
  const bool live = row < n;
  // Q carries the softmax scale in base-2 units before its split.
  const float scale = rsqrtf(float(D)) * 1.44269504088896341F;
  v16h qf[kSteps], ql[kSteps];
  {
    const float* qr = q + (std::size_t(live ? row : 0) * heads + h) * D;
#pragma unroll
    for (int s = 0; s < kSteps; ++s)
#pragma unroll
      for (int c = 0; c < 4; ++c) {
        float4 f = live ? reinterpret_cast<const float4*>(qr)[s * 4 + c]
                        : make_float4(0, 0, 0, 0);
        f.x *= scale;
        f.y *= scale;
        f.z *= scale;
        f.w *= scale;
        qf[s][c * 4 + 0] = static_cast<_Float16>(f.x);
        qf[s][c * 4 + 1] = static_cast<_Float16>(f.y);
        qf[s][c * 4 + 2] = static_cast<_Float16>(f.z);
        qf[s][c * 4 + 3] = static_cast<_Float16>(f.w);
        ql[s][c * 4 + 0] = static_cast<_Float16>(f.x - float(qf[s][c * 4 + 0]));
        ql[s][c * 4 + 1] = static_cast<_Float16>(f.y - float(qf[s][c * 4 + 1]));
        ql[s][c * 4 + 2] = static_cast<_Float16>(f.z - float(qf[s][c * 4 + 2]));
        ql[s][c * 4 + 3] = static_cast<_Float16>(f.w - float(qf[s][c * 4 + 3]));
      }
  }
  const int span_first = split * span, span_last = span_first + span - 1;
  const auto first_key = [&](int query) {
    return max(window > 0 ? query + 1 - window : 0, span_first);
  };
  const int query = position + row;
  const int lo = first_key(query), hi = min(query, span_last);
  const int block_first = max(0, first_key(position + q0));
  const int block_last = min(position + min(q0 + kQueries, n) - 1, span_last);
  const int wave_first = first_key(position + w0);
  const int wave_last = min(position + min(w0 + 16, n) - 1, span_last);
  // Keys every query of the wave sees: tiles inside skip the mask.
  const int open_first = first_key(position + min(w0 + 16, n) - 1);
  const int open_last = min(position + w0, span_last);
  v8f acc[kSteps] = {};
  float maximum = -INFINITY, sum = 0;
  // K: 32 keys x 16 uint4 per tile, two per thread. V: lane owns a key and
  // wave owns 16 dimensions, so the transposed LDS writes do not conflict.
  uint4 kr[2], vr[2];
  const auto load = [&](int base) {
#pragma unroll
    for (int i = 0; i < 2; ++i) {
      const int idx = tid + i * 256, t = base + idx / (D / 8);
      kr[i] = t <= block_last
                  ? reinterpret_cast<const uint4*>(
                        KeyRow(k, ck, t, position, capacity, stride) +
                        g * D)[idx % (D / 8)]
                  : make_uint4(0, 0, 0, 0);
    }
    const int t = base + lane;
#pragma unroll
    for (int i = 0; i < 2; ++i)
      vr[i] = t <= block_last
                  ? reinterpret_cast<const uint4*>(
                        KeyRow(v, cv, t, position, capacity, stride) + g * D +
                        wave * 16)[i]
                  : make_uint4(0, 0, 0, 0);
  };
  load(block_first);
  for (int base = block_first; base <= block_last; base += kKeys) {
    __syncthreads();
#pragma unroll
    for (int i = 0; i < 2; ++i) {
      const int idx = tid + i * 256;
      *reinterpret_cast<uint4*>(
          &sk[idx / (D / 8) * kKStride + idx % (D / 8) * 8]) = kr[i];
    }
    {
      const auto* vh = reinterpret_cast<const Half*>(vr);
#pragma unroll
      for (int d = 0; d < 16; ++d)
        svt[(wave * 16 + d) * kVStride + lane] = vh[d];
    }
    __syncthreads();
    if (base + kKeys <= block_last)
      load(base + kKeys);
    if (w0 >= n || base > wave_last || base + kKeys <= wave_first)
      continue;
    v8f s[2] = {};
#pragma unroll
    for (int st = 0; st < kSteps; ++st)
#pragma unroll
      for (int kb = 0; kb < 2; ++kb) {
        const v16h kf = Fragment(&sk[(kb * 16 + col) * kKStride + st * 16]);
        s[kb] = __builtin_amdgcn_wmma_f32_16x16x16_f16_w32(kf, ql[st], s[kb]);
        s[kb] = __builtin_amdgcn_wmma_f32_16x16x16_f16_w32(kf, qf[st], s[kb]);
      }
    float tile_max = -INFINITY;
    if (base >= open_first && base + kKeys - 1 <= open_last) {
#pragma unroll
      for (int kb = 0; kb < 2; ++kb)
#pragma unroll
        for (int i = 0; i < 8; ++i)
          tile_max = fmaxf(tile_max, s[kb][i]);
    } else {
#pragma unroll
      for (int kb = 0; kb < 2; ++kb)
#pragma unroll
        for (int i = 0; i < 8; ++i) {
          const int t = base + kb * 16 + 2 * i + half;
          s[kb][i] = t >= lo && t <= hi ? s[kb][i] : -INFINITY;
          tile_max = fmaxf(tile_max, s[kb][i]);
        }
    }
    tile_max = fmaxf(tile_max, OtherHalf(tile_max));
    const float next = fmaxf(maximum, tile_max);
    const float shift = next == -INFINITY ? 0 : next;
    const float alpha = __builtin_amdgcn_exp2f(maximum - shift);
    maximum = next;
    // Probabilities round to F16 once; the sum adds the rounded values, so
    // the weights applied to V are exactly normalized.
    unsigned own[2][4];
    float local = 0;
#pragma unroll
    for (int kb = 0; kb < 2; ++kb)
#pragma unroll
      for (int j = 0; j < 4; ++j) {
        const auto a = static_cast<_Float16>(
                       __builtin_amdgcn_exp2f(s[kb][2 * j] - shift)),
                   b = static_cast<_Float16>(
                       __builtin_amdgcn_exp2f(s[kb][2 * j + 1] - shift));
        local += float(a) + float(b);
        own[kb][j] = unsigned(__builtin_bit_cast(Half, a)) |
                     unsigned(__builtin_bit_cast(Half, b)) << 16;
      }
    sum = sum * alpha + local;
    // An unchanged maximum gives alpha == 1 exactly.
    if (__builtin_amdgcn_ballot_w32(alpha != 1.0F))
#pragma unroll
      for (int t = 0; t < kSteps; ++t)
        acc[t] *= alpha;
#pragma unroll
    for (int kb = 0; kb < 2; ++kb) {
      // Key 2m comes from the first half's element m, key 2m + 1 from the
      // second half's.
      union {
        v16h f;
        unsigned u[8];
      } p;
#pragma unroll
      for (int j = 0; j < 4; ++j) {
        const unsigned other = OtherHalf(own[kb][j]);
        const unsigned first = half ? other : own[kb][j],
                       second = half ? own[kb][j] : other;
        p.u[2 * j] = (first & 0xffffu) | second << 16;
        p.u[2 * j + 1] = first >> 16 | (second & 0xffff0000u);
      }
#pragma unroll
      for (int t = 0; t < kSteps; ++t)
        acc[t] = __builtin_amdgcn_wmma_f32_16x16x16_f16_w32(
            Fragment(&svt[(t * 16 + col) * kVStride + kb * 16]), p.f, acc[t]);
    }
  }
  const float total = sum + OtherHalf(sum);
  if (!live)
    return;
  if (gridDim.y > 1) {
    float* out =
        partial + ((std::size_t(split) * n + row) * heads + h) * (D + 2);
    if (!half) {
      out[0] = maximum;
      out[1] = total;
    }
#pragma unroll
    for (int t = 0; t < kSteps; ++t)
#pragma unroll
      for (int i = 0; i < 8; ++i)
        out[2 + t * 16 + 2 * i + half] = acc[t][i];
    return;
  }
  const float g_scale = gate ? 1 + expf(-gate[row * heads + h]) : 1.0F;
  float* out = y + (std::size_t(row) * heads + h) * D;
#pragma unroll
  for (int t = 0; t < kSteps; ++t)
#pragma unroll
    for (int i = 0; i < 8; ++i)
      out[t * 16 + 2 * i + half] = (acc[t][i] / total) / g_scale;
}
// One decode query per head over the F16 ring. A block owns one KV group and
// a span of keys, processed in kDecodeKeys tiles with an online softmax; four
// threads split each key's dot products and all heads of the group share
// every loaded key and value row. Q, scores and P*V stay FP32. With several
// spans, each block stores its maximum, denominator and unnormalized output
// for DecodeCombine.
constexpr int kDecodeKeys = 64, kMaxGroup = 8, kMaxDecodeSplits = 128;
template<int D>
__launch_bounds__(256) __global__
    void DecodeAttn(const float* __restrict__ q, const Half* __restrict__ k,
                    const Half* __restrict__ v, const float* __restrict__ gate,
                    const Half* __restrict__ ck, const Half* __restrict__ cv,
                    float* __restrict__ y, float* __restrict__ partial,
                    int heads, int kh, int position, int capacity, int window,
                    int span) {
  constexpr int kChunks = D / 32;  // uint4 (8-half) chunks per thread and row
  __shared__ float4 sq[kMaxGroup][D / 4];
  __shared__ uint4 sv[kDecodeKeys][D / 8];
  __shared__ float sp[kMaxGroup][kDecodeKeys];
  __shared__ float reduce[8][kMaxGroup];
  const int g = blockIdx.x, split = blockIdx.y, splits = gridDim.y;
  const int tid = threadIdx.x, lane = tid % 32, wave = tid / 32;
  const int j = tid / 4, part = tid % 4;
  const int group = heads / kh, stride = kh * D;
  const int first = window > 0 ? max(0, position + 1 - window) : 0;
  const int begin = first + split * span;
  const int end = min(begin + span, position + 1);
  for (int i = tid; i < group * D / 4; i += 256)
    sq[i / (D / 4)][i % (D / 4)] = reinterpret_cast<const float4*>(
        q + (std::size_t(g) * group + i / (D / 4)) * D)[i % (D / 4)];
  // Reduces one value per head across the block (maximum or sum).
  const auto block_reduce = [&](float (&value)[kMaxGroup], bool maximum) {
    for (int hh = 0; hh < group; ++hh) {
      for (int offset = 16; offset; offset /= 2) {
        const float other = __shfl_xor(value[hh], offset, 32);
        value[hh] = maximum ? fmaxf(value[hh], other) : value[hh] + other;
      }
      if (!lane)
        reduce[wave][hh] = value[hh];
    }
    __syncthreads();
    for (int hh = 0; hh < group; ++hh) {
      value[hh] = reduce[0][hh];
      for (int w = 1; w < 8; ++w)
        value[hh] = maximum ? fmaxf(value[hh], reduce[w][hh])
                            : value[hh] + reduce[w][hh];
    }
    __syncthreads();
  };
  // Threads split the group's heads; each owns D * group / 256 dimensions.
  const int per_head = 256 / group, dims = D / per_head;
  const int oh = tid / per_head, d0 = (tid % per_head) * dims;
  const auto* sv_halves = reinterpret_cast<const _Float16*>(sv);
  const float scale = rsqrtf(float(D));
  float maxima[kMaxGroup], sums[kMaxGroup], acc[kMaxGroup / 2] = {};
  for (int hh = 0; hh < kMaxGroup; ++hh) {
    maxima[hh] = -INFINITY;
    sums[hh] = 0;
  }
  for (int base = begin; base < end; base += kDecodeKeys) {
    const int keys = min(kDecodeKeys, end - base), t = base + j;
    const bool valid = j < keys;
    float4 kk[2 * kChunks];
    __syncthreads();
    if (valid) {
      const Half* key = KeyRow(k, ck, t, position, capacity, stride) + g * D;
      const Half* value = KeyRow(v, cv, t, position, capacity, stride) + g * D;
#pragma unroll
      for (int c = 0; c < kChunks; ++c) {
        const int u = c * 4 + part;
        const uint4 kh8 = reinterpret_cast<const uint4*>(key)[u],
                    vh8 = reinterpret_cast<const uint4*>(value)[u];
        kk[2 * c] = Widen(make_uint2(kh8.x, kh8.y));
        kk[2 * c + 1] = Widen(make_uint2(kh8.z, kh8.w));
        sv[j][u] = vh8;
      }
    }
    __syncthreads();
    float score[kMaxGroup], tile[kMaxGroup];
    for (int hh = 0; hh < group; ++hh) {
      float dot = 0;
      if (valid)
#pragma unroll
        for (int c = 0; c < 2 * kChunks; ++c) {
          const float4 qq = sq[hh][(c / 2 * 4 + part) * 2 + c % 2];
          dot = fmaf(qq.x, kk[c].x, dot);
          dot = fmaf(qq.y, kk[c].y, dot);
          dot = fmaf(qq.z, kk[c].z, dot);
          dot = fmaf(qq.w, kk[c].w, dot);
        }
      dot += __shfl_xor(dot, 1, 4);
      dot += __shfl_xor(dot, 2, 4);
      score[hh] = valid ? dot * scale : -INFINITY;
      tile[hh] = score[hh];
    }
    block_reduce(tile, true);
    float alpha[kMaxGroup];
    for (int hh = 0; hh < group; ++hh) {
      const float next = fmaxf(maxima[hh], tile[hh]);
      alpha[hh] = expf(maxima[hh] - next);
      maxima[hh] = next;
      const float p = valid ? expf(score[hh] - next) : 0;
      if (!part)
        sp[hh][j] = p;
      // Each key appears in four lanes; count it once.
      tile[hh] = part ? 0 : p;
    }
    block_reduce(tile, false);
    for (int hh = 0; hh < group; ++hh)
      sums[hh] = sums[hh] * alpha[hh] + tile[hh];
    float own_alpha = alpha[0];
    for (int hh = 1; hh < group; ++hh)
      own_alpha = oh == hh ? alpha[hh] : own_alpha;
    for (int d = 0; d < dims; ++d)
      acc[d] *= own_alpha;
    for (int key = 0; key < keys; ++key) {
      const float p = sp[oh][key];
      for (int d = 0; d < dims; ++d)
        acc[d] = fmaf(p, float(sv_halves[key * D + d0 + d]), acc[d]);
    }
  }
  float own_max = maxima[0], own_sum = sums[0];
  for (int hh = 1; hh < group; ++hh)
    if (oh == hh) {
      own_max = maxima[hh];
      own_sum = sums[hh];
    }
  const int h = g * group + oh;
  if (splits == 1) {
    const float g_scale = gate ? 1 + expf(-gate[h]) : 1.0F;
    for (int d = 0; d < dims; ++d)
      y[std::size_t(h) * D + d0 + d] = (acc[d] / own_sum) / g_scale;
    return;
  }
  float* out = partial + (std::size_t(split) * heads + h) * (D + 2);
  if (!(tid % per_head)) {
    out[0] = own_max;
    out[1] = own_sum;
  }
  for (int d = 0; d < dims; ++d)
    out[2 + d0 + d] = acc[d];
}
// Merges WmmaAttn key spans (base-2 maxima): one block per (row, head).
template<int D>
__global__ void PromptCombine(const float* __restrict__ partial,
                              const float* __restrict__ gate,
                              float* __restrict__ y, int rows, int splits) {
  const int rh = blockIdx.x, d = threadIdx.x;
  float maximum = -INFINITY;
  for (int s = 0; s < splits; ++s)
    maximum = fmaxf(maximum, partial[(std::size_t(s) * rows + rh) * (D + 2)]);
  float sum = 0, acc = 0;
  for (int s = 0; s < splits; ++s) {
    const float* part = partial + (std::size_t(s) * rows + rh) * (D + 2);
    const float w = __builtin_amdgcn_exp2f(part[0] - maximum);
    sum = fmaf(part[1], w, sum);
    acc = fmaf(part[2 + d], w, acc);
  }
  y[std::size_t(rh) * D + d] = (acc / sum) / (gate ? 1 + expf(-gate[rh]) : 1.0F);
}
template<int D>
__global__ void DecodeCombine(const float* __restrict__ partial,
                              const float* __restrict__ gate,
                              float* __restrict__ y, int heads, int splits) {
  const int h = blockIdx.x, d = threadIdx.x;
  float maximum = -INFINITY;
  for (int s = 0; s < splits; ++s)
    maximum = fmaxf(maximum, partial[(std::size_t(s) * heads + h) * (D + 2)]);
  float sum = 0, acc = 0;
  for (int s = 0; s < splits; ++s) {
    const float* part = partial + (std::size_t(s) * heads + h) * (D + 2);
    const float w = expf(part[0] - maximum);
    sum = fmaf(part[1], w, sum);
    acc = fmaf(part[2 + d], w, acc);
  }
  y[std::size_t(h) * D + d] = (acc / sum) / (gate ? 1 + expf(-gate[h]) : 1.0F);
}
__global__ void PackRows(const float* k, const float* v, Half* k16, Half* v16,
                         std::size_t count) {
  const auto i = std::size_t(blockIdx.x) * blockDim.x + threadIdx.x;
  if (i >= count)
    return;
  k16[i] = ToHalf(k[i]);
  v16[i] = ToHalf(v[i]);
}
// out[i] = x[rows[i]]: the pooled (last) row of every sequence.
__global__ void GatherRowsKernel(const float* __restrict__ x,
                                 const std::uint32_t* __restrict__ rows,
                                 float* __restrict__ out, int width) {
  const int i = blockIdx.y;
  const float* src = x + std::size_t(rows[i]) * width;
  float* dst = out + std::size_t(i) * width;
  for (int c = blockIdx.x * blockDim.x + threadIdx.x; c < width;
       c += gridDim.x * blockDim.x)
    dst[c] = src[c];
}
// llama.cpp b9925 (HIP) rounds every activation that enters a Q8_0 matmul
// to 8-bit blocks of 32 values (q8_1) and multiplies integer codes. This
// kernel reproduces that rounding in place, so the GEMMs below see the
// values llama.cpp's integer dot products see. Per row, kQ8Mmq follows
// quantize_mmq_q8_1 (ggml-cuda/quantize.cu: d_inv = 127 / amax,
// q = roundf(x * d_inv), d = 1 / d_inv in FP32), used by MMQ for more than
// eight rows; kQ8Mmvq follows quantize_q8_1 (d = amax / 127,
// q = roundf(x / d), d stored as FP16), used by MMVQ for up to eight rows;
// kQ8None leaves the row as it is. One wave owns one block of 32 values.
__global__ void QuantizeQ8RowsKernel(float* __restrict__ x, int K,
                                     const std::uint8_t* __restrict__ style) {
  const int row = blockIdx.y;
  const int mode = style[row];
  const int i = blockIdx.x * blockDim.x + threadIdx.x;
  if (mode == kQ8None || i >= K)
    return;  // Uniform per wave: K is a multiple of 32.
  float* p = x + std::size_t(row) * K + i;
  const float v = *p;
  float amax = fabsf(v);
  for (int d = 16; d; d /= 2)
    amax = fmaxf(amax, __shfl_xor(amax, d, 32));
  float out = 0.0F;
  if (amax > 0.0F) {
    if (mode == kQ8Mmq) {
      const float d_inv = 127.0F / amax;
      const float q = roundf(v * d_inv);
      out = q * (1.0F / d_inv);
    } else {
      const float d = amax / 127.0F;
      const float q = roundf(v / d);
      out = q * __half2float(__float2half_rn(d));
    }
  }
  *p = out;
}
}  // namespace

void LaunchBatchedRMSNorm(const float* x, const float* weight, float* out,
                          void* out_bf16, std::size_t batch_size,
                          std::size_t dim, float eps, hipStream_t stream) {
  if (dim == 5120 && batch_size <= 64) {
    BatchedRMSNormKernel<5120><<<batch_size, 256, 0, stream>>>(
        x, weight, out, static_cast<hip_bfloat16*>(out_bf16), batch_size, dim,
        eps);
    return;
  }
  BatchedRMSNormKernel<><<<batch_size, 256, 0, stream>>>(
      x, weight, out, static_cast<hip_bfloat16*>(out_bf16), batch_size, dim,
      eps);
}

void LaunchBatchedPerHeadRMSNorm(const float* x, const float* weight,
                                 float* out, std::size_t batch_size,
                                 std::uint32_t num_heads,
                                 std::uint32_t head_dim, float eps,
                                 hipStream_t stream) {
  const dim3 grid(num_heads, static_cast<unsigned int>(batch_size));
  BatchedPerHeadRMSNormKernel<<<grid, 256, 0, stream>>>(
      x, weight, out, batch_size, num_heads, head_dim, eps);
}

void LaunchBatchedResidualAdd(const float* a, const float* b, float* out,
                              std::size_t batch_size, std::size_t dim,
                              hipStream_t stream) {
  const std::size_t total = batch_size * dim;
  const std::size_t block_size = 256;
  const std::size_t grid_size = (total + block_size - 1) / block_size;
  BatchedResidualAddKernel<<<grid_size, block_size, 0, stream>>>(a, b, out,
                                                                 total);
}

void LaunchBatchedSwiGLUActivation(const float* gate, const float* up,
                                   float* out, void* out_bf16,
                                   std::size_t num_elements,
                                   hipStream_t stream) {
  if (num_elements == 0)
    return;
  const unsigned int block_size = 256;
  const unsigned int num_blocks =
      static_cast<unsigned int>((num_elements + block_size - 1) / block_size);
  BatchedSwiGLUActivationKernel<<<num_blocks, block_size, 0, stream>>>(
      gate, up, out, static_cast<hip_bfloat16*>(out_bf16), num_elements);
}

void LaunchGEMV(const void* A, core::GgmlType a_type, const float* x, float* y,
                std::size_t M, std::size_t K, hipStream_t stream) {
  constexpr std::uint32_t kWavesPerBlock = 4;
  constexpr std::uint32_t kBlockThreads = kWavesPerBlock * 32;
  if (a_type == core::GgmlType::kQ8_0) {
    const std::size_t num_pairs = (M + 1U) / 2U;
    const std::size_t grid = (num_pairs + kWavesPerBlock - 1U) / kWavesPerBlock;
    Q8_0GEMVKernel_2Rows<kWavesPerBlock>
        <<<grid, kBlockThreads, 0, stream>>>(A, x, y, M, K);
    return;
  }
  if (a_type == core::GgmlType::kBF16 && K % 8 == 0 && K < 8192) {
    const auto* A_bf16 = static_cast<const hip_bfloat16*>(A);
    const std::size_t grid = (M + kWavesPerBlock - 1) / kWavesPerBlock;
    Wave32GEMVKernel_1Row<kWavesPerBlock>
        <<<grid, kBlockThreads, 0, stream>>>(A_bf16, x, y, M, K);
    return;
  }
  const std::size_t block_size = K >= 16384 ? 512 : 256;
  FastGEMVBlockKernel<<<M, block_size, 0, stream>>>(A, a_type, x, y, M, K);
}

void LaunchBatchedQuantGEMMFp32(core::GgmlType type, const void* w,
                                const float* fp32_x, float* y,
                                std::size_t batch, std::size_t m, std::size_t k,
                                hipStream_t stream) {
  if (m == 0 || k == 0 || batch == 0 || type != core::GgmlType::kQ8_0)
    return;
  if (batch > 8) {
    for (std::size_t offset = 0; offset < batch;) {
      const std::size_t remaining = batch - offset;
      const std::size_t width =
          remaining >= 16 ? 16 : (remaining >= 12 ? 12 : 0);
      const float* input = fp32_x + offset * k;
      float* output = y + offset * m;
      if (width == 16) {
        SmallBatchQ8_0ExactFp32VecGEMMKernel<16, 16, 3, true, true>
            <<<(m + 47) / 48, 512, 0, stream>>>(w, input, output, m, k);
      } else if (width == 12) {
        SmallBatchQ8_0ExactFp32VecGEMMKernel<16, 12, 2, true, true>
            <<<(m + 31) / 32, 512, 0, stream>>>(w, input, output, m, k);
      } else {
        const std::size_t step = std::min<std::size_t>(8, remaining);
        LaunchBatchedQuantGEMMFp32(type, w, input, output, step, m, k, stream);
        offset += step;
        continue;
      }
      offset += width;
    }
    return;
  }
  constexpr std::size_t kWarp = 32;
  constexpr std::size_t kVecWarpsPerBlock = 16;
  constexpr std::size_t kVecRowsPerWave = 2;
  constexpr std::size_t kVecRowsPerBlock = kVecWarpsPerBlock * kVecRowsPerWave;
  const unsigned int vec_blocks =
      static_cast<unsigned int>((m + kVecRowsPerBlock - 1) / kVecRowsPerBlock);
  const dim3 vec_block(static_cast<unsigned int>(kWarp * kVecWarpsPerBlock));
  switch (batch) {
    case 1:
      SmallBatchQ8_0ExactFp32VecGEMMKernel<kVecWarpsPerBlock, 1,
                                           kVecRowsPerWave>
          <<<vec_blocks, vec_block, 0, stream>>>(w, fp32_x, y, m, k);
      return;
    case 2:
      SmallBatchQ8_0ExactFp32VecGEMMKernel<kVecWarpsPerBlock, 2,
                                           kVecRowsPerWave>
          <<<vec_blocks, vec_block, 0, stream>>>(w, fp32_x, y, m, k);
      return;
    case 3:
      SmallBatchQ8_0ExactFp32VecGEMMKernel<kVecWarpsPerBlock, 3,
                                           kVecRowsPerWave>
          <<<vec_blocks, vec_block, 0, stream>>>(w, fp32_x, y, m, k);
      return;
    case 4:
      SmallBatchQ8_0ExactFp32VecGEMMKernel<kVecWarpsPerBlock, 4,
                                           kVecRowsPerWave>
          <<<vec_blocks, vec_block, 0, stream>>>(w, fp32_x, y, m, k);
      return;
    case 5:
      SmallBatchQ8_0ExactFp32VecGEMMKernel<kVecWarpsPerBlock, 5,
                                           kVecRowsPerWave>
          <<<vec_blocks, vec_block, 0, stream>>>(w, fp32_x, y, m, k);
      return;
    case 6:
      SmallBatchQ8_0ExactFp32VecGEMMKernel<kVecWarpsPerBlock, 6,
                                           kVecRowsPerWave>
          <<<vec_blocks, vec_block, 0, stream>>>(w, fp32_x, y, m, k);
      return;
    case 7:
      SmallBatchQ8_0ExactFp32VecGEMMKernel<kVecWarpsPerBlock, 7,
                                           kVecRowsPerWave>
          <<<vec_blocks, vec_block, 0, stream>>>(w, fp32_x, y, m, k);
      return;
    default:
      SmallBatchQ8_0ExactFp32VecGEMMKernel<kVecWarpsPerBlock, 8,
                                           kVecRowsPerWave>
          <<<vec_blocks, vec_block, 0, stream>>>(w, fp32_x, y, m, k);
      return;
  }
}

void Embed(const Tensor& w, const std::uint32_t* tokens, float* out, int n,
           hipStream_t s) {
  Embedding<<<(std::size_t(n) * w.cols + 255) / 256, 256, 0, s>>>(w, tokens,
                                                                  out, n);
}
std::size_t DenseWorkspaceBytes(std::size_t rows, std::size_t K) {
  return SplitActivationBytes(rows, K);
}
// The widest tile keeps 64 accumulators in each of 256 threads.
std::size_t SplitPartialBytes() {
  return std::size_t(kMaxSplitUnits) * 256 * 64 * sizeof(float);
}
namespace {
bool SplitPrompt(const Tensor& w, int n, DenseWorkspace workspace) {
  return n >= 32 && w.type == core::GgmlType::kQ8_0 && workspace.quantized;
}
// Blocks of kernel resident at once on the device.
template<auto kernel>
int ResidentBlocks() {
  static const int count = [] {
    int device = 0, units = 0, per_unit = 0;
    if (hipGetDevice(&device) != hipSuccess ||
        hipDeviceGetAttribute(&units, hipDeviceAttributeMultiprocessorCount,
                              device) != hipSuccess ||
        hipOccupancyMaxActiveBlocksPerMultiprocessor(&per_unit, kernel, 256,
                                                     0) != hipSuccess)
      return 0;
    return units * per_unit;
  }();
  return count;
}
// Splits the tiles of the last, partial wave of resident blocks across K
// when that shortens the launch. Time is counted in K blocks per wave; a
// part costs about four more for its prologue and partial sums (measured
// at LFM3's shapes).
SplitK PlanSplit(int token_blocks, int tiles, int k_blocks, int resident,
                 DenseWorkspace workspace) {
  SplitK plan{token_blocks, tiles};
  if (!workspace.partial || !workspace.tickets || resident <= 0)
    return plan;
  const int rest = tiles % resident;
  if (!rest)
    return plan;
  constexpr double kPartCost = 4;
  double best = k_blocks;
  for (int parts = 2; parts <= kMaxSplitParts; ++parts) {
    if (rest * parts > kMaxSplitUnits || k_blocks / parts < 8)
      break;
    const double time = (rest * parts + resident - 1) / resident *
                        (double(k_blocks) / parts + kPartCost);
    if (time < best) {
      best = time;
      plan.parts = parts;
    }
  }
  if (plan.parts > 1) {
    plan.split_from = tiles - rest;
    plan.partial = workspace.partial;
    plan.tickets = workspace.tickets;
  }
  return plan;
}
template<bool kSwiGLU = false, bool kRaw = false>
void LaunchSplit(std::span<const Output> outputs, SplitActivations split, int n,
                 int K, hipStream_t s, DenseWorkspace workspace = {}) {
  constexpr int BN = 64;
  Projections jobs{};
  jobs.count = int(outputs.size());
  int row_blocks = 0;
  bool wide = false;
  for (const auto& o : outputs)
    wide = wide || o.weight->rows >= 1024;
  const int tile_rows = (wide ? 256 : 64) / (kSwiGLU ? 2 : 1);
  for (int i = 0; i < jobs.count; ++i) {
    const auto& w = *outputs[i].weight;
    jobs.job[i] = {w.data, outputs[i].out, int(w.rows)};
    jobs.first_block[i] = row_blocks;
    if (!kSwiGLU || i == 0)
      row_blocks += (int(w.rows) + tile_rows - 1) / tile_rows;
  }
  const int token_blocks = (n + BN - 1) / BN, tiles = token_blocks * row_blocks;
  if (kSwiGLU)
    jobs.count = 1;  // Both weights belong to every row block.
  const auto launch = [&]<auto kernel>() {
    const auto plan = kSwiGLU ? SplitK{token_blocks, tiles}
                              : PlanSplit(token_blocks, tiles, K / 32,
                                          ResidentBlocks<kernel>(), workspace);
    const int units = plan.split_from + (tiles - plan.split_from) * plan.parts;
    kernel<<<units, 256, 0, s>>>(jobs, split, n, K, plan);
  };
  if (wide)
    launch.template operator()<RegQ8Gemm<BN / 16, kSwiGLU, kRaw>>();
  else
    launch.template operator()<SplitQ8Gemm<64, BN, 4, 2, kSwiGLU, kRaw>>();
}
}  // namespace
// One-row Q8_0 projections of one input in a single launch; false when the
// weights do not qualify.
template<bool kSwiGLU>
bool LaunchMultiGEMV(std::span<const Output> outputs, const float* x,
                     hipStream_t s) {
  constexpr std::uint32_t kWaves = 4;
  if (outputs.size() > Projections::kMax)
    return false;
  Projections jobs{};
  jobs.count = int(outputs.size());
  int blocks = 0;
  for (int i = 0; i < jobs.count; ++i) {
    const auto& w = *outputs[i].weight;
    if (w.type != core::GgmlType::kQ8_0 || w.cols != outputs[0].weight->cols ||
        w.cols % kQ8_0BlockSize)
      return false;
    jobs.job[i] = {w.data, outputs[i].out, int(w.rows)};
    jobs.first_block[i] = blocks;
    const int units = kSwiGLU ? int(w.rows) : (int(w.rows) + 1) / 2;
    if (!kSwiGLU || i == 0)
      blocks += (units + kWaves - 1) / kWaves;
  }
  if (kSwiGLU)
    jobs.count = 1;
  Q8_0MultiGEMV<kWaves, kSwiGLU>
      <<<blocks, kWaves * 32, 0, s>>>(jobs, x, outputs[0].weight->cols);
  return true;
}
bool SharesSplit(std::span<const Output> outputs, int n,
                 DenseWorkspace workspace) {
  bool shared = outputs.size() <= Projections::kMax;
  for (const auto& o : outputs)
    shared = shared && o.weight->cols == outputs[0].weight->cols &&
             SplitPrompt(*o.weight, n, workspace);
  return shared;
}
bool ResidualNorm(const float* branch, const Tensor* post_norm, float* x,
                  const Tensor* norm, float* z, int n, int H, float eps,
                  bool split, hipStream_t s, DenseWorkspace workspace) {
  if (H % 256 || H / 256 > kNormItems)
    return false;
  ResidualNormKernel<<<n, 256, 0, s>>>(
      branch, post_norm ? static_cast<const float*>(post_norm->data) : nullptr,
      x, norm ? static_cast<const float*>(norm->data) : nullptr,
      split ? nullptr : z, SplitActivations::In(workspace.quantized, n, H), H,
      eps);
  return true;
}
void Project(std::span<const Output> outputs, const float* x, int n,
             hipStream_t s, DenseWorkspace workspace, bool split_ready) {
  const auto K = outputs[0].weight->cols;
  if (n == 1 && LaunchMultiGEMV<false>(outputs, x, s))
    return;
  if (!SharesSplit(outputs, n, workspace)) {
    for (const auto& o : outputs)
      Dense(*o.weight, x, o.out, n, s, workspace);
    return;
  }
  const auto split = SplitActivations::In(workspace.quantized, n, K);
  if (!split_ready)
    SplitRows<<<n, 256, 0, s>>>(x, split, K);
  // With one wide projection all of them share its tiles; waves past a
  // narrow projection's rows skip their products.
  LaunchSplit(outputs, split, n, K, s, workspace);
}
void ProjectSwiGLU(const Tensor& gate, const Tensor& up, const float* x,
                   float* out, float* up_scratch, int n, hipStream_t s,
                   DenseWorkspace workspace, bool split_ready) {
  const Output outputs[] = {{&gate, out}, {&up, nullptr}};
  if (SharesSplit(outputs, n, workspace) && gate.rows == up.rows) {
    const auto split = SplitActivations::In(workspace.quantized, n, gate.cols);
    if (!split_ready)
      SplitRows<<<n, 256, 0, s>>>(x, split, gate.cols);
    LaunchSplit<true>(outputs, split, n, gate.cols, s);
    return;
  }
  if (n == 1 && gate.rows == up.rows && LaunchMultiGEMV<true>(outputs, x, s))
    return;
  Dense(gate, x, out, n, s, workspace);
  Dense(up, x, up_scratch, n, s, workspace);
  LaunchBatchedSwiGLUActivation(out, up_scratch, out, nullptr,
                                std::size_t(n) * gate.rows, s);
}
void ProjectFfn(const Tensor& gate, const Tensor& up, const Tensor& down,
                const float* x, float* hidden, float* up_scratch, float* out,
                int n, hipStream_t s, DenseWorkspace workspace,
                bool split_ready, const std::uint8_t* q8_style) {
  const Output first[] = {{&gate, hidden}, {&up, nullptr}};
  if (workspace.row_max && SharesSplit(first, n, workspace) &&
      gate.rows == up.rows && SplitPrompt(down, n, workspace) &&
      down.cols == gate.rows) {
    auto split = SplitActivations::In(workspace.quantized, n, gate.cols);
    if (!split_ready)
      SplitRows<<<n, 256, 0, s>>>(x, split, gate.cols);
    split.row_max = workspace.row_max;
    (void)hipMemsetAsync(workspace.row_max, 0, std::size_t(n) * 4, s);
    LaunchSplit<true>(first, split, n, gate.cols, s);
    // Rounding can raise a block maximum by an ulp; the split exponent from
    // row_max then puts it at 2^15, still inside FP16.
    QuantizeQ8Rows(hidden, n, int(gate.rows), q8_style, s);
    SplitActivations raw{};
    raw.raw = hidden;
    raw.row_max = workspace.row_max;
    const Output second[] = {{&down, out}};
    LaunchSplit<false, true>(second, raw, n, down.cols, s, workspace);
    return;
  }
  ProjectSwiGLU(gate, up, x, hidden, up_scratch, n, s, workspace, split_ready);
  QuantizeQ8Rows(hidden, n, int(gate.rows), q8_style, s);
  Dense(down, hidden, out, n, s, workspace);
}
void Dense(const Tensor& w, const float* x, float* out, int n, hipStream_t s,
           DenseWorkspace workspace) {
  if (SplitPrompt(w, n, workspace)) {
    const Output output{&w, out};
    Project({&output, 1}, x, n, s, workspace);
    return;
  }
  if (w.type == core::GgmlType::kF16)
    F16Dense<<<dim3((w.rows + 3) / 4, n), 128, 0, s>>>(w, x, out, n);
  else if (n == 1)
    LaunchGEMV(w.data, w.type, x, out, w.rows, w.cols, s);
  else if (gufo::quant::QuantizedBlockElements(w.type))
    LaunchBatchedQuantGEMMFp32(w.type, w.data, x, out, n, w.rows, w.cols, s);
  else
    for (int i = 0; i < n; ++i)
      LaunchGEMV(w.data, w.type, x + std::size_t(i) * w.cols,
                 out + std::size_t(i) * w.rows, w.rows, w.cols, s);
}
void RopeFrequencies(float* out, int d, float theta, hipStream_t s) {
  Frequencies<<<1, d / 2, 0, s>>>(out, d, theta);
}
void Rope(float* x, const float* frequencies, const float* f, int n, int h,
          int d, int p, hipStream_t s) {
  const int threads = d / 2 * std::max(1, 256 / (d / 2)),
            rows = threads / (d / 2);
  Rotary<<<(n * h + rows * kRopeRows - 1) / (rows * kRopeRows), threads, 0,
           s>>>(x, frequencies, f, n, h, d, p);
}
constexpr int kMinPromptSpan = 2048, kMaxPromptSplits = 8;
int PromptSplits(int keys, int& span) {
  span = std::max(kMinPromptSpan,
                  (keys + kMaxPromptSplits - 1) / kMaxPromptSplits);
  return (keys + span - 1) / span;
}
std::size_t AttentionScratchBytes(int heads, int dim, int context, int rows) {
  int span;
  const int prompt = PromptSplits(context, span);
  const std::size_t decode =
      std::min((context + kDecodeKeys - 1) / kDecodeKeys, kMaxDecodeSplits);
  return std::max(decode, std::size_t(prompt > 1 ? prompt * rows : 0)) * heads *
         (dim + 2) * sizeof(float);
}
void Attention(const float* q, const Half* k, const Half* v, const float* g,
               const Half* ck, const Half* cv, float* out, int n, int h, int kh,
               int d, int p, int cap, int win, hipStream_t s, float* scratch) {
  const int group = h / kh;
  if (d != 128 || !scratch || h % kh || group < 2 || 8 % group)
    throw std::invalid_argument("unsupported attention shape");
  if (n == 1) {
    const int first = win > 0 ? std::max(0, p + 1 - win) : 0;
    const int tiles = (p + 1 - first + kDecodeKeys - 1) / kDecodeKeys;
    // 64 spans keep short histories wide; past 64K keys more spans pay.
    const int most = tiles > 1024 ? kMaxDecodeSplits : 64;
    const int span = (tiles + most - 1) / most * kDecodeKeys;
    const int splits = (p + 1 - first + span - 1) / span;
    DecodeAttn<128><<<dim3(kh, splits), 256, 0, s>>>(
        q, k, v, g, ck, cv, out, scratch, h, kh, p, cap, win, span);
    if (splits > 1)
      DecodeCombine<128><<<h, 128, 0, s>>>(scratch, g, out, h, splits);
    return;
  }
  int span;
  const int splits = win ? 1 : PromptSplits(p + n, span);
  if (splits == 1)
    span = p + n;
  const dim3 grid((n + 128 / group - 1) / (128 / group), splits, kh);
  const auto launch = [&](auto kernel) {
    kernel<<<grid, 256, 0, s>>>(q, k, v, g, ck, cv, out, scratch, n, h, kh, p,
                                cap, win, span);
  };
  if (group == 2)
    launch(WmmaAttn<128, 2>);
  else if (group == 4)
    launch(WmmaAttn<128, 4>);
  else
    launch(WmmaAttn<128, 8>);
  if (splits > 1)
    PromptCombine<128><<<n * h, 128, 0, s>>>(scratch, g, out, n * h, splits);
}
void PackKV(const float* k, const float* v, Half* k16, Half* v16,
            std::size_t count, hipStream_t s) {
  if (count)
    PackRows<<<(count + 255) / 256, 256, 0, s>>>(k, v, k16, v16, count);
}
void PromptHeads(float* q, float* k, const float* v, const float* q_norm,
                 const float* k_norm, const float* frequencies,
                 const float* factors, Half* k16, Half* v16, int n, int heads,
                 int kv_heads, int d, int p, float eps, hipStream_t s) {
  if (d != 128)
    throw std::invalid_argument("prompt heads need dimension 128");
  DecodeHeadsKernel<128><<<dim3(heads + kv_heads, n), 64, 0, s>>>(
      q, k, v, q_norm, k_norm, frequencies, factors, k16, v16, heads, kv_heads,
      p, 0, eps);
}
void PromptHeads(float* q, float* k, const float* v, const float* q_norm,
                 const float* k_norm, const float* frequencies,
                 const std::uint32_t* positions, Half* k16, Half* v16, int n,
                 int heads, int kv_heads, int d, float eps, hipStream_t s) {
  if (d != 128)
    throw std::invalid_argument("prompt heads need dimension 128");
  DecodeHeadsKernel<128><<<dim3(heads + kv_heads, n), 64, 0, s>>>(
      q, k, v, q_norm, k_norm, frequencies, nullptr, k16, v16, heads, kv_heads,
      0, 0, eps, positions);
}
void GatherRows(const float* x, const std::uint32_t* rows, float* out,
                int count, int width, hipStream_t s) {
  if (count > 0)
    GatherRowsKernel<<<dim3((width + 255) / 256, count), 256, 0, s>>>(
        x, rows, out, width);
}
void QuantizeQ8Rows(float* x, int n, int K, const std::uint8_t* style,
                    hipStream_t s) {
  if (K % 32)
    throw std::invalid_argument("q8 rounding needs a width divisible by 32");
  if (n > 0 && style)
    QuantizeQ8RowsKernel<<<dim3((K + 255) / 256, n), 256, 0, s>>>(x, K, style);
}
}  // namespace qwen3_embedding::gpu
