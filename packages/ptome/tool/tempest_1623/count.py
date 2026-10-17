"""Each column's printed lines on the scan, counted from the ink (the
column cut by columns.py: its rows' ink right of the speakers' indent,
peaks at least two-thirds of a line apart), against the spec's
(folio.spec, gen.py's fit.json): the columns whose counts differ.

    python3 -I count.py
"""
import json, os
import numpy as np
from PIL import Image

WORK = os.environ.get('TEMPEST_WORK', os.path.expanduser('~/.cache/asciidart-work/print-match/tempest'))
fit = json.load(open(os.path.join(WORK, 'fit.json')))
spec = {}
for f in fit:
    if isinstance(f['line'], int):
        spec[(f['page'], f['col'])] = max(spec.get((f['page'], f['col']), 0), f['line'])


def lines(leaf, col):
    a = np.asarray(Image.open(os.path.join(WORK, 'cols', f'{leaf:04d}-{col}.png')).convert('L')) < 120
    prof = a[:, 20:-20].sum(axis=1).astype(float)
    sm = np.convolve(prof, np.ones(9) / 9, mode='same')
    peaks = [y for y in range(1, len(sm) - 1) if sm[y] >= sm[y - 1] and sm[y] > sm[y + 1] and sm[y] > 0.12 * sm.max()]
    chosen = []
    for y in sorted(peaks, key=lambda y: -sm[y]):
        if all(abs(y - c) >= 36 for c in chosen):
            chosen.append(y)
    return sorted(chosen)


for page in range(1, 20):
    for col in (1, 2):
        n = len(lines(24 + page, col))
        s = spec.get((page, col), 0)
        flag = '' if abs(n - s - 2) <= 1 else '  <--'
        print(f'{page}/{col}: scan {n} (with head and foot), spec {s}{flag}')
