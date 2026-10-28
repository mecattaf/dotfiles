/** Composition for the Nix fleet's DSH 0.2.1-rc.2 launcher, not the retired pi CLI.
 * The fleet wrapper owns provider endpoints, sandbox and credentials. This patch selects the exact
 * Gufo catalog model and writes plain JSONL to an isolated home that outlives session turns.
 */
import type { HarnessSession } from "./harness.ts";
import { join } from "node:path";

export function dshPatch(home: string, model: string, effort?: string, session?: HarnessSession): string {
  const rows: Record<string, unknown>[] = [
    { id: "agent-default-model", config: { provider: "gufo", model, ...(effort === undefined || effort === "off" ? {} : { reasoningEffort: effort }) } },
    { id: "session-persistence-jsonl", config: { root: join(home, "sessions"), compression: "none" } },
    { id: "session-title-llm", disabled: true },
  ];
  if (session !== undefined) {
    rows.push({ insert: [{ id: "substrate-project", name: new URL("./dsh-project.mjs", import.meta.url).href, config: {
      serverName: "project", transport: "stdio", command: session.mcp.command, args: ["mcp"], env: session.mcp.env,
      failOnStartupError: true, ...(session.tools === undefined ? {} : { tools: session.tools }),
    } }] }, { id: "headless-runner", inject: ["headlessStartup", "substrateProjectReady"] });
    if (session.tools !== undefined) {
      // A coordinator owns read + role-gated project MCP only. It cannot execute shell, write files,
      // launch child agents/workflows, discover skills or load cwd instructions outside its own brief.
      rows.push({ id: "tool-fs", config: { read: true, readImage: false, write: false, edit: false } },
        { id: "sandbox-policy", config: { mode: "read-only" } });
      for (const id of ["tool-bash", "tool-pwsh", "tool-jobs", "tool-fs-search", "agent-instructions", "skill-filesystem", "tool-skill",
        "tool-workflow", "tool-subagent", "tool-subagent-control", "tool-goal", "tool-schedule", "tool-web", "tool-todo", "tool-session-query",
        "tool-working-directory", "tool-workspace-dependencies", "tool-ask-user", "tool-present", "goal-round-driver", "tool-ralph"]) rows.push({ id, disabled: true });
    }
  }
  return JSON.stringify(rows, null, 1) + "\n";
}
