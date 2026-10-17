"""A first tribune.spec from decide.py's draft (draft.json): each page
(`@page N`) its regions (`@region ID KIND`, regions.txt's), each region's
printed lines by their kind, from where they stand in the region:

  `P ` a paragraph's first line (set in), `  ` a line going on, `N ` a
  paragraph's first line not set in, `C ` a centred line, `H ` a head's
  line (taller than the region's text: its height, `H<px> `), `L ` a
  line with its figure flush right (` | ` before it).

A word Tesseract and the OCR read differently, that neither the
transcription nor the vocabulary decides, `⟦so⟧`, to be read off the
scan. Each line's box on the scan: where.json.

    python3 -I spec.py > tribune.spec.draft
"""
import json, os, re, statistics, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from common import WORK
from lines import regions


def edge(pts, side):
    """The region's text edge down the leaf (a leaf leans, a column bows):
    a line through the lines' ends ([side] -1 the left, 1 the right),
    fitted to those nearest the edge, again and again."""
    keep = pts
    a, b = statistics.median(x for x, y in pts), 0.0
    for _ in range(4):
        if len(keep) < 3:
            break
        ys = [y for x, y in keep]
        xs = [x for x, y in keep]
        my, mx = sum(ys) / len(ys), sum(xs) / len(xs)
        den = sum((y - my) ** 2 for y in ys) or 1
        b = sum((y - my) * (x - mx) for x, y in keep) / den
        a = mx - b * my
        res = sorted(side * (x - (a + b * y)) for x, y in pts)
        cut = res[len(res) * 6 // 10]
        keep = [(x, y) for x, y in pts if side * (x - (a + b * y)) >= cut - 6]
    return lambda y: a + b * y


def main():
    draft = json.load(open(os.path.join(WORK, 'draft.json')))
    regs = regions()
    out, where = [], []

    def put(line, page=None, box=None):
        out.append(line)
        where.append([page, box])

    for page in sorted(regs):
        put(f'@page {page}', page)
        for rid, kind, rbox in regs[page]:
            put(f'@region {rid} {kind}', page, list(rbox))
            lines = draft[str(page)].get(rid, [])
            if not lines:
                continue
            heights = sorted(l['box'][3] - l['box'][1] for l in lines)
            body = heights[len(heights) // 3] if heights else 50
            fl = edge([(l['box'][0], (l['box'][1] + l['box'][3]) / 2) for l in lines], -1)
            fr = edge([(l['box'][2], (l['box'][1] + l['box'][3]) / 2) for l in lines], 1)
            for l in lines:
                x0, y0, x1, y1 = l['box']
                left, right = fl((y0 + y1) / 2), fr((y0 + y1) / 2)
                t = re.sub(r'\s+', ' ', l['text']).strip()
                if not t:
                    continue
                h = y1 - y0
                gap_l, gap_r = x0 - left, right - x1
                if t.startswith('!'):
                    cells = [c for c in re.split(r'\s*>?!', t) if c]
                    put('L ' + ' | '.join(c.replace('{nbsp}', '').strip() for c in cells), page, l['box'])
                elif h > 1.45 * body:
                    put(f'H{h} {t}', page, l['box'])
                elif gap_l > 40 and gap_r > 40 and abs(gap_l - gap_r) < 0.25 * (gap_l + gap_r) + 20:
                    put(f'C {t}', page, l['box'])
                elif gap_l > 25:
                    put(f'P {t}', page, l['box'])
                else:
                    put(f'  {t}', page, l['box'])
    json.dump(where, open(os.path.join(WORK, 'where.json'), 'w'))
    print('\n'.join(out))


main()
