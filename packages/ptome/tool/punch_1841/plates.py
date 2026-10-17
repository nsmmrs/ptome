"""The plates' cuts (pages 7, 55 and 67, each a wood engraving with its
title and its captions): the engraving's box on the upright leaf, the
ink left when the OCR's lines of text are blanked, from the first long
stretch of inky rows under the title to the last over the captions;
added to PUNCH_WORK/cuts.json as `cut-PAGE-1`, its place on the PDF's
page and its crop of the leaf as scanned (cuts.py's). And the plate's
lines of text on the scan (scan.json, scan.py's): the bands of inky rows
over and under the engraving, a rule's thin band left out, each band's
baseline where its ink falls off most sharply, the spec's lines before
its `@cut` the bands over it, those after the bands under it.

    python3 -I plates.py
"""
import json, math, os, sys
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.environ.get('PUNCH_WORK', os.path.expanduser('~/.cache/asciidart-work/print-match/punch'))
sys.path.insert(0, HERE)
import align
from scan import spec_lines


def cut_at(page):
    """How many of the plate's lines of text the spec sets over its
    engraving (before its `@cut`)."""
    n, here = 0, False
    for raw in open(os.path.join(HERE, 'punch.spec'), encoding='utf-8'):
        raw = raw.rstrip('\n')
        if raw.startswith('@page'):
            here = int(raw.split()[1]) == page
        elif here and raw.startswith('@cut'):
            return n
        elif here and raw and not raw.startswith(('@', '#')):
            n += 1
    return n

PLATES = (7, 55, 67)
PT = 72 / 400
RULE = {'verso': 58.8 + 213.5, 'recto': 53.2 + 213.5}
HEAD = 46.0


def main():
    ocr = json.load(open(os.path.join(WORK, 'ocr.json')))
    geo = json.load(open(os.path.join(WORK, 'geometry.json')))
    path = os.path.join(WORK, 'cuts.json')
    cuts = json.load(open(path))
    scan_path = os.path.join(WORK, 'scan.json')
    scan = json.load(open(scan_path))
    for page in PLATES:
        leaf = page + 3
        g = geo[str(leaf)]
        ink = np.asarray(Image.open(os.path.join(WORK, 'upright', f'{leaf:04d}.png'))) < 110
        h, w = ink.shape
        x0p, y0p, x1p, y1p = g['paper']
        # (The page's edges from its outer edge, the gutter's dark in the
        # scan no part of it: the page's width.)
        if page % 2:
            x0p = max(x0p, int(x1p - 530.5 / PT))
        else:
            x1p = min(x1p, int(x0p + 530.5 / PT))
        rest = ink.copy()
        rest[:, :max(x0p, 0) + 150] = False
        rest[:, x1p - 150:] = False
        rest[:y0p + 60] = False
        rest[y1p - 60:] = False
        lines = align.ocr_lines(ocr, geo, leaf)
        for l in lines:
            a0, b0, a1, b1 = l['box']
            # (A line of text: blanked; a box the OCR drew over the
            # engraving, taller than a line, left.)
            if b1 - b0 < 90:
                rest[max(0, b0 - 8):b1 + 8, max(0, a0 - 8):a1 + 8] = False
        rows = np.convolve(rest.mean(axis=1), np.ones(15) / 15, mode='same') > 0.01
        # (The longest stretch of inky rows, gaps of a few lines bridged.)
        best, start, gap = (0, 0), None, 0
        for y in range(h):
            if rows[y]:
                if start is None:
                    start = y
                gap = 0
            elif start is not None:
                gap += 1
                if gap > 60:
                    if y - gap - start > best[1] - best[0]:
                        best = (start, y - gap)
                    start, gap = None, 0
        if start is not None and h - start > best[1] - best[0]:
            best = (start, h - 1)
        y0, y1 = best
        cols = np.where(np.convolve(rest[y0:y1].mean(axis=0), np.ones(9) / 9, mode='same') > 0.004)[0]
        x0, x1 = int(cols[0]), int(cols[-1])
        side = 'verso' if page % 2 == 0 else 'recto'
        rule, head = g['rule'], g['head'][0]
        c = {'id': f'cut-{page}-1', 'col': 1, 'box': [x0, y0, x1, y1], 'beside': 0, 'side': None, 'gap': None,
             'pt': [round(RULE[side] + (x0 - rule) * PT, 2), round(HEAD + (y0 - head) * PT, 2),
                    round(RULE[side] + (x1 - rule) * PT, 2), round(HEAD + (y1 - head) * PT, 2)]}
        cx, cy = w / 2, h / 2
        a = math.atan(g['lean'])
        corners = []
        for x, y in ((x0, y0), (x1, y0), (x0, y1), (x1, y1)):
            dx, dy = x - cx, y - cy
            corners.append((cx + dx * math.cos(a) + dy * math.sin(a), cy - dx * math.sin(a) + dy * math.cos(a)))
        xs, ys = [p[0] for p in corners], [p[1] for p in corners]
        c['crop'] = [int(min(xs)) - 6, int(min(ys)) - 6, int(max(xs) - min(xs)) + 12, int(max(ys) - min(ys)) + 12]
        cuts[str(page)] = [c]
        print(page, c['pt'], c['crop'])
        # (The lines of text over and under the engraving.)
        text = ink.copy()
        text[:, :x0p + 150] = False
        text[:, x1p - 150:] = False
        text[y0 - 10:y1 + 10] = False
        prof = text.mean(axis=1)
        bands, start = [], None
        for y in range(y0p + 60, y1p - 60):
            if prof[y] > 0.004 and start is None:
                start = y
            elif prof[y] <= 0.004 and start is not None:
                if y - start >= 15:
                    bands.append((start, y))
                start = None
        lines = spec_lines()[(page, 1)]
        above = cut_at(page)
        over = [b for b in bands if b[1] < y0][-above:] if above else []
        under = [b for b in bands if b[0] > y1][:len(lines) - above]
        rows = []
        for b0, b1 in over + under:
            d = prof[b0:b1 + 2][1:] - prof[b0:b1 + 2][:-1]
            base = b0 + int(np.argmin(d)) + 1
            cols = np.where(text[b0:b1].any(axis=0))[0]
            rows.append({'base': round(HEAD + (base - head) * PT, 2),
                         'left': round(RULE[side] + (cols[0] - rule) * PT, 2),
                         'right': round(RULE[side] + (cols[-1] - rule) * PT, 2)})
        scan.setdefault(str(page), {})['1'] = rows
        scan[str(page)]['2'] = []
        print(page, [r['base'] for r in rows])
    strips(geo, cuts)
    regions(geo, cuts)
    json.dump(cuts, open(path, 'w'), indent=0)
    json.dump(scan, open(scan_path, 'w'))


# The Royal Rhythmical Alphabet (page 62): each column's stack of small
# cuts, one beside each letter's verse, cut as one strip floated to the
# column's left; its right edge the scan's (in pixels, on the upright
# leaf), short of the letters', its top and bottom the first cut's and
# the last's.
STRIPS = {62: {1: (1045, 840), 2: (2250, 540)}}


def strips(geo, cuts):
    for page, cols in STRIPS.items():
        leaf = page + 3
        g = geo[str(leaf)]
        ink = np.asarray(Image.open(os.path.join(WORK, 'upright', f'{leaf:04d}.png'))) < 110
        h, w = ink.shape
        rule, head = g['rule'], g['head'][0]
        side = 'verso' if page % 2 == 0 else 'recto'
        out = []
        for col, (edge, top) in cols.items():
            x0 = rule - 1230 if col == 1 else rule + 15
            region = ink[top:g['paper'][3] - 150, x0:edge]
            rows = np.where(region.mean(axis=1) > 0.004)[0]
            colsx = np.where(region.mean(axis=0) > 0.002)[0]
            bx0, by0, bx1, by1 = x0 + int(colsx[0]), top + int(rows[0]), x0 + int(colsx[-1]), top + int(rows[-1])
            c = {'id': f'cut-{page}-{col}', 'col': col, 'box': [bx0, by0, bx1, by1], 'beside': 1, 'side': 'left',
                 'gap': None,
                 'pt': [round(RULE[side] + (bx0 - rule) * PT, 2), round(HEAD + (by0 - head) * PT, 2),
                        round(RULE[side] + (bx1 - rule) * PT, 2), round(HEAD + (by1 - head) * PT, 2)]}
            cx, cy = w / 2, h / 2
            a = math.atan(g['lean'])
            corners = []
            for x, y in ((bx0, by0), (bx1, by0), (bx0, by1), (bx1, by1)):
                dx, dy = x - cx, y - cy
                corners.append((cx + dx * math.cos(a) + dy * math.sin(a), cy - dx * math.sin(a) + dy * math.cos(a)))
            xs, ys = [p[0] for p in corners], [p[1] for p in corners]
            c['crop'] = [int(min(xs)) - 6, int(min(ys)) - 6, int(max(xs) - min(xs)) + 12, int(max(ys) - min(ys)) + 12]
            out.append(c)
            print(page, col, c['pt'])
        cuts[str(page)] = out



# A block cut whole from the scan, its words set into it (the cavatina's
# score on page 54, its staves and its words): a column's region of the
# upright leaf, from a height to a height (in points on the PDF's page),
# the ink's box in it; in place of the cuts cuts.py found in it.
REGIONS = {'cut-54-1': (54, 2, 233.0, 460.0)}


def regions(geo, cuts):
    for cid, (page, col, top, bottom) in REGIONS.items():
        leaf = page + 3
        g = geo[str(leaf)]
        ink = np.asarray(Image.open(os.path.join(WORK, 'upright', f'{leaf:04d}.png'))) < 110
        h, w = ink.shape
        rule, head = g['rule'], g['head'][0]
        side = 'verso' if page % 2 == 0 else 'recto'
        y0, y1 = int(head + (top - HEAD) / PT), int(head + (bottom - HEAD) / PT)
        x0, x1 = (rule - 1230, rule - 8) if col == 1 else (rule + 8, min(w, rule + 1230))
        region = ink[y0:y1, x0:x1]
        rows = np.where(region.mean(axis=1) > 0.004)[0]
        cols_ = np.where(region.mean(axis=0) > 0.004)[0]
        box = [x0 + int(cols_[0]), y0 + int(rows[0]), x0 + int(cols_[-1]), y0 + int(rows[-1])]
        c = {'id': cid, 'col': col, 'box': box, 'beside': 0, 'side': None, 'gap': None,
             'pt': [round(RULE[side] + (box[0] - rule) * PT, 2), round(HEAD + (box[1] - head) * PT, 2),
                    round(RULE[side] + (box[2] - rule) * PT, 2), round(HEAD + (box[3] - head) * PT, 2)]}
        cx, cy = w / 2, h / 2
        a = math.atan(g['lean'])
        corners = []
        for x, y in ((box[0], box[1]), (box[2], box[1]), (box[0], box[3]), (box[2], box[3])):
            dx, dy = x - cx, y - cy
            corners.append((cx + dx * math.cos(a) + dy * math.sin(a), cy - dx * math.sin(a) + dy * math.cos(a)))
        xs, ys = [p[0] for p in corners], [p[1] for p in corners]
        c['crop'] = [int(min(xs)) - 6, int(min(ys)) - 6, int(max(xs) - min(xs)) + 12, int(max(ys) - min(ys)) + 12]
        found = cuts.setdefault(str(page), [])
        found[:] = [o for o in found if not (o['col'] == col and o['pt'][1] < bottom and o['pt'][3] > top)] + [c]
        print(page, cid, c['pt'])


main()
