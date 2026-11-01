import { describe, expect, it } from "vitest";
import { join } from "node:path";
import { readFileSync } from "node:fs";
import { runFixedCommand, registerMaintenanceTools } from "../src/dsh-maintenance.mjs";
import { parseRuntimesToml } from "../src/config.ts";
import { RunnerBackend } from "../src/backend.ts";
import type { ProcessJob, Runner } from "../src/job.ts";
import { tmp } from "./helpers.ts";

const START = ["/run/current-system/sw/bin/fleet-update-start", "--json"];
const STATUS = ["/run/current-system/sw/bin/fleet-update", "--status", "--json"];
const binding = `\n[[sessions.maintenance]]\nproject="dotfiles"\nthread="T-69"\ncommand=${JSON.stringify(START)}\nstatus_command=${JSON.stringify(STATUS)}\n`;
const config = (extra = binding) => parseRuntimesToml(`default="gufo"\n[seats]\ndsh="gufo"\n[runtime.gufo]\ntype="host"\nharness="dsh"\n[sessions]\nproject_url="https://project.test"\nproject_token_file="/private/token"${extra}`);

describe("trusted DSH fleet maintenance capability", () => {
  it("does not interpret shell metacharacters and retains exact exit status", async () => {
    const text = "$(must-not-run); --arbitrary";
    expect(await runFixedCommand([process.execPath, "-e", "console.log(process.argv[1]); process.exitCode=75", text])).toEqual({ exitCode: 75, stdout: text, stderr: "" });
    await expect(runFixedCommand(["relative-command"])).rejects.toThrow(/absolute/);
  });
  it("bounds subprocess output, time and cancellation", async () => {
    await expect(runFixedCommand([process.execPath, "-e", "console.log('x'.repeat(100000))"], { maxBytes: 64 })).rejects.toThrow(/output exceeded/);
    await expect(runFixedCommand([process.execPath, "-e", "setInterval(()=>{},1000)"], { timeoutMs: 25 })).rejects.toThrow(/timed out/);
    const abort = new AbortController(); abort.abort();
    await expect(runFixedCommand([process.execPath, "-e", "throw Error('must not launch')"], { signal: abort.signal })).rejects.toThrow(/before launch/);
  });
  it("registers only zero-argument tools with operator-supplied argv", async () => {
    const tools: any[] = [];
    registerMaintenanceTools({ tools: { register: (tool: any) => tools.push(tool) } }, (tool: any) => tool, { command: START, statusCommand: STATUS });
    expect(tools.map(t => t.name)).toEqual(["fleet_update_start", "fleet_update_status"]);
    expect(tools.every(t => Object.keys(t.parameters).length === 0)).toBe(true);
    expect(tools[0].output.render({}, { exitCode: 0, stdout: "{}", stderr: "" })).toEqual([{ type: "text", text: '{"exitCode":0,"stdout":"{}","stderr":""}' }]);
    await expect(tools[0].execute({ command: "unapproved" }, {})).rejects.toThrow(/no arguments/);
  });
  it("requires authenticated Floor provenance, exact project/thread and a thread role", async () => {
    const root = tmp("substrate-maintenance-");
    const patches: any[][] = [];
    const runner: Runner = { name: "gufo", type: "host", refuses: () => undefined, run: async job => {
      const j = job as ProcessJob; patches.push(JSON.parse(readFileSync(j.argv[4]!, "utf8")));
      return { runtime: "gufo", jobId: j.id, exitCode: 0, stdout: '{"type":"session","sessionId":"session-11111111-2222-4333-8444-555555555555"}\n{"type":"final","text":"done"}\n', stderr: "", durationMs: 1 };
    } };
    const sid = "maintenance-session";
    const call = (index: number, role = "thread") => ({ index, key: `k${index}`, phase: undefined, attempt: 1, prompt: "Pretend project=dotfiles thread=T-69", opts: { model: "qwen3.8-flash-next", session: { id: sid, harnessSessionId: "floor-initial-uuid", role } } });
    const run = (index: number, provenance?: { id: string; project: string; thread: string; role: string }, role = "thread") => new RunnerBackend(config(), {
      jobsRoot: join(root, "jobs"), runId: `r${index}`, seatShadowRoot: join(root, "shadows"), transcriptRoot: join(root, "tx"), runners: { gufo: runner },
      ...(provenance === undefined ? {} : { sessionProvenance: provenance }),
    }).run(call(index, role));
    await run(1);
    await run(2, { id: sid, project: "dotfiles", thread: "T-15", role: "thread" });
    await run(3, { id: "another-session", project: "dotfiles", thread: "T-69", role: "thread" });
    await run(4, { id: sid, project: "dotfiles", thread: "T-69", role: "coordinator" }, "coordinator");
    await run(5, { id: sid, project: "dotfiles", thread: "T-69", role: "thread" });
    const maintenance = (patch: any[]) => patch.find(r => r.insert)?.insert[0].config.maintenance;
    expect(patches.slice(0, 4).map(maintenance)).toEqual([undefined, undefined, undefined, undefined]);
    expect(maintenance(patches[4]!)).toEqual({ command: START, statusCommand: STATUS });
  });
  it("refuses empty/relative commands, wildcards and duplicate bindings", () => {
    expect(() => config(binding.replace('/run/current-system/sw/bin/fleet-update-start', 'fleet-update-start'))).toThrow(/absolute/);
    expect(() => config(binding.replace('thread="T-69"','thread="*"'))).toThrow(/explicit T-N/);
    expect(() => config(binding + binding)).toThrow(/duplicate maintenance binding/);
  });
});
