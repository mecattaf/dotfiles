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
  it('prints "scheduled 0.2.0" and exits 0', () => {
    const r = run('--version');
    assert.equal(r.status, 0);
    assert.match(r.stdout, /^scheduled 0\.2\.0\n?$/);
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

describe('verb table', () => {
  // Every slice-1 verb is built (11 Nov): each entry of the table has its module, so the CLI's
  // "not built yet" path (ERR_MODULE_NOT_FOUND) is unreachable for the shipped verbs.
  it('has a module for every verb', async () => {
    const { readdirSync } = await import('node:fs');
    const built = new Set(readdirSync(new URL('../src/verbs/', import.meta.url)).map((f) => f.replace(/\.mjs$/, '')));
    const verbs = ['ls', 'show', 'validate', 'schema', 'new', 'set', 'rm', 'run', 'history', 'tick'];
    for (const verb of verbs) assert.ok(built.has(verb), verb);
    // The withdrawn verbs (proposals, host gates, outcome checks, SCHED_* environment) are gone.
    assert.deepEqual([...built].sort(), [...verbs].sort());
  });

  it('refuses a withdrawn verb as unknown, exit 2', () => {
    for (const verb of ['put', 'accept', 'dismiss', 'gate', 'check', 'env']) {
      const r = run(verb);
      assert.equal(r.status, 2, verb);
      assert.match(r.stderr, /unknown verb/i);
    }
  });
});
