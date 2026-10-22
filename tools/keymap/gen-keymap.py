#!/usr/bin/env python3
"""gen-keymap.py: generate docs/shell/KEYMAP.md from the shell's key configs.

What it is: the one generator for the shell's binding table (ruling R2 of the
2026-10-22 consolidation dry run: "keymap generated"). Python 3 standard
library only, no network, no display, no compositor. It reads files and writes
one Markdown file; it never runs swaymsg, sway, kitty or herdr.

What it replaced: the hand kept keys table in docs/client-sway-vicinae.md and
the hand counted "108 bindsym" figures in notes (2026-10-22).

Inputs, all relative to the repository root:
  home/dot_config/sway/config and home/dot_config/sway/*.conf
      every bindsym, bindcode and bindswitch, including `mode "x" { }` blocks
  home/home.nix
      the "sway-local.conf" generator: each `lib.optionalString (hostName ==
      "<host>") '' ... ''` string is parsed as Sway config for that host
  home/dot_config/kitty/*.conf
      every `map` and `mouse_map` line (kitty_mod resolved, default ctrl+shift)
  home/dot_config/herdr/config.toml
      the [keys] table: prefix, plain string keys, and [[keys.command]] rows

Doc and group per row: a comment line of the form `## group | verb | doc`
directly above a binding sets group, verb and doc for that binding. Otherwise
doc is the nearest preceding plain comment block in the same paragraph (a
blank line ends a paragraph), and group is inferred from the action (marked
with a trailing `*`).

Deliberately absent: no timestamps, so the output is byte reproducible for a
given input set. The header names the git revision of the last commit that
touched any input, plus a sha256 over the input bytes.

Usage:
  python3 tools/keymap/gen-keymap.py [--repo DIR] [--out FILE] [--check]
  --check exits 1 when FILE differs from what would be generated.
"""

from __future__ import annotations

import argparse
import hashlib
import re
import subprocess
import sys
import tomllib
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from pathlib import Path

GENERATOR = "tools/keymap/gen-keymap.py"
DEFAULT_OUT = "docs/shell/KEYMAP.md"
SWAY_DIR = "home/dot_config/sway"
HOME_NIX = "home/home.nix"
KITTY_DIR = "home/dot_config/kitty"
HERDR_TOML = "home/dot_config/herdr/config.toml"

LAYER_ORDER = ["sway", "kitty", "herdr"]

MOD_ALIASES = {
    "mod4": "Super", "super": "Super", "logo": "Super", "cmd": "Super",
    "mod1": "Alt", "alt": "Alt", "opt": "Alt", "option": "Alt",
    "ctrl": "Ctrl", "control": "Ctrl",
    "shift": "Shift",
    "mod2": "Mod2", "mod3": "Mod3", "mod5": "Mod5", "hyper": "Hyper", "meta": "Meta",
}
MOD_ORDER = ["Super", "Hyper", "Meta", "Ctrl", "Alt", "Shift", "Mod2", "Mod3", "Mod5"]
KEY_ALIASES = {
    "enter": "Return", "return": "Return", "esc": "Escape", "escape": "Escape",
    "space": "space", "tab": "Tab", "backspace": "BackSpace", "delete": "Delete",
    "up": "Up", "down": "Down", "left": "Left", "right": "Right",
    "page_up": "Prior", "page_down": "Next", "home": "Home", "end": "End",
    "insert": "Insert", "menu": "Menu",
}

DOC_TAG = re.compile(r"^##\s*([^|#]+?)\s*\|\s*([^|]*?)\s*\|\s*(.*?)\s*$")


@dataclass
class Row:
    layer: str
    host: str
    mode: str
    chord: str
    action: str
    group: str
    doc: str
    source: str
    flags: list[str] = field(default_factory=list)


# ---------------------------------------------------------------- helpers

def norm_chord(raw: str, variables: dict[str, str] | None = None) -> str:
    """Normalise a chord: modifiers in a fixed order, Mod4 shown as Super."""
    text = raw
    for name, value in sorted((variables or {}).items(), key=lambda kv: -len(kv[0])):
        text = text.replace(name, value)
    parts = [p for p in text.split("+") if p != ""]
    if text.endswith("++"):
        parts.append("plus")
    mods, keys = [], []
    for i, part in enumerate(parts):
        low = part.lower()
        if i < len(parts) - 1 and low in MOD_ALIASES:
            mods.append(MOD_ALIASES[low])
        else:
            keys.append(part)
    mods = sorted(set(mods), key=lambda m: MOD_ORDER.index(m) if m in MOD_ORDER else 99)
    out_keys = []
    for k in keys:
        low = k.lower()
        if low in KEY_ALIASES:
            out_keys.append(KEY_ALIASES[low])
        elif len(k) == 1 and k.isalpha():
            out_keys.append(k.upper())
        elif re.fullmatch(r"f\d{1,2}", low):
            out_keys.append(low.upper())
        else:
            out_keys.append(k)
    return "+".join(mods + out_keys)


def infer_group(action: str) -> str:
    a = action.strip()
    if a.startswith("exec "):
        words = [w for w in a.split()[1:] if not w.startswith("--")]
        if not words:
            return "exec*"
        prog = words[0].rsplit("/", 1)[-1]
        if prog == "kitty" and "-e" in words:
            idx = words.index("-e")
            if idx + 1 < len(words):
                prog = words[idx + 1].rsplit("/", 1)[-1]
        return prog + "*"
    first = a.split()[0] if a else "?"
    if first == "move":
        return "move*"
    return first + "*"


def md_cell(text: str) -> str:
    return text.replace("|", "\\|").replace("\n", " ").strip()


def short(text: str, limit: int = 110) -> str:
    text = " ".join(text.split())
    return text if len(text) <= limit else text[: limit - 3].rstrip() + "..."


# ---------------------------------------------------------------- sway

BIND_RE = re.compile(r"^(bindsym|bindcode|bindswitch)\s+(.*)$")
SET_RE = re.compile(r"^set\s+(\$\S+)\s+(.*)$")
MODE_OPEN_RE = re.compile(r'^mode\s+(?:--pango_markup\s+)?("([^"]*)"|(\S+))\s*\{\s*$')


def parse_sway_text(text: str, source: str, host: str, variables: dict[str, str],
                    first_line: int = 1) -> list[Row]:
    rows: list[Row] = []
    mode_stack: list[str] = []
    comment: list[str] = []
    tag: tuple[str, str, str] | None = None
    for offset, raw_line in enumerate(text.splitlines()):
        lineno = first_line + offset
        line = raw_line.strip()
        if not line:
            comment, tag = [], None
            continue
        if line.startswith("#"):
            m = DOC_TAG.match(line)
            if m:
                tag = (m.group(1), m.group(2), m.group(3))
            else:
                body = line.lstrip("#").strip()
                comment.append(body)
            continue
        m = SET_RE.match(line)
        if m:
            variables[m.group(1)] = m.group(2).strip()
            continue
        m = MODE_OPEN_RE.match(line)
        if m:
            name = m.group(2) if m.group(2) is not None else m.group(3)
            name = variables.get(name, name).strip().strip('"')
            mode_stack.append(name)
            continue
        if line.endswith("{"):
            # Any other block (input, output, seat): track braces, no mode.
            mode_stack.append("")
            continue
        if line == "}":
            if mode_stack:
                mode_stack.pop()
            continue
        m = BIND_RE.match(line)
        if not m:
            continue
        kind, rest = m.group(1), m.group(2)
        tokens = rest.split()
        flags = []
        while tokens and tokens[0].startswith("--"):
            flags.append(tokens.pop(0))
        if not tokens:
            continue
        chord_raw = tokens[0]
        action = " ".join(tokens[1:])
        for name, value in sorted(variables.items(), key=lambda kv: -len(kv[0])):
            action = action.replace(name, value)
        if kind == "bindswitch":
            chord = "switch:" + chord_raw
        elif kind == "bindcode":
            chord = "code:" + norm_chord(chord_raw, variables)
        else:
            chord = norm_chord(chord_raw, variables)
        if tag:
            group, verb, doc = tag
            doc = f"{verb}: {doc}" if verb else doc
        else:
            group = infer_group(action)
            doc = " ".join(c for c in comment if c)
        modes = [x for x in mode_stack if x]
        rows.append(Row("sway", host, modes[-1] if modes else "default", chord,
                        action, group, short(doc), f"{source}:{lineno}", flags))
        tag = None
    return rows


def parse_sway(repo: Path, variables: dict[str, str]) -> tuple[list[Row], list[Path]]:
    sway = repo / SWAY_DIR
    files = []
    if (sway / "config").is_file():
        files.append(sway / "config")
    files += sorted(p for p in sway.glob("*.conf") if p.is_file())
    # Pass one: collect `set $var` from every file, so binds.conf sees $mod
    # from layout.conf regardless of include order.
    for path in files:
        for line in path.read_text(encoding="utf-8").splitlines():
            m = SET_RE.match(line.strip())
            if m:
                variables[m.group(1)] = m.group(2).strip()
    rows: list[Row] = []
    for path in files:
        rows += parse_sway_text(path.read_text(encoding="utf-8"),
                                str(path.relative_to(repo)), "all", dict(variables))
    return rows, files


HOST_STR_RE = re.compile(
    r'lib\.optionalString\s*\(\s*hostName\s*==\s*"([^"]+)"\s*\)\s*\'\'(.*?)(?<!\')\'\'(?!\')',
    re.S)


def parse_home_nix(repo: Path, variables: dict[str, str]) -> tuple[list[Row], list[Path]]:
    path = repo / HOME_NIX
    if not path.is_file():
        return [], []
    text = path.read_text(encoding="utf-8")
    start = text.find('"sway-local.conf"')
    if start < 0:
        return [], [path]
    # The generator ends at the first `'';` that closes the last host string;
    # bound the search to the next top level attribute after it.
    segment_end = text.find("};", start)
    segment = text[start: segment_end if segment_end > 0 else len(text)]
    rows: list[Row] = []
    for m in HOST_STR_RE.finditer(segment):
        host, body = m.group(1), m.group(2).replace("'''", "''")
        first_line = text.count("\n", 0, start + m.start(2)) + 1
        if body.startswith("\n"):
            body = body[1:]
            first_line += 1
        rows += parse_sway_text(body, f"{HOME_NIX} (sway-local.conf)", host,
                                dict(variables), first_line)
    return rows, [path]


# ---------------------------------------------------------------- kitty

KITTY_MAP_RE = re.compile(r"^(map|mouse_map)\s+(\S+)\s+(.*)$")


def parse_kitty(repo: Path) -> tuple[list[Row], list[Path]]:
    kdir = repo / KITTY_DIR
    files = sorted(p for p in kdir.glob("*.conf") if p.is_file())
    kitty_mod = "ctrl+shift"
    for path in files:
        for line in path.read_text(encoding="utf-8").splitlines():
            m = re.match(r"^\s*kitty_mod\s+(\S+)", line)
            if m:
                kitty_mod = m.group(1)
    rows: list[Row] = []
    for path in files:
        comment: list[str] = []
        tag = None
        for lineno, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            line = raw.strip()
            if not line:
                comment, tag = [], None
                continue
            if line.startswith("#"):
                m = DOC_TAG.match(line)
                if m:
                    tag = (m.group(1), m.group(2), m.group(3))
                else:
                    comment.append(line.lstrip("#").strip())
                continue
            m = KITTY_MAP_RE.match(line)
            if not m:
                continue
            kind, chord_raw, action = m.groups()
            chord_raw = chord_raw.replace("kitty_mod", kitty_mod)
            # kitty multi key sequences use `>`: normalise each step.
            chord = " > ".join(norm_chord(step) for step in chord_raw.split(">"))
            mode = "mouse" if kind == "mouse_map" else "default"
            if kind == "mouse_map":
                # mouse_map <button> <event> <modes> <action>
                parts = action.split(None, 2)
                chord = f"{chord} ({' '.join(parts[:2])})" if len(parts) >= 2 else chord
                action = parts[2] if len(parts) == 3 else action
            if tag:
                group, verb, doc = tag
                doc = f"{verb}: {doc}" if verb else doc
            else:
                group = action.split()[0] + "*"
                doc = " ".join(comment)
            rows.append(Row("kitty", "all", mode, chord, action, group, short(doc),
                            f"{path.relative_to(repo)}:{lineno}"))
            tag = None
    return rows, files


# ---------------------------------------------------------------- herdr

def parse_herdr(repo: Path) -> tuple[list[Row], list[Path]]:
    path = repo / HERDR_TOML
    if not path.is_file():
        return [], []
    raw = path.read_bytes()
    data = tomllib.loads(raw.decode("utf-8"))
    keys = data.get("keys", {})
    lines = raw.decode("utf-8").splitlines()

    def line_of(needle: str) -> int:
        for i, line in enumerate(lines, 1):
            if line.strip().startswith(needle):
                return i
        return 0

    prefix = keys.get("prefix", "ctrl+b")
    prefix_n = norm_chord(prefix)

    def expand(k: str) -> str:
        if k.startswith("prefix+"):
            return f"{prefix_n} > {norm_chord(k[len('prefix+'):])}"
        return norm_chord(k)

    rows = [Row("herdr", "strix", "default", prefix_n, "prefix (leader)", "prefix",
                "herdr leader key, pinned explicitly in config", f"{HERDR_TOML}:{line_of('prefix')}")]
    for name, value in sorted(keys.items()):
        if name == "prefix" or not isinstance(value, str):
            continue
        rows.append(Row("herdr", "strix", "default", expand(value), name, "herdr builtin",
                        "", f"{HERDR_TOML}:{line_of(name)}"))
    for entry in keys.get("command", []) or []:
        k = entry.get("key", "")
        if not k:
            continue
        cmd = entry.get("command", "")
        lines_n = len(cmd.strip().splitlines())
        body = cmd.strip() if lines_n <= 1 else f"inline shell script, {lines_n} lines"
        kind = entry.get("type", "")
        action = f"{kind}: {body}" if kind else body
        rows.append(Row("herdr", "strix", "default", expand(k), short(action, 80),
                        "command", short(entry.get("description", "")),
                        f"{HERDR_TOML}:{line_of(f'key = \"{k}\"')}"))
    return rows, [path]


# ---------------------------------------------------------------- render

def git_rev(repo: Path, inputs: list[Path]) -> str:
    rels = [str(p.relative_to(repo)) for p in inputs]
    try:
        out = subprocess.run(["git", "-C", str(repo), "log", "-1", "--format=%h", "--", *rels],
                             capture_output=True, text=True, check=True).stdout.strip()
        dirty = subprocess.run(["git", "-C", str(repo), "status", "--porcelain", "--", *rels],
                               capture_output=True, text=True, check=True).stdout.strip()
        return (out or "uncommitted") + (" plus uncommitted changes" if dirty else "")
    except (OSError, subprocess.CalledProcessError):
        return "unknown (git unavailable)"


def chord_sort_key(row: Row):
    return (row.mode != "default", row.mode, row.chord.lower(), row.host, row.source)


def render(repo: Path) -> str:
    variables: dict[str, str] = {}
    sway_rows, sway_files = parse_sway(repo, variables)
    nix_rows, nix_files = parse_home_nix(repo, variables)
    kitty_rows, kitty_files = parse_kitty(repo)
    herdr_rows, herdr_files = parse_herdr(repo)
    rows = sway_rows + nix_rows + kitty_rows + herdr_rows
    inputs = sway_files + nix_files + kitty_files + herdr_files

    digest = hashlib.sha256()
    for p in inputs:
        digest.update(str(p.relative_to(repo)).encode() + b"\0" + p.read_bytes() + b"\0")

    out: list[str] = []
    w = out.append
    w("# KEYMAP")
    w("")
    w(f"Generated by `{GENERATOR}`. Do not edit by hand; edit the configs and rerun")
    w(f"`python3 {GENERATOR}` from the repository root.")
    w("")
    w(f"Input revision (last commit touching any input): `{git_rev(repo, inputs)}`.")
    w(f"Input sha256: `{digest.hexdigest()[:16]}`.")
    w("")
    w("Inputs:")
    w("")
    for p in inputs:
        w(f"- `{p.relative_to(repo)}`")
    w("")
    w("Reading the tables: `Super` is Sway's `Mod4` (`$mod`). `A > B` is a sequence:")
    w("press A, release, then press B. `switch:` rows are `bindswitch`. Host `all`")
    w("means the shared raw config; `client` and `strix` rows come from the")
    w("`sway-local.conf` generator in `home/home.nix`. A group ending in `*` was")
    w("inferred from the action because no `## group | verb | doc` line was present.")
    w("Doc is the nearest comment above the binding in the same paragraph.")
    w("")

    w("## Counts")
    w("")
    w("| Layer | Host | Mode | Bindings |")
    w("|---|---|---|---|")
    counts = Counter((r.layer, r.host, r.mode) for r in rows)
    for (layer, host, mode), n in sorted(counts.items(), key=lambda kv: (LAYER_ORDER.index(kv[0][0]), kv[0][1], kv[0][2])):
        w(f"| {layer} | {host} | {mode} | {n} |")
    w(f"| total | | | {len(rows)} |")
    w("")
    # Coverage: raw grep counts of binding lines against parsed rows, so a
    # parser miss shows up in the table instead of silently.
    raw_sway = sum(len(re.findall(r"(?m)^\s*(?:bindsym|bindcode|bindswitch)\s", p.read_text(encoding="utf-8")))
                   for p in sway_files)
    raw_kitty = sum(len(re.findall(r"(?m)^\s*(?:map|mouse_map)\s", p.read_text(encoding="utf-8")))
                    for p in kitty_files)
    w("Coverage (raw binding lines found by a line regex, against rows parsed):")
    w("")
    w(f"- sway raw files: {raw_sway} lines against {len(sway_rows)} rows.")
    w(f"- sway-local.conf generator in home.nix: {len(nix_rows)} rows.")
    w(f"- kitty: {raw_kitty} lines against {len(kitty_rows)} rows.")
    w(f"- herdr: {len(herdr_rows)} rows (prefix plus [[keys.command]] entries).")
    w("")

    for layer in LAYER_ORDER:
        lrows = sorted((r for r in rows if r.layer == layer), key=chord_sort_key)
        w(f"## Layer: {layer}")
        w("")
        if not lrows:
            w("No bindings found.")
            w("")
            continue
        w("| Chord | Host | Mode | Action | Group | Doc | Flags | Source |")
        w("|---|---|---|---|---|---|---|---|")
        for r in lrows:
            w("| " + " | ".join([
                f"`{md_cell(r.chord)}`", r.host, r.mode, f"`{md_cell(short(r.action, 90))}`",
                md_cell(r.group), md_cell(r.doc), md_cell(" ".join(r.flags)), f"`{r.source}`",
            ]) + " |")
        w("")

    w("## Conflicts")
    w("")
    w("Identical chords in more than one layer. Sway grabs a chord before the focused")
    w("window sees it, so a Sway row shadows the kitty or herdr row on the same chord")
    w("(kitty and herdr rows are only reachable when Sway does not bind the chord, or")
    w("under `$mod+Escape` shortcuts inhibition).")
    w("")
    by_chord: dict[str, list[Row]] = defaultdict(list)
    for r in rows:
        if r.mode == "mouse":
            continue
        by_chord[r.chord].append(r)
    cross = {c: rs for c, rs in by_chord.items() if len({r.layer for r in rs}) > 1}
    # A herdr sequence `Ctrl+B > X` also collides at its first step.
    first_steps: dict[str, list[Row]] = defaultdict(list)
    for r in rows:
        if " > " in r.chord:
            first_steps[r.chord.split(" > ")[0]].append(r)
    if not cross:
        w("None across layers.")
    else:
        w("| Chord | Rows |")
        w("|---|---|")
        for c in sorted(cross, key=str.lower):
            w(f"| `{md_cell(c)}` | " + "; ".join(
                f"{r.layer} ({r.host}) `{md_cell(short(r.action, 50))}` at `{r.source}`" for r in cross[c]) + " |")
    w("")
    w("### Same chord twice inside one layer")
    w("")
    w("Rows on the same layer, mode and chord where the hosts overlap (`all` overlaps")
    w("every host). In Sway the later include wins when `--no-warn` is set; otherwise")
    w("Sway logs a duplicate binding warning.")
    w("")
    inner = []
    for c, rs in sorted(by_chord.items(), key=lambda kv: kv[0].lower()):
        for layer in LAYER_ORDER:
            lr = [r for r in rs if r.layer == layer]
            seen = defaultdict(list)
            for r in lr:
                seen[r.mode].append(r)
            for mode, mr in seen.items():
                hosts = [r.host for r in mr]
                if len(mr) > 1 and (len(set(hosts)) < len(hosts) or "all" in hosts):
                    inner.append((c, layer, mode, mr))
    if not inner:
        w("None.")
    else:
        w("| Chord | Layer | Mode | Rows |")
        w("|---|---|---|---|")
        for c, layer, mode, mr in inner:
            w(f"| `{md_cell(c)}` | {layer} | {mode} | " + "; ".join(
                f"{r.host} `{md_cell(short(r.action, 50))}` {md_cell(' '.join(r.flags))} at `{r.source}`" for r in mr) + " |")
    w("")
    w("### Sequence prefixes shadowed by a single chord")
    w("")
    shadow = []
    for first, seqs in sorted(first_steps.items()):
        singles = [r for r in by_chord.get(first, []) if r.layer != seqs[0].layer]
        if singles:
            shadow.append((first, seqs, singles))
    if not shadow:
        w("None: no other layer binds a sequence's first step.")
    else:
        for first, seqs, singles in shadow:
            w(f"- `{first}` starts {len(seqs)} sequences in {seqs[0].layer} and is also bound in "
              + ", ".join(f"{r.layer} at `{r.source}`" for r in singles) + ".")
    w("")
    w("## Not verified")
    w("")
    w("This table is parsed from files, not read from a running compositor. It does")
    w("not prove any binding works on the client or on the strix. Includes outside the")
    w("repository (`/etc/sway/physical-session.conf`, kitty's built in defaults, herdr's")
    w("built in defaults) are not parsed, so their bindings are absent here.")
    w("No second reader (Tom's light verification rule, 2026-10-20).")
    return "\n".join(out) + "\n"


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--repo", default=str(Path(__file__).resolve().parents[2]))
    ap.add_argument("--out", default=None, help=f"default: <repo>/{DEFAULT_OUT}; '-' for stdout")
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args(argv)
    repo = Path(args.repo).resolve()
    text = render(repo)
    out = args.out or str(repo / DEFAULT_OUT)
    if args.check:
        current = Path(out).read_text(encoding="utf-8") if Path(out).is_file() else ""
        if current != text:
            print(f"{out} is stale; rerun {GENERATOR}", file=sys.stderr)
            return 1
        return 0
    if out == "-":
        sys.stdout.write(text)
    else:
        Path(out).parent.mkdir(parents=True, exist_ok=True)
        Path(out).write_text(text, encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

# Not verified
# Run only against the dry run clone on 2026-10-22 (py_compile and one
# generation, MEASURED). Not run against the gpuix-shell worktree. Sway's
# grouped `bindsym { }` syntax and multi file include order are not modelled;
# when two rows share a chord the table lists both and does not say which wins.
# No second reader (Tom's light verification rule, 2026-10-20).
