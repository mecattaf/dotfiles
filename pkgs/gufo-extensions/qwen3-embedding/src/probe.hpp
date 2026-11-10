#ifndef QWEN3_EMBEDDING_PROBE_HPP_
#define QWEN3_EMBEDDING_PROBE_HPP_

#include <map>
#include <string>
#include <string_view>

namespace qwen3_embedding {

/// Empty when `model_root` is a `.gguf` file this extension runs, else why
/// not, in words. GPU-free; reads only the GGUF header.
[[nodiscard]] std::string ExplainModel(std::string_view model_root);

/// The provider probe: ExplainModel(model_root).empty(). Never throws.
[[nodiscard]] bool ProbeQwen3Embedding(std::string_view model_root) noexcept;

/// The embeddings resolver. A GGUF carries no sentence-transformers prompts,
/// so the map is always empty: clients frame queries themselves.
bool ResolveQwen3Embedding(std::string_view model_root,
                           std::map<std::string, std::string>* prompts,
                           std::string* error);

}  // namespace qwen3_embedding

#endif  // QWEN3_EMBEDDING_PROBE_HPP_
