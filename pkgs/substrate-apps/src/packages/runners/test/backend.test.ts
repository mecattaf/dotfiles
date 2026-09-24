import { describe, expect, it } from "vitest";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { RunnerBackend, credentialMount } from "../src/backend.ts";
import { parseRuntimesToml } from "../src/config.ts";
import { CLAUDE_MODEL, HALOGEN_MODEL } from "../src/harness.ts";
import type { Job, ProcessJob, Runner, RunResult } from "../src/job.ts";
import { workerdRunner } from "../src/workerd.ts";
import { tmp } from "./helpers.ts";

const HOME = "/home/u";
const config = parseRuntimesToml(
  `
default = "gv"
# Successor review r4: a phase may leave the sandboxed default only for a runtime the allow list names.
allow = ["gv", "vm", "hd", "ssh:worker", "edge", "k8s"]
[credentials]
scope = "dir"
[phases]
Scout = "ssh:worker"
[runtime.gv]
type = "gvisor"
runsc = "/nix/store/x/bin/runsc"
[runtime.vm]
type = "microvm"
[runtime.hd]
type = "herdr"
[runtime."ssh:worker"]
type = "ssh"
host = "worker"
harness = "pi"
[runtime.edge]
type = "workerd"
workerd = "/bin/true"
[runtime.k8s]
type = "ax"
`,
  "t",
  HOME,
);

/** A recording runner that answers with a canned outcome. */
function recorder(name: string, type: string, answer: (j: ProcessJob) => Partial<RunResult> = () => ({})) {
  const jobs: ProcessJob[] = [];
  const r: Runner = {
    name,
    type,
    refuses: () => undefined,
    run: async (j: Job) => {
      jobs.push(j as ProcessJob);
      return { runtime: name, jobId: j.id, exitCode: 0, stdout: "", stderr: "", durationMs: 1, ...answer(j as ProcessJob) } as RunResult;
    },
  };
  return { r, jobs };
}

const envelope = (o: Record<string, unknown>) =>
  JSON.stringify({ type: "result", subtype: "success", is_error: false, session_id: "s-1", usage: { input_tokens: 10, output_tokens: 5 }, ...o });

const call = (over: Record<string, unknown> = {}) => ({ index: 1, key: "k1", prompt: "P", opts: {}, phase: undefined, attempt: 1, ...over });

describe("RunnerBackend", () => {
  it("selects by opts.runtime, then phase, then default, and leaves a receipt", async () => {
    const gv = recorder("gv", "gvisor", () => ({ stdout: envelope({ result: "from-gv" }) }));
    const vm = recorder("vm", "microvm", () => ({ stdout: envelope({ result: "from-vm" }) }));
    const sw = recorder("ssh:worker", "ssh", () => ({ stdout: "from-pi\n" }));
    const jobsRoot = tmp();
    const b = new RunnerBackend(config, { jobsRoot, runId: "wf_1", runners: { gv: gv.r, vm: vm.r, "ssh:worker": sw.r } });
    expect(await b.run(call({ opts: { runtime: "vm" }, phase: "Scout" }))).toMatchObject({ text: "from-vm", agentId: "s-1" });
    expect(await b.run(call({ index: 2, phase: "Scout" }))).toEqual({ text: "from-pi" });
    expect(await b.run(call({ index: 3, phase: "Other" }))).toMatchObject({ text: "from-gv", usage: { inputTokens: 10, outputTokens: 5 } });
    const receipt = JSON.parse(readFileSync(join(jobsRoot, "wf_1-2-a1", "receipt.json"), "utf8"));
    expect(receipt).toMatchObject({ runtime: "ssh:worker", type: "ssh", via: "phase", exitCode: 0, harness: "pi" });
  });

  it("claude runs the allowlisted full id (fable -> claude-fable-5-1), prompt on stdin, schema via --json-schema", async () => {
    const gv = recorder("gv", "gvisor", () => ({ stdout: envelope({ result: "", structured_output: { ok: true } }) }));
    const b = new RunnerBackend(config, { jobsRoot: tmp(), runId: "r", runners: { gv: gv.r } });
    const schema = { type: "object", properties: { ok: { type: "boolean" } } };
    expect(await b.run(call({ prompt: "secret prompt", opts: { schema, model: "fable" } }))).toMatchObject({ object: { ok: true } });
    const j = gv.jobs[0]!;
    expect(j.argv.slice(0, 4)).toEqual(["claude", "-p", "--model", "claude-fable-5-1"]);
    expect(CLAUDE_MODEL).toBe("claude-opus-5-5");
    expect(j.argv).toContain("--json-schema");
    expect(j.argv.join(" ")).not.toContain("secret prompt");
    expect(j.stdin).toBe("secret prompt");
    expect(j.agent).toBe(true);
  });

  it("pi on ssh:worker targets Halogen and mounts nothing", async () => {
    const sw = recorder("ssh:worker", "ssh", () => ({ stdout: '```json\n{"n":1}\n```' }));
    const b = new RunnerBackend(config, { jobsRoot: tmp(), runId: "r", runners: { "ssh:worker": sw.r } });
    expect(await b.run(call({ phase: "Scout", opts: { schema: { type: "object" } } }))).toEqual({ object: { n: 1 } });
    expect(sw.jobs[0]!.argv).toEqual(expect.arrayContaining(["pi", "-p", "--no-session", "--model", HALOGEN_MODEL]));
    expect(sw.jobs[0]!.mounts).toBeUndefined();
  });

  it("mounts the seat credential where each runtime's harness looks, rw, and names it in CLAUDE_CONFIG_DIR", async () => {
    const rt = (n: string) => config.runtimes[n]!;
    expect(credentialMount(config, { type: "host" }, "claude")).toEqual({ source: "/home/u/.claude", target: "/home/u/.claude", mode: "rw", purpose: "credential" });
    expect(credentialMount(config, rt("hd"), "claude")?.target).toBe("/home/u/.claude");
    expect(credentialMount(config, rt("gv"), "claude")?.target).toBe("/home/agent/.claude");
    expect(credentialMount(config, rt("vm"), "claude")?.target).toBe("/root/.claude");
    expect(credentialMount(config, rt("ssh:worker"), "claude")).toBeUndefined();
    expect(credentialMount(config, rt("gv"), "pi")).toBeUndefined();
    const gv = recorder("gv", "gvisor", () => ({ stdout: envelope({ result: "x" }) }));
    await new RunnerBackend(config, { jobsRoot: tmp(), runId: "r", runners: { gv: gv.r } }).run(call());
    expect(gv.jobs[0]!.env).toEqual({ CLAUDE_CONFIG_DIR: "/home/agent/.claude", CLAUDE_CODE_SUBAGENT_MODEL: "claude-opus-5-5", CLAUDE_CODE_SUBAGENT_MODEL_FORCE: "1" });
    expect(gv.jobs[0]!.mounts).toEqual([{ source: "/home/u/.claude", target: "/home/agent/.claude", mode: "rw", purpose: "credential" }]);
  });

  it("refusals, non-zero exits, unknown runtimes and bad envelopes are errors, never values", async () => {
    const bad = recorder("gv", "gvisor", () => ({ exitCode: 2, stderr: "boom" }));
    const b = new RunnerBackend(config, { jobsRoot: tmp(), runId: "r", runners: { gv: bad.r, edge: workerdRunner("edge", { workerd: "/bin/true" }) } });
    expect((await b.run(call())).error).toMatch(/runtime gv: claude exited 2: boom/);
    expect((await b.run(call({ index: 2, opts: { runtime: "edge" } }))).error).toMatch(/refused: workerd runs Worker-shaped jobs only/);
    expect((await b.run(call({ index: 3, opts: { runtime: "nope" } }))).error).toMatch(/names no runtime/);
    const junk = recorder("gv", "gvisor", () => ({ stdout: "not json" }));
    const b2 = new RunnerBackend(config, { jobsRoot: tmp(), runId: "r", runners: { gv: junk.r } });
    expect((await b2.run(call())).error).toMatch(/not a JSON envelope/);
    const isErr = recorder("gv", "gvisor", () => ({ stdout: envelope({ subtype: "error_max_turns", is_error: true }) }));
    const b3 = new RunnerBackend(config, { jobsRoot: tmp(), runId: "r", runners: { gv: isErr.r } });
    expect((await b3.run(call())).error).toMatch(/error_max_turns/);
  });

  it("the ax seam writes the Task it would send and dispatches nothing", async () => {
    const jobsRoot = tmp();
    const out = await new RunnerBackend(config, { jobsRoot, runId: "wf_9", workflow: "w", defaultSeat: "cc" }).run(call({ opts: { runtime: "k8s", label: "L" } }));
    expect(out.error).toMatch(/refused: ax seam is spec-only/);
    const task = JSON.parse(readFileSync(join(jobsRoot, "wf_9-1-a1", "ax-task.json"), "utf8"));
    expect(task.name).toMatch(/^wf-9-1-[0-9a-f]{8}$/);
    expect(existsSync(join(jobsRoot, "wf_9-1-a1", "receipt.json"))).toBe(true);
  });
});
