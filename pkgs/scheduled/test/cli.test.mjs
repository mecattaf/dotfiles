// cli.test.mjs — integration tests for the CLI entry point
// Tests --version, --help, unknown verb, and not-built verb behaviour.
// Run: node --test test/cli.test.mjs

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { join, dirname } from 'node:path';

const NODE = process.execPath;
const CLI = join(dirname(fileURLToPath(import.meta.url)), '../src/cli.mjs');

function run(...args) {
  return spawnSync(NODE, [CLI, ...args], { encoding: 'utf8' });
}

// ---------------------------------------------------------------------------
// --version
// ---------------------------------------------------------------------------

describe('--version', () => {
  it('prints "scheduled 0.1.0" and exits 0', () => {
    const r = run('--version');
    assert.equal(r.status, 0);
    assert.match(r.stdout, /^scheduled 0\.1\.0\n?$/);
    assert.equal(r.stderr, '');
  });
});

// ---------------------------------------------------------------------------
// --help
// ---------------------------------------------------------------------------

describe('--help', () => {
  it('prints usage and exits 0', () => {
    const r = run('--help');
    assert.equal(r.status, 0);
    assert.ok(r.stdout.includes('scheduled ls'), '--help should include verb list');
    assert.ok(r.stdout.includes('scheduled tick'), '--help should include tick');
  });
});

// ---------------------------------------------------------------------------
// unknown verb
// ---------------------------------------------------------------------------

describe('unknown verb', () => {
  it('prints usage to stderr and exits 2', () => {
    const r = run('frobnicate');
    assert.equal(r.status, 2);
    assert.match(r.stderr, /unknown verb/i);
    // usage should appear on stderr
    assert.ok(r.stderr.includes('scheduled ls'), 'usage should be on stderr');
  });
});

// ---------------------------------------------------------------------------
// no verb
// ---------------------------------------------------------------------------

describe('no verb', () => {
  it('prints usage to stderr and exits 2', () => {
    const r = run();
    assert.equal(r.status, 2);
    assert.ok(r.stderr.includes('scheduled ls'), 'usage should be on stderr');
    assert.equal(r.stdout, '');
  });
});

// ---------------------------------------------------------------------------
// verb not built yet
// ---------------------------------------------------------------------------

describe('not-built verb', () => {
  // `dismiss` is in the verb table but its module file does not exist in this task.
  // The CLI must catch ERR_MODULE_NOT_FOUND and print the right message.
  it('prints "scheduled: <verb> is not built yet" and exits 2', () => {
    const r = run('dismiss');
    assert.equal(r.status, 2);
    assert.match(r.stderr, /scheduled: dismiss is not built yet/);
  });
});
