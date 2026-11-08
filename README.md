# dotfiles

One flake for the whole distribution. NixOS + Home Manager configure every
personal machine from one reviewed source of truth.

## Hosts

The flake exports these NixOS host configurations:

| Host | Hardware | Role |
|---|---|---|
| `strix-coordinator` | Framework Desktop, AMD Strix Halo | Headless compute, wired 10.42.0.2; Gufo, the fleet's local model endpoint on :8731, and on-demand Immich ML |
| `strix-worker` | Framework Desktop, AMD Strix Halo | Headless compute, wired 10.42.0.5; Gufo's second TP2 rank, and DeepSeek V4.1 on ds4 (:8732, started by hand) |
| `nas` | UGREEN NASync DXP2800 GT, AMD R2514 | Wired 10.42.0.1: storage, DNS, media, and the closet's Tailscale subnet router |
| `client` | ASUS Zenbook Duo | Physical Domicile desktop; Huion, Magic Trackpad and remote Herdr projector |

Strix and NAS plug into the BE550, with Freebox upstream. Strix's public
Internet route goes directly through BE550; private service DNS uses NAS.
`coordinator` remains an SSH/LAN compatibility alias for `strix` during migration.
strix-worker returned on 2026-10-23 (Tom). See `docs/closet-cutover.md` for the staged rollout.

```
flake.nix        four NixOS hosts wired through one mkHost
modules/         common.nix (every host) + strix.nix (AMD Strix Halo compute host)
hosts/           one module per machine
home/            home-manager: typed nix (home.nix, nvim.nix) + RAW out-of-store
                 configs (kitty, fish, nvim lua) linked via mkOutOfStoreSymlink
overlays/ pkgs/  custom packages (mactahoe themes, …)
docs/local-ai/  Gufo (:8731) and ds4 (:8732), the model catalogue and per-host wanted sets
docs/old/       archival stub indexing retired docs in Git history
```

## Free model lanes in dsh (Gemini, OpenCode Zen, Groq, Mistral, Cohere, NVIDIA, Cloudflare, Hugging Face, Cerebras, Vercel)

The Qwen token plan that used to sit here is gone: the QwenCloud account was
closed on 2026-11-01 (`REKEY.md`), so its dsh route was deleted. Since
2026-11-03 the keyed routes are the free tiers, one agenix ciphertext per
account (`secrets/gemini-api-key-{1,2,3}.age`, `secrets/opencode-zen-key-{1,2,3,4}.age`,
NAS brain tier, mode 400):

- Gemini through llm-pi-ai's native `google` route, the default
  (`google/gemini-3.8-flash`); `DSH_KEY_SLOT=<1|2|3>` picks the account.
- OpenCode Zen's `-free` models through jiesou's provider plugin, in the
  hand-run `dsh zen` profile only; `DSH_KEY_SLOT=<1..4>` picks the org, a
  slot past every list sends Zen's anonymous `public` bearer.
- `DSH_ROUTE=<gemini|gemini-pro|gemini-lite|gufo|zen-deepseek|zen-glm>` picks
  the model per run; there is no fallback list, a 429 means another slot.
- Since issue 687 (same day): Groq (`DSH_ROUTE=groq`, `groq-oss`; three
  keys), Mistral (`mistral`, `codestral`; three keys, Experiment plan),
  Cohere (`cohere`; five trial keys, hand-declared on its OpenAI-compatible
  endpoint), NVIDIA NIM (`nvidia`, `nvidia-deepseek`; one key), Cloudflare
  Workers AI (`cloudflare`, `cloudflare-deepseek`; one token and its account
  id), Hugging Face (`huggingface`; one token, 402 until credits), Cerebras
  (`cerebras`, `cerebras-oss`; one key, the largest allowance) and Vercel AI
  Gateway (`vercel`; one key, 0 credits today). Eighteen more ciphertexts
  (`secrets/{groq,mistral,cohere}-api-key-N.age`, `nvidia-api-key-1`,
  `cloudflare-workers-ai-token-1`, `cloudflare-account-id`,
  `huggingface-inference-token-1`, `cerebras-api-key-1`,
  `vercel-ai-gateway-key-1`, and `grok-api-key-1` stored with no reader),
  same tier and mode. `DSH_KEY_SLOT=<n>`
  picks account n of every lane at once; a slot past a lane's list leaves
  that lane keyless with one stderr line. Gemini stays the default.

Wiring: the dsh wrapper (`pkgs/dsh`, `home/dsh.nix`) reads ONE file per
lane per run into its variable (`GEMINI_API_KEY`, `OPENCODE_ZEN_FREE_API_KEY`,
`GROQ_API_KEY`, `MISTRAL_API_KEY`, `COHERE_API_KEY`, `NVIDIA_API_KEY`,
`CLOUDFLARE_WORKERS_AI_TOKEN` with `CLOUDFLARE_ACCOUNT_ID`, `HF_TOKEN`,
`CEREBRAS_API_KEY`, `AI_GATEWAY_API_KEY`) for
the dsh process only, never for a config dump, after unsetting all of them
and the login shell's full-scope `CLOUDFLARE_API_TOKEN`. dsh strips credential-shaped names from every child
it spawns, and its sandbox runner masks `/run/agenix`. Both tiers may use
prompts for training and review: nothing sensitive goes through them (Gufo
is the lane for that). The ledger, the measured facts, the plugin's
mechanism (it impersonates the OpenCode CLI) and the first commands are in
`docs/free-lanes.md`.

Dsh follows the fleet's brain role to the NAS with its Nix-pinned plugins.
Gemini is the default. The local `gufo` route reads
`lib/local-model.nix` for its endpoint and exact served model IDs
(`http://strix-coordinator:8731`, `qwen3.8-flash-next`, with `qwen3.8-27b`
as its alternate). Local DeepSeek is retired and absent from DSH's model
catalog; remote DeepSeek API routes remain available. The DeepSeek harness replaces
the retired Halogen runtime (Tom, 2026-10-25).

## OpenRouter key

> **Key created 2026-09-29 · $40 of one-time credits (Tom, 09-16: "$40 before October").**

Key at `secrets/openrouter-token.age` (NAS brain tier), delivered to
`/run/agenix/openrouter-token`. No harness routes to it since pi was retired
(2026-10-25); `seats` reads it for the OpenRouter credit row. The free stealth
model the key also reached has been withdrawn, and the openrouter-free lane is
parked (AGENTS.md). A dsh route for the key, or retiring it, is Tom's call.
Check what is left with `curl -s https://openrouter.ai/api/v1/credits -H "Authorization: Bearer $(cat /run/agenix/openrouter-token)"`.

## Branches

- **`main`** — canonical and NixOS-only.
- **`archive/*`** — read-only historical lineage; never used for deployment.

## Usage

```sh
# on a NixOS host
sudo nixos-rebuild switch --flake .#<host>
```
