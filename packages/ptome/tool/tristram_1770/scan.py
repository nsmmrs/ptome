"""Each spec line's place on the scan, in the page's points: its
baseline (where its letters' ink falls off most sharply under them) and
its ink's left and right ends. A line's rows its box in the draft
(where.json, spec.py's); a line with none (a line read by hand, a head
the OCR missed) the band of ink nearest where its neighbours put it.
The leaf set on the page by its text's left edge and its head's
baseline (common.py: LEFT, HEAD); a page with no head by its foot, the
foot's place on the page the book's (its median below the head); the
title and the frontispiece as the leaf lies. Written to
TRISTRAM_WORK/scan.json, by page; the signatures' and direction lines'
places (points from the text's left) to adjust.json (`sig/PAGE`,
`dir/PAGE`).

    python3 -I scan.py [PAGE...]
"""
import difflib, json, os, re, statistics, sys
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from common import WORK, PX, PITCH, LEFT, HEAD, side
from spec import ink_ends

ADJ = os.path.join(HERE, 'adjust.json')


def spec_pages():
    """tristram.spec's pages: [(page, leaf, [(index into where.json, the
    spec line)])], the lines printed (heads, text, feet, the Yorick's)."""
    out = []
    for i, raw in enumerate(open(os.path.join(HERE, 'tristram.spec'), encoding='utf-8').read().rstrip('\n').split('\n')):
        if raw.startswith('@page '):
            _, page, leaf = raw.split()
            out.append((page, int(leaf), []))
        elif not raw.startswith('@'):
            out[-1][2].append((i, raw))
    return out


# (The leaves whose paper is tinted under the text: page 66.)
TINTED = (83,)


def leaf_ink(leaf):
    """The leaf's ink: darker than the paper about it by a good deal (a
    tinted page's paper its own), else darker than 120."""
    from PIL import ImageFilter
    im = Image.open(os.path.join(WORK, 'png', f'{leaf:04d}.png')).convert('L')
    a = np.asarray(im)
    if leaf not in TINTED:
        return a < 120
    bg = np.asarray(im.filter(ImageFilter.MaxFilter(15)).filter(ImageFilter.GaussianBlur(12)))
    return a.astype(int) < bg.astype(int) - 55


def norm(t):
    t = re.sub(r'\[\.\w+\]#+|#+|__|\{\w+\}', '', t).lower().replace('ſ', 's').replace('f', 's')
    return re.sub(r'[^a-z0-9]', '', t)


def baseline(ink, box, initial=False, second=False):
    """The baseline in [box]'s rows: where the ink of the line's middle
    columns falls off most sharply, in its lower half; a box two lines
    deep (an initial's beside the line, or the OCR's two lines run
    together) its first line's."""
    x0, y0, x1, y1 = box
    if initial or y1 - y0 > 1.45 * PITCH * PX:
        # (An initial beside the line: its columns left out; the ink still
        # two lines deep, the first line's.)
        x0 = int(x0 + 0.15 * (x1 - x0))
        rows = np.nonzero(ink[y0:y1, x0:x1].sum(axis=1) > 0.03 * (x1 - x0))[0]
        if len(rows):
            y0, y1 = y0 + rows[0], y0 + rows[-1] + 1
        if second and y1 - y0 > 1.45 * PITCH * PX:
            # (The initial's second line: the lower.)
            y0 = int(y1 - 1.1 * PITCH * PX)
        elif initial or y1 - y0 > 1.45 * PITCH * PX:
            y1 = min(y1, int(y0 + 1.1 * PITCH * PX))
    h = max(8, y1 - y0)
    top, bot = max(0, y0 - 4), min(ink.shape[0] - 1, y1 + 6)
    pr = ink[top:bot, max(0, x0):x1].sum(axis=1).astype(float)
    if len(pr) < 6 or pr.max() == 0:
        return y1 - 0.2 * h
    d = pr[1:] - pr[:-1]
    lo = int(len(d) * 0.45)
    k = lo + int(np.argmin(d[lo:]))
    return top + k + 1


def bands_in(ink, x0, x1, y0, y1):
    """The runs of rows with ink across [x0, x1) in [y0, y1): (top,
    bottom) each, a gap of a few rows bridged."""
    prof = ink[y0:y1, x0:x1].sum(axis=1)
    on = prof > 0.015 * (x1 - x0)
    out, start, miss = [], None, 0
    for y, v in enumerate(on):
        if v:
            start = y if start is None else start
            miss = 0
        elif start is not None:
            miss += 1
            if miss > 3:
                a, b = y0 + start, y0 + y - miss + 1
                if b - a >= 14:
                    out.append((a, b))
                start, miss = None, 0
    if start is not None and y1 - (y0 + start) >= 14:
        out.append((y0 + start, y1))
    return out


def bands(ink, x0, x1, y0=60, y1=None):
    """The rows of ink across [x0, x1): (top, bottom, baseline) each."""
    y1 = y1 or ink.shape[0] - 40
    out = bands_in(ink, x0, x1, y0, y1)
    # (A band two lines deep, an initial beside them: parted where the
    # lines' own ink, the initial's columns aside, parts.)
    parted = []
    for a, b in out:
        if b - a > 1.45 * PITCH * PX:
            cols = np.nonzero(ink[a:b, x0:x1].sum(axis=0))[0]
            lo = x0 + (cols[0] if len(cols) else 0) + int(0.12 * (x1 - x0))
            sub = bands_in(ink, lo, x1, a, b)
            if len(sub) >= 2:
                parted += sub
                continue
            # (Lines run together by a stain or a shadow: parted at the
            # rows of least ink nearest a line's pitch apart.)
            k = round((b - a) / (PITCH * PX))
            if k >= 2:
                prof = ink[a:b, x0:x1].sum(axis=1).astype(float)
                cuts = [a]
                for q in range(1, k):
                    want = q * (b - a) / k
                    lo2, hi2 = int(want - 0.3 * PITCH * PX), int(want + 0.3 * PITCH * PX)
                    cuts.append(a + lo2 + int(np.argmin(prof[lo2:hi2])))
                cuts.append(b)
                parted += list(zip(cuts, cuts[1:]))
                continue
        parted.append((a, b))
    out = parted
    res = []
    for a, b in out:
        cols = np.nonzero(ink[a:b, x0:x1].sum(axis=0))[0]
        box = (x0 + cols[0], a, x0 + cols[-1], b) if len(cols) else (x0, a, x1, b)
        res.append((a, b, baseline(ink, box), box))
    return res


def choose(found, n, pitch, lines, ink):
    """[n] of the bands [found] in order, their baselines' steps nearest
    a line's pitch apart (a title's lines, `X`, any step), the bands with
    the most ink (a speck's, an accent's the least) the likelier."""
    m = len(found)
    mass = [float(ink[f[0]:f[1], f[3][0]:f[3][2] + 1].sum()) for f in found]
    big = sorted(mass)[len(mass) // 2] or 1.0
    weak = [max(0.0, 1 - mm / big) for mm in mass]
    INF = float('inf')
    D = [[INF] * m for _ in range(n)]
    B = [[None] * m for _ in range(n)]
    for j in range(m):
        D[0][j] = 2 * weak[j]
    for i in range(1, n):
        free = lines[i][1].startswith(('X ', 'C ', 'h ', 'f ', 'V+', 'R ', '@')) or lines[i - 1][1].startswith(('X ', 'h ', 'C '))
        for j in range(i, m):
            for q in range(i - 1, j):
                if D[i - 1][q] == INF:
                    continue
                step = found[j][2] - found[q][2]
                cost = 0 if free else ((step - pitch) / pitch) ** 2
                if step < 0.5 * pitch:
                    cost += 10
                cost += 2 * weak[j]
                if D[i - 1][q] + cost < D[i][j]:
                    D[i][j], B[i][j] = D[i - 1][q] + cost, q
    j = min(range(m), key=lambda j: D[n - 1][j])
    out = []
    for i in range(n - 1, -1, -1):
        out.append(found[j])
        j = B[i][j] if i else None
    return out[::-1]


def main():
    where = json.load(open(os.path.join(WORK, 'where.json')))
    path = os.path.join(WORK, 'scan.json')
    data = json.load(open(path)) if os.path.exists(path) else {}
    adjust = json.load(open(ADJ)) if os.path.exists(ADJ) else {}
    only = set(sys.argv[1:])
    pages = spec_pages()
    abbyy = {int(k) if isinstance(k, str) and k.isdigit() else k: v for k, v in enumerate(json.load(open(os.path.join(WORK, 'ocr2.json'))))}
    abbyy = {k: v['lines'] for k, v in abbyy.items() if isinstance(v, dict) and 'lines' in v}
    tess = {k: v['lines'] for k, v in json.load(open(os.path.join(WORK, 'tess.json'))).items()}
    pitch_px = PITCH * PX
    gaps = []
    measured = {}
    for page, leaf, lines in pages:
        if only and page not in only:
            continue
        ink = leaf_ink(leaf)
        boxes = [where[i] for i, _ in lines]
        known = [b for b in boxes if b]
        if known:
            x0 = int(min(b[0] for b in known)) - 40
            x1 = int(max(b[2] for b in known)) + 40
        else:
            x0, x1 = 100, 1050
        top_ink = None
        if page in ('67', '68'):
            # (A black page: its head the band above its ink.)
            dark = np.asarray(Image.open(os.path.join(WORK, 'png', f'{leaf:04d}.png')).convert('L')) < 90
            top_ink = int(np.nonzero(dark.mean(axis=1) > 0.4)[0].min())
        found = bands(ink, max(0, x0), min(ink.shape[1], x1), y1=top_ink - 5 if top_ink else None)
        rows = []
        for k, ((i, raw), b) in enumerate(zip(lines, boxes)):
            if b:
                base = baseline(ink, b, raw.startswith('I '), k > 0 and lines[k - 1][1].startswith('I '))
                a, z = ink_ends(ink, b)
                rows.append({'base': base, 'left': a, 'right': z, 'box': b})
            else:
                rows.append(None)
        # (Lines with no box: an OCR's line whose letters are the line's,
        # in order; then the bands left, in order, nearest where the lines
        # about them put them.)
        if rows and all(r is None for r in rows) and len(found) >= len(rows):
            # (A page read by hand: as many of its bands as its lines, in
            # order, those most evenly a line apart (a speck's band, the
            # paper's, left out).)
            for k, f in zip(range(len(rows)), choose(found, len(rows), pitch_px, lines, ink)):
                a, z = ink_ends(ink, f[3])
                rows[k] = {'base': f[2], 'left': a, 'right': z, 'box': list(f[3])}
        if any(r is None for r in rows):
            ocr = [l for src in (abbyy.get(leaf, []), tess.get(str(leaf), [])) for l in src]
            want = [k for k, r in enumerate(rows) if r is None and norm(lines[k][1][2:])]
            for k in want:
                t = norm(re.sub(r'^\S+ ', '', lines[k][1]) if lines[k][1].startswith(('X ', 'V+')) else lines[k][1][2:])
                lo = max((rows[j]['base'] for j in range(k) if rows[j]), default=0)
                hi = min((rows[j]['base'] for j in range(k + 1, len(rows)) if rows[j]), default=1e9)
                best, arg = 0.6, None
                for o in ocr:
                    ot = norm(' '.join(w['t'] for w in o['w']))
                    if not ot or not (lo < o['b'][3] and o['b'][1] < hi):
                        continue
                    r = difflib.SequenceMatcher(None, t, ot, autojunk=False).ratio()
                    if r > best:
                        best, arg = r, o
                if arg:
                    b = arg['b']
                    a, z = ink_ends(ink, b)
                    rows[k] = {'base': baseline(ink, b, lines[k][1].startswith('I '),
                                                k > 0 and lines[k - 1][1].startswith('I ')),
                               'left': a, 'right': z, 'box': b}
        used = {round(r['base']) for r in rows if r}
        free = [f for f in found if not any(abs(f[2] - u) < 0.4 * pitch_px for u in used)]
        if all(r is None for r in rows) and len(free) == len(rows):
            for k, f in enumerate(free):
                a, z = ink_ends(ink, f[3])
                rows[k] = {'base': f[2], 'left': a, 'right': z, 'box': list(f[3])}
        for k in range(len(rows)):
            if rows[k] is not None:
                continue
            prev = next(((j, rows[j]['base']) for j in range(k - 1, -1, -1) if rows[j]), None)
            nxt = next(((j, rows[j]['base']) for j in range(k + 1, len(rows)) if rows[j]), None)
            if prev:
                want = prev[1] + (k - prev[0]) * pitch_px
            elif nxt:
                want = nxt[1] - (nxt[0] - k) * pitch_px
            else:
                want = None
            # (A head or a foot further from its neighbour than a line.)
            near = 1.0 if lines[k][1][:2] in ('h ', 'f ') else 0.6
            cand = [f for f in free if want is None or abs(f[2] - want) < near * pitch_px]
            if prev:
                cand = [f for f in cand if f[2] > prev[1] + 0.4 * pitch_px]
            if cand:
                f = min(cand, key=lambda f: abs(f[2] - want) if want is not None else f[2])
                free.remove(f)
                a, z = ink_ends(ink, f[3])
                rows[k] = {'base': f[2], 'left': a, 'right': z, 'box': list(f[3])}
        # (A line whose baseline its neighbours belie, the lines about it
        # a line's pitch from it and from each other (an OCR's box two
        # lines deep, say): the band nearest where they put it.)
        for k in range(1, len(rows) - 1):
            a, r, b = rows[k - 1], rows[k], rows[k + 1]
            if not (a and r and b) or lines[k][1][:2] in ('h ', 'f ', 'X ', 'C ') or lines[k - 1][1][:2] in ('h ', 'X ', 'C '):
                continue
            if abs((b['base'] - a['base']) - 2 * pitch_px) > 0.25 * pitch_px:
                continue
            want = (a['base'] + b['base']) / 2
            if abs(r['base'] - want) > 0.35 * pitch_px:
                near = [f for f in found if abs(f[2] - want) < 0.35 * pitch_px]
                if near:
                    f = min(near, key=lambda f: abs(f[2] - want))
                    rows[k] = dict(r, base=f[2])
                else:
                    rows[k] = dict(r, base=want)
        measured[page] = (leaf, lines, rows, ink)
    # (The foot's place below the head, the book's: its median.)
    for page, (leaf, lines, rows, ink) in measured.items():
        if lines and rows and lines[0][1].startswith('h ') and lines[-1][1].startswith('f ') and rows[0] and rows[-1]:
            gaps.append(rows[-1]['base'] - rows[0]['base'])
    foot_gap = statistics.median(gaps) if gaps else 22 * pitch_px
    for page, (leaf, lines, rows, ink) in measured.items():
        # (The text's left edge: where most of its lines' ink starts.)
        lefts = sorted(round(r['left']) for r, (i, raw) in zip(rows, lines)
                       if r and raw[:2] in ('  ', 'N ', 'n '))
        if lefts:
            lx = max(set(lefts), key=lambda x: sum(abs(y - x) <= 5 for y in lefts))
            lx = min(y for y in lefts if abs(y - lx) <= 5)
        else:
            lx = 154 if side(leaf) == 'recto' else 228
        if lines and lines[0][1].startswith('h ') and rows[0]:
            ay = rows[0]['base']
        elif lines and lines[-1][1].startswith('f ') and rows[-1]:
            ay = rows[-1]['base'] - foot_gap
        else:
            ay = HEAD * PX
        to = lambda x, y: (LEFT[side(leaf)] + (x - lx) / PX, HEAD + (y - ay) / PX)
        out = []
        for (i, raw), r in zip(lines, rows):
            if r is None:
                out.append(None)
                continue
            _, b = to(0, r['base'])
            left, _ = to(r['left'], 0)
            right, _ = to(r['right'], 0)
            # (The top of its ink: its capitals' height, a title's size.)
            bx = [int(v) for v in r['box']]
            band = ink[max(0, int(r['base']) - int(2.5 * pitch_px)):int(r['base']), max(0, int(r['left'])):int(r['right']) + 1]
            prof = band.sum(axis=1)
            on = np.nonzero(prof > max(2, 0.01 * band.shape[1]))[0]
            # (The run of rows with ink that ends at the baseline.)
            top_px = int(r['base'])
            for y in range(len(prof) - 1, -1, -1):
                if prof[y] > max(2, 0.01 * band.shape[1]):
                    top_px = int(r['base']) - (len(prof) - y)
                elif int(r['base']) - (len(prof) - y) < top_px - 3:
                    break
            _, top = to(0, top_px)
            out.append({'base': round(b, 2), 'left': round(left, 2), 'right': round(right, 2), 'top': round(top, 2)})
            if raw.startswith('f '):
                # (The foot's signature and direction line: its ink's runs.)
                x0, y0, x1, y1 = [int(v) for v in r['box']]
                cols = np.nonzero(ink[y0:y1, max(0, int(lx) - 20):x1 + 20].sum(axis=0))[0] + max(0, int(lx) - 20)
                runs, start = [], None
                for a, z in zip(cols, list(cols[1:]) + [None]):
                    start = a if start is None else start
                    if z is None or z - a > 25:
                        runs.append((start, a))
                        start = None
                parts = [p.strip() for p in raw[2:].split(' | ')]
                marks = parts[:-1] if len(parts) > 1 else []
                if len(runs) >= len(marks) + 1 and marks:
                    for mark, run in zip(marks, runs):
                        key = 'dir' if mark.startswith('VOL') else 'sig'
                        adjust[f'{key}/{page}'] = round((run[0] - lx) / PX, 1)
        data[page] = out
        if page == '1':
            # (The rule under the title: the rows with ink most of the
            # way across, between its lines and the chapter's head.)
            a = np.asarray(Image.open(os.path.join(WORK, 'png', f'{leaf:04d}.png')).convert('L')) < 110
            rows_r = [y for y in range(250, 900) if a[y, 100:1050].sum() > 500]
            if rows_r:
                y0, y1 = min(rows_r), max(rows_r) + 1
                cols = np.nonzero(a[y0:y1].sum(axis=0) > (y1 - y0) // 2)[0]
                (rx0, ry0), (rx1, ry1) = to(cols.min(), y0), to(cols.max() + 1, y1)
                data['rule/1'] = [round(rx0, 2), round(ry0, 2), round(rx1 - rx0, 2), round(ry1 - ry0, 2)]
        if page in ('67', '68'):
            # (The black page's ink: the rows and columns mostly dark.)
            dark = ink_dark = np.asarray(Image.open(os.path.join(WORK, 'png', f'{leaf:04d}.png')).convert('L')) < 90
            r = np.nonzero(dark.mean(axis=1) > 0.4)[0]
            c = np.nonzero(dark.mean(axis=0) > 0.4)[0]
            (x0, y0), (x1, y1) = to(c.min(), r.min()), to(c.max() + 1, r.max() + 1)
            data[f'black/{page}'] = [round(x0, 2), round(y0, 2), round(x1 - x0, 2), round(y1 - y0, 2)]
    json.dump(data, open(path, 'w'))
    json.dump(dict(sorted(adjust.items())), open(ADJ, 'w'), indent=0)
    print(len(measured), 'pages;', sum(r is None for v in data.values() for r in v), 'lines not found')


if __name__ == '__main__':
    main()
