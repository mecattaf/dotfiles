{
  lib,
  packages,
}:

let
  offlineModelEnv = [
    "HF_HOME=/var/cache/llama-swap/huggingface"
    "HF_HUB_OFFLINE=1"
    "TRANSFORMERS_OFFLINE=1"
  ];
in
{
  rocm =
    { modelPath, ... }:
    {
      cmd = "${packages.llamaRocm}/bin/llama-server --port \${PORT} -m ${lib.escapeShellArg (toString modelPath)}";
    };
  vulkan =
    { modelPath, ... }:
    {
      cmd = "${packages.llamaVulkan}/bin/llama-server --port \${PORT} -m ${lib.escapeShellArg (toString modelPath)}";
    };
  ds4 =
    { modelPath, ... }:
    {
      cmd = "${packages.ds4}/bin/ds4-server --host 127.0.0.1 --port \${PORT} -m ${lib.escapeShellArg (toString modelPath)}";
    };
  vllm =
    {
      deployment,
      modelDirectory,
      ...
    }:
    {
      cmd = "${packages.vllm}/bin/vllm serve ${lib.escapeShellArg (toString modelDirectory)} --host 127.0.0.1 --port \${PORT} --served-model-name ${lib.escapeShellArg deployment.model}";
      env = offlineModelEnv ++ [
        "TORCHINDUCTOR_CACHE_DIR=/var/cache/llama-swap/torchinductor"
        "TRITON_CACHE_DIR=/var/cache/llama-swap/triton"
        "VLLM_CACHE_ROOT=/var/cache/llama-swap/vllm"
        "VLLM_DO_NOT_TRACK=1"
        "VLLM_NO_USAGE_STATS=1"
      ];
      useModelName = deployment.model;
    };
  mlx =
    {
      modelDirectory,
      ...
    }:
    {
      cmd = "${packages.mlxLm}/bin/mlx_lm.server --model ${lib.escapeShellArg (toString modelDirectory)} --host 127.0.0.1 --port \${PORT}";
      env = offlineModelEnv;
      # mlx-lm maps this sentinel to the immutable --model directory. Without
      # the rewrite it treats the public roster ID as a Hugging Face repo.
      useModelName = "default_model";
    };
}
