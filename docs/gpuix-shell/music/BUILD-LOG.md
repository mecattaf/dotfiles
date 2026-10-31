# Music build log

One section per packet (`## M<n> <title>`), appended by its builder: done / not done / untested,
the exact test commands and counts, and anything that could not be verified. The spec is
[`../MUSIC.md`](../MUSIC.md); packets and ownership are its §7.

## M0 Design pass (MUSIC.md)

- Done: MUSIC.md (spec, interfaces, packets, test plan, runbook). Created `pkgs/gpuix-shell/package.json`
  and `tsconfig.json`; `bun install` once (140 packages; bun blocked one `node-gyp` postinstall of an
  optional dbus-next dependency, not needed). Frozen contract files: `src/launcher/provider.ts`,
  `src/music/{types,errors,config,format}.ts`, `src/music/subsonic/{types,api,map}.ts`,
  `src/music/format.test.ts`.
- Verified: `bun x tsc --noEmit -p .` exit 0 (strict); `bun test src/music/format.test.ts` 5 pass;
  MUSIC.md §6.2–6.10 signature blocks compile as `.d.ts` against the frozen files (0 errors).
- Not done: every module beyond the contracts (that is M1–M7). No Navidrome call, mpv run or
  compositor test in this pass.
- Do not re-run `bun install` concurrently; note new dependencies here for the completer.
