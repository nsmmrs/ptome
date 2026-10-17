"""The printed lines of each region of the pages (regions.txt), from the
Library of Congress's OCR (alto.json): each word given to the region its
middle falls in, a region's words grouped into lines by their baselines
(words whose boxes share most of their height), each line its box and
its words left to right, the lines top to bottom. Written to
TRIBUNE_WORK/lines.json, by page and region.

    python3 -I lines.py
"""
import json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from common import WORK


def regions():
    """regions.txt: {page: [(id, kind, (x0, y0, x1, y1))]}."""
    out = {}
    for raw in open(os.path.join(HERE, 'regions.txt'), encoding='utf-8'):
        if not raw.strip() or raw.startswith('#'):
            continue
        page, rid, kind, *box = raw.split()
        out.setdefault(int(page), []).append((rid, kind, tuple(map(int, box))))
    return out


def region_of(regs, x, y):
    for rid, kind, (x0, y0, x1, y1) in regs:
        if x0 <= x < x1 and y0 <= y < y1:
            return rid
    return None


def overlap(a, b):
    """How much of the shorter of two boxes' heights they share."""
    top, bottom = max(a[1], b[1]), min(a[3], b[3])
    return max(0, bottom - top) / max(1, min(a[3] - a[1], b[3] - b[1]))


def main():
    alto = json.load(open(os.path.join(WORK, 'alto.json')))
    regs = regions()
    out = {}
    for page, lines in alto.items():
        # (The OCR's lines, each parted where its words fall in two
        # regions; two parts in a region side by side on one baseline, a
        # line the OCR cut in two, one.)
        res = {rid: [] for rid, kind, box in regs[int(page)]}
        for l in lines:
            parts = {}
            for w in l['words']:
                x0, y0, x1, y1 = w['box']
                rid = region_of(regs[int(page)], (x0 + x1) / 2, (y0 + y1) / 2)
                if rid:
                    parts.setdefault(rid, []).append(w)
            for rid, ws in parts.items():
                box = [min(w['box'][0] for w in ws), min(w['box'][1] for w in ws),
                       max(w['box'][2] for w in ws), max(w['box'][3] for w in ws)]
                for r in res[rid]:
                    mid = lambda b: (b[1] + b[3]) / 2
                    if (overlap(r['box'], box) > 0.7 or abs(mid(r['box']) - mid(box)) < 0.25 * (r['box'][3] - r['box'][1])) \
                            and (box[0] > r['box'][2] - 5 or box[2] < r['box'][0] + 5):
                        r['words'] += ws
                        r['box'] = [min(r['box'][0], box[0]), min(r['box'][1], box[1]),
                                    max(r['box'][2], box[2]), max(r['box'][3], box[3])]
                        break
                else:
                    res[rid].append({'box': box, 'words': list(ws)})
        for rid, rows in res.items():
            # (A row the OCR read in a rule or a cut's edge, no word in it:
            # none.)
            rows[:] = [r for r in rows if re.search(r'[A-Za-z0-9]{2}', ''.join(w['t'] for w in r['words']))
                       and r['box'][2] - r['box'][0] > 40]
            for r in rows:
                r['words'].sort(key=lambda w: w['box'][0])
            rows.sort(key=lambda r: (r['box'][1] + r['box'][3]) / 2)
        out[page] = res
    json.dump(out, open(os.path.join(WORK, 'lines.json'), 'w'))
    for page, res in out.items():
        print(page, {rid: len(rows) for rid, rows in res.items()})


if __name__ == "__main__":
    main()
