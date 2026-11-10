#include "inputs.hpp"

#include <stdexcept>
#include <utility>

#include "config.hpp"

namespace qwen3_embedding {

std::size_t ByteLimit(const Tokenizer& tokenizer) {
  // An overlong 4-byte UTF-8 sequence decodes to one ASCII byte, so input
  // bytes can shrink fourfold before the byte-level BPE sees them.
  return kMaxSequenceTokens * tokenizer.max_token_bytes() * 4;
}

PrepareStatus PrepareInputs(const Tokenizer& tokenizer,
                            const std::vector<gufo::ext::EmbeddingInput>& inputs,
                            bool truncate, PreparedInputs* prepared,
                            std::size_t* failed_index, std::string* error) {
  prepared->sequences.clear();
  prepared->token_counts.clear();
  prepared->sequences.reserve(inputs.size());
  prepared->token_counts.reserve(inputs.size());
  const std::size_t byte_limit = ByteLimit(tokenizer);
  for (std::size_t index = 0; index < inputs.size(); ++index) {
    std::string text;
    for (const auto& part : inputs[index].content) {
      if (part.type != gufo::ext::EmbeddingPart::Type::kText) {
        if (error != nullptr) {
          *error = "qwen3-embedding embeds text only";
        }
        if (failed_index != nullptr) {
          *failed_index = index;
        }
        return PrepareStatus::kInvalidInput;
      }
      text += part.value;
    }
    if (!truncate && text.size() > byte_limit) {
      if (failed_index != nullptr) {
        *failed_index = index;
      }
      return PrepareStatus::kInputTooLong;
    }
    std::vector<std::uint32_t> ids;
    try {
      ids = tokenizer.Encode(text);
    } catch (const std::invalid_argument& failure) {
      if (error != nullptr) {
        *error = std::string("input text cannot be tokenized: ") + failure.what();
      }
      if (failed_index != nullptr) {
        *failed_index = index;
      }
      return PrepareStatus::kInvalidInput;
    }
    if (ids.size() > kMaxSequenceTokens) {
      if (!truncate) {
        if (failed_index != nullptr) {
          *failed_index = index;
        }
        return PrepareStatus::kInputTooLong;
      }
      ids.resize(kMaxSequenceTokens);
      ids.back() = tokenizer.eos_id();
    }
    prepared->token_counts.push_back(ids.size());
    prepared->sequences.push_back(std::move(ids));
  }
  return PrepareStatus::kOk;
}

}  // namespace qwen3_embedding
