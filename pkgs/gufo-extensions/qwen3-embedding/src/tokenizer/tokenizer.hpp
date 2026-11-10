#ifndef QWEN3_EMBEDDING_TOKENIZER_TOKENIZER_HPP_
#define QWEN3_EMBEDDING_TOKENIZER_TOKENIZER_HPP_

#include <cstddef>
#include <cstdint>
#include <gufo/ext/gguf_reader.hpp>
#include <optional>
#include <string>
#include <string_view>
#include <unordered_map>
#include <utility>
#include <vector>

namespace qwen3_embedding {

/// The Qwen2 byte-level BPE tokenizer exactly as llama.cpp (build 9925) runs
/// it for this GGUF with add_special and parse_special on, which is what
/// llama-server does for /v1/embeddings and /tokenize:
///
/// 1. Special tokens (CONTROL, USER_DEFINED and UNKNOWN token types, plus the
///    tokens llama.cpp promotes to CONTROL by their text, such as `</s>`) are
///    found literally in the raw text, longest first, and become their ids.
/// 2. Every other fragment goes through the Qwen2 pre-tokenizer, the GPT-2
///    byte-to-unicode map and the rank-ordered BPE merges; a final symbol with
///    no vocabulary entry falls back to its single-byte tokens.
/// 3. No BOS; the EOS is appended when the GGUF says add_eos_token.
///
/// Encode is const and keeps no state between calls, so concurrent callers
/// may share one tokenizer.
class Tokenizer {
public:
  /// Token types, as GGUF `tokenizer.ggml.token_type` stores them.
  enum TokenType : std::int32_t {
    kUndefined = 0,
    kNormal = 1,
    kUnknown = 2,
    kControl = 3,
    kUserDefined = 4,
    kUnused = 5,
    kByte = 6,
  };

  struct Vocab {
    std::vector<std::string> tokens;
    std::vector<std::int32_t> types;
    std::vector<std::string> merges;
    std::uint32_t eos_id{0};
    bool add_eos{true};
    bool add_bos{false};
    std::optional<std::uint32_t> bos_id;
    /// Special ids the GGUF names; when one is absent llama.cpp finds it by
    /// text instead and promotes that token to CONTROL.
    bool has_eot_id{false}, has_eom_id{false};
    bool has_fim_pre_id{false}, has_fim_suf_id{false}, has_fim_mid_id{false};
    bool has_fim_pad_id{false}, has_fim_rep_id{false}, has_fim_sep_id{false};
  };

  static std::optional<Tokenizer> Load(const gufo::core::GgufReader& reader,
                                       std::string* error = nullptr);
  static std::optional<Tokenizer> FromVocab(Vocab vocab,
                                            std::string* error = nullptr);

  /// Token ids with the EOS appended (add_special and parse_special on).
  /// Throws std::invalid_argument when the text decodes to a code point above
  /// U+10FFFF, which llama.cpp cannot tokenize either.
  [[nodiscard]] std::vector<std::uint32_t> Encode(std::string_view text) const;
  /// The same with add_special and parse_special chosen by the caller.
  [[nodiscard]] std::vector<std::uint32_t> Encode(std::string_view text,
                                                  bool add_special,
                                                  bool parse_special) const;

  [[nodiscard]] std::uint32_t eos_id() const { return eos_id_; }
  [[nodiscard]] std::size_t vocab_size() const { return tokens_.size(); }
  /// No token covers more input bytes than this.
  [[nodiscard]] std::size_t max_token_bytes() const { return max_token_bytes_; }
  /// The token's text as stored (GPT-2 byte-encoded for normal tokens).
  [[nodiscard]] const std::string& token_text(std::uint32_t id) const {
    return tokens_.at(id);
  }
  /// The raw bytes a token stands for (special tokens: their text).
  [[nodiscard]] std::string Piece(std::uint32_t id) const;
  /// Special-token ids in partition order (longest text first).
  [[nodiscard]] const std::vector<std::uint32_t>& special_tokens() const {
    return special_;
  }

private:
  struct PairHash {
    std::size_t operator()(
        const std::pair<std::string, std::string>& pair) const noexcept;
  };

  Tokenizer() = default;
  void TokenizeBpe(const std::string& text,
                   std::vector<std::uint32_t>& output) const;
  [[nodiscard]] int FindBpeRank(const std::string& left,
                                const std::string& right) const;
  [[nodiscard]] std::optional<std::uint32_t> TextToToken(
      const std::string& text) const;

  std::vector<std::string> tokens_;
  std::vector<std::int32_t> types_;
  std::unordered_map<std::string, std::uint32_t> token_to_id_;
  std::unordered_map<std::pair<std::string, std::string>, int, PairHash>
      bpe_ranks_;
  std::vector<std::uint32_t> special_;
  std::uint32_t eos_id_{0};
  std::optional<std::uint32_t> bos_id_;
  bool add_eos_{true};
  bool add_bos_{false};
  std::size_t max_token_bytes_{0};
};

}  // namespace qwen3_embedding

#endif  // QWEN3_EMBEDDING_TOKENIZER_TOKENIZER_HPP_
