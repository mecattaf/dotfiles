// Gate G1: the tokenizer, loaded from the Library GGUF, must give exactly the
// ids llama.cpp b9925 gives on the embedding path for every case of
// tests/fixtures/tokenizer_golden.json (hand-written, random and raw-byte
// cases; special tokens parsed, no BOS, EOS appended). Any mismatch fails;
// the first 20 are printed. Pieces are compared as a second check.
//
// Needs QWEN3_EMBEDDING_MODEL; exits 77 (skipped) without it or without the
// fixture.

#include <algorithm>
#include <cstdint>
#include <gufo/ext/gguf_reader.hpp>
#include <gufo/ext/json.hpp>
#include <iostream>
#include <map>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

#include "src/tokenizer/tokenizer.hpp"
#include "tests/support.hpp"

namespace {

using qwen3_embedding::Tokenizer;
using qwen3_embedding::testing::Check;

std::string Join(const std::vector<std::uint32_t>& ids, std::size_t limit = 40) {
  std::ostringstream out;
  out << '[';
  for (std::size_t i = 0; i < ids.size() && i < limit; ++i) {
    out << (i ? "," : "") << ids[i];
  }
  if (ids.size() > limit) {
    out << ",... (" << ids.size() << " ids)";
  }
  out << ']';
  return out.str();
}

std::string FromHex(const std::string& hex) {
  Check(hex.size() % 2 == 0, "odd hex string in fixture");
  std::string bytes;
  for (std::size_t i = 0; i < hex.size(); i += 2) {
    bytes.push_back(static_cast<char>(std::stoi(hex.substr(i, 2), nullptr, 16)));
  }
  return bytes;
}

void Sanity(const Tokenizer& tokenizer) {
  const struct {
    std::string text;
    std::vector<std::uint32_t> ids;
  } cases[] = {
      {"hello world", {14990, 1879, 151643}},
      {"don't 1234 ABC-def_ghi",
       {15007, 944, 220, 16, 17, 18, 19, 19360, 28799, 62, 75076, 151643}},
      {"literal <|endoftext|> and <|im_end|> inside text",
       {35785, 220, 151643, 323, 220, 151645, 4766, 1467, 151643}},
      {"", {151643}},
  };
  for (const auto& entry : cases) {
    const auto ids = tokenizer.Encode(entry.text);
    Check(ids == entry.ids, "'" + entry.text + "' gives " + Join(ids) +
                                ", expected " + Join(entry.ids));
  }
  Check(tokenizer.eos_id() == 151643, "eos id");
  Check(tokenizer.vocab_size() == 151665, "vocab size");
  std::cout << "tokenizer_test: sanity cases ok; " << tokenizer.special_tokens().size()
            << " special tokens, max token " << tokenizer.max_token_bytes()
            << " bytes\n";
}

struct Case {
  std::string id;
  std::string group;
  std::string category;
  std::string text;
  std::vector<std::uint32_t> ids;
  std::vector<std::string> pieces;
};

std::vector<Case> ReadCases(const gufo::json::Value& root) {
  const auto* cases = root.find("cases");
  Check(cases != nullptr && cases->is_array(), "fixture has no cases array");
  std::vector<Case> out;
  for (const auto& item : cases->items()) {
    Case entry;
    entry.id = item.member_str("id", "");
    entry.group = item.member_str("group", "");
    entry.category = item.member_str("category", "");
    if (const auto* hex = item.find("bytes_hex"); hex != nullptr) {
      entry.text = FromHex(hex->str());
    } else {
      const auto* text = item.find("text");
      Check(text != nullptr && text->is_string(), entry.id + " has no text");
      entry.text = text->str();
    }
    const auto* ids = item.find("ids");
    Check(ids != nullptr && ids->is_array(), entry.id + " has no ids");
    for (const auto& id : ids->items()) {
      entry.ids.push_back(static_cast<std::uint32_t>(id.as_size()));
    }
    if (const auto* pieces = item.find("pieces"); pieces != nullptr) {
      for (const auto& piece : pieces->items()) {
        if (piece.is_string()) {
          entry.pieces.push_back(piece.str());
        } else {
          std::string bytes;
          for (const auto& byte : piece.items()) {
            bytes.push_back(static_cast<char>(byte.as_size()));
          }
          entry.pieces.push_back(std::move(bytes));
        }
      }
    } else if (const auto* hexes = item.find("pieces_hex"); hexes != nullptr) {
      for (const auto& piece : hexes->items()) {
        entry.pieces.push_back(FromHex(piece.str()));
      }
    }
    out.push_back(std::move(entry));
  }
  return out;
}

int Golden(const Tokenizer& tokenizer, const std::filesystem::path& path) {
  const auto text = qwen3_embedding::testing::ReadFile(path);
  if (!text.has_value()) {
    std::cout << "tokenizer_test: fixture " << path << " missing; G1 pending\n";
    return qwen3_embedding::testing::kSkip;
  }
  const gufo::json::Value root = gufo::json::parse(*text);
  Check(root.member_size("eos_id", 0) == 151643, "fixture eos_id");

  // The special-token set must be the one llama.cpp builds.
  if (const auto* special = root.find("special_tokens"); special != nullptr) {
    std::set<std::uint32_t> expected;
    for (const auto& id : special->find("ids")->items()) {
      expected.insert(static_cast<std::uint32_t>(id.as_size()));
    }
    const std::set<std::uint32_t> actual(tokenizer.special_tokens().begin(),
                                         tokenizer.special_tokens().end());
    Check(actual == expected, "special tokens differ from the fixture's (" +
                                  std::to_string(actual.size()) + " vs " +
                                  std::to_string(expected.size()) + ")");
  }

  const std::vector<Case> cases = ReadCases(root);
  std::map<std::string, std::pair<std::size_t, std::size_t>> by_group;
  std::size_t mismatches = 0;
  std::size_t piece_mismatches = 0;
  std::size_t total_ids = 0;
  for (const Case& entry : cases) {
    auto& [passed, seen] = by_group[entry.group];
    ++seen;
    std::vector<std::uint32_t> ids;
    std::string failure;
    try {
      ids = tokenizer.Encode(entry.text);
    } catch (const std::exception& error) {
      failure = error.what();
    }
    total_ids += entry.ids.size();
    if (!failure.empty() || ids != entry.ids) {
      if (++mismatches <= 20) {
        std::size_t at = 0;
        while (at < ids.size() && at < entry.ids.size() && ids[at] == entry.ids[at]) {
          ++at;
        }
        std::cout << "MISMATCH " << entry.id << " (" << entry.category << "): "
                  << (failure.empty() ? "" : "threw '" + failure + "' ")
                  << "first difference at " << at << "\n  got      "
                  << Join(ids) << "\n  expected " << Join(entry.ids) << '\n';
      }
      continue;
    }
    ++passed;
    if (!entry.pieces.empty()) {
      bool same = entry.pieces.size() == ids.size();
      for (std::size_t i = 0; same && i < ids.size(); ++i) {
        same = tokenizer.Piece(ids[i]) == entry.pieces[i];
      }
      if (!same && ++piece_mismatches <= 5) {
        std::cout << "PIECE MISMATCH " << entry.id << '\n';
      }
    }
  }

  // Cases llama.cpp itself cannot tokenize must throw here too.
  std::size_t oracle_failures = 0;
  if (const auto* checks = root.find("checks"); checks != nullptr) {
    if (const auto* failures = checks->find("oracle_failures");
        failures != nullptr && failures->is_array()) {
      for (const auto& failure : failures->items()) {
        const std::string bytes = FromHex(failure.member_str("bytes_hex", ""));
        bool threw = false;
        try {
          (void)tokenizer.Encode(bytes);
        } catch (const std::invalid_argument&) {
          threw = true;
        }
        Check(threw, "oracle failure " + failure.member_str("name", "") +
                         " was tokenized");
        ++oracle_failures;
      }
    }
  }

  // Encode is const and stateless: threads sharing it agree with the
  // serial results.
  {
    std::vector<std::vector<std::uint32_t>> serial(cases.size());
    for (std::size_t i = 0; i < cases.size(); ++i) {
      try {
        serial[i] = tokenizer.Encode(cases[i].text);
      } catch (const std::exception&) {
      }
    }
    std::vector<std::thread> threads;
    std::vector<std::size_t> disagreements(4, 0);
    for (std::size_t t = 0; t < disagreements.size(); ++t) {
      threads.emplace_back([&, t] {
        for (std::size_t round = 0; round < 2; ++round) {
          for (std::size_t i = t; i < cases.size(); i += 2) {
            std::vector<std::uint32_t> ids;
            try {
              ids = tokenizer.Encode(cases[i].text);
            } catch (const std::exception&) {
            }
            disagreements[t] += ids != serial[i] ? 1 : 0;
          }
        }
      });
    }
    for (auto& thread : threads) {
      thread.join();
    }
    for (const auto count : disagreements) {
      Check(count == 0, "concurrent encoding disagrees with serial encoding");
    }
  }

  std::cout << "tokenizer_test: G1 " << cases.size() << " cases, " << total_ids
            << " expected ids, " << mismatches << " mismatches;";
  for (const auto& [group, counts] : by_group) {
    std::cout << ' ' << group << ' ' << counts.first << '/' << counts.second;
  }
  std::cout << "; piece mismatches " << piece_mismatches
            << "; oracle failures reproduced " << oracle_failures << '\n';
  if (mismatches != 0) {
    std::cout << "FAIL tokenizer_test: G1 has " << mismatches << " mismatches\n";
    return 1;
  }
  Check(piece_mismatches == 0, "pieces differ from llama.cpp's");
  return 0;
}

}  // namespace

int main() {
  qwen3_embedding::testing::TestName() = "tokenizer_test";
  const auto model = qwen3_embedding::testing::ModelPath();
  if (!model.has_value()) {
    std::cout << "tokenizer_test: QWEN3_EMBEDDING_MODEL unset; skipped\n";
    return qwen3_embedding::testing::kSkip;
  }
  std::string error;
  const auto reader = gufo::core::GgufReader::OpenFile(*model, &error);
  Check(reader != nullptr, "cannot open " + model->string() + ": " + error);
  const auto tokenizer = Tokenizer::Load(*reader, &error);
  Check(tokenizer.has_value(), "tokenizer load failed: " + error);
  Sanity(*tokenizer);
  return Golden(*tokenizer,
                qwen3_embedding::testing::FixtureDir() / "tokenizer_golden.json");
}
