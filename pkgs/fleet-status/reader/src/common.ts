export const OBJECT_KEY = 'v1/status.json';
export const MAX_BYTES = 1_048_576;
export const DISCONNECT_MS = 180_000;

export class BodyLimitError extends Error {}

export async function readBounded(stream: ReadableStream<Uint8Array> | null): Promise<Uint8Array> {
  if (!stream) return new Uint8Array();
  const reader = stream.getReader();
  const parts: Uint8Array[] = [];
  let length = 0;
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      length += value.byteLength;
      if (length > MAX_BYTES) {
        await reader.cancel();
        throw new BodyLimitError();
      }
      parts.push(value);
    }
  } finally { reader.releaseLock(); }
  const result = new Uint8Array(length);
  let offset = 0;
  for (const part of parts) { result.set(part, offset); offset += part.byteLength; }
  return result;
}

export function json(value: unknown, status = 200, headers: HeadersInit = {}): Response {
  return new Response(JSON.stringify(value), { status, headers: {
    'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff', ...headers,
  } });
}

export function safeError(code: string, status: number, headers: HeadersInit = {}): Response {
  return json({ error: code }, status, headers);
}

export function asHead(response: Response, method: string): Response {
  return method === 'HEAD' ? new Response(null, { status: response.status, headers: response.headers }) : response;
}
