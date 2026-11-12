#!/usr/bin/env python3
"""Render Markdown, text, or HTML as local A4 PDFs and optionally print them."""

from __future__ import annotations

import argparse
import html
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from collections import Counter
from dataclasses import dataclass, field, replace
from html.parser import HTMLParser
from pathlib import Path
from typing import NoReturn


@dataclass(frozen=True)
class Profile:
    label: str
    family: str
    size_pt: float
    line_height: float
    heading_weight: int = 600


PROFILES = {
    "garamond": Profile("EB Garamond", "EB Garamond", 12.0, 1.38),
    "baskerville": Profile("Libre Baskerville", "Libre Baskerville", 10.8, 1.43, 700),
    "source-serif": Profile("Source Serif 4", "Source Serif 4", 11.25, 1.42),
    "times": Profile("Liberation Serif · Times-style", "Liberation Serif", 11.5, 1.40, 700),
}
PROFILE_ALIASES = {
    "eb-garamond": "garamond",
    "libre-baskerville": "baskerville",
    "source": "source-serif",
    "source-serif-4": "source-serif",
    "liberation": "times",
    "liberation-serif": "times",
    "times-new-roman": "times",
}
DEFAULT_PRINTER = os.environ.get("PRINT_PAPER_PRINTER", "Brother_HL_L2445DW")


@dataclass(frozen=True)
class Layout:
    """Bounded page fitting (#673): pagination first, then margins and leading,
    and only then type size. Margins are top, sides, bottom in millimetres."""
    top_mm: float
    side_mm: float
    bottom_mm: float
    scale: float = 1.0
    leading: float | None = None  # None keeps the profile's own leading


LAYOUTS = {
    "standard": Layout(20, 30, 21),
    # Same type size; the render-only experiment in #673 measured 13 → 8 pages
    # from table flow plus these margins and leading, with no font change.
    "snug": Layout(19, 25, 20, leading=1.36),
    "compact": Layout(18, 25, 19, scale=0.96, leading=1.34),
    "dense": Layout(17, 23, 18, scale=0.91, leading=1.28),
}
# Readable floors (#673): continuous text, table text included.
BODY_FLOOR_PT = 10.0
TABLE_FLOOR_PT = 9.5
TABLE_SCALE = 0.9
MM = 72 / 25.4


def fail(message: str) -> NoReturn:
    raise SystemExit(f"print-paper: {message}")


def run(command: list[str], *, check: bool = True,
        env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(command, capture_output=True, text=True, env=env)
    if check and result.returncode:
        detail = (result.stderr or result.stdout).strip()
        fail(f"command failed ({command[0]}): {detail}")
    return result


def find_renderer() -> str:
    path = shutil.which("weasyprint")
    if path:
        return path
    fail("WeasyPrint is not available on PATH; use the Nix-managed paper-render package")


def normalize_profile(name: str) -> str:
    normalized = PROFILE_ALIASES.get(name.lower(), name.lower())
    if normalized not in PROFILES:
        fail(f"unknown profile {name!r}; use --list-profiles")
    return normalized


def require_font(profile: Profile) -> None:
    fc_match = shutil.which("fc-match")
    if not fc_match:
        fail("fc-match is unavailable; cannot guard against silent font fallback")
    result = run([fc_match, "--format=%{family}", profile.family])
    resolved = result.stdout.split(",", 1)[0].strip()
    if resolved.casefold() != profile.family.casefold():
        fail(
            f"font {profile.family!r} is unavailable (fontconfig chose {resolved!r}); "
            "activate the dotfiles font declaration first"
        )


def strip_frontmatter(lines: list[str]) -> list[str]:
    if not lines or lines[0].strip() != "---":
        return lines
    for index in range(1, len(lines)):
        if lines[index].strip() in ("---", "..."):
            return lines[index + 1 :]
    return lines


def inline_markup(value: str) -> str:
    escaped = html.escape(value, quote=False)
    stash: list[str] = []

    def hold(fragment: str) -> str:
        stash.append(fragment)
        return f"\x00{len(stash) - 1}\x01"

    escaped = re.sub(
        r"\x60([^\x60\n]+)\x60",
        lambda match: hold(f"<code>{match.group(1)}</code>"),
        escaped,
    )
    escaped = re.sub(
        r"!\[([^\]]*)\]\(([^)\s]+)(?:\s+[&quot;]*.*?[&quot;]*)?\)",
        lambda match: hold(
            f'<img src="{html.escape(match.group(2), quote=True)}" '
            f'alt="{html.escape(match.group(1), quote=True)}">'
        ),
        escaped,
    )
    escaped = re.sub(
        r"\[([^\]]+)\]\(([^)\s]+)(?:\s+[&quot;]*.*?[&quot;]*)?\)",
        lambda match: hold(
            f'<a href="{html.escape(match.group(2), quote=True)}">{match.group(1)}</a>'
        ),
        escaped,
    )
    escaped = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", escaped)
    escaped = re.sub(r"(?<![\w_])__(.+?)__(?![\w_])", r"<strong>\1</strong>", escaped)
    escaped = re.sub(r"~~(.+?)~~", r"<del>\1</del>", escaped)
    escaped = re.sub(r"(?<!\*)\*([^*\n]+)\*(?!\*)", r"<em>\1</em>", escaped)
    escaped = re.sub(r"(?<![\w_])_([^_\n]+)_(?![\w_])", r"<em>\1</em>", escaped)
    for index, fragment in enumerate(stash):
        escaped = escaped.replace(f"\x00{index}\x01", fragment)
    return escaped


def external_image_sources(body: str) -> list[str]:
    """Inspect the renderer's HTML, so Markdown examples in code stay text."""
    class Images(HTMLParser):
        def __init__(self) -> None:
            super().__init__()
            self.local: list[str] = []

        def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
            if tag != "img":
                return
            source = dict(attrs).get("src") or ""
            if not source.startswith("data:"):
                self.local.append(source)

    images = Images()
    images.feed(body)
    return images.local


HR_PATTERN = re.compile(r"^\s*([-*_])(?:\s*\1){2,}\s*$")
LIST_ITEM_PATTERN = re.compile(r"^(\s*)([-+*]|\d{1,9}[.)])(\s+|\s*$)(.*)$")


@dataclass(frozen=True)
class ListMarker:
    indent: int
    delimiter: str
    ordered: bool
    number: int
    content_indent: int
    content: str


def list_marker(line: str) -> ListMarker | None:
    if HR_PATTERN.match(line):
        return None
    match = LIST_ITEM_PATTERN.match(line.expandtabs(4))
    if not match:
        return None
    lead, token, gap, content = match.groups()
    ordered = token[0].isdigit()
    # CommonMark: five or more spaces after the marker open an indented code
    # block, and the item content column falls back to a single space.
    spaces = len(gap) if content.strip() else 1
    if not 1 <= spaces <= 4:
        spaces = 1
    return ListMarker(
        indent=len(lead),
        delimiter=token[-1] if ordered else token,
        ordered=ordered,
        number=int(token[:-1]) if ordered else 0,
        content_indent=len(lead) + len(token) + spaces,
        content=content,
    )


def split_table_row(line: str) -> list[str]:
    line = line.strip().strip("|")
    return [cell.strip() for cell in re.split(r"(?<!\\)\|", line)]


def is_table_divider(line: str) -> bool:
    cells = split_table_row(line)
    return bool(cells) and all(re.fullmatch(r":?-{3,}:?", cell) for cell in cells)


def is_block_start(lines: list[str], index: int) -> bool:
    value = lines[index]
    stripped = value.strip()
    if not stripped:
        return True
    if re.match(r"^#{1,6}\s+", stripped):
        return True
    if re.match(r"^(\x60{3}|~~~)", stripped):
        return True
    if re.match(r"^([-*_])(?:\s*\1){2,}\s*$", stripped):
        return True
    if list_marker(value) is not None:
        return True
    if stripped.startswith(">"):
        return True
    if index + 1 < len(lines) and "|" in value and is_table_divider(lines[index + 1]):
        return True
    return False


def parse_list(lines: list[str], index: int) -> tuple[str, int]:
    """Consume one CommonMark list, returning its HTML and the next line index."""
    marker = list_marker(lines[index])
    if marker is None:
        raise ValueError("parse_list called off a list marker")
    ordered = marker.ordered
    delimiter = marker.delimiter
    start = marker.number
    items: list[list[str]] = []
    loose = False

    while True:
        content_indent = marker.content_indent
        item: list[str] = [marker.content]
        index += 1
        blank_seen = False
        while index < len(lines):
            raw = lines[index].expandtabs(4)
            if not raw.strip():
                blank_seen = True
                index += 1
                continue
            indent = len(raw) - len(raw.lstrip())
            if indent >= content_indent:
                if blank_seen:
                    item.append("")
                    loose = True
                    blank_seen = False
                item.append(raw[content_indent:])
                index += 1
                continue
            if blank_seen or list_marker(raw) is not None:
                break
            # Lazy continuation: an 80-column hard wrap stays in this item
            # instead of becoming a sibling paragraph and splitting the list.
            item.append(raw.strip())
            index += 1
        items.append(item)

        following = list_marker(lines[index]) if index < len(lines) else None
        if (
            following is None
            or following.indent >= content_indent
            or following.ordered != ordered
            or following.delimiter != delimiter
        ):
            break
        loose = loose or blank_seen
        marker = following

    tag = "ol" if ordered else "ul"
    attributes = f' start="{start}"' if ordered and start != 1 else ""
    rendered = [f"<{tag}{attributes}>"]
    for item in items:
        body, _ = render_blocks(item, tight=not loose)
        rendered.append(f"<li>{body}</li>")
    rendered.append(f"</{tag}>")
    return "\n".join(rendered), index


def markdown_to_html(source: str) -> tuple[str, str | None]:
    lines = strip_frontmatter(source.replace("\r\n", "\n").replace("\r", "\n").split("\n"))
    return render_blocks(lines)


def render_blocks(lines: list[str], *, tight: bool = False) -> tuple[str, str | None]:
    """Render a block sequence; tight suppresses <p> around list-item text."""
    out: list[str] = []
    title: str | None = None
    index = 0

    while index < len(lines):
        line = lines[index]
        stripped = line.strip()
        if not stripped:
            index += 1
            continue

        fence = re.match(r"^(\x60{3}|~~~)\s*([\w+-]*)\s*$", stripped)
        if fence:
            marker, language = fence.groups()
            index += 1
            body: list[str] = []
            while index < len(lines) and not lines[index].strip().startswith(marker):
                body.append(lines[index])
                index += 1
            if index < len(lines):
                index += 1
            class_name = f' class="language-{html.escape(language)}"' if language else ""
            out.append(f"<pre><code{class_name}>{html.escape(chr(10).join(body))}</code></pre>")
            continue

        heading = re.match(r"^(#{1,6})\s+(.+?)\s*#*\s*$", stripped)
        if heading:
            level = len(heading.group(1))
            text = heading.group(2)
            if title is None and level == 1:
                title = re.sub(r"[*_\x60~]", "", text)
            out.append(f"<h{level}>{inline_markup(text)}</h{level}>")
            index += 1
            continue

        if re.match(r"^([-*_])(?:\s*\1){2,}\s*$", stripped):
            out.append("<hr>")
            index += 1
            continue

        if index + 1 < len(lines) and "|" in line and is_table_divider(lines[index + 1]):
            headers = split_table_row(line)
            index += 2
            rows: list[list[str]] = []
            while index < len(lines) and "|" in lines[index] and lines[index].strip():
                rows.append(split_table_row(lines[index]))
                index += 1
            out.append("<table><thead><tr>")
            out.extend(f"<th>{inline_markup(cell)}</th>" for cell in headers)
            out.append("</tr></thead><tbody>")
            for row in rows:
                padded = row + [""] * max(0, len(headers) - len(row))
                out.append("<tr>")
                out.extend(f"<td>{inline_markup(cell)}</td>" for cell in padded[: len(headers)])
                out.append("</tr>")
            out.append("</tbody></table>")
            continue

        if list_marker(line) is not None:
            block, index = parse_list(lines, index)
            out.append(block)
            continue

        if stripped.startswith(">"):
            quoted: list[str] = []
            while index < len(lines) and lines[index].strip().startswith(">"):
                quoted.append(re.sub(r"^\s*>\s?", "", lines[index]))
                index += 1
            out.append(f"<blockquote><p>{inline_markup(' '.join(quoted))}</p></blockquote>")
            continue

        paragraph: list[str] = []
        while index < len(lines) and not is_block_start(lines, index):
            paragraph.append(lines[index].strip())
            index += 1
        if not paragraph:
            paragraph.append(stripped)
            index += 1
        joined = ""
        for part in paragraph:
            hard_break = part.endswith("  ")
            joined += part.rstrip() + ("\x00BR\x01" if hard_break else " ")
        rendered = inline_markup(joined.strip()).replace("\x00BR\x01", "<br>")
        out.append(rendered if tight else f"<p>{rendered}</p>")

    return "\n".join(out), title


def css_string(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def print_css(profile: Profile, *, label: bool = False, layout: str = "standard") -> str:
    geometry = LAYOUTS[layout]
    margin = f"{geometry.top_mm:g}mm {geometry.side_mm:g}mm {geometry.bottom_mm:g}mm"
    table_pt = max(TABLE_FLOOR_PT, round(profile.size_pt * TABLE_SCALE, 3))
    caption = (
        f"{profile.label} · {profile.size_pt:g} pt · {profile.line_height:g} line height"
    )
    label_box = (
        f"""
  @bottom-center {{
    content: {css_string(caption)};
    color: #555;
    font-family: sans-serif;
    font-size: 7.5pt;
    letter-spacing: 0.025em;
    line-height: 1;
  }}"""
        if label
        else ""
    )
    return f"""
@page {{
  size: A4 portrait;
  margin: {margin};
  /* These margin boxes are the only page furniture. Both sit in the reserved bottom margin, outside the
     content box: the bare folio at the right, the optional profile caption
     centered well clear of it. */
  @bottom-right {{
    content: counter(page);
    color: #666;
    font-family: sans-serif;
    font-size: 7pt;
    font-weight: 400;
    letter-spacing: 0.02em;
    line-height: 1;
  }}{label_box}
}}

* {{ box-sizing: border-box; }}
html {{ color: #151515; background: #fff; }}
body {{
  margin: 0;
  font-family: "{profile.family}", serif;
  font-size: {profile.size_pt:g}pt;
  font-weight: 400;
  line-height: {profile.line_height:g};
  font-kerning: normal;
  font-optical-sizing: auto;
  font-synthesis: none;
  text-rendering: optimizeLegibility;
  hyphens: auto;
}}
main {{ display: block; }}
h1, h2, h3, h4, h5, h6 {{
  break-after: avoid-page;
  color: #111;
  font-family: inherit;
  font-weight: {profile.heading_weight};
  hyphens: none;
  line-height: 1.15;
  margin: 1.25em 0 0.48em;
}}
h1 {{
  font-size: 1.72em;
  letter-spacing: -0.012em;
  margin-top: 0;
}}
h2 {{ font-size: 1.28em; }}
h3 {{ font-size: 1.08em; }}
p {{
  margin: 0 0 0.82em;
  orphans: 3;
  widows: 3;
}}
strong {{ font-weight: 600; }}
em {{ font-style: italic; }}
a {{
  color: inherit;
  text-decoration: underline;
  text-decoration-thickness: 0.045em;
  text-underline-offset: 0.12em;
}}
blockquote {{
  border-left: 0.6pt solid #555;
  break-inside: auto;
  font-style: italic;
  margin: 1.05em 0 1.05em 1.1em;
  padding-left: 1em;
}}
blockquote p {{ margin: 0; orphans: 3; widows: 3; }}
ul, ol {{
  margin: 0.45em 0 0.9em 1.4em;
  padding: 0;
}}
li {{ margin: 0.18em 0; padding-left: 0.18em; }}
hr {{
  border: 0;
  border-top: 0.6pt solid #888;
  margin: 1.3em 0;
}}
/* Tables flow across pages (#673). Keeping a whole long table together left
   its section heading alone on the previous page. The column header repeats
   on each continuation page, an ordinary row stays whole, and a row taller
   than a page still breaks rather than clipping. */
table {{
  border-collapse: collapse;
  break-inside: auto;
  font-size: {table_pt:g}pt;
  margin: 0.8em 0 1em;
  width: 100%;
}}
thead {{ display: table-header-group; }}
tr {{ break-inside: avoid; }}
th, td {{
  border-bottom: 0.5pt solid #999;
  padding: 0.35em 0.5em;
  text-align: left;
  vertical-align: top;
}}
/* Column headers are short labels: no automatic hyphenation inside them. */
th {{ font-weight: 600; hyphens: manual; overflow-wrap: break-word; }}
pre {{
  background: #f4f4f2;
  break-inside: auto;
  orphans: 4;
  widows: 4;
  overflow-wrap: anywhere;
  padding: 0.8em 0.9em;
  white-space: pre-wrap;
}}
code {{
  font-family: "DejaVu Sans Mono", monospace;
  font-size: 0.82em;
}}
img {{
  break-inside: avoid-page;
  display: block;
  height: auto;
  margin: 1em auto;
  max-height: 205mm;
  max-width: 100%;
}}
"""


def document_html(
    body: str,
    *,
    title: str,
    base_uri: str,
    profile: Profile,
    label: bool,
    layout: str = "standard",
) -> str:
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<base href="{html.escape(base_uri, quote=True)}">
<title>{html.escape(title)}</title>
<style>{print_css(profile, label=label, layout=layout)}</style>
</head>
<body>
<main>
{body}
</main>
</body>
</html>
"""


def html_input_document(
    source: str,
    *,
    title: str,
    base_uri: str,
    profile: Profile,
    label: bool,
    layout: str = "standard",
) -> str:
    if not re.search(r"<html[\s>]", source, flags=re.I):
        return document_html(
            source,
            title=title,
            base_uri=base_uri,
            profile=profile,
            label=label,
            layout=layout,
        )
    additions = (
        f'<base href="{html.escape(base_uri, quote=True)}">\n'
        f"<style>{print_css(profile, label=label, layout=layout)}</style>\n"
    )
    if re.search(r"</head\s*>", source, flags=re.I):
        source = re.sub(r"</head\s*>", additions + "</head>", source, count=1, flags=re.I)
    else:
        source = re.sub(
            r"<html([^>]*)>",
            r"<html\1><head>" + additions + "</head>",
            source,
            count=1,
            flags=re.I,
        )
    return source


def pdf_info(path: Path) -> tuple[int | None, tuple[float, float] | None]:
    executable = shutil.which("pdfinfo")
    if executable:
        result = run([executable, str(path)])
        pages_match = re.search(r"^Pages:\s+(\d+)", result.stdout, flags=re.M)
        size_match = re.search(
            r"^Page size:\s+([0-9.]+)\s+x\s+([0-9.]+)\s+pts",
            result.stdout,
            flags=re.M,
        )
        pages = int(pages_match.group(1)) if pages_match else None
        size = (
            (float(size_match.group(1)), float(size_match.group(2)))
            if size_match
            else None
        )
        return pages, size

    # Chrome leaves its page dictionaries and MediaBox readable even when the
    # content streams are compressed. This keeps the safety gate functional
    # before a fresh NixOS generation has made poppler-utils available.
    payload = path.read_bytes()
    pages = len(re.findall(rb"/Type\s*/Page\b", payload)) or None
    box_match = re.search(
        rb"/MediaBox\s*\[\s*([-0-9.]+)\s+([-0-9.]+)\s+"
        rb"([-0-9.]+)\s+([-0-9.]+)\s*\]",
        payload,
    )
    if not box_match:
        return pages, None
    x1, y1, x2, y2 = (float(value) for value in box_match.groups())
    return pages, (x2 - x1, y2 - y1)


def fitted_profile(profile: Profile, layout: str) -> Profile:
    geometry = LAYOUTS[layout]
    leading = profile.line_height
    if geometry.leading is not None:
        leading = min(leading, geometry.leading) if geometry.scale == 1.0 else geometry.leading
    size = profile.size_pt
    if geometry.scale != 1.0:
        size = max(BODY_FLOOR_PT, size * geometry.scale)
    return replace(profile, size_pt=size, line_height=leading)


# --- Page-quality measurement (#673) ---------------------------------------
#
# A readable PDF and a printer receipt do not prove a well-paginated document.
# These checks read the rendered PDF's own text geometry (pdftotext
# -bbox-layout) and compare it with the HTML that produced it. Hard defects
# block printing; nothing a model says can override them. Soft findings steer
# the bounded layout choice in print-auto.py.

NEAR_EMPTY_FILL = 0.25
SHORT_TAIL_LINES = 3
GIANT_TABLE_ROWS = 30
GIANT_TABLE_COLUMNS = 7
DENSE_CELL_CHARS = 160


def normalize_text(value: str) -> str:
    return "".join(ch for ch in value.casefold() if ch.isalnum())


def text_tokens(value: str) -> list[str]:
    return re.findall(r"[^\W_]+", value.casefold())


@dataclass
class SourceFacts:
    """What the renderer was asked to show, read back from its HTML."""
    text: list[str] = field(default_factory=list)
    headings: list[str] = field(default_factory=list)
    anchors: list[str] = field(default_factory=list)
    tables: list[dict] = field(default_factory=list)
    images: int = 0


class SourceCollector(HTMLParser):
    SKIP = {"head", "style", "script", "title"}
    BLOCKS = {"h1", "h2", "h3", "h4", "h5", "h6", "p"}

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.facts = SourceFacts()
        self.skip = 0
        self.block: list[str] | None = None
        self.block_tag = ""
        self.table_depth = 0
        self.table: dict | None = None
        self.cell: list[str] | None = None

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag in self.SKIP:
            self.skip += 1
        elif tag == "img":
            self.facts.images += 1
        elif tag == "table":
            self.table_depth += 1
            if self.table_depth == 1:
                self.table = {"rows": 0, "columns": 0, "cell_chars": []}
        elif tag == "tr" and self.table is not None and self.table_depth == 1:
            self.table["rows"] += 1
            self.table["_cols"] = 0
        elif tag in ("td", "th") and self.table is not None and self.table_depth == 1:
            self.table["_cols"] = self.table.get("_cols", 0) + 1
            self.table["columns"] = max(self.table["columns"], self.table["_cols"])
            self.cell = []
        elif tag in self.BLOCKS and not self.table_depth:
            self.block, self.block_tag = [], tag

    def handle_endtag(self, tag: str) -> None:
        if tag in self.SKIP and self.skip:
            self.skip -= 1
        elif tag == "table" and self.table_depth:
            self.table_depth -= 1
            if not self.table_depth and self.table is not None:
                cells = self.table.pop("cell_chars")
                self.table.pop("_cols", None)
                self.table["max_cell_chars"] = max(cells, default=0)
                self.facts.tables.append(self.table)
                self.table = None
        elif tag in ("td", "th") and self.cell is not None and self.table is not None:
            self.table["cell_chars"].append(len(" ".join("".join(self.cell).split())))
            self.cell = None
        elif tag == self.block_tag and self.block is not None:
            text = " ".join("".join(self.block).split())
            if text:
                if tag.startswith("h"):
                    self.facts.headings.append(text)
                self.facts.anchors.append(text)
            self.block, self.block_tag = None, ""

    def handle_data(self, data: str) -> None:
        if self.skip:
            return
        self.facts.text.append(data)
        if self.block is not None:
            self.block.append(data)
        if self.cell is not None:
            self.cell.append(data)


def source_facts(body: str) -> SourceFacts:
    collector = SourceCollector()
    collector.feed(body)
    collector.close()
    return collector.facts


@dataclass
class TextLine:
    x_min: float
    y_min: float
    x_max: float
    y_max: float
    words: list[str]

    @property
    def text(self) -> str:
        return " ".join(self.words)


@dataclass
class PageText:
    width: float
    height: float
    lines: list[TextLine]


class BboxParser(HTMLParser):
    """Reads `pdftotext -bbox-layout` XHTML: pages, lines and words."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.pages: list[PageText] = []
        self.line: TextLine | None = None
        self.word: list[str] | None = None

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        values = {key: value or "0" for key, value in attrs}
        if tag == "page":
            self.pages.append(PageText(float(values["width"]), float(values["height"]), []))
        elif tag == "line" and self.pages:
            self.line = TextLine(float(values["xmin"]), float(values["ymin"]),
                                 float(values["xmax"]), float(values["ymax"]), [])
        elif tag == "word" and self.line is not None:
            self.word = []

    def handle_endtag(self, tag: str) -> None:
        if tag == "word" and self.word is not None and self.line is not None:
            self.line.words.append("".join(self.word))
            self.word = None
        elif tag == "line" and self.line is not None:
            if self.line.words:
                self.pages[-1].lines.append(self.line)
            self.line = None

    def handle_data(self, data: str) -> None:
        if self.word is not None:
            self.word.append(data)


def parse_bbox(xhtml: str) -> list[PageText]:
    parser = BboxParser()
    parser.feed(xhtml)
    parser.close()
    return parser.pages


def _overlaps(a: TextLine, b: TextLine) -> bool:
    width = min(a.x_max, b.x_max) - max(a.x_min, b.x_min)
    height = min(a.y_max, b.y_max) - max(a.y_min, b.y_min)
    if width <= 0 or height <= 0:
        return False
    smaller = min((a.x_max - a.x_min) * (a.y_max - a.y_min),
                  (b.x_max - b.x_min) * (b.y_max - b.y_min))
    return smaller > 0 and width * height > 0.3 * smaller


def assess_layout(pages: list[PageText], facts: SourceFacts, geometry: Layout,
                  *, body_pt: float, table_pt: float) -> dict:
    """Measure every page and list the layout defects of one candidate."""
    defects: list[dict] = []

    def defect(kind: str, severity: str, detail: str, page: int | None = None) -> None:
        entry = {"kind": kind, "severity": severity, "detail": detail}
        if page is not None:
            entry["page"] = page
        defects.append(entry)

    headings = [normalize_text(h) for h in facts.headings if normalize_text(h)]
    count = len(pages)
    page_facts: list[dict] = []
    stream: list[str] = []
    prefixes: set[str] = set()
    words: set[str] = set()

    for number, page in enumerate(pages, 1):
        left = geometry.side_mm * MM
        right = page.width - geometry.side_mm * MM
        top = geometry.top_mm * MM
        bottom = page.height - geometry.bottom_mm * MM
        # Page furniture (the folio and the optional profile caption) lives
        # in the bottom margin box, outside the content box.
        content = sorted((line for line in page.lines if line.y_min < bottom - 0.5),
                         key=lambda line: (round(line.y_min, 1), line.x_min))
        for line in content:
            if (line.x_min < left - 3 or line.x_max > right + 3 or line.y_min < top - 3
                    or line.x_max > page.width or line.y_max > page.height):
                defect("overflow", "hard",
                       f"text outside the content box: {line.text[:60]!r}", number)
                break
        for index, first in enumerate(content):
            if any(_overlaps(first, second) for second in content[index + 1:]):
                defect("overlap", "hard", f"overlapping text near {first.text[:60]!r}", number)
                break

        def is_heading(line: TextLine) -> bool:
            value = normalize_text(line.text)
            return (len(value) >= 2 and abs(line.x_min - left) <= 1.5
                    and any(value in heading for heading in headings))

        flags = [is_heading(line) for line in content]
        fill = 0.0
        if content:
            fill = max(0.0, min(1.0, (max(l.y_max for l in content) - top) / (bottom - top)))
        page_facts.append({"page": number, "lines": len(content),
                           "heading_lines": sum(flags), "fill": round(fill, 3)})
        final = number == count
        if count > 1:
            if content and all(flags):
                defect("heading_only_page", "hard",
                       "the page holds only a section heading; its content starts overleaf",
                       number)
            elif not final and content and flags[max(range(len(content)),
                                                     key=lambda i: content[i].y_max)]:
                defect("heading_at_page_foot", "hard",
                       "a heading ends the page and its content starts overleaf", number)
            if not content:
                defect("blank_page", "soft" if facts.images else "hard",
                       "the page has no text", number)
            elif not final and fill < NEAR_EMPTY_FILL and not all(flags):
                defect("near_empty_page", "soft" if facts.images else "hard",
                       f"only {fill:.0%} of the page is used before a page break", number)
            if final and content and not all(flags) and len(content) <= SHORT_TAIL_LINES:
                defect("short_tail", "soft",
                       f"the last page carries only {len(content)} line(s); a reflow may save it",
                       number)
        for line in content:
            stream.append(normalize_text(line.text))
            for word in line.words:
                words.add(normalize_text(word))
                if word[-1:] in "-‐­":
                    prefixes.add(normalize_text(word))
            prefixes.add(normalize_text(line.words[-1]))

    rendered = "".join(stream)
    # Source preservation: every source character and word is on the page.
    # Repeated table headers and list markers may add text; nothing may be lost.
    source_text = "".join(facts.text)
    wanted, have = Counter(normalize_text(source_text)), Counter(rendered)
    short = {ch: wanted[ch] - have[ch] for ch in wanted if have[ch] < wanted[ch]}
    if short:
        defect("content_missing", "hard",
               f"{sum(short.values())} source character(s) are not in the PDF text")
    missing = []
    for token in dict.fromkeys(text_tokens(source_text)):
        if token in rendered:
            continue
        # A word broken at a line end inside a table cell may be interleaved
        # with the neighbouring cell in reading order.
        if any(token[:cut] in prefixes and token[cut:] in words
               for cut in range(1, len(token))):
            continue
        missing.append(token)
    if missing:
        defect("content_missing", "hard",
               f"{len(missing)} source word(s) are not in the PDF text, e.g. {missing[:5]}")
    # Reading order: headings and paragraphs appear in source order.
    position = 0
    for anchor in facts.anchors:
        value = normalize_text(anchor)[:32]
        if not value:
            continue
        found = rendered.find(value, position)
        if found < 0:
            defect("reading_order", "hard", f"out of order or missing: {anchor[:60]!r}")
            break
        position = found + len(value)

    if body_pt < BODY_FLOOR_PT or table_pt < TABLE_FLOOR_PT:
        defect("unreadable_type", "hard",
               f"type below the readable floor (body {body_pt:g} pt, tables {table_pt:g} pt)")

    advisories = []
    for index, table in enumerate(facts.tables, 1):
        if (table["rows"] > GIANT_TABLE_ROWS or table["columns"] >= GIANT_TABLE_COLUMNS
                or table["max_cell_chars"] > DENSE_CELL_CHARS):
            advisories.append({
                "kind": "giant_table", "table": index, **table,
                "detail": "a long or dense table reads poorly on paper; prose or short "
                          "lists suit narrative material (#673). Printed as submitted.",
            })
    return {
        "status": "measured",
        "pages": count,
        "type": {"body_pt": round(body_pt, 3), "table_pt": round(table_pt, 3)},
        "page_facts": page_facts,
        "defects": defects,
        "advisories": advisories,
    }


def measure_pdf(path: Path, body: str, *, layout: str, profile: Profile) -> dict:
    table_pt = max(TABLE_FLOOR_PT, round(profile.size_pt * TABLE_SCALE, 3))
    executable = shutil.which("pdftotext")
    pages, _ = pdf_info(path)
    if not executable:
        return {"status": "unmeasured", "pages": pages, "page_facts": [], "advisories": [],
                "type": {"body_pt": profile.size_pt, "table_pt": table_pt},
                "defects": [{"kind": "unmeasured", "severity": "hard",
                             "detail": "pdftotext is unavailable; the layout cannot be checked"}]}
    result = run([executable, "-bbox-layout", str(path), "-"])
    report = assess_layout(parse_bbox(result.stdout), source_facts(body), LAYOUTS[layout],
                           body_pt=profile.size_pt, table_pt=table_pt)
    report["layout"] = layout
    return report


def render_pdf(renderer: str, page: str, output: Path, *, keep_html: bool) -> Path:
    output.parent.mkdir(parents=True, exist_ok=True)
    html_path = output.with_suffix(".html")
    temporary_html = not keep_html
    if temporary_html:
        handle = tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            suffix=".html",
            prefix="print-paper-",
            delete=False,
        )
        handle.write(page)
        handle.close()
        html_path = Path(handle.name)
    else:
        html_path.write_text(page, encoding="utf-8")

    try:
        result = run(
            [renderer, "--allowed-protocols", "file,data", str(html_path), str(output.resolve())],
            check=False,
        )
        if result.returncode or not output.exists() or not output.stat().st_size:
            detail = (result.stderr or result.stdout).strip()
            fail(f"WeasyPrint PDF export failed for {output.name}: {detail}")
        if result.stderr:
            print(result.stderr.strip(), file=sys.stderr)
    finally:
        if temporary_html:
            html_path.unlink(missing_ok=True)

    pages, size = pdf_info(output)
    if size and (abs(size[0] - 595.28) > 2 or abs(size[1] - 841.89) > 2):
        fail(f"{output.name} is not A4 ({size[0]:.2f} × {size[1]:.2f} pt)")
    if pages is not None:
        print(f"rendered {output} ({pages} page{'s' if pages != 1 else ''}, A4)")
    else:
        print(f"rendered {output} (A4)")
    return output


def submit_print(path: Path, *, printer: str, copies: int, sides: str) -> str:
    lp = shutil.which("lp")
    lpstat = shutil.which("lpstat")
    if not lp or not lpstat:
        fail("CUPS client commands lp/lpstat are unavailable")
    state = run([lpstat, "-p", printer], check=False)
    if state.returncode:
        fail(f"printer {printer!r} is unavailable: {(state.stderr or state.stdout).strip()}")
    options = {
        "one-sided": "one-sided",
        "long-edge": "two-sided-long-edge",
        "short-edge": "two-sided-short-edge",
    }
    result = run(
        [
            lp,
            "-d",
            printer,
            "-n",
            str(copies),
            "-o",
            "media=A4",
            "-o",
            f"sides={options[sides]}",
            str(path),
        ]
    )
    message = result.stdout.strip()
    print(f"queued {path.name}: {message}")
    return message


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Render Markdown/text/HTML into readable A4 PDFs through headless Chrome."
    )
    parser.add_argument("input", nargs="?", help="input .md, .txt, or .html file; use - for stdin")
    parser.add_argument(
        "--profile",
        action="append",
        default=[],
        help="type profile; repeat to render variants",
    )
    parser.add_argument(
        "--compare",
        action="store_true",
        help="render garamond, baskerville, source-serif, and times variants",
    )
    parser.add_argument("--list-profiles", action="store_true", help="list profiles and exit")
    parser.add_argument("--check-assets", action="store_true",
                        help="check compute portability without starting a browser or printing")
    parser.add_argument("-o", "--output", type=Path, help="output path for one profile")
    parser.add_argument(
        "--output-dir",
        type=Path,
        help="directory for generated PDFs (default: beside input)",
    )
    parser.add_argument("--title", help="document title metadata override")
    parser.add_argument("--layout", choices=tuple(LAYOUTS), default="standard",
                        help="bounded page fitting; source text is unchanged and type stays at least 10 pt")
    parser.add_argument("--measure", type=Path,
                        help="write the page-quality measurement of the one rendered PDF as JSON (#673)")
    parser.add_argument(
        "--label",
        action="store_true",
        help="add the profile name and metrics at the page foot",
    )
    parser.add_argument("--keep-html", action="store_true", help="keep generated HTML beside PDF")
    parser.add_argument(
        "--require-one-page",
        action="store_true",
        help="fail before printing if any result is not exactly one page",
    )
    parser.add_argument("--force", action="store_true", help="replace existing output files")
    parser.add_argument(
        "--print",
        dest="submit",
        action="store_true",
        help="submit every validated PDF to CUPS",
    )
    parser.add_argument(
        "--submit-only",
        action="store_true",
        help=(
            "skip rendering; treat input as an already-rendered .pdf and submit "
            "it to CUPS directly. Pairs with a prior render-only invocation so "
            "submission never races a still-being-revised document (issue #227)."
        ),
    )
    parser.add_argument("--printer", default=DEFAULT_PRINTER, help="CUPS destination")
    parser.add_argument("--copies", type=int, default=1, help="copies per PDF")
    parser.add_argument(
        "--sides",
        choices=("one-sided", "long-edge", "short-edge"),
        default="long-edge",
        help="CUPS duplex mode (default: long-edge duplex, to save paper)",
    )
    args = parser.parse_args()
    if args.copies < 1:
        parser.error("--copies must be at least 1")
    return args


def main() -> None:
    args = parse_args()
    if args.list_profiles:
        for name, profile in PROFILES.items():
            print(
                f"{name:14} {profile.label:34} "
                f"{profile.size_pt:g} pt / {profile.line_height:g}"
            )
        return
    if not args.input:
        fail("an input file is required (or use --list-profiles)")

    if args.submit_only:
        # Deliberately does not render. This is the second half of the
        # render-verify-submit contract (issue #227): the caller renders
        # WITHOUT --print, verifies the result against whatever the user
        # asked for (page count, completeness), and only then re-invokes the
        # script in this mode to queue the already-verified PDF exactly
        # once. There is no code path here that can feed the printer pages
        # from a document that has not already been rendered and inspected.
        pdf_path = Path(args.input).expanduser().resolve()
        if not pdf_path.is_file():
            fail(f"--submit-only target does not exist: {pdf_path}")
        if pdf_path.suffix.lower() != ".pdf":
            fail(f"--submit-only expects an already-rendered .pdf, got {pdf_path.name}")
        submit_print(pdf_path, printer=args.printer, copies=args.copies, sides=args.sides)
        return

    if args.compare:
        profile_names = list(PROFILES)
        if args.profile:
            fail("--compare and --profile are mutually exclusive")
    else:
        profile_names = [normalize_profile(name) for name in args.profile] or ["source-serif"]
    profile_names = list(dict.fromkeys(profile_names))
    if args.output and len(profile_names) != 1:
        fail("--output is valid only when rendering one profile")
    if args.measure and len(profile_names) != 1:
        fail("--measure is valid only when rendering one profile")

    if args.input == "-":
        source = sys.stdin.read()
        input_path = None
        stem = "document"
        base_uri = Path.cwd().resolve().as_uri() + "/"
        suffix = ".md"
    else:
        input_path = Path(args.input).expanduser().resolve()
        if not input_path.is_file():
            fail(f"input does not exist: {input_path}")
        source = input_path.read_text(encoding="utf-8")
        stem = input_path.stem
        base_uri = input_path.parent.as_uri() + "/"
        suffix = input_path.suffix.lower()

    if suffix in (".html", ".htm"):
        body = source
        detected_title = None
    else:
        body, detected_title = markdown_to_html(source)
    if args.check_assets:
        if external_image_sources(body):
            fail("a compute-rendered Markdown drop cannot fetch external images; "
                 "drop an existing PDF or use self-contained image data")
        return
    title = args.title or detected_title or stem.replace("-", " ").replace("_", " ").title()

    output_dir = (
        args.output_dir.expanduser().resolve()
        if args.output_dir
        else (input_path.parent if input_path else Path.cwd())
    )
    outputs: list[Path] = []
    renderer = find_renderer()
    use_label = args.label or args.compare

    for profile_name in profile_names:
        profile = PROFILES[profile_name]
        require_font(profile)
        profile = fitted_profile(profile, args.layout)
        output = (
            args.output.expanduser().resolve()
            if args.output
            else output_dir / f"{stem}--{profile_name}.pdf"
        )
        if output.exists() and not args.force:
            fail(f"refusing to replace {output}; pass --force to replace it")
        page = (
            html_input_document(
                body,
                title=title,
                base_uri=base_uri,
                profile=profile,
                label=use_label,
                layout=args.layout,
            )
            if suffix in (".html", ".htm")
            else document_html(
                body,
                title=title,
                base_uri=base_uri,
                profile=profile,
                label=use_label,
                layout=args.layout,
            )
        )
        outputs.append(render_pdf(renderer, page, output, keep_html=args.keep_html))
        if args.measure:
            report = measure_pdf(output, body, layout=args.layout, profile=profile)
            args.measure.parent.mkdir(parents=True, exist_ok=True)
            args.measure.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
            hard = [d for d in report["defects"] if d["severity"] == "hard"]
            print(f"measured {output.name}: {report['pages']} page(s), "
                  f"{len(hard)} hard layout defect(s)")

    if args.require_one_page:
        bad: list[str] = []
        for output in outputs:
            pages, _ = pdf_info(output)
            if pages != 1:
                bad.append(f"{output.name}: {pages if pages is not None else 'unknown'} pages")
        if bad:
            fail("one-page requirement failed: " + "; ".join(bad))

    if args.submit:
        for output in outputs:
            submit_print(
                output,
                printer=args.printer,
                copies=args.copies,
                sides=args.sides,
            )


if __name__ == "__main__":
    main()
