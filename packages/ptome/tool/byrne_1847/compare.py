"""A rendered page beside its scan, both at the page's size, and a
blend (the scan red, the render blue) for registration.

    python3 -I compare.py PDF-PNG LEAF OUT
"""
import json, os, sys
from PIL import Image, ImageChops, ImageOps
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from seg import SCAN
H = json.load(open(f'{HERE}/heads.json'))
S = 72 / 300
PAGE_W, PAGE_H, HEAD_Y = 532.8, 669.6, 28.2


def main():
    png, leaf, out = sys.argv[1], sys.argv[2], sys.argv[3]
    r = Image.open(png).convert('L')
    scale = r.width / PAGE_W          # px per pt in the render
    scan = Image.open(SCAN % int(leaf)).convert('L')
    import gen
    from pieces import page
    cx, hb = gen.head_of(leaf, page(leaf))
    # (The scan placed as gen.py places it: its head's centre the page's
    # centre, its baseline HEAD_Y below the top.)
    f = scale * S
    s = scan.resize((round(scan.width * f), round(scan.height * f)))
    ox = PAGE_W / 2 * scale - cx * f
    oy = HEAD_Y * scale - hb * f
    canvas = Image.new('L', r.size, 255)
    canvas.paste(s, (round(ox), round(oy)))
    blend = Image.merge('RGB', (r, canvas, canvas))
    side = Image.new('RGB', (r.width * 3, r.height), 'white')
    side.paste(canvas.convert('RGB'), (0, 0))
    side.paste(r.convert('RGB'), (r.width, 0))
    side.paste(Image.merge('RGB', (canvas, r, r)), (r.width * 2, 0))
    side.save(out)
    # (In colour too, the scan beside the render.)
    rc = Image.open(png).convert('RGB')
    sc = Image.open(SCAN % int(leaf)).convert('RGB').resize((round(scan.width * f), round(scan.height * f)))
    cc = Image.new('RGB', r.size, 'white')
    cc.paste(sc, (round(ox), round(oy)))
    both = Image.new('RGB', (r.width * 2, r.height), 'white')
    both.paste(cc, (0, 0))
    both.paste(rc, (r.width, 0))
    both.save(out.replace('cmp-', 'cmpc-'))


if __name__ == '__main__':
    main()
