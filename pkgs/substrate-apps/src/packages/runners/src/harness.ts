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
 *   Halogen on the strix (the default, unchanged), the Qwen token plan, or
 *   OpenRouter (paid models, and the free lane as its own provider key so it
 *   spends its own seat). The runtime table names the provider
 *   (`provider = "..."`, config.ts); the model comes from the catalog of that
 *   provider (models.ts; a provider with no entry is parked and the backend
 *   refuses before anything is dialled, so this builder always gets a model).
 *   pi resolves each key itself (`!cat /run/agenix/...` in models.json), so no
 *   credential passes through here. Since 2026-10-10 the session is SAVED into
 *   the job's own dir (`--session-dir`, archived with the transcripts so the
 *   seats oracle counts factory spend; CMP-2); a caller that gives none keeps
 *   `--no-session`. An uncatalogued model rides in a job-scoped agent dir
 *   (`PI_CODING_AGENT_DIR`, backend.ts). A schema becomes an instruction plus
 *   a JSON parse of the reply, because pi has no structured-output flag.
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
  /**
   * A retry of a session turn whose harness session already holds the attempt before (it was resumed by id): the
   * prompt reached the session then, and the tool calls it made have run, so only the corrections are sent
   * (integration pass 2026-10-13, CARRIED item 9).
   */
  readonly continued?: boolean;
  /** codex `--sandbox`; default `read-only` (a runtime table's `codexSandbox`). */
  readonly codexSandbox?: "read-only" | "workspace-write";
  /** pi's provider (a runtime table's `provider`); default `halogen`. */
  readonly piProvider?: PiProvider;
  /** pi: where this job's session is written (`--session-dir`); absent means `--no-session`. */
  readonly piSessionDir?: string;
  /** pi: a job-scoped agent dir carrying a generated models.json (`PI_CODING_AGENT_DIR`); absent means pi's own. */
  readonly piAgentDir?: string;
  /** agent({session}): the harness session this call resumes by id, and its project MCP (sessions chapter, 2026-10-12). */
  readonly session?: HarnessSession;
}

/**
 * One turn of an agent session, as the harness sees it (EXCHANGE sections 3 and 8). claude starts the session with
 * `--session-id` and resumes it with `--resume`; pi always passes `--session-id` (it creates the session if missing);
 * codex starts a thread and resumes it with `codex exec resume <thread id>`. Every harness gets the one `project` MCP.
 */
export interface HarnessSession {
  /** The harness session id: the floor-minted UUID for claude and pi, codex's own thread id once it has one. */
  readonly id: string;
  /** A later turn: the harness already holds this session (its transcript, rollout or pi session file was found by id). */
  readonly resume: boolean;
  /** The project MCP server: `<command> mcp` with its four variables. */
  readonly mcp: { readonly command: string; readonly env: Readonly<Record<string, string>> };
  /** The mcp.json written for this session; claude reads it (`--mcp-config <file> --strict-mcp-config`). */
  readonly mcpConfig: string;
  /** pi: the tools a coordinator is limited to (`--tools`); absent for a thread. */
  readonly tools?: readonly string[];
}

/** Options a harness can honour; a call asking for another is refused, never silently dropped. */
export const HARNESS_OPTIONS: Readonly<Record<HarnessName, readonly ("effort" | "agentType")[]>> = {
  claude: ["effort", "agentType"],
  // pi maps effort to `--thinking <level>` (sessions chapter, correction 7).
  pi: ["effort"],
  codex: [],
};

const correction = (errors: readonly string[]) => `Your previous reply was rejected: ${errors.join("; ")}.\nReply again, correcting exactly that.`;
const withCorrections = (prompt: string, errors: readonly string[] | undefined) =>
  errors && errors.length ? `${prompt}\n\n${correction(errors)}` : prompt;
/** The text a call sends: its prompt with the corrections, or the corrections alone on a retry the session already holds. */
const promptOf = (call: HarnessCall) =>
  call.continued && call.previousErrors && call.previousErrors.length ? correction(call.previousErrors) : withCorrections(call.prompt, call.previousErrors);

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
      ...(call.session ? [call.session.resume ? "--resume" : "--session-id", call.session.id, "--mcp-config", call.session.mcpConfig, "--strict-mcp-config"] : []),
    ],
    stdin: promptOf(call),
    env: model === CLAUDE_MODEL ? CLAUDE_SUBAGENT_ENV : { ...CLAUDE_SUBAGENT_ENV, CLAUDE_CODE_SUBAGENT_MODEL: model },
  };
}

export function piInvocation(call: HarnessCall): HarnessInvocation {
  const provider: PiProvider = call.piProvider ?? HALOGEN_PROVIDER;
  // The backend resolves the model from the catalog and refuses a parked provider first (models.ts); a bare call
  // with no model is a programming error, never a silent default (the pinned PI_DEFAULT_MODEL table is gone).
  if (call.model === undefined) throw new Error(`pi harness: no model for provider ${provider} (the catalog has no entry for it; the lane is parked)`);
  const prompt = call.schema
    ? `${promptOf(call)}\n\nReply with one JSON value only, no prose and no code fence, valid against this JSON Schema:\n${JSON.stringify(call.schema)}`
    : promptOf(call);
  return {
    argv: [
      "pi",
      "-p",
      ...(call.piSessionDir !== undefined ? ["--session-dir", call.piSessionDir] : ["--no-session"]),
      ...(call.session ? ["--session-id", call.session.id] : []),
      "--provider",
      PI_PROVIDERS[provider].pi,
      "--model",
      call.model,
      ...(call.effort !== undefined ? ["--thinking", call.effort] : []),
      // a coordinator: read and the project tools only, and no skills or context files, so its prompt holds the 9.1
      // context and nothing more (EXCHANGE section 8, amended 2026-10-13 after the step 6 replay)
      ...(call.session?.tools ? ["--tools", call.session.tools.join(","), "--no-skills", "--no-context-files"] : []),
      "--mode",
      "text",
    ],
    stdin: prompt,
    ...(call.piAgentDir !== undefined ? { env: { PI_CODING_AGENT_DIR: call.piAgentDir } } : {}),
  };
}

export function codexInvocation(call: HarnessCall): HarnessInvocation {
  const prompt = call.schema
    ? `${promptOf(call)}\n\nReply with one JSON value only, no prose and no code fence, valid against this JSON Schema:\n${JSON.stringify(call.schema)}`
    : promptOf(call);
  const mode = call.codexSandbox ?? "read-only";
  const model = call.model !== undefined ? ["-m", call.model] : [];
  const s = call.session;
  if (!s) return { argv: ["codex", "exec", "--json", "--skip-git-repo-check", "--sandbox", mode, ...model, "-"], stdin: prompt };
  // The project MCP as config overrides; `codex exec resume` has no --sandbox, so a resumed turn sets sandbox_mode.
  const mcp = ["-c", `mcp_servers.project.command=${s.mcp.command}`, "-c", `mcp_servers.project.args=["mcp"]`,
    ...Object.entries(s.mcp.env).flatMap(([k, v]) => ["-c", `mcp_servers.project.env.${k}=${v}`])];
  return {
    argv: s.resume
      ? ["codex", "exec", "resume", s.id, "--json", "--skip-git-repo-check", "-c", `sandbox_mode="${mode}"`, ...model, ...mcp, "-"]
      : ["codex", "exec", "--json", "--skip-git-repo-check", "--sandbox", mode, ...model, ...mcp, "-"],
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
  /** claude's `total_cost_usd`, when the envelope carries it. */
  readonly costUsd?: number;
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
  const cost = typeof env.total_cost_usd === "number" && Number.isFinite(env.total_cost_usd) && env.total_cost_usd >= 0 ? env.total_cost_usd : undefined;
  const usage = u && typeof u === "object" ? { ...claudeUsage(u), ...(cost !== undefined ? { costUsd: cost } : {}) } : undefined;
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
