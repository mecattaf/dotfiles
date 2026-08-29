Managed local LLM and VLM calls go through llama-swap. Stable diffusion is
outside this LLM route.

**The NPU path is decommissioned — permanently, 2026-08-29.** FastFlowLM (`flm`)
and the request-scoped `utility-model` wrapper are no longer installed on any
host, and the XDNA2 NPU is not an inference target on either Strix Halo twin.
Both twins now boot with `amd_iommu=off`, which is by itself enough to make the
old NPU path unbootable; this is a decommission, not a pause. Do not add a `flm`
invocation, an `flm serve` unit, an NPU backend row, or a `utility` slot back.

Interactive local inference is the llama-swap GPU roster and nothing else. There
is no ad-hoc CLI escape hatch any more: if a model is not served by llama-swap,
it is not available locally.

The three retired FastFlowLM catalog rows keep `status = "retired"` with archive
receipts in `lib/local-models.nix`; the weights themselves survive under
`/mnt/nas/models/weights/flm/` and nowhere else.
