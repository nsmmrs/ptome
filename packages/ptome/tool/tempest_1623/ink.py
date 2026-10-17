"""A column of a leaf's ink, on the PDF's page as scan.py sets it (its
frame on the PDF's): the rows where its lines' ink stops, each a
baseline, in points from the page's top — for the lines Tesseract
garbles.

    python3 -I ink.py PAGE X0 X1 Y0 Y1
"""
import os, sys
import numpy as np
from PIL import Image
sys.argv, ARGS = sys.argv[:1], [float(a) for a in sys.argv[1:]]
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import scan as S

DPI = 300
k = DPI / 72
page, x0, x1, y0, y1 = int(ARGS[0]), *ARGS[1:]
left, head, sx, sy = S.geometry(page)
leaf = 24 + page
c = S.cols[str(leaf)]
img = Image.open(os.path.join(S.WORK, 'png', f'{leaf:04d}.png')).convert('L')
up = img.rotate(-np.degrees(np.arctan(c['lean'])), resample=Image.BICUBIC, fillcolor=255)
a, b = S.PT * sx * k, S.PT * sy * k
tx, ty = S.FRAME[0] * k - left * a, S.FRAME[1] * k - head * b
w, h = int(x1 * k) + 1, int(y1 * k) + 1
q = np.asarray(up.transform((w, h), Image.AFFINE, (1 / a, 0, -tx / a, 0, 1 / b, -ty / b),
                            resample=Image.BILINEAR, fillcolor=255)) < 110
p = q[int(y0 * k):, int(x0 * k):].sum(1).astype(float)
# (A baseline: the row under a run of dense rows where the ink falls to
# under a third of the run's most.)
out, run = [], 0.0
for y in range(1, len(p)):
    run = max(run, p[y - 1])
    if run > 0.08 * (x1 - x0) * k and p[y] < run / 3 and p[y - 1] >= run / 3:
        v = round(y0 + y / k, 2)
        if not out or v - out[-1] > 6:
            out.append(v)
        run = 0.0
    elif p[y] < 0.02 * (x1 - x0) * k:
        run = 0.0
print(out)
