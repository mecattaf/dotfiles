#!/usr/bin/env python3
"""fontbuilder stage S8 - make a FontForge/patcher output a pure function of its tables.

MEASURED (scout2 + scout3 C10, 2026-09-17): nerd-font-patcher's only
non-deterministic table is `head` (modified + the derived checkSumAdjustment).
Ligaturizer's FontForge generate() has TWO: `head` AND a 28-byte `FFTM` whose
sourceModified is the wall clock - and because checkSumAdjustment is computed
over ALL tables, pinning head's timestamps alone leaves the file non-identical.
So: pin head.created/modified to SOURCE_DATE_EPOCH and DELETE FFTM. This runs
after S5 (work/lig) as well as after S7b (nf) and on every desktop face.

The `del FFTM` line is load-bearing, not dead code.
"""
import os
import sys

from fontTools.ttLib import TTFont

MAC_EPOCH_DELTA = 2082844800  # 1904-01-01 -> 1970-01-01
FONTFORGE_PRIVATE = ("FFTM",)


def canonicalize(path, epoch):
    mac = int(epoch) + MAC_EPOCH_DELTA
    f = TTFont(path, recalcTimestamp=False, recalcBBoxes=False)
    f["head"].created = mac
    f["head"].modified = mac
    for tag in FONTFORGE_PRIVATE:
        if tag in f:
            del f[tag]
    f.save(path + ".tmp")
    os.replace(path + ".tmp", path)
    g = TTFont(path, lazy=True)
    assert not any(t in g.reader.keys() for t in FONTFORGE_PRIVATE), "%s still carries a FontForge stamp" % path
    assert g["head"].modified == mac, "%s head.modified not pinned" % path
    g.close()


if __name__ == "__main__":
    epoch = int(os.environ.get("SOURCE_DATE_EPOCH", "0"))
    for p in sys.argv[1:]:
        canonicalize(p, epoch)
