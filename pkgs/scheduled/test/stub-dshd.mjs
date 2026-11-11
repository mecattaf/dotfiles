#!/usr/bin/env node

import fs from 'node:fs';
import { fileURLToPath } from 'node:url';

export const SAMPLE_FAILED_STATE = {
  state: 'failed',
  enabled: false,
  lastRun: {
    startedAt: 1794354856,
    invocationId: 'fb9a810a54094f8ca9e6c8e774622dcd',
    ending: 'failed',
    endedAt: 1794354936,
    serviceResult: 'exit-code',
    exitCode: 'exited',
    exitStatus: '1',
    child: { exitCode: 1 },
    thisBoot: true,
  },
  release: { name: 'default', state: 'current', label: 'dsh-0.2.2-rc.1' },
  remedy: 'dshd start --rerun ovn-d3-2',
};

export const SAMPLE_STATES = {
  failed: SAMPLE_FAILED_STATE,
};

function main() {
  const argv = process.argv.slice(2);

  // Append each argv to $STUB_DSHD_LOG if configured
  if (process.env.STUB_DSHD_LOG) {
    try {
      fs.appendFileSync(process.env.STUB_DSHD_LOG, JSON.stringify(argv) + '\n');
    } catch (err) {
      console.error(`Failed to append to STUB_DSHD_LOG: ${err.message}`);
    }
  }

  const stateFile = process.env.STUB_DSHD_STATE;
  let stateData = null;

  if (stateFile) {
    if (SAMPLE_STATES[stateFile]) {
      stateData = SAMPLE_STATES[stateFile];
    } else if (fs.existsSync(stateFile)) {
      try {
        stateData = JSON.parse(fs.readFileSync(stateFile, 'utf8'));
      } catch (err) {
        console.error(`Invalid JSON in STUB_DSHD_STATE: ${err.message}`);
        process.exit(1);
      }
    } else {
      // If state file path is set but file does not exist: dshd get reports not-found (exit 3)
      if (argv[0] === 'get') {
        process.stderr.write('floor not found\n');
        process.exit(3);
      }
    }
  }

  const cmd = argv[0];

  if (cmd === 'get') {
    if (!stateData) {
      process.stderr.write('floor not found\n');
      process.exit(3);
    }

    const exitCode = stateData.exitCode ?? stateData.code;
    if (typeof exitCode === 'number' && exitCode !== 0) {
      if (stateData.stderr) process.stderr.write(stateData.stderr + '\n');
      if (stateData.stdout) process.stdout.write(stateData.stdout + '\n');
      else if (stateData.error) process.stdout.write(JSON.stringify({ error: stateData.error }) + '\n');
      process.exit(exitCode);
    }

    if (stateData.stdout) {
      process.stdout.write(stateData.stdout + '\n');
    } else {
      process.stdout.write(JSON.stringify(stateData) + '\n');
    }
    process.exit(0);
  }

  if (cmd === 'start') {
    if (stateData?.start) {
      const startExitCode = stateData.start.exitCode ?? stateData.start.code;
      if (typeof startExitCode === 'number' && startExitCode !== 0) {
        if (stateData.start.stderr) process.stderr.write(stateData.start.stderr + '\n');
        if (stateData.start.stdout) process.stdout.write(stateData.start.stdout + '\n');
        process.exit(startExitCode);
      }
      const out = stateData.start.stdout || (typeof stateData.start === 'string' ? stateData.start : JSON.stringify(stateData.start));
      process.stdout.write(out + '\n');
      process.exit(0);
    }

    // Default start answer
    process.stdout.write(JSON.stringify({ result: 'started' }) + '\n');
    process.exit(0);
  }

  if (cmd === 'update') {
    if (stateData?.update) {
      const updateExitCode = stateData.update.exitCode ?? stateData.update.code;
      if (typeof updateExitCode === 'number' && updateExitCode !== 0) {
        if (stateData.update.stderr) process.stderr.write(stateData.update.stderr + '\n');
        if (stateData.update.stdout) process.stdout.write(stateData.update.stdout + '\n');
        process.exit(updateExitCode);
      }
      const out = stateData.update.stdout || (typeof stateData.update === 'string' ? stateData.update : JSON.stringify(stateData.update));
      process.stdout.write(out + '\n');
      process.exit(0);
    }

    // Default update answer
    process.stdout.write(JSON.stringify({ result: 'updated' }) + '\n');
    process.exit(0);
  }

  // Any other command
  process.exit(0);
}

const selfPath = fileURLToPath(import.meta.url);
if (process.argv[1] && (process.argv[1] === selfPath || process.argv[1].endsWith('stub-dshd.mjs'))) {
  main();
}
