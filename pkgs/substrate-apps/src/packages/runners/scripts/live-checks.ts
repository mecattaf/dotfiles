/**
 * Live checks: one `claude --version` job per runtime that can run here, plus
 * the Worker job for workerd, the refusals that are the designed answer
 * elsewhere, and optional small real calls.
 *
 *   tsx scripts/live-checks.ts --out DIR --only host,herdr,gvisor,microvm,workerd,ax   (under runtime-test)
 *   tsx scripts/live-checks.ts --out DIR --only ssh,pi                                  (outside: ssh needs the agent socket)
 *   add --infer to also run one tiny `claude -p` through RunnerBackend on each named runtime
 *
 * herdr runs against an ISOLATED server this script starts in a scratch HOME
 * and kills by pid; the live herdr is never addressed. Every result is one JSON
 * line in <out>/live-<name>.json.
 */
import { spawn, spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { hostRunner } from "../src/host.ts";
import { herdrRunner } from "../src/herdr.ts";
import { gvisorRunner } from "../src/gvisor.ts";
import { microvmRunner } from "../src/microvm.ts";
import { sshRunner } from "../src/ssh.ts";
import { workerdRunner } from "../src/workerd.ts";
import { axRunner } from "../src/ax.ts";
import { RunnerBackend, credentialMount } from "../src/backend.ts";
import { decodeRuntimes } from "../src/config.ts";
import type { Job, ProcessJob, Runner } from "../src/job.ts";

const arg = (k: string) => {
  const i = process.argv.indexOf(`--${k}`);
  return i > 0 ? process.argv[i + 1] : undefined;
};
const out = arg("out") ?? join(process.cwd(), "live-out");
const only = new Set((arg("only") ?? "host").split(","));
const infer = process.argv.includes("--infer");
mkdirSync(out, { recursive: true });
const RUNSC = process.env.AXC_RUNSC ?? "/nix/store/da343m78crf7s2d2b3yrb7hjpsb44gq4-gvisor-20260406.0/bin/runsc";
const WORKERD = process.env.AXC_WORKERD ?? "/nix/store/4ffm95hsqvrsvwxyjvc64wwbnsi7rp1k-workerd-1.20260722.1/bin/workerd";

const config = decodeRuntimes({ credentials: { claude: "~/.claude", mode: "rw" } }, "live-checks");
const stamp = new Date().toISOString();
const inWrapper = (() => {
  try {
    return !/^0\s+0\s+4294967295$/.test(readFileSync("/proc/self/uid_map", "utf8").trim());
  } catch {
    return false;
  }
})();

async function record(name: string, runner: Runner, job: Job) {
  const t0 = Date.now();
  const res = await runner.run(job);
  const line = { name, at: stamp, runtimeType: runner.type, wallMs: Date.now() - t0, job: job.kind === "process" ? { argv: job.argv, mounts: job.mounts ?? [] } : { kind: "worker" }, result: res };
  writeFileSync(join(out, `live-${name}.json`), JSON.stringify(line, null, 1));
  const r = res as unknown as Record<string, unknown>;
  console.log(`${name}: ${"refused" in r ? `REFUSED ${String(r.refused).slice(0, 160)}` : `rc=${r.exitCode} stdout=${JSON.stringify(String(r.stdout).trim().slice(0, 120))} ${r.durationMs}ms`}`);
  return res;
}

const versionJob = (id: string, runtimeType: string): ProcessJob => {
  const rt = { type: runtimeType } as never;
  const m = credentialMount(config, rt, "claude");
  return {
    kind: "process",
    id,
    argv: ["claude", "--version"],
    jobDir: join(out, "jobs", id),
    agent: true,
    ...(m ? { mounts: [m], env: { CLAUDE_CONFIG_DIR: m.target } } : {}),
    timeoutMs: 120000,
  };
};

async function isolatedHerdr(): Promise<{ socket: string; stop: () => void }> {
  const home = join(out, "herdr-home");
  const cfg = join(home, ".config");
  mkdirSync(join(cfg, "herdr"), { recursive: true });
  writeFileSync(join(cfg, "herdr/config.toml"), "onboarding = false\n");
  const env: NodeJS.ProcessEnv = { ...process.env, HOME: home, XDG_CONFIG_HOME: cfg, XDG_STATE_HOME: join(home, ".local/state"), XDG_DATA_HOME: join(home, ".local/share") };
  for (const k of Object.keys(env)) if (k.startsWith("HERDR_")) delete env[k];
  const socket = join(cfg, "herdr/herdr.sock");
  if (!socket.startsWith(out)) throw new Error("isolation guard: socket not under the scratch dir");
  const srv = spawn("herdr", ["server"], { env, stdio: ["ignore", "ignore", "ignore"] });
  for (let i = 0; i < 100 && !existsSync(socket); i++) await new Promise((r) => setTimeout(r, 100));
  const st = spawnSync("herdr", ["status"], { env, encoding: "utf8" });
  if (!st.stdout.includes(`socket: ${socket}`)) {
    srv.kill("SIGTERM");
    throw new Error(`isolation guard: herdr status does not name ${socket}: ${st.stdout}${st.stderr}`);
  }
  return { socket, stop: () => srv.kill("SIGTERM") };
}

async function tinyInference(name: string, runner: Runner) {
  const cfg = { ...config, default: name, runtimes: { [name]: { type: runner.type } as never } };
  const b2 = new RunnerBackend(cfg, { jobsRoot: join(out, "jobs"), runId: `live-infer-${name}`, runners: { [name]: runner } });
  const t0 = Date.now();
  const res = await b2.run({ index: 1, key: "live", prompt: "Reply with exactly the word pong and nothing else.", opts: {}, phase: undefined, attempt: 1 });
  writeFileSync(join(out, `live-infer-${name}.json`), JSON.stringify({ name, at: stamp, wallMs: Date.now() - t0, outcome: res }, null, 1));
  console.log(`infer ${name}: ${JSON.stringify(res).slice(0, 200)}`);
}

console.log(`live checks at ${stamp}, wrapper=${inWrapper}, out=${out}`);

if (only.has("host")) {
  const h = hostRunner("host");
  await record("host", h, versionJob("live-host", "host"));
  if (infer) await tinyInference("host", h);
}
if (only.has("herdr")) {
  const iso = await isolatedHerdr();
  try {
    const a = herdrRunner("herdr", { socket: iso.socket, autoLink: true, pluginDir: join(out, "herdr-plugin") });
    await record("herdr-action", a, versionJob("live-herdr-action", "herdr"));
    const p = herdrRunner("herdr-pane", { socket: iso.socket, mode: "pane" });
    await record("herdr-pane", p, versionJob("live-herdr-pane", "herdr"));
  } finally {
    iso.stop();
  }
}
if (only.has("gvisor")) {
  const g = gvisorRunner("gvisor", { runsc: RUNSC, state: join(homedir(), ".local/state/substrate/runsc") });
  await record("gvisor", g, versionJob("live-gvisor", "gvisor"));
  if (infer) await tinyInference("gvisor", g);
}
if (only.has("microvm")) {
  await record("microvm", microvmRunner("microvm", { state: join(homedir(), ".local/state/substrate/microvm") }), versionJob("live-microvm", "microvm"));
}
if (only.has("workerd")) {
  const w = workerdRunner("workerd", { workerd: WORKERD });
  await record("workerd-agent-refused", w, versionJob("live-workerd-agent", "workerd"));
  await record("workerd-worker-job", w, {
    kind: "worker",
    id: "live-workerd-job",
    module: `export default { async test(ctrl, env) {
      const d = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(env.INPUT));
      console.log(JSON.stringify({ sha256: [...new Uint8Array(d)].map(b => b.toString(16).padStart(2, "0")).join("") }));
    } };`,
    bindings: { INPUT: "hello tom" },
    jobDir: join(out, "jobs", "live-workerd-job"),
  });
}
if (only.has("ax")) {
  await record("ax", axRunner("ax"), versionJob("live-ax", "ax"));
}
if (only.has("ssh")) {
  await record("ssh-worker", sshRunner("ssh:worker", { host: "worker" }), { ...versionJob("live-ssh", "ssh") });
}
if (only.has("pi")) {
  const s = sshRunner("ssh:worker", { host: "worker" });
  const cfg = decodeRuntimes({ default: "ssh:worker", runtime: { "ssh:worker": { type: "ssh", host: "worker", harness: "pi" } } }, "live-pi");
  const b = new RunnerBackend(cfg, { jobsRoot: join(out, "jobs"), runId: "live-pi", runners: { "ssh:worker": s } });
  const t0 = Date.now();
  const res = await b.run({ index: 1, key: "live-pi", prompt: "Reply with exactly the word pong and nothing else.", opts: {}, phase: undefined, attempt: 1 });
  writeFileSync(join(out, "live-pi-worker.json"), JSON.stringify({ name: "pi-on-worker", at: stamp, wallMs: Date.now() - t0, outcome: res }, null, 1));
  console.log(`pi on worker: ${JSON.stringify(res).slice(0, 200)} (${Date.now() - t0} ms)`);
}
