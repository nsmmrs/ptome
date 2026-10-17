"""Each page of the PDF laid over its scan, to read by eye: the scan
mapped onto the PDF's page as compare.py maps it, in
red, the PDF in blue, where both have ink, black. Written to
JOHNSON_WORK/overlay/NN.png (the whole page) and NN-C-K.png (column C's
Kth third, at full size).

    python3 -I overlay.py [PDF]
"""
import json, os, subprocess, sys
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import compare

DPI = 150
OUT = os.path.join(compare.WORK, 'overlay')


def main():
    os.makedirs(OUT, exist_ok=True)
    report = compare.run(quiet=True)
    report.pop('bad_words')
    for pi, page in enumerate(compare.PAGES):
        base = os.path.join(OUT, f'pdf-{page}')
        subprocess.run(['pdftoppm', '-r', str(DPI), '-png', '-gray', '-f', str(pi + 1), '-l', str(pi + 1),
                        '-singlefile', compare.PDF, base], check=True)
        pdf = Image.open(base + '.png').convert('L')
        scan = Image.open(os.path.join(compare.WORK, f'{page:04d}.png')).convert('L')
        ax, bx, cx, ay, by, cy = report[page]['transform']
        # (The scan in the PDF's pixels: PDF point p = M q + t, q the
        # scan's point, so q = M^-1 (p - t); PIL's affine maps each output
        # pixel to its input pixel.)
        k = DPI / 72  # PDF pixels a point
        s = 300 / 72  # scan pixels a point
        inv = np.linalg.inv(np.array([[ax, bx], [ay, by]]))
        m = inv * (s / k)
        off = -inv @ np.array([cx, cy]) * s
        warped = scan.transform(pdf.size, Image.AFFINE,
                                (m[0, 0], m[0, 1], off[0], m[1, 0], m[1, 1], off[1]),
                                resample=Image.BILINEAR, fillcolor=255)
        p = np.asarray(pdf) < 128
        q = np.asarray(warped) < 110
        img = np.full(p.shape + (3,), 255, np.uint8)
        img[q] = (230, 60, 60)
        img[p] = (60, 90, 230)
        img[p & q] = (0, 0, 0)
        im = Image.fromarray(img)
        im.save(os.path.join(OUT, f'{page}.png'))
        w, h = im.size
        split = int(compare.SPLIT * k)
        for c, (x0, x1) in enumerate([(0, split), (split, w)], 1):
            for third in range(3):
                y0 = int(h * (0.06 + 0.31 * third))
                im.crop((x0, y0, x1, y0 + int(h * 0.33))).save(os.path.join(OUT, f'{page}-{c}-{third + 1}.png'))
        os.remove(base + '.png')


main()
