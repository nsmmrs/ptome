"""Each month's lines and rows on the PDF against the scan's (measure.py's
measure.json): each of the PDF's verse lines against the scan's nearest,
each row against the scan's row of the same day; the lines and rows off
by more than a point listed.

    python3 -I check.py
"""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import measure

PDF = os.path.join(measure.WORK, 'build', 'poor-richard.pdf')
scan = json.load(open(os.path.join(measure.WORK, 'measure.json')))
total = bad = 0
for leaf in measure.MONTHS:
    g = measure.pdf_text(PDF, measure.month_page(PDF, leaf))
    w = scan[str(leaf)]
    verse = [round(a - min(w['verse'], key=lambda b: abs(a - b)), 1) for a in g['verse']]
    rows = [round(a - b, 1) for a, b in zip(g['rows'], w['rows'])]
    off = [x for x in verse + rows if abs(x) > 1]
    total += len(verse) + len(rows)
    bad += len(off)
    print(f"{leaf}: head {g['head'][0] - w['head'][0]:+.1f}; verse {len(g['verse'])}/{len(w['verse'])} "
          f"rows {len(g['rows'])}/{len(w['rows'])}; off >1 pt: {off}")
print(f'{bad} of {total} lines off by more than a point')
