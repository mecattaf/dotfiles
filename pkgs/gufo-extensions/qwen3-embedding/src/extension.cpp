// GPU-free registration. A build without HIP still probes the GGUF and lists
// the provider, with no runner; the HIP build registers the runner from
// provider.cpp instead.
#include <gufo/ext/embeddings.hpp>
#include <gufo/ext/registry.hpp>

#include "probe.hpp"

void qwen3_embedding_register(gufo::ext::Registry& registry) {
#if !defined(ENGINE_ENABLE_HIP)
  registry.AddEmbeddingProvider({
      .id = "qwen3-embedding",
      .probe = &qwen3_embedding::ProbeQwen3Embedding,
      .resolve = &qwen3_embedding::ResolveQwen3Embedding,
      .create = nullptr,
  });
#else
  (void)registry;
#endif
}
