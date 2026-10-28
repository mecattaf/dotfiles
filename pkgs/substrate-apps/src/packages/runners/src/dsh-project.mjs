// Loaded by DSH's own resolver, which supplies its installed MCP bridge. No second
// harness or MCP dependency is installed into Substrate. A missing project server
// leaves the required headless runner waiting and makes startup fail closed.
import { registerMaintenanceTools } from "./dsh-maintenance.mjs";
import { createRequire } from "node:module";
import { pathToFileURL } from "node:url";
import { realpathSync } from "node:fs";

export const name = "substrate-project";
export const inject = ["tools"];
export async function apply(ctx, config) {
  const { tools, maintenance, ...server } = config;
  const fromDsh = createRequire(realpathSync(process.argv[1]));
  const bridge = await import(pathToFileURL(fromDsh.resolve("@deepseek-ai/dsh-mcp-client")).href);
  await bridge.apply(ctx, { toolCallTimeoutMs: 60_000, cwd: process.cwd(), ...server, failOnStartupError: true });
  if (maintenance !== undefined) {
    if (tools !== undefined) throw new Error("coordinators cannot receive maintenance commands");
    const { defineTool } = await import(pathToFileURL(fromDsh.resolve("@deepseek-ai/dsh-tools")).href);
    registerMaintenanceTools(ctx, defineTool, maintenance);
  }
  const known = ctx.tools.schemas().map(t => t.name);
  if (!known.some(n => n.startsWith("mcp__project__"))) throw new Error("project MCP published no tools");
  if (tools !== undefined) {
    const allowed = new Set(tools);
    ctx.tools.guard(exec => allowed.has(exec.name) ? undefined : "Substrate coordinator may use read and its project MCP only");
    ctx.on("agent/created", ({ agent }) => {
      agent.ctx.tools.restrict({ allow: known.filter(n => allowed.has(n)) });
    });
  }
  ctx.provide("substrateProjectReady", true);
}
