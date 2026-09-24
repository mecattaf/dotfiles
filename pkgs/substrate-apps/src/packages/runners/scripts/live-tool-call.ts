/**
 * One tiny agent() call through RunnerBackend on gVisor that must use a tool:
 * proves the credential mount, IS_SANDBOX, the store PATH and /bin/sh together.
 *   tsx scripts/live-tool-call.ts --out DIR   (under runtime-test)
 */
import { writeFileSync, mkdirSync } from "node:fs";
import { join } from "node:path";
import { RunnerBackend } from "../src/backend.ts";
import { decodeRuntimes } from "../src/config.ts";

const i = process.argv.indexOf("--out");
const out = i > 0 ? process.argv[i + 1]! : join(process.cwd(), "live-out");
mkdirSync(out, { recursive: true });
const RUNSC = process.env.AXC_RUNSC ?? "/nix/store/da343m78crf7s2d2b3yrb7hjpsb44gq4-gvisor-20260406.0/bin/runsc";
const config = decodeRuntimes({ default: "gvisor", runtime: { gvisor: { type: "gvisor", runsc: RUNSC } } }, "live-tool-call");
const b = new RunnerBackend(config, { jobsRoot: join(out, "jobs"), runId: "live-tool" });
const schema = { type: "object", properties: { uname: { type: "string" }, home: { type: "string" } }, required: ["uname", "home"] };
const t0 = Date.now();
const res = await b.run({
  index: 1,
  key: "live-tool",
  prompt: "Use the Bash tool to run exactly: uname -r; echo $HOME. Report the two output lines as uname and home.",
  opts: { schema },
  phase: undefined,
  attempt: 1,
});
writeFileSync(join(out, "live-tool-call-gvisor.json"), JSON.stringify({ at: new Date().toISOString(), wallMs: Date.now() - t0, outcome: res }, null, 1));
console.log(JSON.stringify(res), `${Date.now() - t0} ms`);
