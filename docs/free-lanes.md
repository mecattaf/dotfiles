# Free model lanes in dsh

Issues: [#685](https://github.com/mecattaf/dotfiles/issues/685) (Gemini and
OpenCode Zen, the first batch) and
[#687](https://github.com/mecattaf/dotfiles/issues/687) (Groq, Mistral,
Cohere, NVIDIA, Cloudflare Workers AI, Hugging Face, Cerebras and Vercel AI
Gateway, plus a stored Grok key, the second batch, same day). Tom's rulings
(2026-11-03): the only harnesses are dsh, Claude Code and Codex, and API
providers go through dsh; for Zen's free models the known workaround plugin
jiesou/dsh-opencode-zen-free-provider replaces installing the OpenCode CLI;
model selection per provider must be straightforward, round-robin is a
nice-to-have. The QwenCloud account closed on 2026-11-01, so dsh's
`qwen-token-plan` route is deleted here.

Everything in this file is either MEASURED (the orchestrator, firsthand, on
the NAS on 2026-11-03) or a declaration one of the two PRs makes. Nothing
below claims a live smoke that has not run; section 6 lists what is still
unverified. Section 1b, the batch-2 rows of sections 3 to 5 and their
entries in section 6 come from issue 687.

## 1. Measured facts (2026-11-03)

- Gemini: three AI Studio API keys (three Google accounts). All three answer
  `GET https://generativelanguage.googleapis.com/v1beta/openai/models` with
  HTTP 200 and 60 models; the ids include gemini-3.8-flash, gemini-3.7-flash,
  gemini-3.6-flash, gemini-3.5-flash, gemini-3.5-flash-lite,
  gemini-3.1-pro-preview, gemini-3.1-flash-lite, gemini-3-flash-preview,
  gemini-2.5-pro, gemini-2.5-flash and gemini-2.5-flash-lite. That proves
  liveness only, not remaining quota.
- OpenCode Zen: four console orgs (key 1 GitHub-linked, keys 2–4
  Google-linked). From a plain OpenAI-compatible client at
  `https://opencode.ai/inference/openai/v1`: `pulse-alpha-free` answers HTTP
  403 `RegionError` ("This model is not available in your country", France)
  on all four keys; `deepseek-v4.1-flash-free` and `glm-5.3-flash-free`
  answer HTTP 429 `FreeUsageLimitError` ("Free usage limit reached. Free
  models work in OpenCode; subscribe to OpenCode Go") on all four keys at
  the FIRST call. The official OpenCode client 1.19.3 with key 2 ran
  `opencode run -m opencode/deepseek-v4.1-flash-free` and answered "ready".
  So the 429 is a client-fingerprint gate, not a usage limit, and the keys
  and models are live.
- The fleet dsh is 0.2.1-rc.2 (`pkgs.llm-agents.dsh`) and bundles
  `@earendil-works/pi-ai` 1.3.0. Its catalog ships a native `google`
  provider (api google-generative-ai, env `GEMINI_API_KEY`) listing all 11
  ids above; a hand-declared provider name can only use the openai-* or
  anthropic protocols, so the Gemini route must keep the name `google`. dsh
  has no multi-key support, no fallback list and no per-run model flag.
- The plugin's tag 0.1.28 is commit 7e779c73d2127327be529908ffc5a834934e8598
  (2026-10-22); `main` has the same tree. `fetchFromGitHub` hash
  `sha256-kH3IYGHA1zGsEYN4dXIR7VnQD5joezKBbxt0Nb0TOmA=` (from the builder's
  first fakeHash build). Its manifest's dsh peer ranges (`>=0.2.0-rc.2 <0.3`)
  pass dsh's compatibility preflight, which includes prereleases; the pi-ai
  peer range (`^0.85.1`) is not checked by dsh and every imported symbol
  exists in 1.3.0.
- Ciphertexts: `secrets/gemini-api-key-{1,2,3}.age` and
  `secrets/opencode-zen-key-{1,2,3,4}.age`, age, recipients admin + NAS host
  key (the brain-only tier). Delivered by `modules/secrets.nix` as
  `/run/agenix/<name>`, owner tom, mode 400. No key value appears in any
  file, log or test of this repository.

## 1b. Measured facts, second batch (2026-11-03, orchestrator)

- Groq: three keys, all valid at `https://api.groq.com/openai/v1`;
  `qwen/qwen3.8-27b` (131,072 context, the wanted model),
  `openai/gpt-oss-120b`, `openai/gpt-oss-20b` and whisper are listed and a
  chat answered. Per key, the `x-ratelimit` headers say 1,000 requests/day
  and 8,000 tokens/minute; the docs say 30 RPM and 200K tokens/day.
- Mistral: three keys, all valid at `https://api.mistral.ai/v1` (55 models,
  among them mistral-medium-latest, codestral-latest,
  magistral-medium-latest, mistral-small-latest, ministral-14b, devstral).
  Chat answers HTTP 429 with `x-ratelimit-limit-req-minute: 0`: the free
  Experiment plan is not yet activated on the accounts (Tom is doing that).
- Cohere: five keys, all valid at `https://api.cohere.com` (v2 chat). The
  OpenAI-compatible `https://api.cohere.com/compatibility/v1` answers 401
  without a key on `/models` and `/chat/completions`, so it exists; the
  docs page (docs.cohere.com/docs/compatibility-api) shows bearer auth,
  streaming, tools, no `store`, `reasoning_effort` only `none` or `high`,
  and names only `command-a-plus-05-2026` as a chat model; the other three
  ids (command-a-03-2025, command-a-reasoning-08-2025,
  command-r-plus-08-2024) were listed by the v2 API. Trial: 20 calls/minute,
  1,000/month per key.
- NVIDIA NIM: one key at `https://integrate.api.nvidia.com/v1`;
  `z-ai/glm-5.3-flash` answered with reasoning; `deepseek-ai/deepseek-v4.1-flash`,
  `nvidia/nemotron-3.5-super-vl-120b-a12b`, `nvidia/nemotron-3-super-120b-a12b`,
  `minimaxai/minimax-m3.1-flash` and `openai/gpt-oss-20b` are listed;
  `moonshotai/kimi-k2.6` is 404 for this account. About 40 RPM (docs,
  unconfirmed).
- Cloudflare Workers AI: token and account id valid; OpenAI-compatible base
  `https://api.cloudflare.com/client/v4/accounts/<ACCOUNT_ID>/ai/v1`;
  `@cf/qwen/qwen3.8-27b`, `@cf/deepseek-ai/deepseek-v4.1-flash-1017`,
  `@cf/deepseek-ai/deepseek-v4-pro-0813`, `@cf/openai/gpt-oss-120b`,
  `@cf/google/gemma-4-26b-a4b-it`, `@cf/meta/llama-4-scout-17b-16e-instruct`.
  10,000 neurons/day, reset 00:00 UTC.
- Hugging Face: a fine-grained token with `inference.serverless.write`;
  `https://router.huggingface.co/v1` lists 127 models, chat is HTTP 402 on a
  Free account (no included credits).
- Cerebras: one key (no per-key rotation), valid at `https://api.cerebras.ai/v1`;
  `qwen-3.8-27b` answered, `gpt-oss-120b` is listed. Headers: 450
  requests/minute, 648K requests/day, 150K tokens/minute, 216M tokens/day.
- Vercel AI Gateway: one key, valid at `https://ai-gateway.vercel.sh/v1`
  (OpenAI-compatible); credits balance 0 today, so no call can answer. No
  model was measured.
- Grok (xAI): one stored key that xAI rejects as an API key; Tom keeps it for
  later. Declared as a ciphertext only, no provider, no reader.
- Live smoke after the NAS switch (2026-11-03, one request per lane on its
  default model): groq-oss, cohere, nvidia, cerebras, cerebras-oss,
  gemini-lite and the three `zen` modes answered; mistral 429 (plan not
  activated) and vercel 403 (`customer_verification_required`: a credit card
  must be on file before the free credits serve) refused as expected. Three
  routes failed on configuration, fixed in the same day: pi-ai sends the
  instructions as a `developer` message to every reasoning model whose
  compat allows it and Groq's Qwen chat template answers 400 "Unexpected
  message role", so `qwen/qwen3.8-27b` declares
  `compat.supportsDeveloperRole = false`; the Cloudflare ids and the
  hand-declared Hugging Face id carry no reasoning metadata, so their routes
  declare `reasoningEffort = null` and the overlay drops the key instead of
  forcing `high` (UNSUPPORTED_REASONING_EFFORT).
- pi-ai 1.3.0 (the fleet dsh) ships native catalog routes `groq`,
  `mistral` (wire protocol `mistral-conversations` on `https://api.mistral.ai`,
  not the `/v1` chat the orchestrator measured), `nvidia`, `huggingface` and
  `cerebras` (openai-completions, both measured ids catalog-verified),
  `vercel-ai-gateway` (anthropic-messages on `https://ai-gateway.vercel.sh`,
  not the OpenAI-compatible `/v1` that was measured),
  `cloudflare-workers-ai` (its model endpoints carry the placeholder
  `{CLOUDFLARE_ACCOUNT_ID}`, which pi-ai's own resolver fills from the
  variable of that name in the process environment at request time); it
  ships no `cohere` route. On a catalog route a hand-declared id takes its
  api and endpoint from the catalog provider, which works for groq, mistral,
  nvidia and huggingface but not for cloudflare-workers-ai (no fixed
  endpoint to default from), so `@cf/deepseek-ai/deepseek-v4.1-flash-1017`
  is not declared until a pi-ai catalog lists it.
- Ciphertexts: `secrets/groq-api-key-{1,2,3}.age`, `secrets/mistral-api-key-{1,2,3}.age`,
  `secrets/cohere-api-key-{1..5}.age`, `secrets/nvidia-api-key-1.age`,
  `secrets/cloudflare-workers-ai-token-1.age`, `secrets/cloudflare-account-id.age`,
  `secrets/huggingface-inference-token-1.age`, `secrets/cerebras-api-key-1.age`,
  `secrets/vercel-ai-gateway-key-1.age`, `secrets/grok-api-key-1.age`; same
  recipients and delivery as the first batch. The account id is an identifier, not a credential, but
  is kept at the same tier; it is the one value of this lane that dsh does
  not strip from the model's child processes (dsh strips names matching
  KEY, TOKEN, SECRET or PASSWORD, and pi-ai reads it under that exact name).

## 2. What the Zen plugin does, plainly

`@jiesou/dsh-opencode-zen-free-provider` (MIT, 0.1.28, built `lib/`
committed upstream and packaged unmodified in `pkgs/dsh-plugins/opencode-zen-free`)
makes dsh look like the OpenCode CLI toward `https://opencode.ai/inference/v1`:

- it forces `User-Agent: opencode/<version>`, the version read from unpkg's
  `opencode-ai@latest` at mount (fallback 1.19.0; Zen refuses anything below
  1.18.0 with HTTP 426), and sends `x-opencode-client: cli`,
  `x-opencode-project: global` and four `ses_` session-id headers minted in
  opencode's own id format;
- it omits `HTTP-Referer` and `x-opencode-request`, pads placeholder
  `bash`/`read` tools into the request, replays empty `reasoning_content`
  on assistant messages, and rewrites 401/403 refusals so dsh does not
  classify them as AUTH errors;
- it exposes every catalog id ending in `-free` that models.dev does not
  mark deprecated, as provider `opencode-zen-free-provider` (display
  "OpenCode Zen Free"), api `openai-completions` (`openai-responses` for
  muse-spark ids);
- it resolves its key ONLY through dsh's `credentials` service
  (`credentialRef('OPENCODE_ZEN_FREE_API_KEY')`) and otherwise sends the
  anonymous bearer `public`; it never reads `process.env`, and it does not
  read `OPENCODE_API_KEY`.

Zen's free gating changes with each opencode release and the plugin tracks
it by code, not by contract. Every prompt sent this way leaves the machine to
opencode.ai; Zen's data terms were not read. The Chinese README warns that
free models are rate-limited per IP, so the four orgs probably share one
bucket from the NAS (inferred, not measured).

## 3. What this PR declares

| Piece | Where | What |
|---|---|---|
| Plugin package | `pkgs/dsh-plugins/opencode-zen-free/default.nix` | fetchFromGitHub at tag 0.1.28, no build, installCheck: `node --check`, every import is a declared peer or `node:`, only opencode.ai, unpkg.com and models.dev are named, the credentials ref and `public` fallback are where the profile expects them |
| `zen` profile | `pkgs/dsh/config.nix`, `pkgs/dsh/default.nix` | stderr-log + the plugin; `credentials` re-enabled (the headless bundle disables it, and the plugin reads its key only through it); default route `opencode-zen-free-provider/deepseek-v4.1-flash-free`; plugin row retry `normal`, 3 retries (the design's `always` mode has no retry bound in this dsh and would retry a 429 forever) |
| Gemini route | `pkgs/dsh/config.nix` | native `google` provider, `apiKeyEnv = GEMINI_API_KEY`, the 11 catalog ids, default `google/gemini-3.8-flash`; `qwen-token-plan` deleted (function, provider, default route, acp row) |
| Route overlays | `pkgs/dsh/config.nix` `routes`, wrapper `DSH_ROUTE` | `gemini`, `gemini-pro`, `gemini-lite`, `gufo`, `zen-deepseek`, `zen-glm`: one-row `agent-default-model` overlays after the profile's layers; headless, sdk, acp and zen only; any other name is refused (exit 2) |
| Key slots | `pkgs/dsh/default.nix` `keyFiles`, `home/dsh.nix` | `DSH_KEY_SLOT=<n>` (default 1) reads the n-th agenix file of each list into `GEMINI_API_KEY` (3) and `OPENCODE_ZEN_FREE_API_KEY` (4) for the exec'd dsh only; never on a config dump, never traced, never printed; the wrapper first unsets those two and `OPENCODE_API_KEY`; a slot past a list says so once on stderr and exports nothing (`DSH_KEY_SLOT=4` is Zen-only, `5` is anonymous Zen); `0`, blank or non-numeric is refused |
| Secrets | `secrets.nix`, `modules/secrets.nix`, `REKEY.md` | seven brain-only ciphertexts, owner tom, mode 400, like openrouter-token |
| Checks | `tests/dsh-zen` (new), `tests/dsh-config`, `tests/dsh-plugins` | dsh-zen boots the zen profile from a seeded catalog cache (proves the pi-ai 1.3.0 import, `createProvider` and `registerAdapter`), dumps zen/headless/route overlays, refusals, the slot reader with sandbox-only dummy files; dsh-config checks the google provider and the gemini-pro overlay |
| Batch-2 routes (issue 687) | `pkgs/dsh/config.nix` | native catalog routes `groq` (GROQ_API_KEY), `mistral` (MISTRAL_API_KEY), `nvidia` (NVIDIA_API_KEY), `cloudflare-workers-ai` (CLOUDFLARE_WORKERS_AI_TOKEN, plus CLOUDFLARE_ACCOUNT_ID read by pi-ai), `huggingface` (HF_TOKEN), `cerebras` (CEREBRAS_API_KEY), `vercel-ai-gateway` (AI_GATEWAY_API_KEY), each narrowed to the measured ids; `cohere` hand-declared (api openai-completions, baseURL `https://api.cohere.com/compatibility/v1`, no `store`, reasoning `high` on the two reasoning ids, sizes declared not measured); Gemini stays the default of every profile |
| Batch-2 overlays and slots | `pkgs/dsh/config.nix` `routes`, `pkgs/dsh/default.nix`, `home/dsh.nix` | `DSH_ROUTE=<groq\|groq-oss\|mistral\|codestral\|cohere\|nvidia\|nvidia-deepseek\|cloudflare\|cloudflare-deepseek\|huggingface\|cerebras\|cerebras-oss\|vercel>`; `DSH_KEY_SLOT=<n>` now also picks groq (3), mistral (3), cohere (5), nvidia (1), the Cloudflare token and account id (1), huggingface (1), cerebras (1), the Vercel gateway key (1); the wrapper first unsets all of them and the login shell's full-scope `CLOUDFLARE_API_TOKEN` and pi-ai's ambient `CLOUDFLARE_API_KEY` |
| Batch-2 secrets | `secrets.nix`, `modules/secrets.nix`, `REKEY.md` | 18 brain-only ciphertexts, owner tom, mode 400 (`grok-api-key-1` stored only, no reader) |
| Batch-2 checks | `tests/dsh-config`, `flake.nix`, `tests/dsh-zen` | every new route dumps in headless with empty stderr; the hand-declared cohere route's api/baseURL and every keyed route's apiKeyEnv and ids are checked against the policy; `DSH_ROUTE=cloudflare-workers-ai` (a provider name) is refused; dsh-zen's slot reader covers a single-file list (slot 4 says so for NVIDIA and the account id, slot 1 is silent) |

Model selection is explicit per run: `agent-default-model` is the profile
default, `DSH_ROUTE` overlays it, a caller's own `--patch` still comes last.
There is no ordered fallback in dsh, so a 429 means re-running with another
`DSH_KEY_SLOT` or route. Round-robin (`DSH_KEY_SLOT=auto`) is deferred: four
Zen keys behind one IP are probably one bucket, and nothing measured yet shows
different limits between slots.

The stock `headless` profile mounts no plugin and keeps
`credentials` disabled; it gets the Gemini default route and the key slot.
Nothing here touches `~/.dsh`: the profile manifest and store links under
`~/.dsh/profiles/zen` are written by the wrapper on the first `dsh zen`.

## 4. The burndown ledger (reading of 2026-11-03, about 21:00Z)

One row per lane and account, strongest model first. The Claude cloud
credits expire 2026-11-05 07:59Z.

**Reading the ledger with `seats`.** `seats` (home/dot_local/bin/seats)
prints the same table live, under the window table, as "burndown ledger":
one row per key (`gemini-1..3`, `zen-1..4`, `groq-1..3`, `mistral-1..3`,
`cohere-1..5`, `nvidia-1`, `cloudflare-1`, `hf-1`), the two cloud-credit
rows (`cc-credit`, `cc2-credit`, parsed from the usage payload the `cc`
rows already fetch, so the endpoint is never asked twice), and the local
rows (`gpu-strix`, `codex`). Each column says what kind of fact it
is: ALLOWANCE is the provider's published tier typed into the script on
2026-11-03 (static, never measured); RESET is computed from the provider's
rule (Gemini midnight Pacific, Cloudflare 00:00 UTC, Cohere the calendar
month, a credit's own expiry; Groq only from its headers, Zen unpublished);
TODAY is this box's own count of calls recorded against the row since the
last reset, read from the append-only
`~/.local/state/seats/lane-usage.jsonl` (one line
`{ts, lane, slot, model, status}`). Nothing appends to that file yet except
`seats --record <lane> <slot> <model> <status>` (for example
`seats --record gemini 2 gemini-3.8-flash 429`); the dsh wrapper will append
its own line per call in a later PR. A row with no key file on the host says
`no key on this host`; a row with a key and no record is `open` but graded
UNKNOWN until probed. `seats --probe` makes ONE cheap GET per key (the
models list), reads the key from `/run/agenix/<name>` and never prints it,
keeps only the status and the rate-limit headers (Groq's
`x-ratelimit-*`, Cohere's `x-trial-endpoint-call-*` become a request
counter; the rest read ok / 429 / 402), reuses an answer for ten minutes,
and refuses `--watch` intervals under 600 s. A plain-client 429 from Zen is
the fingerprint gate, not quota: only a 429 recorded from `dsh zen` counts.
`seats --only ledger` limits the output to these rows; `--only gemini`
to one family. For the day-over-day index Tom asked for, append one line
per row after each lane run, by hand or from any script, no timer here
(Substrate owns schedules):

```
seats --no-spend --jsonl --only ledger >> ~/today/ledger.jsonl
```

Secret names the script reads beyond this PR's seven, as the batch-2 PR
declares them: `groq-api-key-N`, `mistral-api-key-N`, `cohere-api-key-N`,
`nvidia-api-key-1`, `cloudflare-workers-ai-token-1` plus
`cloudflare-account-id`, `huggingface-inference-token-1` (never
`huggingface-token`, the Hub download token), `cerebras-api-key-1`,
`vercel-ai-gateway-key-1` (probe reads `GET /v1/credits` and shows the
balance) and `grok-api-key-1` (no probe); `SEATS_AGENIX_DIR` moves the
directory for tests.

| Lane / account | Harness | Models, strongest first | Allowance | How exhaustion shows | How to read it today | Credential |
|---|---|---|---|---|---|---|
| Zen org 1 (GitHub-linked) | `dsh zen` | deepseek-v4.1-flash-free, glm-5.3-flash-free (mimo-v2.6-flash-free if the catalog lists it); pulse-alpha-free is 403 RegionError for France | free; per-IP rate limit (Chinese README); daily allowance unpublished | HTTP 429 `FreeUsageLimitError`; only a 429 seen THROUGH the plugin's fingerprint counts, a plain client gets it on the first call | the first `dsh zen` call | `opencode-zen-key-1` (slot 1) |
| Zen orgs 2–4 (Google-linked) | same | same | same; probably one pool with org 1 from the NAS IP (inferred) | same | same; key 2 is the one the official client proved | `opencode-zen-key-{2,3,4}` (slots 2–4) |
| Gemini key 1 | `dsh headless` (default route) | gemini-3.8-flash, 3.6-flash, 3.5-flash-lite, 3.1-flash-lite, 3-flash-preview, 2.5-pro/2.5-flash (deprecated 2026-12-01), 2.5-flash-lite; 3.1-pro-preview is paid-only; 3.7-flash and 3.5-flash free status unknown | free tier per PROJECT; RPM/TPM/RPD unpublished on the docs page, visible at aistudio.google.com/rate-limit while logged in; RPD resets midnight Pacific | HTTP 429 with a quota message (text not yet captured) | the models GET (200 = live only) plus our own call count | `gemini-api-key-1` (slot 1) |
| Gemini keys 2, 3 | same | same | same, if the keys sit in different projects (unverified) | same | same | `gemini-api-key-{2,3}` (slots 2, 3) |
| cc cloud credit | `claude --cloud` as cc | Opus / Fable | $250.00 left, expires 2026-11-05 07:59Z | credit reaches 0, then the weekly window continues silently; burn 30–87 USD/h measured on cc2 | `/run/user/1000/seats/claude-cc.json`, `data.iguana_necktie.remaining_dollars` | `~/.claude` OAuth |
| cc2 cloud credit | `claude --cloud` as cc2 | same | $89.27 left, same expiry | same | same field in `claude-cc2.json` | `~/.claude-work` OAuth |
| cc weekly window | Claude Code, cc | Fable, capped at 50% | 15.0% used; resets Wed 10:00Z | 429 or 100% on the usage endpoint | `seats --only cc` | same |
| cc2 weekly window | Claude Code, cc2 | same | 4.0% used; resets Thu 05:59Z | same | `seats --only cc2` | same |
| Codex | `codex exec` | gpt-6.1-sol, gpt terra | weekly window 100% spent, resets Wed 07:50Z; 3 rate-limit reset credits (next expires 11-06, a person spends one) | window exhausted in the rollout | `seats --only codex` | `~/.codex` |
| Groq key 1 | `DSH_ROUTE=groq` (qwen3.8-27b), `groq-oss` (gpt-oss-120b); gpt-oss-20b by `--patch` | qwen/qwen3.8-27b, openai/gpt-oss-120b, openai/gpt-oss-20b | per key: 1,000 requests/day, 200K tokens/day, 30 RPM, 8,000 TPM (headers measured) | HTTP 429 with `x-ratelimit-remaining-requests: 0` or `-tokens: 0`; dsh reports QUOTA/RATE_LIMIT | the `x-ratelimit-remaining-*` and `x-ratelimit-reset-*` headers of any call | `groq-api-key-1` (slot 1) |
| Groq keys 2, 3 | same | same | same, per key (three accounts) | same | same | `groq-api-key-{2,3}` (slots 2, 3) |
| Mistral key 1 | `DSH_ROUTE=mistral` (mistral-medium-latest), `codestral` | mistral-medium-latest, magistral-medium-latest, codestral-latest, devstral-latest, mistral-small-latest, ministral-14b-2512 | Experiment plan, NOT YET ACTIVE: 429 with `x-ratelimit-limit-req-minute: 0` until Tom activates it; the plan's own limits are on Mistral's pricing page, not yet read | HTTP 429; dsh QUOTA | `x-ratelimit-*` headers; the console at console.mistral.ai | `mistral-api-key-1` (slot 1) |
| Mistral keys 2, 3 | same | same | same, per account | same | same | `mistral-api-key-{2,3}` (slots 2, 3) |
| Cohere key 1 | `DSH_ROUTE=cohere` (command-a-plus-05-2026) | command-a-plus-05-2026, command-a-reasoning-08-2025, command-a-03-2025, command-r-plus-08-2024 | trial: 20 calls/minute, 1,000 calls/month per key | HTTP 429 (per-minute) or the monthly cap message; dsh QUOTA/RATE_LIMIT | own call count; dashboard.cohere.com usage page | `cohere-api-key-1` (slot 1) |
| Cohere keys 2 to 5 | same | same | same, per key | same | same | `cohere-api-key-{2,3,4,5}` (slots 2 to 5) |
| NVIDIA NIM | `DSH_ROUTE=nvidia` (glm-5.3-flash), `nvidia-deepseek` (deepseek-v4.1-flash) | z-ai/glm-5.3-flash, deepseek-ai/deepseek-v4.1-flash, nvidia/nemotron-3.5-super-vl-120b-a12b, nvidia/nemotron-3-super-120b-a12b, minimaxai/minimax-m3.1-flash, openai/gpt-oss-20b | about 40 RPM (docs, unconfirmed); no daily figure published | HTTP 429; dsh RATE_LIMIT | own call timing; build.nvidia.com shows the credit/usage state | `nvidia-api-key-1` (slot 1 only) |
| Cloudflare Workers AI | `DSH_ROUTE=cloudflare` (qwen3.8-27b), `cloudflare-deepseek` (deepseek-v4-pro-0813) | @cf/qwen/qwen3.8-27b, @cf/deepseek-ai/deepseek-v4-pro-0813, @cf/openai/gpt-oss-120b, @cf/google/gemma-4-26b-a4b-it, @cf/meta/llama-4-scout-17b-16e-instruct (deepseek-v4.1-flash-1017 waits for a catalog bump) | 10,000 neurons/day, reset 00:00 UTC | HTTP 429 with a neurons message (text not yet captured); dsh QUOTA | the Workers AI page of the Cloudflare dashboard (neurons used today); the `cf-aig`/usage headers are not published | `cloudflare-workers-ai-token-1` + `cloudflare-account-id` (slot 1 only) |
| Hugging Face | `DSH_ROUTE=huggingface` (gpt-oss-120b:cheapest) | openai/gpt-oss-120b:cheapest, openai/gpt-oss-120b, Qwen/Qwen3.8-27B, deepseek-ai/DeepSeek-V4.1-Flash, zai-org/GLM-5.3-Flash | Free account: no included credits, every chat is 402 today; PRO or bought credits open it | HTTP 402 (no credits) or 429; dsh QUOTA | huggingface.co/settings/billing | `huggingface-inference-token-1` (slot 1 only) |
| Cerebras | `DSH_ROUTE=cerebras` (qwen-3.8-27b), `cerebras-oss` (gpt-oss-120b) | qwen-3.8-27b, gpt-oss-120b | 450 RPM, 648K requests/day, 150K TPM, 216M tokens/day (headers measured); single key, no rotation | HTTP 429; dsh RATE_LIMIT/QUOTA | the `x-ratelimit-*` headers of any call | `cerebras-api-key-1` (slot 1 only) |
| Vercel AI Gateway | `DSH_ROUTE=vercel` (alibaba/qwen3.8-27b, catalog id, not measured) | the gateway's catalog; one id declared | credits balance 0 today: nothing answers until topped up | HTTP 402/403 on a 0 balance (text not captured); dsh QUOTA | vercel.com AI Gateway billing page | `vercel-ai-gateway-key-1` (slot 1 only) |
| Grok (xAI) | none | — | the stored key is rejected by xAI as an API key | — | — | `grok-api-key-1` (stored, no reader) |
| Gufo (local) | `DSH_ROUTE=gufo` | qwen3.8-flash-next, qwen3.8-27b | local, no quota | wrong-id 404, cold-load latency | `seats` row `gpu-strix` | none (LAN) |
| OpenRouter | parked, no dsh route | — | $27.16 of $40.00 left; free lane parked 0/1000 | — | `seats` rows `openrouter`, `openrouter-free` | agenix openrouter-token |
| DeepSeek Flash1017 token plan | — | — | exhausted 04:22Z, resets 7 Nov 16:00Z (reported, not re-measured) | — | — | — |

Data posture on both free lanes: the AI Studio terms say submitted content
may be used to improve products and read by human reviewers, and ask for no
sensitive, confidential or personal information; Zen's terms were not read.
So no `references/personal`, estate, CRM, health, credential or proprietary
material and no private repo contents that matter go through them. Gufo
stays the lane for anything sensitive.

## 5. First commands, after the merge

All from `/home/tom/mecattaf/dotfiles` on the NAS (builds go to
strix-coordinator through the SSH builder; check `ssh strix-coordinator 'df -h /'`
first and stop under 25 GB free). Runtime-sensitive runs go through
`~/.local/bin/runtime-test -- ...`.

```
# 1. Deploy the NAS (fast-forward the checkout first, AGENTS.md "Raw dotfiles")
sudo nixos-rebuild switch --flake .#nas
ls -l /run/agenix/gemini-api-key-1 /run/agenix/opencode-zen-key-1   # mode 400, tom

# 2. Gemini lane smoke, from a project cwd that is neither $HOME nor DSH_HOME
DSH_KEY_SLOT=1 DSH_ROUTE=gemini dsh headless "reply with the single word ready"
DSH_KEY_SLOT=2 DSH_ROUTE=gemini dsh headless "reply with the single word ready"
DSH_KEY_SLOT=3 DSH_ROUTE=gemini dsh headless "reply with the single word ready"
DSH_KEY_SLOT=1 DSH_ROUTE=gemini-pro dsh headless "reply with the single word ready"   # expected to refuse: pro is paid-only

# 3. Zen lane smoke: key 2 is the one the official client proved
DSH_KEY_SLOT=2 dsh zen "reply with the single word ready"
DSH_KEY_SLOT=2 DSH_ROUTE=zen-glm dsh zen "reply with the single word ready"
DSH_KEY_SLOT=5 dsh zen "reply with the single word ready"    # past every list: anonymous `public`; record works / 429

# 4. Ledger (until the seats rows exist, note the 429 texts by hand)
seats --watch 60

# 5. Second batch (issue 687), after that PR's switch; same cwd rule
ls -l /run/agenix/groq-api-key-1 /run/agenix/cohere-api-key-5 /run/agenix/cloudflare-account-id   # 400, tom
DSH_KEY_SLOT=1 DSH_ROUTE=groq dsh headless "reply with the single word ready"
DSH_KEY_SLOT=2 DSH_ROUTE=groq-oss dsh headless "reply with the single word ready"
DSH_KEY_SLOT=1 DSH_ROUTE=cohere dsh headless "reply with the single word ready"      # the hand-declared route's first live call
DSH_KEY_SLOT=1 DSH_ROUTE=nvidia dsh headless "reply with the single word ready"
DSH_KEY_SLOT=1 DSH_ROUTE=cloudflare dsh headless "reply with the single word ready"  # proves the {CLOUDFLARE_ACCOUNT_ID} fill
DSH_KEY_SLOT=1 DSH_ROUTE=mistral dsh headless "reply with the single word ready"     # 429 until the Experiment plan is active
DSH_KEY_SLOT=1 DSH_ROUTE=huggingface dsh headless "reply with the single word ready" # 402 until credits or PRO
DSH_KEY_SLOT=1 DSH_ROUTE=cerebras dsh headless "reply with the single word ready"    # the strongest lane
DSH_KEY_SLOT=1 DSH_ROUTE=vercel dsh headless "reply with the single word ready"      # fails on a 0 balance
```

If the Mistral route still fails once the plan is active, the fallback is
to override the catalog route's protocol in `pkgs/dsh/config.nix`
(`api = "openai-completions"; baseURL = "https://api.mistral.ai/v1";` on the
`mistral` provider), which is the endpoint the orchestrator measured.

If a Zen smoke returns 429 `FreeUsageLimitError` through the plugin, compare
its request headers against the opencode 1.19.3 client in the NAS store
(`/nix/store/fmrzvnxdpjijh4vgs53g8lslz1m6ndq5-opencode-1.19.3`) before
blaming the IP bucket. If the plugin ever fails to mount after a dsh bump,
`checks.dsh-zen` (built on every llm-agents bump) is where it shows; the
tonight-only escape hatch the design named, `pkgs.llm-agents.opencode` with
`OPENCODE_API_KEY`, breaks the three-harness ruling and is not installed.

## 6. Unverified

- Zen's daily allowance, reset time and whether the limiter is per IP, per
  org or per session; whether orgs 1–4 share one bucket from the NAS.
- Whether the anonymous `public` bearer works through the plugin, and
  whether the plugin's fingerprint passes Zen's gate from the NAS at all:
  only the live smoke shows it.
- Runtime behaviour of the plugin on pi-ai 1.3.0 beyond mount:
  `checks.dsh-zen` boots it (import, model build, `createProvider`,
  `registerAdapter`); streaming a turn is the live smoke.
- How dsh classifies Zen's 429 under the plugin row's retry policy (bounded
  to 3 here either way).
- Which `-free` ids the live catalog lists beyond the two measured ones.
- Gemini free-tier RPM/TPM/RPD per model; free status of 3.7-flash and
  3.5-flash; whether the three keys sit in three projects.
- Zen's data terms.
- Batch 2 (issue 687): no live call has gone through dsh on any of the six
  lanes; the checks prove composition, not serviceability. In particular:
  Mistral's `mistral-conversations` protocol on the Experiment plan (the
  measured 429 was on `/v1/chat/completions`); whether Cohere's compatibility
  endpoint accepts pi-ai's openai-completions request shape (tools, the
  `developer` role, `reasoning_effort: high`) and the declared sizes of
  command-a-plus-05-2026; that pi-ai fills `{CLOUDFLARE_ACCOUNT_ID}` from the
  wrapper's exported variable in a real request (read from the resolver's
  code, not run); the hand-declared NVIDIA ids' sizes and whether NIM answers
  them for this account; Hugging Face's `:cheapest` suffix through pi-ai;
  every exhaustion text; Groq's 200K tokens/day and NVIDIA's 40 RPM figures;
  Mistral's Experiment-plan limits as published; Vercel's anthropic-messages
  protocol through pi-ai and whether `alibaba/qwen3.8-27b` is served there
  (0 balance today, no model measured).

## Zen client: OpenCode CLI

Issue: [#691](https://github.com/mecattaf/dotfiles/issues/691). Tom: "i m
open to installing opencode just for the free compute anyway". So the
OpenCode CLI is installed as a headless client for the Zen free lane only,
behind the `zen` wrapper; the harnesses stay dsh, Claude Code and Codex, and
nobody sits in `opencode`.

### Why the plugin route did not pass (measured 2026-11-03, 22:30 local, NAS)

After the switch to PR 686, `dsh zen` with the jiesou plugin returned
`429 FreeUsageLimitError "Free usage limit reached. Free models work in
OpenCode"` on key slots 1 and 2 and on the anonymous bearer, for both
deepseek-v4.1-flash-free and glm-5.3-flash-free. In the same minutes the
official client `opencode` 1.19.3 (`pkgs.llm-agents.opencode` at the locked
llm-agents rev 8b5adae, prebuilt in cache.numtide.com and already in the NAS
store) with `OPENCODE_API_KEY` from key 2 and `opencode run -m
opencode/deepseek-v4.1-flash-free "Reply with the single word: ready"`
answered `ready`. The keys and models are live; Zen's gate wants the real
client. The plugin package and the `dsh zen` profile stay as they are; this
section adds the client beside them.

### What is delivered

- `opencode` in the llm-agents allowlist (`home/agent-tools.nix`).
- `~/.config/opencode/opencode.json`: default model
  `opencode/deepseek-v4.1-flash-free`, small model
  `opencode/glm-5.3-flash-free`, `share: disabled`, `autoupdate: false`,
  `enabled_providers: ["opencode"]`, and a permission block that allows
  read/glob/grep/list and denies edit, bash, task, webfetch, websearch,
  question, external_directory and doom_loop. A plain `opencode run` needs no
  tool, so nothing that writes or runs is allowed; the Zen lane answers and
  reads, dsh edits. The docs do not say what an unattended `run` does with an
  `ask` rule, so no rule is left at `ask`. Delivered as ONE file, not a
  whole-dir link: `~/.config/opencode` is Tom's real July 2026 directory
  (package.json, package-lock.json, .gitignore, opencode.jsonc) and keeps his
  files. Measured on 1.19.3: `opencode.jsonc` loads after `opencode.json` and
  wins on conflicting keys, but his `.jsonc` holds only `$schema`, so every
  key of the delivered `opencode.json` survives the merge (`opencode debug
  config` shows it). Delivering under `opencode.jsonc` would have collided
  with his file at activation.
- `zen` (`home/dot_local/bin/zen`, bash, shellcheck-clean): the only place a
  Zen key is read. `OPENCODE_API_KEY` is exported for the exec'd `opencode`
  only, after `set +o xtrace`, and never printed.

### `zen` usage

```
zen [-k N] [-m MODEL] [--burndown] PROMPT...
```

- `-k N` picks `/run/agenix/opencode-zen-key-N` (1 to 4; `ZEN_SLOT` is the
  env form, default 1). An unreadable key file or a slot outside 1 to 4 is a
  refusal on stderr, exit 1 or 2, and nothing is sent.
- `-m MODEL` names the Zen model id without the `opencode/` prefix. The
  default order is deepseek-v4.1-flash-free, then glm-5.3-flash-free.
  pulse-alpha-free answers 403 RegionError for France and is not in the
  order.
- Without `--burndown`, it execs `opencode run -m opencode/MODEL PROMPT...`
  on the first model, so the exit status is opencode's.
- With `--burndown`, it runs (not exec) slot N..4 on the first model, then
  the same slots on the next; a reply naming `FreeUsageLimitError` or `429`
  moves on with one stderr line `zen: slot N model M drained`; any other
  failure stops with opencode's output (measured: opencode exits 1 and
  prints `Error: ...` on an API error).
- Meter: one JSON line per attempt in `~/.local/state/seats/lane-usage.jsonl`
  (`mkdir -p`), `{"ts","lane":"zen","slot","model","status"}`, status
  `sent` (exec path), `ok`, `429` (the stderr line still says "drained")
  or `error`. This is the meter the seats ledger reads: a status starting
  with `429` counts as a refusal and marks the slot spent until its reset,
  the others count as calls; the wrapper writes nothing else. opencode itself keeps
  sessions, snapshots and logs under `~/.local/share/opencode` (Tom's July
  database stays there).
- A non-TTY stdin is closed unless `ZEN_STDIN=1`: opencode appends piped
  stdin to the prompt and waits for EOF, which hangs under an agent's open
  pipe (measured: two 120 s timeouts before the fix).
- Arguments after `--` go to `opencode run` unchanged, e.g.
  `zen -k 2 -- --print-logs "..."`.

### Measured before merge (2026-11-03, 21:37Z, worktree cwd, locked opencode on PATH)

`zen -k 2 "Reply with the single word: ready"` answered `ready` (deepseek,
9 s wall); `zen -k 2 -m glm-5.3-flash-free "..."` answered `ready`;
`zen -k 2 --burndown -m pulse-alpha-free "..."` printed `Error: This model
is not available in your country`, exit 1, meter status `error`;
`zen -k 2 --burndown "..."` answered `ready`, meter status `ok`. The test
meter lines were removed afterwards. A real `drained` step was not provoked.

### First commands, after the switch

```
sudo nixos-rebuild switch --flake .#nas          # from /home/tom/mecattaf/dotfiles
opencode --version                                # 1.19.3
opencode debug config | head -5                   # model opencode/deepseek-v4.1-flash-free
zen -k 2 "Reply with the single word: ready"
zen -k 2 -m glm-5.3-flash-free "Reply with the single word: ready"
zen --burndown "Reply with the single word: ready"   # slots 1..4, then glm
tail -3 ~/.local/state/seats/lane-usage.jsonl
```

Unverified: whether a real 429 through the official client is a per-key or
per-IP bucket (no slot has drained yet); the unreadable-key refusal was
exercised only through the slot-range check, since all four key files are
readable on the NAS.
