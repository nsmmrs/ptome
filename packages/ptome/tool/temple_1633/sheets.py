"""Review sheets for the open choices: each line's crop from the scan,
numbered, the TCP's line (with its proposed filling) and the readings
below. One entry a line: choices on one line together.

    python3 -I sheets.py [PER-SHEET]  -> review/sheet-NN.png, review/index.json
"""
import glob, json, os, sys, textwrap
from PIL import Image, ImageDraw, ImageFont

W = os.path.join(os.environ.get('TEMPLE_WORK', os.path.expanduser('~/.cache/asciidart-work/print-match')), 'herbert')
D = glob.glob(f'{W}/*_jp2')[0]
NAME = D.split('/')[-1][:-4]
S = json.load(open('stream.json'))
C = json.load(open('choices.json'))
FONT = ImageFont.truetype('/usr/share/fonts/noto/NotoSans-Regular.ttf', 22)
WIDTH = 1500
per = int(sys.argv[1]) if len(sys.argv) > 1 else 12
by_line = {}
for c in C:
    if c['open'] or c.get('how') == 'tesseract-ocr':
        by_line.setdefault(c['i'], []).append(c)
order = sorted(by_line)
os.makedirs('review', exist_ok=True)
index = {}
img_cache = {}
n = 0
for s in range(0, len(order), per):
    entries = []
    for i in order[s:s + per]:
        r = S[i]
        n += 1
        index[n] = i
        if 'box' in r and r['box']:
            leaf = r['leaf']
            if leaf not in img_cache:
                img_cache.clear()
                img_cache[leaf] = Image.open(f'{D}/{NAME}_{leaf:04d}.jp2').convert('L')
            x0, y0, x1, y1 = r['box']
            crop = img_cache[leaf].crop((max(0, x0 - 40), max(0, y0 - 30), x1 + 40, y1 + 30))
            scale = min(1.0, (WIDTH - 20) / crop.width, 130 / crop.height)
            crop = crop.resize((int(crop.width * scale), int(crop.height * scale))).convert('RGB')
        else:
            crop = Image.new('RGB', (10, 10), 'white')
        props = [c['value'] for c in by_line[i] if c['value'] != r.get('t')]
        lines = [f'{n}.  TCP: {r.get("t", "")}']
        if props:
            lines.append(f'     proposed: {props[0]}')
        lines.append(f'     OCR: {r.get("ocr", "")}')
        tess = by_line[i][0].get('tess', '')
        lines.append(f'     Tess: {tess}')
        entries.append((crop, lines))
    H = sum(c.height + 28 * len(l) + 16 for c, l in entries)
    sheet = Image.new('RGB', (WIDTH, H), 'white')
    d = ImageDraw.Draw(sheet)
    y = 0
    for crop, lines in entries:
        sheet.paste(crop, (10, y)); y += crop.height + 4
        for k, l in enumerate(lines):
            d.text((10, y), l[:120], fill=(0, 0, 160) if k == 0 else 'black', font=FONT); y += 28
        y += 12
    sheet.save(f'review/sheet-{s // per + 1:02d}.png')
json.dump(index, open('review/index.json', 'w'))
print(len(order), 'lines,', (len(order) + per - 1) // per, 'sheets')
