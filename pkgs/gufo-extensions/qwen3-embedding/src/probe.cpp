#include "probe.hpp"

#include <exception>
#include <filesystem>
#include <gufo/ext/gguf_reader.hpp>
#include <system_error>

#include "config.hpp"
#include "weights.hpp"

namespace qwen3_embedding {

std::string ExplainModel(std::string_view model_root) {
  const std::filesystem::path path(model_root);
  std::error_code status_error;
  if (!std::filesystem::is_regular_file(path, status_error) ||
      path.extension() != ".gguf") {
    return "not a .gguf file: " + path.string();
  }
  std::string error;
  const auto reader = gufo::core::GgufReader::OpenFile(path, &error);
  if (!reader) {
    return "cannot read GGUF " + path.string() + ": " + error;
  }
  if (auto problem = CheckConfig(ReadConfig(*reader)); !problem.empty()) {
    return problem;
  }
  return CheckTensors(*reader);
}

bool ProbeQwen3Embedding(std::string_view model_root) noexcept {
  try {
    return ExplainModel(model_root).empty();
  } catch (const std::exception&) {
    return false;
  } catch (...) {
    return false;
  }
}

bool ResolveQwen3Embedding(std::string_view /*model_root*/,
                           std::map<std::string, std::string>* prompts,
                           std::string* /*error*/) {
  if (prompts != nullptr) {
    prompts->clear();
  }
  return true;
}

}  // namespace qwen3_embedding
