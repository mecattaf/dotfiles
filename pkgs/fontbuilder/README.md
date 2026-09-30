# fontbuilder — the press for the Anthropic font suite

```sh
nix run .#fontbuilder -- /home/tom/colors/waves/capture ~/build/anthropic-fonts-2026-09-17
```

This package ships the **recipe and no bytes**. The Anthropic faces are unlicensed brand
trade dress; they live on the fleet's NAS M.2 only (`nas:/mnt/fast/fonts/anthropic/`), are
pinned by sha256 in `pkgs/anthropic-mono-nerd.nix`, `pkgs/anthropic-ui.nix` and
`pkgs/anthropic-webfonts.nix`, and never enter this repo, which `.gitignore` enforces.

**Inertness is a verified property, not an aspiration.** The derivation's `src` is
`./lib ./data ./tests ./specimen ./fontbuilder.py` and nothing else; no path under `/home`
appears in it; it builds in the normal Nix sandbox; and on a machine that has never seen
the capture tree, `nix build .#fontbuilder` and its `checkPhase` both pass while
`nix run .#fontbuilder -- /nonexistent <out>` exits **2** with
`fontbuilder: source tree does not match the pinned digests` plus one `missing` line per
pinned file.

**Pinned tools.** Everything comes from the flake's own nixpkgs (rev
`da39501c8d0a093136854eddcd6927c8a8bb0d8f`): **nerd-font-patcher 3.5.1** through the local
override, **nerd-fonts.jetbrains-mono 3.5.0** carrying JetBrains Mono 2.304, fontforge
20251009, fontTools 4.63, plus the three third-party pins fetched by hash (Ligaturizer
`c4065187a544a8fab40826fc91db1c6180a2d342`, Fira Code 3.001 at
`e9943d2d631a4558613d7a77c58ed1d3cb790992`, and `glyphnames.json` at the v3.5.1 tag). Most
measurements quoted here and in the suite document were first taken on patcher 3.4.0 from
the registry nixpkgs and re-verified on 3.5.1 by the acceptance suite. Two behaviours
genuinely differ: 3.5.1 ships more icons, so every packaged codepoint count is higher, and
`FontnameParser._remove_regular` drops the `Regular` suffix from the RIBBI face's
PostScript name.

Background: [`docs/fonts/README.md`](../../docs/fonts/README.md) for what is installed,
[`docs/fonts/anthropic-suite.md`](../../docs/fonts/anthropic-suite.md) for every
measurement behind these stages,
[`docs/fonts/nas-and-bootstrap.md`](../../docs/fonts/nas-and-bootstrap.md) for packaging
and deployment.

## 1. What it makes

| output | contents |
|---|---|
| `nf/` | 12 terminal statics, `AnthropicMonoNerdFontMono-<Style>.ttf` |
| `desktop/` | `AnthropicSans-{Roman,Italic}.ttf`, `AnthropicSerif-{Roman,Italic}.ttf`, still **variable** |
| `icons/` | `Anthropicons-Regular.ttf`, pinned at `wght=400 opsz=20 ANIM=0 ANM2=0` |
| `webfonts/` | `woff2/` (7 files), `css/anthropic-fonts.css` |
| `dist/` | 3 `*.tar.zst`, `SHA256SUMS`, the NAS `README.md` |
| reports | `specimens/*.png`, `specimen.html`, `PROVENANCE.tsv`, `align-report/<Style>.json`, `docs/anthropicons-map.json`, `verify.json`, `manifest.json`, `build.log` |

Flags: `--align anchor|none`, `--braille-dy <n>`, `--verify <out>`, `--verify-repro`,
`--package <out> [--nas root@nas:/mnt/fast/fonts/anthropic]`, `--rehash-sources`.
`--help` prints the usage, the invocation examples and the exit-code table.

## 2. Stages, in execution order

The order is the design. Each row says why it sits where it sits.

| # | stage | why here |
|---|---|---|
| S0 | verify-sources | fail closed against 14 pinned digests. This is the inertness gate, and it exits **2** so a caller can tell "no material" from "build broke" |
| S1 | repair-source | the STAT `' Italic'` doubling and the 37 advance-2400 combining marks must be fixed **on the variable file**, because the instancer bakes both in and every instance inherits the repair |
| S2 | instance | before any FontForge stage: FontForge accepts a variable TTF, exits 0, and silently flattens it to the wght=400 default with fvar, gvar and STAT gone |
| S3 | normalize | after instancing, so every later tool reads the final family, style and bits rather than re-deriving them from `…Web` |
| S4 | merge | additive only; a host codepoint is never replaced. Runs before the ligaturizer so the donor glyphs are present when `calt` is built |
| S5 | ligaturize | `--prefix ""` so the `lig.N` names survive for S6, and a **per-weight** Fira donor |
| S6 | align-ligatures | between S5 and S7: it needs Fira's glyphs present and the patcher's box-art replacements absent |
| S7 | nerd-patch | **last.** The only stage that validates and canonicalises the whole name table, and therefore the last writer of every name. shaunsingh's LigaSFMono did the reverse, which is why its PostScript name is the non-conforming `LigaSFMonoNerdFont-Regular` |
| S7b | regraft-pua | after the patch, because `--complete` destroys U+E001 to U+E00A. Re-installs those ten glyphs from the S6 face as `<name>.apua` |
| S8 | canonicalize | after **every** FontForge-touching stage, which means after S5 as well as at the end |
| S9 | desktop | Sans and Serif are **not** instanced: fvar, gvar, STAT and the opsz axis survive because FontForge never touches them |
| S10 | icons | synthesise the name table Anthropicons entirely lacks; `sxHeight 540`, `sCapHeight 720`, because the face is 1000 upm |
| S11 | webfonts | woff2 of the normalized faces plus the `@font-face` sheet, so the web set and the desktop set are one identity |
| S12 | package | three tarballs from **three** stage roots, `SHA256SUMS`, the NAS README |

Three ordering traps worth stating outright:

- **The S6 input path is derived, not chosen.** Ligaturizer writes `path(output_dir,
  font.fontname + '.ttf')` where `font.fontname` is `new_name` with spaces removed plus
  `'-'` plus `input_ID6.split('-')[1]`. So `work/lig/AnthropicMono-<Style>.ttf` is correct
  **only because** S3's nameID 6 rule put exactly one hyphen there. A driver that hardcodes
  that path will silently process a stale file if the naming rule changes.
- **Ligaturizer does not create `--output-dir`.** If it is absent the run completes the
  whole ligaturization and then dies at `font.generate()` with a bare `OSError: Font
  generation failed` and no mention of the directory. `lib/ligaturize.sh` runs `mkdir -p`
  first.
- **Do not add a second normalize after S5.** Ligaturizer visibly damages the name table
  (nameID 1 collapses to `Anthropic Mono` on every face, nameID 4 loses its space,
  ExtraBoldItalic comes out with `head.macStyle 67`), and the intermediate therefore looks
  broken. The patcher rebuilds the whole name table from ID16 and ID17, which Ligaturizer
  preserves, and resets macStyle. Measured: patching the as-is file and a re-normalized
  copy produce **identical** name tables and bits for both a non-RIBBI face (Light Italic)
  and a RIBBI face (Bold Italic). The extra stage is redundant, and dropping ID16/ID17 in
  it would break the rebuild.

**The patcher owns the Regular face's PostScript name, and 3.5.1 changed it.**
`FontnameParser._remove_regular` makes the RIBBI Regular face ship nameID 6
`AnthropicMonoNFM` and nameID 4 `AnthropicMono NFM`, where 3.4.0 gave
`AnthropicMonoNFM-Regular`. The Regular-weight italic stays `AnthropicMonoNFM-Italic` and
every other face keeps `-<Style>`. This is accepted as-is rather than fought, because the
patcher is the last writer of names and kitty's `family=`/`style=` form does not depend on
the spelling. Any assertion or tooling that pattern-matches nameID 6 must allow the bare
family form.

**The build gate for S7 is the log grep, never the exit code.** A face whose family is two
characters too long produces three `^ERROR` lines about over-length names and **exits 0**.
`lib/nerdpatch.sh` redirects `2>&1` into the log and keeps `grep -qE '^ERROR|^CRITICAL'
<log> && exit 1`. FontForge's own C-level stderr messages are not `ERROR`-prefixed and are
deliberately outside that gate.

**The glyphnames override is a package override, not a shim directory.** A shim carrying
`glyphnames.json` beside the binary cannot work: the nixpkgs wrapper sets `sys.argv[0]` to
the store path on its own line 9, before `fetch_glyphnames()` reads
`dirname(sys.argv[0])`. `pkgs/fontbuilder/nerd-font-patcher.nix` pins `glyphnames.json` at
the **v3.5.1** tag and extends **`installPhase`**,
not `postInstall`, because the package's `installPhase` is a custom string with no
`runHook postInstall` and a `postInstall` override is silently dropped, at which point the
build merely *looks* like it succeeded. With the override, U+E0B0 is named
`pl-left_hard_divider` instead of `uniE0B0`, U+F001 `fa-music` instead of `music.1` and
U+E62B `custom-vim` instead of `i_custom_vim`. cmap, advances, shaping and resolution are
identical either way, so it is a provenance change only, but it adds **35,585 bytes** of
`post` per face and therefore a different sha256. Decide it before the tarball is cut.

## 3. Flags that must never be passed

| flag | measured reason |
|---|---|
| `nerd-font-patcher --cell '?'` | it does **not** query anything. It runs the full patch and writes into the **current working directory**. That is how a 440 KB patched TTF once landed in the dotfiles repo root. fontbuilder always passes `--outputdir` and runs from a scratch cwd. |
| `--copy-character-glyphs` | measured crash on Python 3 at `ligaturize.py:88`, `'float' object cannot be interpreted as an integer`, unconditional for this font because `\|1231-1200\|/1200 = 0.026 < 0.1`. It would also splice Fira's punctuation into an Anthropic face. |
| `--careful` | it preserves the PUA but stops the patcher redrawing cell-filling box and block art: U+2588 becomes `(-50,0,1250,1440)` instead of a box spanning x -12 to 1212 (stored bbox; -11 to 1213 as drawn), so full block would no longer fill the cell. The PUA problem is solved by stage S7b instead. |
| explicit icon-set flags instead of `--complete` | omitting `--pomicons` by enumerating the sets makes `FontnameParser` append every set name, yielding nameID 16 `AnthropicMono Nerd Font Mono Plus Font Awesome Plus …` at **183 characters** with `ERROR` lines. |
| `--adjust-line-height` | a no-op here that would still rewrite hhea and OS/2: it only adds +1 when `winAscent + winDescent` is odd, and 1985 + 515 = 2500. The 1985/-515/0 line box is what every kitty layout depends on. |
| `--removeligs` | inert without `--configfile`, and its name invites someone to pass it after S5 has just installed 136 ligatures. |
| `tar --pax-option` with `--format=gnu` | GNU tar 1.35 exits **2** and writes **zero** bytes. The 13-byte artifact that gets blamed on it is **zstd's empty-frame overhead**, reachable only when tar's exit status is discarded by an unguarded pipeline. `set -o pipefail` is load-bearing in `lib/package.py`'s shell, and the file-count assertion guards a different failure: an under-populated stage directory, where tar exits 0, zstd writes a valid 66-byte tarball, and every other check passes. |

## 4. Reproducibility

**There are two non-deterministic tables in this chain, not one.**

`nerd-font-patcher` has only `head` (`modified` plus the derived `checkSumAdjustment`).
**Ligaturizer, through FontForge's `generate()`, has `head` and a 28-byte `FFTM`** whose
`sourceModified` is the build wall clock. Because `checkSumAdjustment` is computed over all
tables, FFTM's drift keeps `head` non-identical **even after head's own timestamps are
pinned**. Measured on two Ligaturizer runs seven seconds apart on identical input:
`DIFFERING TABLES: [('FFTM', 28, 28), ('head', 54, 54)]`, differing at FFTM byte 27 and
head bytes 10, 11 and 35. Pinning head alone still leaves `differ: byte 20`.

So byte-reproducibility of a FontForge-generated file requires pinning `head` **and
deleting `FFTM`**, and `lib/canonicalize.py` does both: it sets `head.created =
head.modified = SOURCE_DATE_EPOCH + 2082844800`, deletes `FFTM`, and re-saves with
`recalcTimestamp=False` so fontTools recomputes `checkSumAdjustment` from the pinned bytes.
The `del FFTM` line is **load-bearing, not dead code** (the comment that once called it
"never present in patcher output" invited its removal), and the stage asserts
`"FFTM" not in TTFont(path).reader.keys()` afterwards.

Consequently S8 runs twice in the graph:

```
S5 → canonicalize(work/lig/*.ttf) → S6 → S7 → S7b → canonicalize(work/nf/*.ttf, work/desktop/*.ttf)
```

The patcher's own output carries no FFTM and strips an incoming one, so the shipped face
was always safe. The non-reproducible artifact is the S5/S6 intermediate, which is exactly
what `--verify-repro` must diff.

`SOURCE_DATE_EPOCH` is **1789603200** (2026-09-17T00:00:00Z) and governs `head` inside
each font. The tar archive takes `--mtime=@0`; they are two different clocks.

**Glyph order is stable by construction.** The merge appends donor glyphs in sorted
codepoint order with deterministic names, and Ligaturizer and the patcher append in their
own fixed orders. Nothing sorts by hash or by dict iteration. The patcher is also
insensitive to `PYTHONHASHSEED` (1 against 999: only `head` differs, which canonicalize
then pins).

**`--verify-repro` must actually run the pipeline twice.** It runs the whole thing into two
trees and diffs every output byte for byte, and it **must print a table of 12 + 5 + 7 + 3
byte-identical artifacts**. An exit 0 with no artifact table is a vacuous pass. Separately,
an unwired or empty build must **fail**: after the stage graph runs, assert the expected
artifact counts (12 `nf/*.ttf`, 5 desktop, 7 woff2, 3 `dist/*.tar.zst`, `SHA256SUMS`) and
exit 1 otherwise. A build tool that produces nothing must never exit 0.

Two things that make a naive implementation pass vacuously, both measured: `package.py`'s
`harden()` chmods the stage to 0555/0444, after which `rm -rf` of that tree fails and the
second repro tree cannot be built; and creating `out/specimens/` and `out/align-report/`
without writing them makes the byte diff compare two empty directories.

The full-shape integration reference, which belongs at `tests/integration.sh`, runs two
Mono Roman faces, two Mono Italic faces, Sans and Serif normalize, Anthropicons, 7 woff2,
canonicalize and three tarballs, all under one epoch and one patcher, twice. Measured
1m14.2s and 1m12.8s with
`diff -r runA/dist runB/dist` identical, 16 of 16 artifacts identical, three **distinct**
tarball hashes and byte-identical `SHA256SUMS`.

**Do not quote a per-face sha256 from any prototype tree.** The prototype slices shipped
divergent copies of the shared library and pinned different epochs and different patcher
derivations, so the same face existed in two versions 35,784 bytes apart. Every per-face
digest from that era is void. The authoritative digests are the ones this unified press
prints, recorded in `manifest.json`, `SHA256SUMS` and
[`docs/fonts/anthropic-suite.md`](../../docs/fonts/anthropic-suite.md) section 10.

## 5. Licence

The recipe is Tom's, MIT, like the rest of this repo.

The **Anthropic faces have no licence of any kind**: nameID 13 and nameID 14 are absent on
every face and `fsType 0x0000` governs document embedding, not redistribution. Donor
outlines are OFL-1.1 (JetBrains Mono 2.304 from `nerd-fonts.jetbrains-mono` 3.5.0, Maple
Mono NF 7.9, Fira Code 3.001) and Bitstream Vera with Arev (DejaVu Sans Mono 2.37);
nerd-font-patcher 3.5.1 is MIT and the icons it adds carry their own upstream terms per
set.

The result is a mixed-licence artifact for **personal use only, never redistributed**.
Provenance is recorded per glyph through the `.jb`, `.dv`, `.maple`, `.dvs`, `.jbs`,
`.mps`, `.synth` and `.apua` name suffixes, in `PROVENANCE.tsv`, and per range in
`manifest.json` and the NAS `README.md`. Tom's ruling on distribution is quoted in
[`docs/fonts/README.md`](../../docs/fonts/README.md) and is not to be relitigated.

## 6. Runtimes, and benign noise

About **19 s per face** on the unified press, and **the patch dominates everything else**.
The fontTools and FontForge stages around it are small and version-stable: instance 0.2 s,
normalize 0.1 s, merge 1.3 s, ligaturize 0.6 to 0.7 s, align 0.5 to 0.6 s, canonicalize
0.1 s.

**Twelve faces is about 4 minutes**, including desktop and webfonts. `--verify-repro`
doubles it. The tarball step is about one second.

Lines that look like failures and are not:

| line | when | meaning |
|---|---|---|
| `This contextual rule applies no lookups.` x272 | every ligaturize run | exactly two per copied ligature, 136 x 2. Benign. |
| `WARNING: Possible problem with the weight metadata detected` | ExtraBold and ExtraBoldItalic only | the patcher's own heuristic disagreeing about a non-RIBBI weight name. Benign. |
| `WARNING: Can not read glyphnames file (FileNotFoundError(2, …))` | only if the patcher override is missing | the Nerd glyphs get raw names. Not fatal, but it means `PROVENANCE.tsv` cannot name the icons. Fix the override, do not ignore it. |
| `Warning: Bad device table` and glyph-name normalisation chatter | FontForge, most runs | C-level stderr, not `ERROR`-prefixed, deliberately outside the grep gate. |
| `macStyle 65` on ExtraBold after ligaturizing | S5 output only | FontForge leaves an undefined bit 6; the patcher cleans it to 0. Do not "fix" the intermediate. |

A run that prints `^ERROR` or `^CRITICAL` is a failure, regardless of exit status.

## 7. Exit codes

| code | meaning |
|---|---|
| 0 | success, and every artifact-count assertion passed |
| 1 | an assertion failed, or the patcher log carried an `ERROR`/`CRITICAL` line, or `--verify` / `--verify-repro` found a difference |
| 2 | the source tree does not match the pinned digests in `data/sources.sha256` |

Exit 2 is distinct on purpose: it says "no material", not "build broke", and it is the
code a machine without `~/colors` gets. `--rehash-sources` regenerates that file and is the
**only** sanctioned way provenance may change.
