/**
 * conwip-run: run one workflow script through the integrated path
 * (interpreter -> CONWIP admission -> runner -> harness), journaling into a
 * run directory. Running the same command on the same directory resumes.
 *
 *   conwip-run <script.js> --dir <run dir> --seat <seat> --runtimes <runtimes.toml>
 *              (--meters <dir> | --capacity-snapshot <file> | --capacity-floor <url> | --no-capacity)
 *              [--model <id>] [--cap N] [--concurrency N] [--max-attempts N]
 *              [--capacity-wait-ms N] [--budget N] [--args <json>]
 *
 * With no capacity flag the gate reads the floor the substrate config names
 * (capacityFloorUrl, bearer from capacityFloorTokenFile); none configured is an
 * error (G4: tally meter files are never a default). --capacity-floor reads
 * that floor's GET /capacity and /capacity/admit at another URL
 * (src/capacity/floor.ts). --capacity-snapshot reads a seat-capacity/2 file,
 * for offline runs. --meters reads the legacy feeder files through
 * src/capacity/tally-meters.ts, only when named. --no-capacity is for a fake
 * seat under test only. Exit codes (src/run-outcome.ts, gap G3): 0 every
 * call done or cached, 1 the script failed, 2 bad arguments or another live
 * process holds the run dir, 3 partial (some calls done, some failed, none
 * refused), 4 every call failed or any call was refused; 130/143 on
 * SIGINT/SIGTERM. Prints result.json on stdout and one summary line on stderr.
 * --budget is the run's token ceiling, kept in run.json for a
 * resume. --no-capacity needs AX_CONWIP_TEST_SEAT=1 and refuses the real
 * seats (the `realSeats` list of the substrate config). SIGINT or SIGTERM aborts the run,
 * waits up to SIGNAL_GRACE_MS for in-flight calls to clean up, then kills the
 * harness process groups this process started (their children also carry a
 * parent-death signal); a second signal kills at once.
 */
import { deployConfig } from "./deploy-config.ts";
import { readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";
import { killLiveGroups, loadRuntimes } from "@substrate/runners";
import { CapacityGate } from "./capacity/gate.ts";
import { capacitySourceFrom, configuredFloorSource, defaultCapacitySource } from "./capacity/config.ts";
import { runIntegrated } from "./integrated.ts";
import { summaryLine } from "./run-outcome.ts";
import { MachineSlots } from "./slots.ts";

const USAGE =
  "usage: conwip-run <script.js> --dir <dir> --seat <seat> --runtimes <file> [--capacity-floor <url> | --capacity-snapshot <file> | --meters <dir> | --no-capacity] [--model <id>] [--cap N] [--concurrency N] [--max-attempts N] [--capacity-wait-ms N] [--budget N] [--args <json>]";

/** Seats that spend a real login or the one Halogen slot: never run ungated. */
export const REAL_SEATS: ReadonlySet<string> = new Set(deployConfig().realSeats);

/** How long a SIGINT/SIGTERM waits for in-flight calls to clean up before the groups are killed. */
export const SIGNAL_GRACE_MS = 15_000;

export async function main(argv: readonly string[], signal?: AbortSignal): Promise<number> {
  const flags = new Map<string, string>();
  const bare = new Set<string>();
  let script: string | undefined;
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i]!;
    if (a === "--no-capacity") bare.add(a);
    else if (a.startsWith("--")) {
      const v = argv[++i];
      if (v === undefined) throw new Error(`${a} needs a value`);
      flags.set(a, v);
    } else if (script === undefined) script = a;
    else throw new Error(`unexpected argument ${a}`);
  }
  const need = (k: string) => {
    const v = flags.get(k);
    if (v === undefined) throw new Error(`${k} is required`);
    return v;
  };
  if (script === undefined) throw new Error("a script path is required");
  const seat = need("--seat");
  const sources = [flags.has("--meters"), flags.has("--capacity-snapshot"), flags.has("--capacity-floor"), bare.has("--no-capacity")].filter(Boolean).length;
  if (sources > 1) throw new Error("at most one of --capacity-floor, --capacity-snapshot, --meters, --no-capacity");
  // --no-capacity is for a fake seat under test, and now enforced (successor
  // review r4: it dispatched on --seat cc with no gate at all).
  if (bare.has("--no-capacity")) {
    if (process.env["AX_CONWIP_TEST_SEAT"] !== "1") throw new Error("--no-capacity needs AX_CONWIP_TEST_SEAT=1 in the environment (fake seats under test only)");
    if (REAL_SEATS.has(seat)) throw new Error(`--no-capacity refused on the real seat ${seat}; use --meters, --capacity-snapshot or --capacity-floor`);
  }
  const source = flags.has("--meters")
    ? capacitySourceFrom({ kind: "meters", dir: flags.get("--meters")! })
    : flags.has("--capacity-snapshot")
      ? capacitySourceFrom({ kind: "snapshot", path: flags.get("--capacity-snapshot")! })
      : flags.has("--capacity-floor")
        ? configuredFloorSource(flags.get("--capacity-floor")!)
        : bare.has("--no-capacity")
          ? undefined
          : defaultCapacitySource();
  const int = (k: string, d: number) => {
    const v = flags.get(k);
    if (v === undefined) return d;
    const n = Number(v);
    if (!Number.isInteger(n) || n < 0) throw new Error(`${k} must be a non-negative integer`);
    return n;
  };
  const run = await runIntegrated({
    scriptPath: script,
    dir: need("--dir"),
    runtimes: loadRuntimes(need("--runtimes")),
    seat,
    defaultModel: flags.get("--model") ?? "claude-opus-5-5",
    cap: int("--cap", 2),
    concurrency: int("--concurrency", 4),
    maxAttempts: int("--max-attempts", 2),
    ...(source ? { capacity: new CapacityGate(source, seat) } : {}),
    capacityWait: { delayMs: 15_000, maxWaitMs: int("--capacity-wait-ms", 0) },
    ...(flags.has("--budget") ? { budgetTotal: int("--budget", 0) } : {}),
    ...(flags.has("--args") ? { args: JSON.parse(flags.get("--args")!) } : {}),
    ...(signal ? { signal } : {}),
    // Slot seats (Halogen) hold a machine-wide slot per call. AX_CONWIP_SLOT_DIR moves the holds (tests).
    machineSlots: new MachineSlots(process.env["AX_CONWIP_SLOT_DIR"] || undefined),
  });
  process.stdout.write(readFileSync(`${run.dir}/result.json`, "utf8"));
  process.stderr.write(summaryLine(run.runId, { outcome: run.outcome, code: run.exitCode, counts: run.callCounts }) + "\n");
  return run.exitCode;
}

/**
 * Signals that abort the run and run every runner's cleanup. SIGHUP (ssh drop,
 * terminal close) and SIGQUIT were missing: their default action killed node
 * and skipped the worktree, seat-shadow, gVisor and herdr cleanup (successor
 * review r5).
 */
export const HANDLED_SIGNALS = [
  ["SIGINT", 130],
  ["SIGTERM", 143],
  ["SIGHUP", 129],
  ["SIGQUIT", 131],
] as const;

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  // A signal aborts the run and awaits its in-flight calls (bounded), so the
  // runners' finally blocks run: worktree settle, seat-shadow removal, herdr
  // workspace.close (successor review r4: process.exit() skipped all three).
  // Whatever is still alive after the grace is killed by group.
  const ac = new AbortController();
  let done: Promise<unknown> = Promise.resolve();
  let signalled = false;
  for (const [sig, code] of HANDLED_SIGNALS) {
    process.on(sig, () => {
      if (signalled) {
        killLiveGroups("SIGKILL");
        process.exit(code);
      }
      signalled = true;
      ac.abort();
      const grace = new Promise((r) => setTimeout(r, SIGNAL_GRACE_MS).unref());
      void Promise.race([done.catch(() => undefined), grace]).then(() => {
        const n = killLiveGroups("SIGKILL");
        process.stderr.write(`conwip-run: ${sig}: aborted in-flight calls, killed ${n} harness group(s); run the same command to resume\n`);
        process.exit(code);
      });
    });
  }
  const running = main(process.argv.slice(2), ac.signal);
  done = running;
  running.then(
    (code) => {
      process.exitCode = code;
    },
    (e: unknown) => {
      process.stderr.write(`conwip-run: ${(e as Error).message}\n${USAGE}\n`);
      process.exitCode = 2;
    },
  );
}
