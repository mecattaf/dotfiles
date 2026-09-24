import { describe, expect, it } from "vitest";
import { RunnerBackend, TEST_SEAT_ENV } from "../src/backend.ts";
import { parseRuntimesToml } from "../src/config.ts";
import { claudeInvocation, codexInvocation, parseCodex } from "../src/harness.ts";
import type { Job, ProcessJob, Runner } from "../src/job.ts";
import { DEFAULT_MODEL_ALLOWLIST, resolveModel } from "../src/models.ts";
import { tmp } from "./helpers.ts";

describe("model allowlist (replaces opusOnly)", () => {
  it("fable is allowed and runs by full id; opus stays the default; an unknown model is rewritten, visibly", () => {
    expect(resolveModel(DEFAULT_MODEL_ALLOWLIST, "claude", "fable")).toMatchObject({ id: "claude-fable-5-1", requested: "fable", ceilings: { model_scoped: 90 } });
    expect(resolveModel(DEFAULT_MODEL_ALLOWLIST, "claude", "claude-fable-5-1").requested).toBeUndefined();
    expect(resolveModel(DEFAULT_MODEL_ALLOWLIST, "claude", undefined).id).toBe("claude-opus-5-5");
    expect(resolveModel(DEFAULT_MODEL_ALLOWLIST, "claude", "sonnet")).toEqual({ id: "claude-opus-5-5", requested: "sonnet" });
    expect(resolveModel(DEFAULT_MODEL_ALLOWLIST, "codex", undefined).id).toBeUndefined();
  });

  it("[[models]] in runtimes.toml replaces the default list and is checked", () => {
    const c = parseRuntimesToml(`[[models]]\nid = "gpt-x"\nharness = "codex"\ndefault = true\nceilings = { seven_day = 80 }\n`, "t");
    expect(resolveModel(c.models!, "codex", undefined)).toEqual({ id: "gpt-x", ceilings: { seven_day: 80 } });
    expect(() => parseRuntimesToml(`[[models]]\nid = "a"\nharness = "claude"\nceilings = { five_hour = 150 }\n`, "t")).toThrow(/ceiling five_hour/);
  });

  it("the route carries the resolved model, the request and the ceilings", () => {
    const c = parseRuntimesToml(`default = "h"\n[runtime.h]\ntype = "host"\n`, "t");
    const b = new RunnerBackend(c, { jobsRoot: tmp(), runId: "r" });
    expect(b.route({ opts: { model: "fable" }, phase: undefined })).toMatchObject({ harness: "claude", model: "claude-fable-5-1", requestedModel: "fable", ceilings: { model_scoped: 90 } });
    expect(b.route({ opts: {}, phase: undefined }).model).toBe("claude-opus-5-5");
  });

  it("claude argv and subagent pin follow the resolved model", () => {
    const inv = claudeInvocation({ prompt: "p", model: "claude-fable-5-1" });
    expect(inv.argv.slice(0, 4)).toEqual(["claude", "-p", "--model", "claude-fable-5-1"]);
    expect(inv.env?.CLAUDE_CODE_SUBAGENT_MODEL).toBe("claude-fable-5-1");
  });
});

describe("the codex harness is real behind the same runner interface", () => {
  it("argv is codex exec --json, non-interactive, prompt on stdin, -m only when a model is named", () => {
    expect(codexInvocation({ prompt: "p" }).argv).toEqual(["codex", "exec", "--json", "--skip-git-repo-check", "--sandbox", "read-only", "-"]);
    expect(codexInvocation({ prompt: "p", model: "gpt-x" }).argv).toContain("-m");
  });

  it("parses the MEASURED codex-cli 0.155.1 event stream (thread id, agent message, usage)", () => {
    const out = [
      { type: "thread.started", thread_id: "019a-t" },
      { type: "turn.started" },
      { type: "item.completed", item: { id: "item_0", type: "agent_message", text: '{"answer":"ok"}' } },
      { type: "turn.completed", usage: { input_tokens: 10, cached_input_tokens: 0, cache_write_input_tokens: 0, output_tokens: 5, reasoning_output_tokens: 0 } },
    ].map((e) => JSON.stringify(e)).join("\n");
    expect(parseCodex(out, true)).toEqual({ object: { answer: "ok" }, usage: { inputTokens: 10, outputTokens: 5, cacheCreationTokens: 0, cacheReadTokens: 0, reasoningTokens: 0 }, agentId: "019a-t" });
  });

  it("with a declared codex seat and no test guard, the runner is reached with the codex argv", async () => {
    const saved = process.env[TEST_SEAT_ENV];
    delete process.env[TEST_SEAT_ENV];
    try {
      const seen: Job[] = [];
      const runner: Runner = {
        name: "cx",
        type: "host",
        refuses: () => undefined,
        run: async (job) => {
          seen.push(job);
          return { runtime: "cx", jobId: job.id, exitCode: 0, stdout: '{"type":"item.completed","item":{"type":"agent_message","text":"ok"}}\n', stderr: "", durationMs: 1 } as never;
        },
      } as Runner;
      const c = parseRuntimesToml(`default = "cx"\n[seats]\ncodex = "codex"\n[runtime.cx]\ntype = "host"\nharness = "codex"\n`, "t");
      const b = new RunnerBackend(c, { jobsRoot: tmp(), runId: "r", runners: { cx: runner } });
      const out = await b.run({ index: 1, key: "k", prompt: "p", opts: {}, phase: undefined, attempt: 1 } as never);
      expect(out.error).toBeUndefined();
      expect(seen).toHaveLength(1);
      expect((seen[0] as ProcessJob).argv.slice(0, 3)).toEqual(["codex", "exec", "--json"]);
    } finally {
      if (saved !== undefined) process.env[TEST_SEAT_ENV] = saved;
    }
  });
});
