"""The first page's head measured from the ink, on the scan (in the PDF's
points, scan.py's frame) and on the PDF (drawn at 300 ppi): the
headpiece's, the title's two lines', the act's line's and the rules'
tops, bottoms, lefts and rights, and the PDF's against the scan's.

    python3 -I head1.py
"""
import os, subprocess, sys
import numpy as np
from PIL import Image
sys.argv = sys.argv[:1]
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import scan as S

# The parts of the head, top to bottom, as bands of the scan's page (pt).
BANDS = [('headpiece', 68, 182), ('THE', 190, 222), ('TEMPEST', 224, 270), ('rule', 278, 290),
         ('act', 292, 310), ('rule2', 312, 322)]


def extents(ink, rowpt, colpt, a, b, x0, x1):
    ys = [y for y in range(ink.shape[0]) if a <= rowpt(y) <= b]
    band = ink[ys[0]:ys[-1] + 1]
    xs = [x for x in range(ink.shape[1]) if x0 <= colpt(x) <= x1]
    sub = band[:, xs[0]:xs[-1] + 1]
    r = np.where(sub.mean(axis=1) > 0.01)[0]
    c = np.where(sub.mean(axis=0) > 0.02)[0]
    if not len(r) or not len(c):
        return None
    return (round(colpt(xs[0] + c[0]), 1), round(rowpt(ys[0] + r[0]), 1),
            round(colpt(xs[0] + c[-1]), 1), round(rowpt(ys[0] + r[-1]), 1))


def scan_parts():
    left, head, sx, sy = S.geometry(1)
    c = S.cols['25']
    img = Image.open(os.path.join(S.WORK, 'png', '0025.png')).convert('L')
    up = img.rotate(-np.degrees(np.arctan(c['lean'])), resample=Image.BICUBIC, fillcolor=255)
    ink = np.asarray(up) < 115
    return {n: extents(ink, lambda y: (y - head) * S.PT * sy + S.FRAME[1], lambda x: (x - left) * S.PT * sx + S.FRAME[0],
                       a, b, 48, 558) for n, a, b in BANDS}


def pdf_parts():
    base = os.path.join(S.WORK, 'head1')
    subprocess.run(['pdftoppm', '-r', '300', '-gray', '-png', '-f', '1', '-l', '1', '-singlefile',
                    os.path.join(S.WORK, 'build', 'tempest-folio.pdf'), base], check=True)
    ink = np.asarray(Image.open(base + '.png').convert('L')) < 128
    k = 72 / 300
    return {n: extents(ink, lambda y: y * k, lambda x: x * k, a, b, 48, 558) for n, a, b in BANDS}


if __name__ == '__main__':
    s, p = scan_parts(), pdf_parts()
    for n, _, _ in BANDS:
        a, b = s[n], p[n]
        print(f'{n:10} scan {a} pdf {b}' + (f'  width {(b[2] - b[0]) / (a[2] - a[0]):.3f} height {(b[3] - b[1]) / (a[3] - a[1]):.3f} top {b[1] - a[1]:+.1f} left {b[0] - a[0]:+.1f}' if a and b else ''))
