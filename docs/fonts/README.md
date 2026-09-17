# The Anthropic font suite

Pressed on 2026-09-17 by `pkgs/fontbuilder` from the brand faces captured in
`~/colors/waves/capture`, stored as three tarballs on the fleet's NAS M.2, pinned by
sha256, and installed on every host through `modules/common.nix`. No font binary is in
this repository and none is ever downloaded.

| page | what it holds |
|---|---|
| this file | what is installed, the standing rules, the daily-driver notes, how to check and how to revert |
| [`anthropic-suite.md`](anthropic-suite.md) | the measurements: sources, defects, names, donors, ligature alignment, PUA, CSS, verification transcript |
| [`nas-and-bootstrap.md`](nas-and-bootstrap.md) | the operations runbook: NAS layout, tarball rules, the seed refactor, the two-switch bootstrap, recovery |
| [`../../pkgs/fontbuilder/README.md`](../../pkgs/fontbuilder/README.md) | the press manual: stages, forbidden flags, reproducibility, runtimes, exit codes |

---

## What is installed

| package | family (fontconfig) | files | reaches disk via | consumer |
|---|---|---|---|---|
| `anthropic-mono-nerd` | `AnthropicMono Nerd Font Mono` | 12 statics `AnthropicMonoNerdFontMono-<Style>.ttf` | `fonts.packages` | kitty, foot, any monospace generic |
| `anthropic-ui` | `Anthropic Sans`, `Anthropic Serif`, `Anthropicons` | 4 variable TTFs + 1 pinned static | `fonts.packages` | GTK, Nautilus, Chrome generics |
| `anthropic-webfonts` | none, deliberately | 7 woff2 + `css/anthropic-fonts.css` | `home.packages` | local web pages only |

The 12 terminal statics are Light, Regular, Medium, SemiBold, Bold and ExtraBold, each in
Roman and Italic. PostScript names are `AnthropicMonoNFM-<Style>`, except the RIBBI Regular
face, which is the bare `AnthropicMonoNFM` because nerd-font-patcher 3.5.1 strips `Regular`
from it. nameID 1 is `AnthropicMono NFM[ Weight]` and nameID 16 is the full
`AnthropicMono Nerd Font Mono`.

Sans and Serif ship **variable** (`wght` 300 to 800, `opsz` 16 to 48). FontForge never
touches them, so `fvar`, `gvar`, `STAT` and the optical-size axis survive and one file
serves every weight and size. `Anthropicons` ships as a static pinned at
`wght=400 opsz=20 ANIM=0 ANM2=0`.

The webfonts package is **not** in `fonts.packages`. It installs to
`/etc/profiles/per-user/tom/share/webfonts/{woff2,css}`, with a convenience handle at
`~/.local/share/webfonts`. A woff2 under any fontconfig-scanned prefix gets indexed and
contends with the installed TTF for the family name, which is why the directory is
`share/webfonts` and never `share/fonts`, and why `fonts.fontconfig.localConf` rejects
`*/share/webfonts/*` and `*.woff2` outright.

## Where the bytes live

```
nas:/mnt/fast/fonts/anthropic/
  anthropic-mono-nerd-fonts.tar.zst   2571132 B   sha256 df043254517d186e6107caedae706436182c29d3e69aaedae031825b0a030fdc
  anthropic-ui-fonts.tar.zst          726204 B     sha256 070d34426a6eab50dd8dd3ae19cf847a52af86adb03d0a4f0d5d1d0de4393c77
  anthropic-webfonts.tar.zst          830195 B    sha256 8da31eca13b2c55bce504567256462d579ccdbee6b8fe713fc33feb65ef40239
  SHA256SUMS                          0444
  README.md                           0644
```

`pkgs/anthropic-mono-nerd.nix`, `pkgs/anthropic-ui.nix` and `pkgs/anthropic-webfonts.nix`
are `requireFile` derivations that name those exact bytes. `home/update-center-seed.nix`
has the NAS add each tarball to its own store from that disk nightly and roots it. The
same pattern as `pkgs/sf-pro.nix`, one directory over.

## Standing rules

- **Font bytes never enter this repository.** `.gitignore` refuses `*.ttf`, `*.otf`,
  `*.woff`, `*.woff2` and `*.tar.zst`. `nerd-font-patcher --cell '?'` does not query
  anything, it patches into the current directory; that is how a 440 KB patched TTF once
  landed in the repo root.
- **A replacement tarball means a new sha256 in two places**: the `sha256 =` line in
  `pkgs/` and the 0444 `SHA256SUMS` on the NAS. Never overwrite a tarball in place.
- **No family string enters this repo until kitty's own resolver has printed it.** Run
  `load_config` on the real `kitty.conf` and assert `get_font_files()` returns the four
  expected PostScript names. `fc-scan` alone would not have caught the 2026-08-21
  incident; a bare `find_best_match` would not have caught it either.
- **`~/colors/waves/capture` is read-only and is the only copy.** It is 274 MB, not a git
  repository, and not on any remote. The press reads it; nothing writes it.
- **Never run `fc-cache` from a build or a test.** Measured: `fc-cache -f <dir>` ignores
  the `<cachedir>` in a private `FONTCONFIG_FILE` and wrote 113,904 bytes into the live
  `~/.cache/fontconfig`. Verification sets `FONTCONFIG_FILE` **and** `XDG_CACHE_HOME`.
- **Never put a woff2 under a fontconfig-scanned prefix.** `fc-scan` parses woff2 on this
  box and returns a family with exit 0, so it would be indexed and contend.
- **Never map a `symbol_map` range to a face measured to lack it.** A `symbol_map` range
  is a hard map with no coverage test and no fall-through. kitty's is empty on purpose.
- **These faces are personal use only.** See the licence position at the end of this page.

## Daily driver

`kitty.conf` names the family explicitly, in the `family=`/`style=` form:

```conf
font_family      family="AnthropicMono Nerd Font Mono"
bold_font        family="AnthropicMono Nerd Font Mono" style="SemiBold"
italic_font      family="AnthropicMono Nerd Font Mono" style="Italic"
bold_italic_font family="AnthropicMono Nerd Font Mono" style="SemiBold Italic"
font_size        16.0
disable_ligatures never
```

That form is used because it is the only one whose result does not depend on the
fontconfig `monospace` alias or on nameID 4 surviving a future patcher release. The bare
string `AnthropicMono Nerd Font Mono SemiBold` is **forbidden**: kitty looks a setting
string up verbatim in its name maps and otherwise falls through to `fc_match` silently,
and `--makegroups 4` caps nameID 4 at 31 characters, so this face's nameID 4 is the
abbreviated `AnthropicMono NFM SemiBold` and the 37-character long form is not a key.
The four style spellings `SemiBold`, `Italic`, `SemiBold Italic` are load-bearing
literals: a typo empties kitty's candidate list and falls silently to its last resort,
`fc-match monospace`. Where that lands depends on the configuration and is never what you
asked for. Under the live system configuration `style="Semi Bold"` resolves to
`LigaSFMonoNerdFont-Bold`; under an alias-free configuration and again after the
`defaultFonts` commit it resolves to `AnthropicMonoNFM-Bold`, so the typo silently costs
two weights inside the right family.

**Bold is SemiBold, not Bold.** That is the 2026-08-21 ruling, kept because SemiBold is
the weight the old silent fallback actually served and the rendering Tom said to keep.
kitty's own `auto` picks SemiBold for this family too.

**Geometry against Liga SFMono at `font_size 16.0`,** measured with kitty's own
`create_test_font_group`:

| | AnthropicMono NFM | Liga SFMono |
|---|---|---|
| cell @96dpi | 13 x 27 px | 13 x 26 px |
| cell @192dpi | 26 x 54 px | 26 x 51 px |
| x-height | 0.5400 em | 0.5298 em |
| cap height | 0.7200 em | 0.7046 em |

**Column width is identical at this size.** 0.600 em is 25.6 px and 0.6182 em is 26.4 px,
and both round to 26 at scale 2, so the column count does not change. Only the rows do,
by 3.70% fewer at 96 dpi and 5.56% fewer at 192 dpi. `modify_font cell_height -6%` takes
54 px back to 51 px, which is Liga SFMono's line density at scale 2. It is left unset on
purpose; set it only if the looser leading actually bothers you.

**Ligature alignment.** Fira Code's ligature art is copied in at stage S5 and then shifted
vertically, per ligature, by the measured difference between each constituent's y-centre
in this face and in Fira. The hyphen alone is 93 units out, which is 1.98 px at 16 pt on a
scale-2 output against a dash only 3.37 px thick. 100 of the 136 ligatures are shifted,
35 are vetoed because a constituent sits on the baseline where the delta is meaningless,
and 1 is clamped. On italics every ligature is additionally sheared 10 degrees about
y=540, which is the host's own italic transform measured from its own `bar`, `exclam`,
`colon` and `I`.

**Box art is Nerd's full-cell set.** The patcher replaces Anthropic's own 22 box-drawing
glyphs with the full 160-glyph Nerd set, drawn to span the cell (x from -12 to 1212, so
12 units of deliberate overlap each side). That is wanted: boxes connect. It is the one
place a donor overrides the brand drawing.

**Braille is merged, but kitty does not use it.** All 256 braille codepoints including the
blank U+2800 are grafted from Maple Mono NF at exactly 2.0x. kitty draws U+2800 to U+28FF
itself before consulting any font, so the merge matters for foot, GTK and Pango, not for
`btop` in kitty. Judge braille in `pango-view` or in `foot`, never in kitty.

**`symbol_map` is empty and carries no commented line.** kitty draws box, block, braille,
powerline and legacy-computing cells itself; and a `symbol_map` range is a hard map, so
mapping CJK, Kana or Hangul to a face that lacks them replaces working Noto with notdef
boxes.

## The "best of": which cut was chosen, and why

Three subset generations of the same three families were served publicly. The suite takes
the anthropic.com **Web** cut (version 26.043.1) for all three text families, repaired.

| family | chosen | measured reason |
|---|---|---|
| Mono | `AnthropicMono-{Roman,Italic}-Web.ttf` | 655 codepoints on every property; there is no fuller Mono anywhere public. The claude.ai cut is byte-identical in all 698 other glyphs and differs only in `.notdef`, so the choice is the live public one. |
| Sans | `AnthropicSans-{Roman,Italic}-Web.ttf` | 713 glyphs / 625 codepoints Roman, equal to the Variable cut. The Web cut uniquely carries the brand glyph **names** at U+E11A to U+E11E. |
| Serif | `AnthropicSerif-{Roman,Italic}-Web.ttf` | 747 / 633 Roman, equal to the Variable cut. Same naming advantage. |
| icons | `Anthropicons-Variable.ttf` | the only copy that exists: 792 glyphs, 307 codepoints in U+E000 to U+E134, four axes including two custom animation axes. |

The Variable cut's two genuine advantages, a correct italic bit and a Serif default at
400, are exactly the two repairs the pipeline performs anyway, so they do not
discriminate. Coverage is then completed, additively and never overwriting a host glyph,
from three donors chosen on measured cell and cap ratios: JetBrains Mono for Greek,
Cyrillic and the punctuation and math blocks; DejaVu Sans Mono for arrows, geometric
shapes and dingbats; Maple Mono NF for braille. Iosevka won the coverage spreadsheet and
was rejected anyway: no uniform scale fits its 1.4135 cap-to-x ratio against this face's
1.3333.

The result is **13,440 codepoints on Regular and 13,441 on Italic** against the 655 the
brand face ships, with every advance still exactly 1200 and a full 256/256 braille block.
The per-face numbers are in [`anthropic-suite.md`](anthropic-suite.md) section 10.

## How to check a suspicion in 10 seconds

```sh
# What is kitty actually using, right now, for all four roles?
# (+runpy wants a tty, hence `script`; the full gate is pkgs/fontbuilder/tests/resolve.py)
script -qec "kitty +runpy 'import json
from kitty.config import load_config
from kitty.fonts.common import get_font_files
ff = get_font_files(load_config(\"$HOME/.config/kitty/kitty.conf\"))
print(json.dumps({k: ff[k].get(\"postscript_name\") for k in (\"medium\",\"bold\",\"italic\",\"bi\")}, indent=1))'" /dev/null

# Is the family installed at all, and is it monospaced to fontconfig?
fc-list | grep -c AnthropicMonoNerdFontMono            # expect 12
fc-list --format '%{file}\n' | grep AnthropicMonoNerdFontMono-Regular.ttf | head -1 | \
  xargs fc-scan --format '%{family}|%{style}|%{weight}|%{slant}|%{spacing}\n'

# Do the generics point where you think?
fc-match monospace ; fc-match sans-serif ; fc-match serif

# Did a woff2 leak into the font namespace?
fc-list | grep -ci woff                                 # expect 0
fc-list : family | grep -cE 'Anthropic (Sans|Serif|Mono) Web|^Anthropicons$'   # expect 0
```

If `fc-scan` reports `spacing` **90** on any terminal face, the S1 phantom-delta repair
was dropped: 37 combining marks in the Italic source interpolate to advance 2400 at
weight 300, and fontconfig then classifies the face as dual-spaced rather than monospaced.
Only one of the twelve faces is at risk and it is Light Italic.

A new kitty window is required after a switch. Old windows keep the old face.
`kitty.conf` is a raw out-of-store symlink into the checkout, so the branch must be
ff-merged into `/home/tom/mecattaf/dotfiles` before `nixos-rebuild switch` or the terminal
silently does not change.

## How to revert

**Reverting is two files, not one.** After the second commit the fontconfig `monospace`
alias points at the Anthropic family, so `Liga SFMono Nerd Font SemiBold Italic` resolves
to the plain `AnthropicMonoNFM`. Reverting `kitty.conf` alone gives the wrong family for
every non-exact line. Revert together:

1. `modules/common.nix` `fonts.fontconfig.defaultFonts` back to SF Pro / Source Serif 4 /
   Liga SFMono;
2. `home/dot_config/kitty/kitty.conf` back to the four `Liga SFMono Nerd Font` lines,
   which are preserved verbatim in the commented old block above them.

Then switch. `sf-pro` and `sfmono-liga` stay installed for exactly this reason and are not
to be removed. The GTK keys in `home/home.nix` are a third, independent revert if only the
desktop is wrong.

## Where the material came from, and the licence position

The faces were recovered in August 2026 from Anthropic's own public web assets: the live
anthropic.com CDN, reached by fetching `ant-brand.shared.*.min.css` and grepping
`@font-face`, and the dead `claude.ai/imagine` site through the Internet Archive. A sweep
of nine Anthropic properties on 2026-08-31 found three distinct subset generations of the
same three families and nothing else; the woff2 were decompressed to TTF with fontTools
because terminals need TTF. A later pass added `Anthropicons-Variable` from the claude.ai
app stylesheet, which is the seventh font and the only icon face. The provenance record is
`~/colors/waves/capture/FONTS.md`. It is a single unversioned copy and that is a standing
exposure independent of anything here.

These are proprietary corporate brand typefaces. No `nameID 13` or `nameID 14` licence
record exists on any Anthropic face and no `OFL.txt` accompanies them; `fsType 0x0000`
governs document embedding, not redistribution. `FONTS.md` reads that as fine to render
locally on your own machine and not fine to ship in a repo or a hosted page. That read is
a note, not a ruling, and is recorded here once because a mixed-licence artifact should
say what it is.

Tom's ruling, 2026-09-01T10:27, verbatim:

> re FONTS no this is my personal laptops on my perso gh, and i lend my hardware to
> friends who are trusted for fw months at most. very easy to get lost in the details, DO
> NOT RELITIGATEON THATONE. a submodule isideal for the fonts and all the rebuilds happen
> locally

and from the same session at 07:29:

> a modified nerd font ligaturized anthropic terminal font; plus the web ui fonts;
> packaged and disributed from my NAS. same motions as how the apple fonts are distributed
> but internal between me and 1-2 friends

Personal use only. The bytes stay on the NAS and out of git. Do not reopen the argument.

Donor outlines carry their own licences and are listed with them in
[`anthropic-suite.md`](anthropic-suite.md): OFL-1.1 for JetBrains Mono, Maple Mono NF and
Fira Code, Bitstream Vera and Arev for DejaVu Sans Mono, MIT for the Nerd Fonts patcher
(3.5.1) with per-glyph upstream terms for the icons it adds.
