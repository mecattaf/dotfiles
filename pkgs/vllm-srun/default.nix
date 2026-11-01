{
  lib,
  fetchFromGitHub,
  python313Packages,
  torchRocm,
}:
let
  py = python313Packages;
in
py.buildPythonPackage {
  pname = "vllm-srun";
  version = "0.2.0-unstable-2026-11-01";
  pyproject = true;

  # Native Decision 3.0 runtime, including d3-ultra's prefix_bidir attention,
  # state-once reads, Box and Track. This is not the vLLM causal-LLM server.
  src = fetchFromGitHub {
    owner = "vllm-project";
    repo = "semantic-router";
    rev = "62c4f39e35aa2dfe929eb18223a7509ebeff6563";
    hash = "sha256-rgbPde4ilD9lglQnqVpjvt+chWnqwUYoZwwLbFASAGM=";
  };
  sourceRoot = "source/src/model-runtime";

  build-system = [
    py.setuptools
    py.wheel
  ];
  dependencies = with py; [
    numpy
    safetensors
    tokenizers
    huggingface-hub
    starlette
    uvicorn
    uvloop
    httptools
    prometheus-client
    pyyaml
    backports-zstd
    pillow
    opencv-python-headless
    filelock
    fsspec
    jinja2
    networkx
    packaging
    sympy
    typing-extensions
  ];
  # The gfx1151 PyTorch/Triton wheel bundle is pinned by nix-strix-halo and
  # uses the same CPython 3.13 ABI. Keep it out of nixpkgs' Python fixpoint:
  # adding py.torch would pull a second, differently built ROCm stack.
  pythonRemoveDeps = [ "torch" ];
  makeWrapperArgs = [
    "--prefix"
    "PYTHONPATH"
    ":"
    torchRocm.sitePackages
    "--prefix"
    "LD_LIBRARY_PATH"
    ":"
    torchRocm.rocmRuntimeEnv.LD_LIBRARY_PATH
    "--set"
    "PYTHONNOUSERSITE"
    "1"
  ];
  pythonImportsCheck = [ "vllm_srun" ];
  doCheck = false;

  passthru = {
    inherit torchRocm;
    upstreamRevision = "62c4f39e35aa2dfe929eb18223a7509ebeff6563";
  };
  meta = {
    description = "Pinned native vLLM Semantic Router decision-model runtime for gfx1151";
    homepage = "https://github.com/vllm-project/semantic-router/tree/main/src/model-runtime";
    license = lib.licenses.asl20;
    platforms = [ "x86_64-linux" ];
    mainProgram = "vllm-srun";
  };
}
