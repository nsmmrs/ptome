"""Sheets to read lines of a spec against the scan: each line's crop of
the scan over the spec's text of it, numbered by the spec's line
(spec.py's where.json places them; fixes.py's origin.json maps
tribune.spec's lines to the draft's); written to TRIBUNE_WORK/review/.

    python3 -I review.py SPEC LINE...      (or the line numbers on stdin)
"""
import json, os, sys
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from common import WORK, IMAGES

PER = 20
W, H = 1200, 96


def main():
    spec = open(sys.argv[1], encoding='utf-8').read().split('\n')
    nums = [int(x) for x in (sys.argv[2:] or sys.stdin.read().split())]
    where = json.load(open(os.path.join(WORK, 'where.json')))
    if os.path.basename(sys.argv[1]) == 'tribune.spec' and os.path.exists(os.path.join(WORK, 'origin.json')):
        origin = json.load(open(os.path.join(WORK, 'origin.json')))
        where = [where[o] if o is not None else [None, None] for o in origin]
    font = ImageFont.truetype(os.path.expanduser('~/.local/share/fonts/ptome/OldStandardTT-Regular.ttf'), 24)
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
            page, box = where[n - 1]
            y = q * H
            if box:
                if page not in images:
                    images[page] = Image.open(os.path.join(WORK, IMAGES[page] + '.jpg')).convert('L')
                crop = images[page].crop((box[0] - 10, box[1] - 4, box[2] + 10, box[3] + 4))
                crop.thumbnail((W - 60, 62))
                sheet.paste(crop, (50, y))
            d.text((2, y + 20), f'{n}', fill=0, font=small)
            d.text((50, y + 64), spec[n - 1][:110], fill=0, font=font)
            d.line((0, y + H - 2, W, y + H - 2), fill=180)
        sheet.save(os.path.join(out, f'{s // PER:02d}.png'))
    print(len(nums), 'lines,', (len(nums) + PER - 1) // PER, 'sheets')


main()
