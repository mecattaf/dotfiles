{
  imageName = "ghcr.io/asf0/strix-vllm";
  # Architecture-specific manifest, not a mutable tag or the multi-arch index.
  imageDigest = "sha256:6ac2fe8bcf1eeed25bd8ed2d7129890f74e7a3066954d51e83ce99f0c4c6514a";
  archiveHash = "sha256-QY6grWN4UHDouSAkH/8VQrXkPK7bMXRVd+AGV2b9NYM=";
  vllmRevision = "efdfdf954bd7d3ae7dfa2ab4702b2317f9d20c42";
  libstrixRevision = "d7862c63cf7fa453780032b966363b6fb5d95121";
  upstreamPrefixPatch = "dfa830766b0d082870ff2f64b0fdc5ab0daaab49";
  modelRevision = "52ba9e7a00402f9560c7fba8c039608e7ddee7fb";
  torch = "2.14.0+rocm10.1.0";
  python = "3.14";
  rocm = "10.1.0";
  # Complete compressed layer descriptors from the pinned registry manifest.
  manifest = builtins.fromJSON (builtins.readFile ./image-manifest.json);
  overlayFiles = [
    "vllm/entrypoints/openai/decisions/strategies.py"
    "vllm/entrypoints/generate/structured_decisions/serving.py"
    "vllm/model_executor/models/config.py"
    "vllm/model_executor/models/d3.py"
    "vllm/transformers_utils/model_arch_config_convertor.py"
    "vllm/v1/worker/gpu/model_states/default.py"
  ];
}
