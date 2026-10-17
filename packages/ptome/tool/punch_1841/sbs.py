"""A page's spec lines beside the PDF's (the page built alone), where they
part: each column's first difference and the lines about it.

    ONLY=PAGE python3 -I sbs.py PAGE
"""
import os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
page = int(sys.argv[1])
sys.argv = sys.argv[:1]
sys.path.insert(0, HERE)
import compare
from scan import spec_lines

L = spec_lines()
pdf = compare.pdf_lines(page)
for c in (1, 2, 3, 4):
    s, p = L.get((page, c), []), pdf[c]
    k = next((i for i in range(max(len(s), len(p)))
              if i >= len(s) or i >= len(p) or (compare.norm(s[i])[:10] != compare.norm(p[i]['text'])[:10]
                                                and compare.norm(s[i]) not in compare.norm(p[i]['text']))), None)
    print(f'COL {c}: {len(s)} spec, {len(p)} PDF' + ('' if k is None else f'; parts at {k + 1}'))
    if k is not None:
        for i in range(max(0, k - 2), min(max(len(s), len(p)), k + 6)):
            a = s[i][:58] if i < len(s) else ''
            b = p[i]['text'][:58] if i < len(p) else ''
            print(f'{i + 1:4d} {a:59s}| {b}')
