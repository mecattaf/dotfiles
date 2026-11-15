import { asHead, BodyLimitError, json, MAX_BYTES, OBJECT_KEY, readBounded, safeError } from './common';
import { validateSnapshot } from './validation';

async function authorized(request: Request, secret: string): Promise<boolean> {
  const provided = /^Bearer (.*)$/i.exec(request.headers.get('Authorization') ?? '')?.[1] ?? '';
  const encoder = new TextEncoder();
  const [providedHash, expectedHash] = await Promise.all([
    crypto.subtle.digest('SHA-256', encoder.encode(provided)),
    crypto.subtle.digest('SHA-256', encoder.encode(secret)),
  ]);
  return crypto.subtle.timingSafeEqual(providedHash, expectedHash);
}

function committedHeaders(object: R2Object | null): Record<string, string> {
  if (!object) return { 'X-Sequence': '-1' };
  const sequence = object.customMetadata?.sequence;
  if (!sequence || !/^\d+$/.test(sequence) || !Number.isSafeInteger(Number(sequence))) throw new Error('invalid metadata');
  return { 'ETag': object.httpEtag, 'X-Sequence': sequence,
    'X-Snapshot-Id': object.customMetadata?.snapshotId ?? '', 'Last-Modified': object.uploaded.toUTCString() };
}

export default {
  async fetch(request, env): Promise<Response> {
    const url = new URL(request.url);
    const finish = (response: Response) => asHead(response, request.method);
    if (url.pathname !== '/v1/status.json' || url.search) return finish(safeError('not_found', 404));
    if (!['PUT', 'HEAD'].includes(request.method)) return safeError('method_not_allowed', 405, { Allow: 'PUT, HEAD' });
    if (typeof env.PUBLISH_TOKEN !== 'string' || env.PUBLISH_TOKEN.length < 32) return finish(safeError('publisher_unconfigured', 503));
    if (!await authorized(request, env.PUBLISH_TOKEN)) return finish(safeError('unauthorized', 401));
    try {
      if (request.method === 'HEAD') {
        const object = await env.PUBLIC_STATUS.head(OBJECT_KEY);
        return finish(json(null, object ? 200 : 404, committedHeaders(object)));
      }
      if (request.headers.get('Content-Type')?.split(';')[0].trim().toLowerCase() !== 'application/json') return safeError('json_required', 415);
      const contentLength = request.headers.get('Content-Length');
      if (contentLength !== null && (!/^\d+$/.test(contentLength) || Number(contentLength) > MAX_BYTES)) return safeError('body_too_large', 413);
      const match = request.headers.get('If-Match');
      const none = request.headers.get('If-None-Match');
      if (match === null && none === null) return safeError('precondition_required', 428);
      if (match !== null && none !== null || none !== null && none !== '*' || match !== null && !/^"[a-f0-9]{32}"$/.test(match)) return safeError('invalid_precondition', 400);
      let bytes: Uint8Array;
      try { bytes = await readBounded(request.body); }
      catch (error) { if (error instanceof BodyLimitError) return safeError('body_too_large', 413); throw error; }
      let data: unknown;
      try { data = JSON.parse(new TextDecoder('utf-8', { fatal: true, ignoreBOM: false }).decode(bytes)); }
      catch { return safeError('invalid_json', 400); }
      if (!validateSnapshot(data)) return safeError('invalid_snapshot', 422);
      const current = await env.PUBLIC_STATUS.head(OBJECT_KEY);
      const headers = committedHeaders(current);
      if (current === null && match !== null || current !== null && (none !== null || match !== current.httpEtag)) return safeError('precondition_failed', 412, headers);
      if (data.publisher.sequence <= Number(headers['X-Sequence'])) return safeError('sequence_not_increasing', 409, headers);
      const condition = current ? { etagMatches: current.etag } : { etagDoesNotMatch: '*' };
      const stored = await env.PUBLIC_STATUS.put(OBJECT_KEY, bytes, {
        onlyIf: condition,
        httpMetadata: { contentType: 'application/json; charset=utf-8', cacheControl: 'no-store' },
        customMetadata: { sequence: String(data.publisher.sequence), snapshotId: data.snapshotId, publisherId: data.publisher.id },
      });
      // R2 evaluates this condition atomically against the actual object,
      // including writers that raced the preceding metadata read.
      if (stored === null) return safeError('precondition_failed', 412);
      console.log(JSON.stringify({ event: 'snapshot_committed', sequence: data.publisher.sequence, bytes: bytes.byteLength }));
      return json({ accepted: true, sequence: data.publisher.sequence }, 200, committedHeaders(stored));
    } catch {
      console.error(JSON.stringify({ event: 'publication_storage_error' }));
      return finish(safeError('storage_unavailable', 503));
    }
  },
} satisfies ExportedHandler<PublisherEnv>;
