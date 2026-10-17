"""Each block's line pitch, the scan's (adjust.json's `pitch/KEY`,
gen.py's `p<hundredths>` roles): the least squares slope of its lines'
baselines on the scan (scan.json) against their places, its lines all
measured; a block of fewer than three such lines its region's.

    python3 -I pitch.py
"""
import json, os, statistics, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from common import WORK

PATH = os.path.join(HERE, 'adjust.json')


def main():
    fit = json.load(open(os.path.join(WORK, 'fit.json')))
    scan = json.load(open(os.path.join(WORK, 'scan.json')))
    adjust = json.load(open(PATH)) if os.path.exists(PATH) else {}
    blocks = {}
    for f in fit:
        if f['kind'] in ('P',):
            blocks.setdefault(f['key'], []).append(f)
    steps, pts_of = {}, {}
    for key, lines in blocks.items():
        rows = scan[str(lines[0]['page'])][lines[0]['region']]
        pts = [(i, rows[f['line'] - 1]['base']) for i, f in enumerate(lines)
               if f['line'] - 1 < len(rows) and not rows[f['line'] - 1].get('guess')]
        pts_of[key] = pts
        for (i, a), (j, b) in zip(pts, pts[1:]):
            if j == i + 1 and 4 < b - a < 30:
                steps.setdefault((lines[0]['page'], lines[0]['region']), []).append(b - a)
    region = {k: statistics.median(v) for k, v in steps.items() if len(v) >= 3}
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
            slope = region.get((lines[0]['page'], lines[0]['region']))
        if slope and 4 < slope < 30:
            adjust[f'pitch/{key}'] = round(slope, 2)
            n += 1
    json.dump(dict(sorted(adjust.items())), open(PATH, 'w'), indent=0)
    print(n, 'blocks pitched')


main()
