Managed local LLM and VLM calls go through llama-swap. Ad-hoc NPU inference uses
`flm run <model>` directly; do not leave `flm serve` resident. Stable diffusion
is outside this LLM route.
