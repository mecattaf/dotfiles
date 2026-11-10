# Qwen3-Embedding-8B (Q8_0 GGUF) text embeddings extension.
#
# Host library: GGUF config and probe, weight views, the Qwen2 byte-level BPE
# tokenizer (a port of llama.cpp's), input preparation and the batch
# scheduler. It builds and probes without a GPU.
# HIP library: the encoder runtime, its kernels and the provider runner.

gufo_extension_target(
  NAME gufo_qwen3_embedding
  SOURCES
    src/config.cpp
    src/weights.cpp
    src/probe.cpp
    src/tokenizer/unicode.cpp
    src/tokenizer/unicode_data.cpp
    src/tokenizer/tokenizer.cpp
    src/inputs.cpp
    src/batch_scheduler.cpp
    src/extension.cpp
  LINK_LIBRARIES
    gufo_ext_runtime
    Threads::Threads
)

if(TARGET gufo_qwen3_embedding)
  target_include_directories(gufo_qwen3_embedding PUBLIC
    "$<BUILD_INTERFACE:${GUFO_EXTENSION_BUILD_ROOT}>"
  )
  if(ENGINE_ENABLE_HIP)
    target_compile_definitions(gufo_qwen3_embedding PRIVATE ENGINE_ENABLE_HIP=1)
  endif()
endif()

gufo_extension_target(
  NAME gufo_qwen3_embedding_hip
  SOURCES
    src/hip/encoder_runtime.cpp
    src/provider.cpp
  LINK_LIBRARIES
    gufo_qwen3_embedding
    gufo_ext_runtime
    hip::host
    roc::hipblas
    roc::hipblaslt
    Threads::Threads
)

if(TARGET gufo_qwen3_embedding_hip)
  gufo_extension_hip_sources(gufo_qwen3_embedding_hip
    SOURCES
      src/hip/ops.hip
  )
  target_compile_definitions(gufo_qwen3_embedding_hip PRIVATE ENGINE_ENABLE_HIP=1)
  target_compile_options(gufo_qwen3_embedding_hip PRIVATE
    $<$<COMPILE_LANGUAGE:CXX>:-O3>
    $<$<COMPILE_LANGUAGE:HIP>:-O3>
    $<$<COMPILE_LANGUAGE:HIP>:-Wno-unused-command-line-argument>
  )
  target_include_directories(gufo_qwen3_embedding_hip PUBLIC
    "$<BUILD_INTERFACE:${GUFO_EXTENSION_BUILD_ROOT}>"
  )
endif()

# gufo_ext_runtime only declares the public services; tests are executables
# that stand apart from `gufo`, so they link the implementations too. Host
# tests need only the core services (GGUF reader); GPU tests add the HIP host.
set(_qwen3_embedding_test_libs gufo_ext_core)
set(_qwen3_embedding_gpu_test_libs gufo_ext_core)
if(ENGINE_ENABLE_HIP)
  list(APPEND _qwen3_embedding_gpu_test_libs gufo_ext_hip)
endif()

# Fixtures are compiled in; GUFO_FIXTURE_DIR overrides the directory. Tests
# that need the GGUF read its path from QWEN3_EMBEDDING_MODEL and exit 77
# (skipped) without it.
set(_qwen3_embedding_fixture_dir "${GUFO_EXTENSION_BUILD_ROOT}/tests/fixtures")

function(_qwen3_embedding_cpu_test name source label)
  gufo_extension_target(
    NAME ${name}
    SOURCES
      ${source}
    LINK_LIBRARIES
      gufo_qwen3_embedding
      gufo_ext_runtime
      ${_qwen3_embedding_test_libs}
      Threads::Threads
  )
  if(TARGET ${name})
    target_compile_definitions(${name} PRIVATE
      "QWEN3_EMBEDDING_FIXTURE_DIR=\"${_qwen3_embedding_fixture_dir}\"")
    add_test(NAME qwen3_embedding.${label} COMMAND ${name})
    set_tests_properties(qwen3_embedding.${label} PROPERTIES
      LABELS "qwen3-embedding;cpu;${label}"
      SKIP_RETURN_CODE 77)
  endif()
endfunction()

_qwen3_embedding_cpu_test(qwen3_embedding_config_test tests/config_test.cpp config)
_qwen3_embedding_cpu_test(qwen3_embedding_tokenizer_test tests/tokenizer_test.cpp tokenizer)
_qwen3_embedding_cpu_test(qwen3_embedding_inputs_test tests/inputs_test.cpp inputs)
_qwen3_embedding_cpu_test(qwen3_embedding_batch_scheduler_test tests/batch_scheduler_test.cpp batch_scheduler)
_qwen3_embedding_cpu_test(qwen3_embedding_probe_test tests/probe_test.cpp probe)

function(_qwen3_embedding_gpu_test name source label)
  gufo_extension_target(
    NAME ${name}
    SOURCES
      ${source}
    LINK_LIBRARIES
      gufo_qwen3_embedding_hip
      gufo_qwen3_embedding
      gufo_ext_runtime
      ${_qwen3_embedding_gpu_test_libs}
      hip::host
      Threads::Threads
  )
  if(TARGET ${name})
    target_compile_definitions(${name} PRIVATE
      ENGINE_ENABLE_HIP=1
      "QWEN3_EMBEDDING_FIXTURE_DIR=\"${_qwen3_embedding_fixture_dir}\"")
    add_test(NAME qwen3_embedding.${label} COMMAND ${name})
    set_tests_properties(qwen3_embedding.${label} PROPERTIES
      LABELS "qwen3-embedding;hip;gpu;gfx1151;${label}"
      SKIP_RETURN_CODE 77
      RUN_SERIAL TRUE)
  endif()
endfunction()

_qwen3_embedding_gpu_test(qwen3_embedding_ops_hip_test tests/ops_hip_test.cpp ops_hip)
_qwen3_embedding_gpu_test(qwen3_embedding_golden_hip_test tests/golden_hip_test.cpp golden_hip)

install(FILES
  "${GUFO_EXTENSION_BUILD_ROOT}/LICENSE"
  "${GUFO_EXTENSION_BUILD_ROOT}/THIRD_PARTY_NOTICES.md"
  DESTINATION share/licenses/gufo/extensions/qwen3_embedding)
