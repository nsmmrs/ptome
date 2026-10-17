"""The lines of a page whose spec and OCR readings disagree (letters
alike under 0.85), each with both readings and a crop of the scan's line
(PUNCH_WORK/review/PAGE-N.png), to read against the scan into fixes.txt.

    python3 -I review.py PAGE
"""
import difflib, json, os, re, sys
from PIL import Image

WORK = os.environ.get('PUNCH_WORK', os.path.expanduser('~/.cache/asciidart-work/print-match/punch'))
page = int(sys.argv[1])
d = [p for p in json.load(open(os.path.join(WORK, 'draft.json'))) if p['page'] == page][0]
norm = lambda t: re.sub(r'[^a-z0-9]', '', t.replace('__', '').replace('&amp;', '&').lower())
img = Image.open(os.path.join(WORK, 'upright', f"{d['leaf']:04d}.png"))
os.makedirs(os.path.join(WORK, 'review'), exist_ok=True)
crops = []
for k, l in enumerate(d['lines']):
    if l['kind'] in ('I', 'R'):
        continue
    a = ''.join(('' if (i == 0 or w.get('join')) else ' ') + w['t'] for i, w in enumerate(l['words']))
    r = difflib.SequenceMatcher(None, norm(a), norm(l['ocr']), autojunk=False).ratio() if l['ocr'] else 1
    if r < 0.85:
        x0, y0, x1, y1 = l['box']
        crops.append(img.crop((x0 - 10, y0 - 8, x1 + 10, y1 + 8)))
        print(f"{len(crops)} col {l['col']} y {y0} [{r:.2f}] {l['kind']}\n   spec {a}\n   ocr  {l['ocr']}")
if crops:
    w = max(c.width for c in crops) // 2
    h = sum(c.height // 2 + 6 for c in crops)
    sheet = Image.new('L', (w, h), 255)
    y = 0
    for c in crops:
        sheet.paste(c.resize((c.width // 2, c.height // 2)), (0, y))
        y += c.height // 2 + 6
    sheet.save(os.path.join(WORK, 'review', f'{page}.png'))
