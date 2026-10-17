"""Sheets to read lines of the spec against the scan: each line's crop of
its upright leaf over the spec's text of it, numbered by the spec's line
(spec.py's `where.json` places them); written to BCP_WORK/review/NN.png.

    python3 -I review.py SPEC LINE...      (or the line numbers on stdin)
"""
import json, os, sys
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from common import WORK

PER = 16
W, H = 1100, 120


def main():
    spec = open(sys.argv[1], encoding='utf-8').read().split('\n')
    nums = [int(x) for x in (sys.argv[2:] or sys.stdin.read().split())]
    where = json.load(open(os.path.join(WORK, 'where.json')))
    if os.path.basename(sys.argv[1]) == 'bcp.spec':
        # (bcp.spec's lines by the draft's they come from: fixes.py's.)
        origin = json.load(open(os.path.join(WORK, 'origin.json')))
        where = [where[o] if o is not None else [None, None] for o in origin]
    font = ImageFont.truetype(os.path.expanduser('~/.local/share/fonts/ptome/Baskervville-Regular.ttf'), 30)
    small = ImageFont.load_default()
    out = os.path.join(WORK, 'review')
    os.makedirs(out, exist_ok=True)
    for f in os.listdir(out):
        os.remove(os.path.join(out, f))
    images = {}
    for s in range(0, len(nums), PER):
        sheet = Image.new('L', (W, H * PER), 255)
        d = ImageDraw.Draw(sheet)
        for q, n in enumerate(nums[s:s + PER]):
            leaf, box = where[n - 1]
            if leaf is not None and leaf not in images:
                images = {leaf: Image.open(os.path.join(WORK, 'upright', f'{leaf:04d}.png')).convert('L')}
            y = q * H
            if box:
                crop = images[leaf].crop((box[0] - 40, box[1] - 8, box[2] + 40, box[3] + 8))
                crop.thumbnail((W - 70, 70))
                sheet.paste(crop, (60, y))
            d.text((2, y + 25), f'{n}', fill=0, font=small)
            d.text((2, y + 40), f'{leaf}', fill=0, font=small)
            d.text((60, y + 74), spec[n - 1], fill=0, font=font)
            d.line((0, y + H - 2, W, y + H - 2), fill=180)
        sheet.save(os.path.join(out, f'{s // PER:02d}.png'))
    print(len(nums), 'lines,', (len(nums) + PER - 1) // PER, 'sheets')


main()
