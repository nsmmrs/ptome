"""Each page's table on its scan: the thick rule left of the numbers
(Num.), traced down the page band by band for the page's lean; the
rules under the heads of the columns and over the figures at the foot;
the page turned upright by the lean (BABBAGE_WORK/upright/nNN.png) and
its frame written to BABBAGE_WORK/frame.json: the thick rule's x and the
two rules' y on the upright page, in pixels.

    python3 -I frame.py [N...]   # the Internet Archive's page numbers, 30-49
"""
import json, os, sys
import numpy as np
from PIL import Image

WORK = os.environ.get('BABBAGE_WORK', os.path.expanduser('~/.cache/asciidart-work/print-match/babbage'))
PAGES = [int(a) for a in sys.argv[1:]] or list(range(30, 50))


def runs(mask, least):
    """The runs of True in mask at least `least` long: (start, end)."""
    out, i = [], 0
    while i < len(mask):
        if mask[i]:
            j = i
            while j + 1 < len(mask) and mask[j + 1]:
                j += 1
            if j - i + 1 >= least:
                out.append((i, j))
            i = j
        i += 1
    return out


def thick_rule(ink, y0, y1):
    """The thick rule's middle between rows y0 and y1: the widest run of
    columns dark over most of those rows, in the page's left half."""
    prof = ink[y0:y1, : ink.shape[1] // 2].mean(axis=0)
    best = max(runs(prof > 0.6, 6), key=lambda r: r[1] - r[0], default=None)
    return None if best is None else (best[0] + best[1]) / 2


def main():
    path = os.path.join(WORK, 'frame.json')
    frames = json.load(open(path)) if os.path.exists(path) else {}
    os.makedirs(os.path.join(WORK, 'upright'), exist_ok=True)
    for n in PAGES:
        img = Image.open(os.path.join(WORK, 'jpg', f'n{n}.jpg')).convert('L')
        # (A page Google gave at a lower resolution: drawn up to the
        # others' by its ink's height, 4,892 pixels on theirs; its frame's
        # rules give its scale on the PDF's page as for any other.)
        if img.height < 3000:
            ys = np.where((np.asarray(img) < 128).any(axis=1))[0]
            k = 4892 / (ys[-1] - ys[0])
            img = img.resize((round(img.width * k), round(img.height * k)), Image.BICUBIC)
        ink = np.asarray(img) < 128
        h, w = ink.shape
        # (The lean: the thick rule's middle in bands down the table.)
        ys, xs = [], []
        for y0 in range(int(h * 0.2), int(h * 0.85), 200):
            x = thick_rule(ink, y0, y0 + 200)
            if x is not None:
                ys.append(y0 + 100)
                xs.append(x)
        lean = float(np.polyfit(ys, xs, 1)[0]) if len(ys) >= 3 else 0.0
        up = img.rotate(-np.degrees(np.arctan(lean)), resample=Image.BICUBIC, fillcolor=255)
        up.save(os.path.join(WORK, 'upright', f'n{n}.png'))
        ink = np.asarray(up) < 128
        x = thick_rule(ink, int(h * 0.2), int(h * 0.85))
        # (The rules across: the darkest rows across the figures' columns,
        # right of the thick rule, near the page's top (the heads') and its
        # foot (over the figures at the foot).)
        across = np.convolve(ink[:, int(x) + 40:int(x) + 1500].mean(axis=1), np.ones(3) / 3, mode='same')
        lo, hi = int(h * 0.08), int(h * 0.22)
        head = float(lo + np.argmax(across[lo:hi]))
        lo, hi = int(h * 0.8), int(h * 0.95)
        foot = float(lo + np.argmax(across[lo:hi]))
        # (The heavy rule after the tenth column, 290.9 points right of the
        # thick rule on the printing's plate: the scan's scale across.)
        k = (foot - head) / 546.2
        lo, hi = int(x + 284 * k), int(x + 298 * k)
        prof = ink[int(head) + 40:int(foot) - 40, lo:hi].mean(axis=0)
        best = max(runs(prof > 0.5, 3), key=lambda r: r[1] - r[0], default=None)
        tenth = lo + (best[0] + best[1]) / 2 if best else None
        frames[str(n)] = {'lean': lean, 'thick': x, 'head': head, 'foot': foot, 'tenth': tenth}
        print(n, {k: round(v, 4) if isinstance(v, float) else v for k, v in frames[str(n)].items()})
    json.dump(frames, open(path, 'w'), indent=0)


main()
