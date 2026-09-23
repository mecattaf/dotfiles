/**
 * CR-08 of the 2026-09-23 evals: derivation, audited offline.
 *
 * `serve` and `cli` both dialled ax before deriving anything, so the one
 * function every entry point calls (`derive`) could not be audited through an
 * entry point without a server. `deriveOnly` reads a records directory, derives
 * every file, and prints one JSON line per record, per item and per
 * diagnostic, then a totals line. It opens no socket, spawns nothing, and
 * writes nothing but the lines it prints.
 */
import { readdirSync } from "node:fs";
import { join } from "node:path";
import { deriveFromFile } from "./record.ts";
import { fixtureOutcome } from "./schema.ts";

export interface DeriveOnlyTotals {
  readonly files: number;
  readonly failedFiles: number;
  readonly items: number;
  readonly resolved: number;
  readonly unresolved: number;
  readonly diagnostics: number;
}

export function deriveOnly(
  recordsDir: string,
  print: (line: string) => void,
  opts: { readonly derive?: typeof deriveFromFile; readonly list?: () => readonly string[] } = {},
): DeriveOnlyTotals {
  const derive = opts.derive ?? deriveFromFile;
  const names = [...(opts.list ? opts.list() : readdirSync(recordsDir))]
    .filter((f) => f.startsWith("wf_") && f.endsWith(".json"))
    .sort();
  let failedFiles = 0, items = 0, resolved = 0, diagnostics = 0;
  for (const f of names) {
    let d: ReturnType<typeof deriveFromFile>;
    try {
      d = derive(join(recordsDir, f));
    } catch (e) {
      failedFiles++;
      print(JSON.stringify({ kind: "record-error", file: f, error: (e as Error).message }));
      continue;
    }
    print(JSON.stringify({ kind: "record", file: f, ...d.summary, items: d.items.length }));
    for (const i of d.items) {
      items++;
      if (i.promptResolved) resolved++;
      print(JSON.stringify({
        kind: "item", runId: i.runId, index: i.index, label: i.label, phaseIndex: i.phaseIndex,
        model: i.model, resolved: i.promptResolved, promptChars: i.prompt.length,
        reason: i.promptUnresolvedReason ?? null, fixtureOutcome: fixtureOutcome(i),
      }));
    }
    for (const g of d.diagnostics) {
      diagnostics++;
      print(JSON.stringify({ kind: "diagnostic", file: f, text: g }));
    }
  }
  const totals: DeriveOnlyTotals = {
    files: names.length, failedFiles, items, resolved, unresolved: items - resolved, diagnostics,
  };
  print(JSON.stringify({ kind: "totals", ...totals }));
  return totals;
}
