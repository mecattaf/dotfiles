/**
 * Durable ledger output: append-only JSON Lines on disk.
 *
 * Until item 26 a run's ledger existed only in memory and on the console, so a
 * run left no record a later reader could open. This module writes one line per
 * ledger event, using the SAME bytes the in-memory serializer already produces.
 *
 * The item 11 ledger's format is a contract with a pinned sha256. Nothing here
 * edits it: `serializeRecords` is reused unchanged, and a log that needs extra
 * columns (the seat log of item 12, the spawn log of item 26) declares its own
 * key list and becomes a SECOND representation rather than a widened first one.
 */
import { deployConfig } from "./deploy-config.ts";
import { appendFileSync, mkdirSync } from "node:fs";
import { dirname, isAbsolute, join, resolve } from "node:path";
import { serializeRecords } from "./ledger.ts";
import { resolveThroughLinks } from "./pathguard.ts";

/**
 * Where a run's ledgers go when the caller names nothing: inside this
 * repository's own working directory, never a system location. `out/` is
 * already ignored by .gitignore, so run output never becomes source.
 */
export const DEFAULT_LEDGER_DIR = "out/ledger";

/**
 * Paths no ledger may ever be written under, whatever a caller passes.
 *
 * `/run/user` is the live session's runtime tree: a September 2026 incident
 * destroyed the live systemd and D-Bus sockets there, and nothing this
 * scheduler writes belongs anywhere near it. The tally-rewrite meters are read
 * only by construction; the seat rule reads those rows and never writes one.
 */
export const FORBIDDEN_LEDGER_PREFIXES: readonly string[] = deployConfig().forbiddenLedgerPrefixes;

export function assertLedgerPathAllowed(path: string): void {
  const abs = resolveThroughLinks(path);
  for (const bad of FORBIDDEN_LEDGER_PREFIXES) {
    if (abs === bad || abs.startsWith(`${bad}/`)) {
      throw new Error(`refusing to write a ledger under ${bad}: ${path} resolves to ${abs}`);
    }
  }
}

/**
 * The default path for one named log, relative to a repository root the caller
 * supplies. Nothing here reads `process.cwd()` implicitly at import time.
 */
export function defaultLedgerPath(repoRoot: string, name: string): string {
  const root = isAbsolute(repoRoot) ? repoRoot : resolve(repoRoot);
  return join(root, DEFAULT_LEDGER_DIR, `${name}.jsonl`);
}

/**
 * An append-only jsonl sink. One `append` is one line, flushed immediately, so
 * a run that is killed still leaves everything it had already recorded.
 *
 * Creating the parent directory is allowed. Truncating or deleting an existing
 * file is not: the file is only ever opened in append mode, and this class
 * exposes no method that shortens it.
 */
export class JsonlSink<E extends object> {
  #lines = 0;

  constructor(
    readonly path: string,
    private readonly keys: readonly string[],
  ) {
    // The check comes FIRST, before any directory is created: `mkdirSync` with
    // `recursive` on a path that passes through a link would otherwise have
    // created the directories under the link's target before anything refused.
    assertLedgerPathAllowed(path);
    mkdirSync(dirname(resolve(path)), { recursive: true });
  }

  /** Append one entry as one line, in the pinned key order, LF terminated. */
  append(entry: E): void {
    appendFileSync(this.path, serializeRecords(this.keys, [entry]), { encoding: "utf8", flag: "a" });
    this.#lines += 1;
  }

  /** How many lines this sink has written. Not how many the file holds. */
  get lines(): number {
    return this.#lines;
  }
}
