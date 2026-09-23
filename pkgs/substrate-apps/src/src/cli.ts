/**
 * End-to-end entry point: derive WorkItems from run records, admit them under a
 * fixed cap against a live ax server, and print the ledger on stdout.
 *
 *   tsx src/cli.ts --records <dir> --addr 127.0.0.1:8080 --cap 2 [--only a,b]
 */
import { readdirSync } from "node:fs";
import { join } from "node:path";
import { AxClient } from "./axclient.ts";
import { deriveFromFile } from "./record.ts";
import { deriveOnly } from "./derive-only.ts";
import { runLoop } from "./loop.ts";
import type { WorkItem } from "./schema.ts";

function arg(name: string, fallback: string): string {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 && process.argv[i + 1] !== undefined ? process.argv[i + 1]! : fallback;
}

const recordsDir = arg("records", "");
const addr = arg("addr", "127.0.0.1:8080");
const cap = Number(arg("cap", "2"));
const only = arg("only", "");
const onlyList = only === "" ? null : only.split(",").map((s) => s.trim());

if (recordsDir === "") {
  console.error("usage: cli.ts --records <dir> [--addr host:port] [--cap N] [--only file,file] [--derive-only]");
  process.exit(2);
}
// CR-08: audit the derivation without any ax server.
if (process.argv.includes("--derive-only")) {
  deriveOnly(recordsDir, (l) => console.log(l));
  process.exit(0);
}

const files = readdirSync(recordsDir)
  .filter((f) => f.startsWith("wf_") && f.endsWith(".json"))
  .sort();

const allItems: WorkItem[] = [];
const selected: WorkItem[] = [];
const diagnostics: string[] = [];

console.log("=== derivation, all six records ===");
for (const f of files) {
  const d = deriveFromFile(join(recordsDir, f));
  allItems.push(...d.items);
  diagnostics.push(...d.diagnostics);
  const unresolved = d.items.filter((i) => !i.promptResolved).length;
  console.log(
    `${f}  runId=${d.summary.runId}  workflow=${d.summary.workflowName}  status=${d.summary.status}` +
      `  result=${d.summary.resultKind}  error=${d.summary.hasError}` +
      `  phases=${d.summary.phaseCount}  agentCount=${d.summary.agentCount}` +
      `  items=${d.items.length}  unresolved=${unresolved}`,
  );
  if (onlyList === null || onlyList.includes(f)) selected.push(...d.items);
}
console.log(`TOTAL derived across all six records: ${allItems.length} items` +
  `, unresolved ${allItems.filter((i) => !i.promptResolved).length}`);
for (const d of diagnostics) console.log(`DIAG ${d}`);

console.log(`=== loop, cap ${cap}, ${selected.length} items, addr ${addr} ===`);
const client = AxClient.connect(addr);
const result = await runLoop(selected, client, {
  cap,
  maxReadingAgeMs: 60_000,
  watchTimeoutMs: 5_000,
  now: () => new Date().toISOString(),
  image: "substrate/placeholder:v1",
});
client.close();

console.log("=== ledger ===");
process.stdout.write(result.ledger.serialize());
console.log("=== counts ===");
console.log(
  JSON.stringify(
    {
      derivedAllSixRecords: allItems.length,
      derivedInThisRun: result.derived,
      admitted: result.admitted,
      released: result.released,
      refused: result.refused,
      unresolvedInThisRun: result.unresolved,
      unresolvedAllSixRecords: allItems.filter((i) => !i.promptResolved).length,
      ledgerLines: result.ledger.entries.length,
    },
    null,
    2,
  ),
);
