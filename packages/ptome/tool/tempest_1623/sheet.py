"""A page of the PDF beside its leaf of the scan, column by column, at
the same scale and height (both on the PDF's page: the scan by its frame,
scan.py's), each pair in thirds: TEMPEST_WORK/sheets/PAGE-C-K.png, the
scan on the left, the PDF on the right, read by eye for a line the spec
lacks or runs together.

    python3 -I sheet.py PAGE...
"""
import json, os, subprocess, sys
import numpy as np
from PIL import Image

WORK = os.environ.get('TEMPEST_WORK', os.path.expanduser('~/.cache/asciidart-work/print-match/tempest'))
PDF = os.path.join(WORK, 'build', 'tempest-folio.pdf')
cols = json.load(open(os.path.join(WORK, 'cols.json')))
DPI = 100
os.makedirs(os.path.join(WORK, 'sheets'), exist_ok=True)
for page in [int(a) for a in sys.argv[1:]]:
    base = os.path.join(WORK, 'sheets', 'pdf')
    subprocess.run(['pdftoppm', '-r', str(DPI), '-gray', '-png', '-f', str(page), '-l', str(page), '-singlefile', PDF, base], check=True)
    pdf = Image.open(base + '.png').convert('L')
    k = DPI / 72
    c = cols[str(24 + page)]
    scan = Image.open(os.path.join(WORK, 'png', f'{24 + page:04d}.png')).convert('L')
    up = scan.rotate(-np.degrees(np.arctan(c['lean'])), resample=Image.BICUBIC, fillcolor=255)
    s = 0.24 * k  # scan pixels to sheet pixels
    up = up.resize((int(up.width * s), int(up.height * s)))
    for col, (px0, px1) in enumerate([(40, 305), (300, 570)], 1):
        a = pdf.crop((int(px0 * k), int(60 * k), int(px1 * k), int(910 * k)))
        sx0 = (c['left'] if col == 1 else c['mid']) * s
        sx1 = (c['mid'] if col == 1 else c['right']) * s
        b = up.crop((int(sx0), int(c['top'] * s) - 20, int(sx1), int(c['top'] * s) - 20 + a.height))
        for third in range(3):
            y0, y1 = a.height * third // 3 - 10 if third else 0, a.height * (third + 1) // 3 + 10
            pa, pb = a.crop((0, y0, a.width, y1)), b.crop((0, y0, b.width, y1))
            o = Image.new('L', (pa.width + pb.width + 8, pa.height), 255)
            o.paste(pb, (0, 0))
            o.paste(pa, (pb.width + 8, 0))
            o.save(os.path.join(WORK, 'sheets', f'{page}-{col}-{third + 1}.png'))
