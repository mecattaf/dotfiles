# 21 — Nix packaging, flake wiring and the test harness for `gpuix-shell`

Reader 21 of the overnight gpuix-shell build (wave 1), written 2026-10-20 23:10–23:55 CEST on the
strix, cc2 seat. Read-only except this file and scratch builds under `/tmp` (listed in §5.9).
Labels: **MEASURED** = I ran it tonight (or read the bytes on disk) and give the command;
**REPORTED** = a file, transcript note or earlier agent says so; **INFERRED** = my reading.

**Revision 2: 2026-10-21 12:00–12:20 CEST, a re-run of reader 21 (Opus).** The night pipeline
stopped at 00:03. NIGHT-LOG: the planner wrote no `PLAN.json`, and every wave-3/4 job ended
`rc=1 bytes=62`. That makes this note the direct input to the wave-3 packet
`runner/wave3/02-complete/002-nix-package.md`, which says "Follow
docs/gpuix-shell/wave1/21-nix-packaging-and-checks.md". Since revision 1 (23:46), the music
chain wrote a real scaffold (`W/pkgs/gpuix-shell/{package.json,tsconfig.json,bun.lock,src/music/**,src/launcher/provider.ts}`,
23:41–23:48). Revision 2:
- builds **that scaffold** under Nix (§5.10, MEASURED);
- pins its two loose versions and settles the lockfile policy (§5.10);
- corrects SCOPE S-012: the native self-tests belong in installCheckPhase, not checkPhase (§5.10);
- adds the measured `git add -N` route to the flake (§5.10) and a numbered builder sequence (§5.11);
- fixes the `deadnix` scope (§5.3e) and updates §6.

Revision 1 still holds: `flake.nix` in W is byte-identical to main `dadb1426` (re-MEASURED
12:01), every line pointer spot-checked in revision 2 still matches, and both revision-1 store
outputs (`6szgr9…`, `3rr5xk9c…`) still exist. Revision 2 kept verification light (Tom's
2026-10-20 standing rule): no smoke was re-run, and the RUNPATH and the build were re-measured once.

Abbreviations used for paths:

| Short | Path |
|---|---|
| `W` | `/home/tom/.wt/dotfiles/gpuix-shell` (this branch, `experimental/gpuix-shell` off main `dadb1426`) |
| `HS` | `/home/tom/.wt/hyprland-solid-shell` (the Hyprland/Solid/0.10.0 precedent, uncommitted) |
| `MS` | `/home/tom/.wt/dotfiles/morning-shell` (PR #565, `tests/workspace-switcher`) |
| `SP` | `/tmp/claude-1000/-home-tom-tuesday-oct20/94d008d7-4112-4bf7-92cd-2de4eab69681/scratchpad` |
| `P21c` | `SP/nixpkg-probe-21c` (a toy gpuix-shell package an earlier attempt at this reader built; see §1.2) |

`flake.nix` is byte-identical in `W` and in `/home/tom/mecattaf/dotfiles` (MEASURED:
`diff <(git -C ~/mecattaf/dotfiles show HEAD:flake.nix) W/flake.nix` → no output; that checkout
is on `rules/ultracode-light-verify` f501e856). So every `flake.nix:N` pointer below holds in both.

---

## 0. The answer in fifteen lines

1. **Yes: `buildNpmPackage` takes the published `@gpuix/native-linux-x64-gnu@0.11.0` prebuilt
   `.node` from `package-lock.json` and `autoPatchelfHook` fixes it.** MEASURED tonight: four
   toy builds against this flake's pinned nixpkgs (`e2587cae`, bun 1.3.13, node 24.18.0) succeeded,
   `auto-patchelf: 0 dependencies could not be satisfied`.
2. **No source build and no patch are needed for 0.11.0.** The "patched 0.10.0 binding" of
   10-14 was the *published* npm binary with only its RUNPATH rewritten by autoPatchelf. The GPUI
   blur patch in `HS/pkgs/desktop-shell/patches/` was never applied and is parked (Tom stopped it).
   Tom's look is flat and opaque, so blur isn't needed (§2).
3. **The binary's real library needs (MEASURED with `readelf -d` + `strings`):** NEEDED =
   `libxcb.so.1`, `libxkbcommon.so.0`, `libxkbcommon-x11.so.0`, `libgcc_s.so.1` (+ libc/libm/ld).
   dlopen()ed = `libwayland-client.so.0`, `libwayland-egl.so.1`, `libvulkan.so.1`, `libEGL.so.1`.
   No fontconfig/freetype/X11/openssl. Fonts come from a built-in Rust fontdb that parses
   `/etc/fonts/fonts.conf` itself.
4. **Best recipe (MEASURED rendering):** `buildInputs = [ stdenv.cc.cc.lib libxkbcommon libxcb ]`
   plus `appendRunpaths = [ wayland vulkan-loader libGL ]/lib`. Then **no `LD_LIBRARY_PATH` in the
   wrapper**, so nothing leaks into apps the launcher spawns. `runtimeDependencies` does **not**
   work for a `.node` (MEASURED: its RUNPATH stayed without wayland/vulkan).
5. **Network:** only the fixed-output `npmDeps` derivation reaches the registry. The main build is
   offline, so every package, including the platform `.node` tarball, must be in `package-lock.json`
   with `resolved` + `integrity`. `bun.lock` is ignored by Nix.
6. **`npmDepsHash`** = `prefetch-npm-deps package-lock.json` (MEASURED: it printed exactly the hash
   the builds used, `sha256-PLas/KzhWF2NvFGTX5Z3OfINGIeGrrVSGse4kAJKI0k=`), or the house way:
   `lib.fakeHash`, build, paste the `got:`.
7. **Bundle everything except `@gpuix/native` + `@gpuix/native/*`** (and dbus-next's optional
   `usocket`, `x11`). Ship only four runtime packages in `node_modules`. Closure: 213.2 MiB, against
   598.8 MiB for `npm prune` + copy-all (MEASURED).
8. **`checkPhase` runs before autoPatchelf.** A `bun test` that imports `@gpuix/react` fails there
   with "Cannot find native binding" (cause: `libxcb.so.1: cannot open shared object file`) unless
   `checkPhase` exports `LD_LIBRARY_PATH` for the three NEEDED libs. MEASURED both ways.
   `installCheckPhase` runs **after** fixup, so `--check-native`/`--check-dbus` belong there
   (MEASURED passing in the sandbox).
9. **The published Linux binary has no test renderer** (`hasTestGpuixRenderer()` → `false`,
   MEASURED). So: pure-logic `bun test` in Nix, plus pixel/IPC smokes on an isolated headless Sway
   under `runtime-test --render-node`. Never in `nix flake check`.
10. **Rendering with the Nix build is MEASURED:** the RUNPATH-only build, with `LD_LIBRARY_PATH`
    and `VK_ICD_FILENAMES` unset, maps a 56 px layer-shell rail with exclusive zone 56 on headless
    Sway 1.12 (gles2) → workspace rect `x=56 width=1384` on 1440×900.
11. **Flake wiring:** one overlay line (`overlays/default.nix`), one entry in the
    `packages.${system}` list (`flake.nix:506-536`), checks `gpuix-shell` (the package; its
    check/installCheck run bun test and the load check) plus `gpuix-shell-themes`, and
    `home-profiles` asserts (`flake.nix:1213-1229` must become conditional). HM module
    `home/gpuix-shell.nix` imported from `home/home.nix:102-115`.
12. **Test conventions:** `tests/<area>/test_*.py` = stdlib `unittest` (not pytest), hermetic,
    wired into a `pkgs.runCommand` check with `python3 …`. `tests/<area>/smoke*.py` = compositor
    tests that refuse a live runtime and run only via `runtime-test`, never in a flake check.
    The branch's `runtime-test` has `--render-node`; the **installed `~/.local/bin/runtime-test`
    does not** (MEASURED: `grep -c render-node` → 0), so smokes must call
    `ROOT/home/dot_local/bin/runtime-test`.
13. **The real scaffold builds** (revision 2, MEASURED 10-21 12:05). A scratch copy of
    `W/pkgs/gpuix-shell` (music + launcher sources, 1,305 lines), plus a stub `src/main.tsx` and
    `build.ts`, passes `tsc --noEmit`, `bun test` (bun 1.3.13: 6 pass, 0 fail, the music
    `format.test.ts` included), autoPatchelf (0 unsatisfied) and installCheck. The closure stays
    at 213.2 MiB.
14. **The scaffold is not Nix-ready yet.** It has no `package-lock.json` (only bun's text
    `bun.lock`), no `build` script, no `build.ts` and no `src/main.tsx`. It also has `"zod": "^4"`
    and `"@types/bun": "latest"`, which resolves to 1.4.3, above the Nix bun 1.3.13. The fix list,
    the exact pins (MEASURED building) and the hash are in §5.10.
15. **`git add -N` makes untracked files visible to the flake** without committing (MEASURED,
    Nix 2.34.8). With it, the builder can use `nix build W#gpuix-shell` instead of the
    `--impure --expr` form (§5.10, §5.11).

---

## 1. What this source is

### 1.1 Sources read (all opened tonight)

| Source | What it gave |
|---|---|
| `W/docs/gpuix-shell/BRIEF.md` (whole) | the order, architecture §3.9 "Nix", working rules §4 |
| `HS/pkgs/desktop-shell/{default.nix,package.json,build.ts,tsconfig.json,main.ts,README.md,.gitignore}` | the 10-14 Nix precedent (Solid, 0.10.0, Hyprland) |
| `HS/pkgs/desktop-shell/patches/README.md` | the never-applied GPUI blur patch; "Stopped at Tom's request" |
| `git -C HS diff main -- flake.nix overlays/default.nix`, `HS/home/hyprland.nix` | how desktop-shell was wired (overlay, packages, units, asserts) |
| `W/flake.nix` 270-345 (overlay list), 434-436 (`overlays.default`), 497-558 (`packages`), 567-581 (formatter/devShell), 583-735 (first checks), 1074-1382 (`home-profiles`), 1596-1620 (`raw-dotfiles-guard`), 1786-1806 (`screenshot-spool`), 2390-2445 (`deadnix`, `browser-session-runtime`, `herdr-launchers`) | the wiring points |
| `W/overlays/default.nix`, `W/pkgs/substrate-apps/default.nix`, `W/pkgs/chrome-stream/default.nix` | overlay idiom, the only other npm/bun precedents (pnpm FOD + esbuild; bun as a runtime dep) |
| `W/home/home.nix:95-125`, `W/home/vicinae.nix`, `W/home/theme.nix`, `W/home/themes/default.nix:1-22,281-296`, `W/modules/sway.nix:15-23,100-165`, `W/hosts/client/default.nix:40-130,232` | HM import list, Vicinae/mako gating, theme fragments, the session target, client wiring |
| `W/home/dot_local/bin/runtime-test` + `git diff` | the `--render-node` copy (byte-identical to HS's copy, MEASURED `diff`) |
| `W/tests/runtime-test/{test_isolation.py,test_allow_kvm.py}`, `HS/tests/runtime-test/test_render_node.py` | wrapper tests |
| `W/tests/sway-vicinae/{README.md,smoke.py}`, `MS/tests/workspace-switcher/{README.md,test_switcher.py,test_fixtures.py,smoke.py}`, `HS/tests/hyprland/{README.md,smoke.py}` | the three smoke shapes |
| `W/docs/runbook-conventions.md`, `W/DECISIONS.md` (head + R-1…R-18 at 715-775 + 83-110), `W/DEFERRED.md`, `W/AGENTS.md` | house rules |
| `W/docs/gpuix-shell/evidence/rail-probe/{rail.tsx,smoke.py}` | the orchestrator's MEASURED rail (bun 1.4.2, no Nix) |
| `W/docs/gpuix-shell/wave1/{01,02,03,13,14}-*.md` (excerpts) | Tom quotes with timestamps, 10-14 lessons L1-L19 |
| The published `@gpuix/native@0.11.0` (`index.js`, `index.d.ts`, `dist/runtime.js`, `package.json`) and `@gpuix/react@0.11.0` | loader behaviour, override env var, automation trigger |
| `/home/tom/Downloads/gpuix` (515df19) `CHANGELOG.md` | layer-shell (0.10.0 §5), Linux test renderer unavailable, quit-on-last-window |
| **Revision 2:** `W/pkgs/gpuix-shell/{package.json,tsconfig.json,.gitignore,bun.lock,src/**}` | the real scaffold the music chain wrote 23:41–23:48 (§5.10) |
| **Revision 2:** `W/docs/gpuix-shell/{SCOPE.md S-001…S-014,BOUNDARY.md,KEYS.md §7–§8,MUSIC.md,NIGHT-LOG.md,ASSUMPTIONS.md}` | the synthesis that already cites this note; S-012 needs the phase correction; unit names `gpuix-shell-<surface>` |
| **Revision 2:** `W/modules/sway.nix:24-41,63,76-79,125`, `W/home/home.nix:405-531`, `W/pkgs/gpuix-shell/src/music/config.ts` | the units' inherited PATH and `XDG_CURRENT_DESKTOP`; `GPUIX_SHELL_MPV` |
| **Revision 2:** `runner/wave3/02-complete/002-nix-package.md` | the builder packet that consumes this note (§5.11 is written for it) |

### 1.2 A predecessor attempt of this same reader

The night runner re-ran three missing readers (NIGHT-LOG 23:27). An earlier attempt at reader 21
left work in `SP` but no note. **MEASURED** (file times and `nix derivation show`):

| Dir | Time | What it varied | Store output | Result |
|---|---|---|---|---|
| `SP/nixpkg-probe-21` | 23:18 | `npm prune --omit=dev` then copy all `node_modules`; wrapper `LD_LIBRARY_PATH` | `cpc4z877…-gpuix-shell-0.1.0` | built; **598.8 MiB** closure (node-gyp tree + patched shebangs pull nodejs/python) |
| `SP/nixpkg-probe-21b` | 23:20 | selective copy of 4 runtime packages; wrapper `LD_LIBRARY_PATH` | `bnsarhrr…` | built; 213 MiB; smoke OK (`/tmp/gpuix-nix-rail-gaa74mc1`) |
| `SP/nixpkg-probe-21c` | 23:24 | selective copy; **`appendRunpaths`**, no wrapper env | `6szgr9gv…` | built; 213.2 MiB; smoke OK twice (`/tmp/gpuix-nix-rail-{35lsigf3,u5u5u0yb}`), one of them without `VK_ICD_FILENAMES` |
| (variant, drv `0pmy5d4m…`) | ~23:22 | `runtimeDependencies = [ wayland vulkan-loader libglvnd ]` | `c3fflbyv…` | built, but **RUNPATH lacks wayland/vulkan** (MEASURED `patchelf --print-rpath`) → would fail without `LD_LIBRARY_PATH` (INFERRED; never smoked) |
| `gpuix-shell-load-check` (drv `07lymb13…`) | — | `runCommand`: `HOME=$TMPDIR …/bin/gpuix-shell --check-native \| tee $out; grep -q true $out` | `yj0a6vh7…` = `{"ok":true,"exports":7,"bun":"1.3.13"}` | passed in the sandbox |

I re-verified the parts the design rests on myself (§5.9): the RUNPATH, the sandbox load, the
render, the hash, and a fourth build `SP/nixpkg-probe-21d` that adds `installCheckPhase` and the
`checkPhase` library net.

---

## 2. Verbatim Tom rulings relevant to the packaged shell

| When | Words (verbatim) | Source | Consequence for packaging/tests |
|---|---|---|---|
| 2026-10-20 ~22:50/23:05 CEST | "staying on sway window manager (my wm of choice) ; and in my ~/dotfiles with an experimental branch" | BRIEF §1 | package lives in `pkgs/gpuix-shell`, wired in this flake, on `experimental/gpuix-shell` |
| 2026-10-20 | "make sure that the work you do will set the foundation for my subsequent work on achieving the world's most complete linux desktop shell without using quickshell. gpuix as the frontend all the way is desired." | BRIEF §1/§5 | one package, many surfaces; recipe must scale (externals list, checks) |
| 2026-10-20 | "keeping the anthropic font that i have ... is important." | BRIEF §1 | fonts come from the system (`modules/common.nix fonts.packages`); never bundle them; `registerFont` not needed (§4.4) |
| 2026-10-20 | "do not block further overnight work on 'waiting on tom's input'" | BRIEF §1 | decisions below are recommendations, logged as assumptions |
| 2026-10-20 23:20 CEST | "logging off now, there will be no further inputs on my behalf. be proactive ... all-claude." | BRIEF §5 | — |
| 2026-10-13 22:25:30Z (00:25 CEST 10-14) | "i digress on the hyprland parts, i m sorry. let s tick to sway window manager. less effort.." | REPORTED, wave1/01 R-A8 (codex `01a1370e` line 1802) | blur research parked; Sway-only smokes; `HYPRLAND_*` unsets in runtime-test are harmless leftovers |
| 2026-10-13 22:16:59Z | "we re doing functionality pull from quickshell NOT visuals or aesthetics whatsoever" | REPORTED, wave1/01 R-A7 | — |
| 2026-10-13 23:21:38Z | "i m not intersted in 'native advantage' . performance is not really the thing i m looking for here. 'supplies another renderer' is fine for something that' react plus generic compositor functionlaity..." | REPORTED, wave1/02 [1054] | bun wrapper startup (~100 ms per CLI call, §4.3) is acceptable |
| 2026-10-14 (README date) | "**Stopped at Tom's request: retain Sway as the window manager.**" (about the GPUI ext-background-effect patch) | `HS/pkgs/desktop-shell/patches/README.md:3` | no GPUI source build; the published binary is the product |
| standing (BRIEF §1) | "flat and opaque, hairlines not shadows, no blur, no frost, wallpaper is #000000 solid" | BRIEF §1 (summary of rulings) | `windowBackground: 'opaque'`, so blur isn't needed |
| standing (BRIEF §1) | "No cron/timers declared in dotfiles. No secrets in git. Fonts never in git (NAS requireFile)." | BRIEF §1; AGENTS.md "Scheduled work (Tom, 2026-09-30)" | HM units are session-bound, not timers; no credentials in the package |
| 2026-10-11 | "can't that be done on the strix side of things? since it's a much more powerful device" | `W/hosts/client/default.nix:58-59` | the client never builds; it is deployed from the strix (`deploy …#client`) |
| 2026-10-11 | (about `~/dotfiles` and `~/mecattaf` on the client) "i dnt need here" | `W/hosts/client/default.nix:95-96` | client has `rawDotfiles.inStore = true` (`:101`); HM units must name store paths, never a checkout |
| 2026-10-11 | "top and center not top right" | `W/home/vicinae.nix:115` (mako `anchor`) | the toast surface placement; it contradicts BRIEF §3.3 "top-right" (flagged in wave1/13) |
| 2026-10-12 | "make the font larger than 11 (12 or 14, need to decide, start at 12)" | `W/home/vicinae.nix:37` | launcher font 12, and an assert target if mirrored |
| 2026-09-16 incident (AGENTS.md) | "Tests and experiments that source shell-script fragments, clean runtime directories, or launch test compositors must run through `runtime-test -- <command> [args...]` … If bubblewrap is unavailable, stop that test rather than silently running it on live sockets." | `W/AGENTS.md:53-62`; Tom's private `agent-runtime-rules.md` | every smoke self-wraps or refuses (§5.6) |
| Tom's private rule | "Do not suppress unexpected coredumps or service failures. Do not restart Herdr or the whole user manager to repair a test incident" | `~/mecattaf/dotfiles/home/agent-runtime-rules.md` | smokes keep all logs; never touch live units |
| 2026-10-12 | "No Claude Desktop or ChatGPT apps and no Chrome --app launcher entries on any host" | `W/flake.nix:1259-1285` (assert) | the launcher's app provider must not add such desktop entries; the assert stays |

**R-5 (2026-09, `DECISIONS.md:741-746`)** says the client is a thin client ("compositor, kitty, the
clipboard bridge (cliphist, wl-clipboard), Chrome, the Duo hardware layer, PipeWire …").
INFERRED: a GPUIX shell replacing Vicinae and mako is in that "compositor" tier, so it belongs in
the client closure. Nothing in DECISIONS.md bars a bun runtime there (`grep -n bun DECISIONS.md` →
0 hits).

---

## 3. Inventory: packaging, wiring and test features

| Feature | What exactly | Where it lives today | keep / replace / new | Notes |
|---|---|---|---|---|
| npm builder | `buildNpmPackage` with `nodejs = nodejs_24` | `HS/pkgs/desktop-shell/default.nix:4-12`; `P21c/default.nix` | keep (pattern) | the only `buildNpmPackage` in either tree; `W/pkgs/substrate-apps` uses `pnpm_10.fetchDeps` + `stdenvNoCC` instead |
| Dependency pin | `package-lock.json` v3 + `npmDepsHash` (FOD `…-npm-deps`) | `HS/pkgs/desktop-shell/package-lock.json`; `P21c/package-lock.json` (140 entries) | keep | MEASURED FOD = 64 MB `_cacache` (it caches darwin/win32 `.node` tarballs too; npm installs only linux) |
| Exact version pins | `"@gpuix/native": "0.11.0"`, `"@gpuix/react": "0.11.0"`, `"react": "19.2.0"`, `"dbus-next": "0.10.2"`; dev `typescript 5.9.3`, `@types/bun 1.3.10`, `@types/react 19.2.0` | `P21c/package.json` | new | BRIEF §3.1 "pin both exact"; `@gpuix/react` brings `react-reconciler 0.33.0`, `scheduler 0.27.0`; `@gpuix/native` brings `zod 4.6.7`, `eventsource-parser 4.1.2` |
| Install scripts off | `npmFlags = [ "--ignore-scripts" ]` | both precedents | keep | `dbus-next` pulls optional `usocket` (node-gyp, `hasInstallScript`), 108 optional lock entries; with scripts off it is never compiled and dbus-next falls back to `net` (REPORTED L17: no Unix-FD passing used) |
| Typecheck in build | `npm run typecheck` = `tsc --noEmit` | precedents' `buildPhase` | keep | dev deps are present during build (custom `installPhase` replaces npm's prune) |
| Bundle | `bun build.ts` → `dist/main.js` (MEASURED 1,171,068 bytes for the toy) | `P21c/build.ts` | keep | externals `["@gpuix/native", "@gpuix/native/*", "usocket", "x11"]` |
| Bun 1.3 external quirk | desktop-shell externalised **only** the exact `@gpuix/native` because "Bun 1.3 loses the namespace binding for export-star of an external subpath when @gpuix/solid is loaded through a dynamic import" | `HS/pkgs/desktop-shell/build.ts:11-18`; wave1/03 L5 | replaced | with React 0.11 + `@gpuix/native/*` external the bundle renders (MEASURED); re-check if Solid ever returns |
| Pure tests in build | `doCheck = true; checkPhase = "bun test"` | precedents | keep + change | add the `LD_LIBRARY_PATH` net (§5.2), MEASURED necessary for any test that imports `@gpuix/*` |
| ELF fix | `autoPatchelfHook` + `buildInputs = [ stdenv.cc.cc.lib libxkbcommon libxcb ]` | `P21c`; desktop-shell had no `libxcb` (0.10.0 relied on wrapper LD path) | keep | MEASURED `0 dependencies could not be satisfied` |
| dlopen libs | `appendRunpaths = map (p: "${lib.getLib p}/lib") [ wayland vulkan-loader libGL ]` | `P21c/default.nix` | **new** (replaces wrapper LD path) | RUNPATH applies to the dlopen caller (the `.node`); `runtimeDependencies` only patches executables (MEASURED failure) |
| Wrapper | `makeWrapper ${bun}/bin/bun $out/bin/gpuix-shell --add-flags $out/lib/gpuix-shell/dist/main.js` | precedents | keep | desktop-shell also `--set DESKTOP_SHELL_EXECUTABLE` and `--prefix PATH` (hyprland glib wireplumber cliphist wl-clipboard) |
| Runtime node_modules | copy only `@gpuix/native`, `@gpuix/native-linux-x64-gnu`, `zod`, `eventsource-parser`; `rm -rf …/@gpuix/native/wasm` | `P21c/default.nix` installPhase | new | 213.2 vs 598.8 MiB (MEASURED). The copy list must track `build.ts` externals (§5.2, §6) |
| Install check | `--check-native`, `--check-dbus` from `$out` after fixup | `SP/nixpkg-probe-21d` (MEASURED pass) | new | desktop-shell had `--check-native` as a CLI mode only |
| Load-check derivation | `runCommand "gpuix-shell-load-check"` | store `yj0a6vh7…` | optional | redundant once installCheck exists |
| Overlay attr | `gpuix-shell = final.callPackage ../pkgs/gpuix-shell { };` | `HS/overlays/default.nix:5` (desktop-shell) | new | `W/overlays/default.nix:2-5` is where the sibling `callPackage`s sit |
| Flake package export | add `gpuix-shell` to `inherit (pkgs) …` | `HS/flake.nix:515`; `W/flake.nix:506-536` | new | gives `nix build .#gpuix-shell` |
| Flake check: build+tests | `gpuix-shell = pkgs.gpuix-shell;` | precedent `W/flake.nix:681` `music-acquire = pkgs.music-acquire;` | new | runs typecheck, bun test, installCheck |
| Flake check: theme fragments | each `themes/<n>/gpuix-shell.json` parsed by the built shell | none yet | new | `home/themes` is pure `{ lib }` (`W/home/themes/default.nix:11-12`) |
| Flake check: topology | `home-profiles` asserts on units, exclusivity, theme fragment | `HS/flake.nix:1233-1240` (desktop-shell asserts) | new | `W/flake.nix:1213-1229` hard-assert Vicinae+mako on the client; must become conditional |
| HM module | `home/gpuix-shell.nix`, option `programs.gpuixShell.enable`, units `WantedBy = sway-physical-session.target` | `HS/home/hyprland.nix:37-104` (desktop-shell units) | new | `useGlobalPkgs = true` (`W/flake.nix:380`) so `pkgs.gpuix-shell` is visible in HM |
| Vicinae/mako exclusivity | `programs.vicinae`, `services.mako` off when the shell is on | `W/home/vicinae.nix:10,24` (`enabled = osConfig.myDisplay.enable`) | replace | otherwise two `org.freedesktop.Notifications` owners |
| Theme fragment | `"gpuix-shell.json" = builtins.toJSON t;` in `render` | `W/home/themes/default.nix:281-290`; HS used `"desktop-shell.json"` (`HS/home/themes/default.nix:294`) | new | owned by the theme reader (17); the check here only consumes it |
| runtime-test `--render-node` | binds one validated `/dev/dri/renderD*`, never `card*`/input | `W/home/dot_local/bin/runtime-test` (uncommitted, copied) | keep | MEASURED shellcheck 0.11.0 clean; MEASURED `HS/tests/runtime-test/test_render_node.py` 4/4 OK against the identical script |
| render-node test | `tests/runtime-test/test_render_node.py` | only in `HS` | **missing in W** | copy it with the wrapper (§6) |
| Pure python tests | `tests/<area>/test_*.py`, stdlib `unittest`, hermetic | `W/tests/herdr/*`, `MS/tests/workspace-switcher/test_*.py` | keep (convention) | wired as `python3 ${./tests/…}` in a `runCommand` (`W/flake.nix:2422-2445`); MS adds `python3 -m unittest discover -s ${./tests/workspace-switcher} -p 'test_*.py'` |
| Compositor smoke | `tests/<area>/smoke*.py`, isolated headless Sway, evidence dir, `results.json` | `W/tests/sway-vicinae/smoke.py`, `MS/tests/workspace-switcher/smoke.py`, `HS/tests/hyprland/smoke.py`, `P21c/smoke_noicd.py` | keep (convention) | never in `nix flake check` (needs namespaces + GPU) |
| Dev loop | npm-installed tree + `NAPI_RS_NATIVE_LIBRARY_PATH` → patched store `.node` | `@gpuix/native/index.js:69-82` | new | MEASURED loads native + react with no `LD_LIBRARY_PATH` under bun 1.4.2 |
| Hash refresh | `lib.fakeHash` → build → paste `got:` | `W/pkgs/substrate-apps/default.nix:23-24,31-35` | keep | or `prefetch-npm-deps package-lock.json` (MEASURED equal) |
| GPUI blur patch | `ext_background_effect_manager_v1` for GPUI | `HS/pkgs/desktop-shell/patches/gpui-ext-background-effect.patch` + README | **dropped** | never compiled; Tom stopped it; Sway is the compositor |
| Patched 0.10.0 store path | `/nix/store/pwp11p3rnmwygrykblk3rr3331mw4k4h-desktop-shell-0.1.0` | gone (MEASURED `ls` → no such file) | dropped | it was autoPatchelf only (README: "patches the published native addon to Nix libraries … there is no source build of the GPUI fork here") |
| Lockfile of record (rev 2) | `package-lock.json` only; `bun.lock` deleted and git-ignored; dev trees via `npm ci --ignore-scripts` | scaffold has `bun.lock` only (`W/pkgs/gpuix-shell/bun.lock`) | **replace** | 5 entries already differ between the two (MEASURED); Nix reads only the npm lock (§5.10) |
| Exact pins (rev 2) | `zod 4.6.7` (= `@gpuix/native`'s), `@types/bun 1.3.13` (= `pkgs.bun`) | scaffold `package.json` has `^4`, `latest` | **replace** | MEASURED building as `SP/nixpkg-probe-21f` |
| Flake visibility pre-commit (rev 2) | `git add -N pkgs/gpuix-shell home/gpuix-shell.nix tests/gpuix-shell` | none | new | MEASURED on Nix 2.34.8 (§5.10); replaces the `--impure --expr` dev form once used |
| HM assertion (rev 2) | `assertions` in `home/gpuix-shell.nix`: no mako, no Vicinae when enabled | SCOPE S-012 asks for it | new | fires on activation/toplevel build; `home-profiles` stays the eval-time gate (§5.10) |
| Unit environment (rev 2) | login `PATH` + session vars imported by `modules/sway.nix:76-79`; `XDG_CURRENT_DESKTOP=sway-physical` | `modules/sway.nix:24-41,63,125` | keep | no wrapper PATH needed for mpv/playerctl/brightnessctl (§5.10); `wpctl` on the session PATH not re-checked in rev 2 |

---

## 4. Design values (numbers a builder needs)

### 4.1 Versions (MEASURED unless marked)

| Thing | Value | How measured |
|---|---|---|
| nixpkgs pin (`inputs.nixpkgs.rev`) | `e2587caef70cea85dd97d7daab492899902dbf5d` | `nix eval` of `f.inputs.nixpkgs.rev` |
| `pkgs.bun` (stable pin, host pkgs) | **1.3.13**, `/nix/store/fs2axbvhmim3y1dwzpf5mh56569h15df-bun-1.3.13` | `nix eval` `client.pkgs.bun` |
| `bun` in `inputs.nixpkgs-fresh` | **1.4.2**, `/nix/store/216mr46yy8xspaydgapjhf4a21y643ji-bun-1.4.2`, the same binary as the BRIEF's dev bun (`~/today/2026-10-14-convergence-soak/build/bun/bin/bun` symlinks to it) | `nix eval` + `readlink -f` |
| `pkgs.nodejs_24` | 24.18.0, `/nix/store/x98gls54ki3fmm2pv2cmi6z8mcda6glk-nodejs-24.18.0` | `nix eval` |
| wayland / vulkan-loader / libglvnd / libxkbcommon / libxcb | 1.26.0 / 1.4.350.0 / 1.7.0 / 1.13.2 / 1.17.0 | store names in the built RUNPATH |
| `vulkan-loader` ICD search | `-DSYSCONFDIR=/run/opengl-driver/share` (finds `/run/opengl-driver/share/vulkan/icd.d/*.json` with no env var) | `nix eval nixpkgs#vulkan-loader.cmakeFlags`; `pkgs/by-name/vu/vulkan-loader/package.nix:53` |
| Sway in smokes | `/nix/store/04g9x522ddd3hi77v013n97li9ccyrhd-sway-1.12` == `client.config.programs.sway.package` | `nix eval` |
| grim | hard-coded `7scglgqh…-grim-1.5.0` exists; the client's pkgs has `srpb3hbl…-grim-1.5.0` | `nix eval` |
| shellcheck | 0.11.0 | `nix shell --inputs-from . nixpkgs#shellcheck` |
| strix tools | `bwrap` 0.12.0, `dbus-run-session` on PATH, `grim` on PATH, `swaymsg` **not** on PATH, python 3.14.6 with PIL 12.3.0 and pytest 9.1.1 | `command -v`, imports |

### 4.2 Sizes (MEASURED)

| Item | Size |
|---|---|
| `gpuix-native.linux-x64-gnu.node` 0.11.0, as published | 52,449,896 B, sha256 `7a94e28f12944207d749299a3d7772fd179a954d95542e0ab13bffa90e27a60d`; lock integrity `sha512-WlDFnxKaKkw9NBhz2UAn7jXvhCvd/A6hYkxrJbtMLks5TRrjwxPpX2P0JQfppZvcQn13r2sivyQVdB1YX0hHTA==` |
| same after autoPatchelf + appendRunpaths | 52,465,080 B, sha256 `49093e57…ab622a` |
| `…-npm-deps` FOD | 64 MB (63 MB `_cacache`; largest blobs 17.7 MB + ~9.6–9.9 MB ×3 = the four platform binaries, INFERRED from sizes) |
| `npm ci` in sandbox | "added 136 packages … in 648ms" |
| toy package output (`P21c`) | 60 MB; closure **213.2 MiB** (bun alone 133.1 MiB) |
| copy-all + `npm prune` variant | 94 MB; closure **598.8 MiB** |
| runtime closure members (selective) | libunistring, libidn2, xgcc-libgcc, glibc, libxdmcp, libxau, libxcb, libx11, libffi, wayland, xkeyboard-config, libxml2, libxkbcommon, bash, bun, gcc-libgcc, libxext, libglvnd, vulkan-loader, gpuix-shell |

### 4.3 Timings (MEASURED on the strix, 32 CPUs)

| What | Time |
|---|---|
| `prefetch-npm-deps package-lock.json` (warm) | 1.6 s |
| toy `bun test` in sandbox | 6–8 ms (1 test); 48 ms for a test importing `@gpuix/react` |
| full toy build (FOD cached) | well under a minute per variant (four variants built 23:18–23:24 by the predecessor) |
| bare `bun` script start (bun 1.3.13, inside runtime-test) | 81 ms average of 5 |
| `gpuix-shell --check-native` (bundle + dlopen) | 102 ms average of 5 |
| `gpuix-shell --check-dbus` (bundle + bundled dbus-next) | 123 ms average of 5 |
| headless-Sway rail smoke, start to `results.json` | a few seconds (one `time.sleep(1)` + polls) |

Consequence (INFERRED): each Sway bind that runs `gpuix-shell <verb>` pays about 0.1 s on the
strix before its socket message is sent, more on the Zenbook. Per Tom's 10-13 ruling that is acceptable.
Part of that cost is the native addon, which every invocation loads (MEASURED, §5.1: the single
bundle hoists `@gpuix/native` to top-level static imports). If it ever matters, build a second,
independent entry point `dist/cli.js` (socket client only, no `@gpuix/*` import anywhere in its
graph) and point the wrapper at it. The daemons run `dist/main.js`.

### 4.4 Runtime facts the package depends on

- **Font discovery (MEASURED `strings`).** The binding embeds `fontdb` + `fontconfig_parser` and
  reads `FONTCONFIG_FILE`, `$XDG_CONFIG_HOME/fontconfig/fonts.conf`, `/etc/fonts/local.conf`,
  `/etc/fonts/fonts.conf`, falling back to `/usr/share/fonts/`, `/usr/local/share/fonts/`,
  `~/.fonts`, `~/.local/share/fonts`. On NixOS `/etc/fonts/fonts.conf` lists the `fonts.packages`
  dirs, so "Anthropic Sans", "Anthropic Serif" and "AnthropicMono Nerd Font" resolve with no
  `registerFont` and no fontconfig library. The Nix sandbox has no `/etc/fonts`, so nothing in
  `bun test` may depend on real glyph metrics.
- **Vulkan ICD.** The nixpkgs loader finds `/run/opengl-driver/share/vulkan/icd.d`
  (`hardware.graphics.enable = true` at `W/modules/common.nix:374`; the client adds
  `intel-media-driver` at `W/hosts/client/default.nix:232`). On the strix that dir holds 13 ICDs,
  including `lvp` (CPU) and `intel_icd`. MEASURED: the rail rendered with `VK_ICD_FILENAMES` unset
  inside `runtime-test --render-node /dev/dri/renderD128` (only one GPU visible there). Adapter
  choice on the Zenbook (Intel, live seat) is **UNVERIFIED** with the Nix build; REPORTED (wave1/03
  L16): a 0.10.0 Mail window ran on the client on 10-14 ("869.4M memory peak").
- **Loader fallbacks (MEASURED `index.js`).** `requireNative()` honours `NAPI_RS_NATIVE_LIBRARY_PATH`
  first (`@gpuix/native/index.js:69-82`), then `./gpuix-native.linux-x64-gnu.node`, then the
  `@gpuix/native-linux-x64-gnu` package. On failure it throws the misleading "Cannot find native
  binding. npm has a bug related to optional dependencies…" and puts the real `dlopen` errors in
  `error.cause`. **Always print `err.cause`** in `--check-native`.
- **Automation server (MEASURED `dist/runtime.js:21-26`).** `createNativeRenderer` enables the
  stdio automation server whenever `process.stdin` is not a TTY. Under systemd, stdin is
  `/dev/null`, so it is enabled in production. INFERRED harmless (EOF at once), but untested; see §6.
- **Test renderer (MEASURED).** `hasTestGpuixRenderer()` → `false`;
  `@gpuix/native/testing` `hasNativeTestRenderer` → `false`. Upstream: "Linux stays unavailable
  until GPUI ships its pending wgpu headless renderer" (`Downloads/gpuix/CHANGELOG.md:939`).
- **0.11.0 API present (MEASURED `index.d.ts`).** `registerFont(data: Buffer)` (lines 178, 386),
  `LayerShellOptions` (685; `exclusiveZone` 704, `keyboardInteractivity` 720), `windowBackground`
  (768), `layerShell` (791).

### 4.5 Geometry/colour values used by the measured probes (probe-only, not design rulings)

From `W/docs/gpuix-shell/evidence/rail-probe/rail.tsx` and `P21c/src/main.tsx`: rail `width 56`,
`height 900`, `paddingTop 12`, `gap 2`, slot `32×30`, `borderRadius 8`, `borderRightWidth 1`
`#373735`, background `#000000`, active slot `#171818`, text `#EAECF0`/`#818898`, Anthropic Sans
13, mono clock `#70B8FF` AnthropicMono Nerd Font 11; layer shell `namespace 'gpuix-shell-rail'`,
`layer 'top'`, `anchor ['left','top','bottom']`, `exclusiveZone 56`,
`keyboardInteractivity 'none'`, `windowBackground 'opaque'`, `focus false`. Smoke output
1440×900 `HEADLESS-1`, `bg #202020`; pixel (2,450) = `(0,0,0)` (rail), (200,450) = `(32,32,32)`
(wallpaper) → the rail painted and nothing else did.

---

## 5. Reusable code, data and the step-by-step recipe

### 5.0 Answering the specific questions

**Can `buildNpmPackage` fetch `@gpuix/native-linux-x64-gnu` 0.11.0 and autoPatchelf it?** Yes,
MEASURED (`P21c`, `nixpkg-probe-21d`). The lockfile entry is an ordinary tarball
(`"optional": true, "os": ["linux"], "cpu": ["x64"]`, `resolved`
`https://registry.npmjs.org/@gpuix/native-linux-x64-gnu/-/native-linux-x64-gnu-0.11.0.tgz`).
`fetchNpmDeps` caches all four platform tarballs. `npm ci` (run by `npmConfigHook`) installs only
the linux one. `autoPatchelfHook` walks `$out` recursively in `fixupPhase`, so the `.node` is
patched wherever `installPhase` copies it.

**How is `npmDepsHash` computed?** Two equivalent ways, both house-sanctioned:

```sh
# (a) direct, MEASURED tonight to equal the hash the build used
cd /home/tom/.wt/dotfiles/gpuix-shell/pkgs/gpuix-shell
nix shell --inputs-from /home/tom/.wt/dotfiles/gpuix-shell nixpkgs#prefetch-npm-deps \
  -c prefetch-npm-deps package-lock.json
# → sha256-…   paste into default.nix npmDepsHash

# (b) the substrate-apps way (W/pkgs/substrate-apps/default.nix:23-24, 31-35):
#     npmDepsHash = lib.fakeHash;  build;  copy the "got: sha256-…" line;  rebuild.
```

`--inputs-from` pins `nixpkgs` to the flake's lock, so the tool is the same one the build uses.

**Is network available at build time?** Only inside the fixed-output `npmDeps` derivation (FODs
may fetch; their output hash is checked). The main derivation is sandboxed offline: `npm ci`
reads `npm_config_cache` = the FOD (build log: "Setting npm_config_cache to
/nix/store/dh0nbvbd…-gpuix-shell-0.1.0-npm-deps"), and "Validating consistency between
/build/source/package-lock.json and …-npm-deps/package-lock.json" fails the build if the
committed lock drifted from the hashed one. Therefore:
- every dependency, transitive and optional, needs `resolved` + `integrity` in
  `package-lock.json` (lockfileVersion 3). No `git+`/`file:`/`link:` deps without extra work;
- `bun.lock`/`bun.lockb` are **not** read by Nix. If a builder runs `bun install`, `package.json`
  can change without `package-lock.json` changing, and the build breaks only at validation;
- tests and the build must not fetch anything (no Navidrome, no herdr, no D-Bus, no Wayland).

**How did the earlier package produce the patched 0.10.0 binding?** By autoPatchelf of the
published npm binary, nothing else. Evidence: `HS/pkgs/desktop-shell/README.md` "patches the
published native addon to Nix libraries … there is no source build of the GPUI fork here";
`patches/README.md` "It is not applied by the desktop shell package and does not modify the
shipped `@gpuix/native` npm addon"; `default.nix:12-15` `autoPatchelfHook`,
`buildInputs = [ stdenv.cc.cc.lib libxkbcommon ]`, wrapper `--prefix LD_LIBRARY_PATH` of ten
libs. The output `pwp11p3r…` has been garbage-collected (MEASURED). REPORTED sha256 of that
`.node`: `8fd95415…857fd` (wave1/03:277). `HS/design/gpuix-comparison/package-native.py:7-31`
reused it: it copied `@gpuix/native{,-linux-x64-gnu}` out of the store path and re-emitted the
wrapper's `LD_LIBRARY_PATH` in a `bundle/run` script with bun 1.4.2.

**Does the published 0.11.0 binary suffice?** Yes, MEASURED: patched only by Nix, it opens a
wlr-layer-shell surface with an exclusive zone on stock Sway 1.12. Tom wants flat and opaque
(no blur), and stock Sway does not do client blur anyway (INFERRED), so a GPUI source build or a
patch would add nothing today. If one is ever wanted, `NAPI_RS_NATIVE_LIBRARY_PATH` lets a
locally built `.node` replace the published one without touching the package (§5.7).

**Which `LD_LIBRARY_PATH` set?**

| Where | Set | Verdict |
|---|---|---|
| `HS/pkgs/desktop-shell/default.nix:38` (0.10.0) | `stdenv.cc.cc.lib libxkbcommon wayland vulkan-loader fontconfig freetype libGL xorg.libX11 xorg.libxcb openssl` (`xorg.*` names are deprecated in this nixpkgs, wave1/03 L18) | over-broad; leaks into children |
| `W/docs/gpuix-shell/evidence/rail-probe/smoke.py:16-19` (dev, bun 1.4.2) | glob `/nix/store/*-{libxkbcommon,wayland-1,vulkan-loader,fontconfig,freetype,libglvnd,libx11,libxcb,openssl,gcc-15}*/lib` | fine for a probe; fragile (every matching store version, GC-dependent) |
| `P21b` wrapper | `wayland vulkan-loader libGL` (+ RUNPATH has xcb/xkbcommon/libgcc) | works (MEASURED), but leaks into launched apps |
| **`P21c` / recommended** | **none.** RUNPATH = `libxcb:libxkbcommon:libgcc:wayland:vulkan-loader:libglvnd` | works (MEASURED twice tonight); no leak |
| `checkPhase` only | `lib.makeLibraryPath [ stdenv.cc.cc.lib libxkbcommon libxcb ]` | needed for import-only tests before fixup (MEASURED) |

Why the leak matters (INFERRED): the launcher spawns apps (Chrome, kitty, Nautilus). A shell
whose wrapper prepends Nix `libvulkan`/`libEGL`/`libwayland` passes them to every child. The live
session already carries `LD_LIBRARY_PATH=/nix/store/swvz04f3…-pipewire-1.6.8-jack/lib` (MEASURED
in this shell), and that must pass through unchanged. The launcher should hand children the
environment it received, minus anything it added itself, plus nothing.

### 5.1 Files of `pkgs/gpuix-shell/` (recipe; the PLAN's scaffold owner writes them)

`pkgs/gpuix-shell/package.json` (scripts as in both precedents; versions exact):

```json
{
  "name": "gpuix-shell",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "scripts": {
    "build": "bun build.ts",
    "test": "bun test",
    "typecheck": "tsc --noEmit"
  },
  "dependencies": {
    "@gpuix/native": "0.11.0",
    "@gpuix/react": "0.11.0",
    "dbus-next": "0.10.2",
    "react": "19.2.0"
  },
  "devDependencies": {
    "@types/bun": "1.3.10",
    "@types/react": "19.2.0",
    "typescript": "5.9.3"
  }
}
```

(Revision 2: superseded by the §5.10 version. That version adds `zod 4.6.7`, which the scaffold
uses, and pins `@types/bun 1.3.13` to match `pkgs.bun`.)

Generate the lock with **npm** from the pinned node (npm 11 ships with node 24.18), never with bun:

```sh
cd /home/tom/.wt/dotfiles/gpuix-shell/pkgs/gpuix-shell
nix shell --inputs-from /home/tom/.wt/dotfiles/gpuix-shell nixpkgs#nodejs_24 \
  -c npm install --package-lock-only --ignore-scripts
# then npm ci --ignore-scripts  to materialise node_modules for development
```

Every added dependency is: `npm install --save-exact --ignore-scripts <pkg>@<ver>`, then refresh
`npmDepsHash`. If the package has a native part, it must also join `build.ts` externals and the
`installPhase` copy list (§5.2).

`pkgs/gpuix-shell/tsconfig.json` (MEASURED working with typecheck in the sandbox):

```json
{"compilerOptions":{"target":"ES2022","module":"ESNext","moduleResolution":"bundler",
  "jsx":"react-jsx","jsxImportSource":"@gpuix/react","strict":true,"skipLibCheck":true,
  "noEmit":true,"types":["bun"]},
 "include":["src/**/*.ts","src/**/*.tsx","build.ts"]}
```

`pkgs/gpuix-shell/build.ts` (verbatim from `P21c`, MEASURED):

```ts
export {};
// Bundle everything except the N-API loader package (exact name and every subpath, so the
// loader's createRequire stays next to its platform package) and dbus-next's unbuilt optional
// native helpers (usocket; x11 autolaunch), which dbus-next requires inside try/catch.
const result = await Bun.build({
  entrypoints: ["./src/main.tsx"],
  target: "bun",
  outdir: "dist",
  external: ["@gpuix/native", "@gpuix/native/*", "usocket", "x11"],
});
if (!result.success) { console.error(result.logs); process.exit(1); }
```

Why `@gpuix/native/*` too: `@gpuix/react` 0.11.0 imports `@gpuix/native/host` (17 sites),
`/automation` (9), `/testing` (4), `/idle-gc` (3) and the root (9) (MEASURED `grep` of
`@gpuix/react/dist`). Keeping them all external gives one copy of the native module state.
Then `zod` and `eventsource-parser` (dependencies of `@gpuix/native`) must ship as files.

`src/main.tsx` must keep three side-effect-free modes that the package checks call
(desktop-shell precedent `HS/pkgs/desktop-shell/main.ts:1-27`; `P21c/src/main.tsx`):

```ts
const arg = process.argv[2] ?? "rail";
if (arg === "--check-native") {
  try {
    const native = await import("@gpuix/native");
    console.log(JSON.stringify({ ok: typeof native.GpuixRenderer === "function",
      exports: Object.keys(native).length, bun: Bun.version }));
    process.exit(0);
  } catch (error) {
    // napi masks the dlopen error; the real one is in error.cause.
    console.error(String((error as Error).message), (error as { cause?: unknown }).cause);
    process.exit(1);
  }
}
if (arg === "--check-dbus") {
  const dbus = await import("dbus-next");            // bundled; never connects
  console.log(JSON.stringify({ ok: typeof dbus.sessionBus === "function" }));
  process.exit(0);
}
if (arg === "--check-theme") {                       // used by checks.gpuix-shell-themes
  const { loadThemeFile } = await import("./theme/load");   // pure module, no @gpuix import
  loadThemeFile(process.argv[3]!);                   // throws on a missing role
  console.log(JSON.stringify({ ok: true }));
  process.exit(0);
}
// every other verb: dynamic import of the surface or the socket client
```

**Correction to the obvious idea: dynamic `import()` in `main.tsx` does not keep the addon out
of CLI verbs.** With one entry point and no code splitting, Bun.build inlines the dynamically
imported `@gpuix/react` graph and **hoists its external imports to top-level static `import`
statements** of `dist/main.js`. MEASURED in the built bundle
(`/nix/store/3rr5xk9c…/lib/gpuix-shell/dist/main.js`): line 23924
`import { GpuixRenderer } from "@gpuix/native";`, 23926 `… from "@gpuix/native/runtime"`, 25866
`import { GpuixRenderer as GpuixRenderer2, isTerminal } from "@gpuix/native";`, plus ten
`@gpuix/native/host|automation|cpu-throttle|idle-gc` imports. Only the explicit
`await import("@gpuix/native")` at 25895 stayed dynamic. ES modules evaluate static imports
first, so **every invocation dlopen()s the 52 MB addon**, `--check-dbus` and every socket-client
verb included. (That is harmless today and consistent with the 102/123 ms timings.) Two ways to
keep CLI verbs light, both INFERRED and untested:
- a second entry point in its own `Bun.build` call, `src/cli.ts` → `dist/cli.js`, whose import
  graph never reaches `@gpuix/*`; the wrapper runs `cli.js`, which talks to the socket or `exec`s
  `bun dist/main.js <surface>` for daemons; or
- `splitting: true` in `Bun.build`, which should put lazily imported modules (and their externals)
  in separate chunks. Check the output with
  `grep -n '^import .*@gpuix' dist/main.js` → expect no hits.

`pkgs/gpuix-shell/.gitignore`: today it is `node_modules/ dist/ .local-state/ *.err *.log bun.lockb`
(MEASURED). Add `result` and `bun.lock` (bun ≥1.2 writes the text `bun.lock`).

### 5.2 `pkgs/gpuix-shell/default.nix` (recommended; MEASURED as `SP/nixpkg-probe-21d/default.nix` with `withCheckLibs = true`)

```nix
{
  lib,
  buildNpmPackage,
  bun,
  nodejs_24,
  autoPatchelfHook,
  makeWrapper,
  stdenv,
  libxkbcommon,
  libxcb,
  wayland,
  vulkan-loader,
  libGL,
}:
# gpuix-shell: the Sway desktop shell (rail, launcher, notifications, OSD, …) on GPUIX 0.11.0.
# The published @gpuix/native-linux-x64-gnu .node is used as is; autoPatchelf points it at Nix
# libraries. Its NEEDED set is libxcb, libxkbcommon(-x11) and libgcc; it dlopen()s
# libwayland-client/-egl, libvulkan and libEGL, which appendRunpaths bakes into its RUNPATH so
# no LD_LIBRARY_PATH reaches the apps the launcher starts. Fonts come from /etc/fonts/fonts.conf
# (the binding parses it itself); Vulkan ICDs from /run/opengl-driver (the nixpkgs loader).
# Refresh npmDepsHash after any package-lock.json change: prefetch-npm-deps package-lock.json.
buildNpmPackage {
  pname = "gpuix-shell";
  version = "0.1.0";
  src = lib.cleanSourceWith {
    src = ./.;
    filter =
      path: _type:
      !(builtins.elem (baseNameOf path) [
        "node_modules"
        "dist"
        "result"
        "default.nix"
        ".local-state"
        "bun.lock"
        "bun.lockb"
      ])
      && !(lib.hasSuffix ".log" path)
      && !(lib.hasSuffix ".err" path);
  };
  nodejs = nodejs_24;
  npmDepsHash = "sha256-…"; # prefetch-npm-deps package-lock.json
  npmFlags = [ "--ignore-scripts" ]; # dbus-next's optional usocket would run node-gyp
  nativeBuildInputs = [
    bun
    autoPatchelfHook
    makeWrapper
  ];
  buildInputs = [
    stdenv.cc.cc.lib
    libxkbcommon
    libxcb
  ];
  # dlopen()ed by the binding (wgpu/ash, wayland-sys, khronos-egl). runtimeDependencies would
  # not do: autoPatchelf adds those to executables only, and this is a shared object.
  appendRunpaths = map (p: "${lib.getLib p}/lib") [
    wayland
    vulkan-loader
    libGL
  ];
  buildPhase = ''
    runHook preBuild
    npm run typecheck
    bun run build
    runHook postBuild
  '';
  doCheck = true;
  # Pure tests: no compositor, socket, bus or network. checkPhase runs before fixup, so the
  # .node is still unpatched; the NEEDED libs on LD_LIBRARY_PATH let a test import @gpuix/*
  # (never render: the Linux binding has no test renderer).
  checkPhase = ''
    runHook preCheck
    export LD_LIBRARY_PATH=${
      lib.makeLibraryPath [
        stdenv.cc.cc.lib
        libxkbcommon
        libxcb
      ]
    }
    bun test
    runHook postCheck
  '';
  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/gpuix-shell/node_modules/@gpuix $out/bin
    cp -r dist package.json $out/lib/gpuix-shell/
    # Runtime node_modules = build.ts's externals only: the loader, its Linux binding, its two
    # JS dependencies. Everything else is bundled in dist/main.js.
    cp -r node_modules/@gpuix/native node_modules/@gpuix/native-linux-x64-gnu \
      $out/lib/gpuix-shell/node_modules/@gpuix/
    cp -r node_modules/zod node_modules/eventsource-parser $out/lib/gpuix-shell/node_modules/
    rm -rf $out/lib/gpuix-shell/node_modules/@gpuix/native/wasm # browser-only build
    makeWrapper ${bun}/bin/bun $out/bin/gpuix-shell \
      --add-flags "$out/lib/gpuix-shell/dist/main.js" \
      --set GPUIX_SHELL_EXECUTABLE "$out/bin/gpuix-shell"
    runHook postInstall
  '';
  # After fixupPhase: the patched binding must load from $out with no library path.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    export HOME=$TMPDIR
    $out/bin/gpuix-shell --check-native | grep -q '"ok":true'
    $out/bin/gpuix-shell --check-dbus | grep -q '"ok":true'
    runHook postInstallCheck
  '';
  meta = {
    description = "GPUIX desktop shell for the Sway seat";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "gpuix-shell";
  };
}
```

Notes on the expression:
- `dontNpmPrune` (precedent line 16) does nothing once `installPhase` is custom, because npm's
  install hook is not used. It is omitted here (INFERRED from nixpkgs' npm hooks; the measured
  `P21c` set it and the custom install ignored it).
- The derivation env showed `strictDeps = 1` and `dontStrip = 1` set by `buildNpmPackage`
  (MEASURED `nix derivation show`), so `buildInputs` are host libs for autoPatchelf, and the `.node`
  is not stripped.
- `npm warn Unknown env config "nodedir"/"platform"/"arch"` appears in every phase. It is benign
  noise from nixpkgs' npm hooks (MEASURED, all four builds succeeded).
- Stable `pkgs.bun` (1.3.13) is the recommendation: every package measurement above used it.
  Developing on the soak's 1.4.2 is fine for speed, but run `bun test` and `bun build.ts` with
  1.3.13 before committing (§5.7). To move the package to 1.4.2, pass
  `bun = fresh.bun` from the "hot packages" overlay block (`W/flake.nix:313-331`, `fresh` at `:318`). That rides
  `nixpkgs-fresh` HEAD, so the bun version would change on every `nix flake update nixpkgs-fresh`.
  Assumption: stay on stable.
- Optional wrapper PATH (INFERRED): the desktop-shell precedent prefixed tool paths (`:37`). For
  gpuix-shell prefer in-process IPC (Sway socket, D-Bus) and the session PATH (wpctl must match the
  running WirePlumber, herdr must match the strix server). If fallbacks are wanted, use `--suffix
  PATH : ${lib.makeBinPath [ … ]}`, never `--prefix`, and never pin `herdr` (it is a flake input
  versioned with the strix server, AGENTS.md "Strix first whenever herdr is bumped").

### 5.3 Flake wiring (exact edits)

**(a) Overlay attr**: `W/overlays/default.nix`, after line 5 (`qwen-speech`):

```nix
  # The Sway desktop shell on GPUIX 0.11.0 (React). Installed by home/gpuix-shell.nix when
  # programs.gpuixShell.enable; `nix build .#gpuix-shell`. See pkgs/gpuix-shell/default.nix.
  gpuix-shell = final.callPackage ../pkgs/gpuix-shell { };
```

This reaches everything: `overlays.default` (`W/flake.nix:434-436`) is the first element of the
shared overlay list (`:298-299`), which top-level `pkgs` (`:334-337`) and every host
(`nixpkgs.overlays = overlays` at `:369` and `:400`) use. HM sees it through
`home-manager.useGlobalPkgs = true` (`:380`).

**(b) Package export**: `W/flake.nix:506-536`, add `gpuix-shell` inside `inherit (pkgs) …;`
(precedent `HS/flake.nix:515` put `desktop-shell` after `chrome-stream`):

```nix
            chrome-stream
            # `nix build .#gpuix-shell` — the Sway desktop shell (pkgs/gpuix-shell).
            gpuix-shell
            fleet-status
```

**(c) Checks**: inside `checks.${system} = {` (`W/flake.nix:583`), next to
`music-acquire = pkgs.music-acquire;` (`:681`):

```nix
        # gpuix-shell: tsc, the pure `bun test` suite (checkPhase) and the post-fixup native and
        # D-Bus load checks (installCheckPhase). No compositor runs here; the Sway smokes in
        # tests/gpuix-shell/ need runtime-test --render-node and a GPU, outside the sandbox.
        gpuix-shell = pkgs.gpuix-shell;

        # Every theme's gpuix-shell.json fragment parses with the shell's own loader, so a
        # role renamed in home/themes/*.nix fails here, not on the seat after `theme <name>`.
        gpuix-shell-themes =
          let
            themes = import ./home/themes { inherit (nixpkgs) lib; };
            fragment =
              n: pkgs.writeText "gpuix-shell-${n}.json" themes.fragments."themes/${n}/gpuix-shell.json";
          in
          pkgs.runCommand "gpuix-shell-themes" { } ''
            export HOME=$TMPDIR
            for f in ${fragment "noir"} ${fragment "claude-dark"} ${fragment "claude-light"}; do
              ${pkgs.gpuix-shell}/bin/gpuix-shell --check-theme "$f"
            done
            touch $out
          '';
```

(`themes.fragments` is the attrset `home/theme.nix:42` turns into `xdg.configFile.*.text`; the
import is pure `{ lib }`, `W/home/themes/default.nix:11-12,22`.) If the PLAN adds hermetic python
tests (for example a binds-to-verbs contract), wire them like `herdr-launchers`
(`W/flake.nix:2422-2445`):

```nix
        gpuix-shell-contract =
          pkgs.runCommand "gpuix-shell-contract"
            {
              nativeBuildInputs = [ pkgs.python3 ];
              GPUIX_SHELL = "${pkgs.gpuix-shell}/bin/gpuix-shell";
              SWAY_CONFIG = ./home/dot_config/sway;
            }
            ''
              export HOME=$TMPDIR
              python3 -m unittest discover -s ${./tests/gpuix-shell} -p 'test_*.py'
              touch "$out"
            '';
```

Caution: `discover -s ${./tests/gpuix-shell}` copies the whole directory into the store, smokes
included. That is harmless, because `discover` only imports `test_*.py`. Smokes must therefore be
named `smoke_*.py`, never `test_*.py`.

**(d) `home-profiles`** (`W/flake.nix:1074-1382`). The current hard asserts that break the moment
the client runs gpuix-shell instead of Vicinae and mako:

```
flake.nix:1213  assert clientHome.programs.vicinae.enable;
flake.nix:1214  assert clientHome.services.mako.enable;
flake.nix:1215  assert clientHome.systemd.user.services.mako.Service.Type == "dbus";
flake.nix:1216  assert clientHome.systemd.user.services.mako.Service.BusName == "org.freedesktop.Notifications";
flake.nix:1217-1219  mako ExecStart
flake.nix:1228  assert clientHome.programs.vicinae.settings.font.normal.family == "Anthropic Sans";
flake.nix:1229  assert clientHome.services.mako.settings.font == "Anthropic Sans 11";
```

Proposed replacement (INFERRED, modelled on `HS/flake.nix:1233-1240`): exactly one launcher and one
notification owner, each bound to the Sway session:

```nix
          # The client runs exactly one notification owner and one launcher: gpuix-shell
          # (experimental/gpuix-shell) or Vicinae + mako (main). Never both, never neither.
          assert clientHome.programs.gpuixShell.enable != clientHome.programs.vicinae.enable;
          assert clientHome.programs.gpuixShell.enable != clientHome.services.mako.enable;
          assert
            clientHome.programs.gpuixShell.enable
            -> (
              builtins.all (u: clientHome.systemd.user.services ? ${u}) [
                "gpuix-shell-notifications"
                "gpuix-shell-rail"
              ]
              && clientHome.systemd.user.services.gpuix-shell-notifications.Service.BusName
                == "org.freedesktop.Notifications"
              && clientHome.systemd.user.services.gpuix-shell-rail.Install.WantedBy
                == [ "sway-physical-session.target" ]
              && builtins.elem pkgs.gpuix-shell clientHome.home.packages
              && clientHome.xdg.configFile ? "themes/noir/gpuix-shell.json"
            );
          assert
            clientHome.programs.vicinae.enable
            -> (
              clientHome.services.mako.settings.font == "Anthropic Sans 11"
              && clientHome.programs.vicinae.settings.font.normal.family == "Anthropic Sans"
            );
          # Never on the headless strix.
          assert !strixHome.programs.gpuixShell.enable;
          assert !(builtins.any (n: nixpkgs.lib.hasPrefix "gpuix-shell" n)
            (builtins.attrNames strixHome.systemd.user.services));
```

(Nix `->` is logical implication. The unit names are placeholders until the PLAN fixes them.)

**(e) Other checks touched (MEASURED reading; INFERRED impact).**
- `deadnix` (`W/flake.nix:2390-2394`) scans `./flake.nix`, `./lib`, `./modules`, `./hosts`,
  `./overlays` and `./home` with `--fail --no-lambda-pattern-names` (revision 2 corrected this
  list, re-read 12:08). An unused `let` binding in `home/gpuix-shell.nix`, or in new
  `flake.nix`/`hosts/client` code, fails it. `./pkgs` is not scanned.
- `herdr-launchers` (`:2422-2445`) shellchecks `home/dot_local/bin/runtime-test`. The
  `--render-node` copy passes shellcheck 0.11.0 with zero findings (MEASURED).
- `tests/sway-vicinae/smoke.py:46-50` evaluates `h.programs.vicinae.settings` and
  `h.xdg.configFile."mako/config".text`. Both vanish when the client switches to gpuix-shell, so
  that smoke must be skipped or retargeted on this branch (INFERRED).
- `raw-dotfiles-guard` (`:1596-1620`) asserts `(homeOf "client").rawDotfiles.programs == [ ]`.
  Units must use `${pkgs.gpuix-shell}/bin/…`, never `%h/.local/bin/…`, or the strix guard list
  changes and the client loses its store-only property.

### 5.4 HM module skeleton (packaging-relevant parts only)

`home/gpuix-shell.nix`, imported in `W/home/home.nix:102-115` (alphabetical, before
`./harness-records.nix`). Gating copies `W/home/vicinae.nix:10,24`; unit shape copies mako
(`W/home/vicinae.nix:127-143`) and desktop-shell (`HS/home/hyprland.nix:38-104`):

```nix
{
  config,
  lib,
  pkgs,
  osConfig,
  ...
}:
let
  cfg = config.programs.gpuixShell;
  target = "sway-physical-session.target";
  unit = description: exec: extra: {
    Unit = {
      Description = description;
      ConditionEnvironment = "WAYLAND_DISPLAY";
      After = [ target ];
      PartOf = [ target ];
    };
    Service = {
      ExecStart = "${pkgs.gpuix-shell}/bin/gpuix-shell ${exec}";
      Restart = "on-failure";
      RestartSec = 2;
      Slice = "app.slice";
    } // extra;
    Install.WantedBy = [ target ];
  };
in
{
  options.programs.gpuixShell.enable = lib.mkEnableOption "the GPUIX desktop shell (replaces Vicinae and mako)";

  config = lib.mkIf (cfg.enable && osConfig.myDisplay.enable) {
    home.packages = [ pkgs.gpuix-shell pkgs.libnotify ];
    systemd.user.services.gpuix-shell-notifications = unit "GPUIX shell notifications, toasts and OSD" "notifications" {
      Type = "dbus";
      BusName = "org.freedesktop.Notifications";
    };
    systemd.user.services.gpuix-shell-rail = unit "GPUIX shell workspace rail" "rail" { };
  };
}
```

And in `W/home/vicinae.nix:10`: `enabled = osConfig.myDisplay.enable && !config.programs.gpuixShell.enable;`.
With that one line, mako, Vicinae and their desktop entries all switch off together. Caveat: the
`xdg.desktopEntries` in that file (herdr-picker etc., from `:149`) also live under that `mkIf`; the
gpuix-shell launcher reads `.desktop` files, so the entries may need to move out of the gate.

Where to turn it on (INFERRED): `W/hosts/client/default.nix`, beside `:101`
(`home-manager.users.tom.rawDotfiles.inStore = true;`), add
`home-manager.users.tom.programs.gpuixShell.enable = true;`. On main the line is absent or
`false`. That gives Tom a one-line rollback to Vicinae and mako.

Session environment: units started by `sway-physical-session.target` get `WAYLAND_DISPLAY DISPLAY
SWAYSOCK I3SOCK XDG_CURRENT_DESKTOP XDG_SESSION_TYPE XDG_SESSION_DESKTOP` from
`dbus-update-activation-environment --systemd` (`W/modules/sway.nix:15-23,125`), plus
`XDG_RUNTIME_DIR` from the user manager. That is enough for the socket at
`$XDG_RUNTIME_DIR/gpuix-shell/shell.sock`. No `VK_ICD_FILENAMES` is needed (§4.4). Sway binds that
call the CLI live in the raw `home/dot_config/sway/binds.conf:6,7,114` (`vicinae toggle`,
`vicinae cmd launch clipboard:history`). They are raw files, not Nix-gated, so the switch belongs
in the generated `sway-local.conf` or in a bind that tries `gpuix-shell` first (keys reader's call).

### 5.5 Test conventions (MEASURED reading of the three suites)

| Kind | Name | Framework | Runs where | Wired how |
|---|---|---|---|---|
| TS unit | `src/**/<name>.test.ts` beside the code (desktop-shell: `controller.test.ts`, `notifications.test.ts` at package root) | `bun:test` (`import { expect, test } from "bun:test"`) | Nix `checkPhase` + dev | automatic via `doCheck` |
| Python unit | `tests/<area>/test_<topic>.py` | stdlib `unittest` (`class X(unittest.TestCase)`, `if __name__ == '__main__': unittest.main()`); load scripts via `importlib.machinery.SourceFileLoader` from `HERDR_SCRIPTS` or `ROOT/home/dot_local/bin` (`MS/tests/workspace-switcher/test_switcher.py:17-21`) | `nix flake check` + dev | `python3 ${./tests/…/test_x.py}` or `python3 -m unittest discover -s ${./tests/…} -p 'test_*.py'` in a `runCommand` (`W/flake.nix:2442-2443`; `MS` adds the discover line) |
| Fixtures | `tests/<area>/fixtures/<host>-<hhmm>-<ipc>.json`, captured live and dated in the docstring | — | — | `MS/tests/workspace-switcher/fixtures/zenbook-0221-get_{workspaces,tree,outputs}.json` |
| Compositor smoke | `tests/<area>/smoke.py` (or `smoke_<surface>.py` per BRIEF §4) | plain python + `subprocess`; asserts; writes `results.json`; `print('evidence', dir)` | **only** `runtime-test [--render-node …]`; never a flake check | by hand; README states the command and the last evidence dir |
| Wrapper tests | `tests/runtime-test/test_*.py` | `unittest`; "Run on a host with unprivileged user namespaces, outside the Nix build sandbox." (`test_isolation.py:1`) | by hand | not in a flake check |

pytest is installed on the strix (9.1.1) but no suite uses it: every python test in the tree is
`unittest`, and the flake checks have only `pkgs.python3` (no pytest) in `nativeBuildInputs`.
Every smoke **refuses a live runtime** first:

```python
runtime = Path(os.environ['XDG_RUNTIME_DIR'])
assert not (runtime / 'bus').exists(), 'Refusing a live user runtime'          # MS smoke.py:75-77
assert not Path('/dev/input').exists(), 'Refusing a seat with real input devices'
assert not list(Path('/dev/dri').glob('card*')), 'Physical display devices exposed'  # HS smoke.py:73-76
```

Two self-wrapping styles exist (choose one per smoke):
- **Run-under style** (`MS/tests/workspace-switcher/smoke.py`, `P21c/smoke_noicd.py`): the
  operator types `runtime-test --render-node /dev/dri/renderD128 -- python3 tests/…/smoke_x.py`.
  The script only guards.
- **Self-wrapping style** (`W/tests/sway-vicinae/smoke.py:262-290`,
  `HS/tests/hyprland/smoke.py:261-288`): the outer `main()` builds a temp dir and metadata (via
  `nix eval` of the client flake), then re-executes itself `--inside DIR` through
  `ROOT/home/dot_local/bin/runtime-test --render-node <node> -- bwrap --die-with-parent
  --unshare-net --bind / / --dev-bind /dev /dev --tmpfs /tmp/.X11-unix --chmod 1777 /tmp/.X11-unix
  -- dbus-run-session --config-file DIR/dbus.conf -- python3 __file__ --inside DIR`. The inner
  `--dev-bind /dev /dev` carries the already-isolated `/dev` (with the one render node) into the
  inner bwrap; sway-vicinae's `--dev /dev` would drop it (fine there: pixman, no GPU). Use this
  style for the notifications smoke, which must own `org.freedesktop.Notifications` on a private
  bus. The private `dbus.conf` text is at `HS/tests/hyprland/smoke.py:66-68`.

### 5.6 Smoke template (merge of the MEASURED Nix rail smoke and the HS wrapper)

`tests/gpuix-shell/smoke_rail.py`. The inner part is `P21c/smoke_noicd.py` (MEASURED tonight:
`{"ok": true, "workspace_rect": {"x": 56, "y": 0, "width": 1384, "height": 900}, …}`, evidence
`/tmp/gpuix-nix-rail-onr01fae`):

```python
#!/usr/bin/env python3
"""The Nix-built gpuix-shell rail on a private headless Sway (gles2, one render node).

    nix build .#gpuix-shell            # or the --impure --expr form in tests/gpuix-shell/README.md
    python3 tests/gpuix-shell/smoke_rail.py --shell result/bin/gpuix-shell

The script wraps itself in this checkout's runtime-test (the installed ~/.local/bin copy may
lack --render-node). No LD_LIBRARY_PATH and no VK_ICD_FILENAMES: the package's RUNPATH and the
nixpkgs Vulkan loader must suffice. Evidence is kept under /tmp/gpuix-shell-smoke-rail-*.
"""
import argparse, json, os, subprocess, sys, tempfile, time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RUNTIME_TEST = ROOT / 'home/dot_local/bin/runtime-test'


def flake_paths():
    # The client's own Sway/grim, not hard-coded store hashes that rot at the next pin bump.
    expr = (f'let f = builtins.getFlake {json.dumps(str(ROOT))}; c = f.nixosConfigurations.client; '
            'in { sway = c.config.programs.sway.package.outPath; grim = c.pkgs.grim.outPath; }')
    out = subprocess.run(['nix', 'eval', '--impure', '--json', '--expr', expr],
                         capture_output=True, text=True, check=True, timeout=300).stdout
    return json.loads(out)


def wait(fn, label, n=200):
    for _ in range(n):
        v = fn()
        if v:
            return v
        time.sleep(.1)
    raise AssertionError(label)


def inside(directory, shell):
    meta = json.loads((directory / 'metadata.json').read_text())
    runtime = Path(os.environ['XDG_RUNTIME_DIR'])
    assert not (runtime / 'bus').exists(), 'Refusing a live user runtime'
    assert not Path('/dev/input').exists(), 'Refusing real input devices'
    assert not list(Path('/dev/dri').glob('card*')), 'Physical display devices exposed'
    sway, swaymsg, grim = (f"{meta['sway']}/bin/sway", f"{meta['sway']}/bin/swaymsg", f"{meta['grim']}/bin/grim")
    (directory / 'sway.conf').write_text(
        'output HEADLESS-1 mode 1440x900 bg #202020 solid_color\nxwayland disable\nseat seat0 fallback true\n')
    env = {k: v for k, v in os.environ.items() if not k.startswith('HERDR_') and k not in ('LD_LIBRARY_PATH', 'VK_ICD_FILENAMES')}
    env.update(WLR_BACKENDS='headless', WLR_HEADLESS_OUTPUTS='1', WLR_RENDERER='gles2',
               WLR_RENDER_DRM_DEVICE=os.environ['TEST_RENDER_NODE'], WLR_LIBINPUT_NO_DEVICES='1',
               SWAY_DISABLE_SD_NOTIFY='1', XDG_CURRENT_DESKTOP='sway',
               DBUS_SYSTEM_BUS_ADDRESS='unix:path=/nonexistent-test-system-bus')
    log = (directory / 'sway.log').open('w')
    compositor = subprocess.Popen([sway, '--unsupported-gpu', '-c', str(directory / 'sway.conf')],
                                  stdout=log, stderr=subprocess.STDOUT, env=env)
    app, result = None, {'ok': False}
    try:
        env['SWAYSOCK'] = str(wait(lambda: next(iter(runtime.glob('sway-ipc*.sock')), None), 'sway ipc'))
        env['WAYLAND_DISPLAY'] = wait(lambda: next((p.name for p in runtime.glob('wayland-*') if p.is_socket()), None), 'wayland')
        app = subprocess.Popen([str(shell), 'rail'], stdout=(directory / 'app.log').open('w'),
                               stderr=subprocess.STDOUT, env=env)

        def zone():
            if app.poll() is not None:
                raise AssertionError(f'rail exited {app.returncode}\n' + (directory / 'app.log').read_text())
            ws = json.loads(subprocess.run([swaymsg, '-r', '-t', 'get_workspaces'], capture_output=True, text=True, env=env).stdout)
            return ws[0]['rect'] if ws and ws[0]['rect']['x'] == 56 else None

        rect = wait(zone, 'exclusive zone 56 never reserved')
        time.sleep(1)
        subprocess.run([grim, '-t', 'ppm', '-o', 'HEADLESS-1', str(directory / 'shot.ppm')], check=True, env=env)
        head, size, _, px = (directory / 'shot.ppm').read_bytes().split(b'\n', 3)
        w, h = map(int, size.split())
        pixel = lambda x, y: tuple(px[(y * w + x) * 3:(y * w + x) * 3 + 3])
        result = {'ok': True, 'workspace_rect': rect, 'size': [w, h],
                  'rail_px_2_450': pixel(2, 450), 'wallpaper_px_200_450': pixel(200, 450)}
        assert result['wallpaper_px_200_450'] == (32, 32, 32), result
    finally:
        if app and app.poll() is None:
            app.terminate(); app.wait(timeout=5)
        compositor.terminate(); compositor.wait(timeout=5)
        (directory / 'results.json').write_text(json.dumps(result, indent=2, default=list))
    print(json.dumps(result, default=list), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--shell', type=Path, required=False)
    parser.add_argument('--render-node', default='/dev/dri/renderD128')
    parser.add_argument('--inside', type=Path, help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.inside:
        return inside(args.inside, args.shell)
    if not args.shell or not args.shell.is_file():
        parser.error('--shell must name the built gpuix-shell executable')
    if not RUNTIME_TEST.is_file():
        raise SystemExit('runtime-test is required; refusing an unisolated compositor test')
    directory = Path(tempfile.mkdtemp(prefix='gpuix-shell-smoke-rail-'))
    (directory / 'metadata.json').write_text(json.dumps(flake_paths()))
    print(f'Isolated test evidence: {directory}', flush=True)
    env = {k: v for k, v in os.environ.items() if not k.startswith('HERDR_')}
    env['TEST_RENDER_NODE'] = args.render_node
    subprocess.run([str(RUNTIME_TEST), '--render-node', args.render_node, '--', sys.executable, __file__,
                    '--inside', str(directory), '--shell', str(args.shell.resolve())],
                   env=env, check=True, timeout=240)


if __name__ == '__main__':
    main()
```

Per-surface additions (INFERRED, from BRIEF §3.3 geometry):
- launcher: `layer overlay`, keyboard exclusive. Drive keys with `wtype -s` (persistent virtual
  keyboard, `MS` README) or with `@gpuix/native/automation` (`launch`, `getByTestId`, `fill`,
  `press('escape')`; REPORTED working on 10-14, wave1/03 L14). Read the surface from
  `swaymsg -t get_outputs`/grim.
- notifications: self-wrapping style with `dbus-run-session`, then `notify-send` from libnotify
  (`pkgs.libnotify`, already in client `home.packages`, `W/home/vicinae.nix:145`) and
  `gdbus call … GetServerInformation`. Assert the toast pixels.
- two outputs (eDP-1/eDP-2 mirror): `WLR_HEADLESS_OUTPUTS=2` and `output HEADLESS-1 …`,
  `HEADLESS-2 …` as in `MS/tests/workspace-switcher/smoke.py`.

### 5.7 Development loop (MEASURED pieces marked)

```sh
W=/home/tom/.wt/dotfiles/gpuix-shell
cd $W/pkgs/gpuix-shell
# toolchain identical to the package (bun 1.3.13, node 24.18.0):
nix shell --inputs-from $W nixpkgs#bun nixpkgs#nodejs_24
npm ci --ignore-scripts                       # node_modules from package-lock.json
bun test                                      # pure suite
npx tsc --noEmit && bun build.ts              # what buildPhase runs

# Build the package BEFORE the files are git-tracked. A git flake sees only tracked/staged
# files, and pkgs/gpuix-shell/ is untracked (?? in git status), so `nix build .#gpuix-shell`
# would not see it. This form copies the directory from disk and uses the pinned nixpkgs
# (MEASURED: same bun/node store paths as the hosts):
nix build --impure -L --no-link --print-out-paths --expr \
  'let f = builtins.getFlake "/home/tom/.wt/dotfiles/gpuix-shell";
       p = import f.inputs.nixpkgs { system = "x86_64-linux"; };
   in p.callPackage /home/tom/.wt/dotfiles/gpuix-shell/pkgs/gpuix-shell { }'

# Run surfaces from the dev tree without LD_LIBRARY_PATH soup: point the npm-installed loader
# at the store's patched binding (MEASURED: loads @gpuix/native + @gpuix/react under bun 1.4.2).
OUT=$(nix build … --print-out-paths)          # the command above
export NAPI_RS_NATIVE_LIBRARY_PATH=$OUT/lib/gpuix-shell/node_modules/@gpuix/native-linux-x64-gnu/gpuix-native.linux-x64-gnu.node
$W/home/dot_local/bin/runtime-test --render-node /dev/dri/renderD128 -- \
  python3 $W/tests/gpuix-shell/smoke_rail.py --shell $OUT/bin/gpuix-shell   # or a dev wrapper script

# After the integrator stages the files (git add pkgs/gpuix-shell home/gpuix-shell.nix …):
nix build .#gpuix-shell -L
nix build .#checks.x86_64-linux.gpuix-shell .#checks.x86_64-linux.gpuix-shell-themes .#checks.x86_64-linux.home-profiles -L
nix flake check --offline --no-build          # the house's evaluation gate (DECISIONS.md:933, 1047)
nix build .#nixosConfigurations.client.config.system.build.toplevel --no-link   # the client closure, built on the strix
```

Deploying is not tonight's job (BRIEF §3.10). For MORNING.md: the client never builds
(`W/hosts/client/default.nix:56-60`). The strix builds and pushes with
`deploy github:mecattaf/dotfiles/<rev>#client` (deploy-rs node `client`, `W/flake.nix:475-495`).
For an unmerged branch, the same with a local flake ref (`deploy /home/tom/.wt/dotfiles/gpuix-shell#client`,
INFERRED: deploy-rs accepts any flake ref). The NAS nightly build list includes `client`
(`W/hosts/nas/update-center.nix:62`) but builds main, so the branch is not pre-cached in Attic.

### 5.8 Data a builder can lift

| Data | Path |
|---|---|
| A working `package.json` + `package-lock.json` (React 0.11.0 set, 140 entries, hash `sha256-PLas/KzhWF2NvFGTX5Z3OfINGIeGrrVSGse4kAJKI0k=`) | `P21c/{package.json,package-lock.json}` (copy, then `npm install` new deps on top) |
| Working `build.ts`, `tsconfig.json`, `default.nix` | `P21c/`, `SP/nixpkg-probe-21d/default.nix` (with installCheck + check libs) |
| Passing smoke (no LD path, no ICD) | `P21c/smoke_noicd.py`; same with ICD: `SP/nixpkg-probe-21b/smoke_nix_rail.py` |
| Build logs (phase order, autoPatchelf output) | `SP/nixpkg-probe-21{,b,c}/build.log`, `SP/nixpkg-probe-21d/build-{true,false}.log` |
| Built outputs to smoke against without rebuilding | `/nix/store/6szgr9gvc17g18hxyy9npbnwzpv9g2x0-gpuix-shell-0.1.0` (RUNPATH variant), `/nix/store/3rr5xk9cip3sm2w020jlfz92lrk10hqk-gpuix-shell-0.1.0` (with installCheck); GC roots: none, so they can disappear |
| Patched binding for `NAPI_RS_NATIVE_LIBRARY_PATH` | `<out>/lib/gpuix-shell/node_modules/@gpuix/native-linux-x64-gnu/gpuix-native.linux-x64-gnu.node` |
| Render-node wrapper test to copy into W | `HS/tests/runtime-test/test_render_node.py` (and `HS/tests/runtime-test/test_isolation.py`'s namespace-inode PID check + `HYPRLAND_*` asserts, diff in §5.9) |
| Desktop-shell unit set (dbus-typed notifications daemon + bar + cliphist watchers) | `HS/home/hyprland.nix:37-104` |
| Desktop-shell flake asserts | `git -C HS diff main -- flake.nix` hunks `@@ -1201,15 +1202,18 @@` (seat equalities) and `@@ -1225,6 +1229,15 @@` (desktop-shell absent, vicinae/mako on the Sway target, `themes/noir/desktop-shell.json`) |
| Self-wrapping smoke with private dbus | `HS/tests/hyprland/smoke.py:66-68` (dbus.conf), `:261-288` (wrapper) |
| Live Zenbook Sway fixtures | `MS/tests/workspace-switcher/fixtures/zenbook-0221-*.json` |
| **Revision 2:** the real scaffold + stub entry, with lock, hash and log | `SP/nixpkg-probe-21e/{package.json,package-lock.json,default.nix,build.ts,build.log,src/}` (hash `sha256-BeNnBlxF…xC4=`) |
| **Revision 2:** the same with the recommended pins (copy-ready lock if `package.json` matches §5.10 exactly) | `SP/nixpkg-probe-21f/{package.json,package-lock.json,default.nix,build.log}` (hash `sha256-r6hZuPIv97JGR1F1oaeePCcUG60BWDn0Xt3+qOQwp5o=`); outputs `/nix/store/02hr9b35…`, `/nix/store/snpkm2wy…` (no GC roots) |

### 5.9 What I ran tonight (all MEASURED; nothing touched the live seat)

| # | Command (abridged) | Result |
|---|---|---|
| 1 | `nix derivation show` on every `*gpuix-shell*` drv in the store | the table in §1.2 |
| 2 | `readelf -d` / `strings` / `patchelf --print-rpath` on the built `.node` | NEEDED/dlopen sets (§0.3); RUNPATH per variant |
| 3 | `nix eval` of `client.pkgs.{bun,nodejs_24,vulkan-loader,…}` and `nixpkgs-fresh` bun | §4.1 |
| 4 | `runtime-test -- <out>/bin/gpuix-shell --check-native` / `--check-dbus` for `6szgr9…` and `bnsarhrr…`, `LD_LIBRARY_PATH` unset | `{"ok":true,"exports":7,"bun":"1.3.13"}` / `{"ok":true}` |
| 5 | `prefetch-npm-deps P21c/package-lock.json` | `sha256-PLas/KzhWF2NvFGTX5Z3OfINGIeGrrVSGse4kAJKI0k=` |
| 6 | bun import of the **unpatched** npm `.node` with no library path, in runtime-test | `Cannot find native binding…` (reproduces the sandbox) |
| 7 | `hasTestGpuixRenderer()` / `hasNativeTestRenderer` on 0.11.0 | `false` / `false` |
| 8 | `runtime-test --render-node /dev/dri/renderD128 -- python3 P21c/smoke_noicd.py /nix/store/6szgr9…/bin/gpuix-shell` (`LD_LIBRARY_PATH` unset) | `{"ok": true, "workspace_rect": {"x": 56, "y": 0, "width": 1384, "height": 900}, "size": [1440, 900], "rail_px_2_450": [0,0,0], "bg_px_200_450": [32,32,32]}`; app log `[gpuix] created native window` / `[gpuix] mount complete`; evidence `/tmp/gpuix-nix-rail-onr01fae` |
| 9 | `shellcheck home/dot_local/bin/runtime-test` (0.11.0) | rc 0, no findings |
| 10 | `python3 HS/tests/runtime-test/test_render_node.py -v` (script byte-identical to W's) | 4/4 OK |
| 11 | `NAPI_RS_NATIVE_LIBRARY_PATH=<patched .node>` + npm-installed `probe011` tree, bun 1.4.2, no LD path | `loaded native 7 react render function` |
| 12 | timing loops (§4.3) | 81 / 102 / 123 ms |
| 13 | `nix build --impure --expr … callPackage SP/nixpkg-probe-21d/default.nix { withCheckLibs = true; }` | rc 0; `✓ @gpuix/react imports in the build sandbox [48.00ms]`, `2 pass 0 fail`; `installCheckPhase` after `fixupPhase` passed both checks; out `3rr5xk9c…`, 213.2 MiB |
| 14 | same with `withCheckLibs = false` | rc 1; `error: libxcb.so.1: cannot open shared object file` under "Cannot find native binding" |
| 15 | `nix eval` of `client.config.programs.sway.package` | `04g9x522…-sway-1.12` (= the smokes' hard-coded path) |
| 16 | `grep -n '^import \|from "@gpuix/native' dist/main.js` of `3rr5xk9c…` | static top-level `@gpuix/native` imports at 23924/25866 etc.; only 25895 dynamic (§5.1 correction) |
| 17 | `nix-store --query --roots` on `6szgr9…` and `3rr5xk9c…` | no roots |

Scratch written by me: `SP/nixpkg-probe-21d/` (sources, `default.nix`, two build logs), two
store outputs (`3rr5xk9c…`, plus the failed build's leftovers), `/tmp/gpuix-nix-rail-onr01fae/`,
and three throwaway `.mjs` probes under `/tmp/claude-1000/` (deleted). The `runtime-test` and
`test_render_node.py` runs created only their own private trees. One side effect: `nix-store --query --roots`
(used to confirm the toy outputs have **no** GC roots) removed three *dangling*
`/nix/var/nix/gcroots/auto/*` links that pointed at deleted `/tmp/nix-build-*/result` symlinks.
Nix does that on any roots query, and nothing live was referenced.

Revision 2 scratch: `SP/nixpkg-probe-21e/`, `SP/nixpkg-probe-21f/`, `SP/flake-ita-probe/` (a
two-file git repo for the `add -N` test) and `SP/r21/` (this revision's edit script), plus two
store outputs. Nothing in `W` was written except this file. No smoke and no `runtime-test` run
in revision 2.

### 5.10 Revision 2: the real scaffold under Nix (MEASURED 2026-10-21 12:02–12:10 CEST)

State of `W/pkgs/gpuix-shell` at 12:01. The music chain wrote it 23:41–23:48 and nothing has
changed since (MEASURED `stat`):

| File | State | Nix consequence |
|---|---|---|
| `package.json` | `version 0.0.0`; deps `@gpuix/native 0.11.0`, `@gpuix/react 0.11.0`, `dbus-next 0.10.2`, `react 19.2.0`, **`zod ^4`**; dev **`@types/bun latest`**, `@types/react 19.2.0`, `typescript 5.9.3`; scripts `typecheck`, `test` only | no `build` script, so `bun run build` fails in buildPhase; the two loose ranges contradict BRIEF §3.1 "pin both exact" |
| `bun.lock` | bun's text lockfile (`lockfileVersion 2`), 135 packages; resolves `zod 4.6.7`, `@types/bun 1.4.3` | Nix ignores it; `buildNpmPackage` needs `package-lock.json` |
| `package-lock.json` | **absent** | `npmDepsHash` cannot be computed and the build cannot start |
| `tsconfig.json` | ES2023, `moduleResolution bundler`, `jsxImportSource @gpuix/react`, `allowImportingTsExtensions`, `types ["bun"]`, include `src/**` | works under the Nix `tsc` (MEASURED); `build.ts` is outside `include`, so it is not typechecked (fine) |
| `.gitignore` | `node_modules/ dist/ .local-state/ *.err *.log bun.lockb` | add `result` and `bun.lock` |
| `node_modules/` | written by bun install: 128 top-level dirs, including usocket's node-gyp tree; usocket is unbuilt (no `build/`) | kept out of the store by the `src` filter and by git |
| `src/` | `music/{config,errors,format,format.test,types}.ts`, `music/subsonic/{api,map,types}.ts`, `launcher/provider.ts` (1,305 lines); imports only `react` (type-only), `node:os`, `node:path`, `bun:test` | pure; `bun test` passes in the sandbox (no network, no bus) |
| `build.ts`, `src/main.tsx`, `default.nix` | **absent** | write them from §5.1–§5.2 |

Probe `SP/nixpkg-probe-21e` = the scaffold as is, plus `"build": "bun build.ts"`, plus
`21d`'s `build.ts`, `src/main.tsx`, `src/slots{,.test}.ts` and `default.nix`:

| Step | Command | Result |
|---|---|---|
| lock | `nix shell --inputs-from W nixpkgs#nodejs_24 -c npm install --package-lock-only --ignore-scripts` (npm 11.16.0) | 5.1 s; `lockfileVersion 3`, 141 entries; **every** non-root entry has `resolved` + `integrity`; `zod 4.6.7`, `@types/bun 1.4.3` |
| bun.lock vs package-lock | parse both and compare versions | 5 mismatches, all in usocket's optional node-gyp subtree (`ansi-regex`, `emoji-regex`, `is-fullwidth-code-point`, `string-width`, `strip-ansi`); every runtime package agrees |
| hash | `prefetch-npm-deps package-lock.json` | `sha256-BeNnBlxFoDlMy0wy9Fwtzx2zUJEPYdG9BlniFML1xC4=` |
| build | `nix build --impure -L --expr '… callPackage SP/nixpkg-probe-21e/default.nix { }'` | rc 0, `/nix/store/02hr9b35px5z7r2h0ppygvyq0jjjd1s8-gpuix-shell-0.1.0`; `added 137 packages … in 651ms`; `> tsc --noEmit` clean; `bun test v1.3.13 (bf2e2cec)` **6 pass 0 fail** (`format > durations / counts / truncation / display rules / position extrapolation` + `nine slots`); `auto-patchelf: 0 dependencies could not be satisfied`; installCheck (`--check-native`, `--check-dbus`) passed |
| output | `nix path-info -Sh`, `patchelf --print-rpath` | closure 213.2 MiB; runtime `node_modules` = `@gpuix/{native,native-linux-x64-gnu}`, `zod`, `eventsource-parser`; `.node` RUNPATH `libxcb-1.17.0 : libxkbcommon-1.13.2 : gcc-15.3.0-libgcc : wayland-1.26.0 : vulkan-loader-1.4.350.0 : libglvnd-1.7.0`; wrapper = `exec …bun-1.3.13/bin/bun …/dist/main.js "$@"` with `GPUIX_SHELL_EXECUTABLE` set |

Probe `SP/nixpkg-probe-21f` = 21e with the pins recommended below:

| Step | Result |
|---|---|
| lock | 140 entries; `@types/bun 1.3.13`, `bun-types 1.3.13` |
| hash | `sha256-r6hZuPIv97JGR1F1oaeePCcUG60BWDn0Xt3+qOQwp5o=` (valid only for exactly that `package.json` + `SP/nixpkg-probe-21f/package-lock.json`) |
| build | rc 0, `/nix/store/snpkm2wynicw8csav5vws276c03kj3lp-gpuix-shell-0.1.0`; tsc clean against bun 1.3.13 types; 6 pass 0 fail; autoPatchelf 0 unsatisfied; installCheck passed |

The wave-3 packet names the soak npm (`~/today/2026-10-14-convergence-soak/build/node/bin/npm`).
It is the same npm 11.16.0 on node 24.18.0 (MEASURED), so a lock written with it is equivalent.

**Recommended `pkgs/gpuix-shell/package.json`** (MEASURED building as `21f`; it supersedes the
§5.1 version, which predates the scaffold's zod dependency):

```json
{
  "name": "gpuix-shell",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "scripts": {
    "build": "bun build.ts",
    "test": "bun test",
    "typecheck": "tsc --noEmit"
  },
  "dependencies": {
    "@gpuix/native": "0.11.0",
    "@gpuix/react": "0.11.0",
    "dbus-next": "0.10.2",
    "react": "19.2.0",
    "zod": "4.6.7"
  },
  "devDependencies": {
    "@types/bun": "1.3.13",
    "@types/react": "19.2.0",
    "typescript": "5.9.3"
  }
}
```

Why these two pins:
- `zod 4.6.7` is the version `@gpuix/native` already pulls (its range is `^4.4.3`), so npm keeps
  one copy in `node_modules`. If `src/` imports zod (SCOPE S-009 config schemas), Bun.build bundles
  it into `dist/main.js`, and `@gpuix/native` keeps its own runtime copy. Two copies at runtime is
  harmless and expected (INFERRED).
- `@types/bun 1.3.13` matches `pkgs.bun` 1.3.13, the runtime in the wrapper and in checkPhase.
  With `latest` (1.4.3 today), `tsc` would accept a 1.4-only API that then fails at runtime on
  1.3.13. If the package moves to `fresh.bun` 1.4.x (§5.2 notes), move this pin with it.

**Lockfile policy (recommended; the integrator should log it in ASSUMPTIONS.md, since this reader writes only this file):** commit only
`package-lock.json`. Delete `bun.lock`, add it to `.gitignore`, and install dev trees with
`npm ci --ignore-scripts`. Bun is the runtime, test runner and bundler, not the package manager.
Two lockfiles drift silently (5 entries already differ), and Nix reads only one. If a builder
still prefers `bun install`, they must regenerate `package-lock.json` with npm and redo the hash
after every dependency change. Otherwise the build fails at "Validating consistency between
/build/source/package-lock.json and …-npm-deps/package-lock.json", or `npm ci` rejects a
`package.json` that no longer matches the lock.

**Making the flake see the files without committing (MEASURED, Nix 2.34.8).** In a scratch git
flake (`SP/flake-ita-probe`), an untracked file was invisible (`builtins.pathExists` →
`false`). After `git add -N <file>` it was `true`. Intent-to-add puts an index entry with no
content staged and makes no commit. So the packaging builder can work on the real flake ref:

```sh
git -C /home/tom/.wt/dotfiles/gpuix-shell add -N \
  pkgs/gpuix-shell home/gpuix-shell.nix tests/gpuix-shell      # ignored node_modules/ stays out
nix build /home/tom/.wt/dotfiles/gpuix-shell#gpuix-shell -L
nix build /home/tom/.wt/dotfiles/gpuix-shell#checks.x86_64-linux.gpuix-shell -L
```

The integrator's later `git add` + commit is unaffected, and `git reset <path>` undoes an `-N`
entry. For a dirty tree, Nix reads working-tree contents, so edits made after `add -N` are seen
without re-adding. A brand-new file still needs its own `add -N` (INFERRED from the probe).

**SCOPE S-012 correction.** S-012 says "`--check-native` / `--check-dbus` / `--check-theme`
self-tests in checkPhase". In `buildNpmPackage` the order is build → **check** → install →
**fixup (autoPatchelf)** → **installCheck** (MEASURED: the log order above, and revision 1 §5.9
#13–14). In checkPhase the `.node` is still unpatched and `$out` does not exist. So:
- `bun test` (pure tests, plus import-only tests behind the three-lib `LD_LIBRARY_PATH` net) goes in `checkPhase`;
- `--check-native` and `--check-dbus` (the *installed* wrapper, no library path) go in `installCheckPhase`;
- `--check-theme` over the three rendered fragments goes in the separate
  `checks.gpuix-shell-themes` (§5.3c), because the fragments come from `home/themes/*.nix`,
  outside the package source.

**S-012's "HM evaluation fails if `services.mako.enable` is also true"**, as a module assertion
in `home/gpuix-shell.nix`. The form is INFERRED. HM assertions fire when the activation package
or the system toplevel is built, not on a plain `nix eval` of one option:

```nix
  config = lib.mkIf (cfg.enable && osConfig.myDisplay.enable) {
    assertions = [
      {
        assertion = !config.services.mako.enable && !config.programs.vicinae.enable;
        message = "programs.gpuixShell replaces mako and Vicinae (it owns org.freedesktop.Notifications and the launcher); never enable both.";
      }
    ];
    # … home.packages and the units as in §5.4
  };
```

With `enabled = osConfig.myDisplay.enable && !config.programs.gpuixShell.enable;` at
`home/vicinae.nix:10`, the assertion holds automatically. It catches a later hand edit that
turns mako back on. The evaluation-time gate stays the `home-profiles` asserts (§5.3d).

**Runtime PATH for the units (MEASURED reading).** `modules/sway.nix:24-41` puts `PATH` (plus
`SHELL`, `XDG_DATA_DIRS` and every session variable) in `loginVars`. The session script pushes the
ones present into the user manager with `dbus-update-activation-environment --systemd`
(`modules/sway.nix:76-79`) before it starts `sway-physical-session.target` (`:125`). Units bound
to that target therefore see Tom's login PATH, which carries the all-hosts `home.packages` of
`home/home.nix:405-531` (mpv at `:476`): `mpv`, `playerctl`, `brightnessctl`, `wl-clipboard`, `cliphist`, `wtype`,
`grim`, `slurp`, `pamixer`. Consequences:
- the wrapper needs no `--prefix PATH` (revision 1 §5.2 stands);
- the music player finds `mpv` through `GPUIX_SHELL_MPV || "mpv"` (`src/music/config.ts:20,89`).
  Pinning it with `--set-default GPUIX_SHELL_MPV ${lib.getExe mpv}` is optional. It could put a
  second mpv in the closure if versions differ (INFERRED). Recommendation: rely on PATH;
- the session exports `XDG_CURRENT_DESKTOP=sway-physical` (`modules/sway.nix:63`), not `sway`.
  The launcher's `.desktop` `OnlyShowIn`/`NotShowIn` filtering, and any smoke that sets
  `XDG_CURRENT_DESKTOP=sway` (the §5.6 template does), must allow for that (INFERRED).

**bun test hygiene for the Nix check.** In checkPhase, `bun test` collects every
`*.test.ts|*_test.ts|*.spec.ts|*_spec.ts` under the package source. The sandbox has no network,
no session bus, no `XDG_RUNTIME_DIR` and no `/etc/fonts`. MUSIC.md plans `NAVIDROME_LIVE=1`
fixture recording and `NAVIDROME_FAKE=1` GUI smokes. A live test must either live outside
`pkgs/gpuix-shell` (in `tests/gpuix-shell/`) or be wrapped in
`test.skipIf(!process.env.NAVIDROME_LIVE)`, because in the sandbox it fails rather than skips.
Tests take paths from an injected `env`, as `src/music/config.ts:2-3` already does, and never fall
back to `/run/user/<uid>`.

### 5.11 Step-by-step for the packaging builder (wave-3 packet `002-nix-package.md`), in order

1. In `W/pkgs/gpuix-shell`: apply the §5.10 `package.json`. Write `build.ts` (§5.1) and
   `src/main.tsx` with the three `--check-*` modes (§5.1); surfaces load by dynamic import.
2. `rm bun.lock`; append `bun.lock` and `result` to `.gitignore`.
3. Generate the lock: `nix shell --inputs-from W nixpkgs#nodejs_24 -c npm install
   --package-lock-only --ignore-scripts` (or the soak npm 11.16.0, equivalent). Then run
   `npm ci --ignore-scripts` for a dev tree. If `package.json` matches §5.10 byte for byte,
   `SP/nixpkg-probe-21f/package-lock.json` and its hash can be copied instead.
4. Compute the hash: `nix shell --inputs-from W nixpkgs#prefetch-npm-deps -c prefetch-npm-deps
   package-lock.json`, and paste it into `default.nix` (§5.2).
5. `git -C W add -N pkgs/gpuix-shell`, and later `home/gpuix-shell.nix` and `tests/gpuix-shell`.
6. Add the overlay line (§5.3a) and the package export (§5.3b), then `nix build W#gpuix-shell -L`.
   Expect this log order: `> tsc --noEmit` → `bun test v1.3.13` → `auto-patchelf: 0 dependencies
   could not be satisfied` → `Running phase: installCheckPhase`.
7. Add the `"gpuix-shell.json"` fragment to `home/themes/default.nix` `render` (schema from the
   theme reader / DESIGN.md §tokens). Then add `checks.gpuix-shell` and
   `checks.gpuix-shell-themes` (§5.3c) and run
   `nix build W#checks.x86_64-linux.gpuix-shell W#checks.x86_64-linux.gpuix-shell-themes -L`.
8. Write `home/gpuix-shell.nix` (§5.4 plus the §5.10 assertion; units at least for `rail` and
   `notifications`, named `gpuix-shell-<surface>` per SCOPE S-001/S-013). Import it in
   `home/home.nix:102-115`; set `enabled = … && !config.programs.gpuixShell.enable` at
   `home/vicinae.nix:10`; enable it in `hosts/client/default.nix` next to `:101`.
9. Rewrite the `home-profiles` asserts at `flake.nix:1213-1229` (§5.3d). Then check
   `nix eval W#nixosConfigurations.client.config.home-manager.users.tom.programs.gpuixShell.enable`
   → `true`, the same for `strix` → `false`, and run
   `nix build W#checks.x86_64-linux.home-profiles -L`.
10. Run `nix build W#checks.x86_64-linux.deadnix` (it scans `flake.nix lib modules hosts overlays
    home`) and `nix fmt` on the new `.nix` files. Use `nix flake check --no-build` as the
    evaluation gate. Build the client toplevel last, because it is the slow one:
    `nix build W#nixosConfigurations.client.config.system.build.toplevel --no-link`.
11. Run the smokes (`tests/gpuix-shell/smoke_*.py`, §5.6) against `result/bin/gpuix-shell`, only
    through `W/home/dot_local/bin/runtime-test --render-node /dev/dri/renderD128`.
12. Record each measured step in `docs/gpuix-shell/BUILD-LOG.md`, and say "untested" for the rest.

For every later dependency: `npm install --save-exact --ignore-scripts <pkg>@<ver>`, then step 4.
If the dependency is native or loads files at runtime, also add it to the `build.ts` `external`
list and the `installPhase` copy list, and give it an import line in a `--check-*` mode.

---

## 6. Gaps, unknowns and risks

1. **The real package is only a partial scaffold** (revision 2). It has music + launcher
   contracts, but no entry point, no npm lock and no `default.nix` (§5.10). A scratch copy with a
   stub `main.tsx` was MEASURED building under Nix. The real entry point, the surfaces, OpenUI
   `lang-core` and the remaining music modules (mpv player, MPRIS over dbus-next, art cache) will
   grow the dependency set and the bundle, and none of them has been built under Nix yet.
2. **The runtime-node_modules copy list is hand-kept.** If a new dependency must stay external
   (native addon, worker file, dynamic `require` of a data path), both `build.ts` `external` and
   `installPhase` must change, or the install check fails only if `--check-*` touches that code.
   Mitigation (INFERRED): extend `installCheckPhase` to import each external, or derive the copy
   list from `build.ts` in a tiny script.
3. **Bundled dbus-next is only import-tested** (`--check-dbus`). A real `sessionBus()` round trip
   from the bundle (owning `org.freedesktop.Notifications`, UPower/NM/BlueZ/MPRIS calls) is
   **UNVERIFIED**. REPORTED for 10-14: dbus-next was *external* then, and its real-bus test was
   opt-in and not reported run (wave1/03 §3.3.6). It needs the self-wrapping notifications smoke
   with `dbus-run-session`.
4. **Zenbook GPU path with the Nix build is UNVERIFIED.** All renders tonight are the strix's
   Radeon `renderD128` in a nested headless Sway. Intel adapter choice among 13 ICDs (including
   CPU `lvp`), HiDPI scale 2 on two panels, and live-seat focus are untested. If wgpu picks the
   wrong adapter, pin `VK_ICD_FILENAMES=/run/opengl-driver/share/vulkan/icd.d/intel_icd.x86_64.json`
   in the units (INFERRED fix).
5. **Two bun versions.** Package and tests run on bun 1.3.13; the BRIEF's dev bun and the
   orchestrator's rail probe use 1.4.2. `Bun.build` behaviour differs between minors (the
   desktop-shell external quirk was a 1.3 bug). Assumption: build and test on 1.3.13 before commit.
   Revision 2: the scaffold's `@types/bun latest` = 1.4.3 widens the gap at type level. Pin
   `1.3.13` (§5.10, MEASURED building).
6. **Untracked files are invisible to the flake.** `nix build .#gpuix-shell` and `nix flake check`
   see `pkgs/gpuix-shell`, `home/gpuix-shell.nix` and `tests/gpuix-shell` only after `git add`. Use
   the `--expr` form until the integrator stages them (§5.7). Revision 2: `git add -N` is enough,
   with no content staged and no commit (MEASURED, §5.10).
7. **`home-profiles` will fail** as soon as the client enables the shell (`W/flake.nix:1213-1229`
   are hard asserts), and `tests/sway-vicinae/smoke.py` will fail to evaluate. Both need the
   conditional forms in §5.3(d).
8. **The installed runtime-test lacks `--render-node`.** `~/.local/bin/runtime-test` →
   `~/mecattaf/dotfiles/home/dot_local/bin/runtime-test` (main), 0 hits for `render-node`
   (MEASURED). Tom's private rule says to use `~/.local/bin/runtime-test`; GPU smokes cannot until
   the branch merges and the strix switches. They must call `ROOT/home/dot_local/bin/runtime-test`.
   That copy is the same bubblewrap isolation with one more device, so the rule's intent holds.
9. **`tests/runtime-test/test_render_node.py` and the improved `test_isolation.py` are not in W.**
   The wrapper was copied without its test. Copy both from `HS/tests/runtime-test/` (diff:
   PID-namespace inode instead of a numeric PID, plus `HYPRLAND_*` unset asserts).
10. **The automation stdio server is on under systemd** (stdin is not a TTY; `dist/runtime.js:21`).
    Harmless is INFERRED; no one has tested whether it changes event handling or CPU. Check one
    unit's behaviour with `StandardInput=null` (the default) in the first live soak.
11. **Memory per process.** REPORTED 869.4 M cgroup peak for one 0.10.0 Mail window on the client
    (wave1/03 L16). BRIEF §3.2 plans seven processes. Each runs a bun runtime plus a GPUI thread.
    Measure RSS per surface in the smokes (`/proc/<pid>/status` VmRSS) before committing to that.
12. **The npm-deps FOD carries all four platform binaries** (≈40 MB of darwin/win32 tarballs,
    INFERRED from blob sizes). This is a cost, not a fault. Trimming it means editing the lockfile
    by hand, which `npm` undoes, so leave it.
13. **CLI latency, and the addon loads on every invocation.** ~0.1 s per call on the strix (§4.3),
    more on the Zenbook (UNMEASURED). The single bundle hoists `@gpuix/native` to static imports
    (MEASURED, §5.1), so even `gpuix-shell launcher` (a socket message) maps the 52 MB addon.
    Acceptable per Tom 10-13; a separate `dist/cli.js` entry (or `splitting: true`) is the fix if
    needed.
14. **No D-Bus activation file.** With mako's package gone, nothing activates a notification server
    by D-Bus if the shell's unit is down. libnotify's `notify-send` then fails instead of starting
    mako. Optionally ship `share/dbus-1/services/org.freedesktop.Notifications.service` with
    `SystemdService=gpuix-shell-notifications.service` (INFERRED; mako's HM unit is `Type=dbus` the
    same way).
15. **Old evidence is GC-able.** The 0.10.0 store path is gone; the four toy outputs above have no
    GC roots either. Hashes and RUNPATHs are recorded here so nobody needs them.
16. **`deadnix` covers `flake.nix`, `lib/`, `modules/`, `hosts/`, `overlays/` and `home/`**
    (scope corrected in revision 2). An unused `let` in `home/gpuix-shell.nix` fails
    `checks.deadnix` (`W/flake.nix:2390-2394`). `pkgs/` is not covered; `statix`/`nixfmt` are
    devShell tools only, not checks. Run `nix fmt` on new `.nix` files for house style (formatter
    = `pkgs.nixfmt`, `W/flake.nix:567`).
17. **Toast anchor contradiction** (Tom 2026-10-11 "top and center not top right" vs BRIEF §3.3
    "top-right"). This is not packaging, but a `home-profiles` assert or smoke pixel test would
    encode one of them; the design reader/ASSUMPTIONS must pick first. Revision 2: DESIGN.md:247
    now encodes `"anchor": "top-right"`, and KEYS.md:526 logs the contradiction as open. A
    `home-profiles` assert should therefore not pin the anchor until Tom rules.
18. **Smoke file naming conflict** (revision 2). `BOUNDARY.md:181,308` names the harness
    `tests/native-compositor.py` (from wave1/14), while SCOPE S-011 and BRIEF §4 name
    `tests/gpuix-shell/smoke_<surface>.py`. Recommendation: SCOPE's names. They keep `test_*.py`
    free for hermetic `unittest discover` in a flake check (§5.3c), and `smoke_*.py` out of it.
19. **SCOPE S-012 puts the native self-tests in checkPhase**, which fails, because the binding is
    unpatched before fixup (MEASURED revision 1 §5.9 #14). Use installCheckPhase (§5.10). Whoever
    edits SCOPE.md should fix the row; this reader does not edit SCOPE.md.
20. **`XDG_CURRENT_DESKTOP` is `sway-physical` on the seat** (`modules/sway.nix:63`) but `sway`
    in every smoke template. Desktop-entry filtering in the launcher could pass the smoke and
    differ live (INFERRED; no test).
21. **No live test may sit in `bun test`'s path** inside `pkgs/gpuix-shell` unless it is skipped
    by an env guard (§5.10). Nothing enforces this yet. A grep check (`NAVIDROME_LIVE` and
    `fetch(` only in `skipIf` blocks) is an INFERRED option and is not proposed as a flake check.
