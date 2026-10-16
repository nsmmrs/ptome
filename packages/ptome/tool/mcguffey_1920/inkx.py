"""The ink runs along a line of a leaf: where words start and end (pt,
from the text's left edge) in the band of x-height above BASELINE.

    python3 -I inkx.py WORK LEAF LEFT-PT BASELINE-PT [BASELINE-PT...]
"""
import glob, sys
import numpy as np
from PIL import Image

work, leaf, left = sys.argv[1], int(sys.argv[2]), float(sys.argv[3])
d = glob.glob(f'{work}/*_jp2')[0]
name = d.split('/')[-1][:-4]
PT = 72 / 360
a = np.asarray(Image.open(f'{d}/{name}_{leaf:04d}.jp2').convert('L')) < 110
for b in map(float, sys.argv[4:]):
    y = int(b / PT)
    band = a[y - 20:y - 4]
    cols = band.sum(0) > 0
    runs = []
    x = 0
    W = len(cols)
    while x < W:
        if cols[x]:
            s = x
            gap = 0
            while x < W and gap < 18:
                gap = 0 if cols[x] else gap + 1
                x += 1
            runs.append((s, x - gap))
        x += 1
    print(f'{b:6.1f}: ' + '  '.join(f'{s * PT - left:.1f}-{e * PT - left:.1f}' for s, e in runs))
