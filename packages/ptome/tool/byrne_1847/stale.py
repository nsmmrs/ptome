"""The decided leaves with a picture not yet traced: python3 -I stale.py"""
import json, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from pieces import TEXT, page, picture_name
from seg import W
T = json.load(open(f'{W}/byrne/traced.json')) if os.path.exists(f'{W}/byrne/traced.json') else {}
out = []
for leaf in sorted({k.split(':')[0] for k in TEXT}, key=int):
    p = page(leaf)
    names = {picture_name(leaf, x[1]) for l in p['lines'] for x in l.get('pieces', ()) if x[0] == 'pic'}
    names |= {picture_name(leaf, d) for d in p['diagrams']}
    if not names <= set(T.get(leaf, {})):
        out.append(leaf)
print(' '.join(out))
