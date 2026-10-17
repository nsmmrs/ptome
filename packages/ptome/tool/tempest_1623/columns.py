"""Each page's two columns on the scan: the rule between them and the
frame's rules about them (their ink, the page turned upright by its
frame's left rule), the head's rule above and the foot below, each
column cut out level and read by Tesseract line by line (`--psm 4`,
hOCR): TEMPEST_WORK/cols/NNNN-C.png and .hocr, and cols.json, each
column's box on the upright page in pixels and the page's lean.

    python3 -I columns.py [LEAF...]
"""
import json, os, subprocess, sys
import numpy as np
from PIL import Image

WORK = os.environ.get('TEMPEST_WORK', os.path.expanduser('~/.cache/asciidart-work/print-match/tempest'))
LEAVES = list(range(25, 44))


def runs(prof, thr, minlen):
    out, x = [], 0
    while x < len(prof):
        if prof[x] > thr:
            x1 = x
            while x1 + 1 < len(prof) and prof[x1 + 1] > thr:
                x1 += 1
            if x1 - x + 1 >= minlen:
                out.append((x, x1 + 1))
            x = x1
        x += 1
    return out


def page(leaf):
    img = Image.open(os.path.join(WORK, 'png', f'{leaf:04d}.png')).convert('L')
    a = np.asarray(img) < 120
    h, w = a.shape
    # (The page's lean: the rule between the columns, band by band, the
    # darkest column near the page's middle.)
    pts = []
    for y0 in range(int(h * 0.25), int(h * 0.85), 150):
        prof = np.convolve(a[y0:y0 + 150].mean(axis=0), np.ones(3) / 3, mode='same')
        x0, x1 = int(w * 0.44), int(w * 0.56)
        x = x0 + int(np.argmax(prof[x0:x1]))
        if prof[x] > 0.5:
            pts.append((y0 + 75, x))
    # (A page whose rule between the columns breaks off, the last page
    # set in bands: the frame's left rule, which runs down it whole.)
    if len(pts) < 3:
        pts = []
        for y0 in range(int(h * 0.1), int(h * 0.95), 150):
            prof = np.convolve(a[y0:y0 + 150].mean(axis=0), np.ones(3) / 3, mode='same')
            x = int(np.argmax(prof[:int(w * 0.15)]))
            if prof[x] > 0.5:
                pts.append((y0 + 75, x))
    lean = 0.0
    if len(pts) >= 3:
        a2 = np.array(pts, dtype=float)
        # (The bands that agree: a band without the rule found elsewhere.)
        med = np.median(a2[:, 1])
        a2 = a2[np.abs(a2[:, 1] - med) < 25]
        if len(a2) >= 3:
            lean = float(np.polyfit(a2[:, 0], a2[:, 1], 1)[0])
    up = img.rotate(-np.degrees(np.arctan(lean)), resample=Image.BICUBIC, fillcolor=255)
    b = np.asarray(up) < 120
    prof = np.convolve(b[int(h * 0.3):int(h * 0.85)].mean(axis=0), np.ones(3) / 3, mode='same')
    downs = [(x0 + x1) / 2 for x0, x1 in runs(prof, 0.6, 2)]
    mid = int(w * 0.44) + int(np.argmax(prof[int(w * 0.44):int(w * 0.56)]))
    left = max([x for x in downs if x < mid - w * 0.2], default=w * 0.03)
    right = min([x for x in downs if x > mid + w * 0.2], default=w * 0.97)
    # (The columns from the frame's top rule, or on the play's first page
    # the rule under its first scene's head, to its foot: the running
    # head and the foot's line read with them, told apart later.)
    rows = b[:, int(left) + 20:int(right) - 20].mean(axis=1)
    across = [(y0 + y1) / 2 for y0, y1 in runs(rows, 0.5, 2)]
    top = max([y for y in across if y < h * 0.4], default=h * 0.02)
    bottom = h - 20
    return up, lean, {'left': left, 'mid': mid, 'right': right, 'top': top, 'bottom': bottom}


def main():
    leaves = [int(a) for a in sys.argv[1:]] or LEAVES
    os.makedirs(os.path.join(WORK, 'cols'), exist_ok=True)
    path = os.path.join(WORK, 'cols.json')
    data = json.load(open(path)) if os.path.exists(path) else {}
    for leaf in leaves:
        up, lean, box = page(leaf)
        data[str(leaf)] = dict(box, lean=lean)
        for c, (x0, x1) in enumerate([(box['left'] + 6, box['mid'] - 6), (box['mid'] + 6, box['right'] - 6)], 1):
            crop = up.crop((int(x0), int(box['top']) + 6, int(x1), int(box['bottom'])))
            base = os.path.join(WORK, 'cols', f'{leaf:04d}-{c}')
            crop.save(base + '.png')
            subprocess.run(['tesseract', base + '.png', base, '--psm', '4', '-l', 'eng', 'hocr'],
                           check=True, capture_output=True)
        print(leaf, {k: round(v, 1) for k, v in box.items()}, round(lean, 5))
    json.dump(data, open(path, 'w'), indent=0)


main()
