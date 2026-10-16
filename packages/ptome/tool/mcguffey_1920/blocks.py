"""A leaf's layout in points: its text block's left edge, each OCR line's
baseline, left and right (from the text's left), its x-height; each
picture's ink box (the large ink outside the words).

    python3 -I blocks.py WORK LEAF [LEAF...]
"""
import glob, json, re, sys
import numpy as np
from PIL import Image

work = sys.argv[1]
P = json.load(open(f'{work}/ocr.json'))
d = glob.glob(f'{work}/*_jp2')[0]
name = d.split('/')[-1][:-4]
PT = 72 / 360


def leaf_layout(leaf):
    a = np.asarray(Image.open(f'{d}/{name}_{leaf:04d}.jp2').convert('L')) < 110
    lines = []
    mask = a.copy()
    for l in P[leaf]['lines']:
        words = [w for w in l['w'] if re.search(r'[A-Za-z0-9]', w['t'])]
        if not words:
            continue
        x0 = min(w['b'][0] for w in words)
        x1 = max(w['b'][2] for w in words)
        y0 = min(w['b'][1] for w in words)
        y1 = max(w['b'][3] for w in words)
        if y1 - y0 > 120:
            continue
        prof = a[max(0, y0 - 4):y1 + 4, x0:x1].sum(1)
        band = np.nonzero(prof > 0.35 * prof.max())[0]
        base = max(0, y0 - 4) + band[-1]
        lines.append(dict(x0=x0, x1=x1, base=base, xh=band[-1] - band[0],
                          t=' '.join(w['t'] for w in l['w']),
                          ws=[(w['b'][0], w['b'][2], w['t']) for w in words]))
        for w in words:
            bx0, by0, bx1, by1 = w['b']
            mask[max(0, by0 - 8):by1 + 8, max(0, bx0 - 8):bx1 + 8] = False
    # (The pictures: large ink outside the words.)
    pics = []
    S = 8
    H, W = mask.shape[0] // S, mask.shape[1] // S
    cells = mask[:H * S, :W * S].reshape(H, S, W, S).sum((1, 3)) > 3
    grown = cells.copy()
    for _ in range(2):
        g = grown.copy()
        g[1:] |= grown[:-1]; g[:-1] |= grown[1:]; g[:, 1:] |= grown[:, :-1]; g[:, :-1] |= grown[:, 1:]
        grown = g
    seen = np.zeros_like(grown)
    for y in range(H):
        for x in range(W):
            if grown[y, x] and not seen[y, x]:
                stack = [(y, x)]; seen[y, x] = True; pts = []
                while stack:
                    cy, cx = stack.pop(); pts.append((cy, cx))
                    for ny, nx in ((cy + 1, cx), (cy - 1, cx), (cy, cx + 1), (cy, cx - 1)):
                        if 0 <= ny < H and 0 <= nx < W and grown[ny, nx] and not seen[ny, nx]:
                            seen[ny, nx] = True; stack.append((ny, nx))
                ys = [p[0] for p in pts]; xs = [p[1] for p in pts]
                y0, y1, x0, x1 = min(ys) * S, (max(ys) + 1) * S, min(xs) * S, (max(xs) + 1) * S
                if y1 - y0 > 150 and x1 - x0 > 150:
                    sub = mask[y0:y1, x0:x1]
                    yy, xx = np.nonzero(sub)
                    pics.append((x0 + xx.min(), y0 + yy.min(), x0 + xx.max(), y0 + yy.max()))
    return a.shape, lines, pics


WORDS = '-w' in sys.argv
JSON = next((a[7:] for a in sys.argv if a.startswith('--json=')), None)
dump = {}
for leaf in [int(a) for a in sys.argv[2:] if a != '-w' and not a.startswith('--')]:
    (h, w), lines, pics = leaf_layout(leaf)
    body = [l for l in lines if l['x1'] - l['x0'] > 900]
    left = int(np.median([l['x0'] for l in body if l['x0'] < min(b['x0'] for b in body) + 25])) if body else 0
    right = max((l['x1'] for l in body), default=0)
    print(f'== leaf {leaf} ({w}x{h}px) text left {left * PT:.1f}pt right {right * PT:.1f}pt measure {(right - left) * PT:.1f}pt')
    dump[leaf] = dict(left=left * PT, lines=[dict(base=l['base'] * PT, x0=(l['x0'] - left) * PT,
                                                    x1=(l['x1'] - left) * PT, xh=l['xh'] * PT, t=l['t'],
                                                    ws=[((a - left) * PT, (b - left) * PT, t) for a, b, t in l['ws']])
                                              for l in lines],
                      pics=[dict(top=p[1] * PT, bottom=p[3] * PT, x0=(p[0] - left) * PT, x1=(p[2] - left) * PT) for p in pics])
    items = [(l['base'], 'L', l) for l in lines] + [(p[1], 'P', p) for p in pics]
    prev = None
    for y, kind, it in sorted(items, key=lambda i: i[0]):
        if kind == 'L':
            gap = '' if prev is None else f'+{(it["base"] - prev) * PT:5.2f}'
            print(f'  L base {it["base"] * PT:6.1f} x {(it["x0"] - left) * PT:6.1f}..{(it["x1"] - left) * PT:6.1f} xh {it["xh"] * PT:4.1f} {gap:>7s}  {it["t"][:60]}')
            if WORDS:
                print('      words: ' + '  '.join(f'{(w[0] - left) * PT:.1f}-{(w[1] - left) * PT:.1f}:{w[2]}' for w in it['ws']))
            prev = it['base']
        else:
            x0, y0, x1, y1 = it
            print(f'  P top {y0 * PT:6.1f} bottom {y1 * PT:6.1f} x {(x0 - left) * PT:6.1f}..{(x1 - left) * PT:6.1f}  ({(x1 - x0) * PT:.1f} x {(y1 - y0) * PT:.1f} pt)')
            prev = y1

if JSON:
    json.dump(dump, open(JSON, 'w'), ensure_ascii=False, indent=0)
