/**
 * substrate-runners: the CLI user's end of the runtimes file.
 *
 *   substrate-runners check [--config F]                  decode the file, list runtimes and whether each can take a job here
 *   substrate-runners select [--config F] [--runtime R] [--phase P]
 *                                                         which runtime an agent() call would get, and why
 *   substrate-runners run <runtime> [--config F] [--job-dir D] [--timeout-ms N] -- argv...
 *                                                         run one process job (stdin passes through) and print the outcome JSON
 *   substrate-runners herdr-link [--socket S]             link the runner plugin into a herdr server (explicit: it changes that server's plugins)
 *   substrate-runners example                             print a commented runtimes.toml
 */
import { mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { loadRuntimes, lookupRuntime, selectRuntime } from "./config.ts";
import { runnerFor } from "./registry.ts";
import { defaultSocket, linkPlugin } from "./herdr.ts";
import { isRefusal } from "./job.ts";

interface Out {
  code: number;
  out: string;
}

function flags(args: string[]): { f: Record<string, string>; rest: string[]; pos: string[] } {
  const f: Record<string, string> = {};
  const pos: string[] = [];
  for (let i = 0; i < args.length; i++) {
    const a = args[i]!;
    if (a === "--") return { f, rest: args.slice(i + 1), pos };
    if (a.startsWith("--")) f[a.slice(2)] = args[++i] ?? "";
    else pos.push(a);
  }
  return { f, rest: [], pos };
}

const readStdin = (): string => {
  if (process.stdin.isTTY) return "";
  try {
    return readFileSync(0, "utf8");
  } catch {
    return "";
  }
};

export async function main(argv: string[]): Promise<Out> {
  const [cmd, ...args] = argv;
  const { f, rest, pos } = flags(args);
  try {
    switch (cmd) {
      case "example":
        return { code: 0, out: readFileSync(join(dirname(fileURLToPath(import.meta.url)), "../runtimes.example.toml"), "utf8").trimEnd() };
      case "check": {
        const c = loadRuntimes(f.config);
        const names = ["host", ...Object.keys(c.runtimes).filter((n) => n !== "host")];
        const probe = { kind: "process" as const, id: "check", argv: ["claude", "--version"], jobDir: join(tmpdir(), "axc-check") };
        const lines = names.map((n) => {
          const r = lookupRuntime(c, n)!;
          const why = runnerFor(n, r).refuses(probe);
          return `${n.padEnd(14)} ${r.type.padEnd(8)} ${why ? `refuses: ${why}` : "ready"}`;
        });
        return {
          code: 0,
          out: [`config: ${c.source}`, `default: ${c.default}`, `phases: ${JSON.stringify(c.phases)}`, `credentials: ${c.credentials.claude} (${c.credentials.mode}, mounted)`, ...lines].join("\n"),
        };
      }
      case "select": {
        const c = loadRuntimes(f.config);
        const s = selectRuntime(c, { ...(f.runtime !== undefined ? { runtime: f.runtime } : {}), ...(f.phase !== undefined ? { phase: f.phase } : {}) });
        return { code: 0, out: JSON.stringify(s) };
      }
      case "run": {
        const name = pos[0];
        if (!name || rest.length === 0) return { code: 2, out: "usage: substrate-runners run <runtime> [--config F] [--job-dir D] -- argv..." };
        const c = loadRuntimes(f.config);
        const r = lookupRuntime(c, name);
        if (!r) return { code: 2, out: `no runtime ${name} in ${c.source}` };
        const jobDir = f["job-dir"] ?? mkdtempSync(join(tmpdir(), "axc-run-"));
        const res = await runnerFor(name, r).run({
          kind: "process",
          id: `cli-${process.pid}`,
          argv: rest,
          stdin: readStdin(),
          jobDir,
          ...(f["timeout-ms"] ? { timeoutMs: Number(f["timeout-ms"]) } : {}),
        });
        return { code: isRefusal(res) ? 3 : res.exitCode === 0 ? 0 : 1, out: JSON.stringify(res, null, 1) };
      }
      case "herdr-link": {
        const socket = f.socket ?? defaultSocket();
        const dir = await linkPlugin(socket);
        return { code: 0, out: `linked substrate-runner from ${dir} into ${socket}` };
      }
      default:
        return { code: 2, out: "usage: substrate-runners check|select|run|herdr-link|example (see src/cli.ts)" };
    }
  } catch (e) {
    return { code: 2, out: (e as Error).message };
  }
}
