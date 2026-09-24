/**
 * The interpreter (eval/2026-09-23-interpreter, merged read-only) driving
 * RunnerBackend: agent({runtime}) and [phases] defaults decide where each call
 * runs, results flow back into the script, refusals become null.
 */
import { describe, expect, it } from "vitest";
import { runWorkflow } from "../../interpreter/src/index.ts";
import { RunnerBackend } from "../src/backend.ts";
import { parseRuntimesToml } from "../src/config.ts";
import { workerdRunner } from "../src/workerd.ts";
import type { Job, ProcessJob, Runner, RunResult } from "../src/job.ts";
import { tmp } from "./helpers.ts";

const config = parseRuntimesToml(
  `
default = "hd"
[credentials]
scope = "dir"
[phases]
"Review" = "gv"
[runtime.hd]
type = "herdr"
[runtime.gv]
type = "gvisor"
runsc = "/nix/store/x/bin/runsc"
[runtime.edge]
type = "workerd"
workerd = "/bin/true"
`,
  "integration",
  "/home/u",
);

function fake(name: string, type: string, seen: { runtime: string; prompt: string }[]): Runner {
  return {
    name,
    type,
    refuses: () => undefined,
    run: async (j: Job): Promise<RunResult> => {
      const p = j as ProcessJob;
      seen.push({ runtime: name, prompt: p.stdin ?? "" });
      const schema = p.argv.includes("--json-schema");
      const envelope = {
        type: "result",
        subtype: "success",
        is_error: false,
        session_id: `${name}-${seen.length}`,
        usage: { input_tokens: 3, output_tokens: 2 },
        result: schema ? "" : `${name} says ${p.stdin?.split(" ")[0]}`,
        ...(schema ? { structured_output: { verdict: `ok-from-${name}` } } : {}),
      };
      return { runtime: name, jobId: j.id, exitCode: 0, stdout: JSON.stringify(envelope), stderr: "", durationMs: 1 };
    },
  };
}

const SCRIPT = `export const meta = { name: 'runtimes', description: 'runtime selection', phases: [{ title: 'Build' }, { title: 'Review' }] }
phase('Build')
const a = await agent('alpha task', { label: 'a' })
const b = await agent('beta task', { label: 'b', runtime: 'gv' })
phase('Review')
const r = await agent('review ' + a, { label: 'r', schema: { type: 'object', properties: { verdict: { type: 'string' } }, required: ['verdict'] } })
const w = await agent('edge task', { label: 'w', runtime: 'edge' })
return { a, b, r, w }
`;

describe("interpreter + RunnerBackend", () => {
  it("routes each agent() by runtime, phase default and file default; refusals become null", async () => {
    const seen: { runtime: string; prompt: string }[] = [];
    const backend = new RunnerBackend(config, {
      jobsRoot: tmp(),
      runId: "wf_it",
      runners: { hd: fake("hd", "herdr", seen), gv: fake("gv", "gvisor", seen), edge: workerdRunner("edge", { workerd: "/bin/true" }) },
    });
    const res = await runWorkflow(SCRIPT, { backend, concurrency: 2, maxAttempts: 1, runId: "wf_it" });
    expect(seen.map((s) => s.runtime)).toEqual(["hd", "gv", "gv"]);
    expect(seen[2]!.prompt).toBe("review hd says alpha");
    const out = (res as unknown as { result?: unknown; value?: unknown; returnValue?: unknown });
    const value = out.result ?? out.value ?? out.returnValue;
    expect(value).toEqual({ a: "hd says alpha", b: "gv says beta", r: { verdict: "ok-from-gv" }, w: null });
  });
});
