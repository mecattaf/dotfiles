/**
 * Harnesses: how an agent() call becomes argv plus stdin, and how its stdout
 * becomes a result. Two exist today.
 *
 * - `claude`: Claude Code headless, run with the full model id the model
 *   allowlist resolved (models.ts; default `claude-opus-5-5`; never an alias,
 *   OI-6: aliases drifted to other models), JSON envelope out, the schema
 *   passed through `--json-schema` when the call has one. The prompt goes on
 *   stdin so it never appears in a process listing.
 * - `pi`: pi against Halogen, which runs on the worker only. No session is
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

export function piInvocation(call: HarnessCall): HarnessInvocation {
  const prompt = call.schema
    ? `${withCorrections(call.prompt, call.previousErrors)}\n\nReply with one JSON value only, no prose and no code fence, valid against this JSON Schema:\n${JSON.stringify(call.schema)}`
    : withCorrections(call.prompt, call.previousErrors);
  return {
    argv: ["pi", "-p", "--no-session", "--provider", HALOGEN_PROVIDER, "--model", call.model ?? HALOGEN_MODEL, "--mode", "text"],
    stdin: prompt,
  };
}

export function codexInvocation(call: HarnessCall): HarnessInvocation {
  const prompt = call.schema
    ? `${withCorrections(call.prompt, call.previousErrors)}\n\nReply with one JSON value only, no prose and no code fence, valid against this JSON Schema:\n${JSON.stringify(call.schema)}`
    : withCorrections(call.prompt, call.previousErrors);
  return {
    argv: ["codex", "exec", "--json", "--skip-git-repo-check", "--sandbox", "read-only", ...(call.model !== undefined ? ["-m", call.model] : []), "-"],
    stdin: prompt,
  };
}

export const invocationFor = (h: HarnessName, call: HarnessCall): HarnessInvocation =>
  h === "pi" ? piInvocation(call) : h === "codex" ? codexInvocation(call) : claudeInvocation(call);

export interface Parsed {
  readonly text?: string;
  readonly object?: unknown;
  readonly usage?: { readonly inputTokens: number; readonly outputTokens: number };
  readonly agentId?: string;
  readonly error?: string;
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
  const u = env.usage as { input_tokens?: number; output_tokens?: number } | undefined;
  const usage = u ? { inputTokens: u.input_tokens ?? 0, outputTokens: u.output_tokens ?? 0 } : undefined;
  const agentId = typeof env.session_id === "string" ? env.session_id : undefined;
  const base = { ...(usage ? { usage } : {}), ...(agentId ? { agentId } : {}) };
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
      const u = ev.usage as { input_tokens?: number; output_tokens?: number } | undefined;
      if (u) usage = { inputTokens: u.input_tokens ?? 0, outputTokens: u.output_tokens ?? 0 };
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
