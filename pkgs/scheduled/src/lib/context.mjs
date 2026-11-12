// context.mjs — build the shared context object passed to every verb.
// The context carries I/O handles, path configuration and injected commands
// so that tests can pass their own values without touching the real system.

import { homedir } from 'node:os';
import { realpathSync } from 'node:fs';
import { join } from 'node:path';

/**
 * The heartbeat's own state directory: SCHEDULED_STATE_DIR, then systemd's STATE_DIRECTORY,
 * then $XDG_STATE_HOME/scheduled, else ~/.local/state/scheduled. Never the superagent's stateDir.
 */
export function stateDirOf(env, home) {
  if (env.SCHEDULED_STATE_DIR) return env.SCHEDULED_STATE_DIR;
  // systemd joins several StateDirectory= paths with ':'; the unit names one.
  if (env.STATE_DIRECTORY) return env.STATE_DIRECTORY.split(':')[0];
  return join(env.XDG_STATE_HOME || join(home, '.local', 'state'), 'scheduled');
}

/**
 * Build the ctx object used by every verb. Flags (--inbox, --state-dir, --home, --floor-instance,
 * --now) are parsed by the verbs that take them and win over these defaults.
 *
 * @param {string[]} argv  process.argv.slice(2) or equivalent
 * @returns {{ argv: string[], ctx: object }}
 */
export function makeContext(argv) {
  const env = process.env;
  // The real path of $HOME: discovery starts at the real path, and records carry real paths.
  const home = realpathSync(env.HOME || homedir());

  const ctx = {
    home,
    stateDir: stateDirOf(env, home),
    inbox: env.SCHEDULED_INBOX || null,
    floorInstance: env.SCHEDULED_FLOOR_INSTANCE || null,
    env,
    now: () => new Date(),
    out: (s) => process.stdout.write(s),
    err: (s) => process.stderr.write(s),
    uid: process.getuid(),
    dshd: env.SCHEDULED_DSHD ?? '/run/current-system/sw/bin/dshd',
    systemctl: env.SCHEDULED_SYSTEMCTL ?? '/run/current-system/sw/bin/systemctl',
    machineIdFile: env.SCHEDULED_MACHINE_ID_FILE ?? '/etc/machine-id',
  };

  return { argv, ctx };
}
