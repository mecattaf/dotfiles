#ifndef QWEN3_EMBEDDING_INPUTS_HPP_
#define QWEN3_EMBEDDING_INPUTS_HPP_

#include <cstddef>
#include <cstdint>
#include <gufo/ext/embeddings.hpp>
#include <string>
#include <vector>

#include "tokenizer/tokenizer.hpp"

namespace qwen3_embedding {

enum class PrepareStatus { kOk, kInputTooLong, kInvalidInput };

struct PreparedInputs {
  /// Token ids per input, EOS last; at most kMaxSequenceTokens each.
  std::vector<std::vector<std::uint32_t>> sequences;
  /// Per input, the ids counted for usage (including the EOS).
  std::vector<std::size_t> token_counts;
};

/// Tokenizes embedding inputs the way llama-server does for this model: the
/// text parts of an input are concatenated, special-token text is parsed, the
/// EOS is appended. An input longer than kMaxSequenceTokens (8192, EOS
/// included) fails with kInputTooLong and its index unless `truncate`, which
/// keeps the first 8191 ids and the EOS. Image, audio and video parts fail
/// with kInvalidInput. Thread-safe for a shared tokenizer.
[[nodiscard]] PrepareStatus PrepareInputs(
    const Tokenizer& tokenizer,
    const std::vector<gufo::ext::EmbeddingInput>& inputs, bool truncate,
    PreparedInputs* prepared, std::size_t* failed_index, std::string* error);

/// Input bytes above which an input is certainly longer than
/// kMaxSequenceTokens: no token covers more than max_token_bytes() bytes, and
/// one input byte decodes to at least a quarter byte of re-encoded text.
[[nodiscard]] std::size_t ByteLimit(const Tokenizer& tokenizer);

}  // namespace qwen3_embedding

#endif  // QWEN3_EMBEDDING_INPUTS_HPP_
