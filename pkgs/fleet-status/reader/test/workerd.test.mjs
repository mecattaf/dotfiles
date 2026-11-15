import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile, mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { build } from 'esbuild';
import { Miniflare, convertV4MiniflareOptions } from 'miniflare';

// Project-local Wrangler4.162.0 with its matching Miniflare engine.
const TOKEN = 'test-only-publisher-bearer-0123456789abcdef';
const ROOT = new URL('../', import.meta.url);
const KEY = 'v1/status.json';
async function bundle(entry, extra = {}) {
  const result = await build({ absWorkingDir: ROOT.pathname, entryPoints: [entry], bundle: true, write: false,
    format: 'esm', platform: 'browser', target: 'es2022', ...extra });
  return result.outputFiles[0].text;
}
function snapshot(sequence = 1) {
  const now = new Date().toISOString();
  const old = new Date(Date.now() - 3600000).toISOString();
  return { schemaVersion: 'fleet-observations/1', snapshotId: 'snapshot-' + sequence, synthetic: false,
    publisher: { id: 'nas-observer', sequence, expectedHeartbeatSeconds: 60 }, generatedAt: now,
    catalogRevision: 'a'.repeat(64), subjects: [{ id: 'fleet', kind: 'fleet', label: 'Fleet', relations: [] },
      { id: 'host-nas', kind: 'host', label: 'NAS', declaredMode: 'continuous', relations: [{ kind: 'part-of', targetId: 'fleet' }] }],
    observations: [{ subjectId: 'host-nas', sourceId: 'fleet.snapshot', key: 'host.reachability', grade: 'cached', value: 'reachable',
      observedAt: old, lastAttemptAt: now, expiresAt: old, errorCode: null }], events: [],
    coverage: [{ sourceId: 'fleet.snapshot', state: 'cached', lastAttemptAt: now, lastSuccessAt: old, errorCode: null }] };
}
const auth = { Authorization: 'Bearer ' + TOKEN };
function putHeaders(etag) { return { ...auth, 'Content-Type': 'application/json', ...(etag ? { 'If-Match': etag } : { 'If-None-Match': '*' }) }; }

test('reader and scoped publisher in real workerd with R2', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'fleet-status-runtime-'));
  const script = await bundle('src/reader.ts');
  const publisher = await bundle('src/publisher.ts');
  const staleReader = await bundle('src/reader.ts', { define: { 'Date.now': 'TEST_NOW' }, banner: { js: `const TEST_NOW = () => ${Date.now() + 240000};` } });
  const broken = await bundle('test/storage-error.mjs');
  const assets = Object.fromEntries(await Promise.all(['index.html', 'app.js', 'styles.css'].map(async name => ['/' + name, await readFile(new URL('public/' + name, ROOT), 'utf8')])));
  assets['/'] = assets['/index.html'];
  const mf = new Miniflare(convertV4MiniflareOptions({ workers: [
    { name: 'reader', modules: true, script, compatibilityDate: '2026-11-15', r2Buckets: { PUBLIC_STATUS: 'public' }, serviceBindings: { ASSETS: 'assets' } },
    { name: 'publisher', modules: true, script: publisher, compatibilityDate: '2026-11-15', r2Buckets: { PUBLIC_STATUS: 'public' }, bindings: { PUBLISH_TOKEN: TOKEN } },
    { name: 'stale', modules: true, script: staleReader, compatibilityDate: '2026-11-15', r2Buckets: { PUBLIC_STATUS: 'public' }, serviceBindings: { ASSETS: 'assets' } },
    { name: 'broken', modules: true, script: broken, compatibilityDate: '2026-11-15' },
    { name: 'assets', modules: true, compatibilityDate: '2026-11-15', script: `const files=${JSON.stringify(assets)};export default {fetch(request){return new Response(files[new URL(request.url).pathname]??'',{headers:{'Content-Type':'text/plain'}})}}` },
  ], r2Persist: directory }));
  try {
    const reader = await mf.getWorker('reader');
    const writer = await mf.getWorker('publisher');
    const stale = await mf.getWorker('stale');
    const failed = await mf.getWorker('broken');
    const bucket = await mf.getR2Bucket('PUBLIC_STATUS', 'reader');
    const request = (worker, path, init) => worker.fetch('https://status.test' + path, init);
    let etag;
    await t.test('missing object is explicitly uninitialized; catalog and HEAD agree', async () => {
      const result = await request(reader, '/api/v1/status.json');
      assert.equal(result.status, 200);
      const data = await result.json();
      assert.deepEqual(data.connection, { state: 'uninitialized', lastReceivedAt: null, deadlineAt: null });
      assert.equal(data.snapshot, null);
      assert.equal((await request(reader, '/api/v1/catalog.json')).status, 200);
      assert.equal(await (await request(reader, '/api/v1/status.json', { method: 'HEAD' })).text(), '');
      assert.equal((await request(writer, '/v1/status.json', { method: 'HEAD', headers: auth })).headers.get('X-Sequence'), '-1');
    });
    await t.test('route and method failures precede storage; storage error is safe', async () => {
      assert.equal((await request(failed, '/unknown')).status, 404);
      assert.equal((await request(failed, '/api/v1/status.json', { method: 'POST' })).status, 405);
      const response = await request(failed, '/api/v1/status.json');
      assert.equal(response.status, 503);
      assert.deepEqual(await response.json(), { error: 'storage_unavailable' });
    });
    await t.test('publisher requires bearer, fixed path/method and CAS preconditions', async () => {
      assert.equal((await request(writer, '/v1/status.json', { method: 'HEAD' })).status, 401);
      assert.equal((await request(writer, '/v1/status.json', { method: 'PUT', headers: { ...auth, Authorization: 'Bearer wrong' } })).status, 401);
      assert.equal((await request(writer, '/another-object', { method: 'PUT', headers: auth })).status, 404);
      assert.equal((await request(writer, '/v1/status.json', { method: 'GET', headers: auth })).status, 405);
      assert.equal((await request(writer, '/v1/status.json', { method: 'PUT', headers: { ...auth, 'Content-Type': 'application/json' }, body: JSON.stringify(snapshot()) })).status, 428);
    });
    await t.test('invalid schema, private fields, synthetic and false semantic values cannot publish', async () => {
      const invalid = [
        value => { value.synthetic = true; }, value => { value.cwd = '/private'; },
        value => { value.subjects[1].label = 'PRIVATE ACCOUNT EMAIL'; },
        value => { value.observations[0].key = 'cwd'; },
        value => { value.observations[0].value = 'PRIVATE SECRET'; },
        value => { value.observations[0].value = { credential: 'private' }; },
        value => { value.observations[0].subjectId = 'missing'; },
        value => { value.observations[0].sourceId = 'constructor'; },
        value => { value.observations[0].value = true; },
        value => { value.publisher.sequence = Number.MAX_SAFE_INTEGER + 1; },
        value => { value.subjects[1].publicUrl = 'https://private.invalid/internal'; },
        value => { value.subjects[1].relations[0].targetId = 'missing'; },
        value => { value.subjects.push(value.subjects[1]); },
        value => { value.observations.push(value.observations[0]); },
        value => { value.observations[0].scope = 'private-custom-scope'; },
        value => { value.observations[0].errorCode = 'PRIVATE EXCEPTION'; },
        value => { value.observations[0].lastAttemptAt = '2000-01-01T00:00:00Z'; },
        value => { value.observations[0].lastGood = { value: 'PRIVATE SECRET', observedAt: value.observations[0].observedAt }; },
        value => { value.observations[0].value = 2; value.observations[0].unit = 'bytes'; },
        value => { value.events.push({ id: 'event-' + 'a'.repeat(24), subjectId: 'fleet', sourceId: 'fleet.snapshot', type: 'collector.error', summary: 'PRIVATE EXCEPTION', at: value.generatedAt }); },
      ];
      for (const mutate of invalid) {
        const value = snapshot(); mutate(value);
        const response = await request(writer, '/v1/status.json', { method: 'PUT', headers: putHeaders(), body: JSON.stringify(value) });
        assert.equal(response.status, 422, await response.text());
      }
      assert.equal(await bucket.head(KEY), null);
    });
    await t.test('fresh receipt stays connected while old source time and stale value stay unchanged', async () => {
      const value = snapshot();
      // A recent upload of old observations is connected, without rewriting source ages.
      value.generatedAt = value.observations[0].observedAt;
      value.observations[0].lastAttemptAt = value.generatedAt;
      value.coverage[0].lastAttemptAt = value.generatedAt;
      const response = await request(writer, '/v1/status.json', { method: 'PUT', headers: putHeaders(), body: JSON.stringify(value) });
      assert.equal(response.status, 200, await response.clone().text());
      etag = response.headers.get('ETag');
      assert.match(etag, /^"[a-f0-9]{32}"$/);
      assert.equal(response.headers.get('X-Sequence'), '1');
      assert.equal(response.headers.get('X-Snapshot-Id'), 'snapshot-1');
      const head = await request(writer, '/v1/status.json', { method: 'HEAD', headers: auth });
      assert.equal(head.headers.get('ETag'), etag);
      assert.equal(await head.text(), '');
      const data = await (await request(reader, '/api/v1/status.json')).json();
      assert.equal(data.connection.state, 'connected');
      assert.equal(data.snapshot.observations[0].observedAt, value.observations[0].observedAt);
      assert.equal(data.snapshot.observations[0].value, 'reachable');
      const disconnected = await (await request(stale, '/api/v1/status.json')).json();
      assert.equal(disconnected.connection.state, 'disconnected');
      assert.equal(disconnected.snapshot.snapshotId, value.snapshotId);
      const catalog = await (await request(reader, '/api/v1/catalog.json')).json();
      assert.equal(catalog.snapshotId, value.snapshotId);
      assert.equal(catalog.catalogRevision, value.catalogRevision);
      assert.deepEqual(catalog.subjects, value.subjects);
    });
    await t.test('sequence and CAS conflicts never replace the committed snapshot', async () => {
      assert.equal((await request(writer, '/v1/status.json', { method: 'PUT', headers: putHeaders(etag), body: JSON.stringify(snapshot(1)) })).status, 409);
      assert.equal((await request(writer, '/v1/status.json', { method: 'PUT', headers: putHeaders('"' + '0'.repeat(32) + '"'), body: JSON.stringify(snapshot(2)) })).status, 412);
      const competing = await Promise.all([2, 3].map(sequence => request(writer, '/v1/status.json', { method: 'PUT', headers: putHeaders(etag), body: JSON.stringify(snapshot(sequence)) })));
      assert.deepEqual(competing.map(response => response.status).sort(), [200, 412]);
      const head = await request(writer, '/v1/status.json', { method: 'HEAD', headers: auth });
      assert.ok(['2', '3'].includes(head.headers.get('X-Sequence')));
      const response = await request(reader, '/api/v1/status.json');
      assert.equal((await response.json()).snapshot.publisher.sequence, Number(head.headers.get('X-Sequence')));
    });
    await t.test('streaming cap rejects bodies beyond 1MiB without trusting Content-Length', async () => {
      const body = new ReadableStream({ start(controller) { controller.enqueue(new Uint8Array(600000)); controller.enqueue(new Uint8Array(600000)); controller.close(); } });
      const response = await request(writer, '/v1/status.json', { method: 'PUT', headers: putHeaders(etag), body, duplex: 'half' });
      assert.equal(response.status, 413);
    });
    await t.test('corrupt stored data is unavailable rather than disconnected or exposed', async () => {
      await bucket.put(KEY, '{"private":"DO_NOT_EXPOSE"}');
      const response = await request(reader, '/api/v1/status.json');
      assert.equal(response.status, 503);
      assert.equal((await response.text()).includes('DO_NOT_EXPOSE'), false);
    });
    await t.test('assets have an explicit CSP and browser rendering never uses HTML injection', async () => {
      const response = await request(reader, '/');
      assert.equal(response.status, 200);
      assert.ok(response.headers.get('Content-Security-Policy').includes("script-src 'self'"));
      assert.ok((await response.text()).includes('Fleet status'));
      assert.equal(/innerHTML|outerHTML|insertAdjacentHTML|document\.write/.test(assets['/app.js']), false);
      assert.ok(assets['/app.js'].includes('textContent'));
    });
  } finally { await mf.dispose(); await rm(directory, { recursive: true, force: true }); }
});
