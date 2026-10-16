"""The words printed around a woodcut in a scan of it: the rectangles of
its ink apart from the picture (the largest connected ink), padded, to
paint out (fetch.yml's `blank`), and the picture's box.

    python3 -I blanks.py IMAGE [KEEP-BELOW-PX]
"""
import sys
import numpy as np
from PIL import Image

path = sys.argv[1]
a = np.asarray(Image.open(path).convert('L')) < 150
H, W = a.shape
S = 3
h, w = H // S, W // S
cells = a[:h * S, :w * S].reshape(h, S, w, S).sum((1, 3)) > 2
grown = cells.copy()
for _ in range(1):
    g = grown.copy()
    g[1:] |= grown[:-1]; g[:-1] |= grown[1:]; g[:, 1:] |= grown[:, :-1]; g[:, :-1] |= grown[:, 1:]
    grown = g
lab = np.zeros((h, w), int)
comps = []
for y in range(h):
    for x in range(w):
        if grown[y, x] and not lab[y, x]:
            n = len(comps) + 1
            stack = [(y, x)]; lab[y, x] = n; pts = []
            while stack:
                cy, cx = stack.pop(); pts.append((cy, cx))
                for ny, nx in ((cy + 1, cx), (cy - 1, cx), (cy, cx + 1), (cy, cx - 1)):
                    if 0 <= ny < h and 0 <= nx < w and grown[ny, nx] and not lab[ny, nx]:
                        lab[ny, nx] = n; stack.append((ny, nx))
            ys = [p[0] for p in pts]; xs = [p[1] for p in pts]
            comps.append((len(pts), min(xs) * S, min(ys) * S, (max(xs) + 1) * S, (max(ys) + 1) * S))
main = max(comps)
print('picture', main[1:])
rects = []
for c in comps:
    if c is main:
        continue
    _, x0, y0, x1, y1 = c
    # (A speck, not a letter: the picture's own.)
    if y1 - y0 < 18 or (x1 - x0) * (y1 - y0) < 500:
        continue
    rects.append([max(0, x0 - 3), max(0, y0 - 3), x1 - x0 + 6, y1 - y0 + 6])
print('blank:', rects)
