/**
 * One path resolver, shared by the two guards that need it.
 *
 * A-10 of the 2026-09-23 review made `assertLedgerPathAllowed` follow symlinks;
 * A-24 of the same review recorded that `assertReadablePath` in `src/record.ts`
 * did NOT, so a refusal still failed open for one spelling. Item 38 left it
 * because sharing the helper meant a cross-import from the parser into the
 * ledger module, or a new file it had forbidden itself. This is that file. It
 * imports nothing from this repository, so neither guard depends on the other.
 */
import { isAbsolute, join, resolve } from "node:path";
import { readlinkSync } from "node:fs";

/**
 * How many links deep this will follow before it gives up. A link loop is not a
 * path a guard can decide; refusing to walk one forever is the whole of the bound.
 */
export const MAX_LINK_DEPTH = 32;

/**
 * Normalize a path AND expand any symlink along it, including a link whose
 * target does not exist yet.
 *
 * `resolve()` collapses `..` but does not follow links, so a symlinked
 * directory walks straight past a prefix comparison. `realpathSync` is not
 * usable here: both callers name a path that may not exist yet, and it throws
 * on a dangling link, which is exactly the case that has to be caught.
 */
export function resolveThroughLinks(path: string, depth = 0): string {
  const abs = resolve(path);
  if (depth >= MAX_LINK_DEPTH) return abs;
  const segments = abs.split("/").filter((s) => s.length > 0);
  let walked = "/";
  for (let i = 0; i < segments.length; i++) {
    const here = join(walked, segments[i]!);
    let target: string | undefined;
    try {
      target = readlinkSync(here);
    } catch {
      target = undefined; // not a link, or not there at all: an ordinary segment
    }
    if (target !== undefined) {
      const base = isAbsolute(target) ? target : join(walked, target);
      return resolveThroughLinks(join(base, ...segments.slice(i + 1)), depth + 1);
    }
    walked = here;
  }
  return abs;
}
