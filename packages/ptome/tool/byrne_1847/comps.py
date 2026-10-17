"""Each leaf's components (the ink outside the text) numbered on the
page, for text.tsv's {cN+cM} symbols: green a line's symbol's, blue a
diagram's, red neither.

    python3 -I comps.py LEAF... -> rev/comps-LEAF.png
"""
import json, os, sys
from PIL import Image, ImageDraw, ImageFont
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from seg import SCAN, W

SEG = json.load(open(f'{HERE}/seg-frozen.json'))
G = json.load(open(f'{HERE}/groups-frozen.json'))


def inside(c, b, slack=3):
    return c[0] >= b[0] - slack and c[1] >= b[1] - slack and c[2] <= b[2] + slack and c[3] <= b[3] + slack


def owners(leaf):
    """Each component's owner: ('s', line, item), ('d', n) or None."""
    g = G[leaf]
    out = []
    for c in SEG[leaf]['comps']:
        own = None
        for li, l in enumerate(g['lines']):
            for ii, it in enumerate(l['items']):
                if it['kind'] == 'symbol' and inside(c['box'], it['box']):
                    own = ('s', li, ii)
        if own is None:
            for di, d in enumerate(g['diagrams']):
                if inside(c['box'], d['box']):
                    own = ('d', di)
        out.append(own)
    return out


def main():
    font = ImageFont.load_default(size=20)
    for leaf in sys.argv[1:]:
        im = Image.open(SCAN % int(leaf)).convert('RGB')
        mask = Image.open(f'{W}/byrne/masks/rest-{leaf}.png').convert('L')
        faint = Image.blend(im, Image.new('RGB', im.size, (255, 255, 255)), 0.7)
        im = Image.composite(im, faint, mask)
        d = ImageDraw.Draw(im)
        for i, (c, own) in enumerate(zip(SEG[leaf]['comps'], owners(leaf))):
            col = (0, 160, 0) if own and own[0] == 's' else (0, 0, 220) if own else (220, 0, 0)
            b = c['box']
            d.rectangle(b, outline=col, width=1)
            d.text((b[0], b[1] - 18), f'c{i}', fill=col, font=font)
        im.save(f'{W}/byrne/rev/comps-{leaf}.png')


if __name__ == '__main__':
    main()
