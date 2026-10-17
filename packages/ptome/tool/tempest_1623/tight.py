"""The lines the face sets wider than their column (Poppler's words of a
line past the column's right edge or before its left), each set closer
(adjust.json's `{"tight": n}`, gen.py's `tight<n>`), a tenth of a point
a letter more each round, until none is.

    python3 -I tight.py [ROUNDS]
"""
import json, os, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
ROUNDS = int(sys.argv[1]) if len(sys.argv) > 1 else 6
del sys.argv[1:]
sys.path.insert(0, HERE)
import compare

# The columns' edges on the PDF's page (the look's margins and gap).
EDGES = [(47.7, 294.15), (310.95, 557.4)]
path = os.path.join(HERE, 'adjust.json')


def squeezed(page):
    """The lines of the PDF's [page] whose words the justification has
    run into each other (their gaps under half a point): too wide too."""
    import html, re
    out = subprocess.run(['pdftotext', '-bbox-layout', '-f', str(page), '-l', str(page), compare.PDF, '-'],
                         capture_output=True, text=True, check=True).stdout
    rows = {}
    for m in re.finditer(r'<word xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" yMax="([\d.]+)">', out):
        x0, y0, x1, y1 = map(float, m.groups())
        base = y1 - (y1 - y0) * compare.DESCENT
        rows.setdefault((1 if x0 < compare.SPLIT else 2, round(base)), []).append((x0, x1))
    bad = set()
    for key, ws in rows.items():
        ws.sort()
        # (A word Poppler splits at a combining mark, `heauē s`: one word.)
        gaps = [ws[i + 1][0] - ws[i][1] for i in range(len(ws) - 1) if ws[i][1] - ws[i][0] > 3 and ws[i + 1][1] - ws[i + 1][0] > 3]
        if len(ws) > 3 and gaps and min(gaps) < 0.5:
            bad.add(key)
    return bad
for n in range(ROUNDS):
    subprocess.run([os.path.join(HERE, 'build.sh')], check=True, stdout=subprocess.DEVNULL)
    adjust = json.load(open(path)) if os.path.exists(path) else {}
    fit = json.load(open(os.path.join(compare.WORK, 'fit.json')))
    pdf = compare.pdf_lines()
    found = 0
    for page in range(1, 20):
        if page - 1 >= len(pdf):
            break
        for c in (1, 2):
            spec = [f for f in fit if f['page'] == page and f['col'] == c and isinstance(f['line'], int)]
            for f, p in zip(spec, pdf[page - 1][c - 1]):
                pass
            # (By its words: any line past an edge, and the spec's line it
            # stands for, by its order among the column's lines.)
            lines = pdf[page - 1][c - 1]
            # (The first page's head over its columns: not their lines.)
            if page == 1:
                lines = compare.column_lines(pdf, page, c, spec, compare.first_lines())
            words = squeezed(page)
            for i, p in enumerate(lines):
                lo, hi = EDGES[c - 1]
                if p['right'] > hi + 0.6 or p['left'] < lo - 0.6 or (c, round(p['base'])) in words:
                    if i < len(spec):
                        key = f"{page}/{c}/{spec[i]['line']}"
                        a = adjust.setdefault(key, {})
                        a['tight'] = min(12, a.get('tight', 0) + 1)
                        found += 1
                        print(key, p['text'][:50])
    json.dump(dict(sorted(adjust.items())), open(path, 'w'), indent=0)
    print(f'round {n + 1}: {found} lines too wide')
    if not found:
        break
