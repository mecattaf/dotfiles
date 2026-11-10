// The kernels the forward pass uses, at Qwen3-Embedding-8B's shapes, against
// FP64 host references. The projection and attention references follow the
// LFM3 extension's tests/ops_test.cpp (gufo-org/lfm3-gufo-extension 23efc07,
// MIT, gufo contributors). Large shapes check sampled rows only.
//
// Needs a HIP device; exits 77 (skipped) without one.

#include <hip/hip_runtime.h>

#include <algorithm>
#include <bit>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <gufo/ext/experimental/ggml_dequant.hpp>
#include <iostream>
#include <random>
#include <stdexcept>
#include <string>
#include <vector>

#include "src/hip/ops.hpp"

namespace g = qwen3_embedding::gpu;
using qwen3_embedding::Tensor;

namespace {

int failures = 0;

void Check(hipError_t e) {
  if (e != hipSuccess) {
    throw std::runtime_error(hipGetErrorString(e));
  }
}

template<typename T = float>
struct Buffer {
  T* p{};
  std::size_t n{};
  explicit Buffer(std::size_t count) : n(count) {
    Check(hipMalloc(&p, std::max<std::size_t>(count, 1) * sizeof(T)));
    Check(hipMemset(p, 0, std::max<std::size_t>(count, 1) * sizeof(T)));
  }
  explicit Buffer(const std::vector<T>& x) : Buffer(x.size()) {
    Check(hipMemcpy(p, x.data(), x.size() * sizeof(T), hipMemcpyHostToDevice));
  }
  Buffer(const Buffer&) = delete;
  Buffer& operator=(const Buffer&) = delete;
  ~Buffer() { (void)hipFree(p); }
  std::vector<T> Read() const {
    std::vector<T> x(n);
    Check(hipMemcpy(x.data(), p, n * sizeof(T), hipMemcpyDeviceToHost));
    return x;
  }
};

std::vector<float> Data(std::size_t n, float scale, unsigned seed) {
  std::vector<float> x(n);
  for (std::size_t i = 0; i < n; ++i) {
    x[i] = scale * std::sin(float(i) * 0.73F + float(seed) * 1.3F);
  }
  return x;
}

void Report(const std::string& what, double worst, double limit) {
  const bool ok = std::isfinite(worst) && worst <= limit;
  std::cout << (ok ? "ok   " : "FAIL ") << what << ": worst " << worst
            << " (limit " << limit << ")\n";
  if (!ok) {
    ++failures;
  }
}

/// Synthetic Q8_0 weights [M][K] with the scale range of the real model.
std::vector<gufo::quant::block_q8_0> Q8Weights(int M, int K, unsigned seed) {
  std::vector<gufo::quant::block_q8_0> w(std::size_t(M) * K / 32);
  std::mt19937 rng(seed);
  for (auto& block : w) {
    block.d = static_cast<std::uint16_t>(0x1c00 + rng() % 0x0800);
    for (auto& q : block.qs) {
      q = static_cast<std::int8_t>(int(rng() % 255) - 127);
    }
  }
  return w;
}

struct DeviceQ8 {
  Buffer<std::uint8_t> bytes;
  Tensor tensor;
  DeviceQ8(const std::vector<gufo::quant::block_q8_0>& w, int M, int K)
      : bytes(w.size() * sizeof(w[0])) {
    Check(hipMemcpy(bytes.p, w.data(), bytes.n, hipMemcpyHostToDevice));
    tensor = Tensor{bytes.p, gufo::core::GgmlType::kQ8_0, std::uint32_t(K),
                    std::uint32_t(M), bytes.n};
  }
};

/// Rows of out = W x, checked on every `step`-th weight row, with an error
/// bound relative to sum |w x| of each product.
double ProjectionError(const std::vector<gufo::quant::block_q8_0>& w,
                       const std::vector<float>& x, const std::vector<float>& y,
                       int n, int M, int K, int step) {
  double worst = 0;
  for (int t = 0; t < n; ++t) {
    for (int m = 0; m < M; m += step) {
      double sum = 0, magnitude = 0;
      for (int b = 0; b < K / 32; ++b) {
        const auto& block = w[std::size_t(m) * (K / 32) + b];
        const double d = gufo::quant::Fp16ToFloat(block.d);
        for (int j = 0; j < 32; ++j) {
          const double term = d * block.qs[j] * x[std::size_t(t) * K + b * 32 + j];
          sum += term;
          magnitude += std::abs(term);
        }
      }
      const double error =
          std::abs(y[std::size_t(t) * M + m] - sum) / (magnitude + 1e-30);
      worst = std::max(worst, error);
    }
  }
  return worst;
}

void Projection(int n, int M, int K, int step) {
  const auto w = Q8Weights(M, K, unsigned(M + K));
  const auto x = Data(std::size_t(n) * K, 0.9F, unsigned(n));
  DeviceQ8 dw(w, M, K);
  Buffer<float> dx(x), out(std::size_t(n) * M);
  Buffer<std::uint8_t> quant(g::DenseWorkspaceBytes(n, K));
  Buffer<float> partial(g::SplitPartialBytes() / 4);
  Buffer<unsigned> tickets(g::kMaxSplitUnits);
  g::Dense(dw.tensor, dx.p, out.p, n, nullptr,
           {quant.p, nullptr, partial.p, tickets.p});
  Check(hipDeviceSynchronize());
  Report("Dense Q8_0 n=" + std::to_string(n) + " M=" + std::to_string(M) +
             " K=" + std::to_string(K) + " (relative to sum|wx|)",
         ProjectionError(w, x, out.Read(), n, M, K, step), 1e-5);
}

// q, k, v projections of one input in one launch, as the forward pass does.
void ProjectQkv(int n) {
  constexpr int K = 4096;
  const int rows[] = {4096, 1024, 1024};
  std::vector<std::vector<gufo::quant::block_q8_0>> w;
  for (int i = 0; i < 3; ++i) {
    w.push_back(Q8Weights(rows[i], K, unsigned(100 + i)));
  }
  DeviceQ8 dq(w[0], rows[0], K), dk(w[1], rows[1], K), dv(w[2], rows[2], K);
  const auto x = Data(std::size_t(n) * K, 0.5F, 7);
  Buffer<float> dx(x), oq(std::size_t(n) * rows[0]), ok(std::size_t(n) * rows[1]),
      ov(std::size_t(n) * rows[2]);
  Buffer<std::uint8_t> quant(g::DenseWorkspaceBytes(n, K));
  Buffer<float> partial(g::SplitPartialBytes() / 4);
  Buffer<unsigned> tickets(g::kMaxSplitUnits);
  const g::Output outputs[] = {{&dq.tensor, oq.p}, {&dk.tensor, ok.p},
                               {&dv.tensor, ov.p}};
  g::Project(outputs, dx.p, n, nullptr, {quant.p, nullptr, partial.p, tickets.p});
  Check(hipDeviceSynchronize());
  double worst = 0;
  const Buffer<float>* outs[] = {&oq, &ok, &ov};
  for (int i = 0; i < 3; ++i) {
    worst = std::max(worst, ProjectionError(w[i], x, outs[i]->Read(), n,
                                            rows[i], K, 61));
  }
  Report("Project q/k/v n=" + std::to_string(n) + " (relative to sum|wx|)",
         worst, 1e-5);
}

// down(silu(gate x) * up x), the fused FFN.
void Ffn(int n) {
  constexpr int H = 4096, F = 12288;
  const auto wg = Q8Weights(F, H, 11), wu = Q8Weights(F, H, 12),
             wd = Q8Weights(H, F, 13);
  DeviceQ8 dg(wg, F, H), du(wu, F, H), dd(wd, H, F);
  const auto x = Data(std::size_t(n) * H, 0.5F, 3);
  Buffer<float> dx(x), hidden(std::size_t(n) * F), up(std::size_t(n) * F),
      out(std::size_t(n) * H);
  Buffer<std::uint8_t> quant(g::DenseWorkspaceBytes(n, F));
  Buffer<unsigned> row_max(n);
  Buffer<float> partial(g::SplitPartialBytes() / 4);
  Buffer<unsigned> tickets(g::kMaxSplitUnits);
  g::ProjectFfn(dg.tensor, du.tensor, dd.tensor, dx.p, hidden.p, up.p, out.p, n,
                nullptr, {quant.p, row_max.p, partial.p, tickets.p});
  Check(hipDeviceSynchronize());
  const auto h = hidden.Read();
  const auto y = out.Read();
  // The activation: checked on sampled rows against FP64 gate/up.
  double worst_h = 0;
  for (int t = 0; t < n; t += std::max(1, n / 5)) {
    for (int m = 0; m < F; m += 97) {
      double gsum = 0, usum = 0, gmag = 0, umag = 0;
      for (int k = 0; k < H; ++k) {
        const auto& bg = wg[std::size_t(m) * (H / 32) + k / 32];
        const auto& bu = wu[std::size_t(m) * (H / 32) + k / 32];
        const double xv = x[std::size_t(t) * H + k];
        const double tg = gufo::quant::Fp16ToFloat(bg.d) * bg.qs[k % 32] * xv;
        const double tu = gufo::quant::Fp16ToFloat(bu.d) * bu.qs[k % 32] * xv;
        gsum += tg;
        usum += tu;
        gmag += std::abs(tg);
        umag += std::abs(tu);
      }
      const double want = gsum / (1 + std::exp(-gsum)) * usum;
      // d(silu(g) u) is bounded by (|u| + |g u|) times the input errors.
      const double bound =
          (std::abs(usum) * 1.2 * gmag + (std::abs(gsum) + 1) * umag) + 1e-30;
      worst_h = std::max(worst_h, std::abs(h[std::size_t(t) * F + m] - want) / bound);
    }
  }
  Report("ProjectFfn activation n=" + std::to_string(n) + " (relative)", worst_h,
         1e-5);
  // The down projection, from the GPU's own activation.
  Report("ProjectFfn down n=" + std::to_string(n) + " (relative to sum|wx|)",
         ProjectionError(wd, h, y, n, H, F, 41), 1e-5);
}

float Round16(float x) { return float(static_cast<_Float16>(x)); }

// Causal attention at position 0 of one sequence, 32 query heads over 8 KV
// heads, no gate; the cache pointers alias the chunk as the forward pass
// passes them. Checked on `rows` query rows.
void Attention(int n, const std::vector<int>& check_rows) {
  constexpr int H = 32, KH = 8, D = 128;
  const int stride = KH * D;
  auto q = Data(std::size_t(n) * H * D, 0.7F, 1),
       k = Data(std::size_t(n) * stride, 0.5F, 2),
       v = Data(std::size_t(n) * stride, 0.9F, 3);
  for (auto* x : {&k, &v}) {
    for (auto& e : *x) {
      e = Round16(e);
    }
  }
  Buffer<float> dq(q), dk(k), dv(v), out(std::size_t(n) * H * D);
  Buffer<g::Half> k16(k.size()), v16(v.size());
  Buffer<float> scratch(g::AttentionScratchBytes(H, D, n, n) / 4 + 1);
  g::PackKV(dk.p, dv.p, k16.p, v16.p, k.size(), nullptr);
  g::Attention(dq.p, k16.p, v16.p, nullptr, k16.p, v16.p, out.p, n, H, KH, D, 0,
               n, 0, nullptr, scratch.p);
  Check(hipDeviceSynchronize());
  const auto y = out.Read();
  double worst = 0;
  for (const int row : check_rows) {
    if (row >= n) {
      continue;
    }
    for (int h = 0; h < H; ++h) {
      const int kh = h / (H / KH);
      std::vector<double> scores;
      double max = -INFINITY;
      for (int t = 0; t <= row; ++t) {
        double sum = 0;
        for (int d = 0; d < D; ++d) {
          sum += double(q[(std::size_t(row) * H + h) * D + d]) *
                 k[std::size_t(t) * stride + kh * D + d];
        }
        scores.push_back(sum / std::sqrt(double(D)));
        max = std::max(max, scores.back());
      }
      double den = 0;
      for (auto& s : scores) {
        s = std::exp(s - max);
        den += s;
      }
      for (int d = 0; d < D; ++d) {
        double sum = 0;
        for (int t = 0; t <= row; ++t) {
          sum += scores[t] / den * v[std::size_t(t) * stride + kh * D + d];
        }
        worst = std::max(worst,
                         std::abs(y[(std::size_t(row) * H + h) * D + d] - sum));
      }
    }
  }
  Report("Attention n=" + std::to_string(n) + " (absolute)", worst,
         n == 1 ? 2e-6 : 1e-3);
}

void ResidualNorm(int n) {
  constexpr int H = 4096;
  const auto x = Data(std::size_t(n) * H, 3.0F, 5),
             branch = Data(std::size_t(n) * H, 2.0F, 6),
             weight = Data(H, 1.5F, 7);
  Buffer<float> dx(x), db(branch), dw(weight), z(std::size_t(n) * H);
  Tensor norm{dw.p, gufo::core::GgmlType::kF32, H, 1, H * 4};
  if (!g::ResidualNorm(db.p, nullptr, dx.p, &norm, z.p, n, H, 1e-6F, false,
                       nullptr, {})) {
    throw std::runtime_error("ResidualNorm refused H=4096");
  }
  Check(hipDeviceSynchronize());
  const auto gx = dx.Read();
  const auto gz = z.Read();
  double worst_x = 0, worst_z = 0;
  for (int t = 0; t < n; ++t) {
    double squares = 0;
    std::vector<double> sum(H);
    for (int i = 0; i < H; ++i) {
      sum[i] = double(float(x[std::size_t(t) * H + i] + branch[std::size_t(t) * H + i]));
      squares += sum[i] * sum[i];
      worst_x = std::max(worst_x, std::abs(gx[std::size_t(t) * H + i] - sum[i]));
    }
    const double inv = 1 / std::sqrt(squares / H + 1e-6);
    for (int i = 0; i < H; ++i) {
      const double want = sum[i] * inv * weight[i];
      worst_z = std::max(worst_z, std::abs(gz[std::size_t(t) * H + i] - want) /
                                      (std::abs(want) + 1e-3));
    }
  }
  Report("ResidualNorm residual n=" + std::to_string(n), worst_x, 0);
  Report("ResidualNorm norm n=" + std::to_string(n) + " (relative)", worst_z,
         1e-5);
}

void Embed() {
  constexpr int V = 97, H = 4096;
  const auto table = Q8Weights(V, H, 21);
  DeviceQ8 dt(table, V, H);
  const std::vector<std::uint32_t> ids = {0, 5, 96, 5, 42, 1, 77};
  Buffer<std::uint32_t> dids(ids);
  Buffer<float> out(ids.size() * H);
  g::Embed(dt.tensor, dids.p, out.p, int(ids.size()), nullptr);
  Check(hipDeviceSynchronize());
  const auto y = out.Read();
  double worst = 0;
  for (std::size_t r = 0; r < ids.size(); ++r) {
    for (int i = 0; i < H; ++i) {
      const auto& block = table[std::size_t(ids[r]) * (H / 32) + i / 32];
      const float want = gufo::quant::Fp16ToFloat(block.d) * float(block.qs[i % 32]);
      worst = std::max(worst, double(std::abs(y[r * H + i] - want)));
    }
  }
  Report("Embed Q8_0 rows (exact)", worst, 0);
}

// Per-head q/k RMSNorm and NeoX RoPE (theta 1e6) at per-row positions, with
// the K/V rows packed to F16, as for two packed sequences.
void PromptHeads() {
  constexpr int H = 32, KH = 8, D = 128;
  const std::vector<std::uint32_t> pos = {0, 1, 2, 3, 0, 1, 2, 4095, 8191};
  const int n = int(pos.size());
  const auto q = Data(std::size_t(n) * H * D, 2.0F, 31),
             k = Data(std::size_t(n) * KH * D, 3.0F, 32),
             v = Data(std::size_t(n) * KH * D, 1.0F, 33),
             qn = Data(D, 1.5F, 34), kn = Data(D, 0.8F, 35);
  Buffer<float> dq(q), dk(k), dv(v), dqn(qn), dkn(kn), freqs(D / 2);
  Buffer<std::uint32_t> dpos(pos);
  Buffer<g::Half> k16(k.size()), v16(v.size());
  g::RopeFrequencies(freqs.p, D, 1e6F, nullptr);
  g::PromptHeads(dq.p, dk.p, dv.p, dqn.p, dkn.p, freqs.p, dpos.p, k16.p, v16.p,
                 n, H, KH, D, 1e-6F, nullptr);
  Check(hipDeviceSynchronize());
  const auto gq = dq.Read();
  const auto gk16 = k16.Read();
  const auto gv16 = v16.Read();
  double worst_q = 0, worst_k = 0, worst_v = 0;
  const auto expected = [&](const std::vector<float>& x, const std::vector<float>& w,
                            std::size_t base, int row, int i) {
    double squares = 0;
    for (int d = 0; d < D; ++d) {
      squares += double(x[base + d]) * x[base + d];
    }
    const double inv = 1 / std::sqrt(squares / D + 1e-6);
    const int pair = i % (D / 2);
    const double a = x[base + pair] * inv * w[pair],
                 b = x[base + pair + D / 2] * inv * w[pair + D / 2];
    const double angle = double(pos[row]) * std::pow(1e6, -2.0 * pair / D);
    return i < D / 2 ? a * std::cos(angle) - b * std::sin(angle)
                     : b * std::cos(angle) + a * std::sin(angle);
  };
  for (int row = 0; row < n; ++row) {
    for (int h = 0; h < H; ++h) {
      const std::size_t base = (std::size_t(row) * H + h) * D;
      for (int i = 0; i < D; ++i) {
        worst_q = std::max(worst_q, std::abs(gq[base + i] - expected(q, qn, base, row, i)));
      }
    }
    for (int h = 0; h < KH; ++h) {
      const std::size_t base = (std::size_t(row) * KH + h) * D;
      for (int i = 0; i < D; ++i) {
        const float got_k = float(std::bit_cast<_Float16>(gk16[base + i]));
        const float got_v = float(std::bit_cast<_Float16>(gv16[base + i]));
        const double want_k = expected(k, kn, base, row, i);
        worst_k = std::max(worst_k, std::abs(got_k - want_k));
        worst_v = std::max(worst_v, double(std::abs(got_v - Round16(v[base + i]))));
      }
    }
  }
  // Angles reach 8191 radians: FP32 frequencies and sincosf bound the error.
  Report("PromptHeads q (absolute, positions to 8191)", worst_q, 5e-3);
  Report("PromptHeads k16 (absolute, F16, positions to 8191)", worst_k, 5e-3);
  Report("PromptHeads v16 (exact F16 rounding)", worst_v, 0);
}

// llama.cpp's q8_1 rounding of activations, both styles, bit for bit
// against the same float expressions on the host.
void QuantizeQ8() {
  constexpr int K = 4096;
  const int n = 4;
  auto x = Data(std::size_t(n) * K, 5.0F, 41);
  for (int i = 0; i < 32; ++i) {
    x[64 + i] = 0.0F;  // an all-zero block
  }
  const std::vector<std::uint8_t> style = {g::kQ8Mmq, g::kQ8Mmvq, g::kQ8None,
                                           g::kQ8Mmq};
  Buffer<float> dx(x);
  Buffer<std::uint8_t> ds(style);
  g::QuantizeQ8Rows(dx.p, n, K, ds.p, nullptr);
  Check(hipDeviceSynchronize());
  const auto y = dx.Read();
  std::size_t mismatches = 0;
  for (int t = 0; t < n; ++t) {
    for (int b = 0; b < K / 32; ++b) {
      const float* block = x.data() + std::size_t(t) * K + b * 32;
      float amax = 0;
      for (int j = 0; j < 32; ++j) {
        amax = std::max(amax, std::abs(block[j]));
      }
      for (int j = 0; j < 32; ++j) {
        float want = block[j];
        if (style[t] != g::kQ8None) {
          want = 0.0F;
          if (amax > 0) {
            if (style[t] == g::kQ8Mmq) {
              const float d_inv = 127.0F / amax;
              want = std::round(block[j] * d_inv) * (1.0F / d_inv);
            } else {
              const float d = amax / 127.0F;
              want = std::round(block[j] / d) * float(static_cast<_Float16>(d));
            }
          }
        }
        const float got = y[std::size_t(t) * K + b * 32 + j];
        if (std::memcmp(&got, &want, 4) != 0) {
          ++mismatches;
        }
      }
    }
  }
  Report("QuantizeQ8Rows bit mismatches", double(mismatches), 0);
}

void Gather() {
  constexpr int W = 4096;
  const auto x = Data(std::size_t(10) * W, 1.0F, 51);
  const std::vector<std::uint32_t> rows = {9, 0, 4};
  Buffer<float> dx(x), out(rows.size() * W);
  Buffer<std::uint32_t> dr(rows);
  g::GatherRows(dx.p, dr.p, out.p, int(rows.size()), W, nullptr);
  Check(hipDeviceSynchronize());
  const auto y = out.Read();
  double worst = 0;
  for (std::size_t r = 0; r < rows.size(); ++r) {
    for (int i = 0; i < W; ++i) {
      worst = std::max(worst, double(std::abs(y[r * W + i] - x[rows[r] * W + i])));
    }
  }
  Report("GatherRows (exact)", worst, 0);
}

}  // namespace

int main() {
  int devices = 0;
  if (hipGetDeviceCount(&devices) != hipSuccess || devices == 0) {
    std::cout << "ops_hip_test: no HIP device; skipped\n";
    return 77;
  }
  hipDeviceProp_t props{};
  Check(hipGetDeviceProperties(&props, 0));
  std::cout << "ops_hip_test on " << props.gcnArchName << "\n";
  try {
    Embed();
    Gather();
    QuantizeQ8();
    ResidualNorm(1);
    ResidualNorm(33);
    PromptHeads();
    for (const int n : {1, 7, 32, 64, 512}) {
      Projection(n, 1024, 4096, n >= 512 ? 7 : 1);
      Projection(n, 4096, 4096, n >= 64 ? 31 : 3);
      Projection(n, 4096, 12288, n >= 64 ? 61 : 7);
    }
    for (const int n : {1, 31, 64, 300}) {
      ProjectQkv(n);
    }
    for (const int n : {1, 7, 32, 100}) {
      Ffn(n);
    }
    Attention(1, {0});
    Attention(5, {0, 1, 2, 3, 4});
    Attention(64, {0, 15, 16, 31, 63});
    Attention(300, {0, 127, 128, 299});
    Attention(2100, {0, 2047, 2048, 2099});
  } catch (const std::exception& failure) {
    std::cout << "FAIL ops_hip_test: " << failure.what() << "\n";
    return 1;
  }
  std::cout << (failures == 0 ? "ops_hip_test: all checks passed\n"
                              : "ops_hip_test: " + std::to_string(failures) +
                                    " checks failed\n");
  return failures == 0 ? 0 : 1;
}
