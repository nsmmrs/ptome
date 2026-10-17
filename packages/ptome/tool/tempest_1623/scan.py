"""Each printed line's place on the scan: its baseline and the left and
right ends of its ink, in the PDF's points, page by page, column by
column. Each leaf turned upright (columns.py's lean) and set on the
PDF's page by its frame: its left, middle and right rules, its head's
rule and its foot's, scaled onto the PDF's frame (no fit to the PDF's
lines). Each spec line matched to Tesseract's lines by its letters
(Needleman-Wunsch), a line Tesseract missed a pitch from its
neighbours; on the last leaf, curled, the lines spaced as its ink's
are. A line's ends from the rule it stands from, traced down the leaf
where the paper curls it (rule_at), the rule's own ink left out.

    python3 -I scan.py [PAGE...]   # TEMPEST_WORK/scan.json
"""
import json, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
import numpy as np
from PIL import Image

WORK = os.environ.get('TEMPEST_WORK', os.path.expanduser('~/.cache/asciidart-work/print-match/tempest'))
PT = 0.24
# The PDF's frame (images/folio-frame.svg): its left rule's x, its head's
# rule's y, its right rule's x, its foot's rule's y, in points.
FRAME = (40.2, 61.2, 566.0, 906.2)
cols = json.load(open(os.path.join(WORK, 'cols.json')))
fit = json.load(open(os.path.join(WORK, 'fit.json')))


def counts():
    out = {}
    for f in fit:
        if isinstance(f['line'], int):
            out[(f['page'], f['col'])] = out.get((f['page'], f['col']), 0) + 1
    return out


PITCH = 12.48 / PT  # the lines' pitch, in the scan's rows


def match(cand, sm, blocks, count):
    """The [count] candidates that are the column's lines, in order: by
    dynamic programming, each line a candidate, the lines of a block a
    pitch apart (each row off it costs), lines of different blocks at
    least two-thirds of a pitch apart, strong candidates preferred."""
    if count == 0 or not cand:
        return []
    top = float(np.median(sorted((sm[y] for y in cand), reverse=True)[:count]))
    gain = [min(1.0, sm[y] / top) * 40 for y in cand]
    m, inf = len(cand), float('inf')
    cost = [[inf] * m for _ in range(count)]
    back = [[-1] * m for _ in range(count)]
    for j in range(m):
        cost[0][j] = -gain[j]
    for i in range(1, count):
        same = blocks[i] == blocks[i - 1]
        for j in range(i, m):
            best, arg = inf, -1
            for k in range(i - 1, j):
                if cost[i - 1][k] == inf:
                    continue
                d = cand[j] - cand[k]
                if d < PITCH * 0.6:
                    continue
                if same:
                    pen = abs(d - PITCH) * 2.0
                else:
                    pen = 0.0 if d >= PITCH * 0.95 else (PITCH * 0.95 - d) * 4.0
                c = cost[i - 1][k] + pen
                if c < best:
                    best, arg = c, k
            if arg >= 0:
                cost[i][j] = best - gain[j]
                back[i][j] = arg
    j = min(range(m), key=lambda j: cost[count - 1][j])
    out = []
    for i in range(count - 1, -1, -1):
        out.append(cand[j])
        j = back[i][j]
    return sorted(out)


GEOMETRY = {}


def norm(t):
    import re
    t = re.sub(r'\[[^]]*\]|\{[v^] |[_{}@|^]', '', t)
    return re.sub(r'[^a-z]', '', t.lower().replace('ſ', 's').replace('v', 'u').replace('j', 'i')).replace('f', 's')


def spec_lines(page, col):
    """The spec's lines of the column, their letters."""
    out, p, c = [], None, 0
    for line in open(os.path.join(HERE, 'folio.spec'), encoding='utf-8'):
        line = line.rstrip('\n')
        if line.startswith('@page'):
            p, c = int(line.split()[1]), 0
            seen = 0
        elif line == '@column':
            seen += 1
            c = seen
        elif line == '@endband':
            # (Under a band, across the page: no column's.)
            c = -1 if c >= 2 else c
        elif p == page and c == col and line and not line.startswith(('@', '#')):
            out.append(norm(line[2:]))
    return out


def text_match(page, col, top, bottom):
    """Each spec line's baseline on the upright page: the Tesseract line
    it aligns with (Needleman-Wunsch on their letters), else a pitch on
    from the line before."""
    import difflib
    spec = spec_lines(page, col)
    tess = [(b, norm(t)) for b, t in tess_lines(page, (col - 1) % 2 + 1) if top - 20 < b < bottom + 30]
    n, m = len(spec), len(tess)
    score = [[0.0] * (m + 1) for _ in range(n + 1)]
    move = [[None] * (m + 1) for _ in range(n + 1)]
    gap = -0.2
    for i in range(1, n + 1):
        score[i][0], move[i][0] = score[i - 1][0] + gap, 'up'
    for j in range(1, m + 1):
        score[0][j], move[0][j] = score[0][j - 1] + gap, 'left'
    for i in range(1, n + 1):
        for j in range(1, m + 1):
            a, b = spec[i - 1], tess[j - 1][1]
            sim = difflib.SequenceMatcher(None, a, b, autojunk=False).ratio() if a and b else 0
            options = [(score[i - 1][j - 1] + sim - 0.35, 'diag'), (score[i - 1][j] + gap, 'up'), (score[i][j - 1] + gap, 'left')]
            score[i][j], move[i][j] = max(options)
    i, j, match = n, m, {}
    while i > 0 and j > 0:
        mv = move[i][j]
        if mv == 'diag':
            match[i - 1] = tess[j - 1][0]
            i, j = i - 1, j - 1
        elif mv == 'up':
            i -= 1
        else:
            j -= 1
    # (A match out of order with its neighbours, or nearer the line before
    # than two-thirds of a pitch: Tesseract's line read twice or misplaced;
    # left unmatched.)
    for k in sorted(match):
        before = [match[q] for q in match if q < k]
        after = [match[q] for q in match if q > k]
        if (before and match[k] < max(before) + PITCH * 0.66 * (k - max(q for q in match if q < k))) \
                or (after and match[k] > min(after)):
            del match[k]
    out = []
    for k in range(n):
        if k in match:
            out.append(match[k])
        else:
            prev = out[-1] if out else None
            nxt = next(((match[q], q) for q in range(k + 1, n) if q in match), None)
            if prev is not None:
                out.append(prev + PITCH)
            elif nxt:
                out.append(nxt[0] - (nxt[1] - k) * PITCH)
            else:
                out.append(top + k * PITCH)
    return out


RULES = {}


def rule_at(ink, rule, top, bottom):
    """The rule down the page near `rule` (a column of the upright page),
    traced: its darkest column in bands of 120 rows, a quadratic through
    those where it is strong; its column at a row."""
    key = (id(ink), rule)
    if key not in RULES:
        lo = int(rule) - 30
        ys, xs = [], []
        for y in range(top, bottom - 120, 120):
            prof = np.convolve(ink[y:y + 120, lo:int(rule) + 30].mean(axis=0), np.ones(5) / 5, mode='same')
            if prof.max() > 0.5:
                ys.append(y + 60)
                xs.append(lo + float(np.argmax(prof)))
        ys, xs = np.array(ys, dtype=float), np.array(xs)
        fit = None
        if len(ys) >= 4:
            # (Bands where the rule is broken, or a letter darker: off the
            # curve through the rest, left out.)
            keep = np.abs(xs - np.median(xs)) < 15
            for _ in range(2):
                fit = np.polyfit(ys[keep], xs[keep], 2)
                keep = np.abs(np.polyval(fit, ys) - xs) < 3
        RULES[key] = (lambda y: float(np.polyval(fit, y))) if fit is not None else (lambda y: float(rule))
    return RULES[key]


def ink_rows(ink, x0, x1, top, bottom):
    """The rows of the upright page where the column's lines' ink stops
    (each a baseline): under a run of dense rows, the first row with under
    a third of the run's most."""
    p = ink[top:bottom, x0:x1].sum(axis=1).astype(float)
    out, run = [], 0.0
    for y in range(1, len(p)):
        run = max(run, p[y - 1])
        if run > 0.03 * (x1 - x0) and p[y] < run / 3 <= p[y - 1]:
            if not out or top + y - out[-1] > 6 / PT:
                out.append(top + y)
            run = 0.0
        elif p[y] < 0.01 * (x1 - x0):
            run = 0.0
    return out


def tess_lines(page, col):
    """Tesseract's lines in the column (columns.py's crop and hOCR): each
    its baseline as a row of the upright page and its text."""
    import html, re
    leaf = 24 + page
    c = cols[str(leaf)]
    x0 = int(c['left']) + 6 if col == 1 else int(c['mid']) + 6
    y0 = int(c['top']) + 6
    s = open(os.path.join(WORK, 'cols', f'{leaf:04d}-{col}.hocr'), encoding='utf-8').read()
    out = []
    for m in re.finditer(r"class='ocr_line'[^>]*title=\"bbox (\d+) (\d+) (\d+) (\d+); baseline ([-\d.]+) ([-\d.]+)[^\"]*\"(.*?)</span>\s*</span>", s, re.S):
        bx0, by0, bx1, by1 = map(int, m.groups()[:4])
        words = [html.unescape(re.sub('<[^>]+>', '', w)) for w in re.findall(r"class='ocrx_word'[^>]*>(.*?)</span>", m.group(7) + '</span>', re.S)]
        out.append((y0 + by1 + float(m.group(6)), ' '.join(words)))
    return out


def tess_baselines(page, col):
    """Tesseract's lines' baselines in the column (columns.py's crop and
    hOCR), as rows of the upright page: each line's baseline at its left."""
    import re
    leaf = 24 + page
    c = cols[str(leaf)]
    x0 = int(c['left']) + 6 if col == 1 else int(c['mid']) + 6
    y0 = int(c['top']) + 6
    s = open(os.path.join(WORK, 'cols', f'{leaf:04d}-{col}.hocr'), encoding='utf-8').read()
    out = []
    for m in re.finditer(r"class='ocr_line'[^>]*title=\"bbox (\d+) (\d+) (\d+) (\d+); baseline ([-\d.]+) ([-\d.]+)", s):
        bx0, by0, bx1, by1 = map(int, m.groups()[:4])
        if bx1 - bx0 < 60:
            continue
        out.append(y0 + by1 + float(m.group(6)))
    return out


def geometry(page):
    """The page's frame on the scan (its left rule, its head's rule) and
    its scale onto the PDF's: (left, head, sx, sy)."""
    if page not in GEOMETRY:
        column(page, 1, 0)
    return GEOMETRY[page]


def column(page, col, count):
    leaf = 24 + page
    c = cols[str(leaf)]
    img = Image.open(os.path.join(WORK, 'png', f'{leaf:04d}.png')).convert('L')
    up = img.rotate(-np.degrees(np.arctan(c['lean'])), resample=Image.BICUBIC, fillcolor=255)
    a = np.asarray(up)
    ink = a < 115
    h, w = ink.shape
    # (The frame's rules down: the darkest columns of ink near the page's
    # edges and its middle, over the middle half of its height.)
    prof = np.convolve(ink[int(h * 0.4):int(h * 0.85)].mean(axis=0), np.ones(3) / 3, mode='same')
    left_rule = int(np.argmax(prof[:int(w * 0.15)]))
    right_rule = int(w * 0.85) + int(np.argmax(prof[int(w * 0.85):]))
    mid_rule = int(w * 0.44) + int(np.argmax(prof[int(w * 0.44):int(w * 0.53)]))
    c = dict(c, left=left_rule, right=right_rule, mid=mid_rule)
    xcol = (col - 1) % 2 + 1  # (the last page's 3rd and 4th: its 1st's and 2nd's places)
    x0, x1 = (int(c['left']) + 8, int(c['mid']) - 8) if xcol == 1 else (int(c['mid']) + 8, int(c['right']) - 8)
    # (The rules across the frame: its top, the head's rule under it, its
    # foot; the text between the head's rule, or the first page's head,
    # and the foot's.)
    full = ink[:, int(c['left']) + 30:int(c['right']) - 30].mean(axis=1)
    rules, y = [], 0
    while y < h:
        if full[y] > 0.3:
            y1 = y
            while y1 + 1 < h and full[y1 + 1] > 0.3:
                y1 += 1
            if y1 - y < 25:
                rules.append((y + y1) / 2)
            y = y1
        y += 1
    # (The frame's top: the first rule; the head's rule 110 to 180 pixels
    # under it; the foot: the last thick rule.)
    first = rules[0] if rules else 0
    # (The head's rule: the darkest row 125 to 160 pixels under the top.)
    lo, hi = int(first) + 125, int(first) + 160
    head_rule = lo + int(np.argmax(full[lo:hi]))
    top = int(head_rule) + 22
    if page == 1:
        # (The first page: its frame's top rule set on the PDF's; its
        # columns under the head's second rule, 318 pt down.)
        head_rule = first + 140
        top = int(head_rule + (322 - FRAME[1]) / PT)
    # (The foot's rule: the darkest row in the page's lowest eighth.)
    lo = int(h * 0.86)
    foot_y = lo + int(np.argmax(full[lo:int(h * 0.98)]))
    thick = [foot_y] if full[foot_y] > 0.3 else []
    bottom = int(min(thick)) - 6 if thick else h - 30
    # (Each scan's own scale: its frame set on the PDF's, the head's rule
    # to the foot's and the left rule to the right as the PDF's.)
    foot_rule = float(thick[0]) if thick else None
    # (A page whose foot's rule is too faint to find: the others' scale.)
    sy = (FRAME[3] - FRAME[1]) / ((foot_rule - head_rule) * PT) if foot_rule and page != 1 else 1.004
    sx = (FRAME[2] - FRAME[0]) / ((c['right'] - c['left']) * PT) if c['right'] - c['left'] > 2000 else 1.0
    GEOMETRY[page] = (c['left'], head_rule, sx, sy)
    if col == 1 and count:
        print(page, 'first', round(first), 'head', head_rule, 'foot', foot_rule, 'sy', round(sy, 4), 'sx', round(sx, 4), file=sys.stderr)
    # (The spec's lines matched to Tesseract's by their letters, in order;
    # a line Tesseract missed set a pitch from its neighbours.)
    chosen = text_match(page, col, top, bottom)
    # (The last page, whose short lines and brace Tesseract reads a line
    # off: its lines spaced as the ink's lines are, the run of them
    # nearest Tesseract's, set level with Tesseract's baselines (the ink's
    # fall a point or so under them, the other pages fitted to them). The
    # epilogue's column, its heads and its initial's ink no lines', by
    # Tesseract's.)
    if page == 19 and col != 3:
        rows = ink_rows(ink, x0, x1, top, bottom)
        n = len(chosen)
        best = min(((float(np.median(np.abs(np.array(rows[k:k + n]) - chosen))), k) for k in range(len(rows) - n + 1)),
                   default=None)
        if best and best[0] < 0.3 * PITCH:
            run = np.array(rows[best[1]:best[1] + n], dtype=float)
            chosen = list(run - float(np.median(run - np.array(chosen))))
    tess = []
    lines = []
    for base in chosen:
        base = int(round(base))
        # (Tesseract's baseline for the line, where it read one near: the
        # ink's steepest fall is a point or two off it on a line of
        # capitals or descenders.)

        # (The rule the column stands from, where it is at the line's
        # height: a leaf curled, its rules bending, the line where it stands
        # from it; the rule's own ink no letter's.)
        rule = c['left'] if xcol == 1 else c['mid']
        local = rule_at(ink, rule, top, bottom)(base)
        shift = rule - local
        a0 = max(x0, int(local) + 8)
        band = ink[base - 26:base + 1, a0:x1]
        dense = np.convolve(band.sum(axis=0) > 1, np.ones(7), mode='same') >= 5
        xs = np.where(dense)[0]
        l, r = (a0 + xs[0] + shift, a0 + xs[-1] + shift) if len(xs) else (x0, x1)
        # (On the PDF's page: the scan's frame set on the PDF's, its left
        # rule on the left rule, its head's rule on the head's rule.)
        def frame(x, y):
            return ((x - c['left']) * PT * sx + FRAME[0], (y - head_rule) * PT * sy + FRAME[1])
        bl, bb = frame(l, base)
        br, _ = frame(r, base)
        lines.append({'base': round(bb, 2), 'left': round(bl, 2), 'right': round(br, 2)})
    return lines


if __name__ == '__main__':
    pages = [int(a) for a in sys.argv[1:]] or list(range(1, 20))
    path = os.path.join(WORK, 'scan.json')
    data = json.load(open(path)) if os.path.exists(path) else {}
    n = counts()
    for page in pages:
        data[str(page)] = [column(page, c, n.get((page, c), 0)) for c in ((1, 2, 3, 4) if page == 19 else (1, 2))]
        for c, lines in enumerate(data[str(page)], 1):
            b = [l['base'] for l in lines]
            if len(b) > 10:
                print(page, c, 'pitch', round((b[-1] - b[0]) / (len(b) - 1), 3), file=sys.stderr)
            d = np.diff(b) if len(b) > 1 else [0]
            print(page, c, len(lines), round(float(np.median(d)), 2), 'gaps>', [round(float(x), 1) for x in d if x > 1.6 * np.median(d)])
    json.dump(data, open(path, 'w'), indent=0)
