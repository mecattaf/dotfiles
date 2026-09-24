/**
 * Machine-wide slot holds for slot seats (Halogen's one slot), successor
 * review r4: the r3 fix counted only this process's in-flight calls, so two
 * conwip-run processes on one halogen seat both admitted on "holders 0" and
 * held the one slot together. The reading's `holders` came from the tally
 * kernel's leases, which conwip-run never takes.
 *
 * A hold is a kernel flock on `<root>/<seat>.<k>` (k < the seat's slot
 * capacity), held by a small flock(1) helper whose stdin is this process: the
 * kernel drops it when this process releases it, closes the pipe or dies by any
 * signal (the helper also carries a parent-death signal). There is no stale
 * file to reclaim and no check-then-take race: taking slot k either succeeds
 * atomically or it is held by a live process.
 */
import { spawn } from "node:child_process";
import { existsSync, mkdirSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { PDEATHSIG_WRAPPER } from "@substrate/runners";

const FLOCK = ["/run/current-system/sw/bin/flock", "/usr/bin/flock", "/bin/flock"].find((p) => existsSync(p));

export const defaultSlotRoot = (): string => join(homedir(), ".local", "state", "substrate", "slots");

export interface SlotHold {
  readonly path: string;
  release(): Promise<void>;
}

/** Try to take one flock on `path` without waiting. undefined when another process holds it. */
export async function tryHold(path: string): Promise<SlotHold | undefined> {
  if (!FLOCK) throw new Error("flock(1) not found; refusing a slot seat without a machine-wide hold");
  const argv = [...PDEATHSIG_WRAPPER, FLOCK, "-n", "-o", "-E", "75", path, "sh", "-c", "echo locked; exec cat >/dev/null"];
  const child = spawn(argv[0]!, argv.slice(1), { stdio: ["pipe", "pipe", "ignore"] });
  const exited = new Promise<number>((r) => child.on("close", (code) => r(code ?? 1)));
  const got = await new Promise<boolean>((r) => {
    child.stdout.once("data", () => r(true));
    void exited.then(() => r(false));
    child.on("error", () => r(false));
  });
  if (!got) {
    const code = await exited;
    if (code === 75) return undefined;
    throw new Error(`slot hold ${path}: flock exit ${code}`);
  }
  child.stdout.resume();
  return {
    path,
    release: async () => {
      child.stdin.end();
      await exited;
    },
  };
}

export class MachineSlots {
  constructor(readonly root: string = defaultSlotRoot()) {}

  /** Take any free slot of `seat` among its `capacity`; undefined when every one is held machine-wide. */
  async take(seat: string, capacity: number): Promise<SlotHold | undefined> {
    mkdirSync(this.root, { recursive: true, mode: 0o700 });
    const safe = seat.replace(/[^A-Za-z0-9_.-]/g, "_");
    for (let k = 0; k < capacity; k++) {
      const h = await tryHold(join(this.root, `${safe}.${k}`));
      if (h) return h;
    }
    return undefined;
  }
}
