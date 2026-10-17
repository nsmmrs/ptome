"""A page of the PDF over its leaf of the scan, to read by eye: the leaf
turned upright (geometry.py) and set on the PDF's page by its rule
between the columns and its double rule under the running head (the
look's places for them), at the scan's scale, in red; the PDF in blue;
where both have ink, black: PUNCH_WORK/overlay/PAGE.png.

    python3 -I overlay.py PAGE...
"""
import json, os, subprocess, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image

WORK = os.environ.get('PUNCH_WORK', os.path.expanduser('~/.cache/asciidart-work/print-match/punch'))
PAGES = [int(a) for a in sys.argv[1:]]
sys.argv = sys.argv[:1]
import compare
DPI = int(os.environ.get('DPI', 150))
Q = DPI / 72
PT = 72 / 400
# The PDF's rule between the columns and its head's rule, a verso's and
# a recto's (the look's margins and the columns' widths).
RULE = {'verso': 58.8 + 213.5, 'recto': 53.2 + 213.5}
HEAD = 46.0
OUT = os.path.join(WORK, 'overlay')
os.makedirs(OUT, exist_ok=True)
geo = json.load(open(os.path.join(WORK, 'geometry.json')))
for page in PAGES:
    leaf = page + 3
    side = 'verso' if page % 2 == 0 else 'recto'
    base = os.path.join(OUT, 'pdf')
    # (Its place in the PDF, compare.py's: a page built alone, gen.py's
    # ONLY, its place in that list.)
    at = compare.page_index(page)
    subprocess.run(['pdftoppm', '-r', str(DPI), '-gray', '-png', '-f', str(at), '-l', str(at), '-singlefile',
                    os.path.join(WORK, 'build', 'punch.pdf'), base], check=True)
    pdf = np.asarray(Image.open(base + '.png').convert('L')) < 128
    g = geo[str(leaf)]
    up = Image.open(os.path.join(WORK, 'upright', f'{leaf:04d}.png')).convert('L')
    head = g['head'][0] if g['head'] else 85.3 / PT
    h, w = pdf.shape
    a = 1 / (PT * Q)  # scan pixels a PDF pixel
    warped = up.transform((w, h), Image.AFFINE, (a, 0, g['rule'] - RULE[side] / PT, 0, a, head - HEAD / PT),
                          resample=Image.BILINEAR, fillcolor=255)
    s = np.asarray(warped) < 110
    o = np.full((h, w, 3), 255, np.uint8)
    o[s] = (230, 60, 60)
    o[pdf] = (60, 90, 230)
    o[pdf & s] = (0, 0, 0)
    Image.fromarray(o).save(os.path.join(OUT, f'{page}.png'))
