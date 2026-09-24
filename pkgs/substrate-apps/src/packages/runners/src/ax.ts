/**
 * `ax`: the seam onto ax, Agent Substrate and Kubernetes. It computes the Task
 * one agent() call would become, with the exact FIELD-MAP 5a keys and the hard
 * pre-dispatch byte check, and it never dispatches: no k3s, Substrate, Redis or
 * ax-server runs on the fleet (EVAL-REPORT R4), and stock v0.3.0 would hold a
 * WIP slot forever on a clean exit (FM-1) until carried patch P1 lands.
 *
 * The runner refuses every job; `axTaskSpec` is what a future dispatcher sends.
 */
import { createHash } from "node:crypto";
import { refusal, type Runner } from "./job.ts";

export const AX_NOT_DISPATCHED =
  "ax seam is spec-only: no k3s, Agent Substrate, Redis or ax-server runs on the fleet (EVAL R4), and v0.3.0 needs carried patch P1 before a clean exit frees its slot";

/** Env budget per FIELD-MAP 5a (PROBE test 4 falls back silently above 26412 bytes). */
export const INLINE_ENV_BUDGET = 16384;

export interface AxCall {
  readonly runId: string;
  readonly index: number;
  readonly label: string;
  readonly prompt: string;
  readonly model: string;
  readonly journalKey: string;
  readonly workflow: string;
  readonly phaseIndex: number;
  readonly phaseTitle: string;
  readonly seat: string;
  readonly attempt: number;
  readonly effort?: string;
  readonly schema?: Record<string, unknown>;
  readonly isolation?: string;
  readonly agentType?: string;
  readonly parent?: string;
}

export interface AxOptions {
  readonly atespace?: string;
  readonly sandboxClass?: "gvisor" | "microvm";
  readonly image?: string;
}

export interface AxTask {
  readonly atespace: string;
  readonly name: string;
  readonly spec: {
    readonly image: string;
    readonly command: readonly string[];
    readonly gateway: { readonly name: string };
    readonly sandboxClass: string;
    readonly env: readonly { readonly name: string; readonly value: string }[];
  };
  readonly labels: Readonly<Record<string, string>>;
  readonly annotations: Readonly<Record<string, string>>;
  /** Present when the prompt left the env: the file the run's branch must carry. */
  readonly promptFile?: { readonly path: string; readonly sha256: string };
  readonly envBytes: number;
}

export const fold = (runId: string) =>
  runId
    .toLowerCase()
    .replace(/[^a-z0-9-]+/g, "-")
    .replace(/^-+|-+$/g, "");

const sha256 = (s: string) => createHash("sha256").update(s).digest("hex");

/** The Task for one call, or a refusal when even the file route leaves the env over budget. */
export function axTaskSpec(call: AxCall, o: AxOptions = {}): AxTask | { refused: string } {
  const atespace = o.atespace ?? "ultracode";
  const key8 = call.journalKey.slice(0, 8);
  const name = `${fold(call.runId)}-${call.index}-${key8}`;
  const promptSha = sha256(call.prompt);
  const base: [string, string][] = [
    ["AX_CONWIP_RUN_ID", call.runId],
    ["AX_CONWIP_LABEL", call.label],
    ["AX_CONWIP_MODEL", call.model],
    ["AX_CONWIP_ITEM_KEY", `${call.runId}#${call.index}`],
    ["AX_CONWIP_JOURNAL_KEY", call.journalKey],
    ["AX_CONWIP_WORKFLOW", call.workflow],
    ["AX_CONWIP_PHASE_INDEX", String(call.phaseIndex)],
    ["AX_CONWIP_PHASE_TITLE", call.phaseTitle],
    ["AX_CONWIP_SEAT", call.seat],
    ["AX_CONWIP_ATTEMPT", String(call.attempt)],
    ...(call.effort !== undefined ? ([["AX_CONWIP_EFFORT", call.effort]] as [string, string][]) : []),
    ...(call.schema ? ([["AX_CONWIP_SCHEMA_JSON", JSON.stringify(call.schema)]] as [string, string][]) : []),
    ["AX_CONWIP_PROMPT_SHA256", promptSha],
    ["AX_CONWIP_RESULT_PATH", "/workspace/.ax/result.json"],
    ["AX_CONWIP_USAGE_PATH", "/workspace/.ax/usage.json"],
    ...(call.isolation
      ? ([
          ["AX_CONWIP_ISOLATION", call.isolation],
          ["AX_CONWIP_BRANCH", `uc/${fold(call.runId)}/${call.index}`],
        ] as [string, string][])
      : []),
    ...(call.agentType !== undefined ? ([["AX_CONWIP_AGENT_TYPE", call.agentType]] as [string, string][]) : []),
    ...(call.parent !== undefined ? ([["AX_CONWIP_PARENT", call.parent]] as [string, string][]) : []),
  ];
  const bytes = (kv: [string, string][]) => kv.reduce((n, [, v]) => n + Buffer.byteLength(v, "utf8"), 0);
  let env = [...base, ["AX_CONWIP_PROMPT", call.prompt] as [string, string]];
  let promptFile: AxTask["promptFile"];
  if (bytes(env) > INLINE_ENV_BUDGET) {
    const path = `/workspace/.ultracode/${key8}/prompt.md`;
    env = [...base, ["AX_CONWIP_PROMPT_FILE", path]];
    promptFile = { path, sha256: promptSha };
    if (bytes(env) > INLINE_ENV_BUDGET) {
      return { refused: `env is ${bytes(env)} bytes without the prompt, over the ${INLINE_ENV_BUDGET} byte budget` };
    }
  }
  const labels: Record<string, string> = {
    "ultracode.mecattaf.dev/run-id": fold(call.runId),
    "ultracode.mecattaf.dev/workflow": fold(call.workflow).slice(0, 63),
    "ultracode.mecattaf.dev/phase-index": String(call.phaseIndex),
    "ultracode.mecattaf.dev/seat": call.seat,
    "ultracode.mecattaf.dev/journal-key": call.journalKey.slice(0, 32),
    ...(call.parent ? { "ultracode.mecattaf.dev/parent": fold(call.parent).slice(0, 63) } : {}),
    "app.kubernetes.io/managed-by": "substrate",
    "app.kubernetes.io/part-of": "ultracode",
  };
  const annotations: Record<string, string> = {
    "ultracode.mecattaf.dev/run-id-raw": call.runId,
    "ultracode.mecattaf.dev/label": call.label,
    "ultracode.mecattaf.dev/item-key": `${call.runId}#${call.index}`,
    "ultracode.mecattaf.dev/phase-title": call.phaseTitle,
    "ultracode.mecattaf.dev/model": call.model,
    ...(call.effort !== undefined ? { "ultracode.mecattaf.dev/effort": call.effort } : {}),
    "ultracode.mecattaf.dev/attempt": String(call.attempt),
  };
  return {
    atespace,
    name,
    spec: {
      image: o.image ?? "substrate/agent:unbuilt",
      command: ["ultracode-agent"],
      gateway: { name: "ultracode-egress" },
      sandboxClass: o.sandboxClass === "microvm" ? "microvm" : "",
      env: env.map(([n, value]) => ({ name: n, value })),
    },
    labels,
    annotations,
    ...(promptFile ? { promptFile } : {}),
    envBytes: bytes(env),
  };
}

export function axRunner(name: string): Runner {
  return {
    name,
    type: "ax",
    refuses: () => AX_NOT_DISPATCHED,
    run: async (job) => refusal(name, job, AX_NOT_DISPATCHED),
  };
}
