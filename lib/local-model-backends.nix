# The catalog's backend vocabulary. `local` is the live set: engines
# modules/local-models.nix can render a llama-swap cmd for (asserted 1:1
# against the renderer table).
#
# There is no `appliances` kind any more. It held exactly one member, "npu"
# (FastFlowLM on the XDNA2 NPU), and existed so the schema could name a backend
# the proxy deliberately did not manage. The NPU was decommissioned permanently
# 2026-08-29 and the tier itself was retired 2026-08-31 (#270): a category with
# zero live members earns no enum branch. `retired` keeps the value legal ONLY
# so the four archived FLM rows in lib/local-models.nix stay honest history —
# a status = "retired" row recording backend = "npu" is a fact about the past,
# not a servable configuration. modules/local-models.nix asserts that no
# non-retired row may use a retired backend value.
{
  local = [
    "rocm"
    "vulkan"
    "ds4"
    "vllm"
    "mlx"
  ];
  retired = [ "npu" ];
}
