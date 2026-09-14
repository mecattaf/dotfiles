#!/usr/bin/env python3
"""Disposable journal OCR experiment: reversible, deterministic image preparation."""
import hashlib
import json
import math
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
GROUPS = [[1], [2], [3], [4, 5], [6], [7, 8], [9, 10], [11, 12], [13], [14], [15, 16], [17]]

def main():
    rows = json.loads((ROOT / 'photo-metadata.json').read_text())
    out = ROOT / 'inputs'
    out.mkdir(exist_ok=True)
    for row in rows:
        n = row['capture_order']
        src = ROOT / 'originals' / row['file']
        assert hashlib.sha256(src.read_bytes()).hexdigest() == row['sha256']
        im = Image.open(src).convert('RGB')
        rotation = 0 if n == 6 else 90
        if rotation:
            im = im.transpose(Image.Transpose.ROTATE_90)
        w, h = im.size
        beta = math.sqrt(w * h / 3686400)
        # Matches the inspected Halogen 0.7.0 frontend's max-area branch.
        size = (math.floor(w / beta / 32) * 32, math.floor(h / beta / 32) * 32)
        im = im.resize(size, Image.Resampling.BICUBIC)
        target = out / f'capture-{n:02}.png'
        im.save(target)
        row.update(rotation_ccw=rotation, input=str(target.relative_to(ROOT)),
                   input_sha256=hashlib.sha256(target.read_bytes()).hexdigest(),
                   input_width=size[0], input_height=size[1], image_tokens=size[0]*size[1]//1024,
                   page=next(i for i, group in enumerate(GROUPS, 1) if n in group))
        print(n, size, row['page'])
    (ROOT / 'input-manifest.json').write_text(json.dumps({'status':'Page grouping pending final visual review', 'preprocessing':'Original decoded RGB, visually chosen quarter-turn, exact Halogen BICUBIC max-area resize; no sharpening, text cleanup or generative processing', 'groups':GROUPS, 'captures':rows}, indent=2)+'\n')

if __name__ == '__main__':
    main()
