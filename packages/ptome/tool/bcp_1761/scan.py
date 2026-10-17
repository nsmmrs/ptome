"""Each spec line's place on the scan, in the page's points: its
baseline (where its words' own ink falls off most sharply, the median
of its first words') and its ink's left and right ends; the spec's lines
of a page matched to Tesseract's lines of its leaf (tess.json) by their
letters, in order; a line Tesseract missed set a pitch from its
neighbours. The leaf set on the page by its frame of flowers
(common.to_page). Written to BCP_WORK/scan.json.

    python3 -I scan.py [LEAF...]
"""
import difflib, json, os, re, sys
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from common import WORK, to_page

PITCH = 17.31


def norm(t):
    return re.sub(r'[^a-z0-9]', '', re.sub(r'\[[^\]]*\]#+|#+|__|\{[a-z]+\}|[⟦⟧]', '', t).lower().replace('f', 's'))


def spec_lines():
    """bcp.spec's lines by leaf, in order (their text after the kind)."""
    out, leaf = {}, None
    for raw in open(os.path.join(HERE, 'bcp.spec'), encoding='utf-8'):
        raw = raw.rstrip('\n')
        if raw.startswith('@page'):
            leaf = int(raw.split()[1])
            out[leaf] = []
        elif raw and not raw.startswith(('@', '#')) and leaf is not None:
            # (A line's text after its kind: `V+N `, `X ROLE ` the longer
            # kinds; a foot's parts, a catchword after ` @ `, as read.)
            m = re.match(r'^(?:V\+\d+|X \S+) (.*)$', raw)
            out[leaf].append((m.group(1) if m else raw[2:]).replace(' @ ', ' ').replace(' | ', ' '))
    # (The Calendar's months: months.py's lines.)
    import months
    for page in months.pages():
        out[page['leaf']] = months.page_lines(page)
    return out


def match(spec, ocr):
    n, m = len(spec), len(ocr)
    a = [norm(s) for s in spec]
    b = [norm(o['ocr']) for o in ocr]
    score = np.zeros((n + 1, m + 1))
    move = np.zeros((n + 1, m + 1), dtype=int)
    gap = -0.2
    score[1:, 0] = gap * np.arange(1, n + 1)
    score[0, 1:] = gap * np.arange(1, m + 1)
    move[1:, 0], move[0, 1:] = 1, 2
    for i in range(1, n + 1):
        for j in range(1, m + 1):
            sim = difflib.SequenceMatcher(None, a[i - 1], b[j - 1], autojunk=False).ratio() if a[i - 1] and b[j - 1] else 0
            opts = (score[i - 1, j - 1] + sim - 0.4, score[i - 1, j] + gap, score[i, j - 1] + gap)
            k = int(np.argmax(opts))
            score[i, j], move[i, j] = opts[k], k
    out = [None] * n
    i, j = n, m
    while i > 0 and j > 0:
        if move[i, j] == 0:
            out[i - 1] = j - 1
            i, j = i - 1, j - 1
        elif move[i, j] == 1:
            i -= 1
        else:
            j -= 1
    return out


def foot(ink, words, pitch_px):
    feet = []
    for wd in words:
        a0, b0, a1, b1 = wd['box']
        if sum(ch.isalpha() for ch in wd['t']) < 2 or b1 - b0 > 1.6 * pitch_px or a1 - a0 < 12 \
                or any(ch in wd['t'] for ch in ')]}|({['):
            continue
        top, bot = max(0, b0 - 3), min(ink.shape[0] - 1, b1 + 4)
        pr = ink[top:bot, max(0, a0):a1].mean(axis=1)
        if len(pr) < 6:
            continue
        feet.append(top + int(np.argmin(pr[1:] - pr[:-1])) + 1)
        if len(feet) == 4:
            break
    return int(np.median(feet)) if feet else None


def main():
    tess = json.load(open(os.path.join(WORK, 'tess.json')))
    geo = json.load(open(os.path.join(WORK, 'geometry.json')))
    lines = spec_lines()
    path = os.path.join(WORK, 'scan.json')
    data = json.load(open(path)) if os.path.exists(path) else {}
    leaves = [int(a) for a in sys.argv[1:] if a.isdigit()] or sorted(lines)
    import months
    cal = {p['leaf']: p for p in months.pages()}
    cgeo = months.geometry()
    for leaf in leaves:
        if leaf in cal:
            # (A month's page: its lines' baselines from calgeo.py's, its
            # frame's top where months.py sets it.)
            bases, _ = months.scan_baselines(cal[leaf], cgeo[str(leaf)])
            fy = months.place(cgeo[str(leaf)])[1]
            data[str(leaf)] = [{'base': round(fy + b, 2) if b is not None else None, 'left': None, 'right': None}
                               for b in bases]
            continue
        g = geo[str(leaf)]
        tp = to_page(g)
        sy = (g['frame']['outer'][3] - g['frame']['outer'][1]) / 593.97
        pitch_px = PITCH * sy
        ink = np.asarray(Image.open(os.path.join(WORK, 'upright', f'{leaf:04d}.png'))) < 120
        spec = lines.get(leaf, [])
        cand = tess.get(str(leaf), [])
        idx = match(spec, cand)
        out = []
        for k, s in enumerate(spec):
            if idx[k] is None:
                out.append(None)
                continue
            o = cand[idx[k]]
            x0, y0, x1, y1 = o['box']
            base = foot(ink, o['words'], pitch_px)
            if base is None:
                base = y1 - int(0.25 * (y1 - y0))
            left, b = tp(x0, base)
            right, _ = tp(x1, base)
            out.append({'base': round(b, 2), 'left': round(left, 2), 'right': round(right, 2)})
        for k in range(len(out)):
            if out[k] is None:
                prev = next((out[j]['base'] + (k - j) * PITCH for j in range(k - 1, -1, -1) if out[j] and out[j].get('base')), None)
                nxt = next((out[j]['base'] - (j - k) * PITCH for j in range(k + 1, len(out)) if out[j] and out[j].get('base')), None)
                b = prev if prev is not None else nxt
                out[k] = {'base': round(b, 2) if b is not None else None, 'left': None, 'right': None, 'guess': True}
        data[str(leaf)] = out
    json.dump(data, open(path, 'w'))
    print(len(leaves), 'leaves')


if __name__ == '__main__':
    main()
