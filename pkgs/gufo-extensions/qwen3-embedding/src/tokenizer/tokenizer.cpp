// Port of the BPE path of llama.cpp src/llama-vocab.cpp (build 9925,
// ed8c26150e6b0ed6e2635cab75ace5ed121482ca, MIT, the ggml authors) for the
// "gpt2" model with the "qwen2" pre-tokenizer: vocabulary load, the text
// rules that promote tokens to CONTROL, the special-token cache,
// tokenizer_st_partition and llm_tokenizer_bpe_session::tokenize.

#include "tokenizer.hpp"

#include <algorithm>
#include <functional>
#include <queue>
#include <stdexcept>
#include <variant>

#include "unicode.hpp"

namespace qwen3_embedding {
namespace {

using unicode::unicode_len_utf8;

bool IsSpecialType(std::int32_t type) {
  return type == Tokenizer::kControl || type == Tokenizer::kUserDefined ||
         type == Tokenizer::kUnknown;
}

// Token texts llama.cpp's vocabulary load matches to find special ids that
// the GGUF does not name (llama-vocab.cpp, "auto-detect special tokens by
// text"). The first match in each group becomes that id and is promoted to
// CONTROL.
const std::vector<std::string_view> kEotTexts = {
    "<|eot_id|>", "<|im_end|>", "<|end|>", "<end_of_turn>", "<|endoftext|>",
    "<|end_of_text|>", "<EOT>", "_<EOT>", "[EOT]",
    "<\xef\xbd\x9c" "end\xe2\x96\x81" "of\xe2\x96\x81" "sentence\xef\xbd\x9c>",
    "<end_of_utterance>"};
const std::vector<std::string_view> kEomTexts = {"<|eom_id|>"};
const std::vector<std::string_view> kFimPreTexts = {
    "<|fim_prefix|>", "<fim-prefix>", "<fim_prefix>",
    "<\xef\xbd\x9c" "fim\xe2\x96\x81" "begin\xef\xbd\x9c>", "<PRE>",
    "\xe2\x96\x81<PRE>", "<|code_prefix|>", "<|prefix|>"};
const std::vector<std::string_view> kFimSufTexts = {
    "<|fim_suffix|>", "<fim-suffix>", "<fim_suffix>",
    "<\xef\xbd\x9c" "fim\xe2\x96\x81" "hole\xef\xbd\x9c>", "<SUF>",
    "\xe2\x96\x81<SUF>", "<|code_suffix|>", "<|suffix|>"};
const std::vector<std::string_view> kFimMidTexts = {
    "<|fim_middle|>", "<fim-middle>", "<fim_middle>",
    "<\xef\xbd\x9c" "fim\xe2\x96\x81" "end\xef\xbd\x9c>", "<MID>",
    "\xe2\x96\x81<MID>", "<|code_middle|>", "<|middle|>"};
const std::vector<std::string_view> kFimPadTexts = {
    "<|fim_pad|>", "<fim-pad>", "<fim_pad>", "<PAD>", "[PAD]"};
const std::vector<std::string_view> kFimRepTexts = {
    "<|fim_repo|>", "<|repo_name|>", "<fim-repo>", "<REPO>", "<reponame>"};
const std::vector<std::string_view> kFimSepTexts = {"<|file_sep|>"};
// End-of-generation texts: every token with one of these texts is promoted
// to CONTROL, whatever the GGUF says.
const std::vector<std::string_view> kEogTexts = {
    "<|eot_id|>", "<|im_end|>", "<|end|>", "<|return|>", "<|call|>",
    "<|flush|>", "<|calls|>", "<end_of_turn>", "<|endoftext|>", "</s>",
    "<|eom_id|>", "<EOT>", "_<EOT>", "[EOT]", "[EOS]", "<|end_of_text|>",
    "<end_of_utterance>", "<eos>", "<turn|>", "<|tool_response>",
    "<\xef\xbd\x9c" "end\xe2\x96\x81" "of\xe2\x96\x81" "sentence\xef\xbd\x9c>"};
// Always rendered as USER_DEFINED (llama.cpp's gpt-oss rule).
const std::vector<std::string_view> kUserDefinedTexts = {
    "<|channel|>", "<|message|>", "<|start|>", "<|constrain|>"};

bool Contains(const std::vector<std::string_view>& texts, std::string_view text) {
  return std::ranges::find(texts, text) != texts.end();
}

/// One piece of the raw text during the special-token partition: a token id,
/// or the raw bytes [offset, offset + length).
struct Fragment {
  bool is_token{false};
  std::uint32_t token{0};
  std::size_t offset{0};
  std::size_t length{0};
};

struct Symbol {
  int prev;
  int next;
  const char* text;
  std::size_t n;
};

struct Bigram {
  struct Comparator {
    bool operator()(const Bigram& l, const Bigram& r) const {
      return l.rank > r.rank || (l.rank == r.rank && l.left > r.left);
    }
  };
  int left;
  int right;
  std::string text;
  int rank;
  std::size_t size;
};

std::vector<std::string> ToStrings(const std::vector<std::string_view>& views) {
  return {views.begin(), views.end()};
}

}  // namespace

std::size_t Tokenizer::PairHash::operator()(
    const std::pair<std::string, std::string>& pair) const noexcept {
  const std::size_t first = std::hash<std::string>{}(pair.first);
  const std::size_t second = std::hash<std::string>{}(pair.second);
  return first ^ (second + 0x9e3779b97f4a7c15ULL + (first << 6) + (first >> 2));
}

std::optional<Tokenizer> Tokenizer::Load(const gufo::core::GgufReader& reader,
                                         std::string* error) {
  const auto fail = [&](std::string message) -> std::optional<Tokenizer> {
    if (error != nullptr) {
      *error = std::move(message);
    }
    return std::nullopt;
  };
  if (reader.GetMetadataString("tokenizer.ggml.model").value_or("") != "gpt2" ||
      reader.GetMetadataString("tokenizer.ggml.pre").value_or("") != "qwen2") {
    return fail("the tokenizer is not gpt2 with the qwen2 pre-tokenizer");
  }
  Vocab vocab;
  vocab.tokens = ToStrings(reader.GetMetadataStringArray("tokenizer.ggml.tokens"));
  vocab.merges = ToStrings(reader.GetMetadataStringArray("tokenizer.ggml.merges"));
  if (const auto* types = reader.FindMetadata("tokenizer.ggml.token_type")) {
    if (const auto* list = std::get_if<std::vector<std::int64_t>>(&types->value)) {
      vocab.types.assign(list->begin(), list->end());
    } else if (const auto* unsigned_list =
                   std::get_if<std::vector<std::uint64_t>>(&types->value)) {
      vocab.types.assign(unsigned_list->begin(), unsigned_list->end());
    }
  }
  const auto eos = reader.GetMetadataUint32("tokenizer.ggml.eos_token_id");
  if (!eos.has_value()) {
    return fail("tokenizer.ggml.eos_token_id is missing");
  }
  vocab.eos_id = *eos;
  vocab.bos_id = reader.GetMetadataUint32("tokenizer.ggml.bos_token_id");
  // llama.cpp's defaults for a BPE vocabulary when the keys are absent.
  vocab.add_eos = reader.GetMetadataBool("tokenizer.ggml.add_eos_token").value_or(false);
  vocab.add_bos = reader.GetMetadataBool("tokenizer.ggml.add_bos_token").value_or(false);
  const auto has_id = [&](std::string_view key) {
    const auto id = reader.GetMetadataUint32(key);
    return id.has_value() && *id < vocab.tokens.size();
  };
  vocab.has_eot_id = has_id("tokenizer.ggml.eot_token_id");
  vocab.has_eom_id = has_id("tokenizer.ggml.eom_token_id");
  vocab.has_fim_pre_id = has_id("tokenizer.ggml.fim_pre_token_id") ||
                         has_id("tokenizer.ggml.prefix_token_id");
  vocab.has_fim_suf_id = has_id("tokenizer.ggml.fim_suf_token_id") ||
                         has_id("tokenizer.ggml.suffix_token_id");
  vocab.has_fim_mid_id = has_id("tokenizer.ggml.fim_mid_token_id") ||
                         has_id("tokenizer.ggml.middle_token_id");
  vocab.has_fim_pad_id = has_id("tokenizer.ggml.fim_pad_token_id");
  vocab.has_fim_rep_id = has_id("tokenizer.ggml.fim_rep_token_id");
  vocab.has_fim_sep_id = has_id("tokenizer.ggml.fim_sep_token_id");
  return FromVocab(std::move(vocab), error);
}

std::optional<Tokenizer> Tokenizer::FromVocab(Vocab vocab, std::string* error) {
  const auto fail = [&](std::string message) -> std::optional<Tokenizer> {
    if (error != nullptr) {
      *error = std::move(message);
    }
    return std::nullopt;
  };
  const std::size_t n_tokens = vocab.tokens.size();
  if (n_tokens == 0 || n_tokens > 0x7fffffff) {
    return fail("the vocabulary is empty or too large");
  }
  if (!vocab.types.empty() && vocab.types.size() != n_tokens) {
    return fail("tokenizer.ggml.token_type does not match the vocabulary");
  }
  if (vocab.eos_id >= n_tokens) {
    return fail("the EOS id is outside the vocabulary");
  }
  Tokenizer tokenizer;
  tokenizer.eos_id_ = vocab.eos_id;
  tokenizer.add_eos_ = vocab.add_eos;
  tokenizer.add_bos_ = vocab.add_bos;
  if (vocab.bos_id.has_value() && *vocab.bos_id < n_tokens) {
    tokenizer.bos_id_ = vocab.bos_id;
  }
  if (vocab.add_bos && !tokenizer.bos_id_.has_value()) {
    return fail("add_bos_token is set without a BOS id");
  }

  tokenizer.tokens_.reserve(n_tokens);
  tokenizer.types_.reserve(n_tokens);
  tokenizer.token_to_id_.reserve(n_tokens);
  for (std::size_t i = 0; i < n_tokens; ++i) {
    std::string word = std::move(vocab.tokens[i]);
    if (word.empty()) {
      word = "[EMPTY_" + std::to_string(i) + "]";
    }
    tokenizer.token_to_id_[word] = static_cast<std::uint32_t>(i);
    tokenizer.max_token_bytes_ = std::max(tokenizer.max_token_bytes_, word.size());
    tokenizer.tokens_.push_back(std::move(word));
    tokenizer.types_.push_back(vocab.types.empty() ? kNormal : vocab.types[i]);
  }

  // Merge ranks: "left right", split at the first space after position 0;
  // the first rank of a repeated pair wins.
  tokenizer.bpe_ranks_.reserve(vocab.merges.size());
  for (std::size_t i = 0; i < vocab.merges.size(); ++i) {
    const std::string& word = vocab.merges[i];
    std::string first;
    std::string second;
    const std::size_t pos = word.find(' ', 1);
    if (pos != std::string::npos) {
      first = word.substr(0, pos);
      second = word.substr(pos + 1);
    }
    tokenizer.bpe_ranks_.emplace(std::make_pair(first, second),
                                 static_cast<int>(i));
  }

  // Text rules. llama.cpp walks its token map in hash order and takes the
  // first match of each group; ties never arise for this vocabulary (each
  // group has at most one candidate), and here the lowest id wins.
  std::vector<bool> control(n_tokens, false);
  std::vector<bool> user_defined(n_tokens, false);
  const auto promote_first = [&](bool has_id,
                                 const std::vector<std::string_view>& texts) {
    if (has_id) {
      return;
    }
    for (std::size_t id = 0; id < n_tokens; ++id) {
      if (Contains(texts, tokenizer.tokens_[id])) {
        control[id] = true;
        return;
      }
    }
  };
  promote_first(vocab.has_eot_id, kEotTexts);
  promote_first(vocab.has_eom_id, kEomTexts);
  promote_first(vocab.has_fim_pre_id, kFimPreTexts);
  promote_first(vocab.has_fim_suf_id, kFimSufTexts);
  promote_first(vocab.has_fim_mid_id, kFimMidTexts);
  promote_first(vocab.has_fim_pad_id, kFimPadTexts);
  promote_first(vocab.has_fim_rep_id, kFimRepTexts);
  promote_first(vocab.has_fim_sep_id, kFimSepTexts);
  bool has_tool_response = false;
  std::optional<std::size_t> end_s;
  for (std::size_t id = 0; id < n_tokens; ++id) {
    const std::string& text = tokenizer.tokens_[id];
    if (Contains(kEogTexts, text)) {
      control[id] = true;
      has_tool_response = has_tool_response || text == "<|tool_response>";
      if (text == "</s>") {
        end_s = id;
      }
    }
    if (Contains(kUserDefinedTexts, text)) {
      user_defined[id] = true;
    }
  }
  // llama.cpp's Gemma 4 rule: with <|tool_response>, </s> is a normal token.
  bool end_s_normal = has_tool_response && end_s.has_value();

  for (std::size_t id = 0; id < n_tokens; ++id) {
    bool special = IsSpecialType(tokenizer.types_[id]) || control[id];
    if (end_s_normal && id == *end_s) {
      special = false;
    }
    if (user_defined[id]) {
      special = true;
    }
    if (special) {
      tokenizer.special_.push_back(static_cast<std::uint32_t>(id));
    }
  }
  std::ranges::stable_sort(tokenizer.special_, [&](std::uint32_t a, std::uint32_t b) {
    return tokenizer.tokens_[a].size() > tokenizer.tokens_[b].size();
  });
  return tokenizer;
}

int Tokenizer::FindBpeRank(const std::string& left,
                           const std::string& right) const {
  const auto found = bpe_ranks_.find(std::make_pair(left, right));
  return found == bpe_ranks_.end() ? -1 : found->second;
}

std::optional<std::uint32_t> Tokenizer::TextToToken(const std::string& text) const {
  const auto found = token_to_id_.find(text);
  if (found == token_to_id_.end()) {
    return std::nullopt;
  }
  return found->second;
}

std::vector<std::uint32_t> Tokenizer::Encode(std::string_view text) const {
  return Encode(text, /*add_special=*/true, /*parse_special=*/true);
}

std::vector<std::uint32_t> Tokenizer::Encode(std::string_view text_view,
                                             bool add_special,
                                             bool parse_special) const {
  const std::string raw_text(text_view);
  std::vector<std::uint32_t> output;

  // tokenizer_st_partition: split the raw text at every special token, longest
  // first. With parse_special off, only USER_DEFINED tokens are split out.
  std::vector<Fragment> fragments;
  if (!raw_text.empty()) {
    fragments.push_back({.is_token = false, .token = 0, .offset = 0,
                         .length = raw_text.size()});
    for (const std::uint32_t special_id : special_) {
      const std::int32_t type = types_[special_id];
      if (!parse_special && type != kUserDefined) {
        continue;
      }
      const std::string& text = tokens_[special_id];
      std::vector<Fragment> next;
      next.reserve(fragments.size());
      for (const Fragment& fragment : fragments) {
        if (fragment.is_token) {
          next.push_back(fragment);
          continue;
        }
        std::size_t base_offset = fragment.offset;
        std::size_t base_length = fragment.length;
        while (true) {
          const std::size_t match =
              std::string_view(raw_text.data(), base_offset + base_length)
                  .find(text, base_offset);
          if (match == std::string_view::npos) {
            if (base_length > 0) {
              next.push_back({.is_token = false, .token = 0,
                              .offset = base_offset, .length = base_length});
            }
            break;
          }
          if (match > base_offset) {
            next.push_back({.is_token = false, .token = 0,
                            .offset = base_offset,
                            .length = match - base_offset});
          }
          next.push_back({.is_token = true, .token = special_id, .offset = 0,
                          .length = 0});
          const std::size_t right = match + text.size();
          base_length = base_offset + base_length - right;
          base_offset = right;
          if (base_length == 0) {
            break;
          }
        }
      }
      fragments = std::move(next);
    }
  }

  if (add_special && add_bos_) {
    output.push_back(*bos_id_);
  }
  for (const Fragment& fragment : fragments) {
    if (fragment.is_token) {
      output.push_back(fragment.token);
    } else {
      TokenizeBpe(raw_text.substr(fragment.offset, fragment.length), output);
    }
  }
  if (add_special && add_eos_) {
    output.push_back(eos_id_);
  }
  return output;
}

void Tokenizer::TokenizeBpe(const std::string& text,
                            std::vector<std::uint32_t>& output) const {
  const auto word_collection = unicode::unicode_regex_split_qwen2(text);

  std::vector<Symbol> symbols_final;
  std::vector<Symbol> symbols;
  int final_prev_index = -1;

  for (const auto& word : word_collection) {
    std::priority_queue<Bigram, std::vector<Bigram>, Bigram::Comparator>
        work_queue;
    symbols.clear();

    int index = 0;
    std::size_t offset = 0;
    while (offset < word.size()) {
      Symbol sym{};
      const std::size_t char_len =
          std::min(word.size() - offset, unicode_len_utf8(word[offset]));
      sym.text = word.c_str() + offset;
      sym.n = char_len;
      offset += sym.n;
      sym.prev = index - 1;
      sym.next = offset == word.size() ? -1 : index + 1;
      index++;
      symbols.push_back(sym);
    }

    const auto add_new_bigram = [&](int left, int right) {
      if (left == -1 || right == -1) {
        return;
      }
      std::string left_token(symbols[left].text, symbols[left].n);
      std::string right_token(symbols[right].text, symbols[right].n);
      const int rank_found = FindBpeRank(left_token, right_token);
      if (rank_found < 0) {
        return;
      }
      Bigram bigram;
      bigram.left = left;
      bigram.right = right;
      bigram.text = left_token + right_token;
      bigram.size = left_token.size() + right_token.size();
      bigram.rank = rank_found;
      work_queue.push(std::move(bigram));
    };

    for (int i = 1; i < static_cast<int>(symbols.size()); ++i) {
      add_new_bigram(i - 1, i);
    }

    // build token(s)
    while (!work_queue.empty()) {
      Bigram bigram = work_queue.top();
      work_queue.pop();

      auto& left_symbol = symbols[bigram.left];
      auto& right_symbol = symbols[bigram.right];

      if (left_symbol.n == 0 || right_symbol.n == 0) {
        continue;
      }
      std::string left_token(left_symbol.text, left_symbol.n);
      std::string right_token(right_symbol.text, right_symbol.n);
      if (left_token + right_token != bigram.text) {
        continue;  // outdated bigram
      }

      // merge the right sym into the left one
      left_symbol.n += right_symbol.n;
      right_symbol.n = 0;

      // remove the right sym from the chain
      left_symbol.next = right_symbol.next;
      if (right_symbol.next >= 0) {
        symbols[right_symbol.next].prev = bigram.left;
      }

      add_new_bigram(left_symbol.prev, bigram.left);  // left side
      add_new_bigram(bigram.left, left_symbol.next);  // right side
    }

    // add the finished tokens to the final list keeping order
    for (auto& sym : symbols) {
      if (sym.n > 0) {
        sym.prev = final_prev_index;
        sym.next = -1;
        if (final_prev_index != -1) {
          symbols_final[final_prev_index].next =
              static_cast<int>(symbols_final.size());
        }
        symbols_final.push_back(sym);
        final_prev_index = static_cast<int>(symbols_final.size()) - 1;
      }
    }
  }

  if (symbols_final.empty()) {
    return;
  }
  for (int i = 0; i != -1; i = symbols_final[i].next) {
    const auto& symbol = symbols_final[i];
    if (symbol.n == 0) {
      continue;
    }
    const std::string str(symbol.text, symbol.n);
    if (const auto token = TextToToken(str)) {
      output.push_back(*token);
      continue;
    }
    // No vocabulary entry: one token per byte of the encoded text, when the
    // byte alone is a token (llama.cpp's fallback for byte-encoded BPE).
    for (const char byte : str) {
      if (const auto byte_token = TextToToken(std::string(1, byte))) {
        output.push_back(*byte_token);
      }
    }
  }
}

std::string Tokenizer::Piece(std::uint32_t id) const {
  const std::string& text = tokens_.at(id);
  if (IsSpecialType(types_.at(id))) {
    return text;
  }
  std::string bytes;
  for (const auto cpt : unicode::unicode_cpts_from_utf8(text)) {
    std::uint8_t byte = 0;
    if (unicode::unicode_utf8_to_byte(unicode::unicode_cpt_to_utf8(cpt), &byte)) {
      bytes.push_back(static_cast<char>(byte));
    } else {
      bytes += unicode::unicode_cpt_to_utf8(cpt);
    }
  }
  return bytes;
}

}  // namespace qwen3_embedding
