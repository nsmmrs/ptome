"""Each picture of the decided pages (pieces.py) traced from the scan
into SVG, from its components' own ink: an outline for each ink (potrace),
filled in the printing's colours, yellow, red, blue, then black.

    python3 -I trace.py OUT-DIR -> OUT-DIR/l<leaf>-<kind><n>.svg, traced.json
"""
import json, os, re, subprocess, sys, tempfile
import numpy as np
from PIL import Image
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from seg import SCAN, W, classify
from pieces import SEG, page, picture_name, box_of

G = json.load(open(f'{HERE}/groups-frozen.json'))
# The inks, as the existing work draws them (sampled from the scans).
COLOURS = [(1, '#E8AE2B'), (2, '#D2402B'), (3, '#2B5B93'), (4, '#1C1C1C')]


def trace(mask):
    """[mask]'s outline as SVG path data in its pixels (y down)."""
    if not mask.any():
        return ''
    with tempfile.TemporaryDirectory() as t:
        Image.fromarray(np.where(mask, 0, 255).astype(np.uint8)).convert('1').save(f'{t}/m.pbm')
        out = subprocess.run(['potrace', '-b', 'svg', '-r', '72', '-t', '6', '-a', '1.0', '-O', '0.3',
                              '--flat', '-o', '-', f'{t}/m.pbm'], capture_output=True, text=True, check=True).stdout
    paths = re.findall(r'<path d="([^"]*)"', out, re.S)
    tr = re.search(r'transform="([^"]*)"', out)
    return tr[1] if tr else '', ' '.join(p.replace('\n', ' ') for p in paths)


def dehalo(k):
    """Black pixels at a coloured ink's edge (its anti-aliasing, read as
    dark) given to the colour around them."""
    from scipy import ndimage
    k = k.copy()
    black = k == 4
    best = np.zeros(k.shape, np.uint8)
    most = np.zeros(k.shape)
    for ink in (1, 2, 3):
        share = ndimage.uniform_filter((k == ink).astype(float), 7)
        better = share > most
        most[better] = share[better]
        best[better] = ink
    blk = ndimage.uniform_filter(black.astype(float), 7)
    move = black & (most > 0.3) & (blk < 0.55)
    k[move] = best[move]
    return k


def svg(k, box, pad=2):
    x0, y0, x1, y1 = box
    x0, y0 = max(0, x0 - pad), max(0, y0 - pad)
    x1, y1 = min(k.shape[1], x1 + pad), min(k.shape[0], y1 + pad)
    sub = k[y0:y1, x0:x1]
    w, h = x1 - x0, y1 - y0
    body = []
    for ink, colour in COLOURS:
        m = sub == ink
        if ink != 4:
            # (A colour's wash pale in places, read as paper: its small
            # holes filled; a circle's inside, or a hollow figure's, kept.)
            from scipy import ndimage
            holes = ndimage.binary_fill_holes(m) & ~m
            lab, n = ndimage.label(holes)
            if n:
                size = np.bincount(lab.ravel())
                m |= (size[lab] < 3000) & (lab > 0)
        got = trace(m)
        if got and got[1]:
            body.append(f'<g transform="{got[0]}" fill="{colour}" stroke="none"><path d="{got[1]}"/></g>')
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w * 0.24:.2f}pt" height="{h * 0.24:.2f}pt" '
            f'viewBox="0 0 {w} {h}">' + ''.join(body) + '</svg>\n'), [x0, y0, x1, y1]


def labels(leaf):
    """[leaf]'s components as a label picture: each frozen component's
    pixels its index + 1."""
    from scipy import ndimage
    rest = np.asarray(Image.open(f'{W}/byrne/masks/rest-{leaf}.png')) > 0
    lab, _ = ndimage.label(rest, structure=np.ones((3, 3)))
    by_box = {}
    for i, sl in enumerate(ndimage.find_objects(lab)):
        if sl is not None:
            by_box[(sl[1].start, sl[0].start, sl[1].stop, sl[0].stop)] = i + 1
    out = np.zeros(lab.shape, np.int32)
    for ci, c in enumerate(SEG[leaf]['comps']):
        out[lab == by_box[tuple(c['box'])]] = ci + 1
    return out


def main():
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    only = set(sys.argv[2:])
    path = f'{W}/byrne/traced.json'
    record = json.load(open(path)) if os.path.exists(path) else {}
    for leaf in G:
        if only and leaf not in only:
            continue
        a = np.asarray(Image.open(SCAN % int(leaf)).convert('RGB'))
        k, _ = classify(a)
        k = dehalo(k)
        lab = labels(leaf)
        p = page(leaf)
        pics = {}
        for l in p['lines']:
            for piece in l.get('pieces', ()):
                if piece[0] == 'pic':
                    pics[piece[1]] = 2
        for d in p['diagrams']:
            pics[d] = 4
        rec = record[leaf] = {}
        for comps, pad in pics.items():
            name = picture_name(leaf, comps)
            if comps[0] == 'r':
                # (The box closed in on its ink.)
                x0, y0, x1, y1 = box_of(leaf, comps)
                ys, xs = np.nonzero(k[y0:y1, x0:x1])
                b = [x0 + int(xs.min()), y0 + int(ys.min()), x0 + int(xs.max()) + 1, y0 + int(ys.max()) + 1]
                text, box = svg(k, b, pad=1)
            else:
                mask = np.isin(lab, np.array(comps) + 1)
                text, box = svg(np.where(mask, k, 0), box_of(leaf, comps), pad=pad)
            open(f'{out}/{name}', 'w').write(text)
            rec[name] = box
        # (The initial and a line drawn whole: all their ink.)
        whole = []
        if p['initial']:
            whole.append((f'l{leaf}-initial.svg', p['initial']['box']))
        for l in p['lines']:
            if l.get('role') == 'picture':
                whole.append((f'l{leaf}-line{l["base"]}.svg', l['box']))
        for name, b in whole:
            text, box = svg(k, b, pad=2)
            open(f'{out}/{name}', 'w').write(text)
            rec[name] = box
        print(leaf, len(pics), flush=True)
    json.dump(record, open(path, 'w'))


if __name__ == '__main__':
    main()
