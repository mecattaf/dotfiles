/**
 * The deployment config layer. Everything that names one operator's machine
 * (home paths, seat names, the meters directory, forbidden prefixes) lives
 * here as data, never as a constant in code, so the repository stays a
 * template and a deployment differs from it only by one JSON file.
 *
 * Lookup order, first hit wins:
 *   1. `SUBSTRATE_CONFIG` names a JSON file (an unreadable or invalid file is
 *      an error, not a silent fallback);
 *   2. `$XDG_CONFIG_HOME/substrate/substrate.json` (default `~/.config/...`),
 *      used only when it exists;
 *   3. the neutral built-in defaults below.
 *
 * The committed example is `deploy/substrate.config.example.json`. A leading
 * `~/` in any path is expanded against the current home directory.
 */
import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

export interface DeployConfig {
  /** Paths the run-record reader must never open, nor bind into a sandbox. */
  readonly forbiddenReadPrefixes: readonly string[];
  /** Paths no ledger may be written under. `/run/user` is always included. */
  readonly forbiddenLedgerPrefixes: readonly string[];
  /** The local meter directory read by the legacy `--meters` capacity source (named explicitly, never a default source). */
  readonly metersDir: string;
  /** The floor whose GET /capacity the admission gate reads when no capacity flag is given; null for none. */
  readonly capacityFloorUrl: string | null;
  /** A file holding the floor's operator bearer for those reads; null sends none. */
  readonly capacityFloorTokenFile: string | null;
  /** Last-resort ax.proto location when the vendored copy is missing; null for none. */
  readonly axProtoFallbackPath: string | null;
  /** Seats that must never run with `--no-capacity`. */
  readonly realSeats: readonly string[];
  /** The working directory handed to `codex exec -C` by the seats dry-run CLI. */
  readonly codexWorkdir: string;
}

export const CONFIG_ENV = "SUBSTRATE_CONFIG";

const expand = (p: string, home: string): string => (p === "~" ? home : p.startsWith("~/") ? join(home, p.slice(2)) : p);

export function defaultDeployConfig(home: string = homedir()): DeployConfig {
  return {
    forbiddenReadPrefixes: [],
    forbiddenLedgerPrefixes: ["/run/user"],
    metersDir: join(home, ".local", "state", "substrate", "meters"),
    capacityFloorUrl: null,
    capacityFloorTokenFile: null,
    axProtoFallbackPath: null,
    realSeats: [],
    codexWorkdir: process.cwd(),
  };
}

const isStringArray = (v: unknown): v is string[] => Array.isArray(v) && v.every((x) => typeof x === "string");

/** Decodes one config object over the defaults. Unknown keys are refused so a typo cannot silently drop a guard. */
export function decodeDeployConfig(raw: unknown, home: string = homedir(), source = "config"): DeployConfig {
  if (raw === null || typeof raw !== "object" || Array.isArray(raw)) throw new Error(`${source}: expected a JSON object`);
  const o = raw as Record<string, unknown>;
  const d = defaultDeployConfig(home);
  const known = new Set(["$schema", "comment", ...Object.keys(d)]);
  for (const k of Object.keys(o)) if (!known.has(k)) throw new Error(`${source}: unknown key ${JSON.stringify(k)}`);
  const arr = (k: keyof DeployConfig, fallback: readonly string[]): readonly string[] => {
    const v = o[k];
    if (v === undefined) return fallback;
    if (!isStringArray(v)) throw new Error(`${source}: ${k} must be an array of strings`);
    return v.map((p) => expand(p, home));
  };
  const str = (k: keyof DeployConfig, fallback: string): string => {
    const v = o[k];
    if (v === undefined) return fallback;
    if (typeof v !== "string" || v.length === 0) throw new Error(`${source}: ${k} must be a non-empty string`);
    return expand(v, home);
  };
  const proto = o.axProtoFallbackPath;
  if (proto !== undefined && proto !== null && (typeof proto !== "string" || proto.length === 0)) {
    throw new Error(`${source}: axProtoFallbackPath must be a non-empty string or null`);
  }
  const nullable = (k: "capacityFloorUrl" | "capacityFloorTokenFile", expandPath: boolean): string | null => {
    const v = o[k];
    if (v === undefined || v === null) return null;
    if (typeof v !== "string" || v.length === 0) throw new Error(`${source}: ${k} must be a non-empty string or null`);
    return expandPath ? expand(v, home) : v;
  };
  const ledger = arr("forbiddenLedgerPrefixes", d.forbiddenLedgerPrefixes);
  return {
    forbiddenReadPrefixes: arr("forbiddenReadPrefixes", d.forbiddenReadPrefixes),
    forbiddenLedgerPrefixes: ledger.includes("/run/user") ? ledger : ["/run/user", ...ledger],
    metersDir: str("metersDir", d.metersDir),
    capacityFloorUrl: nullable("capacityFloorUrl", false),
    capacityFloorTokenFile: nullable("capacityFloorTokenFile", true),
    axProtoFallbackPath: typeof proto === "string" ? expand(proto, home) : null,
    realSeats: arr("realSeats", d.realSeats),
    codexWorkdir: str("codexWorkdir", d.codexWorkdir),
  };
}

/** Where the config is read from under this environment, or null for the defaults. */
export function deployConfigPath(env: Readonly<Record<string, string | undefined>> = process.env, home: string = homedir()): string | null {
  const explicit = env[CONFIG_ENV];
  if (explicit !== undefined && explicit !== "") return expand(explicit, home);
  const xdg = env.XDG_CONFIG_HOME !== undefined && env.XDG_CONFIG_HOME !== "" ? env.XDG_CONFIG_HOME : join(home, ".config");
  const p = join(xdg, "substrate", "substrate.json");
  return existsSync(p) ? p : null;
}

export function loadDeployConfig(env: Readonly<Record<string, string | undefined>> = process.env, home: string = homedir()): DeployConfig {
  const path = deployConfigPath(env, home);
  if (path === null) return defaultDeployConfig(home);
  let text: string;
  try {
    text = readFileSync(path, "utf8");
  } catch (e) {
    throw new Error(`cannot read the substrate config ${path}: ${(e as NodeJS.ErrnoException).code ?? String(e)}`);
  }
  let raw: unknown;
  try {
    raw = JSON.parse(text);
  } catch {
    throw new Error(`the substrate config ${path} is not valid JSON`);
  }
  return decodeDeployConfig(raw, home, path);
}

let cached: DeployConfig | undefined;
/** The process-wide config, read once. */
export function deployConfig(): DeployConfig {
  cached ??= loadDeployConfig();
  return cached;
}
