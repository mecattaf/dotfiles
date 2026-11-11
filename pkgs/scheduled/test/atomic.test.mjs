// atomic.test.mjs — tests for src/lib/atomic.mjs
// Run: node --test test/atomic.test.mjs

import { describe, it, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, existsSync, mkdirSync } from 'node:fs';
import { rm } from 'node:fs/promises';
import { join } from 'node:path';
import os from 'node:os';

import { writeAtomic, linkExclusive, appendLine } from '../src/lib/atomic.mjs';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function tmpDir() {
  return mkdtempSync(join(os.tmpdir(), 'scheduled-atomic-test-'));
}

// ---------------------------------------------------------------------------
// writeAtomic
// ---------------------------------------------------------------------------

describe('writeAtomic', () => {
  let dir;
  before(() => { dir = tmpDir(); });
  after(() => rm(dir, { recursive: true, force: true }));

  it('writes string content to path', async () => {
    const path = join(dir, 'out.jsonc');
    await writeAtomic(path, '{"hello":1}');
    assert.equal(readFileSync(path, 'utf8'), '{"hello":1}');
  });

  it('overwrites existing file atomically', async () => {
    const path = join(dir, 'over.txt');
    await writeAtomic(path, 'first');
    await writeAtomic(path, 'second');
    assert.equal(readFileSync(path, 'utf8'), 'second');
  });

  it('writes Buffer content', async () => {
    const path = join(dir, 'buf.bin');
    const buf = Buffer.from([0x61, 0x62, 0x63]);
    await writeAtomic(path, buf);
    assert.deepEqual(readFileSync(path), buf);
  });

  it('leaves no .tmp file on success', async () => {
    const path = join(dir, 'clean.txt');
    await writeAtomic(path, 'hello');
    const tmpPath = join(dir, `.clean.txt.${process.pid}.tmp`);
    assert.ok(!existsSync(tmpPath), 'tmp file should not remain');
  });
});

// ---------------------------------------------------------------------------
// linkExclusive
// ---------------------------------------------------------------------------

describe('linkExclusive', () => {
  let dir, tmpSpool, incoming;
  before(() => {
    dir = tmpDir();
    tmpSpool = join(dir, 'tmp');
    incoming = join(dir, 'incoming');
    mkdirSync(tmpSpool);
    mkdirSync(incoming);
  });
  after(() => rm(dir, { recursive: true, force: true }));

  it('returns created and writes the file', async () => {
    const dest = join(incoming, 'occ1.json');
    const result = await linkExclusive(tmpSpool, dest, '{"v":1}');
    assert.equal(result, 'created');
    assert.equal(readFileSync(dest, 'utf8'), '{"v":1}');
  });

  it('returns exists when destination already exists', async () => {
    const dest = join(incoming, 'occ2.json');
    await linkExclusive(tmpSpool, dest, '{"v":1}');
    const result = await linkExclusive(tmpSpool, dest, '{"v":2}');
    assert.equal(result, 'exists');
    // content should remain the first write
    assert.equal(readFileSync(dest, 'utf8'), '{"v":1}');
  });

  it('leaves no temp file after created', async () => {
    const dest = join(incoming, 'occ3.json');
    await linkExclusive(tmpSpool, dest, 'x');
    const leftover = tmpSpool;
    const { readdirSync } = await import('node:fs');
    const remaining = readdirSync(leftover).filter(f => f.endsWith('.json'));
    assert.equal(remaining.length, 0, 'no temp files should remain');
  });
});

// ---------------------------------------------------------------------------
// appendLine
// ---------------------------------------------------------------------------

describe('appendLine', () => {
  let dir;
  before(() => { dir = tmpDir(); });
  after(() => rm(dir, { recursive: true, force: true }));

  it('appends a JSON line to a new file', async () => {
    const path = join(dir, 'ledger.jsonl');
    await appendLine(path, { v: 1, msg: 'hello' });
    const lines = readFileSync(path, 'utf8').trim().split('\n');
    assert.equal(lines.length, 1);
    assert.deepEqual(JSON.parse(lines[0]), { v: 1, msg: 'hello' });
  });

  it('appends multiple lines', async () => {
    const path = join(dir, 'multi.jsonl');
    await appendLine(path, { a: 1 });
    await appendLine(path, { b: 2 });
    await appendLine(path, { c: 3 });
    const lines = readFileSync(path, 'utf8').trim().split('\n');
    assert.equal(lines.length, 3);
    assert.deepEqual(JSON.parse(lines[2]), { c: 3 });
  });

  it('each line ends with a newline', async () => {
    const path = join(dir, 'newline.jsonl');
    await appendLine(path, { x: 1 });
    const content = readFileSync(path, 'utf8');
    assert.ok(content.endsWith('\n'), 'file must end with newline');
  });
});
