"""A page of the PDF over its scan, to read by eye: the scan turned
upright and set on the PDF's page by its frame (frame.py's: its thick
rule on the PDF's, its rules across on the PDF's, scaled between them),
in red, the PDF in blue, where both have ink, black:
BABBAGE_WORK/overlay/PAGE.png at 150 ppi.

    python3 -I overlay.py PAGE...
"""
import json, os, subprocess, sys
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from common import FOOT_RULE, HEAD_RULE, THICK, WORK

PAGES = [int(a) for a in sys.argv[1:]]
OUT = os.path.join(WORK, 'overlay')
os.makedirs(OUT, exist_ok=True)
DPI = int(os.environ.get("DPI", 150))
q = DPI / 72
frames = json.load(open(os.path.join(WORK, 'frame.json')))
for page in PAGES:
    base = os.path.join(OUT, 'pdf')
    subprocess.run(['pdftoppm', '-r', str(DPI), '-gray', '-png', '-f', str(page - 5), '-l', str(page - 5), '-singlefile',
                    os.path.join(WORK, 'build', 'babbage.pdf'), base], check=True)
    pdf = np.asarray(Image.open(base + '.png').convert('L')) < 128
    n = page + 24
    f = frames[str(n)]
    k = (f['foot'] - f['head']) / (FOOT_RULE - HEAD_RULE)  # scan pixels a point
    side = 'verso' if page % 2 == 0 else 'recto'
    up = Image.open(os.path.join(WORK, 'upright', f'n{n}.png')).convert('L')
    # (The PDF's pixel (X, Y) from the scan's: x = thick + (X / q - THICK) k.)
    h, w = pdf.shape
    a = k / q
    warped = up.transform((w, h), Image.AFFINE, (a, 0, f['thick'] - THICK[side] * k, 0, a, f['head'] - HEAD_RULE * k),
                          resample=Image.BILINEAR, fillcolor=255)
    s = np.asarray(warped) < 128
    o = np.full((h, w, 3), 255, np.uint8)
    o[s] = (230, 60, 60)
    o[pdf] = (60, 90, 230)
    o[pdf & s] = (0, 0, 0)
    Image.fromarray(o).save(os.path.join(OUT, f'{page}.png'))
