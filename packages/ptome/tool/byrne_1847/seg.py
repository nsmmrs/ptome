"""Each Book I page of the scan in its parts: the running head; the lines
of text, each its words (the OCR's) and its symbols (the ink outside the
words, by colour) in order along it; the diagrams; the woodcut initial.

    python3 -I seg.py [FIRST LAST] -> seg.json (and rev/seg-NN.png overlays)
"""
import json, os, re, sys
import numpy as np
from PIL import Image, ImageDraw

W = os.environ.get('BYRNE_WORK', os.path.expanduser('~/.cache/asciidart-work/print-match'))
SCAN = f'{W}/byrne/firstsixbooksofe00byrn_jp2/firstsixbooksofe00byrn_%04d.jp2'
OCR = json.load(open(f'{W}/byrne/ocr.json'))
HERE = os.path.dirname(os.path.abspath(__file__))
# The printing's inks, sampled from the scan.
INKS = {'yellow': (240, 190, 36), 'red': (238, 79, 38), 'blue': (22, 77, 109), 'black': (46, 45, 29)}
# Book I's pages: leaves 35-84, pages 1-50.
LEAVES = range(35, 85)


def classify(a):
    """Each pixel's ink (0 paper, 1 yellow, 2 red, 3 blue, 4 black): by
    its hue against the inks', the page's paper the bright pixels'
    median; the text's ink, a dark grey, black."""
    a = a.astype(np.int32)
    R, G, B = a[..., 0], a[..., 1], a[..., 2]
    lum = R + G + B
    flat = lum.ravel()
    paper = np.median(a.reshape(-1, 3)[flat > np.percentile(flat, 60)], 0)
    k = np.zeros(lum.shape, np.uint8)
    dark = lum < paper.sum() - 200
    red = (R - np.maximum(G, B) > 60) & (R > 140)
    yellow = (R > 150) & (G > 110) & (R - B > 100) & ~red
    blue = (B - R > 25) & (G - R > 15) & (lum < paper.sum() - 60)
    # (Red and yellow by hue: some sheets' yellow an orange, 38°, the
    # red 10-15°, its edge toward the paper's under 30°.)
    warm = red | yellow
    hue = np.degrees(np.arctan2(np.sqrt(3) * (G - B), 2 * R - G - B))
    yellow = warm & (hue >= 30)
    red = warm & (hue < 30)
    k[dark] = 4
    k[yellow] = 1
    k[red] = 2
    k[blue] = 3
    return k, paper


def is_text(t):
    """A word the text sets: letters or digits, or the punctuation around
    them; not the OCR's reading of a symbol (`—`, `=`, `.*.`)."""
    t = t.strip()
    if not t:
        return False
    if re.search(r'[A-Za-z0-9]', t):
        return not re.fullmatch(r'[_\-—–=^~*•.:■]+', t)
    return t in ('(', ')', ',', ';', '.', ':', '),', ').', '(.', '),', ');')


def components(mask, min_px=6):
    from scipy import ndimage
    lab, n = ndimage.label(mask, structure=np.ones((3, 3)))
    objs = ndimage.find_objects(lab)
    out = []
    for i, sl in enumerate(objs):
        if sl is None:
            continue
        ys, xs = sl
        sub = lab[sl] == i + 1
        cnt = int(sub.sum())
        if cnt < min_px:
            continue
        out.append(dict(box=[xs.start, ys.start, xs.stop, ys.stop], px=cnt))
    return out


def leaf_parts(leaf, masks=False):
    a = np.asarray(Image.open(SCAN % leaf).convert('RGB'))
    k, paper = classify(a)
    H, Wd = k.shape
    lines = OCR[leaf]['lines']
    # (The running head: the first line, in the top tenth.)
    head = [l for l in lines if l['b'][3] < 0.1 * H]
    # (A word as tall as two lines: the OCR's reading of a symbol, a
    # circle as `o`.)
    words = [w for l in lines if l not in head for w in l['w']
             if is_text(w['t']) and w['b'][3] - w['b'][1] < 90]
    ink = k > 0
    # (Letters by a looser dark than the symbols': their strokes' edges,
    # which a stricter one breaks into pieces.)
    lum = a.astype(np.int32).sum(2)
    black = ((lum < paper.sum() - 90) & ((k == 0) | (k == 4)))
    # (A word's own ink: the black in its box in pieces a letter high,
    # columns apart; what is in its box but not letters — a symbol's
    # colour, a black line or dots the OCR read with the word — left to
    # the symbols.)
    from scipy import ndimage
    text_mask = np.zeros_like(ink)
    kept = []
    for w in words:
        x0, y0, x1, y1 = w['b']
        x0, y0 = max(0, x0 - 2), max(0, y0 - 2)
        sub = black[y0:y1 + 2, x0:x1 + 2]
        lab, n = ndimage.label(sub, structure=np.ones((3, 3)))
        thick = ndimage.distance_transform_edt(sub)
        letters = np.zeros_like(sub)
        for i, sl in enumerate(ndimage.find_objects(lab)):
            if sl is None:
                continue
            h = sl[0].stop - sl[0].start
            wd = sl[1].stop - sl[1].start
            # (A letter: taller than a dot, not a long thin line, its
            # strokes a type's stems, not a symbol's solid shape.)
            stem = thick[sl][lab[sl] == i + 1].max()
            if h >= 14 and not (wd >= 40 and wd >= 2.5 * h) and stem <= 8.5:
                letters[sl] |= lab[sl] == i + 1
            elif h >= 6 and wd <= 10 and (lab[sl] == i + 1).sum() >= 20:
                # (a stop, a comma, the dot of an i: small, but round)
                letters[sl] |= lab[sl] == i + 1
        ys, xs = np.nonzero(letters)
        if not len(ys):
            continue
        bx0, bx1 = x0 + int(xs.min()), x0 + int(xs.max()) + 1
        by0, by1 = y0 + int(ys.min()), y0 + int(ys.max()) + 1
        # (The letters' ink, and the dark ink about them: their pieces a
        # strict dark breaks off; not a line or a symbol beside them.)
        grown = ndimage.binary_dilation(letters, iterations=4)
        text_mask[y0:y0 + sub.shape[0], x0:x0 + sub.shape[1]] |= grown & sub
        kept.append(dict(w, b=[bx0, by0, bx1, by1]))
    words = kept
    # (Around each letter, its anti-aliased edge.)
    text_mask = ndimage.binary_dilation(text_mask, iterations=2) & (black | (k == 0))
    # (The head's line, its folio too, which the OCR may miss.)
    head_bottom = max([l['b'][3] for l in head], default=int(0.08 * H))
    text_mask[:head_bottom + 12, :] = True
    # (The scan's edges: the film's dark border, the gutter.)
    edge = np.zeros_like(ink)
    edge[:, :40] = edge[:, -40:] = True
    edge[:40, :] = edge[-40:, :] = True
    rest = ink & ~text_mask & ~edge
    comps = components(rest, min_px=6)
    # (The paper's edge, a shadow along it: long and thin, near the scan's
    # side.)
    comps = [c for c in comps if not ((c['box'][3] - c['box'][1]) > 8 * (c['box'][2] - c['box'][0])
                                       and (c['box'][0] < 0.12 * Wd or c['box'][2] > 0.88 * Wd))]
    for c in comps:
        x0, y0, x1, y1 = c['box']
        sub = k[y0:y1, x0:x1]
        cnt = np.bincount(sub[sub > 0].ravel(), minlength=5)
        c['inks'] = {name: int(cnt[i + 1]) for i, name in enumerate(INKS)}
    if masks:
        os.makedirs(f'{W}/byrne/masks', exist_ok=True)
        Image.fromarray(rest).save(f'{W}/byrne/masks/rest-{leaf}.png')
    return dict(leaf=leaf, size=[Wd, H], paper=[float(v) for v in paper],
                head=[dict(text=' '.join(w['t'] for w in l['w']), box=l['b']) for l in head],
                words=[dict(text=w['t'], box=w['b'], conf=w['c']) for w in words],
                comps=comps)


def main():
    if sys.argv[1:2] == ['--masks']:
        # (Each leaf's ink outside the text, as a picture: what its
        # symbols and diagrams are traced from; seg-frozen.json kept.)
        frozen = json.load(open(f'{HERE}/seg-frozen.json'))
        for leaf in LEAVES:
            got = leaf_parts(leaf, masks=True)
            assert [c['box'] for c in got['comps']] == [c['box'] for c in frozen[str(leaf)]['comps']], leaf
            print(leaf, flush=True)
        return
    first, last = (int(sys.argv[1]), int(sys.argv[2])) if len(sys.argv) > 2 else (LEAVES.start, LEAVES.stop - 1)
    out_path = f'{W}/byrne/seg.json'
    out = json.load(open(out_path)) if os.path.exists(out_path) else {}
    for leaf in range(first, last + 1):
        out[str(leaf)] = leaf_parts(leaf)
        print(leaf, len(out[str(leaf)]['words']), len(out[str(leaf)]['comps']), flush=True)
    json.dump(out, open(out_path, 'w'))


if __name__ == '__main__':
    main()
