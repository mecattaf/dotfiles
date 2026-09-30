# Anthropic fonts: the NAS side and the bootstrap

The operations runbook. What lives on the NAS M.2, how the three tarballs are built and
why each rule is load-bearing, how `update-center-seed` roots them, the ordered bootstrap
with its two switches, and what to do when it breaks.

Companion pages: [`README.md`](README.md) for what is installed,
[`anthropic-suite.md`](anthropic-suite.md) for the measurements,
[`../../pkgs/fontbuilder/README.md`](../../pkgs/fontbuilder/README.md) for the press.

---

## 1. NAS layout

```
/mnt/fast/fonts/anthropic/                          0755 root:root
/mnt/fast/fonts/anthropic/README.md                 0644 root:root
/mnt/fast/fonts/anthropic/SHA256SUMS                0444 root:root
/mnt/fast/fonts/anthropic/anthropic-mono-nerd-fonts.tar.zst   0444 root:root
/mnt/fast/fonts/anthropic/anthropic-ui-fonts.tar.zst          0444 root:root
/mnt/fast/fonts/anthropic/anthropic-webfonts.tar.zst          0444 root:root
```

This reproduces `apple/` exactly, which was reconnoitred read-only: `apple/README.md` is
`-rw-r--r--` (0644) while `SHA256SUMS` and both `*.tar.zst` are `-r--r--r--` (0444), and
the directory is 0755. `SHA256SUMS` is plain `sha256sum` output, two spaces, bare
filenames, one line per tarball.

**Do not use `chmod 444 <dir>/*`.** It would make `README.md` 0444 and diverge from
`apple/`, which keeps its README writable so it can be regenerated in place.

Reference sizes in the sibling directory, for scale: `sf-pro-fonts.tar.zst` is 134,568,961
bytes and `sfmono-liga-fonts.tar.zst` is 3,093,475 bytes. Ours:

| tarball | top-level dirs | bytes | sha256 |
|---|---|---|---|
| `anthropic-mono-nerd-fonts.tar.zst` | `truetype/` | 2571132 | `df043254517d186e6107caedae706436182c29d3e69aaedae031825b0a030fdc` |
| `anthropic-ui-fonts.tar.zst` | `truetype/` | 726204 | `070d34426a6eab50dd8dd3ae19cf847a52af86adb03d0a4f0d5d1d0de4393c77` |
| `anthropic-webfonts.tar.zst` | `css/`, `woff2/` | 830195 | `8da31eca13b2c55bce504567256462d579ccdbee6b8fe713fc33feb65ef40239` |

Three tarballs, not five. `sf-pro-fonts.tar.zst` already proves one archive may carry
several families. Every basename is dot-free before `.tar.zst` and unique against `tally`,
`tally-b`, `tally-lake`, `sf-pro-fonts` and `sfmono-liga-fonts` in the flat
`/var/lib/update-center/seeds` namespace.

Operational facts that shape everything below:

- `/mnt/fast` is **not** NFS- or SMB-exported. `ssh` as root is the only path.
- The tarballs are **not substitutable from attic** (narinfo 404 for both existing ones)
  while the **built outputs are**. That asymmetry is the whole reason for the local seed.
- update-center's `ExecStopPost` runs `nix-store --gc` on the NAS; the last run freed 43.0
  GiB. A seed without a GC root does not survive it.
- Attic retention is one month, last-accessed, so the packages must stay in a real host
  closure. They do: they are in `modules/common.nix`.

### The generated README

`fontbuilder --package` writes the NAS `README.md` and it is scp'd. **It is not in git.**
It follows `apple/README.md`'s six-part shape:

1. an H1;
2. the dated bytes paragraph with the `requireFile` and no-download statement;
3. a `| file | family | consumer |` table;
4. an `Origins:` paragraph naming the **14 source files with digests** plus every donor
   with store path, revision and licence;
5. the `update-center-seed` nightly paragraph;
6. the manual recovery line, then the closing rule verbatim: *"Never modify or rename
   these files; a replacement means a new sha256 in dotfiles."*

The `Origins:` half is threaded from `manifest.py` into `package.write_readme()`. The
prototype read `$FONTBUILDER_ORIGINS` and fell back to a bare pointer at `manifest.json`,
which would have shipped the NAS README without its provenance half. Check that paragraph
is populated before uploading.

---

## 2. Tarball construction

```bash
set -euo pipefail                      # LOAD-BEARING, see the --pax-option note
export SOURCE_DATE_EPOCH=$EPOCH        # governs head INSIDE each font, not the archive
cd "$STAGE/<root>" && chmod 0444 */* && chmod 0555 */
tar --format=gnu --sort=name --numeric-owner --owner=0 --group=0 --mtime=@0 \
    -cf - truetype | zstd -19 -T1 -q -o "$OUT/anthropic-mono-nerd-fonts.tar.zst" -f
# webfonts tarball, arguments in alphabetical order:
tar --format=gnu --sort=name --numeric-owner --owner=0 --group=0 --mtime=@0 \
    -cf - css woff2 | zstd -19 -T1 -q -o "$OUT/anthropic-webfonts.tar.zst" -f
( cd "$OUT" && sha256sum anthropic-mono-nerd-fonts.tar.zst anthropic-ui-fonts.tar.zst \
                         anthropic-webfonts.tar.zst > SHA256SUMS )
```

Every flag earns its place, and each one has a measured trap behind it.

| rule | why, measured |
|---|---|
| `--format=gnu`, never `--pax-option` | GNU tar 1.35 with `--pax-option` on a gnu-format archive exits **2** and writes **zero** bytes. The 13-byte artifact people report is **zstd's empty-frame overhead** (`: \| zstd -19` gives 13 B, `28b5 2ffd 24…`), reachable only when tar's exit status is discarded. With `set -o pipefail` the pipeline exits 2, and in `package.py` the first `subprocess.run(..., check=True)` raises before any count is reached. |
| `--mtime=@0`, unconditionally | Both existing `apple/` archives carry `1970-01-01` entry times. `SOURCE_DATE_EPOCH` and the archive clock are two different clocks: the former governs `head.created/modified` inside each font, the archive takes `@0`. |
| three tarballs from **three** stage roots | A single-root mapping emitted two **byte-identical** archives (measured `d28f658f…` twice in one `SHA256SUMS`, each containing the mono **and** the ui faces). The packager maps `mono`, `ui` and `web` to separate stage roots, with cwd at `stage/<root>` so published entry names stay bare `truetype/…`, and asserts the three digests are **pairwise distinct**. |
| a per-tarball **file** count minimum | The real failure the count catches is an empty or under-populated stage directory: tar then exits 0 with just `truetype/`, zstd makes a valid **66-byte** tarball, and `zstd -lv` shows the same fingerprint as a good one. That failure is invisible to every other check. Count files, not entries (`[n for n in names if not n.endswith("/")]`), with minimums 12 / 5 / 8. A `min_entries=1` default called with no override is vacuous for the only case it can catch. |
| `-T1`, and **no `--long`** | `-T1` is what makes zstd byte-reproducible. `--long=27` buys 8% (2,350,653 B) but changes the frame's Window Size line and raises the decompressor's memory requirement, breaking shape parity with `apple/*.tar.zst`. |
| stream into zstd, never `zstd -o` from a file | Streaming reproduces the apple fingerprint: `zstd -lv` shows Frames 1, DictID 0, Check XXH64, Window 8.00 MiB and **no Decompressed Size line**. Confirmed on the real 12-face archive. |
| bare top-level dir, no `./` entry | `zstd -dc … \| tar -tvf -` must show `dr-xr-xr-x 0/0` for directories, `-r--r--r-- 0/0` for files and `1970-01-01` times. Verified live against `sf-pro-fonts.tar.zst`. `sfmono-liga` is the older `./`-rooted form and is not the model. |
| no interior dot in any basename | `update-center-seed` derives the GC-root name with `${f%%.*}`, which strips at the **first** dot. |
| `requireFile`'s `name` equals the NAS basename | `nix-store --add-fixed sha256` names the store path from the basename. |

**Size, measured and not extrapolated.** All 12 final faces are 32,760,340 bytes of TTF,
tar 32,778,240 bytes, and **2,558,889 bytes (2.44 MiB) at `zstd -19 -T1`**, ratio 12.81x,
about one second. Expect 2.4 to 2.7 MB. The final number is 2571132.

**Never extrapolate tarball size from fewer than about four faces.** A two-face probe
measures only 3.5x because cross-face redundancy needs several faces inside zstd's 8 MiB
window. That is how an earlier estimate of 5 to 9 MB came about; it was wrong by a factor
of 2.5.

One more hazard in the packager itself: `harden()` chmods the stage to 0555/0444, after
which `rm -rf` of that tree fails with `Permission denied`, so the second repro tree and
every rebuild into an existing out-dir abort. Either chmod back after the tar stream is
written, or tar from a throwaway `copytree` in `$TMPDIR`.

---

## 3. The seed refactor

`home/update-center-seed.nix` roots each vendor tarball in the NAS store so the nightly
build finds it. The change is from bare basenames under one hardcoded directory to full
paths, because since this suite there are two vendor directories on the M.2.

**Before:**

```nix
  fontArchives = [
    "sf-pro-fonts.tar.zst"
    "sfmono-liga-fonts.tar.zst"
  ];
```
```bash
      for f in ${lib.escapeShellArgs fontArchives}; do
        pairs+=("''${f%%.*}=/mnt/fast/fonts/apple/$f")
      done
```

**After:**

```nix
  fontArchives = [
    "/mnt/fast/fonts/apple/sf-pro-fonts.tar.zst"
    "/mnt/fast/fonts/apple/sfmono-liga-fonts.tar.zst"
    "/mnt/fast/fonts/anthropic/anthropic-mono-nerd-fonts.tar.zst"
    "/mnt/fast/fonts/anthropic/anthropic-ui-fonts.tar.zst"
    "/mnt/fast/fonts/anthropic/anthropic-webfonts.tar.zst"
  ];
  fontRootNames = map (p: lib.head (lib.splitString "." (baseNameOf p))) fontArchives;
  checkedFontArchives =
    lib.throwIf (lib.length (lib.unique fontRootNames) != lib.length fontRootNames)
      "update-center-seed: font archive basenames collide once stripped at the first dot: ${toString fontRootNames}"
      (lib.throwIf (lib.any (n: n == "") fontRootNames)
        "update-center-seed: a font archive basename yields an empty or nested GC-root name"
        fontArchives);
```
```bash
      for f in ${lib.escapeShellArgs checkedFontArchives}; do
        b="''${f##*/}"; n="''${b%%.*}"
        for m in ''${names[@]+"''${names[@]}"}; do
          if [ "$m" = "$n" ]; then
            log "FAILED: font archive $b would take the GC-root name '$n', already claimed by locked node $m" >&2
            exit 1
          fi
        done
        pairs+=("$n=$f")
      done
```

It produces exactly five flat pairs: `sf-pro-fonts`, `sfmono-liga-fonts`,
`anthropic-mono-nerd-fonts`, `anthropic-ui-fonts`, `anthropic-webfonts`, each mapped to
its full path. The directory is carried in the **value**, where the remote half's `case
$path in /nix/store/*)` already routes it to `nix-store --add-fixed`. **The remote heredoc
needs no change.** Verified end to end: both `assert old in s` guards matched the live file
byte for byte, the generated loop emits five flat, dot-free, slash-free names of length
12, 17, 25, 18 and 18, and running the extracted remote body against a `nix-store` stub
produced **eight** flat symlinks.

### The two failure modes it prevents

**(1) A missing basename strip aborts the run, loudly.** Without `${f##*/}`, `${f%%.*}` on
a path yields an **absolute** name, so `nix-store --realise --add-root "$d/$name"` targets
a nonexistent directory and fails. The remote body runs under `set -eu`, so the script
aborts **there** and the sweep below never runs: the unit fails, failure-surfacing sees it,
and **no existing root is touched**. Measured with `tally`, `tally-b` and `tally-lake`
pre-populated: `ln: failed to create symbolic link '…/seeds2//mnt/fast/fonts/apple/sf-pro-fonts':
No such file or directory`, exit 1, all three siblings still present.

An earlier version of this comment claimed the sweep would delete every sibling. It is
**wrong** and must not ship: `set -eu` stops the script first. Keep the strip anyway,
because a loud nightly failure is still a broken seed.

**(2) A font basename colliding with a locked node name silently clobbers a real seed.**
This is the hole the eval-time guard cannot see: `fontRootNames` compares font basenames
only against each other, while the locked-node names (`tally`, `tally-b`, `tally-lake`)
are discovered at **runtime** from the lock. Measured: adding
`/mnt/fast/fonts/anthropic/tally.tar.zst` **evaluates cleanly**, and feeding the resulting
pairs to the unmodified remote heredoc silently clobbers `seeds/tally` with the font
tarball. `keep` contains "tally", so the sweep preserves the wrong one and the loss
surfaces only as update-center's `seed-missing tally` at 01:30 on the NAS. The shell loop
above closes it in the local half. `''${names[@]+…}` keeps it safe under `set -u` when the
lock names no mecattaf node.

Say in the comment which guard covers which case: the eval-time `lib.throwIf` covers
font against font, the shell check covers font against node.

Two minor notes worth one line each in the file. `lib.hasInfix "/" n` is unreachable,
because `baseNameOf` can never return a string containing a slash; only `n == ""` can
fire, and only for a basename beginning with a dot. And a trailing slash slips through both
guards, since `baseNameOf "/mnt/fast/fonts/anthropic/"` is `"anthropic"`. The eval-time
name derivation is also an independent second implementation of the shell's `${f##*/}`
plus `${b%%.*}`, and nothing ties the two together.

---

## 4. Bootstrap

**Two switches.** Switch 1 installs the packages only; the review window happens against
that. Switch 2 flips the consumers, and only after Tom approves. That is the definition of
done.

0. **Guard.** `git -C $DOT status --porcelain` and expect only the known unrelated modified
   files and the untracked wallpaper PNG. Append the `.gitignore` block. **Never `git add
   -A`**; stage explicit paths. Do not touch the uncommitted `background_opacity` hunk in
   `kitty.conf`.
1. **Branch.** `git -C $DOT switch -c work/anthropic-fonts-nas`, following the
   `work/sf-pro-nas` precedent.
2. **Land the press, no hashes yet.** `pkgs/fontbuilder/**`, the `.gitignore` block, the
   `flake.nix` overlay line and the `fontbuilder` export. Commit. Verify with
   `nix-instantiate --parse` on every new `.nix`, and `nix build .#fontbuilder` plus its
   `checkPhase` **without** `~/colors` present, which is the inertness property.
   **Decide the `glyphnames.json` override here**: it adds 35,585 bytes of `post` per face
   and therefore changes every sha256, so it must be settled before the press runs.
3. **Press.** `nix run .#fontbuilder -- /home/tom/colors/waves/capture ~/build/anthropic-fonts-2026-09-17`.
   About **4 minutes** for the 12 terminal faces including desktop and webfonts, measured
   on the unified press at roughly 19 s per face.
4. **Verify before packaging**, because the sha256 is cut from these bytes:
   `nix run .#fontbuilder -- --verify ~/build/anthropic-fonts-2026-09-17`.
5. **The gate. Three decisions, all baked into the hash.** Open `specimens/align-none.png`
   and `specimens/align-anchor.png`, and `specimen.html` in a throwaway Chrome profile.
   1. align mode, `anchor` against `none`;
   2. braille `dy`, 0 against +17 against +55, from the braille rows in the same sheet;
   3. the glyphnames override, already taken at step 2; confirm it is in the manifest.
   Look at four rows, not three: ligature and hyphen alignment, box art, the donor seam
   (Greek, Cyrillic and braille beside Latin), and the braille block. **Decide now.** A
   later change means new tarballs, a new sha256 and a NAS re-upload.
6. **Prove determinism.** `nix run .#fontbuilder -- <src> ~/build/repro-check --verify-repro`
   must exit 0 **and print a table of 12 + 5 + 7 + 3 byte-identical artifacts**. An exit 0
   with no artifact table is a vacuous pass, which is exactly what the unimplemented flag
   used to do.
7. **Package.** `nix run .#fontbuilder -- --package ~/build/anthropic-fonts-2026-09-17 --nas root@nas:/mnt/fast/fonts/anthropic`
   writes `dist/{3 tarballs, SHA256SUMS, README.md}` and prints the three `sha256 = "…";`
   lines.
8. **Seed the coordinator locally, from the build output**, before the NAS round trip and
   before the commit, because the tarballs are not substitutable from attic.

   **Seed all three.** `anthropic-webfonts.tar.zst.drv` is in the coordinator toplevel
   requisites through `home.packages` under home-manager-as-a-NixOS-module, so a
   two-tarball seed still hard-fails switch 1. Verified: `nix-store --query --requisites`
   on the toplevel lists all five `requireFile` derivations.

   **Confirm flat, not recursive.** `nix-store --add-fixed --recursive sha256` produces a
   *different* path and the build still dies with the same `requireFile` message.

   ```bash
   cd ~/build/anthropic-fonts-2026-09-17/dist
   for f in *.tar.zst; do
     p=$(nix-store --add-fixed sha256 "$f")
     q=$(nix-store --print-fixed-path sha256 "$(sha256sum "$f" | cut -d' ' -f1)" "$f")
     [ "$p" = "$q" ] || { echo "seed path mismatch: $p != $q"; exit 1; }
   done
   ```

   **Root the seed for the length of the bootstrap.** Measured: the seeded path gets no GC
   root and never acquires one (`--query --roots` and `--referrers` are both empty even
   after its package is built), `nix-gc.timer` here is weekly with `Persistent=true`, and
   `modules/gc-retention.nix` records an operator hand-running `nix-collect-garbage -d`. A
   sweep between steps 8 and 12 reopens the hard fail.

   ```bash
   mkdir -p ~/build/anthropic-fonts-2026-09-17/gcroots
   for f in *.tar.zst; do
     nix-store --realise --add-root ~/build/anthropic-fonts-2026-09-17/gcroots/"${f%%.*}" --indirect \
       "$(nix-store --print-fixed-path sha256 "$(sha256sum "$f"|cut -d' ' -f1)" "$f")"
   done
   ```

   Delete that directory after step 19 confirms the **built** outputs are substitutable.
   From then on the tarball is never needed again: the apple tarball store paths are
   already gone from this store while the fonts stay installed, which is the proof that a
   one-shot seed suffices.
9. **Upload,** reproducing the permission split exactly:
   ```bash
   ssh root@nas 'mkdir -p /mnt/fast/fonts/anthropic && chmod 0755 /mnt/fast/fonts/anthropic'
   scp ~/build/anthropic-fonts-2026-09-17/dist/{*.tar.zst,SHA256SUMS,README.md} root@nas:/mnt/fast/fonts/anthropic/
   ssh root@nas 'cd /mnt/fast/fonts/anthropic && chmod 0444 *.tar.zst SHA256SUMS && chmod 0644 README.md && chown root:root * && sha256sum -c SHA256SUMS'
   ```
10. **Commit the packages, install-only.** Include `pkgs/anthropic-*.nix` with the real
    bare-hex hashes, the overlay lines, the two tombstone rewordings,
    `home/update-center-seed.nix`, `docs/fonts/**`, `modules/common.nix` **`fonts.packages`
    only**, and `home/home.nix` **`home.packages` only**. Exclude `defaultFonts`, the dconf
    font keys and `kitty.conf`: those are switch 2.
11. **Evaluate. `nix flake check` is NOT the gate.** Measured on a fresh clone of the
    untouched base commit, `nix flake check --no-build` already fails with `error: path
    'pl6rmijq…-source' is not valid` while checking `checks.x86_64-linux.nas-personal-tailnet`,
    a tailscale NixOS test whose source is not in this machine's store. The gate is the
    three toplevel evals, which do pass and which is where the seed collision guard throws:
    ```sh
    nix eval --raw .#nixosConfigurations.{coordinator,worker,client}.config.system.build.toplevel.drvPath
    ```
    plus `nix build --dry-run` of the coordinator toplevel. Measured once seeded: 31
    derivations to build, 4 paths to fetch, and **zero** `*.tar.zst.drv`.
12. **Switch 1.** `sudo nixos-rebuild switch --flake /home/tom/mecattaf/dotfiles#coordinator`,
    when no long-running agent session is mid-flight.
13. **The review window**, on Tom's live session, changing no config. See section 5.
14. **Switch 2, after approval.** Second commit: `modules/common.nix` `defaultFonts`,
    `home/home.nix` dconf keys, `home/dot_config/kitty/kitty.conf`. Open the PR, merge.
15. **Bring the merge into the raw checkout before switching.** `git -C $DOT switch main &&
    git pull --ff-only`. `kitty.conf` is an out-of-store symlink into that directory;
    skipping this silently leaves the terminal on the old font. Then switch again.
16. **Seed the NAS by hand, before the 01:30 nightly.** `systemctl --user start
    update-center-seed`, then `ssh root@nas 'ls -la /var/lib/update-center/seeds/'` and
    expect exactly **8** flat roots: `tally`, `tally-b`, `tally-lake`, `sf-pro-fonts`,
    `sfmono-liga-fonts`, `anthropic-mono-nerd-fonts`, `anthropic-ui-fonts`,
    `anthropic-webfonts`. No nested directories and no pre-existing root deleted. The
    directory currently holds exactly 5 flat symlinks, so the 8 is arithmetic that should
    be confirmed by observation.
17. **Live verification, in this order.**
    ```sh
    fc-list | grep -ci anthropic          # 12 mono + 5 UI faces, and ZERO woff2 lines
    fc-match monospace ; fc-match sans-serif ; fc-match serif
    test -e /etc/profiles/per-user/tom/share/webfonts/css/anthropic-fonts.css
    test -e /etc/profiles/per-user/tom/share/webfonts/woff2/AnthropicSans-Roman.woff2
    fc-list : family | grep -cE 'Anthropic (Sans|Serif|Mono) Web|^Anthropicons$'   # 0
    ```
    The webfonts path is `/etc/profiles/per-user/tom/share/webfonts/`, **not**
    `~/.nix-profile/share/webfonts/`. `home-manager.useUserPackages = true` routes
    `home.packages` through `users.users.tom.packages`; home-manager creates no
    `~/.nix-profile`, and the one on this box is an unrelated imperative `nix profile`
    holding only `brave`. Verified on five packages already in `home.packages` (eza,
    zoxide, glow, bat, fd): all five resolve under `/etc/profiles/per-user/tom/bin` and
    none under `~/.nix-profile/bin`. Then open a **new** kitty window running the demo,
    Nautilus, a Chrome page, and `chrome://settings/fonts`.
18. **Worker and client window.** `modules/common.nix` is common to every host and only the
    coordinator was hand-seeded, so a worker rebuilt between merge and the nightly dies on
    a raw `requireFile` error. Put the recovery command in the PR body:
    ```sh
    scp root@nas:/mnt/fast/fonts/anthropic/<file> . && nix-store --add-fixed sha256 <file>
    ```
19. **After the nightly.** `curl -s -o /dev/null -w '%{http_code}\n'
    http://nas:8080/fleet/<built-output-hash>.narinfo` returns 200 for each of the three
    outputs, proving other hosts never need the tarball, and `journalctl -u update-center
    -n 50` on the NAS shows a clean run.

---

## 5. The review window

The `-o` strings are correct and were verified three ways: an argv dump under bash **and**
fish, `parse_override` plus `get_font_files`, and the real kitty binary accepting the exact
argv and dying only at display creation. But **a lost quote fails silently to Liga
SFMono**, which is the very font the review compares against, so the command gates itself
before spawning:

```bash
OV=( --override 'font_family=family="AnthropicMono Nerd Font Mono"' … --override 'window_padding_width=14' )
REVIEW_ARGV=$(printf '%s\x1f' "${OV[@]}"); export REVIEW_ARGV
kitty +runpy "exec(compile(open('$ASSERT').read(),'a','exec'),{'__name__':'__main__'})" \
  || { echo "REFUSING TO OPEN: the overrides do not resolve to the Anthropic faces"; exit 1; }
exec env -u FONTCONFIG_FILE -u FONTCONFIG_PATH WAYLAND_DISPLAY=wayland-1 \
  XDG_RUNTIME_DIR="/run/user/$(id -u)" kitty --title … "${OV[@]}" --hold bash "$DEMO"
```

`assert_ov.py` re-parses the same strings and demands the four-tuple with `bad_lines ==
[]`. Measured: the positive path prints four OKs then spawns; removing one pair of quotes
gives `BAD CONFIG LINE … does not contain an =`, then "REFUSING TO OPEN", and no spawn.

Three traps recorded with it:

- **Join with `\x1f`, never `\0`.** bash silently drops NUL bytes in a variable, and the
  first attempt passed the pre-flight while actually resolving to Liga SFMono.
- **`-u FONTCONFIG_CACHE` is dead code.** `FONTCONFIG_CACHE` is not a fontconfig variable;
  only `<cachedir>` and `XDG_CACHE_HOME` control cache placement.
- **`XDG_RUNTIME_DIR="/run/user/$(id -u)"` resolves to the private tree** if the command is
  ever run inside `~/.local/bin/runtime-test`, and the window then never reaches Tom's
  session. The review spawn must come from a shell with the real `/run/user/1000`.

The demo script prints the ligature rows, the hyphen/arrow/equals alignment triad, the
prompt, powerline, braille with an explicit U+2800 callout, the box-join figure, Greek and
Cyrillic, and ANSI bold, italic and bold-italic rows that exercise all four resolved faces,
then drops to an interactive shell so Tom can run `btop`, `git log --oneline --graph` and a
TUI pane in it.

**One caveat.** The braille row exercises **kitty's own dot rasteriser**, not the font, so
it can neither approve nor reject the merged braille or the braille `dy`. Judge braille
with `pango-view` or in `foot`, and judge the `dy` from the specimen sheet.

---

## 6. Verifying the unexported packages

The three font packages stay **unexported** from the flake, matching `sf-pro`. Nothing
needs to `nix build` a `requireFile` derivation by name, and exporting them only gives
`nix flake check` more ways to trip over a missing tarball. That makes `nix build
.#anthropic-mono-nerd` impossible by construction, so the verification route is:

```sh
nix build --impure --expr \
  '(builtins.getFlake "'"$DOT"'").nixosConfigurations.coordinator.pkgs.anthropic-mono-nerd'
```

All three were proven that way. Note that `requireFile` sets `meta.license = unfree` on
the src derivation, so a hand-written probe using a bare `import <nixpkgs> {}` fails with
an `allowUnfreePredicate` message that looks nothing like a seeding problem. The flake
itself is fine; the probe is wrong.

`fontbuilder` **is** exported, because `nix run .#fontbuilder` is how it is meant to be
invoked.

---

## 7. If it breaks

| symptom | cause | fix |
|---|---|---|
| `requireFile` error naming a tarball during a build or switch | the store has no fixed-output path for it on this host | `scp root@nas:/mnt/fast/fonts/anthropic/<file> . && nix-store --add-fixed sha256 <file>`. Confirm with `nix-store --print-fixed-path sha256 <hash> <basename>`; if the paths differ you used `--recursive`. |
| switch 1 fails on `anthropic-webfonts.tar.zst` although mono and ui were seeded | the webfonts derivation is in the toplevel requisites through `home.packages` | seed all three, always |
| the terminal still shows the old font after a switch | `kitty.conf` is a raw out-of-store symlink into `$DOT`, and old windows keep the old face | `git -C $DOT switch main && git pull --ff-only`, switch again, open a **new** window |
| kitty shows the right weight in the wrong family, or the right family unstyled | a forbidden bare `<family> <Style>` string, or a typo in `style=` | use `family="…" style="…"`; check with `get_font_files`, never a bare `find_best_match` |
| `fc-scan %{spacing}` reads 90 on a terminal face | the S1 phantom-delta repair was dropped; 37 combining marks reach advance 2400 at weight 300 | re-press; the negative control is instancing the unrepaired Italic at wght=300 and seeing `{1200: 662, 2400: 37}` |
| `fc-list` shows woff2 rows, or `fc-match 'Anthropic Sans'` returns a `.woff2` | the webfonts package reached a fontconfig-scanned prefix, or the glob reject is missing | keep it out of `fonts.packages`; ship the `*/share/webfonts/*` and `*.woff2` reject in `fonts.fontconfig.localConf` |
| `seed-missing tally` on the NAS at 01:30 | a font basename collided with a locked node name and clobbered the root | the shell guard in section 3 exits 1 before that happens; if it already happened, re-run `update-center-seed` after renaming the archive |
| the nightly seed unit failed with `ln: failed to create symbolic link '…//mnt/…'` | the basename strip is missing | restore `b="${f##*/}"`; no existing root was touched, because `set -eu` aborted first |
| a font package rebuilds from scratch on another host | the built output is not in attic yet, or retention expired | check the narinfo; the packages are in `modules/common.nix` so they stay in a real host closure |

---

## 8. Standing gap

**There is no preflight check for font archives.** `hosts/nas/update-center.nix` covers
locked flake nodes only. A font tarball that goes missing, is truncated or has its
permissions changed on the M.2 surfaces as a `requireFile` failure on the next host that
rebuilds, not as an alert. That is good follow-up work and is deliberately out of scope
here.

Two smaller items in the same category. The webfonts glob reject is measured in an
isolated fontconfig configuration only; it has not been applied as
`fonts.fontconfig.localConf` on a real switch, and nobody has checked that rejecting
`*.woff2` system-wide does not also reject something wanted. And the
`home.file.".local/share/webfonts"` handle is a recommendation: its fontconfig
invisibility is inferred from `/etc/fonts/fonts.conf:104` declaring only `<dir
prefix="xdg">fonts</dir>`, which is `~/.local/share/fonts` exactly, rather than tested. Do
not name that handle `fonts`.
