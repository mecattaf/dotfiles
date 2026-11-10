#ifndef QWEN3_EMBEDDING_TOKENIZER_UNICODE_DATA_HPP_
#define QWEN3_EMBEDDING_TOKENIZER_UNICODE_DATA_HPP_

#include <cstdint>
#include <initializer_list>
#include <unordered_set>
#include <utility>

namespace qwen3_embedding::unicode {

inline constexpr std::uint32_t MAX_CODEPOINTS = 0x110000;

/// {start, flags}; a range runs to the next start. The last entry is
/// {MAX_CODEPOINTS, 0}.
extern const std::initializer_list<std::pair<std::uint32_t, std::uint16_t>>
    unicode_ranges_flags;
extern const std::unordered_set<std::uint32_t> unicode_set_whitespace;
/// {code point, lowercase}, ascending, for binary search.
extern const std::initializer_list<std::pair<std::uint32_t, std::uint32_t>>
    unicode_map_lowercase;

}  // namespace qwen3_embedding::unicode

#endif  // QWEN3_EMBEDDING_TOKENIZER_UNICODE_DATA_HPP_
