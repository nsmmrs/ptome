"""The running quotes: the printing sets a quotation's every line after
its first with `“` at the measure's left, the line's text after it (as
a letter is quoted, p. 25). Each line whose first mark, at the text's
left edge (its page's lines' first ink, the tenth from the left), stands apart, a
quote's width and a mark's height high in the line (not an initial,
the height of two lines, nor a dash, a stroke),
given its `“`; or such a mark either OCR reads as a quote; and those
quotes.txt names. Writes draft.json again, its lines `quote`.

    python3 -I quotes.py
"""
import json, os, re, sys
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from common import WORK


def read_as_quote(readings, box):
    """Whether an OCR reads the line's first mark as a quote's (`“`,
    `«`, `¢¢`, `<¢`: those its two commas make it read), a mark alone
    before the words."""
    for lines in readings:
        for L in lines:
            if abs((L['b'][1] + L['b'][3]) / 2 - (box[1] + box[3]) / 2) < 15 and L['w']:
                t = L['w'][0]['t']
                if len(L['w']) > 1 and re.fullmatch(r'[“"«<¢©‘’\'*]{1,3}', t) and re.search(r'[“"«<¢©]', t):
                    return True
    return False


def main():
    draft = json.load(open(os.path.join(WORK, 'draft.json')))
    abbyy = json.load(open(os.path.join(WORK, 'ocr2.json')))
    tess = json.load(open(os.path.join(WORK, 'tess.json')))
    n = 0
    for p, v in draft.items():
        ls = [l for l in v['lines'] if l['kind'] != 'head' and l['box'][2] > l['box'][0]]
        if len(ls) < 5:
            continue
        ink = np.asarray(Image.open(os.path.join(WORK, 'png', f"{v['leaf']:04d}.png")).convert('L')) < 110
        # (The text's left edge: its lines' first ink (a quote's, where
        # the OCR's words begin after it), the tenth from the left.)
        def first(l):
            x0, y0, x1, y1 = l['box']
            cols = np.nonzero(ink[y0:y1, max(0, x0 - 70):x0 + 5].sum(axis=0) >= 2)[0]
            return max(0, x0 - 70) + cols[0] if len(cols) else x0
        xs = sorted(first(l) for l in ls)
        left = xs[len(xs) // 10]
        for k, l in enumerate(ls):
            if l.pop('quote', None):
                l['text'] = l['text'].removeprefix('“ ')
            if k and ls[k - 1]['text'].startswith('CHAP.'):
                continue
            x0, y0, x1, y1 = l['box']
            # (The line's first mark: its columns from the text's left,
            # a gap of a few columns (between its two commas) bridged; a space after it.)
            band = ink[y0:y1, max(0, left - 8):left + 70]
            cols = np.nonzero(band.sum(axis=0) >= 2)[0]
            if len(cols) == 0:
                continue
            end = cols[0]
            for c in cols[1:]:
                if c - end > 8:
                    break
                end = c
            after = cols[cols > end]
            # (Close before the OCR's words or their start (a speck far
            # off not one).)
            at = max(0, left - 8)
            if not (8 <= end - cols[0] <= 32 and (len(after) == 0 or after[0] - end >= 10)
                    and x0 - 50 <= at + cols[0] <= x0 + 5):
                continue
            zone = band[:, cols[0]:end + 1]
            read = read_as_quote([abbyy[v['leaf']]['lines'], tess[str(v['leaf'])]['lines']], l['box'])
            # (Its rows: the run of rows with the most of its ink, a
            # speck's aside.)
            per = zone.sum(axis=1)
            runs, cur = [], []
            for y, c in enumerate(per):
                if c:
                    cur.append(y)
                elif cur:
                    runs.append(cur)
                    cur = []
            if cur:
                runs.append(cur)
            run = max(runs, key=lambda r: per[r].sum())
            # (A quote's marks some 4 points tall (10 to 22 pixels), a
            # dash's stroke 2 or less, an initial's running out of the line.)
            # (Its ink from over the line's small letters (the rows where
            # the line's ink is thickest) to not far into them.)
            prof = ink[y0:y1, x0:x1].sum(axis=1)
            thick = np.nonzero(prof > 0.5 * prof.max())[0]
            # (Deeper where it is two marks, its commas, side by side.)
            gaps = np.nonzero(zone.sum(axis=0) == 0)[0]
            two = len(gaps) >= 2
            x = thick[-1] - thick[0]
            high = (read or per[run].sum() >= 0.8 * per.sum() and run[0] > 1 and 10 <= run[-1] - run[0] <= 22
                    and run[0] < thick[0] and run[-1] < thick[0] + (0.8 if two else 0.6) * x) \
                and not l['text'].startswith(('’', '*'))
            if high and not l['text'].startswith('“'):
                l['text'] = '“ ' + l['text']
                l['quote'] = True
                n += 1
    # (The scan read by eye: quotes.txt.)
    for row in open(os.path.join(HERE, 'quotes.txt'), encoding='utf-8'):
        row = row.strip()
        if not row or row.startswith('#'):
            continue
        p, i = row[1:].split(':')
        l = draft[p]['lines'][int(i)]
        if row[0] == '+' and not l.get('quote'):
            l['text'] = '“ ' + l['text']
            l['quote'] = True
            n += 1
        elif row[0] == '-' and l.pop('quote', None):
            l['text'] = l['text'].removeprefix('“ ')
            n -= 1
    json.dump(draft, open(os.path.join(WORK, 'draft.json'), 'w'), indent=0)
    print(n, 'lines with a running quote')


main()
