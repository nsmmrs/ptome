"""Each line's start against the scan's: the PDF line's left edge from
the text's edge, the scan line's from its leaf's edge, for the lines the
OCR reads well; those more than 3 pt apart."""
import difflib, re, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from tfit import pdf_lines, core
from gen import PAGES, edge_of, PX, local_edge, line_left
from words import lines_of
pages = pdf_lines()
bad = []
for leaf in range(8, 200):
    e = edge_of(leaf)
    if e is None:
        continue
    pdf = [l for l in pages[leaf] if 30 < l['y0'] < 400]
    used = set()
    for l in PAGES[str(leaf)]['lines']:
        want = core(l['text'])
        if len(want) < 12 or not re.match(r"^[A-Z][a-zſ'’]", l['text']):
            continue
        sc = [(difflib.SequenceMatcher(None, want, core(p['t'])).ratio(), n) for n, p in enumerate(pdf) if n not in used]
        if not sc:
            continue
        r, n = max(sc)
        if r < 0.8:
            continue
        used.add(n)
        x = line_left(leaf, l)
        if x is None:
            continue
        dx = (pdf[n]['x0'] - 23.0) - (x - local_edge(leaf, l['base'])) * PX
        if abs(dx) > 5:
            bad.append((leaf + 1, round(dx, 1), l['text'][:40]))
for b in bad:
    print(*b)
print(len(bad), 'lines set in more than 5 pt otherwise than the scan (lines the OCR reads cleanly)')
