"""The ink's pieces (all of it, the text's too) in a box of a leaf's scan:
python3 -I inkbox.py LEAF X0 Y0 X1 Y1 [MIN_PX]"""
import os, sys
import numpy as np
from PIL import Image
from scipy import ndimage
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from seg import SCAN, classify
leaf, x0, y0, x1, y1 = (int(v) for v in sys.argv[1:6])
least = int(sys.argv[6]) if len(sys.argv) > 6 else 30
k, _ = classify(np.asarray(Image.open(SCAN % leaf).convert('RGB')))
sub = k[y0:y1, x0:x1]
lab, n = ndimage.label(sub > 0, structure=np.ones((3, 3)))
for i, sl in enumerate(ndimage.find_objects(lab)):
    m = lab[sl] == i + 1
    if m.sum() < least:
        continue
    inks = np.bincount(sub[sl][m], minlength=5)[1:]
    print((x0 + sl[1].start, y0 + sl[0].start, x0 + sl[1].stop, y0 + sl[0].stop), int(m.sum()), 'ybrk', inks.tolist())
