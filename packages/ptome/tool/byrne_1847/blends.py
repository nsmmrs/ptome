"""The blends (the comparisons' third panels) of the leaves given, side
by side: python3 -I blends.py OUT LEAF..."""
import os, sys
from PIL import Image
R = os.path.expanduser('~/.cache/asciidart-work/print-match/byrne/rev')
ims = [Image.open(f'{R}/cmp-{l}.png') for l in sys.argv[2:]]
w = ims[0].width // 3
out = Image.new('RGB', (w * len(ims), ims[0].height), 'white')
for i, im in enumerate(ims):
    out.paste(im.crop((2 * w, 0, 3 * w, im.height)), (i * w, 0))
out.save(sys.argv[1])
