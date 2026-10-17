"""Each spec line's place on the scan, in the PDF's points: its baseline
and its ink's left and right ends. Each column's spec lines matched to
the OCR's lines of that column (align.py's, the leaf upright) by their
letters, in order (Needleman-Wunsch); a line's baseline where its box's
ink falls off at its foot; a line the OCR missed set a pitch from its
neighbours. On the PDF's page by the leaf's rule between the columns
and its double rule under the running head (overlay.py's anchors).

    python3 -I scan.py [PAGE...]   # PUNCH_WORK/scan.json
"""
import difflib, json, os, re, sys
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.environ.get('PUNCH_WORK', os.path.expanduser('~/.cache/asciidart-work/print-match/punch'))
PT = 72 / 400
PITCH = 7.02
RULE = {'verso': 58.8 + 213.5, 'recto': 53.2 + 213.5}
HEAD = 46.0
PAGES = [int(a) for a in sys.argv[1:] if a.isdigit()]


def norm(t):
    return re.sub(r'[^a-z0-9]', '', t.replace('__', '').lower())


def spec_lines():
    """punch.spec's lines by page and column, in order; a block floating
    to a column's side (`@float` to `@end`) a column of its own, the
    column's number and two."""
    out, page, col, inner = {}, None, 0, 0
    for raw in open(os.path.join(HERE, 'punch.spec'), encoding='utf-8'):
        raw = raw.rstrip('\n')
        if raw.startswith('@page'):
            page, col = int(raw.split()[1]), 0
        elif raw == '@column':
            col += 1
        elif raw.startswith('@float'):
            inner = 2
        elif raw == '@end' and inner:
            inner = 0
        elif raw and not raw.startswith(('@', '#')):
            # (A table's cell of two printed lines: each line its own.)
            text = raw[2:]
            if raw.startswith('T ') and ' // ' in text:
                cells = [c.split(' // ') for c in (text + ' ').split(' | ')]
                for k in range(max(len(c) for c in cells)):
                    out.setdefault((page, col + inner), []).append(' | '.join(c[k] if k < len(c) else '' for c in cells))
                continue
            out.setdefault((page, col + inner), []).append(text)
    return out


def floats():
    """Each column's floating blocks' inner edge (`@float right WIDTH
    GAP`, at the column's right): the PDF's points, by page and column;
    the column's lines short of it, the float's from it."""
    out, page, col = {}, None, 0
    for raw in open(os.path.join(HERE, 'punch.spec'), encoding='utf-8'):
        raw = raw.rstrip('\n')
        if raw.startswith('@page'):
            page, col = int(raw.split()[1]), 0
        elif raw == '@column':
            col += 1
        elif raw.startswith('@float'):
            _, side, width, _gap = raw.split()
            side = 'verso' if page % 2 == 0 else 'recto'
            # (The column's right edge: the rule's gap, or the page's
            # margin, the look's.)
            right = RULE[side] - 2 if col == 1 else 530.5 - (43.9 if side == 'verso' else 51.1)
            edge = right - float(width)
            out[(page, col)] = min(out.get((page, col), edge), edge)
    return out


def match(spec, ocr):
    """Each spec line's OCR line (an index), or None: by their letters."""
    n, m = len(spec), len(ocr)
    a = [norm(s) for s in spec]
    b = [norm(o['ocr']) for o in ocr]
    score = np.zeros((n + 1, m + 1))
    move = np.zeros((n + 1, m + 1), dtype=int)
    gap = -0.2
    score[1:, 0] = gap * np.arange(1, n + 1)
    score[0, 1:] = gap * np.arange(1, m + 1)
    move[1:, 0], move[0, 1:] = 1, 2
    for i in range(1, n + 1):
        for j in range(1, m + 1):
            sim = difflib.SequenceMatcher(None, a[i - 1], b[j - 1], autojunk=False).ratio() if a[i - 1] and b[j - 1] else 0
            opts = (score[i - 1, j - 1] + sim - 0.4, score[i - 1, j] + gap, score[i, j - 1] + gap)
            k = int(np.argmax(opts))
            score[i, j], move[i, j] = opts[k], k
    out = [None] * n
    i, j = n, m
    while i > 0 and j > 0:
        if move[i, j] == 0:
            out[i - 1] = j - 1
            i, j = i - 1, j - 1
        elif move[i, j] == 1:
            i -= 1
        else:
            j -= 1
    return out


def main():
    sys.path.insert(0, HERE)
    import align
    ocr = json.load(open(os.path.join(WORK, 'ocr.json')))
    geo = json.load(open(os.path.join(WORK, 'geometry.json')))
    lines = spec_lines()
    path = os.path.join(WORK, 'scan.json')
    data = json.load(open(path)) if os.path.exists(path) else {}
    pages = PAGES or sorted({p for p, _ in lines})
    for page in pages:
        leaf = page + 3
        g = geo[str(leaf)]
        side = 'verso' if page % 2 == 0 else 'recto'
        head = g['head'][0] if g['head'] else 85.3 / PT
        ink = np.asarray(Image.open(os.path.join(WORK, 'upright', f'{leaf:04d}.png'))) < 110
        to_x = lambda x: RULE[side] + (x - g['rule']) * PT
        to_y = lambda y: HEAD + (y - head) * PT
        ocr_all = align.ocr_lines(ocr, geo, leaf)
        data[str(page)] = {}
        edges = floats()
        for col in (1, 2, 3, 4):
            spec = lines.get((page, col), [])
            if col > 2 and not spec:
                continue
            # (A column with a block floating at its side: its lines short
            # of the float's edge, the float's from it.)
            base_col = col if col <= 2 else col - 2
            edge = edges.get((page, base_col))
            edge_px = g['rule'] + (edge - RULE[side]) / PT if edge is not None else None
            # (A page of one column, a plate: all the OCR's lines its.)
            single = (page, 2) not in lines
            mine = sorted((o for o in ocr_all if o['col'] == base_col or single), key=lambda o: o['box'][3])
            if edge_px is not None:
                # (A line the OCR read across both, a verse's two halves:
                # its words each side of the edge a line of their own.)
                split = []
                for o in mine:
                    sides = {}
                    for wd in o.get('words', []):
                        sides.setdefault(wd['box'][0] >= edge_px - 6, []).append(wd)
                    # (Only where the words part at the edge, a gap wider
                    # than a justified line's spaces: not a line across it.)
                    if len(sides) == 2:
                        gap = min(w['box'][0] for w in sides[True]) - max(w['box'][2] for w in sides[False])
                        if gap < 15:
                            sides = {False: sides[False] + sides[True]}
                    if len(sides) < 2:
                        split.append(o)
                        continue
                    for ws in sides.values():
                        box = [min(w['box'][0] for w in ws), min(w['box'][1] for w in ws),
                               max(w['box'][2] for w in ws), max(w['box'][3] for w in ws)]
                        split.append(dict(o, box=box, words=ws, ocr=' '.join(w['t'] for w in ws)))
                mine = split
            cand = [o for o in mine if edge_px is None or (o['box'][0] >= edge_px - 6) == (col > 2)]
            idx = match(spec, cand)
            out = []
            # (The column's baselines: where its ink falls off under a line.)
            xs0, xs1 = (g['rule'] - 1200, g['rule'] - 8) if base_col == 1 else (g['rule'] + 8, g['rule'] + 1200)
            if edge_px is not None:
                xs0, xs1 = (int(edge_px), xs1) if col > 2 else (xs0, int(edge_px) - 6)
            prof = ink[:, max(0, xs0):xs1].sum(axis=1).astype(float)
            falls, run = [], 0.0
            for y in range(1, len(prof)):
                run = max(run, prof[y - 1])
                if run > 40 and prof[y] < run / 3 <= prof[y - 1]:
                    falls.append(y)
                    run = 0.0
                elif prof[y] < 5:
                    run = 0.0
            falls = np.array(falls)
            prev = None
            pitch_px = PITCH / PT
            for k, s in enumerate(spec):
                if idx[k] is None:
                    out.append(None)
                    continue
                x0, y0, x1, y1 = cand[idx[k]]['box']
                # (Its baseline: the foot of its first words' letters, each
                # word's own ink falling off most sharply under it, the
                # median of them; a word box no taller than a line's, so
                # never one of two lines the OCR drew as one.)
                feet = []
                for wd in cand[idx[k]].get('words', []):
                    a0, b0, a1, b1 = wd['box']
                    # (Not a word the OCR read with a bracket or a brace's
                    # curl in it: its ink falls under the line.)
                    if sum(ch.isalpha() for ch in wd['t']) < 2 or b1 - b0 > 1.3 * pitch_px or a1 - a0 < 12 \
                            or any(ch in wd['t'] for ch in ')]}|({['):
                        continue
                    top, bot = max(0, b0 - 3), min(ink.shape[0] - 1, b1 + 4)
                    pr = ink[top:bot, max(0, a0):a1].mean(axis=1)
                    if len(pr) < 6:
                        continue
                    dd = pr[1:] - pr[:-1]
                    feet.append(top + int(np.argmin(dd)) + 1)
                    if len(feet) == 3:
                        break
                if not feet:
                    # (Or its short words, a letter and a stop: J. Wood.)
                    for wd in cand[idx[k]].get('words', []):
                        a0, b0, a1, b1 = wd['box']
                        if not any(ch.isalpha() for ch in wd['t']) or any(ch in wd['t'] for ch in ')]}|({[') \
                                or b1 - b0 > 1.3 * pitch_px or a1 - a0 < 5:
                            continue
                        top, bot = max(0, b0 - 3), min(ink.shape[0] - 1, b1 + 4)
                        pr = ink[top:bot, max(0, a0):a1].mean(axis=1)
                        if len(pr) >= 6:
                            feet.append(top + int(np.argmin(pr[1:] - pr[:-1])) + 1)
                if feet:
                    base = int(np.median(feet))
                else:
                    base = y1 - 6
                prev = base
                out.append({'base': round(to_y(base), 2), 'left': round(to_x(x0), 2), 'right': round(to_x(x1), 2),
                            'ocr': cand[idx[k]]['ocr'][:40], 'box': [x0, y0, x1, y1]})
            # (A line measured on the one before it, two OCR boxes over one
            # another: taken as missed, set between its neighbours.)
            for k in range(1, len(out)):
                if out[k] and out[k - 1] and out[k]['base'] - out[k - 1]['base'] < 4:
                    nxt = next((out[j] for j in range(k + 1, len(out)) if out[j]), None)
                    if nxt and 8 < nxt['base'] - out[k - 1]['base'] < 20:
                        out[k] = dict(out[k], base=round((out[k - 1]['base'] + nxt['base']) / 2, 2), guess=True)
                    else:
                        out[k] = None
            # (A line the OCR missed: a pitch from its neighbours.)
            for k in range(len(out)):
                if out[k] is None:
                    prev = next((out[j]['base'] + (k - j) * PITCH for j in range(k - 1, -1, -1) if out[j]), None)
                    nxt = next((out[j]['base'] - (j - k) * PITCH for j in range(k + 1, len(out)) if out[j]), None)
                    b = prev if prev is not None else nxt
                    out[k] = {'base': round(b, 2) if b is not None else None, 'left': None, 'right': None, 'guess': True}
            data[str(page)][str(col)] = out
        print(page, {c: len(v) for c, v in data[str(page)].items()}, file=sys.stderr)
    json.dump(data, open(path, 'w'))


if __name__ == '__main__':
    main()
