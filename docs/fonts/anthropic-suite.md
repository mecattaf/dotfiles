# The Anthropic suite, measured

Every number on this page was measured on the files it names. Where a number could only
be known after the final press it is a substituted token. Nothing here is estimated, and
four claims that were once stated confidently and turned out to be wrong are recorded as
corrections rather than quietly deleted.

**Tool versions.** The press runs against the flake's pinned nixpkgs (rev
`da39501c8d0a093136854eddcd6927c8a8bb0d8f`): **nerd-font-patcher 3.5.1**,
**nerd-fonts.jetbrains-mono 3.5.0** carrying JetBrains Mono 2.304, fontforge 20251009 and
fontTools 4.63. The `glyphnames.json` pin is the **v3.5.1** tag. Most measurements quoted
here were first taken on nerd-font-patcher 3.4.0, from the registry nixpkgs, and were
re-verified on 3.5.1 by the acceptance suite. Two things genuinely changed between those
versions and are flagged where they appear: 3.5.1 carries more icons, so every packaged
codepoint count is higher, and its `FontnameParser._remove_regular` changed the Regular
face's PostScript name.

Companion pages: [`README.md`](README.md) for what is installed and how to revert,
[`nas-and-bootstrap.md`](nas-and-bootstrap.md) for operations,
[`../../pkgs/fontbuilder/README.md`](../../pkgs/fontbuilder/README.md) for the press.

---

## 1. The sources

### 1.1 What the capture holds

`~/colors/waves/capture` holds 114 font binaries in six directories. The 30 woff2 reduce
to 18 distinct binaries (12 exact md5 duplicate pairs); the 24 TTFs in `fonts-ttf/` reduce
to 18 (6 duplicate pairs). The canonical set is **7 TTFs, 2,169,776 bytes**, all converted
from woff2 with `fontTools.ttLib.woff2.decompress`.

| file | md5 | bytes |
|---|---|---|
| `fonts-ttf/AnthropicMono-Roman-Web.ttf` | `d41d84355f20e95016a771ac3635f21e` | 149,556 |
| `fonts-ttf/AnthropicMono-Italic-Web.ttf` | `989243d645597f40fa5611f109e3ab42` | 159,276 |
| `fonts-anthropic-com/AnthropicMono-Roman-Web.woff2` | `2a2e6eb0879b5e5be2654294db10ec81` | served bytes |
| `fonts-anthropic-com/AnthropicMono-Italic-Web.woff2` | `78ac2a4e5d90cdaa2e1c355d63d658c0` | served bytes |
| `fonts-anthropic-com/AnthropicSans-Roman-Web.woff2` | `c3fa6192c00bcfaba60d8cd3be70d146` | served bytes |
| `fonts-anthropic-com/AnthropicSans-Italic-Web.woff2` | `ea06d7c2b1c07b0492ba76c1836a890d` | served bytes |
| `fonts-anthropic-com/AnthropicSerif-Roman-Web.woff2` | `1ca11f68b43c5d09efbe5de98b02a085` | served bytes |
| `fonts-anthropic-com/AnthropicSerif-Italic-Web.woff2` | `3d5c02bfee2f0c139e8bc88553cc4faa` | served bytes |
| `fonts-claude-ai/Anthropicons-Variable.woff2` | `5c531978c77d0d8b075705c7975ee1e8` | served bytes |
| `fonts-ttf/Anthropicons-Variable.ttf` | `1839a4a24c7cfff9902ef530116ae7da` | converted |

`JetBrainsMono-Regular.woff2` (md5 `4e0581ae831b349f3f42c0f58d344122`, 1743 glyphs / 1363
codepoints, OFL-1.1) sits in the same directory because anthropic.com serves it for code
blocks. It is not an Anthropic asset and is excluded from every package here.

### 1.2 The pinned digests

`pkgs/fontbuilder/data/sources.sha256` pins **14** files: the 7 decompressed TTFs the
press actually reads, plus the 7 served woff2 as an independent second witness on
provenance. Every one of the 7 woff2 decodes table for table identically to the
corresponding TTF, so pinning them costs nothing and proves the conversion. Stage S0
checks all 14 and exits **2** if any is missing or altered.

```
da959cd930a15102fc1138b21317bc3de24991ff81cbdfadf8d54104519a3020  fonts-ttf/AnthropicMono-Roman-Web.ttf
1701d8e3c63cc8489009669754e278105ca6ceb3206d450470106fe16cc640ec  fonts-ttf/AnthropicMono-Italic-Web.ttf
e9daa8ffee811a5d30e0461d274088fe681107006983619bb2ebac57aa3ec94b  fonts-ttf/AnthropicSans-Roman-Web.ttf
645fd46a169148d33ec58fe3237328765aab810acf34a310a65ba7666cc8aaa5  fonts-ttf/AnthropicSans-Italic-Web.ttf
7db0d8f434869d8bae097736909828d900304cb36360f8e8575b7313d84fe618  fonts-ttf/AnthropicSerif-Roman-Web.ttf
a964c2bdd5720fcb5019cf1be730153c55b744e0a9e6637316c1866f9024dc92  fonts-ttf/AnthropicSerif-Italic-Web.ttf
ffbfbd32a75d7a60eb4a01e0b0e8ac061b1af40c8a2001411eb592f86a6bbffb  fonts-ttf/Anthropicons-Variable.ttf
49b8b95c950b0bee7ecdf68cda9dd6908e980283c50dc570c401de1e683a22e5  fonts-anthropic-com/AnthropicMono-Roman-Web.woff2
58bc928b953cea2666c578222a0a7c4fba4b3eb1b07c840a38be00aaba325f85  fonts-anthropic-com/AnthropicMono-Italic-Web.woff2
1b75c8ee81a05fa77331366e9602b82072bb5223593c928a6488dfe6fd023f1b  fonts-anthropic-com/AnthropicSans-Roman-Web.woff2
ffcf21c4e9a729cbf4710401760434bb1d10bc7db244540e4af796d182c6817d  fonts-anthropic-com/AnthropicSans-Italic-Web.woff2
e96fe97bb7ba2190a9a227d27380e0c79894408bfc6acea5a511774d93a16f69  fonts-anthropic-com/AnthropicSerif-Roman-Web.woff2
7f61e32b5941ad6e5699aeb3e03390a43e5f04f3bff6a5853bed08c802596f83  fonts-anthropic-com/AnthropicSerif-Italic-Web.woff2
d9d306f171f6a3e36470a4481409a9e159926bb327044bee6e06f64d4b476288  fonts-claude-ai/Anthropicons-Variable.woff2
```

### 1.3 Anthropic Mono, measured

| property | value |
|---|---|
| glyphs / codepoints | 699 / 655 (44 unmapped: `.notdef`, `.dnom` digits, `colon.time`, `zero.slash`, the `.short`/`.alt`/`.salt`/`.stackupper` mark variants) |
| unitsPerEm | 2000 |
| axes | `wght` 300 / 400 default / 800 |
| advance | exactly 1200 on every glyph = 0.600 em |
| `post.isFixedPitch` | 1 |
| OS/2 panose | `[2,0,0,9,…]`, proportion 9 = monospaced |
| `achVendID` / `fsType` | `BSPK` / 0 |
| cmap | two subtables, both format 4: `(0,3)` and `(3,1)`. No format 12, so max codepoint U+FB02 and no supplementary plane |
| `nameID` 13 / 14 | absent |

Vertical system, identical Roman and Italic and shared with Sans and Serif:

| field | value |
|---|---|
| hhea ascender / descender / lineGap | 1985 / -515 / 0 |
| hhea advanceWidthMax | 1200 |
| OS/2 version | 4 |
| sTypo asc / desc / gap | 1985 / -515 / 0 |
| usWin ascent / descent | 1985 / 515 |
| sxHeight | 1080 = 0.5400 em |
| sCapHeight | 1440 = 0.7200 em |
| cap / x | 1.3333 |
| default line height | (1985 + 515 + 0) / 2000 = **1.250 em**, and it never moves |
| fsSelection | 192 = bit 6 REGULAR + bit 7 USE_TYPO_METRICS |
| underline pos / thickness | -200 / 100 |
| head bbox, Roman | x -463 to 1363, y -608 to 2182 |
| head bbox, Italic | x -541 to 1496, y -608 to 2182 |

hhea, sTypo and usWin agree, which is why USE_TYPO_METRICS is set and why the line box is
stable across every consumer.

`post.italicAngle` is **-10.0** on Mono, Sans and Serif italics and 0.0 on every Roman.

**cmap coverage by 256-block**, 655 total: U+00xx 191, U+01xx 161, U+02xx 29, U+03xx 24
(combining marks only, no Greek letters), U+1Exx 61, U+20xx 54, U+21xx 26, U+22xx 15,
U+23xx 18, U+24xx 1, U+25xx 35, U+26xx 4, U+27xx 7, U+2Cxx 2, U+2Exx 1, U+E0xx 21,
U+E1xx 2, U+FBxx 3.

Confirmed absent and needed: U+276F (the starship prompt chevron), U+276E, U+251C,
U+258F, U+2800, U+E0B0, U+F00C, U+03BB, U+0410. Confirmed present: U+2500, U+2502,
U+2514, U+2588, U+2192, U+2713, U+2717, U+2026.

**GSUB and GPOS.** Features `aalt ccmp dnom frac liga locl ordn sinf subs sups`; GPOS has
`mark` only, no `kern`, because it is monospaced. Scripts DFLT and latn with langsys
AZE, CAT, CRT, KAZ, MOL, NLD, ROM, TAT, TRK. **`liga` is a decomposition, not a ligature
set**: one MultipleSubst mapping `f_f` to `f f`, `fi` to `f i`, `fl` to `f l`. There is no
`calt` at all. The ligaturizer therefore starts on a clean slate and must add both `liga`
rules and `calt` from scratch; anything claiming to "preserve existing ligatures" would
preserve nothing.

**STAT.** Two design axes, `wght` (ordering 0) and `ital` (ordering 1). The Roman file
carries Format 1 wght values Light 300, Regular 400 (ELIDABLE), Medium 500, Semibold 600,
Bold 700, Extrabold 800, plus a Format 3 ital value 0.0 named `Roman`, ELIDABLE, with
`LinkedValue 1.0` (proper style linking), and `ElidedFallbackNameID` 2. The Italic file
names its wght values `Light Italic`, `Italic` (ELIDABLE), `Medium Italic`, `Semibold
Italic`, `Bold Italic`, `Extrabold Italic`, plus a Format 1 ital value 1.0 named `Italic`,
and `ElidedFallbackNameID` 17. The Italic STAT therefore says "Italic" twice for every
weight other than 400, which is defect 2.1 below.

### 1.4 Sans, Serif and Anthropicons

| face | glyphs / cmap | axes |
|---|---|---|
| Sans Roman | 713 / 625 | `wght` 300-800, `opsz` 16-48 |
| Sans Italic | 651 / 578 | same |
| Serif Roman | 747 / 633 | same |
| Serif Italic | 651 / 554 | same |
| Anthropicons | 792 / 307 | `wght` 400/400/700, `opsz` 12/20/32, `ANIM` 0/0/100, `ANM2` 0/0/100 |

**The italic cuts are not mirrors of their Romans.** Sans loses 62 glyphs and 47
codepoints in the italic; Serif loses 96 and 79. Record it so nobody chases a phantom
loss in the merge. The widely quoted "625/625/713" figure compares Web against Variable
**Romans** only.

Anthropicons is unlike everything else in the set: `nameID1` is `Anthropicons RVRN`,
`nameID2` `Regular`, and there is **no nameID 4, 6, 16 or 17**. upm is 1000 with every
advance exactly 1000, a full-em square, which makes it categorically wrong as a terminal
`symbol_map` source. Tables are GSUB (`rvrn` only), avar, fvar, gvar, glyf, cmap, head,
hhea, hmtx, loca, maxp, name, post, OS/2. There is **no STAT, no GPOS, no GDEF and there
are zero fvar named instances**. OS/2 ships `fsSelection 0`, `achVendID '????'`,
`sxHeight 0`, `sCapHeight 0`; hhea is 1000/0/0. Ink bbox runs y 47 to 952 with a median
glyph top at 878.

The icon set is a variable font with two custom **animation** axes: icons are animated by
interpolating an axis rather than by SVG or CSS keyframes.

---

## 2. Source defects, and what repairs them

Five defects, each measured, each repaired at a named stage.

### 2.1 STAT `' Italic'` doubling (Mono Italic, and Sans/Serif italics)

The Italic wght AxisValues already embed the word Italic; `updateFontNames` then appends
the ital=1 value's `Italic` again. Naive instancing produces
`AnthropicMonoWebWeb-LightItalicItalic`, `… -BoldItalicItalic`, `nameID4 = Anthropic Mono
Web Light Italic Italic`. Worse, weight 700 lands on subfamily `Bold Italic Italic`, which
is not RIBBI, so the instancer leaves `fsSelection 192` and the Bold Italic ends up
flagged **neither bold nor italic**.

Repair (S1, on the variable file so every instance inherits it): strip the `' Italic'`
suffix from the wght AxisValue name records. **5 records, not 6**: the wght=400 value is
named plain `Italic` and must stay. After the strip, weight 700 correctly comes out
`fsSelection 161` / `macStyle 3` and every PostScript name matches its fvar named
instance.

On the variable Sans and Serif the same strip must run on the **wght and opsz axes and
never on ital**: six opsz AxisValues also end in `' Italic'` (`Display Light Italic`
through `Display Extrabold Italic`) and would compose to a doubled Italic. Measured, 18
records stripped per Sans/Serif italic file and 5 per Mono italic.

### 2.2 The 37 phantom advance deltas (Mono Italic only)

37 combining-mark glyphs carry a bogus gvar phantom-point delta of +1200 on the wght
minimum master tuple `(-1,-1,0)`, so their advance interpolates away from 1200 below
weight 400:

| weight | advance |
|---|---|
| 400 | 1200 |
| 399 | 1212 |
| 350 | 1800 |
| 310 | 2280 |
| 300 | 2400 |

Affected: `uni0307 uni0308 uni030A uni030B uni030C uni030F uni0302 uni0304 uni0306
uni0311 uni0312 uni0313 uni0326 uni0327 uni0328 uni0331`, `gravecomb`, `acutecomb`,
`tildecomb`, `dotbelowcomb`, `uni0327.alt`, `uni0328.alt`, `uni030C.salt`, and the 13
`*.short` variants. **The Roman source has zero advance-varying gvar deltas at any
weight.** The defect is wght=300-only on the Italic (400 through 800 already measure
`{1200: 699}`), so exactly one of twelve faces is at risk, and it is the one that flips
the fontconfig verdict.

User-visible consequence: `fc-scan --format '%{spacing}'` on the Light Italic reads **90
(FC_DUAL)** instead of **100 (FC_MONO)**. A dual-spaced face is not a monospace face to
fontconfig. The already-shipped `fonts-static/AnthropicMono-LightItalic.ttf` carries the
identical defect, which is the canary.

Repair (S1): zero the last four coordinate pairs (lsb, advance, top, bottom phantom
points) of every gvar tuple. Outline points untouched. A second, independent belt-and-
braces hmtx clamp runs after instancing; measured at wght=300, raw versus repaired differ
in 37 advances and nothing else (0 lsb differences, 0 outline-coordinate differences
across all 699 glyphs). **Keep both, but never cite the clamp's `advances repaired=0` as
proof the repair worked**: it would mask the repair's removal. The real regression test is
the negative control, instancing the unrepaired source at wght=300 and asserting
`{1200: 662, 2400: 37}` and `%{spacing}` 90.

S1 refuses to run on a non-monospace font. Pointed at Sans it exits 1 with
`repair_source: refusing to zero phantom deltas on a non-monospace font (advances=[0,
100, 200, 216, … 13510])`.

### 2.3 Doubled-`Web` PostScript names

The Web cut's PostScript names carry the generation token twice:
`AnthropicSansWebWeb-TextRegular`, `AnthropicMonoWebWeb-Regular`. Beyond the canonical
nameID 6, the bug also lives in the **fvar instance PostScript-name records**: 12 per
Sans/Serif face and 6 per Mono face, **60 records across the six variable files**. Those
are the names an OS or a browser reports for an instantiated named instance, so they must
be rebuilt as `ps_family + '-' + instance_subfamily_without_spaces`, giving
`AnthropicSans-TextLightItalic`. Without a garbage-collect pass afterwards the orphaned
private records still carry `Web` and still ship: measured 12 dead `AnthropicSansWebWeb-*`
records per Sans/Serif file and 6 per Mono file.

### 2.4 The missing ITALIC bit on the variable row

Every italic variable file ships `fsSelection 192` (REGULAR + USE_TYPO_METRICS, bit 0
clear) and `head.macStyle 0`. Only `post.italicAngle -10` and `nameID2 Italic` mark it as
italic at all. The twelve **named-instance** rows report `slant 100`; the **variable** row
reports `slant 0`, and Chrome, GTK and every variable-axis consumer read the variable row.

Causal isolation on six single-change variants pins the load-bearing bit exactly:

| change | variable-row slant |
|---|---|
| `fsSelection` bit 0 only | **100** |
| `head.macStyle \|= 2` only | 0 |
| `post.italicAngle = -10.0` only | 0 |
| `nameID2` only | 0 |

FreeType derives `FT_STYLE_FLAG_ITALIC` from `head.macStyle` only when `os2.version ==
0xFFFF`, which is never true here. The repair sets `macStyle 2` anyway for OS-spec and
DirectWrite correctness, and **asserts** `italicAngle` rather than claiming to repair it:
both Web italic sources already ship `-10.0` and setting it changes nothing.

Rendering consequences of leaving it unrepaired, both measured: Pango renders an
**upright** request at +9.70 degrees (the italic file wins an upright variable query on
filename order), and Chrome puts +22.99 degrees of synthetic oblique on outlines that are
already italic.

### 2.5 The Serif fvar default at 300

Serif Web Roman and Italic ship `wght` default 300 and `usWeightClass 300`, with
`nameID1 = Anthropic Serif Web Text Light`. Serif Variable defaults to 400. Sans defaults
to 400 in both generations.

The scope of the damage was overstated once and understated once; the measured truth is
split by query level:

- **Family query unaffected.** `fc-match 'Anthropic Serif'` returns the named instance
  `Text Regular`, weight 80, index 131072, before and after the repair. A Pango A/B at 24
  px is mean gray 0.884472 versus 0.884773, RMSE 3.07%, which is pure gvar re-rounding.
- **Face-level queries are broken without it.** Unrepaired, the file's index-0 record is
  advertised as family `Anthropic Serif`, style `Regular`, PostScript
  `AnthropicSerif-Regular`, fullname `Anthropic Serif Regular`, **at weight 50**. So
  `fc-match 'Anthropic Serif:style=Regular'`, `fc-match
  ':postscriptname=AnthropicSerif-Regular'` and `fc-list` all hand back a Light face, and
  index 0 renders Light: 500 ink px / mean 0.861 against the repaired 516 / 0.826, RMSE
  **42%**. That is exactly the path a CSS `local("AnthropicSerif-Regular")` takes in
  Chrome and Firefox on Linux, which the webfont sheet's `local()`-first rule depends on.

Repair (S9, Serif only): `instantiateVariableFont(f, {'wght': (300,400,800)},
inplace=False, updateFontNames=False)` then `usWeightClass = 400`. The axes come out
`('wght',300,400,800)` and `('opsz',16,16,48)`, all 12 named instances survive with
identical coordinates, STAT keeps its 19 AxisValues. Pass `optimize=False`: measured, True
gives TTF 622,644 B / woff2 180,868 B and False gives TTF 659,136 B / woff2 **175,628 B**,
with outline accuracy identical at worst point delta 0.500 either way. The woff2 is the
artifact actually served and the TTF ships inside a zstd -19 tarball, so the smaller woff2
wins and gvar is left as authored.

Moving an fvar default is not free and the once-stated "bbox-identical to the untouched
source" claim is **false**: it rewrites 432 of 747 base outlines and rebases gvar from
7,688 to 10,359 tuples. Over a grid of wght {300,400,500,600,700,800} x opsz {16,24,32,48}
against the same instances of the untouched source: contour structure identical, every
control point within 2 units at 2000 upm (worst 1.5015), every raw glyph bbox within 1
unit (worst 0.5000), every advance within 1 unit (worst exactly -1 unit on 93
glyph-instances, concentrated at **wght 600**). A 3x2 grid at opsz=16 passes vacuously
while 283 glyphs have moved, and comparing `tuple(round(x) for x in bounds)` produces 742
false failures because banker's rounding flips at half-integer coordinates.

### 2.6 The one defect that is not repaired, because the files are discarded

`fonts-static/` (60 files) is unusable. All 12 Mono statics carry identical nameID 1/4/6/
16/17: every Roman claims `AnthropicMonoWebWeb-Regular` and every Italic claims
`AnthropicMonoWebWeb-RegularItalic`; only `usWeightClass` and `post.italicAngle` differ.
Six files claim one PostScript name and fontconfig keeps exactly one. The Sans and Serif
statics collapse the same way, and their Display/Text distinction is fictional:
`AnthropicSans-DisplayBold.ttf` and `-TextBold.ttf` both report `nameID1 = Anthropic Sans
Web Text` and `nameID6 = AnthropicSansWebWeb-TextRegular`. The opsz pin was applied and no
name was changed. The press re-instances from the variable sources instead.

---

## 3. Names: the arithmetic, and the resolver that reads them

### 3.1 The 31-character ceiling

`nerd-font-patcher --makegroups 4` enforces hard limits. Measured across all 12 packaged
faces:

| nameID | patcher limit | worst observed | headroom |
|---|---|---|---|
| 1 family | 31 | 27 `AnthropicMono NFM ExtraBold` | 4 |
| 2 subfamily | 31 | 11 `Bold Italic` | 20 |
| 4 full | 63 | 34 `AnthropicMono NFM ExtraBold Italic` | 29 |
| 6 PostScript | 63 | 32 `AnthropicMonoNFM-ExtraBoldItalic` | 31 |
| **16 preferred family** | **31** | **28 `AnthropicMono Nerd Font Mono`** | **3** |
| 17 preferred subfamily | 31 | 16 `ExtraBold Italic` | 15 |

**nameID 16 is the tightest margin, not nameID 1.** Any family name longer than
`AnthropicMono` trips ID16 and the PostScript-family shortener before it trips ID1.
Negative control: renaming the family `AnthropicMonospaced` (two characters longer)
produces three `^ERROR` lines about over-length names and **exits 0**. Treat
`AnthropicMono` as frozen.

Two consequences that look like mistakes and are not:

- **`Liga` is absent from the family name.** `AnthropicMonoLiga Nerd Font Mono` is 32
  characters against a hard 31 ceiling. Ligature presence is proven by `hb-shape`, not by
  a substring. This is a visible departure from the `Liga SFMono Nerd Font` precedent.
- **`Web` is stripped in normalize, before any tool sees it.** `AnthropicMonoWeb Nerd Font
  Mono` is exactly 31 and would survive only for Regular and Bold, failing for every
  weight that appends a word.
- **The RIBBI Regular face carries no style suffix at all.** Its nameID 6 is
  `AnthropicMonoNFM` and its nameID 4 is `AnthropicMono NFM`. nerd-font-patcher 3.5.1
  introduced `FontnameParser._remove_regular`; 3.4.0 gave `AnthropicMonoNFM-Regular`. The
  Regular-weight **italic** is `AnthropicMonoNFM-Italic`, not `-RegularItalic`, and every
  other face keeps `-<Style>`. That is the patcher's own convention, the patcher is the
  last writer of names, and it is accepted as-is: kitty's `family=`/`style=` form does not
  depend on it. Anything that pattern-matches nameID 6 must therefore allow the bare
  family form.

Two normalize rules are load-bearing and were both learned the hard way:

- **nameID 4 on a non-RIBBI upright face is the family alone.** With `ID4 = 'Anthropic
  Mono Light Regular'` the patcher emits `AnthropicMonoNFM-LightRegular` and ID17 `Light
  Regular`; with `ID4 = 'Anthropic Mono Light'` it emits `AnthropicMonoNFM-Light` and ID17
  `Light`.
- **nameID 6 must contain exactly one hyphen.** Ligaturizer derives its output style
  suffix from `font.fontname.split('-')[1]`, and it writes its output to
  `path(output_dir, font.fontname + '.ttf')`. So `work/lig/AnthropicMono-<Style>.ttf` is
  the S6 input path **only because** the ID6 rule put one hyphen there and spelled the
  style with spaces removed. A driver that hardcodes that path will silently process a
  stale file if the naming rule ever changes. A family name containing a hyphen breaks it
  silently.

### 3.2 How kitty resolves a font setting

`find_best_match()` (`kitty/fonts/fontconfig.py:180-221`) looks the setting string up
**verbatim** in the nameID 6, nameID 4 and nameID 1 + 16 maps, and otherwise falls through
to `fc_match` with no warning. Whether `'<ID16> <Style>'` is a key at all depends on
nameID 4, and `--makegroups 4` caps nameID 4 at 31 characters, so this face's nameID 4 is
the abbreviated `AnthropicMono NFM SemiBold` (26 characters) while the long form is 37 and
can never be a key.

Measured on the real 12-face set under three fontconfig configurations:

```
                                            alias-free    live system          post-switch
family="…" style="SemiBold"                 NFM-SemiBold  NFM-SemiBold         NFM-SemiBold    <- ships
"AnthropicMono NFM SemiBold"  (= nameID4)   NFM-SemiBold  NFM-SemiBold         NFM-SemiBold
"AnthropicMono Nerd Font Mono SemiBold"     NFM-Bold(!)   LigaSFMono-SemiBold  NFM(!)
```

The shipped form resolves to
`{'medium':'AnthropicMonoNFM', 'bold':'AnthropicMonoNFM-SemiBold',
'italic':'AnthropicMonoNFM-Italic', 'bi':'AnthropicMonoNFM-SemiBoldItalic'}` in all three.
The medium role carries no suffix because patcher 3.5.1 removes `Regular` from the RIBBI
face's PostScript name (section 3.1); on 3.4.0 the same tuple read
`AnthropicMonoNFM-Regular`.

Two corrections to the failure mode as it was first written:

- **It does not degrade to `-Regular`.** `get_font_files` passes the real `bold` and
  `italic` flags, and `fontconfig.py:210-222` re-expands the single `fc_match` hit through
  `family_map` and runs `scorer.sorted_candidates`, so the result is the **right style of
  the wrong family**, which is much harder to spot by eye. The original measurement used a
  bare `find_best_match(q)` with `bold=italic=False`, which is not how kitty calls it.
- **"Wrong family" is not stable.** Under an alias-free config the forbidden form resolves
  to `AnthropicMonoNFM-Bold` (right family, wrong weight); after this suite's own
  `defaultFonts` commit it resolves to the plain `AnthropicMonoNFM` (right family, weight
  silently dropped). The only config-independent statement is *the forbidden form does not
  produce the expected four-tuple*. That is what the build gate asserts.

**Always measure roles with `get_font_files`, never with a bare `find_best_match`.** A
bare call defaults to `bold=False, italic=False` and will report a bold-italic role as
the upright Regular face on a font where it in fact resolves correctly. That mistake produced a phantom
"live bold-italic bug" that never existed: `bold_italic_font Liga SFMono Nerd Font
SemiBold Italic` resolves today, through `load_config` on the live file plus
`get_font_files`, to `LigaSFMonoNerdFont-SemiBoldItalic`.

### 3.3 The typo canary

The style string is matched exactly, lowercased. When the exact-match style filter
(`common.py:294-299`) empties the candidate list, `find_best_match_in_candidates` returns
`None` and kitty falls to `find_last_resort_text_font`, which is `fc-match monospace`,
**with no message**. Measured under the live system configuration: `style="Semi Bold"`,
`"Demibold"` and `"Italic SemiBold"` all resolve to `LigaSFMonoNerdFont-Bold`. Case and
internal capitalisation are safe (`"Semibold"` equals `"semibold"` equals fine).

`SemiBold`, `Italic` and `SemiBold Italic` are therefore load-bearing literals, and the
acceptance suite carries a typo canary.

**The canary's assertion is narrower than "resolves outside the Anthropic family",** and
the wider form must not be used. That wider claim holds only where a non-Anthropic
monospace wins kitty's last resort. It is false post-switch by construction, because the
`monospace` alias then prefers `AnthropicMono Nerd Font Mono`: measured in both the
alias-free and the post-switch configurations, `style="Semi Bold"` resolves to
**`AnthropicMonoNFM-Bold`**, so the typo silently costs two weights inside the right
family. The config-independent assertion is that the typo does **not** give the face the
correct spelling gives.

The same caution applies to the negative test on the forbidden long form. Asserting that
it fails to produce the four-tuple through `get_font_files` is a false failure under an
isolated configuration: with no other monospace family reachable, `get_font_files`
re-expands the single `fc_match` hit through `family_map` with the real bold and italic
flags and recovers the right faces anyway. That is the same mechanism that produced the
phantom bold-italic bug. The stable assertion is the bare call with kitty's own default
flags:

```python
find_best_match('AnthropicMono Nerd Font Mono SemiBold',
                bold=False, italic=False, monospaced=True)['postscript_name'] \
    != 'AnthropicMonoNFM-SemiBold'
```

The abbreviated nameID 4 forms (`AnthropicMono NFM SemiBold` and friends) do resolve, and
are recorded as a demoted second choice with two caveats attached: they work only inside
kitty's own `full_map` and are **not** fontconfig families (`fc-match 'AnthropicMono NFM
Italic'` returns `LigaSFMonoNerdFont-Regular.otf`), so they must never appear in
`fonts.fontconfig.defaultFonts` or a GTK `font-name`; and a future patcher release that
re-spells nameID 4 breaks every bare-string form while `family=`/`style=` survives.

---

## 4. Web against Variable: the honest discriminators

Three subset generations exist publicly. The suite takes the anthropic.com **Web** cut
(26.043.1) for all three text families.

| | Web (anthropic.com, claude.com) | Variable (console, docs, claude.ai) | Variable-25x258 (imagine, dead) |
|---|---|---|---|
| Sans R / I | 625 / 578 | 625 / 578 | 581 / 480 |
| Serif R / I | 633 / 554 | 633 / 554 | 567 / 443 |
| Mono R / I | 655 / 655 | 655 / 655 | none served |
| version | 26.043;BSPK | 26.179;BSPK | 25.258;UKWN |
| internal family | `Anthropic Sans Web Text` | `Anthropic Sans Variable Text` | `Anthropic Sans Text Light` |

**cmaps and glyph counts do not discriminate.** The claim that the Web cut has the fullest
cmap is misleading; the two generations are equal. The real discriminators:

| | Web | Variable |
|---|---|---|
| brand glyph names at U+E11A-E11E (`ASlash.pua`, `Anthropic.pua`, `Claude.pua`, `Spark.pua`, `Code.pua`) | **present** | absent |
| italic bits on the variable row | `fsSelection 0b11000000`, `macStyle 0` (broken) | `0b10000001`, `macStyle 2` (correct) |
| Serif `usWeightClass` / fvar default | 300 (broken) | 400 (correct) |
| PostScript names | doubled `Web` (broken) | clean |

The Web cut is chosen for the brand glyph names, and its three defects are exactly three
repairs the pipeline performs anyway. The Variable cut's advantages are therefore not
advantages in this pipeline.

**Mono is a special case: there is no separately named "Variable" Mono generation.** Both
Mono binaries carry the identical internal family `Anthropic Mono Web` and the identical
version 26.043, and a per-table and per-glyph byte comparison shows they differ in exactly
one glyph:

| | anthropic.com cut | claude.ai / console cut |
|---|---|---|
| `.notdef` contours | 20 | 3 |
| `.notdef` bbox | (0, 0, 1200, 1440) | (181, -1, 1019, 1501) |
| `.notdef` advance / lsb | 1200 / 0 | 1200 / 181 |
| `hhea.numberOfHMetrics` | 2 | 1 |

All 698 other glyphs, the whole cmap, GSUB, GPOS, GDEF, STAT, fvar and the name table are
byte-identical. Only glyf, gvar, head, hhea, hmtx and loca differ at all. Because both
claim one identity, shipping both would put two contending files under one family name.
The suite ships one.

---

## 5. Completeness: the donors

`--complete` alone is **not** completeness. The Nerd patcher's own sweep gives 11,192
codepoints but adds nothing outside its icon ranges plus Box Drawing (22 to 128) and Block
Elements (1 to 32): Greek stays 4, Cyrillic 0, Math Operators 15, Control Pictures 0,
Braille 0.

Host metrics the donor scales are measured against: upm 2000, cell 1200 (0.600 em), ink
x-height 1080, ink cap 1440, cap/x 1.3333.

| # | donor | nixpkgs attr | version | licence | faces | scale | resulting advance / cap | supplies |
|---|---|---|---|---|---|---|---|---|
| 1 | JetBrains Mono, from the NFM cut | `nerd-fonts.jetbrains-mono` | 3.5.0, JetBrains Mono 2.304 | SIL OFL-1.1 | 6 weights x roman+italic, 1:1 with ours | `1080/550 = 1.96364` | 1178.2 / 1433.5 (-0.45%) | Greek, Cyrillic + Supplement, combining diacritics, spacing modifiers, Latin Ext-B and IPA, Latin Ext Additional, Latin Ext-C, General Punctuation, super/subscripts, Currency, Letterlike, Number Forms, Math Operators, Misc Technical, Control Pictures, Enclosed Alphanumerics, Supplemental Punctuation, Math Alphanumerics U+1D400-1D7FF, and **U+276F** |
| 2 | DejaVu Sans Mono | `dejavu_fonts` | 2.37 | Bitstream Vera + Arev | 4 faces; heavy weights take `-Bold`, italics `-Oblique` | `1080/1120 = 0.96429` | 1189.0 / 1439.6 (-0.03%, the best metric match measured) | Arrows to 112/112, Geometric Shapes to 96/96, Misc Symbols 149, Dingbats 144 including **U+2718** |
| 3 | Maple Mono NF | `maple-mono.NF` | 7.9 | SIL OFL-1.1 | Thin to ExtraBold x roman+italic | **exactly 2.0** for braille, 1.92857 for the second pass | 1200 / 1480 | **Braille U+2800-28FF, all 256**, plus 16-18 further glyphs per face |
| — | Nerd Fonts, at S7 and last writer wins | `nerd-font-patcher` | 3.5.1 | MIT tool, per-glyph upstream | — | — | — | the full 160-glyph Box Drawing set, Block Elements, Powerline U+E0A0-E0D4, about 10,500 icons including the supplementary Material range U+F0001-F1AF0 |
| — | Fira Code, ligature art only, at S5 | pinned `fetchFromGitHub` | 3.001, rev `e9943d2d631a4558613d7a77c58ed1d3cb790992` | SIL OFL-1.1 | 6 OTFs | Ligaturizer's own 2000/1950 rescale | — | 136 `lig.N` and 205 `CR.x.y` glyphs, `calt` with 136 lookups |

The JetBrains donor path is `share/fonts/truetype/NerdFonts/**JetBrainsMono**/`, not
`…/NerdFonts/Mono/`; the package installs 96 files there in six variants. The merge
selects the **`JetBrainsMonoNerdFontMono-<Style>.ttf`** cut, whose advance is 600/1000 upm
= 0.600 em, exactly 2.0x to the Anthropic 1200/2000 cell.

### 5.1 Why the scale is ink-measured

JetBrains and Maple are both upm 1000 with advance 600, so a naive 2.0x is tempting.
Measured, it puts JetBrains' x-height at 1100 against Anthropic's 1080 (+1.85%) and its
caps at 1460 against 1440, which is visible in a mixed Greek and Latin line. The rule is
`s = xheight_host / xheight_donor` measured from each font's own drawn `x` bbox at build
time, never from OS/2: Maple's OS/2 says 550 and 730 while its ink tops at 560 and 740.

### 5.2 Braille takes exactly 2.0x, on cell-ratio grounds

Maple and the host both use a 0.600 em cell (600/1000 and 1200/2000), so 2.0x reproduces
the donor's ink-to-cell proportion exactly. It is the one scale that needs no
justification against the host's text metrics, because braille has no x-height and the ink
rule does not apply.

The alternative (`1080/560 = 1.928571`) costs **3.70%** in dot size and 6.8% in inked
pixels at kitty 16.0 pt / 192 dpi, while the rasterised dot-column centres are identical
(`[17.5, 27.5, 43.5, …]`, gap sequence `[10,16,10,15,…]` px) at both scales.

**Coordinate roundness is not a reason, and the claim that it was is retracted.**
Worst-case rounding at 1.92857 is 0.5 font units, which is 0.0107 px at 42.67 ppem, or
0.68 of a 1/64 px. A control build carrying twice that error on every coordinate moves
mean pixel coverage by 1.4% against the scale change's 27%, a 19-fold difference. It could
not matter in any case: Maple's U+28FF ships 127 bytes of hinting plus `fpgm`, `prep` and
`cvt`, all of which the pen-based merge drops, so nothing snaps the dots to the pixel grid.
"Lands the advance precisely on 1200" is also not a reason: the merge sets hmtx to the
cell unconditionally at every scale.

Maple's braille dot radius **is** genuinely weight-sensitive (U+2801 bbox
`(134,616,222,704)` at Thin against `(92,574,263,745)` at ExtraBold), so each of the 12
faces takes braille from its own weight.

**The braille y-offset is the thing that actually moves pixels, and it is a decision.** The
merge applies an x-translate only, so the grafted braille ink centre lands at 680 against
the host cell centre `(1985 - 515) / 2 = 735`: braille sits 1.17 px low in a 54 px cell at
16.0 pt / 192 dpi, about 1.5 times the donor's own bias. The suite ships **dy = +55**,
which centres it. The two rejected candidates were dy = 0 (as merged) and dy = +17 (which
reproduces Maple's own bias). It is an outline change and is baked into the hash, so it
was decided before the tarball was cut. kitty draws braille itself, so this affects Pango,
GTK and foot consumers only.

### 5.3 Iosevka and Cascadia, rejected

Iosevka Charon Mono won the coverage spreadsheet: 7,562 codepoints including 903 math
alphanumerics and 247 legacy-computing cells, and OFL-1.1. It is rejected on ratios. Its
cell is 0.500 and its cap/x is 1.4135 against this face's 1.3333. Scaling to match
x-height puts its caps at 1526 against 1440; scaling to match caps puts its x-height at
1019 against 1080. No uniform scale fits, and non-uniform scaling distorts stems. Cascadia
Mono is rejected on cell ratio alone (0.586).

### 5.4 Braille donor survey, and a correction to FONTS.md

`fc-list :charset=2800:spacing=100` returns exactly three families on this box: Cascadia
Code/Mono (0.586 cell, wrong), FreeMono (0.600, no weight range), and Maple Mono NF
(0.600, 256/256, 16 faces, already in `fonts.packages`).

**`FONTS.md` claims JetBrains Mono has full braille. It has zero, and so does every Nerd
Font.** That correction matters because it is the sentence that would otherwise send the
next reader to the wrong donor.

A second qualification: the "preferred braille donor, 256/256 including U+2800" claim is
true of Maple's **Roman** cuts only. All eight `MapleMono-NF-*Italic` cuts are 255/256:
`getBestCmap().get(0x2800)` returns `None`, the codepoint is absent from the cmap
entirely. Every Roman cut maps it to `nbspace`.

That also corrects the stated **cause** of the missing blank braille cell. It is an
italic-only donor-cmap hole, not "a copy path that skips empty outlines": there is no
donor glyph to inspect, so a rule conditioned on the donor glyph having no contours could
never fire. The merge therefore synthesises it and asserts:

```python
if 0x2800 not in hcmap:
    g = Glyph(); g.numberOfContours = 0; g.recalcBounds(hglyf)
    hglyf.glyphs['uni2800.synth'] = g; host.glyphOrder.append('uni2800.synth')
    hhmtx.metrics['uni2800.synth'] = (cell, 0); hcmap[0x2800] = 'uni2800.synth'
braille = sum(1 for c in range(0x2800, 0x2900) if c in hcmap)
assert braille == 256, 'braille %d/256 — U+2800 fix failed' % braille
```

In the shipped italics the Tier-4 upright pass supplies Maple's Roman `nbspace` first, as
`nbspace.mps`, so the synthesis is the guard and not the usual path. Both are needed.

### 5.5 The merge rules that are not obvious

**The oversize ceiling is per face and measured at run time.** Not a flat 1200:

```python
host_max_ink = max(hglyf[n].xMax - hglyf[n].xMin
                   for n in hglyf.keys() if hglyf[n].numberOfContours)
ceiling = max(host_max_ink, int(cell * 1.10))      # never tighter than 1320
```

The host's own glyphs exceed the cell: on the Italic, 61 glyphs pass 1200 with a maximum
of 1444 (`.notdef`) and `integral` at 1440; on ExtraBold Italic, 176 glyphs with a maximum
of 1538 (`dcaron`) and `slash` at 1522. The Nerd box-drawing set this same font ships
spans x -12 to 1212, ink 1224, precisely so that cells connect. Overhang beyond the
advance is normal in a monospace and is not a rejection criterion.

Measured with a flat 1200 rule: the Roman skipped 80 candidates and lost U+25D8, U+25D9,
U+25DA and U+25DB entirely (Geometric 92/96 against the required 96/96); the Italic
skipped 237 to 413 and per-weight totals diverged across 2,212 to 2,290 codepoints. With
the ceiling: Roman 96/96 Geometric and 112/112 Arrows with 20 to 25 skipped, all genuinely
double-width (U+2194 at 1492, U+27F5/6/7 at 1336-1492, U+2326/232B at 1610, all of which a
later donor supplies at cell width anyway); Italic 8 to 25 skipped and a flat 2,404 to
2,408 codepoints across weights.

**Measure the candidate on the unsheared outline.** The Tier-4 shear inflates ink width by
`tan(10°) x glyph height`, up to +325 units, so testing the sheared outline rejects glyphs
for being italic. Measured failure: U+019D on SemiBold Italic, unsheared ink 1131
(accepted) against sheared 1456 versus that face's 1444 ceiling (rejected), while
BoldItalic's 1487 ceiling lets the same glyph through. That is a weight-dependent coverage
lottery. With the fix, `cmap(roman_same_weight) - cmap(italic)` is **empty on all six
italics**, and U+0361 and U+03D3, genuine 1700-unit double-width marks, stay correctly
rejected. The cheaper approximation `width - tan·height <= ceiling` wrongly admits those
two and is not used.

**Tier 4 is two fall-throughs, not one.**

- **Slope fall-through, italics.** For any codepoint still missing after the three italic
  donors, take the upright counterpart and shear it by `Transform(s, 0, tan(10°)·s, s, dx0
  - tan(10°)·540, 0)`, pivoting at y = 540, half the 1080 ink x-height. That is
  independently verified as the host's own transform: fitting `x_italic(y) - x_roman(y)`
  point by point between the normalized Roman and Italic gives `bar` 9.99 degrees / pivot
  539.2, `exclam` 10.01 / 538.7, `colon` 9.99 / 539.3, `I` 9.97 / 534.2. Measured
  contribution per face: `dvs` 237 to 299, `mps` 1 (U+2800), and **`jbs` 0 on every
  face**, because JetBrains Mono Italic already covers everything its upright does in
  these ranges. The sheared JetBrains tier exists only as a safety net.
- **Weight fall-through, heavy faces.** SemiBold, Bold and ExtraBold come out **63
  codepoints short** of the light faces (U+1D670-1D6A3 mathematical monospace letters,
  U+1D7F6-1D7FF monospace digits, and U+038E) because `DejaVuSansMono-Bold.ttf` lacks the
  monospace math alphanumerics that `DejaVuSansMono.ttf` carries and the donor map sends
  every heavy face to the Bold cut. For any codepoint still missing after the
  weight-matched donors, take the **Regular-weight** donor glyph. Bold also gains one the
  Regular lacks, U+27BF.

**The TEXTISH range list includes four blocks that are easy to omit**: Latin Ext-C
(U+2C60-2C7F), Enclosed Alphanumerics (U+2460-24FF), Supplemental Punctuation
(U+2E00-2E7F) and Mathematical Alphanumeric Symbols (U+1D400-1D7FF). Without the last, the
U+1D538 coverage requirement cannot pass.

**Maple takes two passes.** Braille at exactly 2.0x, then the TEXTISH ranges at the ink
scale 1.92857, contributing a further 16 to 18 glyphs per face.

Mechanics: `ensure_format12()` before any supplementary-plane insert, otherwise
`array.array('H', …)` raises `OverflowError` at save time;
`DecomposingRecordingPen` over the donor glyph set, otherwise a composite referencing an
uncopied glyph produces a dangling component and crashes; `hmtx = (cell, xMin if contoured
else 0)`; `dx = (1200 - donor_advance·s) / 2` so the donor glyph is centred in the host
cell. **Host codepoints are never overwritten. The merge is strictly additive.**

### 5.6 Provenance suffixes

Every grafted glyph is renamed `<originalName>.<tag>`, so the shipped font carries its own
machine-readable donor manifest and `PROVENANCE.tsv` regenerates from the font with one
fontTools call over the `post` table. Nothing separate can drift.

| suffix | meaning |
|---|---|
| `.jb` | JetBrains Mono NFM, weight-matched, ink scale |
| `.dv` | DejaVu Sans Mono, weight-matched, ink scale |
| `.maple` | Maple Mono NF, braille at 2.0x or the second TEXTISH pass at ink scale |
| `.dvs` | DejaVu upright, sheared 10 degrees (Tier-4 slope fall-through) |
| `.jbs` | JetBrains upright, sheared (Tier-4; contributes 0 on every face) |
| `.mps` | Maple upright, sheared (Tier-4; exactly one glyph, the blank braille cell) |
| `.synth` | synthesised in the merge, currently only `uni2800.synth` |
| `.apua` | Anthropic PUA re-grafted after the patch (S7b, section 12) |

Named provenance for the **Nerd** glyphs additionally requires the `glyphnames.json`
override; without it the post table carries `uniE0B0` and `music.1` instead of
`pl-left_hard_divider` and `fa-music`.

### 5.7 Measured outcome

**At the merge stage**, which is fontTools only and therefore independent of the patcher
version:

| | Light / Regular / Medium | SemiBold / Bold / ExtraBold |
|---|---|---|
| Roman | 655 to **2,703 cp / 2,747 glyphs** | 655 to **2,641 / 2,685** |
| Italic, with Tier-4 | 2,704 cp | 2,404-2,408 cp before Tier-4 |

**Packaged**, from the unified press on nerd-font-patcher 3.5.1:

| face | codepoints | glyphs |
|---|---|---|
| Regular | **13,440** | **13,837** |
| Italic | **13,441** | **13,838** |
| the other ten | see the per-face table in section 10 | |

3.5.1 carries more icons than 3.4.0, on which the same Roman Regular measured 13,226 cp /
13,613 glyphs. Every packaged count therefore rose, and any figure quoted from the 3.4.0
prototype record is a floor, not the shipped value.

Per block, packaged: Greek 116 (115 on the heavy faces), Cyrillic 184, Arrows 112/112,
Math Operators 195, Control Pictures 36, Box Drawing 128/128, Block Elements 32/32,
Geometric Shapes 96/96, **Braille 256/256 including U+2800**. Those blocks come from the
merge and from the patcher's box and block art, so they are stable across the version
change.

cmap subtable structure, stable: `(0,3)` fmt4 and `(3,1)` fmt4 carry the BMP subset,
`(0,4)` fmt12 and `(3,10)` fmt12 carry the face's full codepoint count, `(1,0)` fmt6
carries 227 entries, and the maximum codepoint is 0xF1AF0. On the 3.4.0 chain the fmt4
subtables held 6,223 entries against 13,226 in fmt12.

Coverage is counted with `len(TTFont(f).getBestCmap())`, the stricter Unicode-only count,
**never** the all-subtable union: the union is inflated by the 227-entry `(1,0)` fmt6
subtable and would hide a regression of roughly 37 codepoints.

**Advance invariant.** The set of hmtx advances over the whole table, `.notdef` included
and with no exclusions, is exactly `{1200}` on all 12 faces. There is no zero-advance
glyph at all, so the customary `- {0}` carve-out is unnecessary and the strong form is
asserted; it would catch a future zero-advance donor glyph.

Per-glyph donor census on the final faces: Light, Regular and Medium `{jb: 695, dv: 1073,
maple: 273}`; SemiBold and Bold `{jb: 695, dv: 1012, maple: 272}`; ExtraBold `{jb: 693,
dv: 1012, maple: 274}`; packaged Italic `{dv: 770, jb: 698, dvs: 299, maple: 274, mps: 1}`
= 2,042 grafted glyphs.

**The italic coverage gap is per face, not uniform.** Without Tier-4 it is 299 / 299 / 299
/ 239 / 238 / 237 for Light, Regular, Medium, SemiBold, Bold and ExtraBold Italic. The
figure 238 is Bold Italic's number alone. With Tier-4 and the unsheared-measurement fix,
`cmap(roman) - cmap(italic)` is empty on all six.

On the 3.4.0 chain the heavy faces sat only **164 codepoints** above the 13,000
acceptance floor once the weight fall-through landed. 3.5.1's larger icon set widens that
margin, but the margin is a property of the donors and the patcher together, so **if a
donor is ever dropped, re-measure the worst face against the floor before trusting it.**

---

## 6. Ligature vertical alignment

### 6.1 Why

Anthropic Mono puts its math strokes on an axis at y = 720/2000 = 0.360 em, exactly half
its 1440 cap height. Fira Code, after Ligaturizer's rescale to em 2000, puts its at 637 to
645. For the hyphen: host centre 735, Fira 642, **delta 93 units**. At `font_size 16.0` on
a scale-2 output the em is 16 x 192/72 = 42.67 device px, so 93/2000 em is **1.98 px**
against a dash stroke only 158/2000 em = 3.37 px thick. The ligature dash is displaced by
about 59% of its own stroke weight. On a 1x output it is still 0.99 px. Raster
corroboration: the whole-line ink centroid of the arrow row moves 0.86 px between the
`none` and `anchor` renders.

### 6.2 Why not a single constant

Measured host against Fira y-centres:

```
hyphen      735 / 642.0 / +93        equal        720 / 637.5 / +82.5
plus        720 / 639.0 / +81        less,greater 720 / 643.1 / +76.9
asciitilde  720 / 644.6 / +75.4      colon        540 / 512.3 / +27.7
exclam      720 / 694.4 / +25.6      bar          664 / 615.4 / +48.6
period    162.5 / 156.9 / +5.6       slash        664 / 724.6 / -60.6
underscore -401.5 / -297 / -104.5    asterisk     968.5 / 694.4 / +274.1
```

A blanket +93 moves `__` further from its target and lifts `!=`'s exclamation and `#=`'s
hash off their baselines.

### 6.3 The algorithm, mode `anchor`

1. **Reconstruct the `lig.N` to spec mapping exactly.** `ligaturize.py` iterates
   `sorted(ligatures, key=lambda l: len(l['chars']))`, stable, and increments its counter
   only for specs whose glyph exists in the donor, naming the result `lig.{counter}` from
   1. Reproducing that gives a mapping verified glyph by glyph: all 136 `lig.N` bounding
   boxes match their claimed Fira source bbox scaled by 2000/1950, **0 mismatches of 136**.
2. **Per-ligature delta, measured from the two fonts at run time**, never hardcoded, so it
   is automatically right for every weight and for Italic:
   `dy(L) = mean over c in set(constituents(L)) of [ ycentre_host(c) - ycentre_donor(c) ·
   host_em/donor_em ]`.
3. **Anchor veto.** If any constituent is in `{numbersign, percent, w, dollar, braceleft,
   braceright, bracketleft, bracketright, parenleft, parenright, ampersand, at,
   underscore, backslash, asterisk}` then `dy = 0` and Fira's drawing is kept verbatim.
4. **Clamp.** `|dy| > 0.08 em` skips and logs.
5. **Apply** as a pure y-translate of the glyf coordinates through `TTGlyphPen` and
   `TransformPen`. Advance stays 1200. **lsb is left untouched on the Roman path and set
   to `xMin` on the sheared italic path**: without that, FontForge inside the patcher
   re-seats each outline so `xMin == stored lsb` and translates every sheared ligature
   horizontally by up to 120 units, 0.06 em. Measured 136 of 136 outlines moved before the
   fix, 0 of 136 after.
6. **Italics, `--slant 10`:** shear every `lig.N` by `tan(10°)` about y = 540. Exact model
   check on the built faces: residuals of `x' = round(x + tan10·(y+dy-540)), y' = y+dy`
   over every point are `{(0,0)}`; on the packaged face the `||` stem angle is 10.00
   degrees against the host's own `bar` at 9.99 and `post.italicAngle -10.0`.
7. Write a per-face JSON report of every decision.

### 6.4 Measured outcome

**Identical on all 12 faces: `{shift: 100, anchor-veto: 35, clamped: 1}`.** The single
clamp is `asciicircum_equal` at dy about -164 to -168, more than 0.08 em, correctly left
alone.

**The dy histogram is -61 to +93, not a +76 to +93 band.** Regular, measured:

```
-61×2 (slash, self-correcting), 6,8,11,15,16,21,25,26,28,31,41,44,49,52,54,55,63,65,66,67,
69,71,73,75, 76×5, 77×5, 78, 79×4, 80×11, 81,82,83,84, 85×12, 93×2
```

**63 of the 100 shifts fall below +76.** Ranges on the other faces: -60 to +93 on Medium,
SemiBold and the italics, -59 to +93 on Bold and ExtraBold. The acceptance test asserts
the range, not a band.

**"Vetoed ligatures are untouched" is true for the Roman only.** On the six italics the
`--slant` pass shears all 136 `lig.N` glyphs, veto or not: measured, vetoed glyphs
unchanged 0 of 35 on the Italic and 36 of 36 on the Roman. That is correct, because the
sheared `__` matches the host italic underscore's own lean (the host underscore moves from
Roman 100…1100 to Italic -76…945, implying a pivot of 518 to 556 against the stage's 540,
about 20 units or 0.4 px of agreement). State the claim as: *the anchor veto leaves the
outline shape untouched; on italics the uniform shear still applies.*

### 6.5 The residuals the stage does not fix, measured and accepted

The veto is all-or-nothing on the whole ligature, so one constituent stroke can land on
two different axes inside the same face:

| stroke family | measured split | at 16 pt / 192 dpi |
|---|---|---|
| `bar` in `\|\|` (shifted +49, centre 664.0) against `{\|`, `\|}`, `[\|`, `\|]` (vetoed, centre 718.0) | **53.0-53.5 units**, identical on all 12 faces | 1.14 px against a 3.2 px stroke = **35% of its own weight** |
| `equal` in `==` (+83, centre 720.75) against `#=` (vetoed, pair centre 654.0) | **66.75 units** | 1.42 px |
| `underscore` in `__` (vetoed) against the host `_` | **104.5 units** | 2.2 px |

Two further corrections to the stated rationale. The anchor set was described as
"precisely the glyphs whose delta is small or opposite-signed"; that is false for 6 of the
15 members. `braceleft`, `braceright`, `bracketleft`, `bracketright`, `parenleft` and
`parenright` all measure delta **-53.9**, the same sign and magnitude as `slash` at -60.6,
which the rule does shift. And `backslash` at -60.6 is numerically identical to `slash`
yet vetoed, so `//` is corrected while `\/` and `/\` are not. 16 of the 35 vetoed
ligatures have a would-be `|dy| >= 40`.

**Resolution: document and accept, with a regression pin.** The alternative is
re-specifying the metric as a per-contour stroke reference, which is a design change and a
new hash. The acceptance suite carries a cross-ligature consistency assertion with **TOL =
70 units**, which pins the known state and catches a regression. Tightening it is a metric
redesign, not a bug fix. Drop the word "coherent" from any summary of this stage.

Secondary note for whoever revisits the metric: the delta is the full glyph bbox centre,
which is not the stroke axis for multi-part glyphs. The host `exclam`'s full-bbox centre
is 720.0 but its stem centre is 946.0, and `#!` (vetoed) already has its stem at 947.5, so
that veto is right for the wrong reason, while `!=` was shifted +54 on a dot-plus-stem
average. The same holds for colon, question and percent.

### 6.6 Modes, and what is documented but not fixed

`--mode anchor` is the default and ships. `--mode none` keeps Fira's art as copied, which
is the honest fallback and is identical in character to the Liga SFMono Tom reads today;
the shear still applies on italics. `--mode dash` was specified once and is dropped,
unwritten and unused. The builder emits `specimens/align-none.png` and
`specimens/align-anchor.png` from one run so the choice is made by looking.

ExtraBold ligatures use `FiraCode-Bold`, whose dash is 252.3 against Anthropic's 300, a
47.7-unit shortfall of about 1.0 px. Fira Code ships nothing heavier. kitty uses Regular
and SemiBold, so this is cosmetic and is not fixed.

Per-weight Fira donor map, chosen by measured dash-stroke thickness at 2000 upm:

| weight | donor | host / Fira dash | delta |
|---|---|---|---|
| 300 Light | `FiraCode-Light.otf` | 120 / 119.0 | -1.0 |
| 400 Regular | `FiraCode-Regular.otf` | 158 / 149.7 | -8.3 |
| 500 Medium | `FiraCode-Medium.otf` | 184 / 188.7 | +4.7 |
| 600 SemiBold | `FiraCode-SemiBold.otf` | 216 / 215.4 | -0.6 |
| 700 Bold | `FiraCode-Bold.otf` | 256 / 252.3 | -3.7 |
| 800 ExtraBold | `FiraCode-Bold.otf` | 300 / 252.3 | -47.7 |

Italics take the same upright donor as their weight; Fira Code ships no italic and the
slant is applied at S6.

Two of 138 ligature specs are absent from Fira 3.001 and silently skipped
(`asciitilde_equal`, `question_colon`), so 136 land. `calt` is registered only for a
hardcoded langsys list omitting AZE, CRT, KAZ, NLD, TAT and TRK; the currently installed
Liga SFMono has the identical hole and terminals shape with `dflt`, so it is harmless.

---

## 7. Anthropicons

The face is packaged as a single static pinned at `wght=400 opsz=20 ANIM=0 ANM2=0`, with
the name table it entirely lacks synthesised: nameID 1 `Anthropicons`, 2 `Regular`, 3
`Anthropicons Regular; <version>`, 4 `Anthropicons Regular`, 6 `Anthropicons-Regular`, 5
`Version 1.000`. `OS/2.version` is bumped from 3 to 4 **before** touching fsSelection bits
7 and 8, or fontTools warns. Then `fsSelection = REGULAR | USE_TYPO_METRICS`,
`usWeightClass 400`, `sxHeight 540`, `sCapHeight 720`, `post.isFixedPitch 1`. `achVendID`
is left as found rather than inventing a vendor.

**The x-height and cap-height values are 540 and 720, not 1080 and 1440.** Anthropicons is
**1000** upm, measured: `head.unitsPerEm 1000`, ink bbox y 47 to 952, median glyph top
878, every advance exactly 1000. Putting 1080 there would place the x-height above the em
square and break x-height-matched fallback and CSS `font-size-adjust`. 540 and 720 are the
text families' own 1080/2000 and 1440/2000 ratios expressed at 1000 upm, so an icon sits
optically level with Anthropic Sans.

Measured result: `fc-scan` reads `Anthropicons|Regular|80|0|100|False`, OS/2 version 3 to
4, fsSelection `0b11000000`, 792 glyphs / 307 cmap, `rvrn` resolved away in the pinned
static and retained in the variable webfont cut.

**Installing Anthropicons changes no font resolution.** Swept over all 309 codepoints
U+E000 to U+E134 crossed with six query forms, with and without the face present, under
both the pre-switch and post-switch default-fonts configuration: **1,854 rows each, 0
differences and 0 Anthropicons wins**. kitty's own `get_fallback_font` agrees. The face is
provably inert, so dropping it from the UI tarball is not a lever for any PUA problem.

**The icon-to-codepoint mapping is not recoverable. Do not re-run the search.** The
original sweep covered `bundles/*.js` and three CSS files; it was widened to the whole
capture, **84 text files**, and found zero raw PUA characters, zero `\uEXXX` escapes and
zero CSS `\eXXX` escapes. Two hits must be named so nobody reopens it:
`claude-code-theme/claude-theme-bundle-source.js` uses PUA characters as
**streaming-markdown sentinels**, spliced in and then stripped; and several `wayback/`
files are binaries and GIFs misread as UTF-8. The only reference anywhere is
`document.fonts.load('16px "Anthropicons-Variable"')` plus the `@font-face` rule, and the
font's own glyph names are `uniE0xx` and `glyphNNNNN`.

**The brand PUA glyph names do not transfer.** The Web cut carries five brand glyph names
at U+E11A to U+E11E, and it is tempting to read them across onto the icon face at the same
codepoints. They are different drawings at different scales: the text-face glyphs are wide
logotype lockups (`Anthropic.pua` 6.635 em, `Claude.pua` 3.389 em, `Code.pua` 2.472 em)
while the icons at those codepoints are 0.51 to 0.81 em squares. Nothing transfers.

Delivered instead: `docs/anthropicons-map.json` with 307 entries (codepoint, character,
glyph name, ink bbox in em, sheet index, per-face collision record, and the search
evidence) and a rendered 307-cell labelled contact sheet with the 50 colliding cells
outlined. A visual naming pass off that sheet is the only remaining route, and nobody has
done it.

---

## 8. The webfont CSS contract

`css/anthropic-fonts.css` declares **two identities per face**, 18 `@font-face` rules
total:

1. the normalized families this repo installs, `Anthropic Sans`, `Anthropic Serif`,
   `Anthropic Mono`, `Anthropicons`, so a local page and the desktop render from one name;
2. the product's own lowercase families recovered verbatim from
   `capture/bundles/c6a992d55-B5RomVEQ.css`: `anthropic-sans`, `anthropic-serif`,
   `anthropic-mono`, `Anthropicons-Variable`, with `font-weight: 300 800`, `font-display:
   swap`, `font-feature-settings: "dlig" 0` on Sans, and the four metric-matched Serif
   fallbacks (`Anthropic Serif Fallback DejaVu / Georgia / Noto / Times`) copied as-is
   with their `size-adjust`, `ascent-override`, `descent-override` and `unicode-range`. A
   page copied out of the product renders unchanged.

`src` is relative (`url("../woff2/<file>") format("woff2")`) so `css/` and `woff2/` move
together. `local()` is listed first so an installed desktop face is used with no download.
`font-display: block` for Anthropicons, because an icon font that swaps shows a flash of
wrong glyphs; `swap` for text.

**Three deliberate deviations from the product CSS, each stated in the file header:**

| | product | here | why |
|---|---|---|---|
| Anthropicons format hint | `format("woff2-variations")` | `format("woff2")` | the hint is deprecated, ignored by current engines, and dropped from the CSS Fonts 4 draft |
| `anthropic-mono` weight range | `font-weight: 400` | `font-weight: 300 800` | the served Mono woff2 **is** a `wght` 300-800 variable font; 400 still resolves to 400 and 700 now gets the drawn bold instead of a synthesised one |
| `Anthropic Mono` `local()` | — | **omitted on purpose** | see below |

**The no-`local()`-for-Mono carve-out.** The suite deliberately does not install a desktop
`Anthropic Mono` TTF, and the installed mono family is the **patched** `AnthropicMono Nerd
Font Mono`: a different cell (0.600 x 1.250 em), 136 ligatures, roughly 11,000 Nerd glyphs.
A `local("AnthropicMono Nerd Font Mono")` in these rules would make a web page render
differently depending on whether the terminal package happens to be installed. The Mono
rules therefore carry no `local()` at all.

**The original served woff2 bytes are not shipped.** All 7 decode identically to the TTFs
already pinned, would add about 822 KB, and would put a second contending identity under
`share/webfonts/`: `fc-scan` parses them and returns `Anthropic Sans Web` and `Anthropic
Mono Web` with exit 0. Their sha256 go in `manifest.json` and in `sources.sha256` instead.

**The woff2 emitted here round-trip exactly.** All 7 were decoded and diffed against a
full table snapshot of their TTFs: glyphOrder, numGlyphs, every cmap subtable, every name
record, GSUB and GPOS counts, fvar axes and instances, STAT, gvar, hmtx, head, OS/2, hhea,
post, all identical. Sans Roman compresses 318,704 to 118,404 bytes, 37.2%.

The `fc-scan`-parses-woff2 hazard is the reason for the fontconfig glob reject. A
`fontformat`-based reject **cannot** work: `fc-scan %{fontformat}` on these files reads
`TrueType`, not `WOFF2`, because FreeType decompresses transparently, so the NixOS
`53-nixos-reject-type1.conf` pattern form matches nothing. The working form is globs:

```xml
<selectfont><rejectfont>
  <glob>*/share/webfonts/*</glob><glob>*.woff2</glob><glob>*.woff</glob>
</rejectfont></selectfont>
```

Verified on a mixed tree: `fc-list` drops to exactly the 2 control TTFs and `fc-match
'Anthropic Sans:italic'` no longer reaches the woff2. The hazard it prevents is real and
order-dependent: with a config whose only `<dir>` is a package store root, which is exactly
what `fonts.packages` produces, `fc-list` returns the 2 TTFs **and all 7 woff2** from
`share/webfonts/` three levels down, 68 pattern rows; and with the webfonts directory
scanned before `share/fonts`, `fc-match 'Anthropic Sans'` returns the **.woff2**, beating
the byte-equivalent TTF purely on directory order. It is not cosmetic: `pango-view
--font='Anthropic Serif 20'` under that config rasterises from the woff2.

When demonstrating the hazard, use the `fc-list` directory-scan form. `fc-scan <file>`
bypasses `<selectfont>` entirely and proves parseability, not indexing.

---

## 9. What was deliberately not done

| not done | why |
|---|---|
| a desktop variable `Anthropic Mono` TTF | the webfont Mono covers the web case; installing a second mono family buys nothing and adds one more name to the fontconfig namespace |
| shipping both Mono generations | they carry the identical internal family and version and differ only in `.notdef`; two files would claim one identity |
| sweeping U+2500-257F and U+2580-259F in the merge | the patcher owns box drawing and block elements at S7 and draws them to span the cell, so boxes connect |
| sweeping CJK, Hangul, Arabic, Devanagari, emoji | out of scope for a terminal face; NixOS appends its own Noto fallbacks after `defaultFonts`, so they resolve with no `symbol_map` at all |
| sweeping U+000D, U+FEFF, U+0AEA, U+16910 | non-printing, or orphan singletons with no block behind them |
| a `symbol_map` line for braille | kitty draws braille itself before `symbol_map` is consulted, so the line is inert; and a commented inert line misleads. Mapping braille to a font with zero braille glyphs leaves the sprites byte-identical to the baseline |
| `--careful` on the patcher | it preserves the PUA but stops the patcher redrawing cell-filling box and block art: U+2588 becomes `(-50,0,1250,1440)` instead of a cell-spanning box, so full block would no longer fill the cell |
| enumerating icon sets to omit Pomicons | `FontnameParser` then appends every set name, yielding a 183-character nameID 16 and `ERROR` lines |
| grafting U+E00D, U+E00E, U+E010 from Anthropicons | they exist in no Anthropic text face; kitty picks them up from `Inter-Regular` at 0.441 em in a 0.600 em cell. A cheap fix exists in the merge and was deliberately not taken until someone actually sees one |
| fixing the ligature residuals of section 6.5 | it means re-specifying the delta metric as a per-contour stroke reference: a design change and a new hash |
| a second normalize pass after ligaturize | Ligaturizer visibly damages the name table, and the patcher rebuilds the whole table from ID16/ID17 anyway. Measured: patching the as-is file and a re-normalized copy produce **identical** name tables and bits for both a non-RIBBI and a RIBBI face. Adding the stage is redundant, and dropping ID16/ID17 in it would break the rebuild |

---

## 10. Verification transcript

Per-face, from the final press:

| face | codepoints | glyphs | bytes | sha256 |
|---|---|---|---|---|
| AnthropicMonoNerdFontMono-Bold.ttf | 13440 | 13837 | 2785876 | `76a8d008b090458c10da7174eb3f7fffc43a19b82d9b5466ddc8abc3539ff576` |
| AnthropicMonoNerdFontMono-BoldItalic.ttf | 13444 | 13841 | 2801356 | `825c197e039968f60bed40e42284017482acce209243ca122f3ce3eaebc0bf9f` |
| AnthropicMonoNerdFontMono-ExtraBold.ttf | 13440 | 13837 | 2786684 | `ceb3a25d31bffc288843189d32bcb6f6b97fff126299036ce690842d8f8cf6f7` |
| AnthropicMonoNerdFontMono-ExtraBoldItalic.ttf | 13444 | 13841 | 2800688 | `af0d454855770a098250f3c63728a6da3b23f0483fe432e1b0e14244ade4dfa7` |
| AnthropicMonoNerdFontMono-Italic.ttf | 13441 | 13838 | 2800680 | `93adadd2383ac0b357a9d9f98e1aad5ec9b253fd2af2f8460880f60654d5981b` |
| AnthropicMonoNerdFontMono-Light.ttf | 13440 | 13837 | 2786256 | `514077623a7d3a9afa3249767c9f990ea2f99e374428d552c79b858e4a5718c6` |
| AnthropicMonoNerdFontMono-LightItalic.ttf | 13441 | 13838 | 2801164 | `d358ee742d15d6ac5e6b75dc87396d231474d5f5fc17903a75b714d7043eea60` |
| AnthropicMonoNerdFontMono-Medium.ttf | 13440 | 13837 | 2785620 | `d760859b37da9f58a75e318e0d2198cc9030d2cbe66a688d1c610ccd806d793c` |
| AnthropicMonoNerdFontMono-MediumItalic.ttf | 13441 | 13838 | 2800844 | `dbb5756082d07fbb06cb33f4f5d4e6193b2950742b077d135207fdc54504748e` |
| AnthropicMonoNerdFontMono-Regular.ttf | 13440 | 13837 | 2785692 | `4896728b8b7913b500c012222b5dca2a9f7148cd5a987ddb70bb6e21e1f072b1` |
| AnthropicMonoNerdFontMono-SemiBold.ttf | 13440 | 13837 | 2785628 | `8e7d81ff8a07dfde2d75056b94967695e3fb151085e3db14fe06338737e0ca11` |
| AnthropicMonoNerdFontMono-SemiBoldItalic.ttf | 13442 | 13839 | 2800948 | `6ff2cb00a1ae35f8047e3c0fc2839a1a405c27d200ba5d571ba6ac756534daf0` |
| AnthropicSans-Italic.ttf | 578 | 651 | 331560 | `10b39db62f0d5c5a2020245808277ba10efddba6392b8eb4bf8b5e3bee5b3270` |
| AnthropicSans-Roman.ttf | 625 | 713 | 318704 | `0e201dba8b69124f3f3eabdcc13240f15f5ee89fa4d34488097f9364e2af6d93` |
| AnthropicSerif-Italic.ttf | 554 | 651 | 605000 | `7841e54fd4f57633640424dd625745aeb6a6f52f8cc2f6e36b58ff582dbb0423` |
| AnthropicSerif-Roman.ttf | 633 | 747 | 659792 | `246e99c250792f804b3b4b866e8132114826c37038c5878ec51e7b73c41b3959` |
| Anthropicons-Regular.ttf | 307 | 792 | 199968 | `519197cf467ea8b15a722765a24dddb25bb88abb3503a87d12d01f7a63055082` |
| AnthropicMono-Italic.woff2 | 655 | 699 | 70424 | `9b5306604715f65fe947ff7977534e639d29926f5e455f2346232fdd764b3352` |
| AnthropicMono-Roman.woff2 | 655 | 699 | 66080 | `dc08f58eb5f37ecc331e5a123d3c3a0b83d7c31553128bd49482ada00be7efb9` |
| AnthropicSans-Italic.woff2 | 578 | 651 | 130736 | `e77eb587e7446f14dc9322fa28695c753f6b4e52e58f390fcbf6abb4c6f86a03` |
| AnthropicSans-Roman.woff2 | 625 | 713 | 118396 | `b571982c97eba001545a79841cce7b2c026cb9ae60e9f32159f54e09dbf52a1d` |
| AnthropicSerif-Italic.woff2 | 554 | 651 | 170324 | `5dd78666632f0854ed16166a311c4a7ae92019c62f2285b1a2ce5387067c3632` |
| AnthropicSerif-Roman.woff2 | 633 | 747 | 175452 | `18df9b94a777e85187388ca1b95c51928a6d9f1bab1e8579c949e3fb466df21c` |
| Anthropicons-Variable.woff2 | 307 | 792 | 96884 | `6181e75f27edfd407552c4bb6670f94f555e32f3ce0dfbf9fc5ee3c505903a13` |

Fixed assertions that hold across all 12 terminal faces:

```
fc-scan  AnthropicMono Nerd Font Mono,AnthropicMono NFM|Regular|AnthropicMono NFM|80|0|100
         weights 50 / 80 / 100 / 180 / 200 / 205 for Light…ExtraBold, slant 100 on italics
hmtx     {adv for adv, _ in hmtx.metrics.values()} == {1200}   (whole table, no exclusions)
line box hhea 1985/-515/0 == sTypo == usWin(1985/515), sxHeight 1080, sCapHeight 1440, upm 2000
GSUB     calt exactly 136 lookups; 496 total lookups on Regular; features ⊇
         {aalt,calt,ccmp,dnom,frac,liga,locl,ordn,sinf,subs,sups}; 17 latn langsys records;
         GDEF present; GPOS mark present; lost_cp = 0; lost features = []
shaping  'x -> y' groups (2,2,…); 'c ==> d' groups (3,3,…); 'a != b', 'p <=> q', 'f /= g' likewise
         U+E0B0, U+F001, U+276F, U+2588, U+28FF, U+2800, U+03BB, U+0410, U+2718, U+1D538, U+F07E5
         each shape to one non-.notdef glyph from the main font
box art  U+2500, U+2550, U+2588 all span x0 <= 0 and x1 >= 1200  (measured -12 … 1212)
align    {shift: 100, anchor-veto: 35, clamped: 1} on every face; dy range -61 … +93
         |ycentre(lig '--') - ycentre(hyphen)| <= 8   (measured 0.0-0.5 on all 12)
         patcher changed 0 of 136 lig outlines
names    nameID1 <= 31, nameID16 <= 31, nameID17 <= 31;
         nameID6 matches ^AnthropicMonoNFM(-[A-Za-z]+)?$  <- the bare form is the RIBBI
         Regular face under patcher 3.5.1 (section 3.1); no 'Regular' glued onto a weight;
         nameID5 contains ';Nerd Fonts 3.5.1'; no record contains 'Web' or 'Italic Italic';
         12 unique PostScript names; patcher log has zero ^ERROR|^CRITICAL lines
```

Three traps in the verification harness itself, each measured:

- **The nameID 6 pattern must allow a missing style suffix.** Patcher 3.5.1 strips
  `Regular` from the RIBBI face, so a regex demanding `-<Style>` fails on a correct font.
- **Every nameID assertion is set membership, not equality.** The name table carries **two**
  `nameID16` records with different strings, `AnthropicMono Nerd Font Mono` (28) and
  `AnthropicMono NFM` (17). A dict keyed by nameID silently keeps only the last and fails
  a correct font.
- **Never assert a literal `fsSelection` integer.** The patcher sets bit 8 (WWS), so Bold
  Italic ships 417 and the non-RIBBI italics ship 385. Assert bit predicates: bit 0 on
  italics; bit 5 and macStyle bit 0 only on the RIBBI Bold pair; bit 6 only on plain
  Regular; bit 7 everywhere; macStyle bit 1 on every italic; and `(fsSelection & 0x41) !=
  0x41` everywhere, because fontTools refuses a font with bits 6 and 0 both set.
- **Run one process per fallback lookup.** Batching more than two `get_fallback_font()`
  calls trips kitty's "Too many fallback fonts" limit, after which every later call returns
  "returned a result with an exception set", which is a silent false pass.

The whole suite runs under `FONTCONFIG_FILE` **and** `XDG_CACHE_HOME` redirected into
scratch. `FONTCONFIG_FILE` alone is not sufficient: with only it set, the live
`~/.cache/fontconfig` directory mtime moved during a verification pass although no cache
file was created or modified. The isolation snapshot is taken **without** `-type f` so a
directory-entry change is caught:

```sh
find ~/.cache/fontconfig -printf '%T@ %s %p\n' | sort | sha256sum
```

which is measured byte-stable across the entire suite: dozens of `fc-scan` and `fc-match`
runs including 1,854-row `:charset` sweeps, `fc-list`, `kitty +runpy`, `pango-view` and
headless Chrome. `kitty +runpy` wants a tty, so wrap it in `script -qec '…' /dev/null`;
the naive `kitty +runpy "$(cat file)"` form breaks on the embedded quotes of the
`family="…"` settings.

---

## 11. The PUA map

Anthropicons claims 307 codepoints in U+E000 to U+E134. The Anthropic **text** faces claim
**50** of those codepoints with entirely different glyphs. The contact sheet outlines those
50 cells.

| range | count | what the text faces put there |
|---|---|---|
| U+E001-E00C, U+E00F, U+E011-E016 | 19 | precomposed Vietnamese, Dutch and Turkish diacritic composites: `Edotbelowacute`, `Edotbelowgrave`, `Edotbelowmacron`, `Odotbelow*`, `IJacute`, `Ndieresis`, `i.loclTRK`, … |
| U+E021, U+E024, U+E02A | 3 | superior figures and letters |
| U+E031, U+E032 | 2 | em-dash fractions |
| U+E0A7, U+E0A8 | 2 | `Istrokeacute` / `istrokeacute`, inside the Nerd powerline block |
| U+E101-E10E, U+E111-E113, U+E115, U+E116 | 17 | Serif `.tilt` alternates |
| U+E11A-E11E | 5 | the brand marks: `ASlash.pua`, `Anthropic.pua`, `Claude.pua`, `Spark.pua`, `Code.pua` |
| U+E135, U+E136 | 2 | `Udotaccent` / `udotaccent` (Mono only, above the icon range) |

Per-face collision counts: Serif 48, Sans 29, Mono 21.

Two facts that follow and are easy to get backwards:

- **U+E0A7 and U+E0A8 are not a Nerd Font collision.** Nerd Fonts defines nothing at
  those two slots, re-confirmed on a patched face. `FONTS.md`'s "2/53 powerline coverage"
  row is these two accented Latin glyphs, not powerline separators.
- **U+E00D, U+E00E and U+E010 are absent from all 12 terminal faces and from every
  Anthropic text source.** kitty's fallback picks them up from `Inter-Regular` at 0.441 em
  inside a 0.600 em cell. The acceptance test asserts only that U+E0A7, U+E0A8 and U+E0B0
  resolve from the Anthropic face itself.

---

## 12. The Pomicons overwrite, and stage S7b

`nerd-font-patcher --complete` **destructively overwrites** ten of Anthropic's own PUA
glyphs. Measured across the identical Regular chain:

```
S6 work/aligned/Regular.ttf   U+E001..E00A = Edotbelowacute … odotbelowacute   (unchanged from source)
S7 patched face               U+E001..E00A = POMODORO_DONE … EXTERNAL_INTERRUPTION
```

The displaced glyphs are **gone from the font entirely**: `'Edotbelowacute' in
getGlyphOrder()` returns False. U+E00B and U+E00C survive because Pomicons stops at E00A,
and U+E0A7 and U+E0A8 survive, which is the pair earlier sampling happened to check and
the reason "the feared collision does not exist" was once recorded. On the live desktop
the net effect would be that the same codepoint shows Ẹ́ in a GTK app and a tomato in
kitty.

Neither obvious fix works. `--careful` preserves the PUA but stops the patcher redrawing
cell-filling box and block art (U+2588 becomes `(-50,0,1250,1440)` instead of
a cell-spanning box, so full block would no longer fill the cell). Enumerating the icon
sets to omit `--pomicons` makes `FontnameParser` append every set name, yielding nameID 16
`AnthropicMono Nerd Font Mono Plus Font Awesome Plus …` at 183 characters with `ERROR`
lines.

**Stage S7b re-grafts them.** It runs after S7 and before canonicalize, on every terminal
face. For each codepoint in U+E001 to U+E00A it takes the glyph from the **S6 aligned**
face through `DecomposingRecordingPen` into a `TTGlyphPen`, installs it under
`<origName>.apua`, copies its hmtx entry, and points every Unicode cmap subtable at it.

Two mechanics that are easy to get wrong and were measured:

- Append the new names to **`glyf.glyphOrder` and `font.setGlyphOrder(...)`**, assigning
  `glyf.glyphs[name] = g` directly. `glyf[name] = g` does not keep `glyphOrder` and
  `glyphs` in step and the save dies in `_m_a_x_p.recalc` with a bare `AssertionError`.
- The orphaned `POMODORO_*` outlines stay in the font, uncmapped. That costs nothing.

Measured on the 3.4.0 Regular, where the face carried 13,224 cmap entries and 13,621
glyphs: the cmap count is unchanged by the re-graft, every advance is still exactly 1200,
U+E001 resolves to `Edotbelowacute.apua` at `(206,-426,1030,1886)`, U+2588 and U+2500
still span the cell, U+E0B0 is still the powerline divider, U+E62B still the vim icon,
U+2800 still the blank `nbspace.maple`, and `hb-shape 'a -> b == c'` is unchanged. The
shipped face's own totals are higher under 3.5.1 (section 5.7); what S7b asserts is
invariance, not a count.

The acceptance suite asserts, for every codepoint in U+E001 to U+E00A, that the packaged
glyph name equals the S6 face's and that the advance is 1200.
