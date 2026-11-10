// Checks input preparation on a tiny byte-level vocabulary (no GGUF needed):
// text parts concatenate, special text is parsed, the EOS is appended, the
// 8192-token limit (EOS included) fails with the input's index unless
// truncation keeps the first 8191 ids and the EOS, and media parts and
// untokenizable bytes are refused. A shared tokenizer serves several threads.

#include <cstdint>
#include <iostream>
#include <string>
#include <thread>
#include <vector>

#include "src/inputs.hpp"
#include "src/tokenizer/tokenizer.hpp"
#include "src/tokenizer/unicode.hpp"
#include "tests/support.hpp"

namespace {

using gufo::ext::EmbeddingInput;
using gufo::ext::EmbeddingPart;
using qwen3_embedding::PrepareInputs;
using qwen3_embedding::PrepareStatus;
using qwen3_embedding::PreparedInputs;
using qwen3_embedding::Tokenizer;
using qwen3_embedding::testing::Check;

constexpr std::uint32_t kEos = 256;
constexpr std::uint32_t kPair = 257;  // "aa"

/// 256 byte tokens (id = byte), the EOS, and one merge "a a" -> "aa".
Tokenizer TinyTokenizer() {
  Tokenizer::Vocab vocab;
  for (int byte = 0; byte < 256; ++byte) {
    vocab.tokens.push_back(qwen3_embedding::unicode::unicode_byte_to_utf8(
        static_cast<std::uint8_t>(byte)));
    vocab.types.push_back(Tokenizer::kNormal);
  }
  vocab.tokens.push_back("<|endoftext|>");
  vocab.types.push_back(Tokenizer::kControl);
  vocab.tokens.push_back("aa");
  vocab.types.push_back(Tokenizer::kNormal);
  vocab.merges = {"a a"};
  vocab.eos_id = kEos;
  vocab.add_eos = true;
  vocab.has_eot_id = true;
  std::string error;
  auto tokenizer = Tokenizer::FromVocab(std::move(vocab), &error);
  Check(tokenizer.has_value(), "tiny vocabulary refused: " + error);
  return std::move(*tokenizer);
}

EmbeddingInput Text(std::string text) {
  return EmbeddingInput{{EmbeddingPart{EmbeddingPart::Type::kText, std::move(text)}}};
}

std::vector<std::uint32_t> Bytes(std::string_view text) {
  std::vector<std::uint32_t> ids;
  for (const char c : text) {
    ids.push_back(static_cast<unsigned char>(c));
  }
  return ids;
}

std::vector<std::uint32_t> WithEos(std::vector<std::uint32_t> ids) {
  ids.push_back(kEos);
  return ids;
}

void Basics(const Tokenizer& tokenizer) {
  PreparedInputs prepared;
  std::size_t failed = 99;
  std::string error;
  std::vector<EmbeddingInput> inputs = {Text("hello"), Text("")};
  inputs.push_back(EmbeddingInput{{{EmbeddingPart::Type::kText, "aa"},
                                   {EmbeddingPart::Type::kText, "aa"}}});
  inputs.push_back(Text("x<|endoftext|>"));
  inputs.push_back(Text("b aaa"));
  Check(PrepareInputs(tokenizer, inputs, false, &prepared, &failed, &error) ==
            PrepareStatus::kOk,
        "basic inputs refused: " + error);
  Check(prepared.sequences.size() == 5 && prepared.token_counts.size() == 5,
        "wrong number of sequences");
  Check(prepared.sequences[0] == WithEos(Bytes("hello")), "hello");
  Check(prepared.token_counts[0] == 6, "hello count");
  Check(prepared.sequences[1] == std::vector<std::uint32_t>{kEos}, "empty input");
  Check(prepared.token_counts[1] == 1, "empty count");
  Check(prepared.sequences[2] == (std::vector<std::uint32_t>{kPair, kPair, kEos}),
        "text parts are not concatenated before tokenizing");
  Check(prepared.sequences[3] == (std::vector<std::uint32_t>{'x', kEos, kEos}),
        "special text is not parsed");
  // "b", " aaa" -> b | ' ' aa a  (the space starts the second word).
  Check(prepared.sequences[4] ==
            (std::vector<std::uint32_t>{'b', ' ', kPair, 'a', kEos}),
        "pre-tokenizer split or merge order");
}

void Limits(const Tokenizer& tokenizer) {
  PreparedInputs prepared;
  std::size_t failed = 99;
  std::string error;

  // 8191 letters + EOS = 8192 ids: fits.
  std::vector<EmbeddingInput> inputs = {Text(std::string(8191, 'b'))};
  Check(PrepareInputs(tokenizer, inputs, false, &prepared, &failed, &error) ==
            PrepareStatus::kOk,
        "8192 ids refused");
  Check(prepared.sequences[0].size() == 8192, "8192 ids not kept");

  // 8192 letters + EOS = 8193 ids: too long, reported at its index.
  inputs = {Text("ok"), Text(std::string(8192, 'b'))};
  Check(PrepareInputs(tokenizer, inputs, false, &prepared, &failed, &error) ==
            PrepareStatus::kInputTooLong,
        "8193 ids accepted without truncation");
  Check(failed == 1, "too-long index is " + std::to_string(failed));

  // Truncation keeps the first 8191 ids and the EOS.
  Check(PrepareInputs(tokenizer, inputs, true, &prepared, &failed, &error) ==
            PrepareStatus::kOk,
        "truncation failed");
  const auto& cut = prepared.sequences[1];
  Check(cut.size() == 8192, "truncated length " + std::to_string(cut.size()));
  Check(cut.back() == kEos && cut[8190] == 'b', "truncated tail");
  Check(prepared.token_counts[1] == 8192, "truncated count");

  // Above the byte bound the input is refused before tokenizing; with
  // truncation it is tokenized and cut.
  const std::size_t limit = qwen3_embedding::ByteLimit(tokenizer);
  Check(limit == 8192 * tokenizer.max_token_bytes() * 4, "byte limit");
  inputs = {Text(std::string(limit + 1, 'b'))};
  failed = 99;
  Check(PrepareInputs(tokenizer, inputs, false, &prepared, &failed, &error) ==
            PrepareStatus::kInputTooLong,
        "input above the byte bound accepted");
  Check(failed == 0, "byte-bound index");
  Check(PrepareInputs(tokenizer, inputs, true, &prepared, &failed, &error) ==
            PrepareStatus::kOk,
        "truncating an input above the byte bound failed");
  Check(prepared.sequences[0].size() == 8192 && prepared.sequences[0].back() == kEos,
        "byte-bound truncation");
}

void Refusals(const Tokenizer& tokenizer) {
  PreparedInputs prepared;
  std::size_t failed = 99;
  std::string error;
  for (const auto type : {EmbeddingPart::Type::kImage, EmbeddingPart::Type::kAudio,
                          EmbeddingPart::Type::kVideo}) {
    std::vector<EmbeddingInput> inputs = {
        Text("fine"),
        EmbeddingInput{{{EmbeddingPart::Type::kText, "look: "},
                        {type, "data:image/png;base64,AAAA"}}}};
    failed = 99;
    error.clear();
    Check(PrepareInputs(tokenizer, inputs, true, &prepared, &failed, &error) ==
              PrepareStatus::kInvalidInput,
          "a media part was accepted");
    Check(failed == 1, "media index");
    Check(error.find("text only") != std::string::npos, "media error: " + error);
  }
  // F5 80 80 80 decodes above U+10FFFF; llama.cpp throws on it too.
  std::vector<EmbeddingInput> inputs = {Text(std::string("\xf5\x80\x80\x80", 4))};
  failed = 99;
  Check(PrepareInputs(tokenizer, inputs, false, &prepared, &failed, &error) ==
            PrepareStatus::kInvalidInput,
        "an untokenizable input was accepted");
  Check(failed == 0, "untokenizable index");
  Check(error.find("cannot be tokenized") != std::string::npos,
        "untokenizable error: " + error);
}

void Threads(const Tokenizer& tokenizer) {
  std::vector<EmbeddingInput> inputs;
  for (int i = 0; i < 64; ++i) {
    inputs.push_back(Text("aaa b" + std::to_string(i) + std::string(i * 7, 'a')));
  }
  PreparedInputs expected;
  std::size_t failed = 0;
  Check(PrepareInputs(tokenizer, inputs, false, &expected, &failed, nullptr) ==
            PrepareStatus::kOk,
        "thread reference");
  std::vector<PreparedInputs> results(8);
  std::vector<std::thread> threads;
  for (auto& result : results) {
    threads.emplace_back([&] {
      std::size_t index = 0;
      (void)PrepareInputs(tokenizer, inputs, false, &result, &index, nullptr);
    });
  }
  for (auto& thread : threads) {
    thread.join();
  }
  for (const auto& result : results) {
    Check(result.sequences == expected.sequences, "threads disagree");
  }
}

}  // namespace

int main() {
  qwen3_embedding::testing::TestName() = "inputs_test";
  const Tokenizer tokenizer = TinyTokenizer();
  Basics(tokenizer);
  Limits(tokenizer);
  Refusals(tokenizer);
  Threads(tokenizer);
  std::cout << "inputs_test: ok\n";
  return 0;
}
