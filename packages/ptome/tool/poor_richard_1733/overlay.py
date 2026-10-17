"""Each month's page of the PDF over its leaf of the scan, to read by
eye: the scan turned upright and set so that its frame's corner is the
PDF's (measure.py), in red, the PDF in blue, where both have ink, black:
PR_WORK/overlay/LEAF.png (at 200 ppi).

    python3 -I overlay.py [LEAF...]
"""
import os, sys
import numpy as np
from PIL import Image
LEAVES = [int(a) for a in sys.argv[1:]]
del sys.argv[1:]
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import measure

PDF = os.path.join(measure.WORK, 'build', 'poor-richard.pdf')
OUT = os.path.join(measure.WORK, 'overlay')


def main():
    os.makedirs(OUT, exist_ok=True)
    for leaf in LEAVES or measure.MONTHS:
        page = measure.pdf_page(PDF, measure.month_page(PDF, leaf)).convert('L')
        p = np.asarray(page) < 128
        ink, gray, k = measure.upright(Image.open(os.path.join(measure.WORK, 'png', f'{leaf:04d}.png')).convert('L'))
        left, top = measure.frame(ink)
        # (The scan's frame corner on the PDF's.)
        dx = int(round(measure.CORNER[0] / measure.PT)) - left
        dy = int(round(measure.CORNER[1] / measure.PT)) - top
        q = np.zeros_like(p)
        h, w = ink.shape
        ys, xs = slice(max(0, dy), min(p.shape[0], h + dy)), slice(max(0, dx), min(p.shape[1], w + dx))
        q[ys, xs] = ink[ys.start - dy:ys.stop - dy, xs.start - dx:xs.stop - dx]
        img = np.full(p.shape + (3,), 255, np.uint8)
        img[q] = (230, 60, 60)
        img[p] = (60, 90, 230)
        img[p & q] = (0, 0, 0)
        im = Image.fromarray(img)
        im.resize((im.width // 2, im.height // 2)).save(os.path.join(OUT, f'{leaf}.png'))


main()
