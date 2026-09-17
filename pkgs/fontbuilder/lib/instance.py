#!/usr/bin/env python3
"""S2 - instance the repaired variable Italic to one static per weight."""
import sys, argparse
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

ap = argparse.ArgumentParser()
ap.add_argument('inp'); ap.add_argument('out')
ap.add_argument('--wght', type=float, required=True)
ap.add_argument('--cell', type=int, default=1200)
a = ap.parse_args()
f = TTFont(a.inp, recalcTimestamp=False)
g = instancer.instantiateVariableFont(f, {'wght': a.wght}, inplace=True, updateFontNames=True)
bad = [n for n, (w, _) in g['hmtx'].metrics.items() if w != a.cell]
for n in bad:
    w, l = g['hmtx'].metrics[n]; g['hmtx'].metrics[n] = (a.cell, l)
g.save(a.out)
nm = g['name']
print('%-32s wght=%-4g belt-and-braces advances repaired=%d  n1=%r n2=%r n4=%r n6=%r wc=%d fsSel=%s macStyle=%d italicAngle=%s' % (
    a.out, a.wght, len(bad), nm.getDebugName(1), nm.getDebugName(2), nm.getDebugName(4),
    nm.getDebugName(6), g['OS/2'].usWeightClass, bin(g['OS/2'].fsSelection), g['head'].macStyle, g['post'].italicAngle))
