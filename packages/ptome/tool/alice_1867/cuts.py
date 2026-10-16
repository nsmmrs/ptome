"""Each printed cut's tight box on its leaf (the ink in ABBYY's image
region, the text lines in it left out)."""
import json, os, re, sys
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import BOOKS, ROOT, in_vocab, core


def component(mask, box, cell=24):
    """The box of the drawing that overlaps [box]: the ink connected to
    it on a grid of [cell]-pixel squares (a square inked when enough of
    it is), across gaps of a square."""
    H, W = mask.shape
    gh, gw = H // cell, W // cell
    grid = mask[:gh * cell, :gw * cell].reshape(gh, cell, gw, cell).sum(axis=(1, 3)) > cell
    seen = np.zeros_like(grid)
    stack = [(r, c) for r in range(box[1] // cell, min(gh, box[3] // cell + 1))
             for c in range(box[0] // cell, min(gw, box[2] // cell + 1)) if grid[r, c]]
    for r, c in stack:
        seen[r, c] = True
    while stack:
        r, c = stack.pop()
        for dr in (-2, -1, 0, 1, 2):
            for dc in (-2, -1, 0, 1, 2):
                rr, cc = r + dr, c + dc
                if 0 <= rr < gh and 0 <= cc < gw and grid[rr, cc] and not seen[rr, cc]:
                    seen[rr, cc] = True
                    stack.append((rr, cc))
    rows = np.nonzero(seen.any(1))[0]
    cols = np.nonzero(seen.any(0))[0]
    if len(rows) == 0:
        return box
    # (Within its squares, to the pixel.)
    y0, y1 = rows[0] * cell, (rows[-1] + 1) * cell
    x0, x1 = cols[0] * cell, (cols[-1] + 1) * cell
    sub = mask[y0:y1, x0:x1]
    r = np.nonzero(sub.sum(1) > 3)[0]
    c = np.nonzero(sub.sum(0) > 3)[0]
    return [int(x0 + c[0]), int(y0 + r[0]), int(x0 + c[-1]), int(y0 + r[-1])]


def measure(book, first_number=2):
    cfg = BOOKS[book]
    t = open(f'{ROOT}/dl/{cfg["id"]}_hocr.html', encoding='utf-8').read()
    pages = re.split(r"(?=<div class=['\"]ocr_page)", t)[1:]
    P = json.load(open(f'{ROOT}/{cfg["id"]}.ocr.json'))
    out = []
    n = first_number
    for leaf in range(cfg['first'], cfg['last'] + 1):
        boxes = [list(map(int, re.search(r'bbox (\d+) (\d+) (\d+) (\d+)', m).groups()))
                 for m in re.findall(r'class="ocr_photo" title="([^"]*)"', pages[leaf])]
        for box in boxes:
            img = np.asarray(Image.open(
                f'{ROOT}/{cfg["id"]}/{cfg["id"]}_jp2/{cfg["id"]}_{leaf:04d}.jp2').convert('L')).astype(float)
            mask = img < np.median(img) - 50
            # (The text lines left out, from their first word of the
            # vocabulary to their last: not the specks the OCR read in
            # the cut beside them.)
            for l in P[leaf]['lines']:
                words = [w for w in l['w'] if len(core(w['t'])) >= 2 and (
                    in_vocab(w['t'].strip().strip('"\'()—-,.;:!?*‘’“”'))
                    or (w['c'] or 0) >= 60)]
                if len(words) >= 1 and (len(words) >= 2 or len(l['w']) == 1):
                    # (Left of the first good word, the words close to it:
                    # a divided word's rest, `ing`; not a speck apart.)
                    ws = sorted(l['w'], key=lambda w: w['b'][0])
                    g = min(ws.index(w) for w in words)
                    while g > 0 and ws[g]['b'][0] - ws[g - 1]['b'][2] < 100:
                        g -= 1
                    words = words + [ws[g]]
                    x0 = min(w['b'][0] for w in words)
                    x1 = max(l['b'][2], max(w['b'][2] for w in words))
                    y0, y1 = l['b'][1], l['b'][3]
                    mask[max(0, y0 - 8):y1 + 8, max(0, x0 - 10):x1 + 10] = False
            # (The running head and the signature left out: their lines,
            # not their bands, a chapter's cut reaching up there.)
            H, W = mask.shape
            for l in P[leaf]['lines']:
                x0, y0, x1, y1 = l['b']
                if y1 < 0.1 * H or y0 > 0.93 * H:
                    mask[max(0, y0 - 10):y1 + 10, max(0, x0 - 10):x1 + 10] = False
            tb = component(mask, box)
            # (And the ink in ABBYY's region alone: where the drawing
            # meets the text beside it.)
            sub = mask[box[1]:box[3], box[0]:box[2]]
            rows = np.nonzero(sub.sum(1) > 3)[0]
            cols = np.nonzero(sub.sum(0) > 3)[0]
            inner = [int(box[0] + cols[0]), int(box[1] + rows[0]),
                     int(box[0] + cols[-1]), int(box[1] + rows[-1])]
            out.append(dict(n=n, leaf=leaf, box=tb, inner=inner))
            n += 1
    return out


if __name__ == '__main__':
    book = sys.argv[1]
    res = measure(book)
    json.dump(res, open(f'{ROOT}/cuts-{book}.json', 'w'), indent=0)
    print(len(res), 'cuts')
