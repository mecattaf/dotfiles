// lock.test.mjs — the tick lock (C3.1 phase 0): one holder at a time, and a
// lock left by a power cut or a killed tick never blocks the next boot's tick.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, writeFile, readFile, rm } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { acquireLock, holderAlive, processStart } from '../src/lib/tick.mjs';

async function dir() { return mkdtemp(join(tmpdir(), 'sched-lock-')); }

test('the lock holds PID, boot and start time, and release removes it', async () => {
  const d = await dir();
  const lock = join(d, '.tick.lock');
  const release = await acquireLock(lock, { boot: 'boot-a' });
  const [pid, boot, start] = (await readFile(lock, 'utf8')).trim().split(' ');
  assert.equal(Number(pid), process.pid);
  assert.equal(boot, 'boot-a');
  assert.equal(start, await processStart(process.pid));
  await release();
  assert.equal(existsSync(lock), false);
  await rm(d, { recursive: true });
});

test('a live holder in this boot is waited for, then the wait times out', async () => {
  const d = await dir();
  const lock = join(d, '.tick.lock');
  await writeFile(lock, `${process.pid} boot-a ${await processStart(process.pid)}\n`);
  await assert.rejects(acquireLock(lock, { boot: 'boot-a', timeoutMs: 150, retryIntervalMs: 20 }), /Timed out waiting for lock/);
  await rm(d, { recursive: true });
});

test('a lock written in another boot is taken over at once, though its PID now runs (power cut, VM S4)', async () => {
  const d = await dir();
  const lock = join(d, '.tick.lock');
  // PID 1 always runs: after a reboot the old holder's PID belongs to someone else.
  await writeFile(lock, '1 boot-before-the-cut 12345\n');
  const t0 = Date.now();
  const release = await acquireLock(lock, { boot: 'boot-after', timeoutMs: 2000 });
  assert.ok(Date.now() - t0 < 1000);
  assert.match(await readFile(lock, 'utf8'), new RegExp(`^${process.pid} boot-after `));
  await release();
  await rm(d, { recursive: true });
});

test('a reused PID in this boot is stale: its start time differs', async () => {
  assert.equal(await holderAlive(`${process.pid} boot-a 1`, { boot: 'boot-a' }), false);
  assert.equal(await holderAlive(`${process.pid} boot-a ${await processStart(process.pid)}`, { boot: 'boot-a' }), true);
});

test('a dead PID is stale; an old PID-only lock still uses the liveness check', async () => {
  assert.equal(await holderAlive('999999999', { boot: 'boot-a' }), false);
  assert.equal(await holderAlive(`${process.pid}`, { boot: 'boot-a' }), true);
  assert.equal(await holderAlive('garbage', { boot: 'boot-a' }), false);
});

test('an empty lock file (a cut between create and write) is stale (second review, Zen #1)', async () => {
  const d = await dir();
  const lock = join(d, '.tick.lock');
  await writeFile(lock, '');
  const release = await acquireLock(lock, { boot: 'boot-a', timeoutMs: 2000 });
  assert.match(await readFile(lock, 'utf8'), new RegExp(`^${process.pid} `));
  await release();
  await rm(d, { recursive: true });
});
