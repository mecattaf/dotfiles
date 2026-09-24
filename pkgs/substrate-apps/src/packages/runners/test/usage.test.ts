// PT-04 (2026-09-24): the harness envelopes' cache and reasoning token counts are carried, not dropped.
import { describe, expect, it } from "vitest";
import { claudeUsage, codexUsage, parseClaude, parseCodex } from "../src/harness.ts";

describe("usage from the harness envelopes", () => {
  it("claude: input and output, plus cache creation, cache read and thinking when reported", () => {
    const env = { type: "result", subtype: "success", is_error: false, result: "hi", session_id: "s1",
      usage: { input_tokens: 10, cache_creation_input_tokens: 5, cache_read_input_tokens: 20, output_tokens: 7, output_tokens_details: { thinking_tokens: 2 } } };
    expect(parseClaude(JSON.stringify(env), false)).toEqual({ text: "hi", agentId: "s1",
      usage: { inputTokens: 10, outputTokens: 7, cacheCreationTokens: 5, cacheReadTokens: 20, reasoningTokens: 2 } });
  });
  it("claude: an envelope without cache fields keeps the two-field shape", () => {
    expect(claudeUsage({ input_tokens: 3, output_tokens: 4 })).toEqual({ inputTokens: 3, outputTokens: 4 });
    expect(claudeUsage({ input_tokens: -1, output_tokens: "x", cache_read_input_tokens: null })).toEqual({ inputTokens: 0, outputTokens: 0 });
  });
  it("codex: cached input and reasoning output from turn.completed", () => {
    const out = [
      JSON.stringify({ type: "thread.started", thread_id: "t1" }),
      JSON.stringify({ type: "item.completed", item: { type: "agent_message", text: "ok" } }),
      JSON.stringify({ type: "turn.completed", usage: { input_tokens: 100, cached_input_tokens: 80, output_tokens: 9, reasoning_output_tokens: 6 } }),
    ].join("\n");
    expect(parseCodex(out, false)).toEqual({ text: "ok", agentId: "t1", usage: { inputTokens: 100, outputTokens: 9, cacheReadTokens: 80, reasoningTokens: 6 } });
    expect(codexUsage({ input_tokens: 1, output_tokens: 2 })).toEqual({ inputTokens: 1, outputTokens: 2 });
  });
});
