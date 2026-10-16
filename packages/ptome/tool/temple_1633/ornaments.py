"""The pictures on each leaf of the scan: ink outside the OCR's words, on
the paper, in connected pieces at least a line high or wide; each a
band of ornament, a flower, a factotum initial or a plain initial (a
letter two or three lines high at the text's edge).

    python3 -I ornaments.py -> ornaments.json, ornaments.png (a sheet)
"""
import glob, json, os, sys
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from words import P, lines_of, furniture

W = os.path.join(os.environ.get('TEMPLE_WORK', os.path.expanduser('~/.cache/asciidart-work/print-match')), 'herbert')
D = glob.glob(f'{W}/*_jp2')[0]
NAME = D.split('/')[-1][:-4]
PAPER = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'paper.json')))
PITCH = 135
MATCHED = {}
for _w in json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'placed.json')))['words']:
    _p = _w['place']
    if _p and _p.get('exact'):
        MATCHED.setdefault(_p['leaf'], []).append(_p['box'])
        if _p.get('box2'):
            MATCHED[_p['leaf']].append(_p['box2'])


def components(mask, S=8, grow=3, min_size=110):
    H, Wd = mask.shape[0] // S, mask.shape[1] // S
    cells = mask[:H * S, :Wd * S].reshape(H, S, Wd, S).sum((1, 3)) > 4
    g = cells.copy()
    for _ in range(grow):
        h = g.copy()
        h[1:] |= g[:-1]; h[:-1] |= g[1:]; h[:, 1:] |= g[:, :-1]; h[:, :-1] |= g[:, 1:]
        g = h
    seen = np.zeros_like(g)
    out = []
    for y in range(H):
        for x in range(Wd):
            if g[y, x] and not seen[y, x]:
                st = [(y, x)]; seen[y, x] = True; pts = []
                while st:
                    cy, cx = st.pop(); pts.append((cy, cx))
                    for ny, nx in ((cy + 1, cx), (cy - 1, cx), (cy, cx + 1), (cy, cx - 1)):
                        if 0 <= ny < H and 0 <= nx < Wd and g[ny, nx] and not seen[ny, nx]:
                            seen[ny, nx] = True; st.append((ny, nx))
                ys = [p[0] for p in pts]; xs = [p[1] for p in pts]
                y0, y1, x0, x1 = min(ys) * S, (max(ys) + 1) * S, min(xs) * S, (max(xs) + 1) * S
                if y1 - y0 >= min_size and x1 - x0 >= min_size:
                    sub = mask[y0:y1, x0:x1]
                    yy, xx = np.nonzero(sub)
                    if len(yy):
                        out.append([int(x0 + xx.min()), int(y0 + yy.min()), int(x0 + xx.max()), int(y0 + yy.max())])
    return out


def leaf_pictures(leaf):
    a = np.asarray(Image.open(f'{D}/{NAME}_{leaf:04d}.jp2').convert('L')) < 120
    mask = np.zeros_like(a)
    # (Inside the film's black edges: a column or row mostly black is
    # the film's, not the page's.)
    cols = a.mean(0) < 0.6
    rows = a.mean(1) < 0.6
    xs = np.nonzero(cols)[0]
    ys = np.nonzero(rows)[0]
    x0, x1 = int(xs[0]) + 60, int(xs[-1]) - 60
    y0, y1 = int(ys[0]) + 60, int(ys[-1]) - 60
    mask[y0:y1, x0:x1] = a[y0:y1, x0:x1]
    # (The words matched to the text, and the page's furniture: not the
    # OCR's readings of an ornament as words.)
    ls_ = lines_of(leaf)
    skip = furniture(leaf, ls_)
    boxes = [w['box'] for i, l in enumerate(ls_) if i in skip for w in l['w']]
    boxes += MATCHED.get(leaf, [])
    for box in boxes:
        if True:
            bx0, by0, bx1, by1 = box
            # (A word's box: but a tall one, an initial the OCR read as a
            # letter, kept.)
            if by1 - by0 > 2 * PITCH:
                continue
            mask[max(0, by0 - 10):by1 + 10, max(0, bx0 - 10):bx1 + 10] = False
    comps = components(mask)
    ls = lines_of(leaf)
    lefts = [l['w'][0]['box'][0] for l in ls if len(l['w']) >= 4]
    left = int(np.percentile(lefts, 20)) if lefts else x0
    out = []
    for c in comps:
        w, h = c[2] - c[0], c[3] - c[1]
        dens = a[c[1]:c[3], c[0]:c[2]].mean()
        # (The paper's edge, a shadow along it: long and thin, at the
        # film's edge.)
        if dens > 0.75 or (h > 8 * w) or c[0] <= x0 + 5 or c[2] >= x1 - 5:
            continue
        # (An ornament: large, dense ink; a fragment of a word left by the
        # OCR's box, or a speck, not.)
        if not (w > 1500 or (h > 2.0 * PITCH and w > 1.6 * PITCH and dens > 0.18)
                or (h > 1.6 * PITCH and w > 1.0 * PITCH and dens > 0.30)):
            continue
        if w > 1500:
            kind = 'band'
        elif abs(c[0] - left) < 200 and h < 6 * PITCH and w < 5 * PITCH and h > 3.2 * PITCH:
            kind = 'factotum'
        else:
            kind = 'flower'
        out.append(dict(box=c, kind=kind))
    return out


def main():
    res = {}
    for leaf in range(0, 203):
        res[leaf] = leaf_pictures(leaf)
    json.dump(res, open('ornaments.json', 'w'))
    # (A sheet of every picture, its leaf and kind.)
    tiles = []
    for leaf, cs in res.items():
        if not cs:
            continue
        im = Image.open(f'{D}/{NAME}_{leaf:04d}.jp2').convert('L')
        for c in cs:
            t = im.crop((c['box'][0], c['box'][1], c['box'][2], c['box'][3]))
            t.thumbnail((300, 120))
            tiles.append((leaf, c['kind'], t))
    import collections
    print(len(tiles), collections.Counter(k for _, k, _ in tiles))
    from PIL import ImageDraw
    cols = 6
    rows = (len(tiles) + cols - 1) // cols
    sheet = Image.new('L', (cols * 310, rows * 145), 255)
    d = ImageDraw.Draw(sheet)
    for i, (leaf, kind, t) in enumerate(tiles):
        x, y = (i % cols) * 310, (i // cols) * 145
        sheet.paste(t, (x, y + 18))
        d.text((x, y), f'{leaf} {kind}', fill=0)
    sheet.save('ornaments.png')


if __name__ == '__main__':
    main()
