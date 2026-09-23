import { chmodSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

export const tmp = (prefix = "axc-runners-") => mkdtempSync(join(tmpdir(), prefix));

/** A fake executable: a bash script written into `dir`. */
export function fakeBin(dir: string, name: string, body: string): string {
  const p = join(dir, name);
  writeFileSync(p, `#!/usr/bin/env bash\n${body}\n`);
  chmodSync(p, 0o755);
  return p;
}
