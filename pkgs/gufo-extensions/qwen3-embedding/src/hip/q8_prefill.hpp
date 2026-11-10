// From the LFM3 Gufo extension (gufo-org/lfm3-gufo-extension 23efc07,
// hip/q8_prefill.hpp, MIT, gufo contributors), namespace renamed.
#ifndef QWEN3_EMBEDDING_HIP_Q8_PREFILL_HPP_
#define QWEN3_EMBEDDING_HIP_Q8_PREFILL_HPP_
#include <hip/hip_fp16.h>
#include <hip/hip_runtime.h>

#include <cstddef>
#include <cstdint>
namespace qwen3_embedding::gpu {
// Prompt activations are split into FP16 high parts and FP16 remainders,
// [token][K] each, after scaling every row by a power of two so its maximum
// lies in [2^14, 2^15). The pair keeps about 22 significant bits of every
// element, not only of the row maximum. Row scales follow both planes.
inline std::size_t SplitActivationBytes(std::size_t tokens, std::size_t K) {
  return tokens * K * 2 * sizeof(__half) + tokens * sizeof(float);
}
// With raw, a projection reads FP32 rows and splits them while staging, with
// the exponent from row_max (the bits of each row's maximum magnitude).
struct SplitActivations {
  __half *high, *low;
  float* scale;
  const float* raw = nullptr;
  unsigned* row_max = nullptr;
  static SplitActivations In(void* base, std::size_t tokens, std::size_t K) {
    auto* half = static_cast<__half*>(base);
    return {half, half + tokens * K,
            reinterpret_cast<float*>(half + 2 * tokens * K), nullptr, nullptr};
  }
};
__device__ __forceinline__ int SplitExponent(float maximum) {
  return maximum > 0 ? 14 - ilogbf(maximum) : 0;
}
__global__ void SplitRows(const float* __restrict__ x, SplitActivations out,
                          int K) {
  const int row = blockIdx.x, tid = threadIdx.x;
  const float* src = x + std::size_t(row) * K;
  float maximum = 0;
  for (int k = tid; k < K; k += 256)
    maximum = fmaxf(maximum, fabsf(src[k]));
  for (int d = 16; d; d /= 2)
    maximum = fmaxf(maximum, __shfl_xor(maximum, d, 32));
  __shared__ float maxima[8];
  if (!(tid % 32))
    maxima[tid / 32] = maximum;
  __syncthreads();
  maximum = 0;
  for (float v : maxima)
    maximum = fmaxf(maximum, v);
  const int e = SplitExponent(maximum);
  if (!tid)
    out.scale[row] = ldexpf(1.0F, -e);
  for (int k = tid; k < K; k += 256) {
    const float v = ldexpf(src[k], e);
    const __half h = __float2half_rn(v);
    out.high[std::size_t(row) * K + k] = h;
    out.low[std::size_t(row) * K + k] = __float2half_rn(v - __half2float(h));
  }
}
namespace detail {
using v16h = __attribute__((__vector_size__(16 * sizeof(_Float16)))) _Float16;
using v8f = __attribute__((__vector_size__(8 * sizeof(float)))) float;
__device__ __forceinline__ v8f Wmma(v16h a, v16h b, v8f c) {
  return __builtin_amdgcn_wmma_f32_16x16x16_f16_w32(a, b, c);
}
// Exact signed Q8 codes as FP16: 0x64XX is 1024 + XX, with XX = q + 128.
__device__ __forceinline__ void Codes(std::uint32_t codes, __half2& lo,
                                      __half2& hi) {
  const __half2 magic = __floats2half2_rn(-1152.0F, -1152.0F);
  codes ^= 0x80808080U;
  const std::uint32_t p0 =
      __builtin_amdgcn_perm(codes, 0x64646464U, 0x01050004U);
  const std::uint32_t p1 =
      __builtin_amdgcn_perm(codes, 0x64646464U, 0x03070206U);
  lo = __hadd2(__builtin_bit_cast(__half2, p0), magic);
  hi = __hadd2(__builtin_bit_cast(__half2, p1), magic);
}
}  // namespace detail
// Up to four projections of the same split input share one launch; each
// owns a contiguous range of row blocks.
struct Projection {
  const void* weight;
  float* out;
  int rows;
};
struct Projections {
  static constexpr int kMax = 4;
  Projection job[kMax];
  int first_block[kMax];
  int count;
};
// Tiles are numbered row block major over token_blocks token blocks. Tiles
// from split_from on, the last partial wave of resident blocks, divide their
// K blocks into parts launches; each part stores its FP32 accumulators, and
// the last part to finish adds them in part order and runs the epilogue.
struct SplitK {
  int token_blocks, split_from, parts = 1;
  float* partial = nullptr;
  unsigned* tickets = nullptr;
};
// Q8_0 weights x split activations. For each K32 block the low and high
// products chain into one FP32 WMMA accumulator, which is then scaled by the
// block's weight scale; row scales apply after the K reduction. Block = BM
// rows x BN tokens, waves = WM row groups x WN token groups. Global loads for
// the next K block are issued before the current block's matrix work, and two
// LDS stages leave one barrier per K block. With kSwiGLU, job 0 is the FFN
// gate and job 1 its up projection: a block holds BM / 2 rows of each and
// writes silu(gate) * up to job 0's output.
template<int BM, int BN, int WM, int WN, bool kSwiGLU = false,
         bool kRaw = false>
__launch_bounds__(256) __global__
    void SplitQ8Gemm(Projections jobs, SplitActivations x, int tokens, int K,
                     SplitK sk) {
  using detail::v16h;
  using detail::v8f;
  static_assert(WM * WN == 8 && (!kSwiGLU || WM % 2 == 0));
  constexpr int RM = BM / 16 / WM, RN = BN / 16 / WN;
  constexpr int kAPer = (BM + 255) / 256, kBPer = (2 * BN + 255) / 256;
  constexpr int kTileRows = kSwiGLU ? BM / 2 : BM;
  // One K block of a row or token is four 16-byte chunks; neighbouring rows
  // permute them so fragment reads cover all bank groups.
  __shared__ __attribute__((aligned(16))) uint4 s_a[2][BM][4];
  __shared__ __attribute__((aligned(16))) uint4 s_b[2][2][BN][4];
  __shared__ float s_d[2][BM];
  const auto swizzle = [](int row, int c) { return c ^ ((row >> 1) & 3); };
  const int blocks = K / 32, tid = threadIdx.x, lane = tid & 31,
            wave = tid >> 5, sub = lane & 15, half = lane >> 4;
  const int wr = wave / WN, wt = wave % WN;
  int tile = blockIdx.x, part = 0, parts = 1;
  if (tile >= sk.split_from) {
    const int u = tile - sk.split_from;
    tile = sk.split_from + u / sk.parts;
    part = u % sk.parts;
    parts = sk.parts;
  }
  const int row_tile = tile / sk.token_blocks;
  int job = 0;
  for (int j = 1; j < jobs.count; ++j)
    if (row_tile >= jobs.first_block[j])
      job = j;
  const int M = jobs.job[job].rows;
  const int r_block = (row_tile - jobs.first_block[job]) * kTileRows,
            t_block = tile % sk.token_blocks * BN;
  const int kb_begin = part * blocks / parts,
            kb_end = (part + 1) * blocks / parts;
  const std::uint8_t* a_ptr[kAPer];
  bool a_live[kAPer];
#pragma unroll
  for (int p = 0; p < kAPer; ++p) {
    const int idx = p * 256 + tid;
    const int source = kSwiGLU ? idx / kTileRows : job;
    const int r = r_block + idx % kTileRows;
    a_live[p] = idx < BM && r < M;
    a_ptr[p] = static_cast<const std::uint8_t*>(jobs.job[source].weight) +
               std::size_t(a_live[p] ? r : M - 1) * blocks * 34;
  }
  // Each B unit is one token's high or low K block, or with kRaw one half
  // of its FP32 K block.
  const void* b_ptr[kBPer];
  [[maybe_unused]] int b_exponent[kBPer];
#pragma unroll
  for (int p = 0; p < kBPer; ++p) {
    const int idx = p * 256 + tid, t = t_block + idx % BN;
    const bool live = idx < 2 * BN && t < tokens;
    if constexpr (kRaw) {
      b_ptr[p] = live ? x.raw + std::size_t(t) * K + idx / BN * 16 : nullptr;
      b_exponent[p] = live ? SplitExponent(__uint_as_float(x.row_max[t])) : 0;
    } else
      b_ptr[p] =
          live ? (idx / BN ? x.low : x.high) + std::size_t(t) * K : nullptr;
  }
  uint4 a_codes[kAPer][2];
  std::uint16_t a_d[kAPer];
  uint4 b_data[kBPer][4];
  const auto fetch = [&](int kb) {
#pragma unroll
    for (int p = 0; p < kAPer; ++p) {
      const std::uint8_t* block = a_ptr[p] + std::size_t(kb) * 34;
      a_d[p] = a_live[p] ? *reinterpret_cast<const std::uint16_t*>(block) : 0;
      __builtin_memcpy(&a_codes[p][0], block + 2, 16);
      __builtin_memcpy(&a_codes[p][1], block + 18, 16);
    }
#pragma unroll
    for (int p = 0; p < kBPer; ++p) {
      if (b_ptr[p]) {
        const auto* src = reinterpret_cast<const uint4*>(
            static_cast<const std::uint8_t*>(b_ptr[p]) +
            std::size_t(kb) * 32 * (kRaw ? sizeof(float) : sizeof(__half)));
#pragma unroll
        for (int c = 0; c < 4; ++c)
          b_data[p][c] = src[c];
      } else {
#pragma unroll
        for (int c = 0; c < 4; ++c)
          b_data[p][c] = make_uint4(0, 0, 0, 0);
      }
    }
  };
  const auto commit = [&](int stage) {
#pragma unroll
    for (int p = 0; p < kAPer; ++p) {
      const int row = p * 256 + tid;
      if (row >= BM)
        break;
      const std::uint32_t words[8] = {
          a_codes[p][0].x, a_codes[p][0].y, a_codes[p][0].z, a_codes[p][0].w,
          a_codes[p][1].x, a_codes[p][1].y, a_codes[p][1].z, a_codes[p][1].w};
      __half2 h[16];
#pragma unroll
      for (int i = 0; i < 8; ++i)
        detail::Codes(words[i], h[2 * i], h[2 * i + 1]);
#pragma unroll
      for (int c = 0; c < 4; ++c) {
        uint4 v;
        __builtin_memcpy(&v, &h[4 * c], 16);
        s_a[stage][row][swizzle(row, c)] = v;
      }
      s_d[stage][row] = __half2float(__builtin_bit_cast(__half, a_d[p]));
    }
#pragma unroll
    for (int p = 0; p < kBPer; ++p) {
      const int idx = p * 256 + tid;
      if (idx >= 2 * BN)
        break;
      const int t = idx % BN;
      if constexpr (kRaw) {
        // SplitRows' rounding: scale, round high, round the remainder.
        float v[16];
        __builtin_memcpy(v, b_data[p], sizeof(v));
        __half high[16], low[16];
#pragma unroll
        for (int e = 0; e < 16; ++e) {
          const float scaled = ldexpf(v[e], b_exponent[p]);
          high[e] = __float2half_rn(scaled);
          low[e] = __float2half_rn(scaled - __half2float(high[e]));
        }
        const int k_half = idx / BN;
#pragma unroll
        for (int c = 0; c < 2; ++c) {
          uint4 h, l;
          __builtin_memcpy(&h, high + 8 * c, 16);
          __builtin_memcpy(&l, low + 8 * c, 16);
          s_b[stage][0][t][swizzle(t, 2 * k_half + c)] = h;
          s_b[stage][1][t][swizzle(t, 2 * k_half + c)] = l;
        }
      } else {
        const int plane = idx / BN;
#pragma unroll
        for (int c = 0; c < 4; ++c)
          s_b[stage][plane][t][swizzle(t, c)] = b_data[p][c];
      }
    }
  };
  v8f acc[RM][RN] = {};
  const v8f zero{};
  fetch(kb_begin);
  commit(0);
  __syncthreads();
  for (int kb = kb_begin; kb < kb_end; ++kb) {
    const int stage = (kb - kb_begin) & 1;
    if (kb + 1 < kb_end)
      fetch(kb + 1);
    // Keeps the next block's loads ahead of the matrix work.
    __builtin_amdgcn_sched_barrier(0);
    v16h a0[RM], a1[RM];
    float d[RM][8];
#pragma unroll
    for (int i = 0; i < RM; ++i) {
      const int row = (wr * RM + i) * 16 + sub;
      uint4 c[4];
#pragma unroll
      for (int q = 0; q < 4; ++q)
        c[q] = s_a[stage][row][swizzle(row, q)];
      __builtin_memcpy(&a0[i], &c[0], 32);
      __builtin_memcpy(&a1[i], &c[2], 32);
#pragma unroll
      for (int l = 0; l < 8; ++l)
        d[i][l] = s_d[stage][(wr * RM + i) * 16 + 2 * l + half];
    }
#pragma unroll
    for (int j = 0; j < RN; ++j) {
      const int t = (wt * RN + j) * 16 + sub;
      v16h b[2][2];
#pragma unroll
      for (int plane = 0; plane < 2; ++plane) {
        uint4 c[4];
#pragma unroll
        for (int q = 0; q < 4; ++q)
          c[q] = s_b[stage][plane][t][swizzle(t, q)];
        __builtin_memcpy(&b[plane][0], &c[0], 32);
        __builtin_memcpy(&b[plane][1], &c[2], 32);
      }
#pragma unroll
      for (int i = 0; i < RM; ++i) {
        v8f c = detail::Wmma(a0[i], b[1][0], zero);
        c = detail::Wmma(a1[i], b[1][1], c);
        c = detail::Wmma(a0[i], b[0][0], c);
        c = detail::Wmma(a1[i], b[0][1], c);
#pragma unroll
        for (int l = 0; l < 8; ++l)
          acc[i][j][l] = fmaf(d[i][l], c[l], acc[i][j][l]);
      }
    }
    if (kb + 1 < kb_end)
      commit(stage ^ 1);
    __syncthreads();
  }
  if (parts > 1) {
    constexpr int kValues = RM * RN * 8;
    const int first = (tile - sk.split_from) * parts;
    float* mine = sk.partial + std::size_t(first + part) * kValues * 256;
#pragma unroll
    for (int i = 0; i < RM; ++i)
#pragma unroll
      for (int j = 0; j < RN; ++j)
#pragma unroll
        for (int l = 0; l < 8; ++l)
          mine[((i * RN + j) * 8 + l) * 256 + tid] = acc[i][j][l];
    __threadfence();
    __syncthreads();
    __shared__ bool s_last;
    if (!tid) {
      unsigned* ticket = sk.tickets + (tile - sk.split_from);
      s_last = atomicAdd(ticket, 1U) == unsigned(parts - 1);
      if (s_last)
        *ticket = 0;
    }
    __syncthreads();
    if (!s_last)
      return;
    __threadfence();
    for (int p = 0; p < parts; ++p) {
      const float* src = sk.partial + std::size_t(first + p) * kValues * 256;
#pragma unroll
      for (int i = 0; i < RM; ++i)
#pragma unroll
        for (int j = 0; j < RN; ++j)
#pragma unroll
          for (int l = 0; l < 8; ++l) {
            const float v = p == part
                                ? mine[((i * RN + j) * 8 + l) * 256 + tid]
                                : __builtin_nontemporal_load(
                                      src + ((i * RN + j) * 8 + l) * 256 + tid);
            acc[i][j][l] = p ? acc[i][j][l] + v : v;
          }
    }
  }
  float* y = jobs.job[job].out;
  // Up waves hand their scaled results to the gate waves through LDS.
  [[maybe_unused]] auto* s_up = reinterpret_cast<float (*)[BN]>(&s_a[0][0][0]);
  static_assert(!kSwiGLU || sizeof(float) * kTileRows * BN <= sizeof(s_a));
  if constexpr (kSwiGLU) {
    if (wr >= WM / 2)
#pragma unroll
      for (int j = 0; j < RN; ++j) {
        const int local = (wt * RN + j) * 16 + sub, token = t_block + local;
        float scale = 0;
        if (token < tokens)
          scale =
              kRaw ? ldexpf(1.0F,
                            -SplitExponent(__uint_as_float(x.row_max[token])))
                   : x.scale[token];
        [[maybe_unused]] float token_max = 0;
#pragma unroll
        for (int i = 0; i < RM; ++i)
#pragma unroll
          for (int l = 0; l < 8; ++l)
            s_up[(wr * RM + i) * 16 + 2 * l + half - kTileRows][local] =
                acc[i][j][l] * scale;
      }
    __syncthreads();
    if (wr >= WM / 2)
      return;
  }
  // Lane halves hold alternate rows of a token. Swapping four values gives
  // every lane eight consecutive rows, stored as two 16-byte writes.
  const auto other_half = [](float value) {
    return __builtin_bit_cast(float, __builtin_amdgcn_permlanex16(
                                         __builtin_bit_cast(int, value),
                                         __builtin_bit_cast(int, value),
                                         0x76543210, 0xfedcba98, false, false));
  };
#pragma unroll
  for (int j = 0; j < RN; ++j) {
    const int local = (wt * RN + j) * 16 + sub, token = t_block + local;
    float scale = 0;
    if (token < tokens)
      scale =
          kRaw ? ldexpf(1.0F, -SplitExponent(__uint_as_float(x.row_max[token])))
               : x.scale[token];
    [[maybe_unused]] float token_max = 0;
#pragma unroll
    for (int i = 0; i < RM; ++i) {
      float value[8];
#pragma unroll
      for (int l = 0; l < 8; ++l) {
        const int tile_row = (wr * RM + i) * 16 + 2 * l + half;
        value[l] = acc[i][j][l] * scale;
        if constexpr (kSwiGLU) {
          // The separate SwiGLU kernel's formula.
          const float g = value[l], u = s_up[tile_row][local];
          const float sig_g = 1.0F / (1.0F + expf(-g));
          value[l] = (g * sig_g) * u;
        }
      }
      float received[4], rows[8];
#pragma unroll
      for (int l = 0; l < 4; ++l)
        received[l] = other_half(half ? value[l] : value[4 + l]);
#pragma unroll
      for (int l = 0; l < 4; ++l) {
        rows[2 * l] = half ? received[l] : value[l];
        rows[2 * l + 1] = half ? value[4 + l] : received[l];
      }
      if constexpr (kSwiGLU)
        for (int l = 0; l < 8; ++l)
          token_max = fmaxf(token_max, fabsf(rows[l]));
      const int row = r_block + (wr * RM + i) * 16 + 8 * half;
      if (token >= tokens)
        continue;
      float* dst = y + std::size_t(token) * M + row;
      if (row + 8 <= M && M % 4 == 0) {
        reinterpret_cast<float4*>(dst)[0] =
            make_float4(rows[0], rows[1], rows[2], rows[3]);
        reinterpret_cast<float4*>(dst)[1] =
            make_float4(rows[4], rows[5], rows[6], rows[7]);
      } else {
#pragma unroll
        for (int l = 0; l < 8; ++l)
          if (row + l < M)
            dst[l] = rows[l];
      }
    }
    if constexpr (kSwiGLU) {
      // Row maxima let the down projection split this output while staging.
      token_max = fmaxf(token_max, other_half(token_max));
      if (x.row_max && !half && token < tokens)
        atomicMax(x.row_max + token, __float_as_uint(token_max));
    }
  }
}
// Q8_0 weights x split activations with register-resident weights. Every
// wave owns its weight rows, so only the activations (shared by all waves)
// pass through LDS. Products are transposed (activations as the WMMA A
// operand): lane L then holds weight row L % 16 for alternate tokens, so
// each lane scales by its own row's Q8 scale. As the B operand, element k
// of column n is read from lane n for even k and lane n + 16 for odd k, so
// both lanes of a row decode all 32 codes of each K block. The sums are
// those of SplitQ8Gemm, in its order. Block = kWaves waves x RM row tiles of
// 16 rows, x BN = 16 * RN tokens. With kSwiGLU a wave holds 16 gate rows
// (tile 0) and the same 16 up rows (tile 1) and applies SwiGLU in registers.
template<int RN, bool kSwiGLU = false, bool kRaw = false, int kWaves = 8>
__launch_bounds__(kWaves * 32) __global__
    void RegQ8Gemm(Projections jobs, SplitActivations x, int tokens, int K,
                   SplitK sk) {
  using detail::v16h;
  using detail::v8f;
  constexpr int RM = 2, BN = 16 * RN;
  constexpr int T = kWaves * 32;
  constexpr int kBPer = (2 * BN + T - 1) / T;
  constexpr int kTileRows = kWaves * 16 * (kSwiGLU ? 1 : RM);
  __shared__ __attribute__((aligned(16))) uint4 s_b[2][2][BN][4];
  const auto swizzle = [](int row, int c) { return c ^ ((row >> 1) & 3); };
  const int blocks = K / 32, tid = threadIdx.x, lane = tid & 31,
            wave = tid >> 5, sub = lane & 15, half = lane >> 4;
  int tile = blockIdx.x, part = 0, parts = 1;
  if (tile >= sk.split_from) {
    const int u = tile - sk.split_from;
    tile = sk.split_from + u / sk.parts;
    part = u % sk.parts;
    parts = sk.parts;
  }
  const int row_tile = tile / sk.token_blocks;
  int job = 0;
  for (int j = 1; j < jobs.count; ++j)
    if (row_tile >= jobs.first_block[j])
      job = j;
  const int M = jobs.job[job].rows;
  const int r_block = (row_tile - jobs.first_block[job]) * kTileRows,
            t_block = tile % sk.token_blocks * BN;
  const int kb_begin = part * blocks / parts,
            kb_end = (part + 1) * blocks / parts;
  const bool wave_live = r_block + (kSwiGLU ? wave * 16 : wave * RM * 16) < M;
  // This lane's row of tile i.
  int row[RM];
  const std::uint8_t* w_ptr[RM];
#pragma unroll
  for (int i = 0; i < RM; ++i) {
    row[i] = r_block + (kSwiGLU ? wave * 16 : (wave * RM + i) * 16) + sub;
    const int source = kSwiGLU ? i : job;
    w_ptr[i] = static_cast<const std::uint8_t*>(jobs.job[source].weight) +
               std::size_t(row[i] < M ? row[i] : M - 1) * blocks * 34;
  }
  const void* b_ptr[kBPer];
  [[maybe_unused]] int b_exponent[kBPer];
#pragma unroll
  for (int p = 0; p < kBPer; ++p) {
    const int idx = p * T + tid, t = t_block + idx % BN;
    const bool live = idx < 2 * BN && t < tokens;
    if constexpr (kRaw) {
      b_ptr[p] = live ? x.raw + std::size_t(t) * K + idx / BN * 16 : nullptr;
      b_exponent[p] = live ? SplitExponent(__uint_as_float(x.row_max[t])) : 0;
    } else
      b_ptr[p] =
          live ? (idx / BN ? x.low : x.high) + std::size_t(t) * K : nullptr;
  }
  uint4 w_codes[RM][2];
  std::uint16_t w_d[RM];
  uint4 b_data[kBPer][4];
  const auto fetch_w = [&](int kb) {
#pragma unroll
    for (int i = 0; i < RM; ++i) {
      const std::uint8_t* block = w_ptr[i] + std::size_t(kb) * 34;
      w_d[i] = *reinterpret_cast<const std::uint16_t*>(block);
      __builtin_memcpy(&w_codes[i][0], block + 2, 16);
      __builtin_memcpy(&w_codes[i][1], block + 18, 16);
    }
  };
  const auto fetch_b = [&](int kb) {
#pragma unroll
    for (int p = 0; p < kBPer; ++p) {
      if (b_ptr[p]) {
        const auto* src = reinterpret_cast<const uint4*>(
            static_cast<const std::uint8_t*>(b_ptr[p]) +
            std::size_t(kb) * 32 * (kRaw ? sizeof(float) : sizeof(__half)));
#pragma unroll
        for (int c = 0; c < 4; ++c)
          b_data[p][c] = src[c];
      } else {
#pragma unroll
        for (int c = 0; c < 4; ++c)
          b_data[p][c] = make_uint4(0, 0, 0, 0);
      }
    }
  };
  const auto commit = [&](int stage) {
#pragma unroll
    for (int p = 0; p < kBPer; ++p) {
      const int idx = p * T + tid;
      if (idx >= 2 * BN)
        break;
      const int t = idx % BN;
      if constexpr (kRaw) {
        // SplitRows' rounding: scale, round high, round the remainder.
        float v[16];
        __builtin_memcpy(v, b_data[p], sizeof(v));
        __half high[16], low[16];
#pragma unroll
        for (int e = 0; e < 16; ++e) {
          const float scaled = ldexpf(v[e], b_exponent[p]);
          high[e] = __float2half_rn(scaled);
          low[e] = __float2half_rn(scaled - __half2float(high[e]));
        }
        const int k_half = idx / BN;
#pragma unroll
        for (int c = 0; c < 2; ++c) {
          uint4 h, l;
          __builtin_memcpy(&h, high + 8 * c, 16);
          __builtin_memcpy(&l, low + 8 * c, 16);
          s_b[stage][0][t][swizzle(t, 2 * k_half + c)] = h;
          s_b[stage][1][t][swizzle(t, 2 * k_half + c)] = l;
        }
      } else {
        const int plane = idx / BN;
#pragma unroll
        for (int c = 0; c < 4; ++c)
          s_b[stage][plane][t][swizzle(t, c)] = b_data[p][c];
      }
    }
  };
  v8f acc[RM][RN] = {};
  const v8f zero{};
  fetch_w(kb_begin);
  fetch_b(kb_begin);
  commit(0);
  __syncthreads();
  for (int kb = kb_begin; kb < kb_end; ++kb) {
    const int stage = (kb - kb_begin) & 1;
    // Decode this block's weights before the next block's loads land in
    // the same registers.
    v16h w[RM][2];
    float d[RM];
#pragma unroll
    for (int i = 0; i < RM; ++i) {
#pragma unroll
      for (int h = 0; h < 2; ++h) {
        const std::uint32_t words[4] = {w_codes[i][h].x, w_codes[i][h].y,
                                        w_codes[i][h].z, w_codes[i][h].w};
        __half2 values[8];
#pragma unroll
        for (int q = 0; q < 4; ++q)
          detail::Codes(words[q], values[2 * q], values[2 * q + 1]);
        __builtin_memcpy(&w[i][h], values, 32);
      }
      d[i] = __half2float(__builtin_bit_cast(__half, w_d[i]));
    }
    if (kb + 1 < kb_end) {
      fetch_w(kb + 1);
      fetch_b(kb + 1);
    }
    __builtin_amdgcn_sched_barrier(0);
#pragma unroll
    for (int j = 0; j < RN; ++j) {
      if (!wave_live)
        break;
      const int t = j * 16 + sub;
      v16h b[2][2];
#pragma unroll
      for (int plane = 0; plane < 2; ++plane) {
        uint4 c[4];
#pragma unroll
        for (int q = 0; q < 4; ++q)
          c[q] = s_b[stage][plane][t][swizzle(t, q)];
        __builtin_memcpy(&b[plane][0], &c[0], 32);
        __builtin_memcpy(&b[plane][1], &c[2], 32);
      }
#pragma unroll
      for (int i = 0; i < RM; ++i) {
        v8f c = detail::Wmma(b[1][0], w[i][0], zero);
        c = detail::Wmma(b[1][1], w[i][1], c);
        c = detail::Wmma(b[0][0], w[i][0], c);
        c = detail::Wmma(b[0][1], w[i][1], c);
#pragma unroll
        for (int l = 0; l < 8; ++l)
          acc[i][j][l] = fmaf(d[i], c[l], acc[i][j][l]);
      }
    }
    if (kb + 1 < kb_end)
      commit(stage ^ 1);
    __syncthreads();
  }
  if (parts > 1) {
    constexpr int kValues = RM * RN * 8;
    const int first = (tile - sk.split_from) * parts;
    float* mine = sk.partial + std::size_t(first + part) * kValues * T;
#pragma unroll
    for (int i = 0; i < RM; ++i)
#pragma unroll
      for (int j = 0; j < RN; ++j)
#pragma unroll
        for (int l = 0; l < 8; ++l)
          mine[((i * RN + j) * 8 + l) * T + tid] = acc[i][j][l];
    __threadfence();
    __syncthreads();
    __shared__ bool s_last;
    if (!tid) {
      unsigned* ticket = sk.tickets + (tile - sk.split_from);
      s_last = atomicAdd(ticket, 1U) == unsigned(parts - 1);
      if (s_last)
        *ticket = 0;
    }
    __syncthreads();
    if (!s_last)
      return;
    __threadfence();
    for (int p = 0; p < parts; ++p) {
      const float* src = sk.partial + std::size_t(first + p) * kValues * T;
#pragma unroll
      for (int i = 0; i < RM; ++i)
#pragma unroll
        for (int j = 0; j < RN; ++j)
#pragma unroll
          for (int l = 0; l < 8; ++l) {
            const float v = __builtin_nontemporal_load(
                src + ((i * RN + j) * 8 + l) * T + tid);
            acc[i][j][l] = p ? acc[i][j][l] + v : v;
          }
    }
  }
  float* y = jobs.job[job].out;
#pragma unroll
  for (int j = 0; j < RN; ++j) {
#pragma unroll
    for (int l = 0; l < 8; ++l) {
      const int token = t_block + j * 16 + 2 * l + half;
      float scale = 0;
      if (token < tokens)
        scale = kRaw ? ldexpf(1.0F,
                              -SplitExponent(__uint_as_float(x.row_max[token])))
                     : x.scale[token];
      if constexpr (kSwiGLU) {
        // The separate SwiGLU kernel's formula.
        const float g = acc[0][j][l] * scale, u = acc[1][j][l] * scale;
        const float sig_g = 1.0F / (1.0F + expf(-g));
        const float value = (g * sig_g) * u;
        if (token < tokens && row[0] < M)
          y[std::size_t(token) * M + row[0]] = value;
        // Row maxima let the down projection split this output while
        // staging.
        float m = row[0] < M ? fabsf(value) : 0.0F;
#pragma unroll
        for (int s = 8; s; s /= 2)
          m = fmaxf(m, __shfl_xor(m, s, 16));
        if (x.row_max && !sub && token < tokens)
          atomicMax(x.row_max + token, __float_as_uint(m));
      } else {
#pragma unroll
        for (int i = 0; i < RM; ++i)
          if (token < tokens && row[i] < M)
            y[std::size_t(token) * M + row[i]] = acc[i][j][l] * scale;
      }
    }
  }
}
}  // namespace qwen3_embedding::gpu
#endif
