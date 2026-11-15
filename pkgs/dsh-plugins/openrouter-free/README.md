# OpenRouter Free native DSH adapter

This small adapter uses the installed DSH PiAiAdapter, native pi-ai model
catalogue and completion transport. DSH still owns the agent, tools, retries,
session log and token usage. No separate request loop or gateway is added.

The last native `onPayload` hook requires one allowlisted `:free` model,
rejects fallback arrays, and forces `provider.allow_fallbacks=false` and
`provider.max_price={prompt:0,completion:0,request:0,image:0}` after any prior
hook. Missing credentials, model removal or shared-pool throttling fail
normally. It resolves only the native `OPENROUTER_API_KEY` credential ref.

The field names and units come from [OpenRouter provider routing](https://openrouter.ai/docs/guides/routing/provider-selection#max-price).
Its [free-variant documentation](https://openrouter.ai/docs/guides/routing/model-variants/free)
explains why a fallback array containing a paid model must be refused.
The model's output ceiling is capped at 8,192 tokens for bounded workers.
