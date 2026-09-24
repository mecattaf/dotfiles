/**
 * Capacity source from configuration: the one place a CLI turns flags and
 * environment into a `CapacitySource`, so `conwip-run` and `serve` cannot
 * disagree about what a flag means.
 *
 *  - `floor`: the ported floor over HTTP (`floor.ts`).
 *  - `snapshot`: a `seat-capacity/2` file (`source.ts`).
 *  - `meters`: the legacy local meter files (`tally-meters.ts`, transitional).
 *    Never a default (G4): the directory must be named, by `dir` or by
 *    `AX_CONWIP_METERS`, or the source refuses to exist.
 *
 * With no flag at all, `defaultCapacitySource` reads the floor the deploy
 * config names (`capacityFloorUrl`, bearer from `capacityFloorTokenFile`); with
 * none configured it throws, and the CLI refuses to start.
 *
 * Every one of them fails closed: a source that cannot answer is a REFUSE at
 * the gate, never an admission.
 */
import { readFileSync } from "node:fs";
import { deployConfig, type DeployConfig } from "../deploy-config.ts";
import { METERS_DIR_ENV } from "../seats.ts";
import { floorCapacitySource, FLOOR_SEAT_IDS, type FloorSourceOptions } from "./floor.ts";
import { snapshotFileSource, type CapacitySource } from "./source.ts";
import { tallyMeterSource } from "./tally-meters.ts";

export type CapacitySourceConfig =
  | { readonly kind: "floor"; readonly url: string; readonly options?: FloorSourceOptions }
  | { readonly kind: "snapshot"; readonly path: string; readonly seatIds?: Readonly<Record<string, string>> }
  | {
      readonly kind: "meters";
      readonly dir?: string;
      readonly env?: Readonly<Record<string, string | undefined>>;
      readonly readFile?: (p: string) => string;
    };

/** The legacy meter source; its directory is `dir`, else `AX_CONWIP_METERS`. There is no default directory. */
export function localMeterSource(config: { readonly dir?: string; readonly env?: Readonly<Record<string, string | undefined>>; readonly readFile?: (p: string) => string } = {}): CapacitySource {
  const fromEnv = (config.env ?? process.env)[METERS_DIR_ENV];
  const dir = config.dir !== undefined && config.dir.length > 0 ? config.dir : fromEnv !== undefined && fromEnv.length > 0 ? fromEnv : undefined;
  if (dir === undefined) {
    throw new Error(`no meters directory named (--meters or ${METERS_DIR_ENV}); the gate reads the floor (--capacity-floor) or a snapshot (--capacity-snapshot)`);
  }
  return tallyMeterSource(dir, config.readFile === undefined ? {} : { readFile: config.readFile });
}

/** Reads a bearer file; the value is returned, never logged. */
export function floorTokenFrom(path: string | null, readFile: (p: string) => string = (p) => readFileSync(p, "utf8")): string | undefined {
  if (path === null) return undefined;
  try {
    return readFile(path).trim();
  } catch (e) {
    throw new Error(`cannot read the floor token file ${path}: ${(e as NodeJS.ErrnoException).code ?? "error"}`);
  }
}

/**
 * The source used when no capacity flag is given: the configured floor. No
 * floor configured is an error, never a fallback to local meter files (G4).
 */
export function defaultCapacitySource(config: Pick<DeployConfig, "capacityFloorUrl" | "capacityFloorTokenFile"> = deployConfig(), readFile?: (p: string) => string): CapacitySource {
  if (config.capacityFloorUrl === null) {
    throw new Error("no capacity source: pass --capacity-floor <url> or --capacity-snapshot <file>, or set capacityFloorUrl in the substrate config");
  }
  return configuredFloorSource(config.capacityFloorUrl, config, readFile);
}

/** The floor at `url`, with the configured bearer when one is configured. */
export function configuredFloorSource(url: string, config: Pick<DeployConfig, "capacityFloorTokenFile"> = deployConfig(), readFile?: (p: string) => string): CapacitySource {
  const token = floorTokenFrom(config.capacityFloorTokenFile, readFile);
  return capacitySourceFrom({ kind: "floor", url, options: token === undefined ? {} : { token } });
}

export function capacitySourceFrom(config: CapacitySourceConfig): CapacitySource {
  switch (config.kind) {
    case "floor": {
      const url = config.url;
      if (!/^https?:\/\/[^/]/.test(url)) throw new Error(`capacity floor url must be http(s)://host[:port], got ${JSON.stringify(url)}`);
      return floorCapacitySource(url, { seatIds: FLOOR_SEAT_IDS, ...(config.options ?? {}) });
    }
    case "snapshot":
      return snapshotFileSource(config.path, config.seatIds === undefined ? {} : { seatIds: config.seatIds });
    case "meters":
      return localMeterSource(config);
  }
}
