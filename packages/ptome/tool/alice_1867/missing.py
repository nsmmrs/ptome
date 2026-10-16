"""Lines the OCR missed: bands of ink, a text line high, in the gaps
between a page's OCR lines (and below its last), on its text column."""
import json, os, sys
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import BOOKS, ROOT

book = sys.argv[1]
cfg = BOOKS[book]
pages = json.load(open(f'{ROOT}/{cfg["id"]}.ocr.json'))
for leaf in range(cfg['first'], cfg['last'] + 1):
    p = pages[leaf]
    H = p['b'][3]
    lines = sorted(p['lines'], key=lambda l: l['b'][1])
    if not lines:
        continue
    img = np.asarray(Image.open(
        f'{ROOT}/{cfg["id"]}/{cfg["id"]}_jp2/{cfg["id"]}_{leaf:04d}.jp2').convert('L')).astype(float)
    x0 = min(l['b'][0] for l in lines)
    x1 = max(l['b'][2] for l in lines)
    col = img[:, x0:x1]
    thr = np.median(col) - 45
    ink = (col < thr).mean(1)
    covered = np.zeros(H, bool)
    for l in lines:
        covered[max(0, l['b'][1] - 10):l['b'][3] + 10] = True
    limit = int(0.94 * H)
    pitch = 151 * H / 4060
    gaps = [(a['b'][3], b['b'][1]) for a, b in zip(lines, lines[1:])
            if b['b'][1] - a['b'][3] > 1.4 * pitch]
    gaps.append((lines[-1]['b'][3], limit))
    rows = set()
    for a, b in gaps:
        rows.update(range(a, b))
    y = lines[0]['b'][3]
    band = None
    found = []
    for yy in range(y, limit):
        if yy not in rows:
            if band is not None and 45 <= yy - band <= 140:
                found.append((band, yy))
            band = None
            continue
        on = ink[yy] > 0.015 and not covered[yy]
        if on and band is None:
            band = yy
        elif not on and band is not None:
            if 45 <= yy - band <= 140:
                found.append((band, yy))
            band = None
    for a, b in found:
        print(f'{leaf}: ink band y {a}-{b} (h {b - a}) not in the OCR')
