"""Each paragraph's line pitch, the scan's (adjust.json's `pitch/KEY`,
gen.py's `p<hundredths>` roles): the least squares slope of its lines'
baselines on the scan (scan.json) against their places, its lines all
measured; a paragraph of fewer than three such lines the page's.

    python3 -I pitch.py
"""
import json, os, statistics, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from common import WORK

PATH = os.path.join(HERE, 'adjust.json')
SMALL = ('R', 'Q')  # (The rubrics in the smaller italic.)


def main():
    fit = json.load(open(os.path.join(WORK, 'fit.json')))
    scan = json.load(open(os.path.join(WORK, 'scan.json')))
    adjust = json.load(open(PATH)) if os.path.exists(PATH) else {}
    blocks = {}
    for f in fit:
        if f.get('key') and f['kind'] not in ('h', 'f'):
            blocks.setdefault(f['key'], []).append(f)
    steps = {}
    pts_of = {}
    for key, lines in blocks.items():
        rows = scan.get(str(lines[0]['page']), [])
        pts = []
        for i, f in enumerate(lines):
            r = rows[f['line'] - 1] if f['line'] - 1 < len(rows) else None
            if r and r.get('base') is not None and not r.get('guess'):
                pts.append((i, r['base']))
        pts_of[key] = pts
        for (i, a), (j, b) in zip(pts, pts[1:]):
            if j == i + 1 and 12 < b - a < 24:
                # (The page's text by its own paragraphs, the rubrics' by
                # all the rubrics', set smaller.)
                group = 'rubric' if lines[0]['kind'] in SMALL else lines[0]['page']
                steps.setdefault(group, []).append(b - a)
    page = {k: statistics.median(v) for k, v in steps.items() if len(v) >= 5}
    n = 0
    for key, lines in blocks.items():
        pts = pts_of[key]
        slope = None
        if len(pts) >= 3:
            xs, ys = [p[0] for p in pts], [p[1] for p in pts]
            mx, my = sum(xs) / len(xs), sum(ys) / len(ys)
            den = sum((x - mx) ** 2 for x in xs)
            if den:
                slope = sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / den
        if slope is None and len(lines) >= 2:
            slope = page.get('rubric' if lines[0]['kind'] in SMALL else lines[0]['page'])
        if slope and 12 < slope < 24:
            adjust[f'pitch/{key}'] = round(slope, 2)
            n += 1
    json.dump(dict(sorted(adjust.items())), open(PATH, 'w'), indent=0)
    print(n, 'paragraphs pitched')


main()
