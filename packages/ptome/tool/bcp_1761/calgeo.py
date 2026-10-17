"""The Calendar's pages measured on the scan (leaves 23-34): each page's
double frame, its rules across (the title's, the table's head's, the
foot's) and down (the table's columns), and the baselines of its lines
(the titles', the heads', each day's row, the notes', the foot's), in
points from the frame's outer top left; written to BCP_WORK/cal.json.

A rule is a run of ink longer than any letter's, gaps of a pixel or two
bridged; a line's baseline the row under which its ink falls off most.

    python3 -I calgeo.py
"""
import json, os, sys
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from common import WORK, PX, PARTS


def runs(v, gap=3):
    """The runs of ink along [v] (a gap of [gap] pixels bridged): (start, end)."""
    out, start, miss = [], None, 0
    for i, b in enumerate(v):
        if b:
            if start is None:
                start = i
            miss = 0
        elif start is not None:
            miss += 1
            if miss > gap:
                out.append((start, i - miss + 1))
                start, miss = None, 0
    if start is not None:
        out.append((start, len(v) - miss))
    return out


def rules(ink, axis, least):
    """The rules along [axis] (0 across, 1 down) at least [least] pixels
    long: (place, from, to, thickness), neighbouring lines of pixels one."""
    lines = ink if axis == 0 else ink.T
    hits = []
    for y, row in enumerate(lines):
        for a, b in runs(row):
            if b - a >= least:
                hits.append((y, a, b))
    out = []
    for y, a, b in sorted(hits):
        for r in out:
            if y - r[4] <= 2 and min(b, r[2]) - max(a, r[1]) > 0.5 * (b - a):
                r[1], r[2], r[4] = min(r[1], a), max(r[2], b), y
                break
        else:
            out.append([y, a, b, y, y])
    return [((r[0] + r[4]) / 2, r[1], r[2], r[4] - r[0] + 1) for r in out]


def long_lines(ink, axis, cover, least=40, window=5):
    """The rules along [axis] that cover [cover] of the page's breadth
    though the leaf lean: a band of [window] lines of pixels whose runs of
    [least] pixels or more together cover it, its place the band's
    darkest line; (place, from, to, thickness)."""
    lines = ink if axis == 0 else ink.T
    n, width = lines.shape
    covered = np.zeros((n, width), bool)
    for y, row in enumerate(lines):
        for a, b in runs(row):
            if b - a >= least:
                covered[y, a:b] = True
    hits = []
    for y in range(n - window):
        band = covered[y:y + window].any(axis=0)
        if band.sum() >= cover:
            hits.append(y + int(np.argmax(covered[y:y + window].sum(axis=1))))
    out = []
    for y in sorted(set(hits)):
        if out and y - out[-1][-1] <= 3:
            out[-1].append(y)
        else:
            out.append([y])
    res = []
    for g in out:
        y = int(round(np.median(g)))
        cols = np.nonzero(covered[max(0, y - 3):y + 4].any(axis=0))[0]
        thick = sum(1 for k in range(max(0, y - 4), min(n, y + 5)) if covered[k].sum() > 0.3 * cover)
        res.append((y, int(cols[0]), int(cols[-1]), thick))
    return res


def baselines(ink, top, bottom, left, right):
    """The baselines of the lines of text between [top] and [bottom]
    (pixel rows), their ink between [left] and [right]: where the ink
    falls off most under each band of rows with ink."""
    prof = ink[top:bottom, left:right].sum(axis=1).astype(float)
    out = []
    for a, b in runs(prof > 0.02 * (right - left), gap=1):
        if b - a < 8:
            continue
        band = prof[a:b + 1]
        drop = band[:-1] - band[1:]
        k = int(np.argmax(drop[len(drop) // 3:])) + len(drop) // 3
        out.append(top + a + k + 1)
    return out


def cluster(items, key, within):
    """[items] (rules) a group to each run of them [within] points apart
    at [key]: each group's longest."""
    out = []
    for it in sorted(items, key=lambda i: i[key]):
        if out and it[key] - out[-1][-1][key] <= within:
            out[-1].append(it)
        else:
            out.append([it])
    return [max(g, key=lambda i: i[2] - i[1]) for g in out]


def dense_baselines(ink, top, bottom, left, right, least):
    """Baselines of lines set close (a note in a small type): where the
    ink falls off most, at least [least] pixels apart, strongest first."""
    region = ink[top:bottom, left:right]
    prof = region.sum(axis=1).astype(float)
    # (A rule's rows, and a row or two either side, are no line's.)
    for y, row in enumerate(region):
        if any(b - a > 0.3 * (right - left) for a, b in runs(row)):
            prof[max(0, y - 3):y + 4] = 0
    drop = np.maximum(prof[:-1] - prof[1:], 0)
    order = np.argsort(-drop)
    picked = []
    for k in order:
        if drop[k] < 0.1 * drop.max():
            break
        if all(abs(k - q) >= least for q in picked):
            picked.append(int(k))
    # (Strongest first: the caller takes as many as it has lines.)
    return [top + k + 1 for k in picked]


SIZE_PX = 10 * PX  # (a line of the Calendar's type, in pixels)


def main():
    geo = json.load(open(os.path.join(WORK, 'geometry.json')))
    res = {}
    for leaf in PARTS['calendar']:
        o = geo[str(leaf)]['frame']['outer']
        ink = np.asarray(Image.open(os.path.join(WORK, 'upright', f'{leaf:04d}.png')).convert('L')) < 130
        x0, y0, x1, y1 = o
        sub = ink[y0 - 6:y1 + 6, x0 - 6:x1 + 6]
        W, H = x1 - x0, y1 - y0
        pt = lambda v: round((v - 6) / PX, 2)
        across = [(pt(y), pt(a), pt(b), round(t / PX, 2)) for y, a, b, t in rules(sub, 0, int(0.3 * W))]
        down = [(pt(x), pt(a), pt(b), round(t / PX, 2)) for x, a, b, t in rules(sub, 1, int(0.15 * H))]
        fw, fh = W / PX, H / PX
        # (The structure: the rules across the frame's inside, the table's
        # rules down, each the longest of its neighbours.)
        # (A leaf that leans or curls more: a wider band, a little less of
        # the breadth.)
        for window, cover in ((5, 0.8), (9, 0.7), (13, 0.6)):
            model_across = [(pt(y), pt(a), pt(b), round(t / PX, 2))
                            for y, a, b, t in long_lines(sub, 0, int(cover * W), window=window)]
            model_across = [a for a in model_across if 6 < a[0] < fh - 6]
            if len(model_across) >= 6:
                break
        model_down = [(pt(x), pt(a), pt(b), round(t / PX, 2)) for x, a, b, t in long_lines(sub, 1, int(0.5 * H))]
        model_down = [d for d in model_down if 8 < d[0] < fw - 8]
        # (Each line's baseline: in the body the letters' column's, else the
        # whole inside's.)
        ys = [a[0] for a in model_across]
        xs = [d[0] for d in model_down]
        px = lambda v: int(round(v * PX)) + 6
        lines = []
        bands = [0] + ys + [fh]
        for top, bottom in zip(bands, bands[1:]):
            if bottom - top < 8:
                continue
            body = len(xs) >= 2 and top >= max(a[0] for a in model_across[:4]) - 1 and bottom - top > 150
            # (The letters' column: the one before the names', the widest.)
            k = max(range(len(xs) - 1), key=lambda i: xs[i + 1] - xs[i]) if len(xs) >= 3 else 0
            l, r = (px(xs[k - 1]) + 9, px(xs[k]) - 9) if body and k >= 1 else (px(12), px(fw - 12))
            lines += [round((b - 6) / PX, 2) for b in baselines(sub, px(top) + 7, px(bottom) - 5, l, r)]
        # (The table's head: Morning and Evening Prayer, their two lines
        # between the month's rule and the head's; `1 Less.` under it, over
        # the lessons' columns.)
        rs = [a[0] for a in model_across]
        head = max(r for r in rs if r < 200)
        month = max(r for r in rs if r < head - 5)
        lx = px(xs[-4]) + 9 if len(xs) >= 4 else px(fw / 2)
        prayer = [round((b - 6) / PX, 2) for b in baselines(sub, px(month) + 7, px(head) - 5, lx, px(fw - 12))]
        less = [round((b - 6) / PX, 2) for b in baselines(sub, px(head) + 7, px(head + 26), lx, px(fw - 12))]
        # (Under the table: its notes, a line at least 7 points from the
        # next, and the foot.)
        foot_rule = min([r for r in rs if r > 400] or [fh - 40])
        below = [round((b - 6) / PX, 2)
                 for b in dense_baselines(sub, px(foot_rule + 2), px(fh - 5.5), px(12), px(fw - 70), int(7 * PX))]
        # (The catchword at the right: the last band of ink over the
        # frame's foot, its bottom.)
        top_, bot_ = px(foot_rule + 2), px(fh - 5.5)
        region = sub[top_:bot_, px(fw - 60):px(fw - 8)]
        rows_ = region.sum(axis=1)
        for y, row in enumerate(region):
            if any(b - a > 0.6 * region.shape[1] for a, b in runs(row)):
                rows_[max(0, y - 3):y + 4] = 0
        bands = [(a, b) for a, b in runs(rows_ > 1, gap=1) if b - a > 0.15 * SIZE_PX]
        catch = round((top_ + bands[-1][1] - 6) / PX, 2) if bands else None
        res[leaf] = {'frame': [round(fw, 2), round(fh, 2)], 'across': across, 'down': down,
                     'rules': model_across, 'columns': model_down, 'lines': lines,
                     'prayer': prayer, 'less': less[:1], 'below': below, 'catch': catch}
    json.dump(res, open(os.path.join(WORK, 'cal.json'), 'w'), indent=1)
    for leaf, r in res.items():
        print(leaf, r['frame'], 'rules', [round(a[0], 1) for a in r['rules']])
        print('   columns', [(round(d[0], 1), round(d[1]), round(d[2])) for d in r['columns']])
        print('   prayer', r['prayer'], 'less', r['less'], 'below', r['below'], 'catch', r['catch'])


main()
