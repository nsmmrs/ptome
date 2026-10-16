"""The index pages' column rules, cut from the scan's page images in
pieces short enough to be straight, the type beside them painted out:
their fetch.yml entries (printed) and their places (index_rules.json)."""
import hashlib, json, os
import numpy as np
from PIL import Image
W = os.environ.get('TEMPLE_WORK', os.path.expanduser('~/.cache/asciidart-work/print-match'))
U = 'https://archive.org/download/bim_early-english-books-1475-1640_the-temple-sacred-poems_herbert-george_1633/page/'
SPANS = {200: (2190, 5450), 201: (760, 5600), 202: (700, 4690)}
out = {}
yml = []
for n, (y0, y1) in SPANS.items():
    a = np.asarray(Image.open(f'{W}/herbert/pagejpg/n{n}.jpg').convert('L')) < 110
    pieces = 1 if n != 201 else 5
    step = (y1 - y0) // pieces
    sha = hashlib.sha256(open(f'{W}/herbert/pagejpg/n{n}.jpg', 'rb').read()).hexdigest()
    out[n] = []
    for k in range(pieces):
        ya, yb = y0 + k * step, y0 + (k + 1) * step if k < pieces - 1 else y1
        seg = a[ya:yb, 1400:2000].mean(0)
        xc = 1400 + int(np.argmax(seg))
        x0 = xc - 22
        sub = a[ya:yb, x0:x0 + 44]
        # (The rule: the columns dark most of the way down; the rest of the
        # ink, type beside it, painted out.)
        cols = sub.mean(0)
        keep = np.nonzero(cols > 0.35 * cols.max())[0]
        blank = []
        if keep[0] > 0:
            blank.append([x0, ya, int(keep[0]) - 1, yb - ya])
        if keep[-1] < 43:
            blank.append([x0 + int(keep[-1]) + 2, ya, 44 - int(keep[-1]) - 2, yb - ya])
        name = f'temple-index-rule-{n}-{k + 1}.png'
        yml.append(f'- name: {name}\n  url: {U}n{n}.jpg\n  sha256: {sha}\n  levels: [40, 200]\n'
                   + (f'  blank: {blank}\n' if blank else '') + f'  crop: [{x0}, {ya}, 44, {yb - ya}]\n')
        out[n].append(dict(name=name, top=ya, height=round((yb - ya) * 72 / 800 * 0.8189, 2)))
json.dump(out, open(f'{W}/her/index_rules.json', 'w'), indent=1)
print(''.join(yml), end='')
