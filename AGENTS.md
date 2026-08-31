Managed local LLM and VLM calls go through llama-swap. Stable diffusion is
outside this LLM route.

**The NPU path is decommissioned — permanently, 2026-08-29.** FastFlowLM (`flm`)
is no longer installed on any host, and the XDNA2 NPU is not an inference target
on either Strix Halo twin. Both twins now boot with `amd_iommu=off`, which is by
itself enough to make the old NPU path unbootable; this is a decommission, not a
pause. Do not add a `flm` invocation, an `flm serve` unit, or an NPU backend row
back.

**The `utility` slot survived that decommission by moving to the GPU roster the
same day.** The stable ID `utility` now resolves to
`qwen36-35b-a3b-mtp-ud-q8-k-xl`, which llama-swap serves as `qwen3.6-35b-a3b`,
and the request-scoped `utility-model` wrapper — installed on the coordinator
only, since that is the one host whose llama-swap carries the row — forwards a
single chat-completions request to it. `/drain` and `/print` dial that seam and
are not retired. What must never come back is an NPU-backed utility deployment;
the slot itself is live.

Interactive local inference is the llama-swap GPU roster and nothing else. There
is no ad-hoc CLI escape hatch any more: if a model is not served by llama-swap,
it is not available locally.

The four retired FastFlowLM catalog rows keep `status = "retired"` with archive
receipts in `lib/local-models.nix`; the weights themselves survive under
`/mnt/nas/models/weights/flm/` and nowhere else. Since 2026-08-31 (#270) the
"appliance" tier is gone from the schema too: `modules/npu-llm.nix` is deleted,
`backendKinds` has no `appliances` kind, and `backend = "npu"` is legal only on
those retired archive rows. Do not reintroduce an appliance tier; a new engine
is a new `local` backend with a llama-swap command renderer, or it does not
serve interactively.
