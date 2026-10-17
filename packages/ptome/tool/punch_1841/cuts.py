"""The cuts on each text page of the scan: in each column (or across the
page), the stretches between the OCR's lines that hold ink but no line
of text, the ink's box in them (on the upright leaf, in pixels), and
whether the column's lines run beside it (a cut the text runs round, a
narrower measure beside it). Written to PUNCH_WORK/cuts.json; each cut's
place among its column's lines for spec.py and gen.py, its box for the
crop (fetch.yml) and its size.

    python3 -I cuts.py [PAGE...]
"""
import json, math, os, sys
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.environ.get('PUNCH_WORK', os.path.expanduser('~/.cache/asciidart-work/print-match/punch'))
sys.path.insert(0, HERE)
import align

PAGES = [int(a) for a in sys.argv[1:]]
# The pages of other kinds: the table set sideways, the plates and their
# blank backs, set by hand.
OTHER = {3, 7, 8, 55, 56, 67, 68}
PT = 72 / 400
RULE = {'verso': 58.8 + 213.5, 'recto': 53.2 + 213.5}
HEAD = 46.0


def main():
    ocr = json.load(open(os.path.join(WORK, 'ocr.json')))
    geo = json.load(open(os.path.join(WORK, 'geometry.json')))
    # (Pages named: theirs found again, the others' kept.)
    path = os.path.join(WORK, 'cuts.json')
    out = json.load(open(path)) if PAGES and os.path.exists(path) else {}
    for page in PAGES or [p for p in list(range(1, 13)) + list(range(49, 73)) if p not in OTHER]:
        leaf = page + 3
        g = geo[str(leaf)]
        ink = np.asarray(Image.open(os.path.join(WORK, 'upright', f'{leaf:04d}.png'))) < 110
        h, w = ink.shape
        lines = align.ocr_lines(ocr, geo, leaf)
        head = g['head'][0] if g['head'] else 470
        rule = g['rule']
        found = []
        for col in (1, 2):
            x0, x1 = (rule - 1200, rule - 8) if col == 1 else (rule + 8, rule + 1200)
            x0, x1 = max(0, x0), min(w, x1)
            mine = sorted((l for l in lines if l['col'] == col), key=lambda l: l['box'][1])
            # (The ink left when each line of text's box is blanked: a
            # cut's, beside lines or between them.)
            rest = ink[:, x0:x1].copy()
            for l in mine:
                a, b = max(0, l['box'][0] - x0 - 6), max(0, l['box'][2] - x0 + 6)
                rest[max(0, l['box'][1] - 6):l['box'][3] + 6, a:b] = False
            rest[:head + 20] = False
            rest[g['paper'][3] - 20:] = False
            dense = np.convolve(rest.mean(axis=1), np.ones(9) / 9, mode='same') > 0.015
            y = 0
            while y < h:
                if dense[y]:
                    e = y
                    gap = 0
                    while e + 1 < h and (dense[e + 1] or gap < 15):
                        gap = 0 if dense[e + 1] else gap + 1
                        e += 1
                    e -= gap
                    if e - y > 60:
                        region = rest[y:e + 1]
                        cols = np.where(np.convolve(region.mean(axis=0), np.ones(9) / 9, mode='same') > 0.01)[0]
                        if len(cols):
                            box = [int(x0 + cols[0]), int(y), int(x0 + cols[-1]), int(e)]
                            # (Lines beside it: the text runs round it.)
                            beside = [l for l in mine if l['box'][1] < e - 10 and l['box'][3] > y + 10]
                            # (The gap between it and the lines beside it, the
                            # side it stands on.)
                            gap, side = None, None
                            if beside:
                                lefts = [l['box'][0] for l in beside]
                                rights = [l['box'][2] for l in beside]
                                if min(lefts) > box[2]:
                                    side, gap = 'left', min(lefts) - box[2]
                                elif max(rights) < box[0]:
                                    side, gap = 'right', box[0] - max(rights)
                            found.append({'col': col, 'box': box, 'beside': len(beside), 'side': side,
                                          'gap': round(gap * PT, 2) if gap is not None else None})
                    y = e
                y += 1
        # (A cut found in both columns at the same rows, across the rule:
        # one cut across the page.)
        merged = []
        for c in sorted(found, key=lambda c: c['box'][1]):
            twin = next((m for m in merged if m['col'] != c['col'] and abs(m['box'][1] - c['box'][1]) < 40
                         and abs(m['box'][3] - c['box'][3]) < 40), None)
            if twin:
                twin['col'] = 'across'
                twin['box'] = [min(twin['box'][0], c['box'][0]), min(twin['box'][1], c['box'][1]),
                               max(twin['box'][2], c['box'][2]), max(twin['box'][3], c['box'][3])]
            else:
                merged.append(c)
        # (Each cut on the PDF's page, scan.py's way, and on the leaf as
        # scanned, turned back, for its crop.)
        side = 'verso' if page % 2 == 0 else 'recto'
        cx, cy = w / 2, h / 2
        a = math.atan(g['lean'])
        for k, c in enumerate(merged):
            x0, y0, x1, y1 = c['box']
            c['id'] = f'cut-{page}-{k + 1}'
            c['pt'] = [round(RULE[side] + (x0 - rule) * PT, 2), round(HEAD + (y0 - head) * PT, 2),
                       round(RULE[side] + (x1 - rule) * PT, 2), round(HEAD + (y1 - head) * PT, 2)]
            corners = []
            for x, y in ((x0, y0), (x1, y0), (x0, y1), (x1, y1)):
                dx, dy = x - cx, y - cy
                corners.append((cx + dx * math.cos(a) + dy * math.sin(a), cy - dx * math.sin(a) + dy * math.cos(a)))
            xs, ys = [p_[0] for p_ in corners], [p_[1] for p_ in corners]
            c['crop'] = [int(min(xs)) - 6, int(min(ys)) - 6, int(max(xs) - min(xs)) + 12, int(max(ys) - min(ys)) + 12]
        out[str(page)] = merged
        print(page, [(c['col'], c['box'], c['beside']) for c in merged])
    json.dump(out, open(os.path.join(WORK, 'cuts.json'), 'w'), indent=0)


main()
