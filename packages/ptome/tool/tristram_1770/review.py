"""Sheets to read the draft's lines against the scan: each line's crop of
its leaf over the draft's text of it, numbered `PAGE:LINE` (the line's
place among the page's lines in draft.json); the flagged lines (`--flagged`),
or those named. Written to TRISTRAM_WORK/review/NN.png and index.txt.

    python3 -I review.py --flagged
    python3 -I review.py PAGE:LINE...
"""
import json, os, sys
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from common import WORK

PER = 18
W, H = 1200, 104


def main():
    draft = json.load(open(os.path.join(WORK, 'draft.json')))
    fixes = {}
    path = os.path.join(HERE, 'fixes.tsv')
    if os.path.exists(path):
        for row in open(path, encoding='utf-8'):
            if row.strip() and not row.startswith('#'):
                k, t = row.rstrip('\n').split('\t', 1)
                fixes[k] = t
    if '--flagged' in sys.argv:
        items = [f'{p}:{i}' for p, v in draft.items() for i, l in enumerate(v['lines'])
                 if l['flag'] and f'{p}:{i}' not in fixes]
    else:
        items = sys.argv[1:]
    font = ImageFont.truetype(os.path.expanduser('~/.local/share/fonts/ptome/LibreCaslonText-Regular.ttf'), 24)
    small = ImageFont.load_default()
    out = os.path.join(WORK, 'review')
    os.makedirs(out, exist_ok=True)
    for f in os.listdir(out):
        os.remove(os.path.join(out, f))
    cache = {}
    for s in range(0, len(items), PER):
        sheet = Image.new('L', (W, H * PER), 255)
        d = ImageDraw.Draw(sheet)
        for q, it in enumerate(items[s:s + PER]):
            p, i = it.rsplit(':', 1)
            v = draft[p]
            l = v['lines'][int(i)]
            leaf = v['leaf']
            if leaf not in cache:
                cache = {leaf: Image.open(os.path.join(WORK, 'png', f'{leaf:04d}.png')).convert('L')}
            x0, y0, x1, y1 = l['box']
            crop = cache[leaf].crop((max(0, x0 - 120), y0 - 8, x1 + 120, y1 + 8))
            crop.thumbnail((W - 70, 64))
            y = q * H
            sheet.paste(crop, (64, y))
            d.text((2, y + 24), it, fill=0, font=small)
            d.text((64, y + 68), fixes.get(it, l['text'])[:110], fill=0, font=font)
            d.line((0, y + H - 2, W, y + H - 2), fill=180)
        sheet.save(os.path.join(out, f'{s // PER:02d}.png'))
    open(os.path.join(out, 'index.txt'), 'w').write('\n'.join(items) + '\n')
    print(len(items), 'lines,', (len(items) + PER - 1) // PER, 'sheets')


main()
