"""Review sheets for a book's open choices: each line's scan with the
choices boxed and numbered, their readings below.

    python3 -I sheets.py BOOK [PER-SHEET]

Writes review/BOOK-NN.png and review/BOOK-index.json (number -> id).
"""
import json, os, sys
from PIL import Image, ImageDraw, ImageFont
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import BOOKS, ROOT

FONT = ImageFont.truetype('/usr/share/fonts/noto/NotoSans-Regular.ttf', 20)
WIDTH = 1300


def main(book, per=14):
    cfg = BOOKS[book]
    choices = json.load(open(f'{ROOT}/choices-{book}.json'))
    pages = json.load(open(f'{ROOT}/{cfg["id"]}.ocr.json'))
    overridden = set()
    dpath = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'decisions', f'{book}.tsv')
    if os.path.exists(dpath):
        for line in open(dpath, encoding='utf-8'):
            if line.startswith('line:'):
                overridden.add(line.split('\t')[0][5:])
    open_ = [c for c in choices if c['how'] is None and c['line'] not in overridden]
    by_line = {}
    for c in open_:
        by_line.setdefault(c['line'], []).append(c)
    order = sorted(by_line, key=lambda l: tuple(int(x) for x in l.split(':')))
    os.makedirs(f'{ROOT}/review', exist_ok=True)
    index = {}
    n = 0
    images = {}
    for s in range(0, len(order), per):
        entries = []
        for lid in order[s:s + per]:
            leaf, i = (int(x) for x in lid.split(':'))
            if leaf not in images:
                images.clear()
                images[leaf] = Image.open(
                    f'{ROOT}/{cfg["id"]}/{cfg["id"]}_jp2/{cfg["id"]}_{leaf:04d}.jp2').convert('RGB')
            img = images[leaf]
            box = pages[leaf]['lines'][i]['b']
            x0, y0, x1, y1 = 0, box[1] - 25, img.width, box[3] + 25
            crop = img.crop((x0, y0, x1, y1)).copy()
            d = ImageDraw.Draw(crop)
            notes = []
            for c in by_line[lid]:
                n += 1
                index[n] = c['id']
                for b in c['boxes'][:6]:
                    if b[1] > box[3] + 60 or b[3] < box[1] - 60:
                        continue
                    d.rectangle((b[0] - 6, b[1] - y0 - 6, b[2] + 6, b[3] - y0 + 6),
                                outline=(220, 0, 0), width=4)
                    d.text((b[0], max(0, b[1] - y0 - 30)), str(n), fill=(220, 0, 0),
                           font=ImageFont.truetype('/usr/share/fonts/noto/NotoSans-Regular.ttf', 36))
                if c['kind'] == 'italic':
                    notes.append(f'{n} italic? SE={c["se"]} scan={c["ocr"]}')
                else:
                    notes.append(f'{n} {c["kind"]}: SE={c["se"]!r}  OCR={c["ocr"]!r}  T={c["reading"]!r}')
            scale = WIDTH / crop.width
            crop = crop.resize((WIDTH, int(crop.height * scale)))
            entries.append((lid, crop, notes))
        H = sum(e[1].height + 26 * (len(e[2]) + 1) + 10 for e in entries)
        sheet = Image.new('RGB', (WIDTH, H), 'white')
        d = ImageDraw.Draw(sheet)
        y = 0
        for lid, crop, notes in entries:
            d.text((4, y), f'line {lid}', fill=(0, 0, 160), font=FONT)
            y += 26
            sheet.paste(crop, (0, y))
            y += crop.height
            for note in notes:
                d.text((8, y), note, fill='black', font=FONT)
                y += 26
            y += 10
        sheet.save(f'{ROOT}/review/{book}-{s // per + 1:02d}.png')
    json.dump(index, open(f'{ROOT}/review/{book}-index.json', 'w'))
    print(len(order), 'lines,', n, 'choices,', (len(order) + per - 1) // per, 'sheets')


if __name__ == '__main__':
    main(sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else 14)
