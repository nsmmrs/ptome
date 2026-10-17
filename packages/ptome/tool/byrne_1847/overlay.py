"""Draw seg.json's parts over a leaf: overlay.py LEAF OUT."""
import json, os, sys
from PIL import Image, ImageDraw
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from seg import SCAN, W
S = json.load(open(f'{W}/byrne/seg.json'))
leaf = sys.argv[1]
im = Image.open(SCAN % int(leaf)).convert('RGB')
d = ImageDraw.Draw(im)
p = S[leaf]
for w in p['words']:
    d.rectangle(w['box'], outline=(0, 160, 0), width=3)
for c in p['comps']:
    col = {'yellow': (200, 150, 0), 'red': (255, 0, 255), 'blue': (0, 200, 255), 'black': (0, 0, 0)}[max(c['inks'], key=c['inks'].get)]
    d.rectangle(c['box'], outline=col, width=2)
G = json.load(open(f'{HERE}/groups-frozen.json')).get(leaf)
if G:
    im = Image.open(SCAN % int(leaf)).convert('RGB')
    d = ImageDraw.Draw(im)
    for l in G['lines']:
        d.line([(0, l['base']), (im.width, l['base'])], fill=(0, 200, 0), width=1)
        for it in l['items']:
            col = {'word': (0, 150, 0), 'stop': (0, 0, 255)}.get(it['kind'], (255, 0, 0))
            d.rectangle(it['box'], outline=col, width=3)
    for g in G['diagrams']:
        d.rectangle(g['box'], outline=(160, 0, 160), width=5)
    if G['initial']:
        d.rectangle(G['initial']['box'], outline=(0, 0, 0), width=6)
im.thumbnail((1000, 1310))
im.save(sys.argv[2])
