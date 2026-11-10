// Gate G2 in the repository: every text of tests/fixtures/reference_embeddings.json
// (oracle ids and vectors from llama.cpp b9925, the July "old way") is run
// alone through the forward pass, from the oracle's own token ids, and must
// reach cosine >= 0.999 against the oracle vector, mean >= 0.9995. Also
// checked: the 48 short texts packed into one batch against the same texts
// alone (G3's 0.9999 bound). The HTTP form of these gates is
// tools/parity_check.py.
//
// Arguments (all optional; with none it is the ctest gate):
//   --activations exact,llamacpp-q8   modes to run, one model load (default:
//                                      the runtime's default)
//   --buckets short,medium,long,xlong buckets for G2
//   --save PATH                        write {id, mode, cosine, embedding}
//                                      JSON lines
//
// Needs QWEN3_EMBEDDING_MODEL and a HIP device; exits 77 (skipped) without.

#include <hip/hip_runtime.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <gufo/ext/json.hpp>
#include <iomanip>
#include <iostream>
#include <map>
#include <numeric>
#include <set>
#include <sstream>
#include <string>
#include <vector>

#include "src/hip/encoder_runtime.hpp"
#include "tests/support.hpp"

namespace {

using qwen3_embedding::hip::Activations;
using qwen3_embedding::hip::EncoderRuntime;

constexpr double kG2Min = 0.999, kG2Mean = 0.9995, kG3Min = 0.9999;

struct Text {
  std::string id;
  std::string bucket;
  std::vector<std::uint32_t> ids;
  std::vector<float> embedding;
};

double Cosine(const std::vector<float>& a, const std::vector<float>& b) {
  double dot = 0, na = 0, nb = 0;
  for (std::size_t i = 0; i < a.size() && i < b.size(); ++i) {
    dot += double(a[i]) * b[i];
    na += double(a[i]) * a[i];
    nb += double(b[i]) * b[i];
  }
  return dot / std::sqrt(na * nb);
}

std::vector<std::string> Split(const std::string& text) {
  std::vector<std::string> out;
  std::stringstream stream(text);
  std::string item;
  while (std::getline(stream, item, ',')) {
    if (!item.empty()) {
      out.push_back(item);
    }
  }
  return out;
}

}  // namespace

int main(int argc, char** argv) {
  qwen3_embedding::testing::TestName() = "golden_hip_test";
  std::vector<std::string> modes;
  std::set<std::string> buckets = {"short", "medium", "long", "xlong"};
  std::string save_path;
  for (int i = 1; i + 1 < argc; i += 2) {
    const std::string flag = argv[i], value = argv[i + 1];
    if (flag == "--activations") {
      modes = Split(value);
    } else if (flag == "--buckets") {
      const auto list = Split(value);
      buckets = std::set<std::string>(list.begin(), list.end());
    } else if (flag == "--save") {
      save_path = value;
    } else {
      std::cerr << "unknown argument " << flag << "\n";
      return 2;
    }
  }
  const auto model = qwen3_embedding::testing::ModelPath();
  if (!model) {
    std::cout << "golden_hip_test: QWEN3_EMBEDDING_MODEL not set; skipped\n";
    return 77;
  }
  int devices = 0;
  if (hipGetDeviceCount(&devices) != hipSuccess || devices == 0) {
    std::cout << "golden_hip_test: no HIP device; skipped\n";
    return 77;
  }
  const auto path = qwen3_embedding::testing::FixtureDir() / "reference_embeddings.json";
  const auto text = qwen3_embedding::testing::ReadFile(path);
  if (!text) {
    std::cout << "golden_hip_test: no " << path << "; skipped\n";
    return 77;
  }
  const gufo::json::Value root = gufo::json::parse(*text);
  std::vector<Text> texts;
  for (const auto& item : root.find("texts")->items()) {
    Text entry;
    entry.id = item.member_str("id", "");
    entry.bucket = item.member_str("bucket", "");
    for (const auto& id : item.find("ids")->items()) {
      entry.ids.push_back(static_cast<std::uint32_t>(id.as_size()));
    }
    for (const auto& value : item.find("embedding")->items()) {
      entry.embedding.push_back(static_cast<float>(value.as_double()));
    }
    texts.push_back(std::move(entry));
  }
  std::cout << "golden_hip_test: " << texts.size() << " reference texts from "
            << path << "\n";

  std::string error;
  const auto loaded = std::chrono::steady_clock::now();
  auto encoder = EncoderRuntime::Create(model->string(), &error);
  if (!encoder) {
    std::cout << "FAIL golden_hip_test: " << error << "\n";
    return 1;
  }
  const auto& report = encoder->load_report();
  std::cout << std::fixed << std::setprecision(2) << "loaded in "
            << std::chrono::duration<double>(std::chrono::steady_clock::now() -
                                             loaded)
                   .count()
            << " s (upload " << report.upload_seconds << " s, warm-up "
            << report.warmup_seconds << " s), weights "
            << double(report.weight_bytes) / 1e9 << " GB, scratch "
            << double(report.scratch_bytes) / 1e9 << " GB (attention "
            << double(report.attention_scratch_bytes) / 1e6 << " MB)"
            << (report.managed_fallback ? ", managed fallback" : "") << "\n";
  if (modes.empty()) {
    modes.emplace_back(qwen3_embedding::hip::ToString(encoder->options().activations));
  }
  std::ofstream save;
  if (!save_path.empty()) {
    save.open(save_path);
  }

  bool passed = true;
  for (const auto& mode_name : modes) {
    Activations mode{};
    if (!qwen3_embedding::hip::ParseActivations(mode_name, &mode)) {
      std::cerr << "unknown activations " << mode_name << "\n";
      return 2;
    }
    encoder->set_activations(mode);
    std::cout << std::setprecision(6) << "== activations " << mode_name << "\n";
    // G2: each text alone.
    std::vector<double> cosines;
    std::map<std::string, std::vector<double>> per_bucket;
    std::map<std::string, double> bucket_seconds;
    std::vector<std::pair<double, std::string>> ranked;
    std::map<std::string, std::vector<float>> alone;
    for (const Text& entry : texts) {
      if (!buckets.contains(entry.bucket)) {
        continue;
      }
      std::vector<std::vector<float>> out;
      const auto start = std::chrono::steady_clock::now();
      if (!encoder->RunBatch({&entry.ids}, &out, &error)) {
        std::cout << "FAIL golden_hip_test: " << entry.id << ": " << error << "\n";
        return 1;
      }
      bucket_seconds[entry.bucket] +=
          std::chrono::duration<double>(std::chrono::steady_clock::now() - start)
              .count();
      const double cosine = Cosine(out[0], entry.embedding);
      cosines.push_back(cosine);
      per_bucket[entry.bucket].push_back(cosine);
      ranked.emplace_back(cosine, entry.id + "(" + std::to_string(entry.ids.size()) + ")");
      alone[entry.id] = out[0];
      if (save.is_open()) {
        save << R"({"id":")" << entry.id << R"(","mode":")" << mode_name
             << R"(","cosine":)" << std::setprecision(9) << cosine
             << R"(,"embedding":[)";
        for (std::size_t i = 0; i < out[0].size(); ++i) {
          save << (i ? "," : "") << out[0][i];
        }
        save << "]}\n" << std::setprecision(6);
      }
    }
    std::sort(ranked.begin(), ranked.end());
    const double min = *std::min_element(cosines.begin(), cosines.end());
    const double mean =
        std::accumulate(cosines.begin(), cosines.end(), 0.0) / double(cosines.size());
    const double max = *std::max_element(cosines.begin(), cosines.end());
    const std::size_t below = std::count_if(cosines.begin(), cosines.end(),
                                            [](double c) { return c < kG2Min; });
    const bool g2 = min >= kG2Min && mean >= kG2Mean;
    std::cout << "G2 " << (g2 ? "pass" : "FAIL") << ": " << cosines.size()
              << " texts  min " << min << "  mean " << mean << "  max " << max
              << "  below 0.999: " << below << "\n";
    for (const auto& [bucket, values] : per_bucket) {
      std::cout << "   " << std::left << std::setw(6) << bucket << std::right
                << " n=" << values.size() << "  min "
                << *std::min_element(values.begin(), values.end()) << "  mean "
                << std::accumulate(values.begin(), values.end(), 0.0) / double(values.size())
                << "  forward " << std::setprecision(1)
                << 1000.0 * bucket_seconds[bucket] / double(values.size())
                << " ms/text" << std::setprecision(6) << "\n";
    }
    std::cout << "   worst:";
    for (std::size_t i = 0; i < ranked.size() && i < 5; ++i) {
      std::cout << " " << ranked[i].second << " " << ranked[i].first;
    }
    std::cout << "\n";
    passed = passed && g2 && cosines.size() == texts.size();
    // G3: the short texts in one batch against the same texts alone.
    std::vector<const std::vector<std::uint32_t>*> packed;
    std::vector<const Text*> short_texts;
    for (const Text& entry : texts) {
      if (entry.bucket == "short" && alone.contains(entry.id)) {
        packed.push_back(&entry.ids);
        short_texts.push_back(&entry);
      }
    }
    if (!packed.empty()) {
      std::vector<std::vector<float>> out;
      if (!encoder->RunBatch(packed, &out, &error)) {
        std::cout << "FAIL golden_hip_test: packed batch: " << error << "\n";
        return 1;
      }
      double g3_min = 1, oracle_min = 1;
      for (std::size_t i = 0; i < out.size(); ++i) {
        g3_min = std::min(g3_min, Cosine(out[i], alone[short_texts[i]->id]));
        oracle_min = std::min(oracle_min, Cosine(out[i], short_texts[i]->embedding));
      }
      const bool g3 = g3_min >= kG3Min;
      std::cout << "G3 " << (g3 ? "pass" : "FAIL") << ": " << out.size()
                << " short texts in one batch vs alone  min " << g3_min
                << "  (packed vs oracle min " << oracle_min << ")\n";
      passed = passed && g3;
    }
  }
  std::cout << (passed ? "golden_hip_test: passed\n" : "golden_hip_test: FAILED\n");
  return passed ? 0 : 1;
}
