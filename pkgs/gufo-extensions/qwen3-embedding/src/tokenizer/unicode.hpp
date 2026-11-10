#ifndef QWEN3_EMBEDDING_TOKENIZER_UNICODE_HPP_
#define QWEN3_EMBEDDING_TOKENIZER_UNICODE_HPP_

// A port of the parts of llama.cpp's src/unicode.{h,cpp} (build 9925,
// ed8c26150e6b0ed6e2635cab75ace5ed121482ca, MIT, the ggml authors) that the
// Qwen2 byte-level BPE tokenizer uses. Function names are llama.cpp's so the
// two can be diffed; behaviour is meant to be identical, including on invalid
// UTF-8.

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace qwen3_embedding::unicode {

/// Code point flags, the low byte being the general category. Same bit
/// values as llama.cpp's `unicode_cpt_flags`.
struct unicode_cpt_flags {
  enum : std::uint16_t {
    UNDEFINED = 0x0001,
    NUMBER = 0x0002,       // \p{N}
    LETTER = 0x0004,       // \p{L}
    SEPARATOR = 0x0008,    // \p{Z}
    ACCENT_MARK = 0x0010,  // \p{M}
    PUNCTUATION = 0x0020,  // \p{P}
    SYMBOL = 0x0040,       // \p{S}
    CONTROL = 0x0080,      // \p{C}
    MASK_CATEGORIES = 0x00FF,
    WHITESPACE = 0x0100,  // \s
  };

  std::uint16_t bits{0};

  [[nodiscard]] bool is_number() const { return (bits & NUMBER) != 0; }
  [[nodiscard]] bool is_letter() const { return (bits & LETTER) != 0; }
  [[nodiscard]] bool is_whitespace() const { return (bits & WHITESPACE) != 0; }
  [[nodiscard]] std::uint16_t as_uint() const { return bits; }
};

std::size_t unicode_len_utf8(char src);
std::string unicode_cpt_to_utf8(std::uint32_t cpt);
/// Throws std::invalid_argument on an invalid sequence at `offset`.
std::uint32_t unicode_cpt_from_utf8(const std::string& utf8,
                                    std::size_t& offset);
/// Invalid bytes become U+FFFD, one per byte skipped, as in llama.cpp.
std::vector<std::uint32_t> unicode_cpts_from_utf8(const std::string& utf8);
unicode_cpt_flags unicode_cpt_flags_from_cpt(std::uint32_t cpt);
/// The GPT-2 byte-to-unicode map: the UTF-8 of the code point standing for
/// `byte` in a byte-level vocabulary.
const std::string& unicode_byte_to_utf8(std::uint8_t byte);
/// The inverse; returns false for a string that is no mapped code point.
bool unicode_utf8_to_byte(const std::string& utf8, std::uint8_t* byte);
std::uint32_t unicode_tolower(std::uint32_t cpt);

/// The Qwen2 pre-tokenizer of llama.cpp: the hand-written matcher
/// `unicode_regex_split_custom_qwen2` for the regex
/// (?:'[sS]|'[tT]|'[rR][eE]|'[vV][eE]|'[mM]|'[lL][lL]|'[dD])|[^\r\n\p{L}\p{N}]?\p{L}+|\p{N}| ?[^\s\p{L}\p{N}]+[\r\n]*|\s*[\r\n]+|\s+(?!\S)|\s+
/// then, as `unicode_regex_split(text, {that regex}, byte_encode = true)`
/// does, each word re-encoded from its code points and mapped byte by byte
/// through the GPT-2 table. Throws std::invalid_argument when a decoded code
/// point has no UTF-8 encoding (above U+10FFFF), as llama.cpp does.
std::vector<std::string> unicode_regex_split_qwen2(const std::string& text);

}  // namespace qwen3_embedding::unicode

#endif  // QWEN3_EMBEDDING_TOKENIZER_UNICODE_HPP_
