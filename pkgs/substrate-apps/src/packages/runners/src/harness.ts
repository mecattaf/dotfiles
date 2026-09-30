/**
 * Harnesses: how an agent() call becomes argv plus stdin, and how its stdout
 * becomes a result. Two exist today.
 *
 * - `claude`: Claude Code headless, run with the full model id the model
 *   allowlist resolved (models.ts; default `claude-opus-5-5`; never an alias,
 *   OI-6: aliases drifted to other models), JSON envelope out, the schema
 *   passed through `--json-schema` when the call has one. The prompt goes on
 *   stdin so it never appears in a process listing.
 * - `pi`: pi against one PROVIDER of `~/.pi/agent/models.json` (PI_PROVIDERS):
 *   Halogen on the worker (the default, unchanged), the Qwen token plan, or
 *   OpenRouter (paid models, and the free stealth model as its own provider
 *   key so it spends its own seat). The runtime table names the provider
 *   (`provider = "..."`, config.ts); the model comes from the allowlist of that
 *   provider (models.ts). pi resolves each key itself (`!cat /run/agenix/...`
 *   in models.json), so no credential passes through here. No session is
 *   saved. A schema becomes an instruction plus a JSON parse of the reply,
 *   because pi has no structured-output flag.
 * - `codex`: `codex exec --json`, non-interactive, prompt on stdin (`-`),
 *   `-m <id>` when the allowlist names one (else codex's own default). A real
 *   codex runs only when `[seats]` binds the codex harness to a capacity seat
 *   (backend.ts); tests run a fake binary under the test guard. The JSONL
 *   event shape parsed here (`thread.started` with thread_id, `item.completed`
 *   with an `agent_message`, `turn.completed` with usage) was MEASURED against
 *   codex-cli 0.155.1 on 2026-09-23 (gap G9 closed).
 */

export const CLAUDE_MODEL = "claude-opus-5-5";
export const HALOGEN_PROVIDER = "halogen";
export const HALOGEN_MODEL = "halogen-qwen3.8-flash-next";

export type HarnessName = "claude" | "pi" | "codex";

/**
 * The pi providers a runtime table may name (`provider = "..."`), each with
 * the `--provider` pi is started with and the seat PROVIDER its capacity
 * reading carries (the gate refuses a call whose seat is another provider's).
 * `openrouter-free` is OpenRouter's free model: the same pi provider, its own
 * seat (a daily request quota, not the paid soft cap).
 */
export const PI_PROVIDERS = {
  halogen: { pi: "halogen", seatProvider: "halogen", seat: "halogen" },
  "qwen-token-plan": { pi: "qwen-token-plan", seatProvider: "qwen", seat: "pi-qwencloud" },
  openrouter: { pi: "openrouter", seatProvider: "openrouter", seat: "openrouter" },
  "openrouter-free": { pi: "openrouter", seatProvider: "openrouter", seat: "openrouter-free" },
} as const satisfies Readonly<Record<string, { readonly pi: string; readonly seatProvider: string; readonly seat: string }>>;
export type PiProvider = keyof typeof PI_PROVIDERS;
export const PI_PROVIDER_NAMES = Object.keys(PI_PROVIDERS) as readonly PiProvider[];
export const isPiProvider = (v: unknown): v is PiProvider => typeof v === "string" && Object.hasOwn(PI_PROVIDERS, v);

export interface HarnessCall {
  readonly prompt: string;
  /** The full model id to run (models.ts resolveModel). Absent: the harness's pinned default, or codex's own. */
  readonly model?: string;
  readonly schema?: Record<string, unknown>;
  /** agent({effort}): claude `--effort`. */
  readonly effort?: string;
  /** agent({agentType}): claude `--agent`. */
  readonly agentType?: string;
  /**
   * Why the previous attempt's reply was rejected (schema errors, no JSON).
   * Appended to the prompt from attempt 2 on, for every harness, so the model
   * sees what to correct (successor review r2: retries resent the identical prompt).
   */
  readonly previousErrors?: readonly string[];
  /** codex `--sandbox`; default `read-only` (a runtime table's `codexSandbox`). */
  readonly codexSandbox?: "read-only" | "workspace-write";
  /** pi's provider (a runtime table's `provider`); default `halogen`. */
  readonly piProvider?: PiProvider;
}

/** Options a harness can honour; a call asking for another is refused, never silently dropped. */
export const HARNESS_OPTIONS: Readonly<Record<HarnessName, readonly ("effort" | "agentType")[]>> = {
  claude: ["effort", "agentType"],
  pi: [],
  codex: [],
};

const withCorrections = (prompt: string, errors: readonly string[] | undefined) =>
  errors && errors.length
    ? `${prompt}\n\nYour previous reply was rejected: ${errors.join("; ")}.\nReply again, correcting exactly that.`
    : prompt;

export interface HarnessInvocation {
  readonly argv: readonly string[];
  readonly stdin: string;
  /** Environment the harness needs on every runtime (merged into job.env). */
  readonly env?: Readonly<Record<string, string>>;
}

/**
 * The claude harness pins its subagents too: without these, the Agent tool's
 * `model` parameter (or an agent's frontmatter) can run Haiku or Sonnet on the
 * seat (successor review r5, REPORTED from the claude 2.1.280 resolver).
 */
export const CLAUDE_SUBAGENT_ENV: Readonly<Record<string, string>> = {
  CLAUDE_CODE_SUBAGENT_MODEL: CLAUDE_MODEL,
  CLAUDE_CODE_SUBAGENT_MODEL_FORCE: "1",
};

export function claudeInvocation(call: HarnessCall): HarnessInvocation {
  const model = call.model ?? CLAUDE_MODEL;
  return {
    argv: [
      "claude",
      "-p",
      "--model",
      model,
      "--output-format",
      "json",
      "--dangerously-skip-permissions",
      ...(call.effort !== undefined ? ["--effort", call.effort] : []),
      ...(call.agentType !== undefined ? ["--agent", call.agentType] : []),
      ...(call.schema ? ["--json-schema", JSON.stringify(call.schema)] : []),
    ],
    stdin: withCorrections(call.prompt, call.previousErrors),
    env: model === CLAUDE_MODEL ? CLAUDE_SUBAGENT_ENV : { ...CLAUDE_SUBAGENT_ENV, CLAUDE_CODE_SUBAGENT_MODEL: model },
  };
}

/**
 * Each pi provider's pinned model when the allowlist resolves none (models.ts
 * DEFAULT_MODEL_ALLOWLIST names the same ids as its defaults).
 */
export const PI_DEFAULT_MODEL: Readonly<Record<PiProvider, string>> = {
  halogen: HALOGEN_MODEL,
  "qwen-token-plan": "qwen3.8-max",
  openrouter: "deepseek/deepseek-v4-pro",
  "openrouter-free": "stealth/space-bunny-alpha",
};

export function piInvocation(call: HarnessCall): HarnessInvocation {
  const provider: PiProvider = call.piProvider ?? HALOGEN_PROVIDER;
  const prompt = call.schema
    ? `${withCorrections(call.prompt, call.previousErrors)}\n\nReply with one JSON value only, no prose and no code fence, valid against this JSON Schema:\n${JSON.stringify(call.schema)}`
    : withCorrections(call.prompt, call.previousErrors);
  return {
    argv: ["pi", "-p", "--no-session", "--provider", PI_PROVIDERS[provider].pi, "--model", call.model ?? PI_DEFAULT_MODEL[provider], "--mode", "text"],
    stdin: prompt,
  };
}

export function codexInvocation(call: HarnessCall): HarnessInvocation {
  const prompt = call.schema
    ? `${withCorrections(call.prompt, call.previousErrors)}\n\nReply with one JSON value only, no prose and no code fence, valid against this JSON Schema:\n${JSON.stringify(call.schema)}`
    : withCorrections(call.prompt, call.previousErrors);
  return {
    argv: ["codex", "exec", "--json", "--skip-git-repo-check", "--sandbox", call.codexSandbox ?? "read-only", ...(call.model !== undefined ? ["-m", call.model] : []), "-"],
    stdin: prompt,
  };
}

export const invocationFor = (h: HarnessName, call: HarnessCall): HarnessInvocation =>
  h === "pi" ? piInvocation(call) : h === "codex" ? codexInvocation(call) : claudeInvocation(call);

export interface Parsed {
  readonly text?: string;
  readonly object?: unknown;
  readonly usage?: Usage;
  readonly agentId?: string;
  readonly error?: string;
  /** The model(s) that answered, as the harness reports them (claude `modelUsage` keys), comma-joined. */
  readonly answeringModel?: string;
}

/**
 * Token usage from a harness envelope. inputTokens and outputTokens are what budgets count (D10); the cache and
 * reasoning counts are carried when the harness reports them (parity gap PT-04: tally's usage parsers kept them,
 * the port had dropped them). A key is present only when the envelope carried it.
 */
export interface Usage {
  readonly inputTokens: number;
  readonly outputTokens: number;
  readonly cacheCreationTokens?: number;
  readonly cacheReadTokens?: number;
  readonly reasoningTokens?: number;
}

const count = (v: unknown): number | undefined => (typeof v === "number" && Number.isFinite(v) && v >= 0 ? v : undefined);
const extra = (o: Record<string, number | undefined>): Partial<Usage> =>
  Object.fromEntries(Object.entries(o).filter(([, v]) => v !== undefined)) as Partial<Usage>;

/** Claude Code's envelope usage: cache_creation_input_tokens, cache_read_input_tokens, output_tokens_details.thinking_tokens. */
export function claudeUsage(u: Record<string, unknown>): Usage {
  const details = (u.output_tokens_details ?? {}) as Record<string, unknown>;
  return {
    inputTokens: count(u.input_tokens) ?? 0,
    outputTokens: count(u.output_tokens) ?? 0,
    ...extra({ cacheCreationTokens: count(u.cache_creation_input_tokens), cacheReadTokens: count(u.cache_read_input_tokens), reasoningTokens: count(details.thinking_tokens) }),
  };
}

/** codex `turn.completed` usage: cached_input_tokens, cache_write_input_tokens, reasoning_output_tokens. */
export function codexUsage(u: Record<string, unknown>): Usage {
  return {
    inputTokens: count(u.input_tokens) ?? 0,
    outputTokens: count(u.output_tokens) ?? 0,
    ...extra({ cacheCreationTokens: count(u.cache_write_input_tokens), cacheReadTokens: count(u.cached_input_tokens), reasoningTokens: count(u.reasoning_output_tokens) }),
  };
}

const stripFence = (s: string) => {
  const m = /^\s*```(?:json)?\s*\n([\s\S]*?)\n\s*```\s*$/.exec(s);
  return m ? m[1]! : s.trim();
};

/**
 * A reply that is not JSON is a MISSING object, not a backend error: the
 * interpreter then retries it as "no structured output" with the reason in
 * previousErrors (successor review r2: 'Sure! {"n": 3}' failed after one attempt).
 */
function parseJsonReply(text: string): { object?: unknown; text?: string } {
  try {
    return { object: JSON.parse(stripFence(text)) };
  } catch {
    return { text };
  }
}

/** Claude Code's `--output-format json` envelope. */
export function parseClaude(stdout: string, wantObject: boolean): Parsed {
  let env: Record<string, unknown>;
  try {
    env = JSON.parse(stdout.trim());
  } catch (e) {
    return { error: `claude stdout is not a JSON envelope: ${(e as Error).message}: ${stdout.slice(0, 200)}` };
  }
  const u = env.usage as Record<string, unknown> | undefined;
  const usage = u && typeof u === "object" ? claudeUsage(u) : undefined;
  const agentId = typeof env.session_id === "string" ? env.session_id : undefined;
  const mu = env.modelUsage;
  const models = mu !== null && typeof mu === "object" && !Array.isArray(mu) ? Object.keys(mu).sort() : [];
  const base = { ...(usage ? { usage } : {}), ...(agentId ? { agentId } : {}), ...(models.length ? { answeringModel: models.join(",") } : {}) };
  if (env.is_error === true || (typeof env.subtype === "string" && env.subtype !== "success")) {
    return { ...base, error: `claude reported ${String(env.subtype)}: ${String(env.result ?? "").slice(0, 300)}` };
  }
  const result = typeof env.result === "string" ? env.result : "";
  if (!wantObject) return { ...base, text: result };
  if (env.structured_output !== undefined) return { ...base, object: env.structured_output };
  return { ...base, ...parseJsonReply(result) };
}

export function parsePi(stdout: string, wantObject: boolean): Parsed {
  const text = stdout.trim();
  if (!wantObject) return { text };
  return parseJsonReply(text);
}

/** `codex exec --json`: one JSON event per line; the last agent message is the reply. */
export function parseCodex(stdout: string, wantObject: boolean): Parsed {
  let text: string | undefined;
  let usage: Parsed["usage"];
  let agentId: string | undefined;
  let failure: string | undefined;
  for (const line of stdout.split("\n")) {
    if (line.trim() === "") continue;
    let ev: Record<string, unknown>;
    try {
      ev = JSON.parse(line);
    } catch {
      continue;
    }
    const item = ev.item as { type?: string; text?: string } | undefined;
    if (ev.type === "thread.started" && typeof ev.thread_id === "string") agentId = ev.thread_id;
    if (ev.type === "item.completed" && item?.type === "agent_message" && typeof item.text === "string") text = item.text;
    if (ev.type === "turn.completed") {
      const u = ev.usage as Record<string, unknown> | undefined;
      if (u && typeof u === "object") usage = codexUsage(u);
    }
    if (ev.type === "turn.failed" || ev.type === "error") failure = JSON.stringify(ev).slice(0, 300);
  }
  const base = { ...(usage ? { usage } : {}), ...(agentId ? { agentId } : {}) };
  if (failure !== undefined) return { ...base, error: `codex reported a failure: ${failure}` };
  if (text === undefined) return { ...base, error: "codex stdout carried no agent_message" };
  return wantObject ? { ...base, ...parseJsonReply(text) } : { ...base, text };
}

export const parseFor = (h: HarnessName, stdout: string, wantObject: boolean): Parsed =>
  h === "pi" ? parsePi(stdout, wantObject) : h === "codex" ? parseCodex(stdout, wantObject) : parseClaude(stdout, wantObject);
