import type { Subprocess } from "@domicile-desktop/sdk/system";
import type { Domicile } from "@domicile-desktop/sdk/desktop/desktop";

/** Fixed helpers carry private payloads on stdin. The deadline includes spawn,
 * output and exit; a helper that ignores termination cannot hold the UI busy. */
export async function runHelperRequest(domicile: Pick<Domicile, "processes">,
  command: readonly string[], payload: unknown, deadlineMs = 110000) {
  let child: Subprocess | undefined, stopped = false, exited = false;
  const readers = new Set<ReadableStreamDefaultReader<Uint8Array>>();
  const read = async (stream: ReadableStream<Uint8Array>) => {
    const reader = stream.getReader(); readers.add(reader);
    const chunks: Uint8Array[] = []; let size = 0;
    try {
      for (;;) {
        const part = await reader.read(); if (part.done) break;
        size += part.value.length;
        if (size > 16384) throw Error("Helper response exceeded its limit");
        chunks.push(part.value);
      }
      const bytes = new Uint8Array(size); let offset = 0;
      for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
      return new TextDecoder("utf-8", { fatal: true }).decode(bytes);
    } finally { readers.delete(reader); reader.releaseLock(); }
  };
  let timer: ReturnType<typeof setTimeout> | undefined;
  const deadline = new Promise<never>((_, reject) => {
    timer = setTimeout(() => reject(Error("Helper deadline exceeded")), deadlineMs);
  });
  const perform = async () => {
    const started = await domicile.processes.spawn(command, { stdin: true });
    const current = started.match({ Ok: value => value, Err: () => undefined });
    if (current === undefined) throw Error("Helper could not start");
    child = current;
    if (stopped) { current.closeStdin(); current.kill(); throw Error("Helper deadline exceeded"); }
    current.write(JSON.stringify(payload)); current.closeStdin();
    const ended = current.exited.then(value => { exited = true; return value; });
    const [stdout, , exit] = await Promise.all([read(current.stdout), read(current.stderr), ended]);
    if (!exit.match({ Ok: value => value.code === 0 && value.signal === undefined, Err: () => false })) throw Error("Helper did not finish");
    return JSON.parse(stdout);
  };
  try { return await Promise.race([perform(), deadline]); }
  finally {
    stopped = true; clearTimeout(timer); if (!exited) child?.kill();
    for (const reader of readers) void reader.cancel().catch(() => {});
  }
}
