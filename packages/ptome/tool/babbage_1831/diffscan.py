"""The differences' column on each page's scan: each difference where it
stands (its sub-column, left or right, and its baseline as a row of the
table, 0 the first row, fractions between) and whether a table of its
proportional parts follows it; written to BABBAGE_WORK/diff.json, the
draft diff.spec was read against the scan from.

The differences are the printed logarithms' differences (each one
first where two entries differ by it, in order down the page); the scan
gives only their places: Tesseract reads each half of the column, a
line of large figures holding a difference, a line of small ones under
it starting `1` the first of its parts. A difference it doesn't read is
listed as missing, to be read off the scan by eye.

    python3 -I diffscan.py [PAGE...]
"""
import html, json, os, re, subprocess, sys
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from common import EDGES, FOOT_RULE, HEAD_RULE, WORK
from gen import log7

PAGES = [int(a) for a in sys.argv[1:]] or list(range(6, 26))
PITCH, GAP = 9.9, 4.9
FIRST_BASE = 95.25  # the first row's baseline, the scan's


def row_of(y):
    """A baseline in points to a row of the table (fractional), the gaps
    between fives counted."""
    t = (y - FIRST_BASE)
    i = 0
    while i < 60 and t > (i + 1) * PITCH + (i + 1) // 5 * GAP - PITCH / 2:
        i += 1
    base = i * PITCH + i // 5 * GAP
    return round(i + (t - base) / PITCH, 2)


def differences(page):
    """The page's differences in order: each first where two printed
    logarithms differ by it."""
    first = 1000 + 50 * (page - 6)
    out = []
    prev = log7(10 * first)[0]
    for n in range(10 * first + 1, 10 * first + 501):
        v = log7(n)[0]
        d = v - prev
        prev = v
        if not out or d < out[-1]:
            out.append(d)
    return out


def hocr_lines(path):
    s = open(path, encoding='utf-8').read()
    out = []
    for m in re.finditer(r"class='ocr_line'[^>]*title=\"bbox (\d+) (\d+) (\d+) (\d+)[^\"]*\"(.*?)</span>\s*</span>", s, re.S):
        words = re.findall(r"class='ocrx_word'[^>]*>(.*?)</span>", m.group(5) + '</span>', re.S)
        text = ' '.join(html.unescape(re.sub('<[^>]+>', '', w)) for w in words).strip()
        out.append((tuple(map(int, m.groups()[:4])), text))
    return out


def main():
    frames = json.load(open(os.path.join(WORK, 'frame.json')))
    path = os.path.join(WORK, 'diff.json')
    data = json.load(open(path)) if os.path.exists(path) else {}
    os.makedirs(os.path.join(WORK, 'diff'), exist_ok=True)
    for page in PAGES:
        n = page + 24
        f = frames[str(n)]
        k = (f['foot'] - f['head']) / (FOOT_RULE - HEAD_RULE)
        img = Image.open(os.path.join(WORK, 'upright', f'n{n}.png'))
        x0 = int(f['thick'] + (EDGES[13] + 1.2) * k)
        x1 = int(f['thick'] + (EDGES[14] + 2) * k)
        y0, y1 = int(f['head'] + 2 * k), int(f['foot'] + 40 * k)
        mid = (x0 + x1) // 2
        to_y = lambda y: HEAD_RULE + (y - f['head']) / k
        expect = differences(page)
        cands = []
        for side, (a, b) in (('left', (x0, mid)), ('right', (mid, x1))):
            base = os.path.join(WORK, 'diff', f'n{n}-{side}')
            img.crop((a, y0, b, y1)).save(base + '.png')
            subprocess.run(['tesseract', base + '.png', base, '--psm', '6', '-c', 'tessedit_char_whitelist=0123456789', 'hocr'],
                           check=True, capture_output=True)
            lines = hocr_lines(base + '.hocr')
            for i, ((lx0, ly0, lx1, ly1), text) in enumerate(lines):
                # (A difference: three large figures, a line of their own
                # (or beside a part's figures); its baseline its figures'
                # tops and their height, 6.7 points.)
                if ly1 - ly0 < 5.8 * k:
                    continue
                for d in re.findall(r'(?<!\d)(\d{3})(?!\d)', text):
                    d = int(d)
                    if d in expect:
                        top = to_y(y0 + ly0)
                        nxt = lines[i + 1] if i + 1 < len(lines) else None
                        parts = bool(nxt and nxt[1].replace(' ', '').startswith('1') and nxt[0][1] - ly1 < 14 * k)
                        cands.append({'d': d, 'side': side, 'row': row_of(top + 6.7), 'parts': parts})
        # (In order: each difference lower than the one before; of two
        # readings of one, the one in order.)
        found = {}
        last = -2.0
        for d in expect:
            opts = sorted((c for c in cands if c['d'] == d and c['row'] > last - 0.5), key=lambda c: c['row'])
            if opts:
                found[d] = opts[0]
                last = opts[0]['row']
        missing = [d for d in expect if d not in found]
        data[str(page)] = {'stream': [found[d] for d in expect if d in found], 'missing': missing}
        print(page, ' '.join(f"{v['d']}{v['side'][0]}{v['row']}{'*' if v['parts'] else ''}" for v in data[str(page)]['stream']),
              'missing', missing)
    json.dump(data, open(path, 'w'), indent=1)


if __name__ == '__main__':
    main()
