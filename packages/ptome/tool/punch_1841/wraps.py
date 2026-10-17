"""Where the PDF's lines first part from the spec's in each column: a spec
line set on two lines (too long for the column at the face's width, or
a word the engine divided), listed with the line before.

    python3 -I wraps.py [PAGE...]
"""
import html, json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ARGS = [int(a) for a in sys.argv[1:]]
sys.argv = sys.argv[:1]
sys.path.insert(0, HERE)
import compare
from scan import spec_lines


def norm(t):
    return re.sub(r'[^a-z0-9]', '', html.unescape(t).replace('__', '').replace('{shy}', '').replace('{ls}', '').lower())


lines = spec_lines()
for page in ARGS or sorted({p for p, _ in lines}):
    pdf = compare.pdf_lines(page)
    for c in (1, 2, 3, 4):
        spec = lines.get((page, c), [])
        got = pdf[c]
        for k, (s, g) in enumerate(zip(spec, got)):
            a, b = norm(s), norm(g['text'])
            if not a.startswith(b[:8]) and not b.startswith(a[:8]):
                print(f'{page}/{c}/{k + 1}: spec  {s[:70]}\n        pdf   {g["text"][:70]}')
                break
