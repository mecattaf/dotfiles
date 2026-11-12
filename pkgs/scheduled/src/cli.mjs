#!/usr/bin/env node
// cli.mjs — the `scheduled` command-line entry point.
//
// Every verb is loaded lazily; a verb whose module has not been written yet
// prints "scheduled: <verb> is not built yet" and exits 2.

import { makeContext } from './lib/context.mjs';

const VERSION = '0.2.0';

// ---------------------------------------------------------------------------
// Usage text (spec §10.1)
// ---------------------------------------------------------------------------

const USAGE = `\
scheduled ${VERSION}

Scheduled items are <agency>/.agency/scheduled/<item>.jsonc. The heartbeat tick
links one occurrence record per due item into the superagent's inbox and wakes
the floor; the superagent decides what runs.

USAGE:
  scheduled ls [--agency A] [--json]
  scheduled show (ID | PATH) [-n N] [--from ISO] [--inbox DIR] [--json]
  scheduled validate PATH... | --all | --stdin --as PATH  [--json]
  scheduled schema
  scheduled new ID --cron EXPR --tz ZONE (--prompt TEXT | --prompt-file PATH) [--name N]
  scheduled set ID PATH (VALUE | --unset) [--expect REV]
  scheduled rm ID [--expect REV]
  scheduled run ID [--home DIR] [--inbox DIR] [--floor-instance NAME] [--json]
  scheduled history [ID] [--inbox DIR] [-n N] [--json]
  scheduled tick --inbox DIR [--state-dir DIR] [--home DIR] [--floor-instance NAME]
                 [--now ISO] [--json]

ENVIRONMENT:
  SCHEDULED_INBOX           default --inbox (the superagent's <stateDir>/inbox/scheduled)
  SCHEDULED_FLOOR_INSTANCE  default --floor-instance (the floor's dshd instance)
  SCHEDULED_STATE_DIR       default --state-dir, then STATE_DIRECTORY, then
                            $XDG_STATE_HOME/scheduled
  SCHEDULED_DSHD            dshd binary (default /run/current-system/sw/bin/dshd)

EXIT CODES:
  0  done
  1  refused (invalid, not found) or a fault the journal names
  2  usage error
  3  conflict (--expect mismatch)
`;

// ---------------------------------------------------------------------------
// Verb → module mapping
// ---------------------------------------------------------------------------

const VERB_MODULES = {
  ls:       './verbs/ls.mjs',
  show:     './verbs/show.mjs',
  validate: './verbs/validate.mjs',
  schema:   './verbs/schema.mjs',
  new:      './verbs/new.mjs',
  set:      './verbs/set.mjs',
  rm:       './verbs/rm.mjs',
  run:      './verbs/run.mjs',
  history:  './verbs/history.mjs',
  tick:     './verbs/tick.mjs',
};

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main() {
  const argv = process.argv.slice(2);

  // Global flags that do not require a verb.
  if (argv[0] === '--version' || argv[0] === '-V') {
    process.stdout.write(`scheduled ${VERSION}\n`);
    process.exit(0);
  }

  if (argv[0] === '--help' || argv[0] === '-h') {
    process.stdout.write(USAGE);
    process.exit(0);
  }

  // Extract verb.
  const verb = argv[0];

  if (!verb || !(verb in VERB_MODULES)) {
    if (verb) {
      process.stderr.write(`scheduled: unknown verb '${verb}'\n`);
    }
    process.stderr.write(USAGE);
    process.exit(2);
  }

  // Build context.
  const { ctx } = makeContext(argv);

  // Load verb module lazily.
  const args = argv.slice(1);
  let mod;
  try {
    mod = await import(VERB_MODULES[verb]);
  } catch (err) {
    if (err.code === 'ERR_MODULE_NOT_FOUND') {
      process.stderr.write(`scheduled: ${verb} is not built yet\n`);
      process.exit(2);
    }
    throw err;
  }

  if (typeof mod.main !== 'function') {
    process.stderr.write(`scheduled: ${verb} is not built yet\n`);
    process.exit(2);
  }

  const code = await mod.main(args, ctx);
  process.exit(typeof code === 'number' ? code : 0);
}

main().catch((err) => {
  // The tick's journal lines carry a syslog priority (DESIGN 12, C3.12); so does its crash.
  const prefix = process.argv[2] === 'tick' ? '<3>' : '';
  process.stderr.write(`${prefix}scheduled: unhandled error: ${err.message}\n`);
  process.exit(1);
});
