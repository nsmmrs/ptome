"""Contact sheets of the words decide.py couldn't decide (`flag`): each
word's crop of the upright leaf, its line round it faint, numbered, the
reading under it; written to BCP_WORK/sheets/NN.png with an index
(sheets/index.tsv: number, leaf, the word's box, the reading) for
readings.tsv, the readings off the scan.

    python3 -I sheets.py
"""
import json, os, sys
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from common import WORK

PER = 40
W, H = 420, 120


def main():
    draft = json.load(open(os.path.join(WORK, 'draft.json')))
    items = []
    for leaf in sorted(draft, key=int):
        for k, l in enumerate(draft[leaf]['lines']):
            for j, w in enumerate(l['words']):
                if w['flag']:
                    items.append((int(leaf), k, j, w, l))
    os.makedirs(os.path.join(WORK, 'sheets'), exist_ok=True)
    font = ImageFont.truetype(os.path.expanduser('~/.local/share/fonts/ptome/Baskervville-Regular.ttf'), 22)
    index = []
    for s in range(0, len(items), PER):
        sheet = Image.new('L', (W * 4, (H + 30) * (PER // 4)), 255)
        d = ImageDraw.Draw(sheet)
        for q, (leaf, k, j, w, l) in enumerate(items[s:s + PER]):
            im = Image.open(os.path.join(WORK, 'upright', f'{leaf:04d}.png')).convert('L')
            x0, y0, x1, y1 = w['box']
            cx = (x0 + x1) // 2
            crop = im.crop((cx - 300, l['box'][1] - 10, cx + 300, l['box'][3] + 10))
            crop.thumbnail((W - 10, H - 10))
            px, py = (q % 4) * W, (q // 4) * (H + 30)
            sheet.paste(crop, (px + 5, py + 5))
            # (The word's place marked under the crop.)
            sc = crop.width / 600
            d.line((px + 5 + (x0 - (cx - 300)) * sc, py + H - 2, px + 5 + (x1 - (cx - 300)) * sc, py + H - 2), fill=0, width=3)
            n = s + q
            d.text((px + 5, py + H + 2), f'{n}: {w["t"]}', fill=0, font=font)
            index.append(f'{n}\t{leaf}\t{x0},{y0}\t{w["t"]}')
        sheet.save(os.path.join(WORK, 'sheets', f'{s // PER:02d}.png'))
    open(os.path.join(WORK, 'sheets', 'index.tsv'), 'w').write('\n'.join(index) + '\n')
    print(len(items), 'words,', (len(items) + PER - 1) // PER, 'sheets')


main()
