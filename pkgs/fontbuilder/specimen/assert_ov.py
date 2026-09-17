"""Pre-flight for specimen/review-window.sh.

Re-parses the SAME --override strings the spawner will pass, through kitty's
own CLI parser, and demands the 4-tuple AND an empty bad-lines list.  Exits 1
otherwise, which is what makes the spawner refuse to open a window.

The strings arrive in REVIEW_ARGV, joined with \\x1f.  NEVER \\0: bash silently
drops NUL bytes in a variable, and the first attempt at this passed the
pre-flight while the window resolved to Liga SFMono - the very font the review
is comparing against.

Run as `kitty +runpy`, which is headless python inside kitty's runtime.  It
opens no window and touches nothing on disk.
"""
import os
import sys

from kitty.cli import create_opts, parse_args
from kitty.cli_stub import CLIOptions
from kitty.fonts.common import get_font_files

# Patcher 3.5.1 added FontnameParser._remove_regular: the RIBBI Regular face
# ships the BARE PostScript name, no -Regular token.  The Regular-weight
# italic is still -Italic and every other face keeps its -<Style> suffix.
WANT = {"medium": "AnthropicMonoNFM",
        "bold": "AnthropicMonoNFM-SemiBold",
        "italic": "AnthropicMonoNFM-Italic",
        "bi": "AnthropicMonoNFM-SemiBoldItalic"}

argv = [a for a in os.environ["REVIEW_ARGV"].split("\x1f") if a]
cli, rest = parse_args(args=argv + ["--hold"], result_class=CLIOptions, usage=None,
                       message=None, appname=None, preparsed_from_c=None)
bad = []
opts = create_opts(cli, accumulate_bad_lines=bad)
ff = get_font_files(opts)
ok = True
for k in ("medium", "bold", "italic", "bi"):
    got = ff[k].get("postscript_name")
    print("   %-7s %-34s %s" % (k, got, "OK" if got == WANT[k] else "WRONG, want " + WANT[k]))
    ok &= got == WANT[k]
if bad:
    ok = False
    for b in bad:
        print("   BAD CONFIG LINE:", b.line, "->", b.exception)
sys.exit(0 if ok else 1)
