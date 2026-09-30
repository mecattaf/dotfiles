#!/usr/bin/env bash
# Anthropic Mono review demo - prints the specimen Tom approves or rejects.
# Spawned by specimen/review-window.sh; prints only, changes nothing, then
# drops to an interactive shell so the face can be typed in.
#
# WHAT THIS SHEET CAN AND CANNOT JUDGE (spec 1 E9 / 11 A22):
# kitty draws U+2800-U+28FF ITSELF (fonts.c:735 -> BOX_FONT), before symbol_map
# and before the font is consulted.  The braille row below therefore exercises
# kitty's own dot rasteriser, NOT the merged braille, and can neither approve
# nor reject it.  Judge the merged braille from specimens/mono-*.png
# (pango-view) or in foot.  Everything else here IS the font.
set -u
b=$'\e[1m'; i=$'\e[3m'; bi=$'\e[1;3m'; d=$'\e[2m'; r=$'\e[0m'
c1=$'\e[38;5;179m'; c2=$'\e[38;5;108m'; c3=$'\e[38;5;110m'

printf '%s\n' "${d}face: AnthropicMono Nerd Font Mono   size: 16.0   cell 26x54 px @ scale 2${r}"
echo
echo "${c1}ligatures${r}    -> => != === <= >= :: |> <- ~> www <=> --> |-> /* */"
echo "${c1}ligatures${r}    ++ -- == /= =~ ?: ;; !! && || <> #{ 0xFF ->> =<< <|>"
echo
echo "${c2}hyphen  row${r}  - - - - - - - -    a-b  x-y  --  ---  ----"
echo "${c2}arrow   row${r}  -> -> -> -> -> ->  a->b x->y  =>  ==>  <-"
echo "${c2}equals  row${r}  = = = = = = = =    a=b  x=y  ==  ===  <="
printf '%s\n' "${d}  (the three strokes above must sit on ONE horizontal axis)${r}"
echo
echo "${c3}prompt${r}       ❯ cd ~/mecattaf/dotfiles && nix build .#fontbuilder"
# PUA/powerline codepoints are written as bash $'\uXXXX' escapes ON PURPOSE.
# Measured, twice: a tool that rewrites this file strips raw PUA characters
# silently, and the powerline row then renders as spaces.  Escapes survive.
pl=$'\ue0b0\ue0b1\ue0b2\ue0b3'; br=$'\ue0a0'; ln=$'\ue0a1'; lk=$'\ue0a2'
pl2=$'\ue0b4\ue0b5\ue0b6\ue0b7'; ic=$'\uf09b \uf07c \uf013 \uf015 \uf0c9'
pua=$'\ue0a7\ue0a8'   # the two E23 survivors, and the pair A11b pins
echo "${c3}powerline${r}    ${pl} ${br} main ${ln} 12 ${lk} ${pl2}  ${ic}  ${pua}"
echo "${c3}braille bar${r}  ⠀⠁⠃⠇⠏⠟⠿⡿⣿ ⡀⣀⣠⣰⣸⣼⣾⣿  [⠀] <- U+2800 must be a BLANK cell, not a box"
printf '%s\n' "${d}  (kitty draws braille itself - this row judges kitty, not the font. See the PNG sheets.)${r}"
echo "${c3}box tree${r}     ├── src/   └── lib/   │  ┌─┐ └─┘ ╭─╮ ═╣  █▓▒░▀▄"
echo "${c3}box join${r}     ┌─┬─┐"
echo "             ├─┼─┤   (the verticals must MEET the horizontals)"
echo "             └─┴─┘"
echo "${c3}greek/cyr${r}    λμπΣΩαβγδε  ЖДЯфывпри  ✓✘✗✔  →←↑↓  ∀∃∈∉∑∏"
echo
# FOUR rows, one per resolved face: a row that only exercised bold/italic/
# bold-italic would leave the medium face untested at exactly the place the
# review is meant to catch a wrong resolution.
echo "${d}Regular (kitty medium)${r} -> => != === <= >= :: |> ❯ └── ⣿ λ Ж The quick brown fox"
echo "${b}SemiBold (kitty bold)${r}  ${b}-> => != === <= >= :: |> ❯ └── ⣿ λ Ж The quick brown fox${r}"
echo "${i}Italic${r}                 ${i}-> => != === <= >= :: |> ❯ └── ⣿ λ Ж The quick brown fox${r}"
echo "${bi}SemiBold Italic${r}        ${bi}-> => != === <= >= :: |> ❯ └── ⣿ λ Ж The quick brown fox${r}"
printf '%s\n' "${d}  (an italic comment containing => must show a SLANTED ligature - A22)${r}"
echo
echo "latin        The quick brown fox jumps over 0123456789  Il1O0  {}[]()  \`'\"’"
echo "code         ${c1}def${r} ${c2}merge${r}(donor, host) ${c1}->${r} dict[str, int]:  ${d}# host_cp |= donor_cp${r}"
echo
printf '%s\n' "${d}window: $(tput cols 2>/dev/null || echo ?) cols x $(tput lines 2>/dev/null || echo ?) rows   (Liga SFMono gave ~5.6% more rows at the same pixel height)${r}"
printf '%s\n' "${d}type anything to try the face; exit or close the window when done.${r}"

# Drop to an interactive shell (spec 10 step 13).  --hold on the kitty side
# keeps the window open even if this fails.
exec bash -i
