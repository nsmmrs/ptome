"""diff.spec's rows set where the scan has the figures: each item's first
line as the PDF sets it (a difference's figures, or a continued table's
first part), its ink slid up and down over the scan's (both on the PDF's
page, the scan by its frame, overlay.py's way) to where they overlap
most, within 10 points; the item's row moved by as much, up to 6 points
(more, a table of parts taken for the next). Run
after diffit.py has set each item where diff.spec says, a few times.

    python3 -I refine.py [PAGE...]
"""
import json, math, os, re, subprocess, sys
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from common import EDGES, FOOT_RULE, HEAD_RULE, RULES, THICK, WORK
from diffit import placed, row_base
from gen import SPEC

PAGES = [int(a) for a in sys.argv[1:]] or list(range(6, 26))
DPI = 200
Q = DPI / 72
FIRST_BASE = 95.25
SPEC_PATH = os.path.join(HERE, 'diff.spec')


def to_row(base):
    """A baseline in points under the first row's as a row (fractional)."""
    lo, hi = -2.0, 60.0
    for _ in range(60):
        mid = (lo + hi) / 2
        if row_base(mid) < base:
            lo = mid
        else:
            hi = mid
    return round((lo + hi) / 2, 2)


def masks(page):
    """The PDF's ink and the scan's on the PDF's page, at DPI."""
    base = os.path.join(WORK, 'refine-pdf')
    subprocess.run(['pdftoppm', '-r', str(DPI), '-gray', '-png', '-f', str(page - 5), '-l', str(page - 5), '-singlefile',
                    os.path.join(WORK, 'build', 'babbage.pdf'), base], check=True)
    pdf = np.asarray(Image.open(base + '.png').convert('L')) < 128
    n = page + 24
    f = json.load(open(os.path.join(WORK, 'frame.json')))[str(n)]
    k = (f['foot'] - f['head']) / (FOOT_RULE - HEAD_RULE)
    side = 'verso' if page % 2 == 0 else 'recto'
    up = Image.open(os.path.join(WORK, 'upright', f'n{n}.png')).convert('L')
    h, w = pdf.shape
    a = k / Q
    warped = up.transform((w, h), Image.AFFINE, (a, 0, f['thick'] - THICK[side] * k, 0, a, f['head'] - HEAD_RULE * k),
                          resample=Image.BILINEAR, fillcolor=255)
    return pdf, np.asarray(warped) < 128


def main():
    out, page, moved = [], None, []
    cache = {}
    lines = open(SPEC_PATH, encoding='utf-8').read().split('\n')
    counters = {}
    for line in lines:
        m = re.match(r'@page (\d+)', line)
        if m:
            page = int(m.group(1))
            counters = {'L': 0, 'R': 0}
        f_ = line.split()
        if page in PAGES and f_ and f_[0] in ('L', 'R', '+L', '+R'):
            side = f_[0][-1]
            kk = counters[side]
            counters[side] += 1
            if page not in cache:
                cache[page] = (masks(page), placed(page))
            (pdf, scan), got = cache[page]
            t = THICK['verso' if page % 2 == 0 else 'recto']
            if (side, kk) in got:
                y = got[(side, kk)]
                x0 = t + RULES[13] + (1.5 if side == 'L' else 22.5)  # (clear of the heavy rule)
                x1 = x0 + 21
                # (The item with its first two parts under it, if it has
                # parts: a shape no other place in the column has.)
                below = 16.5 if (len(f_) > 3 or f_[0].startswith('+')) else 1.0
                ys, ye = int((y - 7.5) * Q), int((y + below) * Q)
                patch = pdf[ys:ye, int(x0 * Q):int(x1 * Q)]
                best, score = 0, -1
                for dy in range(int(-10 * Q), int(10 * Q) + 1):
                    win = scan[ys + dy:ye + dy, int(x0 * Q):int(x1 * Q)]
                    if win.shape != patch.shape:
                        continue
                    sc = np.logical_and(win, patch).sum()
                    if sc > score:
                        best, score = dy, sc
                off = best / Q
                # (Not a whole part's line or more: one table's parts look
                # much like another's a line lower.)
                if 0.3 < abs(off) <= 6 and score > 0.3 * patch.sum():
                    on = f_[0].startswith('+')
                    i = 3 if on else 2
                    old = float(f_[i])
                    new = to_row(row_base(old) + off)
                    f_[i] = f'{new}'
                    moved.append((page, f_[1], round(off, 1)))
                    line = ' '.join(f_)
        out.append(line)
    open(SPEC_PATH, 'w', encoding='utf-8').write('\n'.join(out))
    print(f'{len(moved)} moved:', moved)


if __name__ == '__main__':
    main()
