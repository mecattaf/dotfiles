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
 * means `halogen`): a call on a runtime whose table names that provider
 * resolves against that provider's entries only, so an OpenRouter runtime
 * can never run a Halogen id or the reverse.
 *
 * Absent `[[models]]`, DEFAULT_MODEL_ALLOWLIST applies.
 */
import type { HarnessName, PiProvider } from "./harness.ts";

/** Utilization ceilings in percent: at or above one, the capacity gate refuses this model. */
export interface ModelCeilings {
  readonly five_hour?: number;
  readonly seven_day?: number;
  /** The provider's model-scoped window for this model's family (for example the weekly Fable bar). */
  readonly model_scoped?: number;
}

export interface ModelEntry {
  readonly id: string;
  readonly harness: HarnessName;
  /** pi only: the provider this id is served by (harness.ts PI_PROVIDERS). Absent: halogen. */
  readonly provider?: PiProvider;
  readonly aliases?: readonly string[];
  /** The harness default when a call names no allowed model. At most one per harness (per provider for pi). */
  readonly default?: boolean;
  readonly ceilings?: ModelCeilings;
}

export type ModelAllowlist = readonly ModelEntry[];

/**
 * Opus stays the claude default. Fable is allowed and capped on its
 * model-scoped window at 90 percent (a proposed default, REPORTED as the
 * binding limit on 2026-09-23). codex has no pinned id: an unset model lets
 * codex use its own configured default.
 *
 * pi, per provider (2026-09-30, Tom's budget rulings for the overnight run):
 *   - halogen: the worker's Flash model, unchanged.
 *   - qwen-token-plan: qwen3.8-max, the plan's flagship (weekly credits, not dollars).
 *   - openrouter (paid, soft cap $12 on the seat): ids and prices from the
 *     anonymous GET https://openrouter.ai/api/v1/models on 2026-09-30, USD per
 *     million tokens in/out, each present in pi 0.99.1's openrouter catalog:
 *       deepseek/deepseek-v4-pro     $0.78 / $1.57  (default: strong coding, 1M ctx, cheap enough for a $12 night)
 *       minimax/minimax-m3           $0.30 / $1.20  (agentic coding, 1M ctx)
 *       qwen/qwen3.8-max-0902        $2.00 / $6.00
 *       anthropic/claude-sonnet-5.5  $2.00 / $10.00 (explicit only: one long node can spend dollars)
 *   - openrouter-free: stealth/space-bunny-alpha, $0 (1,000 free requests a day on the key; 1M ctx, tools, reasoning).
 */
export const DEFAULT_MODEL_ALLOWLIST: ModelAllowlist = [
  { id: "claude-opus-5-5", harness: "claude", aliases: ["opus"], default: true },
  { id: "claude-fable-5-1", harness: "claude", aliases: ["fable"], ceilings: { model_scoped: 90 } },
  { id: "halogen-qwen3.8-flash-next", harness: "pi", default: true },
  { id: "qwen3.8-max", harness: "pi", provider: "qwen-token-plan", default: true },
  { id: "deepseek/deepseek-v4-pro", harness: "pi", provider: "openrouter", aliases: ["deepseek"], default: true },
  { id: "minimax/minimax-m3", harness: "pi", provider: "openrouter", aliases: ["minimax"] },
  { id: "qwen/qwen3.8-max-0902", harness: "pi", provider: "openrouter", aliases: ["qwen-max"] },
  { id: "anthropic/claude-sonnet-5.5", harness: "pi", provider: "openrouter" },
  { id: "stealth/space-bunny-alpha", harness: "pi", provider: "openrouter-free", default: true },
];

/** The provider an entry belongs to: its own for pi (default halogen), none for the other harnesses. */
const providerOf = (e: ModelEntry): PiProvider | undefined => (e.harness === "pi" ? (e.provider ?? "halogen") : undefined);

export interface ResolvedModel {
  /** The full id that runs; undefined only for a harness with no default (codex's own default). */
  readonly id: string | undefined;
  /** What the call asked for, when it differs from what runs. */
  readonly requested?: string;
  readonly ceilings?: ModelCeilings;
}

export function resolveModel(list: ModelAllowlist, harness: HarnessName, declared: string | undefined, provider?: PiProvider): ResolvedModel {
  const want = harness === "pi" ? (provider ?? "halogen") : undefined;
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
    if (ids.has(e.id)) problems.push(`models: ${e.id} is listed twice`);
    ids.add(e.id);
    if (e.provider !== undefined && e.harness !== "pi") problems.push(`models: ${e.id} names provider ${e.provider}, which only a pi entry may`);
    const slot = e.harness === "pi" ? `pi (provider ${providerOf(e)})` : e.harness;
    if (e.default) defaults.set(slot, (defaults.get(slot) ?? 0) + 1);
    for (const [k, v] of Object.entries(e.ceilings ?? {})) {
      if (typeof v !== "number" || !(v > 0 && v <= 100)) problems.push(`models: ${e.id} ceiling ${k} must be in (0, 100]`);
    }
  }
  for (const [h, n] of defaults) if (n > 1) problems.push(`models: harness ${h} has ${n} defaults, at most one`);
  return problems;
}
