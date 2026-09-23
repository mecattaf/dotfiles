/**
 * FM-2 of the 2026-09-23 field map: the ax Task this scheduler dispatches,
 * with the FIELD-MAP section 5a env keys and the pre-dispatch size check.
 *
 * Why a HARD check (FIELD-MAP section 3, PROBE test 4, REPORTED): the ax v0.3.0
 * controller copies every env value a second time into `AX_TASK_YAML`, and
 * Substrate caps each env value at 32768 bytes. Past that the controller logs
 * a warning, falls back to the default template, and the Task shows `Running`
 * without its own image or env. So this module never relies on the controller
 * to fail: at or under 16384 bytes of env values the prompt goes inline; above
 * that it goes to the prompt-file route if the caller has one; otherwise, and
 * whenever the remaining env or the estimated AX_TASK_YAML is still too big,
 * the Task is REFUSED before it is sent.
 *
 * Pure: no clock, no filesystem. The prompt-file route, when present, is a
 * function the caller supplies (it must have written the file).
 */
import { DEFAULT_MODEL_ALLOWLIST } from "@substrate/runners";
import { createHash } from "node:crypto";
import type { AxTask } from "./axclient.ts";
import type { WorkItem } from "./schema.ts";

/** FIELD-MAP 5a: the inline budget for the sum of all env values. */
export const ENV_INLINE_BUDGET_BYTES = 16384;
/** Substrate's per-value guardrail, applied to AX_TASK_YAML. */
export const AX_TASK_YAML_CEILING_BYTES = 32768;
export const RESULT_PATH = "/workspace/.ax/result.json";
export const USAGE_PATH = "/workspace/.ax/usage.json";

/**
 * The model ids a Task may run: each harness's pinned full id (runners
 * harness.ts CLAUDE_MODEL, HALOGEN_MODEL). Never an alias, never the record's
 * own model (successor review r3: the record-to-ax watcher posted Tasks
 * running claude-fable-5-1, claude-opus-5[1m] and the alias sonnet).
 */
export const PINNED_TASK_MODELS: ReadonlySet<string> = new Set(
  DEFAULT_MODEL_ALLOWLIST.filter((m) => m.harness !== "codex").map((m) => m.id),
);

export interface TaskContext {
  /** The seat id the Task is for (`cc`, `halogen`). */
  readonly seat: string;
  /**
   * The model the harness that runs this Task is pinned to. Given, it is the
   * Task's AX_CONWIP_MODEL and must be a pinned id (else the Task is
   * refused); the item's own model is kept as AX_CONWIP_RECORD_MODEL,
   * provenance only. Absent, the item's model is the Task's (the CONWIP's
   * items already carry the route's pinned model).
   */
  readonly model?: string;
  /** 1-based; defaults to the item's own attempt, else 1. */
  readonly attempt?: number;
  /** Which occurrence of the same (prompt, opts) within the run; default 1. */
  readonly occurrence?: number;
  /** Compact JSON Schema text, when the agent() call carried a schema. */
  readonly schemaJson?: string;
  readonly isolation?: string;
  readonly agentType?: string;
  /** `<atespace>/<name>` of a parent Task, for a nested workflow(). */
  readonly parent?: string;
  /**
   * The prompt-file route. Given the prompt's sha256 and its 8-char key, it
   * returns the in-sandbox path of a file it has ALREADY written, or undefined
   * when no route exists. Absent, an oversize prompt is refused.
   */
  readonly promptFile?: (sha256: string, key8: string) => string | undefined;
}

export type TaskBuild =
  | { readonly ok: true; readonly task: AxTask; readonly route: "inline" | "file"; readonly envBytes: number; readonly yamlBytesEstimate: number }
  | { readonly ok: false; readonly reason: string; readonly envBytes: number };

const sha256 = (s: string): string => createHash("sha256").update(s, "utf8").digest("hex");
const bytes = (s: string): number => Buffer.byteLength(s, "utf8");

/** An ax object name: lowercase, dots and underscores folded to dashes. */
export function taskNameFor(i: WorkItem): string {
  return `${i.runId}-${i.index}`.toLowerCase().replace(/[^a-z0-9-]/g, "-");
}

/** Canonical JSON: keys sorted at every depth. */
function canonical(v: unknown): string {
  if (Array.isArray(v)) return `[${v.map(canonical).join(",")}]`;
  if (v !== null && typeof v === "object") {
    const o = v as Record<string, unknown>;
    return `{${Object.keys(o).filter((k) => o[k] !== undefined).sort().map((k) => `${JSON.stringify(k)}:${canonical(o[k])}`).join(",")}}`;
  }
  return JSON.stringify(v);
}

/** FIELD-MAP 5a: sha256 of canonical [prompt, opts minus label], then the occurrence. */
export function journalKey(prompt: string, opts: Readonly<Record<string, unknown>>, occurrence: number): string {
  const { label: _label, ...rest } = opts;
  return `${sha256(canonical([prompt, rest]))}:${occurrence}`;
}

/** Build the Task, or refuse it with the reason. */
export function buildTask(i: WorkItem, atespace: string, image: string, ctx: TaskContext): TaskBuild {
  const promptSha = sha256(i.prompt);
  const key8 = promptSha.slice(0, 8);
  const attempt = ctx.attempt ?? i.attempt ?? 1;
  if (ctx.model !== undefined && !PINNED_TASK_MODELS.has(ctx.model)) {
    return { ok: false, reason: `model ${JSON.stringify(ctx.model)} is not a pinned id (${[...PINNED_TASK_MODELS].join(", ")})`, envBytes: 0 };
  }
  const model = ctx.model ?? i.model;
  const opts: Record<string, unknown> = {
    model, effort: i.effort, schema: ctx.schemaJson, isolation: ctx.isolation, agentType: ctx.agentType,
  };
  const env: Array<{ name: string; value: string }> = [
    { name: "AX_CONWIP_RUN_ID", value: i.runId },
    { name: "AX_CONWIP_LABEL", value: i.label },
    { name: "AX_CONWIP_MODEL", value: model },
    { name: "AX_CONWIP_ITEM_KEY", value: `${i.runId}#${i.index}` },
    { name: "AX_CONWIP_JOURNAL_KEY", value: journalKey(i.prompt, opts, ctx.occurrence ?? 1) },
    { name: "AX_CONWIP_WORKFLOW", value: i.workflowName },
    { name: "AX_CONWIP_PHASE_INDEX", value: String(i.phaseIndex) },
    { name: "AX_CONWIP_PHASE_TITLE", value: i.phaseTitle },
    { name: "AX_CONWIP_SEAT", value: ctx.seat },
    { name: "AX_CONWIP_ATTEMPT", value: String(attempt) },
    { name: "AX_CONWIP_PROMPT_SHA256", value: promptSha },
    { name: "AX_CONWIP_RESULT_PATH", value: RESULT_PATH },
    { name: "AX_CONWIP_USAGE_PATH", value: USAGE_PATH },
  ];
  if (model !== i.model) env.push({ name: "AX_CONWIP_RECORD_MODEL", value: i.model });
  if (i.effort !== undefined) env.push({ name: "AX_CONWIP_EFFORT", value: i.effort });
  if (ctx.schemaJson !== undefined) env.push({ name: "AX_CONWIP_SCHEMA_JSON", value: ctx.schemaJson });
  if (ctx.isolation !== undefined) {
    env.push({ name: "AX_CONWIP_ISOLATION", value: ctx.isolation });
    env.push({ name: "AX_CONWIP_BRANCH", value: `uc/${i.runId.toLowerCase().replace(/[^a-z0-9-]/g, "-")}/${i.index}` });
  }
  if (ctx.agentType !== undefined) env.push({ name: "AX_CONWIP_AGENT_TYPE", value: ctx.agentType });
  if (ctx.parent !== undefined) env.push({ name: "AX_CONWIP_PARENT", value: ctx.parent });

  const sum = (e: ReadonlyArray<{ value: string }>) => e.reduce((n, x) => n + bytes(x.value), 0);
  const base = sum(env);
  let route: "inline" | "file";
  if (base + bytes(i.prompt) <= ENV_INLINE_BUDGET_BYTES) {
    env.push({ name: "AX_CONWIP_PROMPT", value: i.prompt });
    route = "inline";
  } else {
    const path = ctx.promptFile?.(promptSha, key8);
    if (path === undefined) {
      return {
        ok: false,
        reason: `env would be ${base + bytes(i.prompt)} bytes with the prompt inline (budget ${ENV_INLINE_BUDGET_BYTES}) and no prompt-file route is configured; ax would silently fall back to its default template`,
        envBytes: base + bytes(i.prompt),
      };
    }
    env.push({ name: "AX_CONWIP_PROMPT_FILE", value: path });
    route = "file";
  }
  const envBytes = sum(env);
  if (envBytes > ENV_INLINE_BUDGET_BYTES) {
    return { ok: false, reason: `env values total ${envBytes} bytes even with the prompt on the file route (budget ${ENV_INLINE_BUDGET_BYTES})`, envBytes };
  }
  const task: AxTask = {
    apiVersion: "ax/v1alpha1",
    kind: "Task",
    metadata: { name: taskNameFor(i), atespace },
    spec: { image, env },
  };
  // AX_TASK_YAML holds the whole Task again. JSON is a conservative stand-in
  // for its YAML (escapes cost at least as much as YAML's quoting).
  const yamlBytesEstimate = bytes(JSON.stringify(task));
  if (yamlBytesEstimate > AX_TASK_YAML_CEILING_BYTES) {
    return { ok: false, reason: `the Task would serialize to about ${yamlBytesEstimate} bytes, over the ${AX_TASK_YAML_CEILING_BYTES}-byte AX_TASK_YAML ceiling`, envBytes };
  }
  return { ok: true, task, route, envBytes, yamlBytesEstimate };
}
