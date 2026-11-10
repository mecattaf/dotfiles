#!/usr/bin/env node
// cli.mjs — the `scheduled` command-line entry point.
//
// Every verb is loaded lazily; a verb whose module has not been written yet
// prints "scheduled: <verb> is not built yet" and exits 2.

import { makeContext } from './lib/context.mjs';

const VERSION = '0.1.0';

// ---------------------------------------------------------------------------
// Usage text (spec §10.1)
// ---------------------------------------------------------------------------

const USAGE = `\
scheduled ${VERSION}

USAGE:
  scheduled ls [--agency A] [--json]
  scheduled show (ID | PATH) [--proposal] [--revision R] [--raw]
                 [-n N] [--from ISO] [--json]
  scheduled validate PATH... | --all | --stdin --as PATH  [--json]
  scheduled new ID --cron EXPR --tz ZONE --prompt TEXT [--paused]
  scheduled put ID [--expect REV|none] [--proposal] [--by WHO] < TEXT
  scheduled set ID PATH (VALUE | --unset) [--expect REV] [--by WHO]
  scheduled rm ID [--expect REV] [--by WHO]
  scheduled run ID [--input K=V]... [--by WHO] [--wait] [--follow]
  scheduled history (ID | --all) [-n N] [--since DUR] [--json]
  scheduled history ID --occurrence KEY [--log] [--json]
  scheduled history ID --edits [--diff] [--json]
  scheduled accept ID [--expect REV]
  scheduled dismiss ID
  scheduled schema
  scheduled env   ID --occurrence KEY --attempt N [--json]
  scheduled gate  ID --occurrence KEY --attempt N --json
  scheduled check ID --occurrence KEY --attempt N --json
  scheduled tick [--json] [--state-dir DIR --now ISO]

EXIT CODES:
  0  done
  1  refused (invalid, not found, proposal limit)
  2  usage error
  3  conflict (--expect mismatch)
  4  environment error (state dir or floor DB unreadable)
`;

// ---------------------------------------------------------------------------
// Verb → module mapping
// ---------------------------------------------------------------------------

const VERB_MODULES = {
  ls:       './verbs/ls.mjs',
  show:     './verbs/show.mjs',
  validate: './verbs/validate.mjs',
  new:      './verbs/new.mjs',
  put:      './verbs/put.mjs',
  set:      './verbs/set.mjs',
  rm:       './verbs/rm.mjs',
  run:      './verbs/run.mjs',
  history:  './verbs/history.mjs',
  accept:   './verbs/accept.mjs',
  dismiss:  './verbs/dismiss.mjs',
  schema:   './verbs/schema.mjs',
  env:      './verbs/env.mjs',
  gate:     './verbs/gate.mjs',
  check:    './verbs/check.mjs',
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
  process.stderr.write(`scheduled: unhandled error: ${err.message}\n`);
  process.exit(1);
});
