"""A column of the scan in parts, to read the spec against by eye:
TEMPEST_WORK/show/PAGE-COL-PART.png, and the spec's lines for that
column, numbered.

    python3 -I show.py PAGE COL [PARTS]
"""
import os, sys
from PIL import Image
WORK = os.environ.get('TEMPEST_WORK', os.path.expanduser('~/.cache/asciidart-work/print-match/tempest'))
HERE = os.path.dirname(os.path.abspath(__file__))
page, col = int(sys.argv[1]), int(sys.argv[2])
parts = int(sys.argv[3]) if len(sys.argv) > 3 else 3
os.makedirs(os.path.join(WORK, 'show'), exist_ok=True)
im = Image.open(os.path.join(WORK, 'cols', f'{24 + page:04d}-{col}.png'))
h = im.height
for k in range(parts):
    part = im.crop((0, int(h * k / parts) - (30 if k else 0), im.width, int(h * (k + 1) / parts) + 30))
    part = part.resize((int(part.width * 0.8), int(part.height * 0.8)))
    part.save(os.path.join(WORK, 'show', f'{page}-{col}-{k + 1}.png'))
cur_page = cur_col = None
n = 0
for line in open(os.path.join(HERE, 'folio.spec'), encoding='utf-8'):
    line = line.rstrip('\n')
    if line.startswith('@page'):
        cur_page, cur_col = int(line.split()[1]), 0
        continue
    if line == '@column':
        cur_col += 1
        n = 0
        continue
    if cur_page == page and cur_col == col:
        if line.startswith('#') or line.startswith('@'):
            print('     ' + line)
        else:
            n += 1
            print(f'{n:3d}  {line}')
