#!/usr/bin/env python3
"""fontbuilder stage S12 - tar, zstd, SHA256SUMS, README.

    package.py <stage-dir> <dist-dir> <epoch> [--origins FILE]

<stage-dir> holds THREE separate roots, one per tarball (measured C9: mapping
two tarballs to the same root emitted two byte-identical archives):

    stage/mono/truetype/   12 terminal faces   -> anthropic-mono-nerd-fonts.tar.zst
    stage/ui/truetype/      5 desktop faces    -> anthropic-ui-fonts.tar.zst
    stage/web/{css,woff2}/  1 css + 7 woff2    -> anthropic-webfonts.tar.zst

MEASURED rules, each load-bearing:
  * --format=gnu, NO --pax-option: with gnu format tar exits 2 and writes ZERO
    bytes (the 13-byte artifact people report is zstd's empty-frame overhead,
    reachable only when tar's exit status is dropped). subprocess check=True
    raises here. The FILE count below guards a different failure: an empty or
    under-populated stage dir tars fine, makes a valid 66-byte archive, and
    shows the same zstd fingerprint as a good one.
  * --mtime=@0, unconditionally: both apple/ archives carry 1970-01-01 entry
    times. SOURCE_DATE_EPOCH governs head INSIDE each font, not the archive.
  * --sort=name --numeric-owner --owner=0 --group=0, entries 0444/0555: the
    sf-pro shape (bare top-level dir, no './' entry, dr-xr-xr-x 0/0).
  * streamed into `zstd -19 -T1` (not `zstd -o file`): reproduces the apple/
    fingerprint - Frames 1, XXH64, Window 8.00 MiB, NO Decompressed Size line.
    -T1 makes it byte-reproducible; no --long (changes the window size).
  * tar from a THROWAWAY copy in $TMPDIR (chmod'd 0444/0555 there), never the
    stage tree itself: a hardened stage cannot be rm -rf'd and every rebuild
    into an existing out-dir would abort.
  * basenames are dot-free before .tar.zst (update-center-seed strips the
    GC-root name at the FIRST dot) and equal the requireFile `name`.
  * the three digests must be pairwise distinct.
"""
import argparse
import hashlib
import os
import shutil
import subprocess
import sys
import tempfile
import time

TARBALLS = {
    "anthropic-mono-nerd-fonts.tar.zst": ("mono", ["truetype"], 12),
    "anthropic-ui-fonts.tar.zst": ("ui", ["truetype"], 5),
    "anthropic-webfonts.tar.zst": ("web", ["css", "woff2"], 8),
}
TAR = ["tar", "--format=gnu", "--sort=name", "--numeric-owner", "--owner=0", "--group=0", "--mtime=@0"]


def harden(tree):
    for root, dirnames, filenames in os.walk(tree, topdown=False):
        for f in filenames:
            os.chmod(os.path.join(root, f), 0o444)
        for d in dirnames:
            os.chmod(os.path.join(root, d), 0o555)


def unharden(tree):
    for root, dirnames, filenames in os.walk(tree):
        os.chmod(root, 0o755)
        for f in filenames:
            os.chmod(os.path.join(root, f), 0o644)


def build_one(stage_root, dirs, out_path, min_files):
    with tempfile.TemporaryDirectory(prefix="fontbuilder-pack.") as tmp:
        work = os.path.join(tmp, "root")
        shutil.copytree(stage_root, work)
        harden(work)
        tarball = subprocess.run(TAR + ["-cf", "-", *dirs], cwd=work, check=True,
                                 stdout=subprocess.PIPE).stdout
        unharden(work)
    names = subprocess.run(["tar", "-tf", "-"], input=tarball, check=True,
                           stdout=subprocess.PIPE).stdout.decode().split("\n")
    names = [n for n in names if n]
    files = [n for n in names if not n.endswith("/")]
    if len(files) < min_files:
        raise SystemExit("fontbuilder: %s would ship %d file(s), expected >= %d - refusing"
                         % (os.path.basename(out_path), len(files), min_files))
    for n in names:
        if n.startswith("./") or n.startswith("/"):
            raise SystemExit("fontbuilder: %s has a bad entry name %r" % (out_path, n))
    with open(out_path, "wb") as fh:
        subprocess.run(["zstd", "-19", "-T1", "-q", "-c"], input=tarball, stdout=fh, check=True)
    os.chmod(out_path, 0o444)
    return files


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


README_TMPL = """# Anthropic fonts — durable fleet copy (NAS M.2)

Every Anthropic face the fleet installs, as the exact bytes pressed on %(date)s
by `pkgs/fontbuilder` in mecattaf/dotfiles from the read-only capture at
`~/colors/waves/capture`. dotfiles pins each archive by sha256 (`requireFile`)
and never downloads them; no font binary is in that repo.

| file | family | consumer |
|---|---|---|
| anthropic-mono-nerd-fonts.tar.zst | AnthropicMono Nerd Font Mono (12 statics, ligaturized + Nerd-patched) | pkgs/anthropic-mono-nerd.nix (kitty terminal face, `monospace`) |
| anthropic-ui-fonts.tar.zst | Anthropic Sans, Anthropic Serif (variable), Anthropicons | pkgs/anthropic-ui.nix (GTK UI, Chrome `sans-serif`/`serif`) |
| anthropic-webfonts.tar.zst | woff2 of the same faces + css/anthropic-fonts.css | pkgs/anthropic-webfonts.nix (webapps; installed OUTSIDE fontconfig's scan path) |

Origins:
%(origins)s

The coordinator's `update-center-seed` adds these to the NAS store each night
and GC-roots them under /var/lib/update-center/seeds. Manual recovery on a host:

    scp root@nas:/mnt/fast/fonts/anthropic/<file> . && nix-store --add-fixed sha256 <file>

Never modify or rename these files; a replacement means a new sha256 in dotfiles.
"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("stage")
    ap.add_argument("dist")
    ap.add_argument("epoch", type=int)
    ap.add_argument("--origins", help="text file with the Origins paragraph (from manifest.py)")
    a = ap.parse_args()
    os.makedirs(a.dist, exist_ok=True)
    made = []
    for name, (root, dirs, min_files) in TARBALLS.items():
        stage_root = os.path.join(a.stage, root)
        if not os.path.isdir(stage_root):
            raise SystemExit("fontbuilder: stage root %s missing" % stage_root)
        out = os.path.join(a.dist, name)
        if os.path.exists(out):
            os.chmod(out, 0o644)
            os.remove(out)
        files = build_one(stage_root, dirs, out, min_files)
        made.append(name)
        print("package: %s  %d files  %d bytes" % (name, len(files), os.path.getsize(out)))
    sums = [(sha256_file(os.path.join(a.dist, n)), n) for n in made]
    if len({h for h, _ in sums}) != len(sums):
        raise SystemExit("fontbuilder: two tarballs hash identically - stage roots are wrong")
    sums_path = os.path.join(a.dist, "SHA256SUMS")
    if os.path.exists(sums_path):
        os.chmod(sums_path, 0o644)
    with open(sums_path, "w", encoding="utf-8") as fh:
        for h, n in sums:
            fh.write("%s  %s\n" % (h, n))
            print("%s  %s" % (h, n))
    os.chmod(sums_path, 0o444)
    origins = open(a.origins, encoding="utf-8").read().rstrip() if a.origins else "see manifest.json beside this build"
    readme = os.path.join(a.dist, "README.md")
    if os.path.exists(readme):
        os.chmod(readme, 0o644)
    with open(readme, "w", encoding="utf-8") as fh:
        fh.write(README_TMPL % {"date": time.strftime("%Y-%m-%d", time.gmtime(a.epoch)), "origins": origins})
    os.chmod(readme, 0o644)
    return 0


if __name__ == "__main__":
    sys.exit(main())
