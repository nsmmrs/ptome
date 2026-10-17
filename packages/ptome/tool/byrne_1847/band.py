"""A leaf's components and OCR words between two heights, with their
owners: python3 -I band.py LEAF Y0 Y1"""
import json, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from pieces import SEG, G, owners
leaf, y0, y1 = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
own = owners(leaf)
for i, c in enumerate(SEG[leaf]['comps']):
    b = c['box']
    if y0 <= (b[1] + b[3]) / 2 <= y1:
        print(f'c{i}', b, {k: v for k, v in c['inks'].items() if v}, own[i])
for l in G[leaf]['lines']:
    for it in l['items']:
        b = it['box']
        if it['kind'] == 'word' and y0 <= (b[1] + b[3]) / 2 <= y1:
            print('w', l['base'], repr(it['text']), b)
