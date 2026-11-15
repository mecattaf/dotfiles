import { asHead, DISCONNECT_MS, json, MAX_BYTES, OBJECT_KEY, readBounded, safeError } from './common';
import { validateSnapshot } from './validation';
import type { Snapshot } from './types';

const API = new Set(['/api/v1/status.json', '/api/v1/catalog.json']);
const ASSETS = new Set(['/', '/index.html', '/app.js', '/styles.css']);

function connection(object: R2Object | null, now: number) {
  if (!object) return { state: 'uninitialized', lastReceivedAt: null, deadlineAt: null };
  const received = object.uploaded.getTime();
  if (!Number.isFinite(received)) throw new Error('invalid receipt time');
  return { state: now - received <= DISCONNECT_MS ? 'connected' : 'disconnected',
    lastReceivedAt: object.uploaded.toISOString(), deadlineAt: new Date(received + DISCONNECT_MS).toISOString() };
}

function catalog(snapshot: Snapshot | null) {
  const signals = new Map<string, Map<string, { key: string; unit?: string }>>();
  for (const row of snapshot?.coverage ?? []) signals.set(row.sourceId, new Map());
  for (const row of snapshot?.observations ?? []) {
    const rows = signals.get(row.sourceId)!;
    rows.set(row.key, { key: row.key, ...(row.unit ? { unit: row.unit } : {}) });
  }
  return { schemaVersion: 'fleet-catalog/1', snapshotId: snapshot?.snapshotId ?? null,
    catalogRevision: snapshot?.catalogRevision ?? null, subjects: snapshot?.subjects ?? [],
    sources: [...signals].map(([id, rows]) => ({ id, signals: [...rows.values()] })) };
}

export default {
  async fetch(request, env): Promise<Response> {
    const url = new URL(request.url);
    const finish = (response: Response) => asHead(response, request.method);
    if ((!API.has(url.pathname) && !ASSETS.has(url.pathname)) || url.search) return finish(safeError('not_found', 404));
    if (!['GET', 'HEAD'].includes(request.method)) return safeError('method_not_allowed', 405, { Allow: 'GET, HEAD' });
    if (ASSETS.has(url.pathname)) {
      const response = await env.ASSETS.fetch(request);
      const headers = new Headers(response.headers);
      headers.set('Content-Security-Policy', "default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'");
      headers.set('X-Content-Type-Options', 'nosniff');
      headers.set('Referrer-Policy', 'no-referrer');
      headers.set('Cache-Control', 'public, max-age=15');
      return new Response(response.body, { status: response.status, headers });
    }
    try {
      const object = await env.PUBLIC_STATUS.get(OBJECT_KEY);
      let snapshot: Snapshot | null = null;
      if (object) {
        if (object.size > MAX_BYTES) throw new Error('invalid object size');
        const bytes = await readBounded(object.body);
        const parsed: unknown = JSON.parse(new TextDecoder('utf-8', { fatal: true, ignoreBOM: false }).decode(bytes));
        if (!validateSnapshot(parsed)) throw new Error('invalid object');
        snapshot = parsed;
      }
      const now = Date.now();
      const value = url.pathname === '/api/v1/catalog.json' ? catalog(snapshot)
        : { schemaVersion: 'fleet-status-response/1', serverTime: new Date(now).toISOString(), connection: connection(object, now), snapshot };
      return finish(json(value, 200, { 'Cache-Control': 'public, max-age=15, must-revalidate' }));
    } catch {
      console.error(JSON.stringify({ event: 'reader_storage_error' }));
      return finish(safeError('storage_unavailable', 503));
    }
  },
} satisfies ExportedHandler<ReaderEnv>;
