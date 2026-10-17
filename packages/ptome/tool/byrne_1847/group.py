"""seg.json's parts as a page's lines, diagrams and initial: each line
its baseline and its items along it (words, symbols, stops), each
symbol and diagram its pieces of ink.

    python3 -I group.py -> groups.json
"""
import json, os, sys
import numpy as np
from PIL import Image
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from seg import SCAN, W, classify

S = json.load(open(f'{W}/byrne/seg.json'))


def overlap(a0, a1, b0, b1):
    return min(a1, b1) - max(a0, b0)


def merge(boxes, near):
    """Boxes merged where [near] says two are one, transitively."""
    groups = [[i] for i in range(len(boxes))]
    bb = [list(b) for b in boxes]
    changed = True
    while changed:
        changed = False
        for i in range(len(bb)):
            if bb[i] is None:
                continue
            for j in range(i + 1, len(bb)):
                if bb[j] is None or not near(bb[i], bb[j]):
                    continue
                bb[i] = [min(bb[i][0], bb[j][0]), min(bb[i][1], bb[j][1]),
                         max(bb[i][2], bb[j][2]), max(bb[i][3], bb[j][3])]
                groups[i] += groups[j]
                bb[j] = None
                changed = True
    return [(b, g) for b, g in zip(bb, groups) if b is not None]


def baseline(k, box):
    """A word's baseline: the bottom of its letters' x-height band."""
    x0, y0, x1, y1 = box
    prof = (k[y0:y1, x0:x1] == 4).sum(1)
    if prof.max() == 0:
        return y1
    band = np.nonzero(prof > 0.35 * prof.max())[0]
    return y0 + int(band[-1])


def leaf(n):
    p = S[str(n)]
    a = np.asarray(Image.open(SCAN % n).convert('RGB'))
    k, _ = classify(a)
    words = [dict(kind='word', text=w['text'], box=w['box'], base=baseline(k, w['box'])) for w in p['words']]
    comps = p['comps']
    # (A symbol's pieces: touching or a few pixels apart, side by side or
    # one over the other.)
    def near(a, b):
        dx = max(a[0] - b[2], b[0] - a[2])
        dy = max(a[1] - b[3], b[1] - a[3])
        # (Dots: a dotted line's, the three of `therefore`, further apart.)
        small = max(a[2] - a[0], a[3] - a[1]) <= 18 or max(b[2] - b[0], b[3] - b[1]) <= 18
        return (dx <= 10 and dy <= 10) or (small and dx <= 20 and dy <= 20)
    groups = []
    for box, idx in merge([c['box'] for c in comps], near):
        inks = {}
        for i in idx:
            for name, v in comps[i]['inks'].items():
                inks[name] = inks.get(name, 0) + v
        groups.append(dict(box=box, inks=inks, px=sum(comps[i]['px'] for i in idx)))
    # (The woodcut initial: a dense black square three or four lines
    # high.)
    initial = None
    for g in groups:
        x0, y0, x1, y1 = g['box']
        w, h = x1 - x0, y1 - y0
        if 140 <= w <= 330 and 140 <= h <= 330 and g['inks'].get('black', 0) > 0.25 * w * h:
            initial = g
    groups = [g for g in groups if g is not initial]
    # (The paper's edge: at the scan's side.)
    Wd = p['size'][0]
    groups = [g for g in groups if not (g['box'][0] > 0.95 * Wd or g['box'][2] < 0.05 * Wd)]
    # (A diagram: very large; a symbol however large sits on a line.)
    diagrams = [g for g in groups if g['box'][3] - g['box'][1] > 420 or g['box'][2] - g['box'][0] > 560]
    rest = [g for g in groups if g not in diagrams]
    # (Lines: the words by their middles; each line's baseline its
    # letters' together.)
    def mid(b):
        return (b[1] + b[3]) / 2
    words.sort(key=lambda w: mid(w['box']))
    lines = []
    for w in words:
        if lines and abs(np.median([mid(x['box']) for x in lines[-1]['items']]) - mid(w['box'])) <= 22:
            lines[-1]['items'].append(w)
        else:
            lines.append(dict(items=[w]))
    for l in lines:
        boxes = [w['box'] for w in l['items']]
        prof = np.zeros(k.shape[0], np.int64)
        for x0, y0, x1, y1 in boxes:
            prof[y0:y1] += (k[y0:y1, x0:x1] == 4).sum(1)
        band = np.nonzero(prof > 0.35 * prof.max())[0]
        l['base'] = int(band[-1]) if len(band) else int(np.median([b[3] for b in boxes]))
    # (A symbol on a line: its middle in the band of the line's letters,
    # where the printing centres them; a stop at the baseline.)
    orphans = []
    for g in rest:
        x0, y0, x1, y1 = g['box']
        mid = (y0 + y1) / 2
        best = None
        for l in lines:
            d = mid - (l['base'] - 14)
            if -45 <= d <= 30 and (best is None or abs(d) < abs(best[0])):
                best = (d, l)
        small = (x1 - x0) <= 16 and (y1 - y0) <= 22
        # (A stop: small, at the baseline, close after a word.)
        after_word = best and any(it['kind'] == 'word' and 0 <= x0 - it['box'][2] <= 14
                                  for it in best[1]['items'])
        if best:
            if small and after_word and abs(y1 - best[1]['base']) <= 8:
                best[1]['items'].append(dict(kind='stop', text='.', box=g['box']))
            elif small and after_word and y0 < best[1]['base'] < y1 and y1 - best[1]['base'] > 6:
                best[1]['items'].append(dict(kind='stop', text=',', box=g['box']))
            elif g['px'] < 40 and (x1 - x0) <= 12:
                pass
            else:
                best[1]['items'].append(dict(kind='symbol', box=g['box'], inks=g['inks']))
        else:
            orphans.append(g)
    # (Black ink a letter high close beside a word: the word's, its box
    # the OCR's short of it.)
    for l in lines:
        for it in list(l['items']):
            if it['kind'] != 'symbol':
                continue
            b = it['box']
            h = b[3] - b[1]
            inks = it['inks']
            if inks.get('black', 0) < 0.9 * max(1, sum(inks.values())) or not (14 <= h <= 50):
                continue
            # (Not a line, not an equals sign: letters.)
            if b[2] - b[0] > 2.5 * h and h < 25:
                continue
            for w in l['items']:
                if w['kind'] == 'word' and (0 <= b[0] - w['box'][2] <= 14 or 0 <= w['box'][0] - b[2] <= 14):
                    w['box'] = [min(w['box'][0], b[0]), min(w['box'][1], b[1]),
                                max(w['box'][2], b[2]), max(w['box'][3], b[3])]
                    l['items'].remove(it)
                    break
    # (Symbols on a line of their own: by their middles.)
    orphans.sort(key=lambda g: (g['box'][1] + g['box'][3]) / 2)
    extra = []
    for g in orphans:
        mid = (g['box'][1] + g['box'][3]) / 2
        if g['px'] < 60:
            continue
        if extra and abs(extra[-1]['mid'] - mid) <= 30:
            extra[-1]['items'].append(dict(kind='symbol', box=g['box'], inks=g['inks']))
        else:
            extra.append(dict(mid=mid, items=[dict(kind='symbol', box=g['box'], inks=g['inks'])]))
    # (A lone large group off the lines: a diagram; one beside others in
    # a row, a line of symbols.)
    keep = []
    for e in extra:
        if len(e['items']) == 1:
            b = e['items'][0]['box']
            if b[3] - b[1] > 200:
                diagrams.append(dict(box=b, inks=e['items'][0]['inks']))
                continue
        keep.append(e)
    extra = keep
    # (Such a line near a diagram and no wider than it: the diagram's.)
    for e in extra:
        boxes = [it['box'] for it in e['items']]
        x0, y0 = min(b[0] for b in boxes), min(b[1] for b in boxes)
        x1, y1 = max(b[2] for b in boxes), max(b[3] for b in boxes)
        host = next((d for d in diagrams if overlap(x0, x1, d['box'][0] - 40, d['box'][2] + 40) > 0
                     and overlap(y0, y1, d['box'][1] - 40, d['box'][3] + 40) > 0), None)
        if host:
            host.setdefault('parts', []).extend(boxes)
            hb = host['box']
            host['box'] = [min(hb[0], x0), min(hb[1], y0), max(hb[2], x1), max(hb[3], y1)]
        else:
            lines.append(dict(base=int(e['mid'] + 14), items=e['items'], symbols_only=True))
    for l in lines:
        l['items'].sort(key=lambda it: it['box'][0])
    lines.sort(key=lambda l: l['base'])
    return dict(lines=lines, diagrams=diagrams, initial=initial, size=p['size'], head=p['head'])


def main():
    out = {}
    for n in map(int, S):
        out[str(n)] = leaf(n)
    json.dump(out, open(f'{W}/byrne/groups.json', 'w'))
    print(len(out), 'leaves')


if __name__ == '__main__':
    main()
