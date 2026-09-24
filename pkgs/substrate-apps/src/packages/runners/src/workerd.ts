/**
 * `workerd`: Worker-shaped jobs only, run one-shot with `workerd test`.
 *
 * An agent() call is refused here, always: an isolate has no process, no shell,
 * no filesystem beyond its bindings and no harness CLI (lane W3, MEASURED). What
 * fits is a deterministic Worker step: an ES module exporting
 * `default { async test(ctrl, env) }`, text bindings as input, stdout and the
 * exit code (0 pass, 1 fail) as output.
 *
 * The workerd binary comes from workerd.nix (`runtime.workerd.workerd`, or a
 * `nix build` of `runtime.workerd.flake` on first use). Egress is closed unless
 * the runtime names an allow list, the same fail-closed stance as workerd.nix's
 * bounded egress; entries are network classes or CIDRs, never hostnames.
 */
import { existsSync, mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { refuseCommon, refusal, type Job, type Runner, type RunResult, type WorkerJob } from "./job.ts";
import { runProc } from "./proc.ts";

export const DEFAULT_WORKERD_FLAKE = "github:mecattaf/workerd.nix#workerd";
export const AGENT_REFUSAL =
  "workerd runs Worker-shaped jobs only; an agent() call needs a process, a shell and a harness CLI, which an isolate does not have";

export interface WorkerdOptions {
  /** Absolute path of the workerd binary. */
  readonly workerd?: string;
  /** Flake installable to build workerd from when `workerd` is absent. */
  readonly flake?: string;
  readonly compatibilityDate?: string;
  /** Egress allow list (network classes such as "private", or CIDRs). Default: none. */
  readonly allow?: readonly string[];
  readonly timeoutMs?: number;
  readonly nix?: string;
}

const BINDING = /^[A-Za-z_][A-Za-z0-9_]*$/;
const capStr = (s: string) => JSON.stringify(s);

/** The capnp config for one job. Module and bindings are `embed`ded files, so no escaping reaches capnp. */
export function workerdConfig(job: WorkerJob, o: WorkerdOptions = {}): { capnp: string; files: Record<string, string> } {
  const files: Record<string, string> = { "job.js": job.module };
  const bindings = Object.entries(job.bindings ?? {}).map(([k, v]) => {
    files[`binding-${k}.txt`] = v;
    return `(name = ${capStr(k)}, text = embed ${capStr(`binding-${k}.txt`)})`;
  });
  const allow = o.allow ?? [];
  const capnp = `using Workerd = import "/workerd/workerd.capnp";
const config :Workerd.Config = (
  services = [
    (name = "main", worker = (
      modules = [ (name = "job.js", esModule = embed "job.js") ],
      compatibilityDate = ${capStr(o.compatibilityDate ?? "2026-02-02")},
      bindings = [ ${bindings.join(", ")} ],
      globalOutbound = "egress",
    )),
    (name = "egress", network = (allow = [ ${allow.map(capStr).join(", ")} ])),
  ],
);
`;
  return { capnp, files };
}

export function workerdRunner(name: string, o: WorkerdOptions = {}): Runner {
  let binary = o.workerd;
  const refuses = (job: Job): string | undefined => {
    if (job.kind !== "worker") return AGENT_REFUSAL;
    const c = refuseCommon(job);
    if (c) return c;
    if (!/export\s+default/.test(job.module)) return "worker job module has no default export";
    for (const k of Object.keys(job.bindings ?? {})) if (!BINDING.test(k)) return `binding name ${JSON.stringify(k)} is not an identifier`;
    if (o.workerd && !existsSync(o.workerd)) return `workerd not found at ${o.workerd}`;
    return undefined;
  };
  const ensureBinary = async (): Promise<string | { error: string }> => {
    if (binary) return binary;
    const flake = o.flake ?? DEFAULT_WORKERD_FLAKE;
    const r = await runProc({ argv: [o.nix ?? "nix", "build", "--no-link", "--print-out-paths", flake], timeoutMs: 20 * 60 * 1000 });
    const out = r.stdout.trim().split("\n").pop() ?? "";
    if (r.exitCode !== 0 || !out.startsWith("/nix/store/")) return { error: `nix build ${flake} failed (rc ${r.exitCode}): ${r.stderr.slice(-600)}` };
    binary = join(out, "bin/workerd");
    return binary;
  };
  return {
    name,
    type: "workerd",
    refuses,
    async run(job, signal): Promise<RunResult> {
      const why = refuses(job);
      if (why || job.kind !== "worker") return refusal(name, job, why ?? AGENT_REFUSAL);
      const bin = await ensureBinary();
      if (typeof bin !== "string") return refusal(name, job, bin.error);
      mkdirSync(job.jobDir, { recursive: true });
      const { capnp, files } = workerdConfig(job, o);
      for (const [f, text] of Object.entries(files)) writeFileSync(join(job.jobDir, f), text);
      writeFileSync(join(job.jobDir, "job.capnp"), capnp);
      const r = await runProc({
        argv: [bin, "test", "job.capnp"],
        cwd: job.jobDir,
        timeoutMs: job.timeoutMs ?? o.timeoutMs ?? 5 * 60 * 1000,
        signal,
      });
      return { runtime: name, jobId: job.id, ...r, detail: { workerd: bin, config: join(job.jobDir, "job.capnp") } };
    },
  };
}
