"""Each leaf's page on the scan: the paper's edges (the microfilm's dark
border outside them), the page's lean (the rule between the columns, or
the lines' left ends), the double rule under the running head, the rule
between the columns, the text's left and right ends and its last line's
foot; written to PUNCH_WORK/geometry.json, the leaf turned upright to
PUNCH_WORK/upright/NNNN.png.

    python3 -I geometry.py [LEAF...]
"""
import json, os, sys
import numpy as np
from PIL import Image

WORK = os.environ.get('PUNCH_WORK', os.path.expanduser('~/.cache/asciidart-work/print-match/punch'))
# (The plates and their blank backs: no running head.)
PLATES = {10, 11, 58, 59, 70, 71}
RULE_PT = {'verso': 58.8 + 213.5, 'recto': 53.2 + 213.5}
LEAVES = [int(a) for a in sys.argv[1:]] or list(range(4, 16)) + list(range(52, 76))


def runs(mask, least=1):
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


def main():
    ocr = json.load(open(os.path.join(WORK, 'ocr.json')))
    path = os.path.join(WORK, 'geometry.json')
    data = json.load(open(path)) if os.path.exists(path) else {}
    os.makedirs(os.path.join(WORK, 'upright'), exist_ok=True)
    for leaf in LEAVES:
        img = Image.open(os.path.join(WORK, 'png', f'{leaf:04d}.png')).convert('L')
        a = np.asarray(img)
        h, w = a.shape
        # (The paper: the long run of bright columns and rows.)
        # (Each column's and row's median: the paper's light, the film's
        # border dark; the text too sparse to move it.)
        colmed = np.median(a[int(h * 0.3):int(h * 0.7):4], axis=0)
        rs = runs(colmed > 110, 50)
        px = (rs[0][0], rs[-1][1])
        rowmed = np.median(a[:, px[0] + 50:px[1] - 50:4], axis=1)
        rs = runs(rowmed > 110, 50)
        py = (rs[0][0], rs[-1][1])
        # (The lean: the text lines' left ends against their heights, the
        # lines of each column.)
        lines = [l for l in ocr[leaf]['lines'] if sum(c.isalpha() for wd in l['w'] for c in wd['t']) > 15
                 and px[0] < l['b'][0] < px[1]]
        mid = (px[0] + px[1]) / 2
        lean = 0.0
        fits = []
        for side in (lambda l: l['b'][2] < mid + 100, lambda l: l['b'][0] > mid - 100):
            pts = [(l['b'][1], l['b'][0]) for l in lines if side(l)]
            if len(pts) > 20:
                ys, xs = np.array(pts, dtype=float).T
                # (Each column's lines flush left: the leftmost tenth.)
                cut = np.percentile(xs, 30)
                keep = xs < cut + 8
                if keep.sum() > 10:
                    fits.append(np.polyfit(ys[keep], xs[keep], 1)[0])
        if fits:
            lean = float(np.median(fits))
        # (Or the rule between the columns' lean, where the lines' left ends
        # disagree with it, a page of verse set in and out: the darkest
        # column near the middle, band by band down the page, fitted, the
        # bands off the line left out.)
        dark = a < 110
        pts = []
        for y in range(py[0] + 700, py[1] - 400, 120):
            band = dark[y:y + 120, int(mid - 250):int(mid + 250)].mean(axis=0)
            x = int(np.argmax(band))
            if band[x] > 0.6:
                pts.append((y + 60, mid - 250 + x))
        if len(pts) >= 15:
            ys, xs = np.array(pts, dtype=float).T
            for _ in range(3):
                fit = np.polyfit(ys, xs, 1)
                off = xs - np.polyval(fit, ys)
                keep = np.abs(off) < max(3, 2 * np.std(off))
                ys, xs = ys[keep], xs[keep]
            if abs(fit[0] - lean) > 0.01:
                lean = float(fit[0])
        up = img.rotate(-np.degrees(np.arctan(lean)), resample=Image.BICUBIC, fillcolor=255)
        up.save(os.path.join(WORK, 'upright', f'{leaf:04d}.png'))
        ink = np.asarray(up) < 110
        # (The double rule under the running head: the two darkest rows
        # across the paper in its top sixth, under the paper's edge.)
        acr = ink[:, px[0] + 80:px[1] - 80].mean(axis=1)
        top = py[0] + 60
        band = acr[top:top + int(h * 0.18)]
        rows = [top + r0 for r0, r1 in runs(band > 0.45, 1)]
        head = rows[:1]
        if not head and leaf not in PLATES:
            # (A faint rule: the first band past a third dark where the
            # head's rule stands on the pages of text, 200 to 330 rows under
            # the paper's top.)
            near = acr[py[0] + 200:py[0] + 330]
            hits = [py[0] + 200 + r0 for r0, r1 in runs(near > 0.3, 1)]
            head = hits[:1]
        # (A plate, its back, a page of no running head: anchored by the
        # paper's edges instead, the leaf the page (its head's rule where
        # a page of text has it, 44.8 points under the paper's top).)
        plain = not head
        # (The rule between the columns: the darkest column near the
        # paper's middle, over the text.)
        body = ink[(head[-1] if head else top) + 60:int(h * 0.85)]
        prof = body.mean(axis=0)
        lo, hi = int(mid - 250), int(mid + 250)
        rule = lo + int(np.argmax(prof[lo:hi]))
        if plain:
            # (The outer edge: a recto's right, a verso's left, the gutter's
            # side of the leaf in the scan's dark; no lean, no rule to take
            # it from.)
            verso = (leaf - 3) % 2 == 0
            head = [int(py[0] + 44.8 / 0.18)]
            rule = int(px[0] + RULE_PT['verso'] / 0.18) if verso else int(px[1] - (530.5 - RULE_PT['recto']) / 0.18)
            if lean:
                lean = 0.0
                up = img
                up.save(os.path.join(WORK, 'upright', f'{leaf:04d}.png'))
        data[str(leaf)] = {'lean': lean, 'paper': [px[0], py[0], px[1], py[1]], 'head': head, 'rule': rule,
                           'rule_dark': round(float(prof[rule]), 2), 'plain': plain}
        print(leaf, data[str(leaf)])
    json.dump(data, open(path, 'w'), indent=0)


main()
