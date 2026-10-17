"""Each frozen component's inks recounted by the present classify (the
colours' split by hue): python3 -I inks.py -> inks.json"""
import json, os, sys
import numpy as np
from PIL import Image
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from seg import SCAN, INKS, classify
SEG = json.load(open(f'{HERE}/seg-frozen.json'))
out = {}
for leaf, p in SEG.items():
    k, _ = classify(np.asarray(Image.open(SCAN % int(leaf)).convert('RGB')))
    rec = out[leaf] = []
    for c in p['comps']:
        x0, y0, x1, y1 = c['box']
        sub = k[y0:y1, x0:x1]
        cnt = np.bincount(sub[sub > 0].ravel(), minlength=5)
        rec.append({name: int(cnt[i + 1]) for i, name in enumerate(INKS)})
json.dump(out, open(f'{HERE}/inks.json', 'w'))
