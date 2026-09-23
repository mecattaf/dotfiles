/**
 * The live end-to-end entry point: the whole CONWIP loop, once, with the
 * outcome coming from a real dispatch instead of from a run record's history.
 *
 *   AX_CONWIP_LIVE_HALOGEN=1 tsx src/e2e-live.ts \
 *     --records <dir> --only <file> [--addr host:port] [--cap N] \
 *     [--wrapper-timeout-seconds S] [--child-timeout-ms MS] \
 *     [--staleness-bound-seconds S]
 *
 * This is a NEW entry point rather than a flag on `src/cli.ts`, on purpose.
 * `src/cli.ts` remains unable to dispatch anything: it does not import
 * `src/live.ts`, passes no `outcomeOf`, and so a typo on the ordinary command
 * line cannot become a live dispatch. There is one way in and it is this file,
 * and this file refuses to run unless AX_CONWIP_LIVE_HALOGEN=1.
 *
 * Live dispatch is permitted on the `halogen` seat only. See DESIGN.md.
 */
import { readdirSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { AxClient } from "./axclient.ts";
import { SEAT_LEDGER_KEYS, SPAWN_LEDGER_KEYS } from "./dispatch.ts";
import { JsonlSink, defaultLedgerPath } from "./jsonl.ts";
import { LEDGER_KEYS } from "./ledger.ts";
import {
  LIVE_ENV_VAR,
  SUGGESTED_CHILD_TIMEOUT_MS,
  SUGGESTED_STALENESS_BOUND_SECONDS,
  SUGGESTED_WRAPPER_TIMEOUT_SECONDS,
  assertLiveEnabled,
  makeHalogenOutcomeOf,
} from "./live.ts";
import { runLoop } from "./loop.ts";
import { deriveFromFile } from "./record.ts";
import { halogenAdapter, renderArgv } from "./seats.ts";
import type { WorkItem } from "./schema.ts";

// Gate first, before argv is even read. Nothing below runs without it.
try {
  assertLiveEnabled(process.env);
} catch (e) {
  console.error((e as Error).message);
  process.exit(3);
}

function arg(name: string, fallback: string): string {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 && process.argv[i + 1] !== undefined ? process.argv[i + 1]! : fallback;
}

const recordsDir = arg("records", "");
const only = arg("only", "");
const addr = arg("addr", "127.0.0.1:8099");
const cap = Number(arg("cap", "1"));

/**
 * Both timeouts and the staleness bound are DATA AT THIS CALL SITE. They are
 * printed before the run, so a receipt quotes what actually ran rather than
 * what a constant in some module happened to say. A real WorkItem prompt is
 * thousands of characters, so these are generously longer than item 26's
 * forty seconds, and a timeout is a legitimate recorded outcome.
 */
const wrapperTimeoutSeconds = Number(
  arg("wrapper-timeout-seconds", String(SUGGESTED_WRAPPER_TIMEOUT_SECONDS)),
);
const childTimeoutMs = Number(arg("child-timeout-ms", String(SUGGESTED_CHILD_TIMEOUT_MS)));
const stalenessBoundSeconds = Number(
  arg("staleness-bound-seconds", String(SUGGESTED_STALENESS_BOUND_SECONDS)),
);

if (recordsDir === "" || only === "") {
  console.error(
    "usage: e2e-live.ts --records <dir> --only <file> [--addr host:port] [--cap N]" +
      " [--wrapper-timeout-seconds S] [--child-timeout-ms MS] [--staleness-bound-seconds S]",
  );
  process.exit(2);
}

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const onlyList = only.split(",").map((s) => s.trim());

const selected: WorkItem[] = [];
for (const f of readdirSync(recordsDir).filter((x) => x.startsWith("wf_") && x.endsWith(".json")).sort()) {
  if (!onlyList.includes(f)) continue;
  const d = deriveFromFile(join(recordsDir, f));
  selected.push(...d.items);
  console.log(
    `RECORD ${f} runId=${d.summary.runId} status=${d.summary.status} items=${d.items.length}` +
      ` resolved=${d.items.filter((i) => i.promptResolved).length}`,
  );
}
for (const i of selected) {
  console.log(
    `ITEM idx=${i.index} phase=${i.phaseIndex} label=${JSON.stringify(i.label)}` +
      ` resolved=${i.promptResolved} promptChars=${i.prompt.length} sourceStatus=${i.sourceStatus}`,
  );
}

const adapter = halogenAdapter(undefined, wrapperTimeoutSeconds);
console.log(`BOUND wrapperTimeoutSeconds=${wrapperTimeoutSeconds}`);
console.log(`BOUND childTimeoutMs=${childTimeoutMs}`);
console.log(`BOUND stalenessBoundSeconds=${stalenessBoundSeconds}`);
console.log(`SEAT seatId=${adapter.seatId} meterPath=${adapter.meterPath}`);
for (const i of selected.filter((x) => x.promptResolved)) {
  const d = adapter.render(i);
  console.log(`ARGV idx=${i.index}: ${renderArgv(d)}`);
  console.log(
    `STDIN idx=${i.index}: ${d.stdin.length} chars, first line: ${JSON.stringify(d.stdin.split("\n")[0]!.slice(0, 120))}`,
  );
}

const loopPath = defaultLedgerPath(REPO_ROOT, "e2e-live-loop");
const seatPath = defaultLedgerPath(REPO_ROOT, "e2e-live-seat");
const spawnPath = defaultLedgerPath(REPO_ROOT, "e2e-live-spawn");
console.log(`LEDGER loop:  ${loopPath}`);
console.log(`LEDGER seat:  ${seatPath}`);
console.log(`LEDGER spawn: ${spawnPath}`);

const outcomeOf = makeHalogenOutcomeOf({
  adapter,
  stalenessBoundSeconds,
  spawnTimeoutMs: childTimeoutMs,
  nowMs: () => Date.now(),
  print: (l) => console.log(l),
  seatSink: new JsonlSink(seatPath, [...SEAT_LEDGER_KEYS]),
  spawnSink: new JsonlSink(spawnPath, [...SPAWN_LEDGER_KEYS]),
});

console.log(`=== loop, cap ${cap}, ${selected.length} items, addr ${addr} ===`);
const client = AxClient.connect(addr);
let result;
try {
  result = await runLoop(selected, client, {
    cap,
    maxReadingAgeMs: 60_000,
    watchTimeoutMs: 5_000,
    now: () => new Date().toISOString(),
    image: "substrate/placeholder:v1",
    outcomeOf,
    ledgerSink: new JsonlSink(loopPath, [...LEDGER_KEYS]),
  });
} catch (e) {
  client.close();
  // No retry. A failed or refused dispatch is the measured outcome, and the
  // jsonl sinks have already flushed everything that did happen.
  console.error(`LIVE RUN FAILED: ${(e as Error).message}`);
  process.exit(1);
}
client.close();

console.log("=== loop ledger ===");
process.stdout.write(result.ledger.serialize());
console.log("=== counts ===");
console.log(
  JSON.stringify(
    {
      derived: result.derived,
      admitted: result.admitted,
      released: result.released,
      refused: result.refused,
      unresolved: result.unresolved,
      ledgerLines: result.ledger.entries.length,
    },
    null,
    2,
  ),
);
