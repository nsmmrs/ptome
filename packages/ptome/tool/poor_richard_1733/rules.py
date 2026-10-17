"""The rules on each page of the scan: the long dark runs across and
down (the frame, the heading's box, the table's rules), in points from
the page's top left (the scans are 400 ppi, 0.18 pt a pixel).

    python3 -I rules.py [LEAF...]   # PR_WORK/rules.json
"""
import json, os, sys
import numpy as np
from PIL import Image

WORK = os.environ.get('PR_WORK', os.path.expanduser('~/.cache/asciidart-work/print-match/poor-richard'))
PT = 72 / 400
LEAVES = [1, 4, 5, 7] + list(range(9, 21))


def runs(mask, min_len):
    """Each row's longest run of ink, if at least [min_len]: (row, start, end)."""
    out = []
    for y, row in enumerate(mask):
        best = (0, 0)
        start = None
        for x, v in enumerate(np.append(row, False)):
            if v and start is None:
                start = x
            elif not v and start is not None:
                if x - start > best[1] - best[0]:
                    best = (start, x)
                start = None
        if best[1] - best[0] >= min_len:
            out.append((y, best[0], best[1]))
    return out


def group(found):
    """Neighbouring rows of a rule as one rule: its middle, thickness, ends."""
    rules = []
    for y, a, b in found:
        if rules and y - rules[-1]['to'] <= 2:
            r = rules[-1]
            r['to'] = y
            r['a'], r['b'] = min(r['a'], a), max(r['b'], b)
        else:
            rules.append({'from': y, 'to': y, 'a': a, 'b': b})
    return [{'at': round((r['from'] + r['to'] + 1) / 2 * PT, 2), 'width': round((r['to'] - r['from'] + 1) * PT, 2),
             'from': round(r['a'] * PT, 2), 'to': round(r['b'] * PT, 2)} for r in rules]


def leaf(n):
    a = np.asarray(Image.open(os.path.join(WORK, 'png', f'{n:04d}.png')).convert('L'))
    ink = a < 110
    across = group(runs(ink, 400))
    down = group(runs(ink.T, 300))
    return {'size': [round(a.shape[1] * PT, 2), round(a.shape[0] * PT, 2)], 'across': across, 'down': down}


if __name__ == '__main__':
    leaves = [int(x) for x in sys.argv[1:]] or LEAVES
    path = os.path.join(WORK, 'rules.json')
    data = json.load(open(path)) if os.path.exists(path) else {}
    for n in leaves:
        data[str(n)] = leaf(n)
        d = data[str(n)]
        print(n, d['size'], 'across', [(r['at'], r['width'], r['from'], r['to']) for r in d['across']])
        print('   down', [(r['at'], r['width'], r['from'], r['to']) for r in d['down']])
    json.dump(data, open(path, 'w'), indent=0)
