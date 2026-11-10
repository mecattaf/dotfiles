// Shared helpers for the host tests: checks, the GGUF path, fixtures and a
// small GGUF writer for synthetic probe files.
#ifndef QWEN3_EMBEDDING_TESTS_SUPPORT_HPP_
#define QWEN3_EMBEDDING_TESTS_SUPPORT_HPP_

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <optional>
#include <string>
#include <string_view>
#include <unistd.h>
#include <utility>
#include <variant>
#include <vector>

#ifndef QWEN3_EMBEDDING_FIXTURE_DIR
#define QWEN3_EMBEDDING_FIXTURE_DIR "tests/fixtures"
#endif

namespace qwen3_embedding::testing {

inline constexpr int kSkip = 77;

inline const char*& TestName() {
  static const char* name = "qwen3_embedding_test";
  return name;
}

inline void Check(bool condition, std::string_view message) {
  if (!condition) {
    std::cerr << "FAIL " << TestName() << ": " << message << '\n';
    std::exit(1);
  }
}

/// The Library GGUF from QWEN3_EMBEDDING_MODEL, or nullopt when unset or
/// missing (tests that need it then skip).
inline std::optional<std::filesystem::path> ModelPath() {
  const char* value = std::getenv("QWEN3_EMBEDDING_MODEL");
  if (value == nullptr || *value == '\0') {
    return std::nullopt;
  }
  std::filesystem::path path(value);
  std::error_code error;
  if (!std::filesystem::is_regular_file(path, error)) {
    return std::nullopt;
  }
  return path;
}

inline std::filesystem::path FixtureDir() {
  if (const char* value = std::getenv("GUFO_FIXTURE_DIR");
      value != nullptr && *value != '\0') {
    return value;
  }
  return QWEN3_EMBEDDING_FIXTURE_DIR;
}

inline std::optional<std::string> ReadFile(const std::filesystem::path& path) {
  std::ifstream input(path, std::ios::binary);
  if (!input) {
    return std::nullopt;
  }
  return std::string(std::istreambuf_iterator<char>(input),
                     std::istreambuf_iterator<char>());
}

/// A fresh directory under the system temp dir, removed on destruction.
class TempDir {
public:
  explicit TempDir(std::string_view tag) {
    path_ = std::filesystem::temp_directory_path() /
            (std::string("qwen3_embedding_") + std::string(tag) + "_" +
             std::to_string(::getpid()));
    std::filesystem::remove_all(path_);
    std::filesystem::create_directories(path_);
  }
  ~TempDir() {
    std::error_code ignored;
    std::filesystem::remove_all(path_, ignored);
  }
  TempDir(const TempDir&) = delete;
  TempDir& operator=(const TempDir&) = delete;
  [[nodiscard]] const std::filesystem::path& path() const { return path_; }

private:
  std::filesystem::path path_;
};

/// Writes GGUF v3 files with the value types the probe reads.
class GgufWriter {
public:
  struct StringArray {
    std::vector<std::string> values;
  };
  struct Int32Array {
    std::vector<std::int32_t> values;
  };
  using Value = std::variant<std::uint32_t, float, bool, std::string,
                             StringArray, Int32Array>;
  struct TensorSpec {
    std::string name;
    std::uint32_t type;  // ggml type id: 0 F32, 1 F16, 8 Q8_0
    std::vector<std::uint64_t> dims;
  };

  void Set(std::string key, Value value) {
    for (auto& entry : metadata_) {
      if (entry.first == key) {
        entry.second = std::move(value);
        return;
      }
    }
    metadata_.emplace_back(std::move(key), std::move(value));
  }
  void Erase(std::string_view key) {
    std::erase_if(metadata_, [&](const auto& entry) { return entry.first == key; });
  }
  void AddTensor(TensorSpec tensor) { tensors_.push_back(std::move(tensor)); }
  /// Changes the stored type of a tensor already added.
  bool SetTensorType(std::string_view name, std::uint32_t type) {
    for (auto& tensor : tensors_) {
      if (tensor.name == name) {
        tensor.type = type;
        return true;
      }
    }
    return false;
  }

  void Write(const std::filesystem::path& path) const {
    std::string out;
    Raw(out, "GGUF", 4);
    U32(out, 3);
    U64(out, tensors_.size());
    U64(out, metadata_.size());
    for (const auto& [key, value] : metadata_) {
      Str(out, key);
      std::visit([&](const auto& v) { Put(out, v); }, value);
    }
    std::uint64_t offset = 0;
    for (const auto& tensor : tensors_) {
      Str(out, tensor.name);
      U32(out, static_cast<std::uint32_t>(tensor.dims.size()));
      std::uint64_t elements = 1;
      for (const auto dim : tensor.dims) {
        U64(out, dim);
        elements *= dim;
      }
      U32(out, tensor.type);
      U64(out, offset);
      const std::uint64_t bytes = tensor.type == 0   ? elements * 4
                                  : tensor.type == 1 ? elements * 2
                                                     : elements / 32 * 34;
      offset += (bytes + 31) / 32 * 32;
    }
    out.resize((out.size() + 31) / 32 * 32, '\0');
    {
      std::ofstream file(path, std::ios::binary | std::ios::trunc);
      file.write(out.data(), static_cast<std::streamsize>(out.size()));
    }
    // The tensor data is all zeros: extend the file sparsely, so a
    // full-size synthetic checkpoint costs no disk.
    std::filesystem::resize_file(path, out.size() + offset);
  }

private:
  static void Raw(std::string& out, const void* data, std::size_t size) {
    out.append(static_cast<const char*>(data), size);
  }
  static void U32(std::string& out, std::uint32_t value) { Raw(out, &value, 4); }
  static void U64(std::string& out, std::uint64_t value) { Raw(out, &value, 8); }
  static void Str(std::string& out, std::string_view value) {
    U64(out, value.size());
    Raw(out, value.data(), value.size());
  }
  static void Put(std::string& out, std::uint32_t value) {
    U32(out, 4);
    U32(out, value);
  }
  static void Put(std::string& out, float value) {
    U32(out, 6);
    Raw(out, &value, 4);
  }
  static void Put(std::string& out, bool value) {
    U32(out, 7);
    const char byte = value ? 1 : 0;
    Raw(out, &byte, 1);
  }
  static void Put(std::string& out, const std::string& value) {
    U32(out, 8);
    Str(out, value);
  }
  static void Put(std::string& out, const StringArray& value) {
    U32(out, 9);
    U32(out, 8);
    U64(out, value.values.size());
    for (const auto& item : value.values) {
      Str(out, item);
    }
  }
  static void Put(std::string& out, const Int32Array& value) {
    U32(out, 9);
    U32(out, 5);
    U64(out, value.values.size());
    for (const auto item : value.values) {
      Raw(out, &item, 4);
    }
  }

  std::vector<std::pair<std::string, Value>> metadata_;
  std::vector<TensorSpec> tensors_;
};

}  // namespace qwen3_embedding::testing

#endif  // QWEN3_EMBEDDING_TESTS_SUPPORT_HPP_
