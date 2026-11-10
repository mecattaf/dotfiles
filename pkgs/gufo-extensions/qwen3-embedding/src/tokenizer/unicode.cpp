// Port of llama.cpp src/unicode.cpp (build 9925,
// ed8c26150e6b0ed6e2635cab75ace5ed121482ca, MIT, the ggml authors): the
// functions the Qwen2 pre-tokenizer and the byte-level encoding use. The
// matcher below is `unicode_regex_split_custom_qwen2` line for line.

#include "unicode.hpp"

#include <algorithm>
#include <array>
#include <cassert>
#include <stdexcept>
#include <unordered_map>
#include <utility>

#include "unicode_data.hpp"

namespace qwen3_embedding::unicode {
namespace {

std::vector<std::uint16_t> unicode_cpt_flags_array() {
  std::vector<std::uint16_t> cpt_flags(MAX_CODEPOINTS,
                                       unicode_cpt_flags::UNDEFINED);
  assert(unicode_ranges_flags.begin()[0].first == 0);
  assert(unicode_ranges_flags.begin()[unicode_ranges_flags.size() - 1].first ==
         MAX_CODEPOINTS);
  for (std::size_t i = 1; i < unicode_ranges_flags.size(); ++i) {
    const auto range_ini = unicode_ranges_flags.begin()[i - 1];
    const auto range_end = unicode_ranges_flags.begin()[i];
    for (std::uint32_t cpt = range_ini.first; cpt < range_end.first; ++cpt) {
      cpt_flags[cpt] = range_ini.second;
    }
  }
  for (const auto cpt : unicode_set_whitespace) {
    cpt_flags[cpt] |= unicode_cpt_flags::WHITESPACE;
  }
  // llama.cpp also sets lowercase, uppercase and NFD bits here. They sit
  // outside the category byte, every in-range code point already has a
  // non-zero category, and the matcher reads only the letter, number and
  // whitespace bits and whether the flags are non-zero, so they are omitted.
  return cpt_flags;
}

std::array<std::string, 256> unicode_byte_to_utf8_map() {
  std::array<std::string, 256> map;
  std::array<bool, 256> set{};
  for (int ch = 0x21; ch <= 0x7E; ++ch) {  // u'!' to u'~'
    map[ch] = unicode_cpt_to_utf8(ch);
    set[ch] = true;
  }
  for (int ch = 0xA1; ch <= 0xAC; ++ch) {  // u'¡' to u'¬'
    map[ch] = unicode_cpt_to_utf8(ch);
    set[ch] = true;
  }
  for (int ch = 0xAE; ch <= 0xFF; ++ch) {  // u'®' to u'ÿ'
    map[ch] = unicode_cpt_to_utf8(ch);
    set[ch] = true;
  }
  int n = 0;
  for (int ch = 0; ch < 256; ++ch) {
    if (!set[ch]) {
      map[ch] = unicode_cpt_to_utf8(256 + n);
      ++n;
    }
  }
  return map;
}

// GPT-2 byte encoding of each word, as llama.cpp's
// unicode_byte_encoding_process.
std::vector<std::string> unicode_byte_encoding_process(
    const std::vector<std::string>& bpe_words) {
  std::vector<std::string> bpe_encoded_words;
  bpe_encoded_words.reserve(bpe_words.size());
  for (const auto& word : bpe_words) {
    std::string text_utf;
    const auto utf_word = unicode_cpts_from_utf8(word);
    for (const auto cpt : utf_word) {
      text_utf += unicode_cpt_to_utf8(cpt);
    }
    std::string encoded_token;
    for (const char c : text_utf) {
      encoded_token += unicode_byte_to_utf8(static_cast<std::uint8_t>(c));
    }
    bpe_encoded_words.emplace_back(std::move(encoded_token));
  }
  return bpe_encoded_words;
}

// Qwen2 system regex:
// "(?i:'s|'t|'re|'ve|'m|'ll|'d)|[^\\r\\n\\p{L}\\p{N}]?\\p{L}+|\\p{N}| ?[^\\s\\p{L}\\p{N}]+[\\r\\n]*|\\s*[\\r\\n]+|\\s+(?!\\S)|\\s+"
std::vector<std::size_t> unicode_regex_split_custom_qwen2(
    const std::vector<std::uint32_t>& cpts,
    const std::vector<std::size_t>& offsets) {
  std::vector<std::size_t> bpe_offsets;  // store the offset of each word
  bpe_offsets.reserve(offsets.size());

  std::size_t start = 0;
  for (auto offset : offsets) {
    const std::size_t offset_ini = start;
    const std::size_t offset_end = start + offset;
    assert(offset_end <= cpts.size());
    start = offset_end;

    static const std::uint32_t OUT_OF_RANGE = 0xFFFFFFFF;
    auto _get_cpt = [&](const std::size_t pos) -> std::uint32_t {
      return (offset_ini <= pos && pos < offset_end) ? cpts[pos] : OUT_OF_RANGE;
    };

    auto _get_flags = [&](const std::size_t pos) -> unicode_cpt_flags {
      return (offset_ini <= pos && pos < offset_end)
                 ? unicode_cpt_flags_from_cpt(cpts[pos])
                 : unicode_cpt_flags{};
    };

    std::size_t _prev_end = offset_ini;
    auto _add_token = [&](const std::size_t end) -> std::size_t {
      assert(_prev_end <= end && end <= offset_end);
      std::size_t len = end - _prev_end;
      if (len > 0) {
        bpe_offsets.push_back(len);
      }
      _prev_end = end;
      return len;
    };

    for (std::size_t pos = offset_ini; pos < offset_end; /*pos++*/) {
      const std::uint32_t cpt = _get_cpt(pos);
      const auto flags = _get_flags(pos);

      // regex: (?i:'s|'t|'re|'ve|'m|'ll|'d) // case insensitive
      if (cpt == '\'' && pos + 1 < offset_end) {
        std::uint32_t cpt_next = unicode_tolower(_get_cpt(pos + 1));
        if (cpt_next == 's' || cpt_next == 't' || cpt_next == 'm' ||
            cpt_next == 'd') {
          pos += _add_token(pos + 2);
          continue;
        }
        if (pos + 2 < offset_end) {
          std::uint32_t cpt_next_next = unicode_tolower(_get_cpt(pos + 2));
          if ((cpt_next == 'r' && cpt_next_next == 'e') ||
              (cpt_next == 'v' && cpt_next_next == 'e') ||
              (cpt_next == 'l' && cpt_next_next == 'l')) {
            pos += _add_token(pos + 3);
            continue;
          }
        }
      }

      // regex: [^\r\n\p{L}\p{N}]?\p{L}+
      if (!(cpt == '\r' || cpt == '\n' || flags.is_number())) {
        if (flags.is_letter() || _get_flags(pos + 1).is_letter()) {  // one or more letters
          pos++;
          while (_get_flags(pos).is_letter()) {
            pos++;
          }
          _add_token(pos);
          continue;
        }
      }

      // regex: \p{N}
      if (flags.is_number()) {
        pos++;
        _add_token(pos);
        continue;
      }

      // regex: <space>?[^\s\p{L}\p{N}]+[\r\n]*
      auto flags2 = (cpt == ' ' ? _get_flags(pos + 1) : flags);
      if (!(flags2.is_whitespace() | flags2.is_letter() | flags2.is_number()) &&
          flags.as_uint()) {
        pos += (cpt == ' ');
        while (!(flags2.is_whitespace() | flags2.is_letter() |
                 flags2.is_number()) &&
               flags2.as_uint()) {
          flags2 = _get_flags(++pos);
        }
        std::uint32_t cpt2 = _get_cpt(pos);
        while (cpt2 == '\r' || cpt2 == '\n') {
          cpt2 = _get_cpt(++pos);
        }
        _add_token(pos);
        continue;
      }

      std::size_t num_whitespaces = 0;
      std::size_t last_end_r_or_n = 0;
      while (_get_flags(pos + num_whitespaces).is_whitespace()) {
        std::uint32_t cpt2 = _get_cpt(pos + num_whitespaces);
        if (cpt2 == '\r' || cpt2 == '\n') {
          last_end_r_or_n = pos + num_whitespaces + 1;
        }
        num_whitespaces++;
      }

      // regex: \s*[\r\n]+
      if (last_end_r_or_n > 0) {
        pos = last_end_r_or_n;
        _add_token(pos);
        continue;
      }

      // regex: \s+(?!\S)
      if (num_whitespaces > 1 &&
          _get_cpt(pos + num_whitespaces) != OUT_OF_RANGE) {
        pos += num_whitespaces - 1;
        _add_token(pos);
        continue;
      }

      // regex: \s+
      if (num_whitespaces > 0) {
        pos += num_whitespaces;
        _add_token(pos);
        continue;
      }

      // no matches
      _add_token(++pos);
    }
  }

  return bpe_offsets;
}

}  // namespace

std::size_t unicode_len_utf8(char src) {
  const std::size_t lookup[] = {1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 3, 4};
  std::uint8_t highbits = static_cast<std::uint8_t>(src) >> 4;
  return lookup[highbits];
}

std::string unicode_cpt_to_utf8(std::uint32_t cpt) {
  std::string result;
  if (/* 0x00 <= cpt && */ cpt <= 0x7f) {
    result.push_back(static_cast<char>(cpt));
    return result;
  }
  if (0x80 <= cpt && cpt <= 0x7ff) {
    result.push_back(static_cast<char>(0xc0 | ((cpt >> 6) & 0x1f)));
    result.push_back(static_cast<char>(0x80 | (cpt & 0x3f)));
    return result;
  }
  if (0x800 <= cpt && cpt <= 0xffff) {
    result.push_back(static_cast<char>(0xe0 | ((cpt >> 12) & 0x0f)));
    result.push_back(static_cast<char>(0x80 | ((cpt >> 6) & 0x3f)));
    result.push_back(static_cast<char>(0x80 | (cpt & 0x3f)));
    return result;
  }
  if (0x10000 <= cpt && cpt <= 0x10ffff) {
    result.push_back(static_cast<char>(0xf0 | ((cpt >> 18) & 0x07)));
    result.push_back(static_cast<char>(0x80 | ((cpt >> 12) & 0x3f)));
    result.push_back(static_cast<char>(0x80 | ((cpt >> 6) & 0x3f)));
    result.push_back(static_cast<char>(0x80 | (cpt & 0x3f)));
    return result;
  }
  throw std::invalid_argument("invalid codepoint");
}

std::uint32_t unicode_cpt_from_utf8(const std::string& utf8,
                                    std::size_t& offset) {
  assert(offset < utf8.size());
  if (!(utf8[offset + 0] & 0x80)) {
    auto result = utf8[offset + 0];
    offset += 1;
    return static_cast<std::uint32_t>(result);
  }
  if (!(utf8[offset + 0] & 0x40)) {
    throw std::invalid_argument("invalid character");
  }
  if (!(utf8[offset + 0] & 0x20)) {
    if (offset + 1 >= utf8.size() || !((utf8[offset + 1] & 0xc0) == 0x80)) {
      throw std::invalid_argument("invalid character");
    }
    auto result = ((utf8[offset + 0] & 0x1f) << 6) | (utf8[offset + 1] & 0x3f);
    offset += 2;
    return static_cast<std::uint32_t>(result);
  }
  if (!(utf8[offset + 0] & 0x10)) {
    if (offset + 2 >= utf8.size() || !((utf8[offset + 1] & 0xc0) == 0x80) ||
        !((utf8[offset + 2] & 0xc0) == 0x80)) {
      throw std::invalid_argument("invalid character");
    }
    auto result = ((utf8[offset + 0] & 0x0f) << 12) |
                  ((utf8[offset + 1] & 0x3f) << 6) | (utf8[offset + 2] & 0x3f);
    offset += 3;
    return static_cast<std::uint32_t>(result);
  }
  if (!(utf8[offset + 0] & 0x08)) {
    if (offset + 3 >= utf8.size() || !((utf8[offset + 1] & 0xc0) == 0x80) ||
        !((utf8[offset + 2] & 0xc0) == 0x80) ||
        !((utf8[offset + 3] & 0xc0) == 0x80)) {
      throw std::invalid_argument("invalid character");
    }
    auto result = ((utf8[offset + 0] & 0x07) << 18) |
                  ((utf8[offset + 1] & 0x3f) << 12) |
                  ((utf8[offset + 2] & 0x3f) << 6) | (utf8[offset + 3] & 0x3f);
    offset += 4;
    return static_cast<std::uint32_t>(result);
  }
  throw std::invalid_argument("failed to convert utf8 to codepoint");
}

std::vector<std::uint32_t> unicode_cpts_from_utf8(const std::string& utf8) {
  std::vector<std::uint32_t> result;
  result.reserve(utf8.size());
  std::size_t offset = 0;
  while (offset < utf8.size()) {
    try {
      result.push_back(unicode_cpt_from_utf8(utf8, offset));
    } catch (const std::invalid_argument& /*ex*/) {
      // Invalid UTF-8: one replacement character per skipped byte.
      ++offset;
      result.emplace_back(0xFFFD);
    }
  }
  return result;
}

unicode_cpt_flags unicode_cpt_flags_from_cpt(const std::uint32_t cpt) {
  static const std::vector<std::uint16_t> cpt_flags = unicode_cpt_flags_array();
  return cpt < cpt_flags.size() ? unicode_cpt_flags{cpt_flags[cpt]}
                                : unicode_cpt_flags{unicode_cpt_flags::UNDEFINED};
}

const std::string& unicode_byte_to_utf8(std::uint8_t byte) {
  static const std::array<std::string, 256> map = unicode_byte_to_utf8_map();
  return map[byte];
}

bool unicode_utf8_to_byte(const std::string& utf8, std::uint8_t* byte) {
  static const std::unordered_map<std::string, std::uint8_t> map = [] {
    std::unordered_map<std::string, std::uint8_t> inverse;
    for (int ch = 0; ch < 256; ++ch) {
      inverse.emplace(unicode_byte_to_utf8(static_cast<std::uint8_t>(ch)),
                      static_cast<std::uint8_t>(ch));
    }
    return inverse;
  }();
  const auto found = map.find(utf8);
  if (found == map.end()) {
    return false;
  }
  *byte = found->second;
  return true;
}

std::uint32_t unicode_tolower(std::uint32_t cpt) {
  // binary search
  auto it = std::lower_bound(
      unicode_map_lowercase.begin(), unicode_map_lowercase.end(), cpt,
      [](const std::pair<std::uint32_t, std::uint32_t>& pair,
         std::uint32_t value) { return pair.first < value; });
  if (it != unicode_map_lowercase.end() && it->first == cpt) {
    return it->second;
  }
  return cpt;  // the original code point if no lowercase mapping is found
}

std::vector<std::string> unicode_regex_split_qwen2(const std::string& text) {
  const auto cpts = unicode_cpts_from_utf8(text);
  // llama.cpp starts from one offset spanning the text. For empty text the
  // custom matcher finds nothing and llama.cpp's std::regex fallback finds
  // nothing either, so there are no words.
  auto bpe_offsets = unicode_regex_split_custom_qwen2(cpts, {cpts.size()});

  std::vector<std::string> bpe_words;
  bpe_words.reserve(bpe_offsets.size());
  std::size_t start = 0;
  for (const std::size_t offset : bpe_offsets) {
    bpe_words.emplace_back();
    for (std::size_t i = start; i < start + offset; ++i) {
      bpe_words.back() += unicode_cpt_to_utf8(cpts[i]);
    }
    start += offset;
  }
  return unicode_byte_encoding_process(bpe_words);
}

}  // namespace qwen3_embedding::unicode
