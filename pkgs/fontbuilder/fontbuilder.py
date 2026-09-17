#!/usr/bin/env python3
"""fontbuilder - the press for the Anthropic font suite.

    nix run .#fontbuilder -- <capture-dir> <out-dir> [--align anchor|none] [--braille-dy N]
                                                     [--only mono|desktop|webfonts|all]
                                                     [--weights 400,600] [--skip-nerd]
                                                     [--skip-specimens] [--verify-repro]
    nix run .#fontbuilder -- --verify <out-dir> [--src <capture-dir>]
    nix run .#fontbuilder -- --package <out-dir>
    nix run .#fontbuilder -- --print-nix-hashes <out-dir>
    nix run .#fontbuilder -- --rehash-sources <capture-dir>

Ships the RECIPE and no bytes. The Anthropic faces are unlicensed brand trade
dress: they live on the fleet's NAS M.2 only (nas:/mnt/fast/fonts/anthropic/),
are pinned by sha256 in pkgs/anthropic-*.nix, and never enter this repo. This
package builds, and its checkPhase passes, on a machine that has never seen the
capture tree: stage S0 then exits 2 and names the mismatch.

STAGES, in execution order (every arrow is measured; see README.md):

  S0  verify-sources   fail closed against data/sources.sha256 (14 files)
  S1  repair-source    on the VARIABLE Mono: strip the STAT ' Italic' doubling,
                       zero the bogus phantom deltas (37 marks at 2400 @ wght 300)
  S2  instance         fontTools instancer, updateFontNames -> 12 statics
  S3  normalize        name table + fsSelection/macStyle/italicAngle + cell
  S4  merge            completeness sweep from the OFL/free donors (+ U+2800)
  S5  ligaturize       Fira Code 3.001 via Ligaturizer, per-weight donor, --prefix ""
  S8  canonicalize     (the S5 output: Ligaturizer writes FFTM + head wall clock)
  S6  align-ligatures  per-ligature constituent delta with the ANCHOR veto; shear italics
  S7  nerd-patch       LAST: the only stage that validates names (--makegroups 4)
  S7b regraft-pua      restore U+E001-E00A that --complete overwrote with Pomicons
  S8  canonicalize     pin head.created/modified -> byte reproducibility
  S9  desktop          Sans/Serif stay VARIABLE: unshare/strip/rename/gc + italic bits
  S10 icons            Anthropicons: synthesise names, pin the default instance
  S11 webfonts         woff2 re-emitted from the normalized faces + the @font-face sheet
  S12 package          three stage roots -> tar --format=gnu | zstd -19 -T1, SHA256SUMS, README

FontForge (under both Ligaturizer and the patcher) flattens variable fonts to
their default instance, which is why S2 comes first. The patcher is last
because it is the only stage that validates the name table; shaunsingh's
LigaSFMono ran them the other way round and ships a non-conforming PS name.
"""
import argparse
import filecmp
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time

EXIT_BAD_SOURCES = 2
DEFAULT_EPOCH = 1789603200  # 2026-09-17T00:00:00Z

HERE = os.path.dirname(os.path.abspath(__file__))
LIB = os.environ.get("FONTBUILDER_LIB", os.path.join(HERE, "lib"))
DATA = os.environ.get("FONTBUILDER_DATA", os.path.join(HERE, "data"))
TESTS = os.environ.get("FONTBUILDER_TESTS", os.path.join(HERE, "tests"))
PY = os.environ.get("FONTBUILDER_PYTHON", sys.executable)

WEIGHTS = [("Light", 300), ("Regular", 400), ("Medium", 500), ("SemiBold", 600), ("Bold", 700), ("ExtraBold", 800)]
FAMILY = "Anthropic Mono"
PS_FAMILY = "AnthropicMono"
EXPECT = {"nf": 12, "desktop": 5, "woff2": 7, "css": 1, "tarballs": 3}


class Build:
    def __init__(self, args, out):
        self.args = args
        self.src = os.path.abspath(args.src)
        self.out = os.path.abspath(out)
        self.epoch = int(os.environ.get("SOURCE_DATE_EPOCH") or DEFAULT_EPOCH)
        self.blocks = json.load(open(os.path.join(DATA, "merge-blocks.json"), encoding="utf-8"))
        self.stages = []
        self.t0 = time.time()

    # ------------------------------------------------------------- helpers
    def p(self, *parts):
        return os.path.join(self.out, *parts)

    def log(self, msg):
        print("fontbuilder: %6.1fs  %s" % (time.time() - self.t0, msg), flush=True)

    def run(self, stage, style, argv, logname=None, env=None):
        logname = logname or ("%s-%s.log" % (stage, style.replace(" ", "")))
        logpath = self.p("logs", logname)
        e = dict(os.environ)
        e["SOURCE_DATE_EPOCH"] = str(self.epoch)
        if env:
            e.update(env)
        t = time.time()
        with open(logpath, "w", encoding="utf-8") as fh:
            r = subprocess.run(argv, stdout=fh, stderr=subprocess.STDOUT, env=e, cwd=self.p("work"))
        dt = time.time() - t
        self.stages.append({"stage": stage, "style": style, "seconds": round(dt, 2), "rc": r.returncode, "log": logname})
        if r.returncode != 0:
            tail = open(logpath, encoding="utf-8", errors="replace").read().splitlines()[-25:]
            sys.exit("fontbuilder: stage %s (%s) failed rc=%d - see %s\n%s" % (stage, style, r.returncode, logpath, "\n".join(tail)))
        return dt

    def py(self, script, *args):
        return [PY, os.path.join(LIB, script), *args]

    def styles(self):
        want = None
        if self.args.weights:
            want = {int(w) for w in self.args.weights.split(",")}
        out = []
        for slope in ("Roman", "Italic"):
            for name, w in WEIGHTS:
                if want and w not in want:
                    continue
                if slope == "Roman":
                    style = name
                else:
                    style = "Italic" if name == "Regular" else name + " Italic"
                out.append((slope, name, w, style))
        return out

    # -------------------------------------------------------------- stages
    def s0(self):
        rc = subprocess.run([PY, os.path.join(LIB, "verify_sources.py"), self.src,
                             os.path.join(DATA, "sources.sha256")]).returncode
        if rc != 0:
            sys.exit(EXIT_BAD_SOURCES)
        self.log("S0 sources verified (14 pinned digests); align=%s braille_dy=%d SOURCE_DATE_EPOCH=%d"
                 % (self.args.align, self.args.braille_dy, self.epoch))

    def layout(self):
        for sub in ("work/inst", "work/norm", "work/merged", "work/lig", "work/aligned", "work/aligned-none",
                    "work/nf-raw", "work/desktop", "nf", "desktop", "webfonts/woff2", "webfonts/css",
                    "dist", "specimens", "align-report", "merge-report", "logs", "verify",
                    "stage/mono/truetype", "stage/ui/truetype", "stage/web/css", "stage/web/woff2"):
            os.makedirs(self.p(sub), exist_ok=True)
        for sub in ("nf", "desktop", "webfonts/woff2", "webfonts/css", "stage/mono/truetype",
                    "stage/ui/truetype", "stage/web/css", "stage/web/woff2"):
            for f in os.listdir(self.p(sub)):
                fp = self.p(sub, f)
                if os.path.isfile(fp):
                    os.chmod(fp, 0o644)
                    os.remove(fp)

    def mono(self):
        src_ttf = os.path.join(self.src, "fonts-ttf")
        fira = os.environ["FONTBUILDER_FIRA"]
        ligz = os.environ["FONTBUILDER_LIGATURIZER"]
        fira_map = self.blocks["fira_weight_map"]
        repaired = {}
        for slope in ("Roman", "Italic"):
            dst = self.p("work", "Mono%s-repaired.ttf" % slope)
            self.run("S1-repair", slope, self.py("repair_source.py", os.path.join(src_ttf, "AnthropicMono-%s-Web.ttf" % slope), dst))
            repaired[slope] = dst
        self.log("S1 repaired both variable Mono sources")
        for slope, wname, w, style in self.styles():
            nospace = style.replace(" ", "")
            t = time.time()
            inst = self.p("work", "inst", "%s.ttf" % nospace)
            norm = self.p("work", "norm", "%s.ttf" % nospace)
            merged = self.p("work", "merged", "%s.ttf" % nospace)
            lig = self.p("work", "lig", "%s-%s.ttf" % (PS_FAMILY, nospace))
            aligned = self.p("work", "aligned", "%s.ttf" % nospace)
            self.run("S2-instance", style, self.py("instance.py", repaired[slope], inst, "--wght", str(w), "--cell", "1200"))
            self.run("S3-normalize", style, self.py("normalize.py", "--in", inst, "--out", norm, "--family", FAMILY,
                                                    "--ps-family", PS_FAMILY, "--style", style, "--cell", "1200",
                                                    "--report", self.p("merge-report", "norm-%s.json" % nospace)))
            self.run("S4-merge", style, self.py("merge.py", "--in", norm, "--out", merged, "--style", nospace,
                                                "--braille-dy", str(self.args.braille_dy),
                                                "--report", self.p("merge-report", "merge-%s.json" % nospace)))
            donor = os.path.join(fira, fira_map[wname])
            if os.path.exists(lig):
                os.remove(lig)
            self.run("S5-ligaturize", style, ["bash", os.path.join(LIB, "ligaturize.sh"), merged, donor, self.p("work", "lig")])
            if not os.path.exists(lig):
                sys.exit("fontbuilder: S5 did not produce %s (ID6 rule broken?)" % lig)
            self.run("S8-canonicalize-lig", style, self.py("canonicalize.py", lig))
            align_args = ["--ligatures", os.path.join(ligz, "ligatures.py"), "--donor", donor]
            slant = ["--slant", "10"] if slope == "Italic" else []
            self.run("S6-align", style, self.py("ligature_align.py", "--in", lig, "--out", aligned, "--mode", self.args.align,
                                                *align_args, *slant, "--report", self.p("align-report", "%s.json" % nospace)))
            if style == "Regular":
                other = "none" if self.args.align == "anchor" else "anchor"
                self.run("S6-align-compare", style, self.py("ligature_align.py", "--in", lig,
                                                            "--out", self.p("work", "aligned-none", "Regular.ttf"),
                                                            "--mode", other, *align_args,
                                                            "--report", self.p("align-report", "Regular-%s.json" % other)))
            if self.args.skip_nerd:
                self.log("%-16s through S6 in %.1fs (--skip-nerd)" % (style, time.time() - t))
                continue
            rawdir = self.p("work", "nf-raw", nospace)
            shutil.rmtree(rawdir, ignore_errors=True)
            os.makedirs(rawdir)
            self.run("S7-nerdpatch", style, ["bash", os.path.join(LIB, "nerdpatch.sh"), aligned, rawdir,
                                             self.p("logs", "S7-patcher-%s.log" % nospace)])
            produced = [f for f in os.listdir(rawdir) if f.endswith(".ttf")]
            if len(produced) != 1:
                sys.exit("fontbuilder: S7 produced %r in %s, expected exactly one .ttf" % (produced, rawdir))
            final = self.p("nf", produced[0])
            self.run("S7b-regraft", style, self.py("regraft_pua.py", "--aligned", aligned,
                                                   "--patched", os.path.join(rawdir, produced[0]), "--out", final))
            self.run("S8-canonicalize", style, self.py("canonicalize.py", final))
            self.log("%-16s -> %s in %.1fs" % (style, produced[0], time.time() - t))

    def desktop(self):
        src_ttf = os.path.join(self.src, "fonts-ttf")
        for fam, slope, extra in (("Sans", "Roman", []), ("Sans", "Italic", ["--italic"]),
                                  ("Serif", "Roman", ["--serif-default-repair"]),
                                  ("Serif", "Italic", ["--italic", "--serif-default-repair"])):
            dst = self.p("desktop", "Anthropic%s-%s.ttf" % (fam, slope))
            self.run("S9-normalize-vf", fam + slope, self.py("normalize_vf.py", "--in", os.path.join(src_ttf, "Anthropic%s-%s-Web.ttf" % (fam, slope)),
                                                              "--out", dst, "--family", "Anthropic %s" % fam, *extra,
                                                              "--report", self.p("merge-report", "vf-%s-%s.json" % (fam, slope))))
            self.run("S8-canonicalize", fam + slope, self.py("canonicalize.py", dst))
        for slope, extra in (("Roman", []), ("Italic", ["--italic"])):
            dst = self.p("work", "desktop", "AnthropicMono-%s.ttf" % slope)
            self.run("S9-normalize-vf", "Mono" + slope, self.py("normalize_vf.py", "--in", os.path.join(src_ttf, "AnthropicMono-%s-Web.ttf" % slope),
                                                                 "--out", dst, "--family", FAMILY, *extra,
                                                                 "--report", self.p("merge-report", "vf-Mono-%s.json" % slope)))
            self.run("S8-canonicalize", "Mono" + slope, self.py("canonicalize.py", dst))
        icons = os.path.join(src_ttf, "Anthropicons-Variable.ttf")
        pinned = self.p("desktop", "Anthropicons-Regular.ttf")
        varb = self.p("work", "desktop", "Anthropicons-Variable.ttf")
        self.run("S10-icons", "pinned", self.py("icons.py", "--in", icons, "--out", pinned, "--pin",
                                                "--report", self.p("merge-report", "icons-pinned.json")))
        self.run("S10-icons", "variable", self.py("icons.py", "--in", icons, "--out", varb,
                                                  "--report", self.p("merge-report", "icons-variable.json")))
        self.run("S8-canonicalize", "icons", self.py("canonicalize.py", pinned, varb))
        self.log("S9/S10 desktop faces + Anthropicons done")

    def webfonts(self):
        pairs = []
        for fam in ("Sans", "Serif"):
            for slope in ("Roman", "Italic"):
                pairs.append("%s:Anthropic%s-%s.woff2" % (self.p("desktop", "Anthropic%s-%s.ttf" % (fam, slope)), fam, slope))
        for slope in ("Roman", "Italic"):
            pairs.append("%s:AnthropicMono-%s.woff2" % (self.p("work", "desktop", "AnthropicMono-%s.ttf" % slope), slope))
        pairs.append("%s:Anthropicons-Variable.woff2" % self.p("work", "desktop", "Anthropicons-Variable.ttf"))
        self.run("S11-webfonts", "all", self.py("webfonts.py", "--outdir", self.p("webfonts", "woff2"),
                                                "--report", self.p("merge-report", "woff2.json"), *pairs))
        shutil.copy(os.path.join(DATA, "anthropic-fonts.css"), self.p("webfonts", "css", "anthropic-fonts.css"))
        self.log("S11 webfonts: 7 woff2 + css")

    def package(self):
        for f in sorted(os.listdir(self.p("nf"))):
            shutil.copy(self.p("nf", f), self.p("stage", "mono", "truetype", f))
        for f in sorted(os.listdir(self.p("desktop"))):
            shutil.copy(self.p("desktop", f), self.p("stage", "ui", "truetype", f))
        for sub in ("css", "woff2"):
            for f in sorted(os.listdir(self.p("webfonts", sub))):
                shutil.copy(self.p("webfonts", sub, f), self.p("stage", "web", sub, f))
        faces = [self.p("nf", f) for f in sorted(os.listdir(self.p("nf")))]
        sys.path.insert(0, LIB)
        import manifest  # noqa: E402
        manifest.write(self.out, self.src, self.epoch, self.args.align, self.args.braille_dy, self.stages,
                       os.path.join(DATA, "sources.sha256"), faces)
        self.run("S12-package", "all", self.py("package.py", self.p("stage"), self.p("dist"), str(self.epoch),
                                               "--origins", self.p("origins.txt")))
        manifest.write(self.out, self.src, self.epoch, self.args.align, self.args.braille_dy, self.stages,
                       os.path.join(DATA, "sources.sha256"), faces)
        self.log("S12 packaged: %s" % ", ".join(sorted(f for f in os.listdir(self.p("dist")))))

    def specimens(self):
        if self.args.skip_specimens:
            return
        r = subprocess.run([PY, os.path.join(LIB, "specimen.py"), self.out],
                           stdout=open(self.p("logs", "specimens.log"), "w"), stderr=subprocess.STDOUT)
        if r.returncode != 0:
            sys.exit("fontbuilder: specimen rendering failed - see logs/specimens.log (use --skip-specimens to bypass)")
        pngs = sorted(f for f in os.listdir(self.p("specimens")) if f.endswith(".png"))
        self.log("specimens: %s" % ", ".join(pngs))

    def assert_counts(self):
        counts = {
            "nf": len([f for f in os.listdir(self.p("nf")) if f.endswith(".ttf")]),
            "desktop": len([f for f in os.listdir(self.p("desktop")) if f.endswith(".ttf")]),
            "woff2": len([f for f in os.listdir(self.p("webfonts", "woff2")) if f.endswith(".woff2")]),
            "css": len([f for f in os.listdir(self.p("webfonts", "css")) if f.endswith(".css")]),
            "tarballs": len([f for f in os.listdir(self.p("dist")) if f.endswith(".tar.zst")]),
        }
        bad = {k: (counts[k], EXPECT[k]) for k in EXPECT if counts[k] != EXPECT[k]}
        if bad:
            sys.exit("fontbuilder: artifact counts wrong (got, expected): %s" % bad)
        self.log("artifact counts ok: %s" % counts)

    def full(self):
        self.s0()
        self.layout()
        only = self.args.only
        if only in ("mono", "all"):
            self.mono()
        if only in ("desktop", "webfonts", "all"):
            self.desktop()
        if only in ("webfonts", "all"):
            self.webfonts()
        if only == "all" and not self.args.skip_nerd and not self.args.weights:
            self.package()
            self.assert_counts()
            self.specimens()
        else:
            self.log("partial build (--only/--weights/--skip-nerd): no packaging, no count assertion")
        with open(self.p("build.json"), "w", encoding="utf-8") as fh:
            json.dump({"stages": self.stages, "epoch": self.epoch, "args": vars(self.args)}, fh, indent=1)
        self.log("done")


# ------------------------------------------------------------------ verbs
def cmd_build(args):
    if args.verify_repro:
        return verify_repro(args)
    Build(args, args.out).full()
    return 0


def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def verify_repro(args):
    """Build twice into two trees and diff every artifact byte for byte."""
    a, b = args.out + ".repro-a", args.out + ".repro-b"
    for t in (a, b):
        shutil.rmtree(t, ignore_errors=True)
        args2 = argparse.Namespace(**vars(args))
        args2.skip_specimens = True
        Build(args2, t).full()
    subs = ["nf", "desktop", "webfonts/woff2", "webfonts/css", "dist", "work/lig", "work/aligned"]
    rows, bad = [], []
    for sub in subs:
        da, db = os.path.join(a, sub), os.path.join(b, sub)
        names = sorted(set(os.listdir(da)) | set(os.listdir(db)))
        for n in names:
            pa, pb = os.path.join(da, n), os.path.join(db, n)
            if not (os.path.isfile(pa) and os.path.isfile(pb)):
                bad.append((sub, n, "missing on one side"))
                continue
            same = filecmp.cmp(pa, pb, shallow=False)
            rows.append((sub, n, sha(pa)[:16], "identical" if same else "DIFFERENT"))
            if not same:
                bad.append((sub, n, sha(pa), sha(pb)))
    print("verify-repro: %d artifacts compared" % len(rows))
    for sub, n, h, verdict in rows:
        print("  %-16s %-44s %s %s" % (sub, n, h, verdict))
    if bad:
        print("verify-repro: FAILED, %d artifact(s) differ:" % len(bad))
        for row in bad:
            print("  ", *row)
        return 1
    if not rows:
        print("verify-repro: FAILED, nothing was built")
        return 1
    print("verify-repro: OK, both trees byte-identical")
    return 0


def cmd_verify(out, src):
    out = os.path.abspath(out)
    rc = 0
    for script, extra in (("accept.py", ["--src", src] if src else []),
                          ("resolve.py", []),
                          ("shape.py", []),
                          ("a12.py", None)):
        path = os.path.join(TESTS, script)
        if not os.path.exists(path):
            print("fontbuilder: %s missing, skipped" % script)
            continue
        if extra is None:
            if not src:
                print("fontbuilder: a12.py needs --src <capture-dir>, skipped")
                continue
            argv = [PY, path, src, out]
        else:
            argv = [PY, path, out, *extra]
        print("fontbuilder: running %s" % " ".join(argv[1:]))
        r = subprocess.run(argv).returncode
        print("fontbuilder: %s -> rc=%d" % (script, r))
        rc = rc or r
    return rc


def cmd_package(out):
    out = os.path.abspath(out)
    epoch = int(os.environ.get("SOURCE_DATE_EPOCH") or DEFAULT_EPOCH)
    argv = [PY, os.path.join(LIB, "package.py"), os.path.join(out, "stage"), os.path.join(out, "dist"), str(epoch)]
    if os.path.exists(os.path.join(out, "origins.txt")):
        argv += ["--origins", os.path.join(out, "origins.txt")]
    return subprocess.run(argv).returncode


def cmd_print_nix_hashes(out):
    sums = os.path.join(out, "dist", "SHA256SUMS")
    if not os.path.isfile(sums):
        print("fontbuilder: no %s - build first" % sums, file=sys.stderr)
        return 2
    for line in open(sums, encoding="utf-8"):
        h, _, name = line.strip().partition("  ")
        print('# %s\n    sha256 = "%s";' % (name, h))
    return 0


def cmd_rehash_sources(src):
    dest = os.path.join(DATA, "sources.sha256")
    names = [ln.strip().partition("  ")[2] for ln in open(dest, encoding="utf-8") if ln.strip()]
    for rel in names:
        p = subprocess.run(["sha256sum", rel], cwd=src, capture_output=True, text=True, check=True)
        sys.stdout.write(p.stdout)
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(
        prog="fontbuilder",
        description="Press the Anthropic font suite: 12 Nerd-patched terminal statics, the variable "
                    "Sans/Serif + Anthropicons desktop faces, the webfonts, and the three NAS tarballs. "
                    "Ships the recipe and no font bytes.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""\
examples:
  fontbuilder ~/colors/waves/capture ~/build/anthropic-fonts-2026-09-17
  fontbuilder <src> <out> --only mono --weights 400,600 --skip-nerd   # fast iteration
  fontbuilder <src> <out> --align none                                # default: anchor
  fontbuilder <src> <out> --braille-dy 0                              # default: 55 (centred)
  fontbuilder <src> <out> --verify-repro                              # build twice, diff
  fontbuilder --verify <out> --src <src>
  fontbuilder --package <out>
  fontbuilder --print-nix-hashes <out>
  fontbuilder --rehash-sources <src>

exit codes:
  0  ok
  1  a stage, a count assertion or an acceptance test failed
  2  the capture tree does not match data/sources.sha256 (the inertness gate)
""")
    ap.add_argument("src", nargs="?", help="the read-only capture directory")
    ap.add_argument("out", nargs="?", help="the output directory (created)")
    ap.add_argument("--only", choices=["mono", "desktop", "webfonts", "all"], default="all")
    ap.add_argument("--weights", help="comma-separated wght values, e.g. 400,600 (mono only; disables packaging)")
    ap.add_argument("--align", choices=["anchor", "none"], default="anchor")
    ap.add_argument("--braille-dy", type=int, default=55)
    ap.add_argument("--skip-nerd", action="store_true", help="stop the mono chain before S7")
    ap.add_argument("--skip-specimens", action="store_true")
    ap.add_argument("--verify-repro", action="store_true", help="build twice into <out>.repro-{a,b} and diff")
    ap.add_argument("--verify", metavar="OUT")
    ap.add_argument("--src", metavar="SRC", help="capture dir for --verify's negative controls / a12")
    ap.add_argument("--package", metavar="OUT")
    ap.add_argument("--print-nix-hashes", metavar="OUT")
    ap.add_argument("--rehash-sources", metavar="SRC")
    args = ap.parse_args(argv)
    if args.verify:
        return cmd_verify(args.verify, args.src)
    if args.package:
        return cmd_package(args.package)
    if args.print_nix_hashes:
        return cmd_print_nix_hashes(args.print_nix_hashes)
    if args.rehash_sources:
        return cmd_rehash_sources(args.rehash_sources)
    if not args.src or not args.out:
        ap.error("both <capture-dir> and <out-dir> are required for a build")
    return cmd_build(args)


if __name__ == "__main__":
    sys.exit(main())
