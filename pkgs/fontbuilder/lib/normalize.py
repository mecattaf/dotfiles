#!/usr/bin/env python3
"""S3 - normalize the name table and the style bits.

fidelity/normalize.py (ID1/2/4/6/16/17 rules, fsSelection/macStyle) with the
ID18/20/21/25 deletion grafted from operations/normalize.py, plus
post.italicAngle = -10 on italics (spec S3).
"""
import sys, json, argparse
from fontTools.ttLib import TTFont

WIN, MAC = (3, 1, 0x409), (1, 0, 0)
RIBBI = {'Regular', 'Bold', 'Italic', 'Bold Italic'}


def fix_names(f, family, style, ps_family):
    n = f['name']
    ribbi = style in RIBBI
    weight_token = style.replace(' Italic', '').replace('Italic', '').strip()
    fam = family if ribbi else '%s %s' % (family, weight_token)
    if style in RIBBI:
        sub = style
    else:
        sub = 'Italic' if style.endswith('Italic') else 'Regular'
    # patcher parses ID4: a non-RIBBI UPRIGHT weight must NOT carry 'Regular'
    full = fam if (not ribbi and sub == 'Regular') else '%s %s' % (fam, sub)
    ps = '%s-%s' % (ps_family, style.replace(' ', ''))
    recs = {1: fam, 2: sub, 4: full, 6: ps, 16: family, 17: style}
    if ribbi:
        recs.pop(16); recs.pop(17)
        n.removeNames(nameID=16); n.removeNames(nameID=17)
    for nid, val in recs.items():
        n.setName(val, nid, *WIN); n.setName(val, nid, *MAC)
    # ID3 unique id: drop Web/Variable
    for rec in list(n.names):
        if rec.nameID == 3:
            try: s = rec.toUnicode()
            except Exception: continue
            s2 = s.replace('Web', '').replace('Variable', '')
            while '  ' in s2: s2 = s2.replace('  ', ' ')
            n.setName(s2.strip(), 3, rec.platformID, rec.platEncID, rec.langID)
    for nid in (18, 20, 21, 25):
        n.removeNames(nameID=nid)
    # belt and braces: no record anywhere may still say Web/Variable
    for rec in list(n.names):
        try: s = rec.toUnicode()
        except Exception: continue
        if 'Web' in s or 'Variable' in s:
            s2 = s.replace('Web', '').replace('Variable', '')
            while '  ' in s2: s2 = s2.replace('  ', ' ')
            n.setName(s2.strip(), rec.nameID, rec.platformID, rec.platEncID, rec.langID)
    return fam, sub, ps


def run(path, out, family, style, ps_family, cell=None, report=None):
    f = TTFont(path, recalcTimestamp=False)
    fam, sub, ps = fix_names(f, family, style, ps_family)
    os2, head, post = f['OS/2'], f['head'], f['post']
    italic = 'Italic' in style
    bold = os2.usWeightClass >= 700
    fs = os2.fsSelection
    fs &= ~0b1100001                      # clear ITALIC(0) BOLD(5) REGULAR(6)
    if italic: fs |= 1
    if bold:   fs |= 1 << 5
    if not italic and not bold: fs |= 1 << 6
    fs |= 1 << 7                          # USE_TYPO_METRICS
    os2.fsSelection = fs
    ms = head.macStyle & ~0b11
    if bold: ms |= 1
    if italic: ms |= 2
    head.macStyle = ms
    post.italicAngle = -10.0 if italic else 0.0
    fixed = []
    if cell:
        for g, (w, l) in list(f['hmtx'].metrics.items()):
            if w != cell:
                f['hmtx'].metrics[g] = (cell, l); fixed.append(g)
    f.save(out)
    nm = f['name']
    print('%-30s n1=%-26r n2=%-14r n4=%-32r n6=%-30r n16=%r n17=%r wc=%3d fsSel=%3d(%s) macStyle=%d italicAngle=%.1f advrepair=%d' % (
        out, nm.getDebugName(1), nm.getDebugName(2), nm.getDebugName(4), nm.getDebugName(6),
        nm.getDebugName(16), nm.getDebugName(17), os2.usWeightClass, fs, bin(fs), head.macStyle,
        post.italicAngle, len(fixed)))
    if report:
        json.dump(dict(family=fam, subfamily=sub, ps=ps, fsSelection=fs, macStyle=head.macStyle,
                       italicAngle=post.italicAngle, repaired=fixed), open(report, 'w'), indent=1)
    return fixed


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('--in', dest='inp', required=True); ap.add_argument('--out', required=True)
    ap.add_argument('--family', default='Anthropic Mono')
    ap.add_argument('--style', required=True)
    ap.add_argument('--ps-family', default='AnthropicMono')
    ap.add_argument('--cell', type=int, default=None)
    ap.add_argument('--report', default=None)
    a = ap.parse_args()
    run(a.inp, a.out, a.family, a.style, a.ps_family, a.cell, a.report)
