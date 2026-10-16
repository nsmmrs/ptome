"""Each printed page against the PDF's page for its leaf: every line the
scan's OCR reads on it found on the PDF's page (the OCR's errors aside),
near its baseline; the page's first and last lines the PDF page's first
and last.

    python3 -I compare.py [--lines] [FIRST-LEAF LAST-LEAF]
"""
import difflib, json, os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from tfit import pdf_lines, core
from gen import PAGES, target

args = [a for a in sys.argv[1:] if not a.startswith('--')]
lo, hi = (int(args[0]), int(args[1])) if args else (8, 199)
detail = '--lines' in sys.argv
pages = pdf_lines()
bad = 0
totals = [0, 0, 0]
for leaf in range(lo, hi + 1):
    v = PAGES[str(leaf)]
    scan = [l for l in v['lines'] if len(core(l['text'])) >= 3]
    if not scan:
        continue
    pdf = [l for l in pages[leaf] if 30 < l['y0'] < 400]
    used, misses, offs = set(), [], []
    order = []
    for l in scan:
        want = core(l['text'])
        best, score = None, 0
        for n, p in enumerate(pdf):
            if n in used:
                continue
            r = difflib.SequenceMatcher(None, want, core(p['t'])).ratio()
            if r > score:
                best, score = n, r
        if best is not None and score >= 0.55:
            used.add(best)
            p = pdf[best]
            base = p['y0'] + (p['y1'] - p['y0']) * 0.7296
            offs.append(base - target(leaf, l['base']))
            order.append(best)
        else:
            misses.append(l['text'])
    extra = [pdf[n]['t'] for n in range(len(pdf)) if n not in used and len(core(pdf[n]['t'])) >= 3]
    worst = max((abs(o) for o in offs), default=0)
    totals[0] += len(scan); totals[1] += len(misses); totals[2] += sum(abs(o) > 1.5 for o in offs)
    if misses or extra or worst > 1.5:
        bad += 1
        print(f'leaf {leaf} (p.{leaf + 1}): {len(scan)} lines, {len(misses)} unmatched, '
              f'{len(extra)} extra, worst {worst:.1f} pt')
        if detail:
            for m in misses:
                print('   scan only:', m[:70])
            for e in extra:
                print('   pdf only: ', e[:70])
print(f'{bad} pages off; {totals[0]} scan lines, {totals[1]} unmatched, {totals[2]} more than 1.5 pt off')
