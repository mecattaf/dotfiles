#!/usr/bin/env python3
"""Render Markdown, text, or HTML as local A4 PDFs and optionally print them."""

from __future__ import annotations

import argparse
import html
import os
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
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


def fail(message: str) -> NoReturn:
    raise SystemExit(f"print-paper: {message}")


def run(command: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(command, capture_output=True, text=True)
    if check and result.returncode:
        detail = (result.stderr or result.stdout).strip()
        fail(f"command failed ({command[0]}): {detail}")
    return result


def find_chrome() -> str:
    for name in ("google-chrome", "google-chrome-stable", "chromium", "chromium-browser"):
        path = shutil.which(name)
        if path:
            return path
    fail("Chrome/Chromium is not available on PATH")


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
    escaped = re.sub(r"__(.+?)__", r"<strong>\1</strong>", escaped)
    escaped = re.sub(r"~~(.+?)~~", r"<del>\1</del>", escaped)
    escaped = re.sub(r"(?<!\*)\*([^*\n]+)\*(?!\*)", r"<em>\1</em>", escaped)
    escaped = re.sub(r"(?<!_)_([^_\n]+)_(?!_)", r"<em>\1</em>", escaped)
    for index, fragment in enumerate(stash):
        escaped = escaped.replace(f"\x00{index}\x01", fragment)
    return escaped


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


def print_css(profile: Profile, *, label: bool = False) -> str:
    caption = (
        f"{profile.label} · {profile.size_pt:g} pt · {profile.line_height:g} line height"
    )
    label_box = (
        f"""
  @bottom-center {{
    content: {css_string(caption)};
    color: #555;
    font-family: "SF Pro Text", sans-serif;
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
  margin: 20mm 30mm 21mm;
  /* Chrome runs with --no-pdf-header-footer, so these margin boxes are the
     only page furniture. Both sit in the reserved bottom margin, outside the
     content box: the bare folio at the right, the optional profile caption
     centered well clear of it. */
  @bottom-right {{
    content: counter(page);
    color: #666;
    font-family: "SF Pro Text", sans-serif;
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
  break-inside: avoid-page;
  font-style: italic;
  margin: 1.05em 0 1.05em 1.1em;
  padding-left: 1em;
}}
blockquote p {{ margin: 0; }}
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
table {{
  border-collapse: collapse;
  break-inside: avoid-page;
  font-size: 0.9em;
  margin: 0.8em 0 1em;
  width: 100%;
}}
th, td {{
  border-bottom: 0.5pt solid #999;
  padding: 0.35em 0.5em;
  text-align: left;
  vertical-align: top;
}}
th {{ font-weight: 600; }}
pre {{
  background: #f4f4f2;
  break-inside: avoid-page;
  overflow: hidden;
  padding: 0.8em 0.9em;
  white-space: pre-wrap;
}}
code {{
  font-family: "Liga SFMono Nerd Font", "JetBrainsMono Nerd Font", monospace;
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
) -> str:
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<base href="{html.escape(base_uri, quote=True)}">
<title>{html.escape(title)}</title>
<style>{print_css(profile, label=label)}</style>
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
) -> str:
    if not re.search(r"<html[\s>]", source, flags=re.I):
        return document_html(
            source,
            title=title,
            base_uri=base_uri,
            profile=profile,
            label=label,
        )
    additions = (
        f'<base href="{html.escape(base_uri, quote=True)}">\n'
        f"<style>{print_css(profile, label=label)}</style>\n"
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


def render_pdf(chrome: str, page: str, output: Path, *, keep_html: bool) -> Path:
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
        with tempfile.TemporaryDirectory(prefix="print-paper-chrome-") as profile_dir:
            result = run(
                [
                    chrome,
                    "--headless=new",
                    "--disable-gpu",
                    "--disable-extensions",
                    "--no-first-run",
                    "--no-pdf-header-footer",
                    "--allow-file-access-from-files",
                    f"--user-data-dir={profile_dir}",
                    f"--print-to-pdf={output.resolve()}",
                    html_path.resolve().as_uri(),
                ],
                check=False,
            )
            if result.returncode or not output.exists() or not output.stat().st_size:
                detail = (result.stderr or result.stdout).strip()
                fail(f"Chrome PDF export failed for {output.name}: {detail}")
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
    parser.add_argument("-o", "--output", type=Path, help="output path for one profile")
    parser.add_argument(
        "--output-dir",
        type=Path,
        help="directory for generated PDFs (default: beside input)",
    )
    parser.add_argument("--title", help="document title metadata override")
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
    title = args.title or detected_title or stem.replace("-", " ").replace("_", " ").title()

    output_dir = (
        args.output_dir.expanduser().resolve()
        if args.output_dir
        else (input_path.parent if input_path else Path.cwd())
    )
    outputs: list[Path] = []
    chrome = find_chrome()
    use_label = args.label or args.compare

    for profile_name in profile_names:
        profile = PROFILES[profile_name]
        require_font(profile)
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
            )
            if suffix in (".html", ".htm")
            else document_html(
                body,
                title=title,
                base_uri=base_uri,
                profile=profile,
                label=use_label,
            )
        )
        outputs.append(render_pdf(chrome, page, output, keep_html=args.keep_html))

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
