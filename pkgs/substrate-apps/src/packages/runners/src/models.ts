/**
 * The model policy as data: an allowlist of full model ids per harness, each
 * with optional aliases and per-window utilization ceilings. It replaces the
 * old `opusOnly` pin (every claude call ran claude-opus-5-5, whatever the
 * script asked for). A script's model is resolved against the list: a full id
 * or an alias of an allowed entry runs as that entry's full id (OI-6: never an
 * alias on the wire); anything else runs as the harness default and the
 * rewrite is visible in the route (`requested`), never silent.
 *
 * Declared in runtimes.toml:
 *
 *   [[models]]
 *   id = "claude-fable-5-1"
 *   harness = "claude"
 *   aliases = ["fable"]
 *   ceilings = { model_scoped = 90 }
 *
 * A pi entry belongs to one pi PROVIDER (`provider = "openrouter"`; absent
 * means `gufo`): a call on a runtime whose table names that provider
 * resolves against that provider's entries only, so an OpenRouter runtime
 * can never run a Gufo id or the reverse.
 *
 * Absent `[[models]]`, DEFAULT_MODEL_ALLOWLIST applies.
 *
 * 2026-10-10 (Tom: "i dnt think it s a g ood idea to have things like that
 * tied to nixos dotfiles"): the catalog is RUNTIME DATA. runtimes.toml names a
 * `models_file` (a plain TOML file of `[[models]]` tables, by default seeded by
 * the operator's deployment at `~/.config/substrate/models.toml`) and the
 * runners re-read it on every call (`catalogFor`, cached by mtime and size):
 * an edit is live on the next call, no restart, no rebuild. Precedence:
 * `models_file`, else inline `[[models]]`, else DEFAULT_MODEL_ALLOWLIST. A file
 * that stops parsing refuses every call with the error (fail closed, never a
 * silent fallback).
 *
 * A pi provider with NO entry is PARKED: the route is refused at once ("no
 * model configured"), route policies fall through, nothing is dialled. The
 * openrouter-free lane ships parked (its stealth model was withdrawn on
 * 2026-10-10; Tom: "i know they will release a new one soon so let s keep the
 * mechanics for it"). An entry may carry a `[models.pi]` table describing a
 * model pi's own catalog does not know (a stealth model on release day): the
 * runner then injects it into a job-scoped pi agent dir (backend.ts
 * piAgentModelsJson) and the id runs with no change to the host's models.json.
 */
import { existsSync, readFileSync, statSync } from "node:fs";
import { Schema } from "effect";
import { parse as parseToml } from "smol-toml";
import { MODEL_PROVIDER_NAMES, type HarnessName, type ModelProvider } from "./harness.ts";

/** Utilization ceilings in percent: at or above one, the capacity gate refuses this model. */
export interface ModelCeilings {
  readonly five_hour?: number;
  readonly seven_day?: number;
  /** The provider's model-scoped window for this model's family (for example the weekly Fable bar). */
  readonly model_scoped?: number;
}

/**
 * pi only: what pi needs to dial a model its built-in provider catalog does not
 * know (the `models` upsert of a provider in pi's models.json, in TOML
 * spelling). `api` and `base_url` default per provider (OpenRouter's
 * OpenAI-compatible endpoint, MEASURED 2026-09-29 for the last stealth model).
 */
export interface PiModelMeta {
  readonly name?: string;
  readonly api?: string;
  readonly base_url?: string;
  readonly reasoning?: boolean;
  readonly input?: readonly string[];
  readonly context_window?: number;
  readonly max_tokens?: number;
}

export interface ModelEntry {
  readonly id: string;
  readonly harness: HarnessName;
  /** pi only: the provider this id is served by (harness.ts PI_PROVIDERS). Absent: gufo. */
  readonly provider?: ModelProvider;
  readonly aliases?: readonly string[];
  /** The harness default when a call names no allowed model. At most one per harness (per provider for pi). */
  readonly default?: boolean;
  /** Explicit model capability. DSH omits reasoning effort when false; other harnesses retain their own behavior. */
  readonly reasoning?: boolean;
  readonly ceilings?: ModelCeilings;
  /** pi only: declares the model to pi when its catalog does not know it (see PiModelMeta). */
  readonly pi?: PiModelMeta;
}

export type ModelAllowlist = readonly ModelEntry[];

/**
 * Opus stays the claude default. Fable is allowed and capped on its
 * model-scoped window at 90 percent (a proposed default, REPORTED as the
 * binding limit on 2026-09-23). codex has no pinned id: an unset model lets
 * codex use its own configured default.
 *
 * pi, per provider (2026-09-30, Tom's budget rulings for the overnight run):
 *   - gufo: the resident Gufo Flash-Next model.
 *   - qwen-token-plan: qwen3.8-max, the plan's flagship (weekly credits, not dollars).
 *   - openrouter (paid, soft cap $12 on the seat): ids and prices from the
 *     anonymous GET https://openrouter.ai/api/v1/models on 2026-09-30, USD per
 *     million tokens in/out, each present in pi 0.99.1's openrouter catalog:
 *       deepseek/deepseek-v4-pro     $0.78 / $1.57  (default: strong coding, 1M ctx, cheap enough for a $12 night)
 *       minimax/minimax-m3           $0.30 / $1.20  (agentic coding, 1M ctx)
 *       qwen/qwen3.8-max-0902        $2.00 / $6.00
 *       anthropic/claude-sonnet-5.5  $2.00 / $10.00 (explicit only: one long node can spend dollars)
 *   - openrouter-free: PARKED since 2026-10-10 (stealth/space-bunny-alpha was withdrawn: 404 "No endpoints
 *     found", run smoke1010r1). No entry here; the models file activates the lane with one table.
 */
export const DEFAULT_MODEL_ALLOWLIST: ModelAllowlist = [
  { id: "claude-opus-5-5", harness: "claude", aliases: ["opus"], default: true },
  { id: "claude-fable-5-1", harness: "claude", aliases: ["fable"], ceilings: { model_scoped: 90 } },
  { id: "qwen3.8-flash-next", harness: "dsh", provider: "gufo", default: true, reasoning: false, aliases: ["local", "nightly"] },
  { id: "qwen3.8-flash-next", harness: "pi", default: true },
  { id: "qwen3.8-max", harness: "pi", provider: "qwen-token-plan", default: true },
  { id: "deepseek/deepseek-v4-pro", harness: "pi", provider: "openrouter", aliases: ["deepseek"], default: true },
  { id: "minimax/minimax-m3", harness: "pi", provider: "openrouter", aliases: ["minimax"] },
  { id: "qwen/qwen3.8-max-0902", harness: "pi", provider: "openrouter", aliases: ["qwen-max"] },
  { id: "anthropic/claude-sonnet-5.5", harness: "pi", provider: "openrouter" },
];

/** The provider an entry belongs to: its own for pi (default gufo), none for the other harnesses. */
const providerOf = (e: ModelEntry): ModelProvider | undefined => (e.harness === "dsh" ? (e.provider ?? "gufo") : e.harness === "pi" ? (e.provider ?? "gufo") : undefined);

export interface ResolvedModel {
  /** The full id that runs; undefined only for a harness with no default (codex's own default). */
  readonly id: string | undefined;
  /** What the call asked for, when it differs from what runs. */
  readonly requested?: string;
  readonly ceilings?: ModelCeilings;
}

/** An explicit capability normalization, retained in admission and execution evidence. */
export interface EffortAdjustment {
  readonly requested: string | null;
  readonly effective: "off";
  readonly source: "model-capability";
}

export function effortFor(entry: ModelEntry | undefined, requested: string | undefined): { readonly value: string | undefined; readonly adjustment?: EffortAdjustment } {
  return entry?.harness === "dsh" && entry.reasoning === false
    ? { value: undefined, adjustment: { requested: requested ?? null, effective: "off", source: "model-capability" } }
    : { value: requested };
}

export function resolveModel(list: ModelAllowlist, harness: HarnessName, declared: string | undefined, provider?: ModelProvider): ResolvedModel {
  const want = harness === "dsh" ? (provider ?? "gufo") : harness === "pi" ? (provider ?? "gufo") : undefined;
  const mine = list.filter((e) => e.harness === harness && providerOf(e) === want);
  const hit =
    declared === undefined
      ? undefined
      : mine.find((e) => e.id === declared || (e.aliases ?? []).some((a) => a.toLowerCase() === declared.toLowerCase()));
  const chosen = hit ?? mine.find((e) => e.default === true);
  const requested = declared !== undefined && declared !== chosen?.id ? { requested: declared } : {};
  return { id: chosen?.id, ...requested, ...(chosen?.ceilings ? { ceilings: chosen.ceilings } : {}) };
}

/** Every problem with a list, for the config decoder. */
export function modelAllowlistProblems(list: ModelAllowlist): string[] {
  const problems: string[] = [];
  const ids = new Set<string>();
  const defaults = new Map<string, number>();
  for (const e of list) {
    const identity = `${e.harness}:${providerOf(e) ?? ""}:${e.id}`;
    if (ids.has(identity)) problems.push(`models: ${e.id} is listed twice`);
    ids.add(identity);
    if (e.provider !== undefined && e.harness !== "pi" && e.harness !== "dsh") problems.push(`models: ${e.id} names provider ${e.provider}, which only a pi or dsh entry may`);
    if (e.pi !== undefined && e.harness !== "pi") problems.push(`models: ${e.id} carries a [models.pi] table, which only a pi or dsh entry may`);
    for (const k of ["context_window", "max_tokens"] as const) {
      const v = e.pi?.[k];
      if (v !== undefined && !(Number.isInteger(v) && v > 0)) problems.push(`models: ${e.id} pi.${k} must be a positive integer`);
    }
    if (e.harness === "dsh" && (e.provider ?? "gufo") !== "gufo") problems.push(`models: ${e.id} dsh currently serves provider gufo only`);
    const slot = e.harness === "pi" || e.harness === "dsh" ? `${e.harness} (provider ${providerOf(e)})` : e.harness;
    if (e.default) defaults.set(slot, (defaults.get(slot) ?? 0) + 1);
    for (const [k, v] of Object.entries(e.ceilings ?? {})) {
      if (typeof v !== "number" || !(v > 0 && v <= 100)) problems.push(`models: ${e.id} ceiling ${k} must be in (0, 100]`);
    }
  }
  for (const [h, n] of defaults) if (n > 1) problems.push(`models: harness ${h} has ${n} defaults, at most one`);
  return problems;
}

/** The reason a call's catalog could not be read; the backend refuses the call with it. */
export class ModelsFileError extends Error {
  override readonly name = "ModelsFileError";
}

const Ceilings = Schema.Struct({
  five_hour: Schema.optionalKey(Schema.Number),
  seven_day: Schema.optionalKey(Schema.Number),
  model_scoped: Schema.optionalKey(Schema.Number),
});
const PiMeta = Schema.Struct({
  name: Schema.optionalKey(Schema.String),
  api: Schema.optionalKey(Schema.String),
  base_url: Schema.optionalKey(Schema.String),
  reasoning: Schema.optionalKey(Schema.Boolean),
  input: Schema.optionalKey(Schema.Array(Schema.String)),
  context_window: Schema.optionalKey(Schema.Number),
  max_tokens: Schema.optionalKey(Schema.Number),
});
/** One `[[models]]` table (runtimes.toml inline, or the models file). */
export const ModelEntrySchema = Schema.Struct({
  id: Schema.String,
  harness: Schema.Literals(["claude", "pi", "dsh", "codex"]),
  provider: Schema.optionalKey(Schema.Literals(MODEL_PROVIDER_NAMES as unknown as readonly [ModelProvider, ...ModelProvider[]])),
  aliases: Schema.optionalKey(Schema.Array(Schema.String)),
  default: Schema.optionalKey(Schema.Boolean),
  reasoning: Schema.optionalKey(Schema.Boolean),
  ceilings: Schema.optionalKey(Ceilings),
  pi: Schema.optionalKey(PiMeta),
});
const ModelsFileSchema = Schema.Struct({ models: Schema.optionalKey(Schema.Array(ModelEntrySchema)) });

/** Decode a models document (`{ models: [...] }`) and check it; throws ModelsFileError naming `source`. */
export function decodeModelsDoc(doc: unknown, source: string): ModelAllowlist {
  let file: typeof ModelsFileSchema.Type;
  try {
    file = Schema.decodeUnknownSync(ModelsFileSchema)(doc);
  } catch (e) {
    throw new ModelsFileError(`${source}: ${(e as Error).message}`);
  }
  const list: ModelAllowlist = file.models ?? [];
  const problems = modelAllowlistProblems(list);
  if (problems.length) throw new ModelsFileError(`${source}:\n  ${problems.join("\n  ")}`);
  return list;
}

export function parseModelsToml(text: string, source: string): ModelAllowlist {
  let doc: unknown;
  try {
    doc = parseToml(text);
  } catch (e) {
    throw new ModelsFileError(`${source}: TOML: ${(e as Error).message}`);
  }
  return decodeModelsDoc(doc, source);
}

const fileCache = new Map<string, { readonly mtimeMs: number; readonly size: number; readonly list: ModelAllowlist }>();

/**
 * The catalog in a models file, re-read whenever the file's mtime or size
 * changed (one stat per call otherwise). A missing or unparsable file throws
 * ModelsFileError: the operator's edit is wrong, and every call says so.
 */
export function loadModelsFile(path: string): ModelAllowlist {
  if (!existsSync(path)) throw new ModelsFileError(`models file ${path} does not exist (runtimes.toml models_file); seed it or unset models_file`);
  const st = statSync(path);
  const hit = fileCache.get(path);
  if (hit && hit.mtimeMs === st.mtimeMs && hit.size === st.size) return hit.list;
  const list = parseModelsToml(readFileSync(path, "utf8"), path);
  fileCache.set(path, { mtimeMs: st.mtimeMs, size: st.size, list });
  return list;
}

/** The catalog a call resolves against: the models file, else the inline list, else the compiled default. */
export function catalogFor(config: { readonly models?: ModelAllowlist; readonly modelsFile?: string }): ModelAllowlist {
  if (config.modelsFile !== undefined) return loadModelsFile(config.modelsFile);
  return config.models ?? DEFAULT_MODEL_ALLOWLIST;
}

/** The entry that `resolveModel` chose, for its metadata (ceilings, pi). */
export function entryFor(list: ModelAllowlist, harness: HarnessName, id: string | undefined, provider?: ModelProvider): ModelEntry | undefined {
  if (id === undefined) return undefined;
  const want = harness === "dsh" ? (provider ?? "gufo") : harness === "pi" ? (provider ?? "gufo") : undefined;
  return list.find((e) => e.harness === harness && providerOf(e) === want && e.id === id);
}

/** The catalog entry a model names, by full id, else by alias (any harness): what an agent session's runtime is resolved from. */
export function catalogEntry(list: ModelAllowlist, model: string): ModelEntry | undefined {
  return list.find((e) => e.id === model) ?? list.find((e) => (e.aliases ?? []).some((a) => a.toLowerCase() === model.toLowerCase()));
}
