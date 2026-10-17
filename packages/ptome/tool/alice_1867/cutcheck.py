"""Each cut's place in the PDF against the printing's: the drawing's ink
box on the PDF page (rendered at the scan's resolution) and on the scan,
each relative to its page's text block (its left edge, its first text
line's top), in points.

    python3 -I cutcheck.py BOOK PDF
"""
import json, os, subprocess, sys, tempfile
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import BOOKS, ROOT, BOOK, DPI, PITCH_PX, ocr_path, scan_path

book, pdf = sys.argv[1], sys.argv[2]
cfg = BOOKS[book]
cuts = json.load(open(f'{ROOT}/placed-{book}.json'))
P = json.load(open(ocr_path(cfg)))
PT = 72 / DPI


def text_origin_pdf(page):
    xml = subprocess.run(['pdftotext', '-f', str(page), '-l', str(page), '-bbox-layout', pdf, '-'],
                         capture_output=True, text=True).stdout
    import re
    lines = [tuple(float(v) for v in m) for m in
             re.findall(r'<line xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" yMax="([\d.]+)"', xml)]
    body = [l for l in lines if l[1] > 45]
    return lines, body


import transcribe
LEFTS = transcribe.text_lefts(transcribe.ocr_lines(book))
rows = []
with tempfile.TemporaryDirectory(dir=os.environ.get('TMPDIR')) as tmp:
    for c in cuts:
        leaf = c['leaf']
        page = leaf - cfg['offset']
        x0, y0, x1, y1 = c['box']
        # The scan: relative to the leaf's text edge and the page's first
        # text line (its OCR top).
        left = LEFTS[leaf]
        scan = ((x0 - left) * PT, (x1 - left) * PT, y0 * PT, y1 * PT)
        # The PDF page, rendered: the ink outside its text lines.
        subprocess.run(['pdftoppm', '-f', str(page), '-l', str(page), '-r', str(DPI), '-gray',
                        '-png', pdf, f'{tmp}/p'], check=True)
        png = [f for f in os.listdir(tmp) if f.startswith('p')][0]
        a = np.asarray(Image.open(f'{tmp}/{png}').convert('L')) < 128
        os.remove(f'{tmp}/{png}')
        all_lines, body = text_origin_pdf(page)
        for (lx0, ly0, lx1, ly1) in all_lines:
            a[int(ly0 / PT) - 4:int(ly1 / PT) + 4, int(lx0 / PT) - 4:int(lx1 / PT) + 4] = False
        ys, xs = np.nonzero(a)
        if len(ys) == 0:
            rows.append((c['n'], page, None))
            continue
        pdf_box = (xs.min() * PT - 18.6, xs.max() * PT - 18.6, ys.min() * PT, ys.max() * PT)
        rows.append((c['n'], page, tuple(p - q for p, q in zip(pdf_box, scan)),
                     (pdf_box[1] - pdf_box[0]) - (scan[1] - scan[0]),
                     (pdf_box[3] - pdf_box[2]) - (scan[3] - scan[2])))
worst = 0
for r in rows:
    if r[2] is None:
        print(f'cut {r[0]:2d} p.{r[1]:3d}: no ink found')
        continue
    n, page, (dl, dr, dt, db), dw, dh = r
    worst = max(worst, abs(dl), abs(dt))
    print(f'cut {n:2d} p.{page:3d}: left {dl:+5.1f} top {dt:+5.1f} width {dw:+5.1f} height {dh:+5.1f} pt')
print(f'largest offset {worst:.1f} pt')
