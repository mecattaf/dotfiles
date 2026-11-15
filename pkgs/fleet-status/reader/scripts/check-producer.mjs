// Opt-in cross-contract check for a privately staged public observer projection.
import { readFile } from 'node:fs/promises';
import { build } from 'esbuild';
import { Miniflare, convertV4MiniflareOptions } from 'miniflare';
const file = process.argv[2];
if (!file) throw new Error('Usage: node scripts/check-producer.mjs PUBLIC-SNAPSHOT.json');
const body = await readFile(file, 'utf8');
const snapshot = JSON.parse(body);
const result = await build({ entryPoints: ['src/publisher.ts'], bundle: true, write: false, format: 'esm', platform: 'browser', target: 'es2022' });
const token = 'public-contract-test-only-not-a-real-secret';
const mf = new Miniflare(convertV4MiniflareOptions({ modules: true, script: result.outputFiles[0].text,
  compatibilityDate: '2026-11-15', r2Buckets: ['PUBLIC_STATUS'], bindings: { PUBLISH_TOKEN: token } }));
try {
  const response = await mf.dispatchFetch('https://publisher.test/v1/status.json', { method: 'PUT',
    headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json', 'If-None-Match': '*' }, body });
  console.log(JSON.stringify({ accepted: response.status === 200, status: response.status,
    sequence: snapshot.publisher.sequence, subjects: snapshot.subjects.length, observations: snapshot.observations.length,
    events: snapshot.events.length, coverage: snapshot.coverage.length, bytes: Buffer.byteLength(body), response: await response.json() }));
  if (response.status !== 200) process.exitCode = 1;
} finally { await mf.dispose(); }
