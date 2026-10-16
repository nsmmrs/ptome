"""The work's fetched images as tool/showcase.dart writes them (fetch.yml:
crop, levels), from the page scans in herbert/pagejpg, into the staged
copy's images/."""
import os, re, sys
from PIL import Image
import numpy as np
W = os.environ.get('TEMPLE_WORK', os.path.expanduser('~/.cache/asciidart-work/print-match'))
REPO = os.path.join(os.environ.get('TEMPLE_HERBERT', os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'test', 'showcase', 'herbert')))
out = f'{W}/build/herbert/images'
os.makedirs(out, exist_ok=True)
text = open(f'{REPO}/fetch.yml').read()
for item in re.split(r'\n- ', text)[1:]:
    name = re.search(r'name: (\S+)', item)[1]
    n = re.search(r'/page/n(\d+)\.jpg', item)[1]
    crop = [int(v) for v in re.search(r'crop: \[([^\]]*)\]', item)[1].split(',')]
    black, white = [int(v) for v in re.search(r'levels: \[([^\]]*)\]', item)[1].split(',')]
    a = np.asarray(Image.open(f'{W}/herbert/pagejpg/n{n}.jpg').convert('L')).astype(int)
    for m in re.finditer(r'\[(\d+), (\d+), (\d+), (\d+)\]', (re.search(r'blank: \[(.*)\]\n', item) or [None, ''])[1]):
        bx, by, bw, bh = map(int, m.groups())
        a[by:by + bh, bx:bx + bw] = 255
    a = np.clip((a - black) * 255 // (white - black), 0, 255).astype(np.uint8)
    x, y, w, h = crop
    Image.fromarray(a[y:y + h, x:x + w]).save(f'{out}/{name}')
print('staged', len(os.listdir(out)))
