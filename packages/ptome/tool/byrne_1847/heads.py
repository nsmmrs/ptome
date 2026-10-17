"""Each leaf's running head and folio from the ink of the head's band
(the OCR's word boxes run on into the space after them): the head's
extent, centre and baseline, the folio's box.

    python3 -I heads.py -> heads.json
"""
import json, os, re, sys
import numpy as np
from PIL import Image
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from seg import SCAN, OCR, classify, LEAVES


def runs(cols, gap):
    xs = np.nonzero(cols)[0]
    out = []
    for x in xs:
        if out and x - out[-1][1] <= gap:
            out[-1][1] = x + 1
        else:
            out.append([x, x + 1])
    return out


def main():
    out = {}
    for leaf in LEAVES:
        a = np.asarray(Image.open(SCAN % leaf).convert('RGB'))
        k, paper = classify(a)
        H = a.shape[0]
        lines = [l for l in OCR[leaf]['lines'] if l['b'][3] < 0.1 * H]
        if not lines:
            continue
        y0 = min(l['b'][1] for l in lines) - 6
        y1 = max(l['b'][3] for l in lines) + 10
        lum = a.astype(np.int32).sum(2)
        dark = lum < paper.sum() - 150
        band = dark[y0:y1, 60:-60]
        groups = [g for g in runs(band.sum(0) > 1, 70) if g[1] - g[0] > 15]
        head = max(groups, key=lambda g: g[1] - g[0])
        folio = [g for g in groups if g is not head and abs((g[0] + g[1]) / 2 - (head[0] + head[1]) / 2) < 800]
        x0, x1 = head[0] + 60, head[1] + 60
        rows = dark[y0:y1, x0:x1].sum(1)
        # (The baseline: the last row of the capitals' ink, before the
        # descenders' few.)
        full = np.nonzero(rows > 0.25 * rows.max())[0]
        base = y0 + int(full[-1]) + 1
        rec = dict(x0=int(x0), x1=int(x1), cx=float(x0 + x1) / 2, base=int(base))
        if folio:
            f = folio[0]
            rec['folio'] = [int(f[0] + 60), int(f[1] + 60)]
        out[str(leaf)] = rec
        print(leaf, rec, flush=True)
    json.dump(out, open(f'{HERE}/heads.json', 'w'))


if __name__ == '__main__':
    main()
