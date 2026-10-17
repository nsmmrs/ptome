"""Each leaf of the Book of Common Prayer's scan (BCP_WORK/jp2) measured:
the paper (the long run of bright columns and rows), the frame of
printers' flowers round the text (the first and the last long dark run
of rows and of columns inside the paper, its outer and inner edges),
and the lean (the frame's left edge, band by band down the leaf,
fitted); the leaf drawn as PNG (png/) and turned upright (upright/).
Written to BCP_WORK/geometry.json.

    python3 -I geometry.py [LEAF...]
"""
import json, os, sys
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from common import WORK, LEAVES


def runs(mask, least):
    out, start = [], None
    for i, v in enumerate(mask):
        if v and start is None:
            start = i
        elif not v and start is not None:
            if i - start >= least:
                out.append((start, i))
            start = None
    if start is not None and len(mask) - start >= least:
        out.append((start, len(mask)))
    return out


def bands(profile, threshold):
    """The first and the last run of a profile over [threshold]: (outer,
    inner) edges of each, the first's outer its start."""
    rs = runs(profile > threshold, 3)
    if not rs:
        return None
    return rs[0], rs[-1]


def measure(a):
    h, w = a.shape
    colmed = np.median(a[int(h * 0.3):int(h * 0.7):4], axis=0)
    rs = runs(colmed > 120, 50)
    px = (rs[0][0], rs[-1][1])
    rowmed = np.median(a[:, px[0] + 50:px[1] - 50:4], axis=1)
    rs = runs(rowmed > 120, 50)
    py = (rs[0][0], rs[-1][1])
    ink = a < 120
    # (The frame looked for over the whole scan: a leaf's edge in shadow
    # can pass for the paper's.)
    inner = ink[2:h - 2, 2:w - 2]
    rows = inner.mean(axis=1)
    cols = inner.mean(axis=0)

    def edge(profile, lo, hi, last):
        # (The rule in that stretch: its darkest run, from its first row
        # past half the darkest's darkness; at the far end, its last.)
        seg = profile[lo:hi]
        if seg.max() < 0.12:
            return None
        rs = runs(seg > seg.max() * 0.5, 1)
        r = rs[-1] if last else rs[0]
        return (lo + r[0], lo + r[1])

    n, m = len(rows), len(cols)
    t = edge(rows, 0, n // 6, False)
    b = edge(rows, n - n // 6, n, True)
    l = edge(cols, 0, m // 5, False)
    r = edge(cols, m - m // 5, m, True)
    if None in (t, b, l, r):
        return px, py, None
    # (The frame as wide as its height has it, 0.587 of it: a leaf's dark
    # edge outside the rule passed over, the darkest run in from it.)
    want = (b[1] - t[0]) * 0.587
    if abs((r[1] - l[0]) - want) > 0.02 * want:
        lo = int(l[0] + want * 0.97)
        hi = int(min(m, l[0] + want * 1.02))
        seg = cols[lo:hi]
        if len(seg) and seg.max() > 0.12:
            k = int(np.argmax(seg))
            rs = runs(seg > seg.max() * 0.5, 1)
            run = next((q for q in rs if q[0] <= k < q[1]), (k, k + 1))
            r = (lo + run[0], lo + run[1])
    (t0, t1), (b0, b1), (l0, l1), (r0, r1) = t, b, l, r
    oy, ox = 2, 2
    frame = {'outer': [ox + l0, oy + t0, ox + r1, oy + b1], 'inner': [ox + l1, oy + t1, ox + r0, oy + b0]}
    return px, py, frame


def main():
    # (GEO_OUT: another file, a share of the leaves measured in parallel.)
    path = os.environ.get('GEO_OUT', os.path.join(WORK, 'geometry.json'))
    data = json.load(open(path)) if os.path.exists(path) else {}
    os.makedirs(os.path.join(WORK, 'png'), exist_ok=True)
    os.makedirs(os.path.join(WORK, 'upright'), exist_ok=True)
    for leaf in [int(a) for a in sys.argv[1:]] or LEAVES:
        png = os.path.join(WORK, 'png', f'{leaf:04d}.png')
        if not os.path.exists(png):
            Image.open(os.path.join(WORK, 'jp2', f'{leaf:04d}.jp2')).convert('L').save(png)
        img = Image.open(png)
        a = np.asarray(img)
        px, py, frame = measure(a)
        lean = 0.0
        if frame:
            # (The lean: the frame's left band's middle, strip by strip down
            # the leaf, fitted.)
            x0, y0, x1, y1 = frame['outer']
            ink = a < 120
            pts = []
            for y in range(y0 + 100, y1 - 100, 40):
                prof = ink[y:y + 40, max(0, x0 - 40):x0 + 60].mean(axis=0)
                xs = np.where(prof > 0.3)[0]
                if len(xs):
                    pts.append((y + 20, max(0, x0 - 40) + xs[0]))
            if len(pts) > 10:
                ys, xs = np.array(pts, dtype=float).T
                fit = np.polyfit(ys, xs, 1)
                keep = np.abs(xs - np.polyval(fit, ys)) < 4
                lean = float(np.polyfit(ys[keep], xs[keep], 1)[0])
        up = img.rotate(-np.degrees(np.arctan(lean)), resample=Image.BICUBIC, fillcolor=255)
        up.save(os.path.join(WORK, 'upright', f'{leaf:04d}.png'))
        px, py, frame = measure(np.asarray(up))
        data[str(leaf)] = {'lean': round(lean, 5), 'paper': [px[0], py[0], px[1], py[1]], 'frame': frame}
        print(leaf, data[str(leaf)])
    json.dump(data, open(path, 'w'), indent=0)


main()
