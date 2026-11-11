// context.mjs — build the shared context object passed to every verb.
// The context carries I/O handles, path configuration and injected commands
// so that tests can pass their own values without touching the real system.

import { homedir } from 'node:os';
import { realpathSync } from 'node:fs';
import { join } from 'node:path';

/**
 * Build the ctx object used by every verb.
 *
 * Global flags consumed here:
 *   --state-dir DIR   override stateDir (used only by `tick`; left in args
 *                     for other verbs to ignore or forward)
 *   --now ISO         override the clock (used only by `tick`; same treatment)
 *
 * @param {string[]} argv  process.argv.slice(2) or equivalent
 * @returns {{ argv: string[], ctx: object }}
 *   argv is the original slice (global flags are NOT stripped; tick parses
 *   them from args itself so it can validate the ISO string in context).
 */
export function makeContext(argv) {
  // The real path of $HOME (DESIGN 6.1: discovery starts at the real path).
  const home = realpathSync(process.env.HOME || homedir());

  // Default stateDir; tick may override via --state-dir in args.
  const stateDir = join(home, '.agency', 'state', 'master');

  const env = process.env;

  const ctx = {
    home,
    stateDir,
    env,
    // now() returns a Date; tick overrides this via --now ISO.
    now: () => new Date(),
    out: (s) => process.stdout.write(s),
    err: (s) => process.stderr.write(s),
    uid: process.getuid(),
    dshd: env.SCHEDULED_DSHD ?? '/run/current-system/sw/bin/dshd',
    systemctl: env.SCHEDULED_SYSTEMCTL ?? '/run/current-system/sw/bin/systemctl',
    floorUrl: env.SCHEDULED_FLOOR_URL ?? 'http://127.0.0.1:3082',
    machineIdFile: env.SCHEDULED_MACHINE_ID_FILE ?? '/etc/machine-id',
  };

  return { argv, ctx };
}
