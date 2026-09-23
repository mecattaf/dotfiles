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
 * Absent `[[models]]`, DEFAULT_MODEL_ALLOWLIST applies.
 */
import type { HarnessName } from "./harness.ts";

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
  readonly aliases?: readonly string[];
  /** The harness default when a call names no allowed model. At most one per harness. */
  readonly default?: boolean;
  readonly ceilings?: ModelCeilings;
}

export type ModelAllowlist = readonly ModelEntry[];

/**
 * Opus stays the claude default. Fable is allowed and capped on its
 * model-scoped window at 90 percent (a proposed default, REPORTED as the
 * binding limit on 2026-09-23). codex has no pinned id: an unset model lets
 * codex use its own configured default.
 */
export const DEFAULT_MODEL_ALLOWLIST: ModelAllowlist = [
  { id: "claude-opus-5-5", harness: "claude", aliases: ["opus"], default: true },
  { id: "claude-fable-5-1", harness: "claude", aliases: ["fable"], ceilings: { model_scoped: 90 } },
  { id: "halogen-qwen3.8-flash-next", harness: "pi", default: true },
];

export interface ResolvedModel {
  /** The full id that runs; undefined only for a harness with no default (codex's own default). */
  readonly id: string | undefined;
  /** What the call asked for, when it differs from what runs. */
  readonly requested?: string;
  readonly ceilings?: ModelCeilings;
}

export function resolveModel(list: ModelAllowlist, harness: HarnessName, declared: string | undefined): ResolvedModel {
  const mine = list.filter((e) => e.harness === harness);
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
    if (e.default) defaults.set(e.harness, (defaults.get(e.harness) ?? 0) + 1);
    for (const [k, v] of Object.entries(e.ceilings ?? {})) {
      if (typeof v !== "number" || !(v > 0 && v <= 100)) problems.push(`models: ${e.id} ceiling ${k} must be in (0, 100]`);
    }
  }
  for (const [h, n] of defaults) if (n > 1) problems.push(`models: harness ${h} has ${n} defaults, at most one`);
  return problems;
}
