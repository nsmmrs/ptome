"""Each page's rows on the PDF against the scan's: their baselines, and
the right ends of the figures in each column (the scan's set on the
PDF's page by its frame, frame.py's: its thick rule on the PDF's, its
rules across on the PDF's, scaled between them; across, registered by
its figures' right ends).

    python3 -I compare.py [--rows] [PAGE...]
"""
import html, json, os, re, subprocess, sys
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
import sys as _sys
_sys.path.insert(0, HERE)
from common import EDGES, FOOT_RULE, HEAD_RULE, PAGE, THICK, WORK
sys.path.insert(0, HERE)
PDF = os.path.join(WORK, 'build', 'babbage.pdf')
DESCENT = 0.238  # Old Standard TT's descent in Poppler's box
ARGS = [a for a in sys.argv[1:] if not a.startswith('--')]
PAGES = [int(a) for a in ARGS] or list(range(6, 26))
SHOW = '--rows' in sys.argv


def pdf_words(page):
    out = subprocess.run(['pdftotext', '-bbox', '-f', str(page - 5), '-l', str(page - 5), PDF, '-'],
                         capture_output=True, text=True, check=True).stdout
    words = []
    for m in re.finditer(r'<word xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" yMax="([\d.]+)">(.*?)</word>', out):
        x0, y0, x1, y1 = map(float, m.groups()[:4])
        words.append((x0, y1 - (y1 - y0) * DESCENT, x1, html.unescape(m.group(5))))
    return words


def scan_rows(page):
    """The scan's rows' baselines and each column's figures' right ends,
    on the PDF's page."""
    n = page + 24
    f = json.load(open(os.path.join(WORK, 'frame.json')))[str(n)]
    a = np.asarray(Image.open(os.path.join(WORK, 'upright', f'n{n}.png'))) < 128
    side = 'verso' if page % 2 == 0 else 'recto'
    k = (f['foot'] - f['head']) / (FOOT_RULE - HEAD_RULE)  # pixels a point down
    kx = k  # across: as down (the rule after the tenth column, too heavy and worn to scale by)
    to_y = lambda y: HEAD_RULE + (y - f['head']) / k
    to_x = lambda x: THICK[side] + (x - f['thick']) / kx
    x0, x1 = int(f['thick'] + 2 * k), int(f['thick'] + EDGES[13] * k)
    p = a[int(f['head'] + 3 * k):int(f['foot'] - 2 * k), x0:x1].mean(axis=1)
    top = int(f['head'] + 3 * k)
    bases, run = [], 0.0
    for y in range(1, len(p)):
        run = max(run, p[y - 1])
        if run > 0.08 and p[y] < run / 3 <= p[y - 1]:
            if not bases or y + top - bases[-1] > 4 * k:
                bases.append(y + top)
            run = 0.0
        elif p[y] < 0.01:
            run = 0.0
    # (The fifty rows: the printing's grid, 9.9 points a row and 4.9 more
    # between fives, set where the most of the ink's falls are nearest
    # it; each row the fall nearest its place, a speck's left out.)
    grid = np.array([i * 9.9 + i // 5 * 4.9 for i in range(50)]) * k
    bs = np.array(bases, dtype=float)
    best = min(bs, key=lambda b0: sum(np.min(np.abs(bs[:, None] - (b0 + grid)), axis=0) ** 0.5))
    # (A row whose fall the foot's rule runs into, slanting: its place on
    # the grid.)
    bases = [float(bs[np.argmin(np.abs(bs - (best + g)))]) for g in grid]
    bases = [b if abs(b - (best + g)) < 3 * k else best + g for b, g in zip(bases, grid)]
    rows = []
    for b in bases:
        band = a[int(b - 7 * k):int(b + 1), :]
        rights = []
        for c in range(2, 13):
            lo, hi = int(f['thick'] + (EDGES[c] + 1.2) * kx), int(f['thick'] + (EDGES[c + 1] - 1.2) * kx)
            cols = np.where(band[:, lo:hi].sum(axis=0) > 2)[0]
            rights.append(to_x(lo + cols[-1]) if len(cols) else None)
        rows.append({'base': to_y(b), 'rights': rights})
    return rows


def pdf_rows(page):
    side = 'verso' if page % 2 == 0 else 'recto'
    t = THICK[side]
    words = pdf_words(page)
    num = sorted((w for w in words if t + EDGES[2] < w[0] < t + EDGES[3] and HEAD_RULE < w[1] < FOOT_RULE),
                 key=lambda w: w[1])
    rows = []
    for w in num:
        rights = []
        for c in range(2, 13):
            ws = [v for v in words if abs(v[1] - w[1]) < 2 and t + EDGES[c] < (v[0] + v[2]) / 2 < t + EDGES[c + 1]]
            rights.append(max(v[2] for v in ws) if ws else None)
        rows.append({'base': w[1], 'rights': rights, 'text': w[3]})
    return rows


def main():
    for page in PAGES:
        s, p = scan_rows(page), pdf_rows(page)
        if len(s) != len(p):
            print(f'{page}: {len(p)} rows on the PDF, {len(s)} on the scan')
        n = min(len(s), len(p))
        # (Across, the scan registered on the PDF by the least squares
        # line through its figures' right ends against the PDF's: each
        # scan stretched across a little differently; down, its frame.)
        pairs = [(s[i]['rights'][c], p[i]['rights'][c]) for i in range(n) for c in range(11)
                 if p[i]['rights'][c] is not None and s[i]['rights'][c] is not None]
        a, b = np.polyfit([x for x, _ in pairs], [y for _, y in pairs], 1)
        for row in s:
            row['rights'] = [a * x + b if x is not None else None for x in row['rights']]
        db = [p[i]['base'] - s[i]['base'] for i in range(n)]
        dr = [p[i]['rights'][c] - s[i]['rights'][c] for i in range(n) for c in range(11)
              if p[i]['rights'][c] is not None and s[i]['rights'][c] is not None]
        print(f'{page}: base off {max(map(abs, db)):.1f} (median {np.median(db):+.2f}); '
              f'right ends off >0.5 pt {sum(abs(x) > 0.5 for x in dr)}, >1 pt {sum(abs(x) > 1 for x in dr)} of {len(dr)} '
              f'(the scan {a:.4f} as wide)')
        if SHOW:
            for i in range(n):
                print(f"  {i:2d} {p[i]['text']:>5} base {db[i]:+.2f}  rights " +
                      ' '.join(f'{p[i]["rights"][c] - s[i]["rights"][c]:+.1f}' if p[i]['rights'][c] and s[i]['rights'][c] else '  -  '
                               for c in range(11)))


main()
