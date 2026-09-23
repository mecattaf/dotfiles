/**
 * Dry-run seat dispatch over work items derived from real run records.
 *
 *   tsx src/seats-cli.ts --records <dir> [--meters <dir>] [--cap 3] [--derive-age]
 *
 * Nothing is executed and nothing is written outside this repository. The
 * meters directory is read only, and the fourth seat is aimed at a path that
 * does not exist rather than at a real file that has been moved away.
 */
import { deployConfig } from "./deploy-config.ts";
import { readdirSync } from "node:fs";
import { join } from "node:path";
import { runSeatDryRun, type SeatDeclaration } from "./dispatch.ts";
import { deriveFromFile } from "./record.ts";
import { METERS_DIR, ccAdapter, codexAdapter, halogenAdapter } from "./seats.ts";
import type { WorkItem } from "./schema.ts";

function arg(name: string, fallback: string): string {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 && process.argv[i + 1] !== undefined ? process.argv[i + 1]! : fallback;
}
const flag = (name: string): boolean => process.argv.includes(`--${name}`);

const recordsDir = arg("records", "");
const metersDir = arg("meters", METERS_DIR);
const cap = Number(arg("cap", "3"));
const deriveAge = flag("derive-age");

if (recordsDir === "") {
  console.error("usage: seats-cli.ts --records <dir> [--meters <dir>] [--cap N] [--derive-age]");
  process.exit(2);
}

const items: WorkItem[] = [];
for (const f of readdirSync(recordsDir).filter((f) => f.startsWith("wf_") && f.endsWith(".json")).sort()) {
  items.push(...deriveFromFile(join(recordsDir, f)).items);
}
const dispatchable = items.filter((i) => i.promptResolved && i.sourceStatus !== "killed");

/**
 * Four seats, one cap. The first three are the real adapters. The fourth is a
 * cc-shaped seat aimed at cc9.json, which is absent: it exists to show the
 * refusal path without touching any real meter file.
 *
 * Every bound is data. Staleness 300s; cap 95 for cc on its weekly figure, 90
 * for codex on utilization_pct because its weekly field is not a number, and
 * none for halogen, which declares a slot row of capacity one and no budget row.
 */
const declarations: SeatDeclaration[] = [
  { adapter: ccAdapter(join(metersDir, "cc.json")), slots: 1,
    bounds: { stalenessBoundSeconds: 300, utilizationField: "weekly_utilization_pct", capPct: 95 } },
  { adapter: codexAdapter(deployConfig().codexWorkdir, join(metersDir, "codex.json")), slots: 1,
    bounds: { stalenessBoundSeconds: 300, utilizationField: "utilization_pct", capPct: 90 } },
  { adapter: halogenAdapter(join(metersDir, "gpu-worker.json")), slots: 1,
    bounds: { stalenessBoundSeconds: 300, utilizationField: "none", capPct: null } },
  { adapter: { ...ccAdapter(`${METERS_DIR}/cc9.json`), seatId: "cc9" }, slots: 1,
    bounds: { stalenessBoundSeconds: 300, utilizationField: "weekly_utilization_pct", capPct: 95 } },
];

console.log(`=== derived ${items.length} items, ${dispatchable.length} dispatchable ===`);
console.log(`=== meters ${metersDir}, cap ${cap}, deriveAgeFromObservedAt ${deriveAge} ===`);

const result = runSeatDryRun(dispatchable, declarations, {
  cap,
  mode: "dry-run",
  deriveAgeFromObservedAtMs: deriveAge ? Date.now() : undefined,
});

console.log("=== seat ledger ===");
process.stdout.write(result.ledger.serialize());
console.log("=== counts ===");
console.log(JSON.stringify({
  admitted: result.admitted,
  refused: result.refused,
  spawned: result.spawned,
  ledgerLines: result.ledger.entries.length,
}, null, 2));
