"""Each paragraph's line pitch, the scan's (adjust.json's `pitch/KEY`,
gen.py's `p<hundredths>` roles): the least squares slope of its lines'
baselines on the scan (scan.json) against their places, its lines the
OCR read; the volume
sets some pieces solid and some leaded. A paragraph of fewer than four
such lines keeps the look's.

    python3 -I pitch.py
"""
import json, os, statistics

HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.environ.get('PUNCH_WORK', os.path.expanduser('~/.cache/asciidart-work/print-match/punch'))
PATH = os.path.join(HERE, 'adjust.json')


def main():
    fit = json.load(open(os.path.join(WORK, 'fit.json')))
    scan = json.load(open(os.path.join(WORK, 'scan.json')))
    adjust = json.load(open(PATH)) if os.path.exists(PATH) else {}
    blocks = {}
    for f in fit:
        if f.get('key'):
            blocks.setdefault(f['key'], []).append(f)
    n = 0
    # (Each column's pitch for each kind of block, the median step between
    # the lines of its blocks of that kind: a block of fewer than four
    # lines, a verse broken where its lines are set in, a footnote, takes
    # its column's.)
    steps = {}
    for key, lines in blocks.items():
        page, col = str(lines[0]['page']), str(lines[0]['col'])
        rows = scan.get(page, {}).get(col, [])
        for a, b in zip(lines, lines[1:]):
            ra = rows[a['line'] - 1] if isinstance(a['line'], int) and a['line'] - 1 < len(rows) else None
            rb = rows[b['line'] - 1] if isinstance(b['line'], int) and b['line'] - 1 < len(rows) else None
            if ra and rb and not ra.get('guess') and not rb.get('guess') and ra.get('base') and rb.get('base'):
                d = rb['base'] - ra['base']
                if 4 < d < 16:
                    steps.setdefault((page, col, lines[0]['kind']), []).append(d)
    column = {k: statistics.median(v) for k, v in steps.items() if len(v) >= 4}
    for key, lines in blocks.items():
        page, col = str(lines[0]['page']), str(lines[0]['col'])
        rows = scan.get(page, {}).get(col, [])
        bases = []
        for f in lines:
            r = rows[f['line'] - 1] if f['line'] - 1 < len(rows) else None
            bases.append(r['base'] if r and r.get('base') is not None and not r.get('guess') else None)
        # (The least squares line through its lines' baselines against
        # their places in it: the scan's pixels a sixth of a point, the
        # pitch from the whole paragraph.)
        pts = [(i, b) for i, b in enumerate(bases) if b is not None]
        if len(pts) >= 4:
            xs = [i for i, _ in pts]
            ys = [b for _, b in pts]
            mx, my = sum(xs) / len(xs), sum(ys) / len(ys)
            den = sum((x - mx) ** 2 for x in xs)
            if den:
                slope = sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / den
                if 4 < slope < 16:
                    adjust[f'pitch/{key}'] = round(slope, 2)
                    n += 1
                    continue
        # (A verse's long line and its turnovers, every line read: its own
        # pitch, an alphabet's letter's lines leaded apart from the next's.)
        if lines[0]['kind'] == 'v' and len(pts) == len(lines) >= 2:
            step = (pts[-1][1] - pts[0][1]) / (len(pts) - 1)
            if 4 < step < 16:
                adjust[f'pitch/{key}'] = round(step, 2)
                n += 1
                continue
        if len(lines) >= 2 and (page, col, lines[0]['kind']) in column:
            adjust[f'pitch/{key}'] = round(column[(page, col, lines[0]['kind'])], 2)
            n += 1
    json.dump(dict(sorted(adjust.items())), open(PATH, 'w'), indent=0)
    print(n, 'paragraphs pitched')


main()
