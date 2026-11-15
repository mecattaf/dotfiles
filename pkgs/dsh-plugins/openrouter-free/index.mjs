import z from '@deepseek-ai/schemastery';
import { assertUsableApiKey, LlmError, resolveRetryPolicy } from '@deepseek-ai/dsh-llm';
import { credentialRef } from '@deepseek-ai/dsh-credentials';
import { PiAiAdapter } from '@deepseek-ai/dsh-llm-pi-ai';
import { createProvider } from '@earendil-works/pi-ai';
import { getBuiltinModels } from '@earendil-works/pi-ai/providers/all';
import { stream, streamSimple } from '@earendil-works/pi-ai/api/openai-completions';

export const name = 'openrouter-free';
export const inject = ['llm', 'credentials'];
const MODEL = 'nvidia/nemotron-3.5-lightning:free';
const KEY = credentialRef('OPENROUTER_API_KEY');
export const Config = z.object({
  models: z.array(z.string()).default([MODEL]),
});

/** Enforced after all upstream payload transforms, immediately before HTTP. */
export function freePayload(payload, model, allowed) {
  if (!allowed.includes(model.id) || !model.id.endsWith(':free') || payload.model !== model.id)
    throw new LlmError('OpenRouter Free requires one exact allowed :free model', 'INVALID_REQUEST');
  if (payload.models !== undefined)
    throw new LlmError('OpenRouter Free does not accept a model fallback array', 'INVALID_REQUEST');
  return {
    ...payload,
    provider: {
      ...payload.provider,
      allow_fallbacks: false,
      max_price: { prompt: 0, completion: 0, request: 0, image: 0 },
    },
    usage: { ...payload.usage, include: true },
  };
}

export function guardedOptions(options, allowed) {
  return {
    ...options,
    onPayload: async (payload, model) => {
      const transformed = await options?.onPayload?.(payload, model) ?? payload;
      return freePayload(transformed, model, allowed);
    },
  };
}

// Explicit credential resolution below owns authentication; no ambient OAuth
// or provider environment fallback is supplied to the native SDK collection.
const auth = {
  credentials: {
    read: async () => undefined,
    list: async () => [],
    modify: async (_id, mutate) => mutate(undefined),
    delete: async () => {},
  },
  authContext: { env: async () => undefined, fileExists: async () => false },
};

export function apply(ctx, config) {
  const allowed = [...new Set(config.models)];
  if (!allowed.length || allowed.some(id => !id.endsWith(':free')))
    throw new Error('OpenRouter Free models must be explicit :free selectors');
  const catalog = getBuiltinModels('openrouter');
  const models = allowed.map(id => {
    const model = catalog.find(candidate => candidate.id === id && candidate.api === 'openai-completions');
    if (!model) throw new Error(`OpenRouter Free selector absent from the installed native catalogue: ${id}`);
    return { ...model, provider: name, maxTokens: Math.min(model.maxTokens, 8192) };
  });
  const provider = createProvider({
    id: name,
    name: 'OpenRouter Free',
    baseUrl: 'https://openrouter.ai/api/v1',
    auth: { apiKey: { name: 'OpenRouter API key', resolve: ({ credential }) => Promise.resolve({
      auth: credential?.key === undefined ? {} : { apiKey: credential.key }, source: name,
    }) } },
    models,
    api: { 'openai-completions': {
      stream: (model, context, options) => stream(model, context, guardedOptions(options, allowed)),
      streamSimple: (model, context, options) => streamSimple(model, context, guardedOptions(options, allowed)),
    } },
  });
  const profiles = new Map([[name, {
    provider: name,
    displayName: 'OpenRouter Free',
    apiKeyEnv: KEY,
    piProvider: provider,
    streamIdleTimeoutMs: 120000,
    retryPolicy: resolveRetryPolicy({ mode: 'normal', maxRetries: 1 }, name),
    modelErrors: new Map(),
    configuredMaxTokens: new Map(models.map(model => [model.id, model.maxTokens])),
  }]]);
  const adapter = new PiAiAdapter({
    profiles: () => profiles,
    auth,
    resolveAttachments: () => ctx.get('attachments'),
    resolveApiKey: async () => {
      const hit = await ctx.credentials.resolve(KEY);
      if (!hit) throw new LlmError('OpenRouter Free has no configured native credential', 'MISSING_CREDENTIAL');
      return assertUsableApiKey(hit.value, name, String(KEY));
    },
  });
  ctx.effect(() => ctx.llm.registerAdapter([name], adapter));
}
