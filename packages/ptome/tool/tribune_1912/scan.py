"""Each line of each region's spec (regions/PAGE-ID.spec) placed on the
scan: the OCR's lines of the region (lines.json, their two readings in
tess.json) paired with the spec's in order (the most alike, a line the
OCR lacks or the spec lacks left over), each paired line its box and its
baseline (where the ink of its middle half falls off most under it); a
line left over placed between its neighbours. In points (the scan's
pixels over PX, the page's origin the scan's). Written to
TRIBUNE_WORK/scan.json: {page: {region: [{base, left, right, size}]}}.

    python3 -I scan.py
"""
import difflib, json, os, re, sys
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from common import WORK, PX, IMAGES
from lines import regions


def key(t):
    return re.sub(r'[^a-z0-9]', '', t.lower())


def spec_lines(page, rid):
    """A region's spec: its lines' text (the kind and the marks gone),
    and the lines themselves."""
    path = os.path.join(HERE, 'regions', f'{page}-{rid}.spec')
    if not os.path.exists(path):
        return [], []
    raw = [l for l in open(path, encoding='utf-8').read().split('\n')[1:] if l and not l.startswith('@')]
    return [line_text(l) for l in raw], raw


def line_text(line):
    """A spec line's words: its kind gone (`P `, `S role `, `F `, `L `); a
    row's (`R `) its cells' in the line's own size, the small ones left
    out."""
    if line.startswith('R '):
        cells = [c.strip() for c in line[2:].split(' | ')]
        return ' '.join(re.sub(r'^\S+ ', '', c).replace('^', '') for c in cells if not c.startswith('s'))
    m = re.match(r'^(?:S \S+ |F\d? |L\+? |[PNC ] )(.*)$', line)
    t = m.group(1) if m else line
    return re.sub(r'\s*\|\s*|\s*//\s*', ' ', t).replace('^', '')


def align(a, b):
    """The spec's lines [a] paired with the OCR's [b] (each two readings):
    [(i, j)], j None where the OCR has no line for it."""
    sim = lambda x, y: max(difflib.SequenceMatcher(None, x, y[0]).ratio(),
                           difflib.SequenceMatcher(None, x, y[1]).ratio())
    n, m = len(a), len(b)
    NEG = -1e9
    D = [[NEG] * (m + 1) for _ in range(n + 1)]
    B = [[None] * (m + 1) for _ in range(n + 1)]
    D[0][0] = 0
    for x in range(n + 1):
        for y in range(m + 1):
            if D[x][y] == NEG:
                continue
            if x < n and y < m:
                v = D[x][y] + sim(a[x], b[y])
                if v > D[x + 1][y + 1]:
                    D[x + 1][y + 1], B[x + 1][y + 1] = v, (x, y, 'm')
            if x < n and D[x][y] - 0.3 > D[x + 1][y]:
                D[x + 1][y], B[x + 1][y] = D[x][y] - 0.3, (x, y, 's')
            if y < m and D[x][y] - 0.3 > D[x][y + 1]:
                D[x][y + 1], B[x][y + 1] = D[x][y] - 0.3, (x, y, 'o')
    x, y, out = n, m, {}
    while (x, y) != (0, 0):
        px, py, k = B[x][y]
        if k == 'm' and sim(a[px], b[py]) > 0.35:
            out[px] = py
        x, y = px, py
    return out


def baseline(ink, box):
    """The line's baseline: where most of its columns' ink ends (the
    lowest ink of each column of the box, the descenders' few below the
    rest), its letters' feet."""
    x0, y0, x1, y1 = box
    a = ink[y0:y1 + 2, x0:x1]
    cols = np.nonzero(a.any(axis=0))[0]
    if len(cols) < 5:
        return y1 - 0.2 * (y1 - y0)
    # (Each column's lowest ink, the ink of the line under it, whose tops
    # reach into the box, left out: the column's ink from the box's middle.)
    mid = (y1 - y0) // 2
    lows = []
    for c in cols:
        col = a[mid:, c]
        r = np.nonzero(col)[0]
        if len(r):
            # (The run of ink that starts in the box's middle half.)
            run_end = r[0]
            for q in r[1:]:
                if q - run_end > 2:
                    break
                run_end = q
            lows.append(mid + run_end)
    if not lows:
        return y1 - 0.2 * (y1 - y0)
    lows.sort()
    return y0 + lows[int(len(lows) * 0.4)] + 1


def fall(ink, x0, x1, est, half, slope, xc):
    """Where the ink of columns [x0, x1) falls off most within [half] of
    [est] (pixels), each column's rows shifted by the region's [slope]
    so that its lines lie level at its middle [xc]."""
    y0 = int(est) - half - 1
    n = 2 * half + 3
    prof = np.zeros(n)
    for x in range(max(0, int(x0)), min(ink.shape[1], int(x1)), 2):
        dy = slope * (x - xc)
        top = y0 + int(round(dy))
        col = ink[top:top + n, x]
        if len(col) == n:
            prof += col
    drop = prof[:-1] - prof[1:]
    k = int(np.argmax(drop))
    return (y0 + k + 1) if drop[k] > 3 else None


def sheared(ink, rbox, slope, step=16):
    """The region's ink summed along rows sheared by [slope] (its columns
    in strips of [step] pixels, each strip shifted as at its middle)."""
    x0, y0, x1, y1 = map(int, rbox)
    xc = (x0 + x1) / 2
    n = y1 - y0
    prof = np.zeros(n)
    for x in range(x0, x1, step):
        top = y0 + int(round(slope * (x + step / 2 - xc)))
        strip = ink[max(0, top):top + n, x:min(x + step, x1)].sum(axis=1)
        prof[:len(strip)] += strip
    return prof


def skew(ink, rbox):
    """The region's lines' slant (pixels down a pixel across): the shear
    at which its rows' ink is sharpest, its baselines' falls steepest."""
    best, arg = -1, 0.0
    for k in range(-24, 25):
        sl = k * 0.0015
        p = sheared(ink, rbox, sl)
        d = np.diff(p)
        v = float((d * d).sum())
        if v > best:
            best, arg = v, sl
    return arg


def head_base(ink, r):
    """A head's baseline: in its box, the fall of ink under rows that all
    have ink (its letters' stems), not under a thin rule."""
    h = r['height'] * PX
    x0, x1 = int(r['left'] * PX), int(r['right'] * PX)
    y0 = int(r['top'] * PX + 0.45 * h)
    y1 = int(r['top'] * PX + 1.1 * h)
    prof = ink[max(0, y0):y1, max(0, x0):x1].sum(axis=1).astype(float)
    if len(prof) < 10 or prof.max() == 0:
        return None
    stem = max(3, int(0.15 * h))
    best, arg = 0, None
    for k in range(stem, len(prof) - 1):
        above = prof[k - stem:k + 1]
        if above.min() < 0.12 * prof.max():
            continue
        d = prof[k] - prof[k + 1]
        if d > best:
            best, arg = d, k
    return max(0, y0) + arg + 1 if arg is not None else None


def refine(ink, res, rbox):
    """The region's baselines refined: the region's slant measured (its
    full lines' baselines at their left and their right thirds), each
    line's baseline where its ink falls off most, levelled to the
    region's middle; one out of step with its neighbours put between
    them first."""
    import statistics
    bases = [r['base'] for r in res]
    gaps = [b - a for a, b in zip(bases, bases[1:]) if 3 < b - a < 30]
    pitch = statistics.median(gaps) if gaps else 9.0
    for i in range(1, len(res) - 1):
        a, b, c = res[i - 1]['base'], res[i]['base'], res[i + 1]['base']
        mid = (a + c) / 2
        if (c - a) < 3 * pitch and abs(b - mid) > 0.45 * pitch and (res[i].get('height') or 0) < 2 * pitch:
            res[i]['base'] = round(mid, 2)
    rx0, rx1 = rbox[0], rbox[2]
    xc = (rx0 + rx1) / 2
    half = int(0.32 * pitch * PX)
    slope = skew(ink, rbox)
    # (The region's baselines: the falls of its levelled ink, each line
    # given the fall nearest where the OCR puts it, in order.)
    ry0, ry1 = int(rbox[1]), int(rbox[3])
    prof = sheared(ink, rbox, slope, 4)
    drop = np.maximum(prof[:-1] - prof[1:], 0)
    sep = max(4, int(0.55 * pitch * PX))
    peaks = [k for k in range(1, len(drop) - 1) if drop[k] >= drop[k - 1] and drop[k] >= drop[k + 1] and drop[k] > 0]
    peaks.sort(key=lambda k: -drop[k])
    strong = drop[peaks[min(len(peaks) - 1, len(res))]] if peaks else 0
    chosen = []
    for k in peaks:
        if drop[k] < 0.2 * strong:
            break
        if all(abs(k - q) >= sep for q in chosen):
            chosen.append(k)
    chosen = sorted(ry0 + k + 1 for k in chosen)
    # (A head: the fall of its own ink, its box's.)
    for r in res:
        if r.get('left') is not None and (r.get('height') or 0) > 1.8 * pitch:
            b = head_base(ink, r)
            if b is not None:
                r['base'] = round(b / PX, 2)
                r['head'] = True
    est = [r['base'] * PX for r in res]
    # (In order: the DP's cost, a line's distance from its fall, a line
    # without one its estimate kept at a cost.)
    m, L = len(chosen), len(est)
    miss = 0.5 * pitch * PX
    INF = float('inf')
    D = [[INF] * (m + 1) for _ in range(L + 1)]
    B = [[None] * (m + 1) for _ in range(L + 1)]
    for j in range(m + 1):
        D[0][j] = 0
    for i in range(1, L + 1):
        for j in range(m + 1):
            best, arg = D[i - 1][j] + miss, (i - 1, j, None)
            if j:
                if D[i][j - 1] < best:
                    best, arg = D[i][j - 1], (i, j - 1, 'skip')
                c = D[i - 1][j - 1] + abs(chosen[j - 1] - est[i - 1])
                if abs(chosen[j - 1] - est[i - 1]) < 0.7 * pitch * PX and c < best and not res[i - 1].get('head'):
                    best, arg = c, (i - 1, j - 1, j - 1)
            D[i][j], B[i][j] = best, arg
    i, j = L, m
    got = [False] * L
    while i > 0:
        pi, pj, what = B[i][j]
        if isinstance(what, int):
            res[i - 1]['base'] = round(chosen[what] / PX, 2)
            got[i - 1] = True
        if what != 'skip':
            i = pi
        j = pj
    # (A line no fall of the region's was given, a short one: its own
    # columns' fall, near the middle of its neighbours'.)
    for i in range(L):
        if got[i] or res[i].get('head'):
            continue
        prev = next((k for k in range(i - 1, -1, -1) if got[k]), None)
        nxt = next((k for k in range(i + 1, L) if got[k]), None)
        e = res[i]['base']
        if prev is not None and nxt is not None and nxt - prev < 6:
            e = res[prev]['base'] + (res[nxt]['base'] - res[prev]['base']) * (i - prev) / (nxt - prev)
        r = res[i]
        x0 = r['left'] * PX if r.get('left') is not None else rx0
        x1 = r['right'] * PX if r.get('right') is not None else rx1
        b = fall(ink, x0, x1, e * PX + slope * ((x0 + x1) / 2 - xc), int(0.3 * pitch * PX), slope, (x0 + x1) / 2)
        r['base'] = round(((b - slope * ((x0 + x1) / 2 - xc)) if b is not None else e * PX) / PX, 2)
    return slope


def main():
    lines = json.load(open(os.path.join(WORK, 'lines.json')))
    tess = json.load(open(os.path.join(WORK, 'tess.json')))
    regs = regions()
    out = {}
    for page in sorted(regs):
        ink = np.asarray(Image.open(os.path.join(WORK, IMAGES[page] + '.jpg'))) < 120
        out[page] = {}
        for rid, kind, rbox in regs[page]:
            texts, raw = spec_lines(page, rid)
            if not texts:
                continue
            rows = lines[str(page)].get(rid, [])
            reads = tess[str(page)].get(rid, [])
            ocr = [(key(t), key(' '.join(w['t'] for w in r['words']))) for r, t in zip(rows, reads)]
            pair = align([key(t) for t in texts], ocr)
            res = []
            for i, t in enumerate(texts):
                if i in pair:
                    box = rows[pair[i]]['box']
                    b = baseline(ink, box)
                    res.append({'base': round(b / PX, 2), 'left': round(box[0] / PX, 2),
                                'right': round(box[2] / PX, 2), 'height': round((box[3] - box[1]) / PX, 2),
                                'top': round(box[1] / PX, 2)})
                else:
                    res.append(None)
            # (A line the OCR lacks: between its neighbours, by their pitch.)
            for i in range(len(res)):
                if res[i] is None:
                    prev = next((j for j in range(i - 1, -1, -1) if res[j]), None)
                    nxt = next((j for j in range(i + 1, len(res)) if res[j]), None)
                    if prev is not None and nxt is not None:
                        b = res[prev]['base'] + (res[nxt]['base'] - res[prev]['base']) * (i - prev) / (nxt - prev)
                    elif prev is not None:
                        b = res[prev]['base'] + 9 * (i - prev)
                    elif nxt is not None:
                        b = res[nxt]['base'] - 9 * (nxt - i)
                    else:
                        b = rbox[1] / PX + 20
                    res[i] = {'base': round(b, 2), 'left': None, 'right': None, 'height': None, 'guess': True}
            # (Each baseline refined where the ink of its line's columns falls
            # off most near it; one out of step with its neighbours first
            # put between them.)
            sl = refine(ink, res, rbox)
            out[page][rid] = res
    json.dump(out, open(os.path.join(WORK, 'scan.json'), 'w'))
    for page, rs in out.items():
        print(page, {rid: (len(v), sum(1 for x in v if x.get('guess'))) for rid, v in rs.items()})


if __name__ == '__main__':
    main()
