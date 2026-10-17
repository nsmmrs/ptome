"""A page of the PDF over its leaf of the scan, to read by eye: the scan
turned upright and set on the PDF's page by its frame as scan.py sets
its lines (its left rule on the PDF's, its head's rule on the PDF's,
scaled to the PDF's frame), in red, the PDF in blue, where both have
ink, black: TEMPEST_WORK/overlay/PAGE.png at 100 ppi.

    python3 -I overlay.py PAGE...
"""
import json, os, subprocess, sys
import numpy as np
from PIL import Image
sys.argv, PAGES = sys.argv[:1], [int(a) for a in sys.argv[1:]]
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import scan as S

OUT = os.path.join(S.WORK, 'overlay')
os.makedirs(OUT, exist_ok=True)
DPI = 150
k = DPI / 72
for page in PAGES:
    base = os.path.join(OUT, 'pdf')
    subprocess.run(['pdftoppm', '-r', str(DPI), '-gray', '-png', '-f', str(page), '-l', str(page), '-singlefile',
                    os.path.join(S.WORK, 'build', 'tempest-folio.pdf'), base], check=True)
    pdf = np.asarray(Image.open(base + '.png').convert('L')) < 128
    geo = S.geometry(page)
    leaf = 24 + page
    c = S.cols[str(leaf)]
    img = Image.open(os.path.join(S.WORK, 'png', f'{leaf:04d}.png')).convert('L')
    up = img.rotate(-np.degrees(np.arctan(c['lean'])), resample=Image.BICUBIC, fillcolor=255)
    # (Scan pixel (x, y) to the PDF's point: (x - left) PT sx + FRAME0, (y - head) PT sy + FRAME1.)
    left, head, sx, sy = geo
    a, b = S.PT * sx * k, S.PT * sy * k
    tx, ty = S.FRAME[0] * k - left * a, S.FRAME[1] * k - head * b
    h, w = pdf.shape
    warped = up.transform((w, h), Image.AFFINE, (1 / a, 0, -tx / a, 0, 1 / b, -ty / b), resample=Image.BILINEAR, fillcolor=255)
    q = np.asarray(warped) < 110
    o = np.full((h, w, 3), 255, np.uint8)
    o[q] = (230, 60, 60)
    o[pdf] = (60, 90, 230)
    o[pdf & q] = (0, 0, 0)
    Image.fromarray(o).save(os.path.join(OUT, f'{page}.png'))
