"""The front pages' blocks moved to where the facsimile sets them: each
block of text/front.adoc has its own `margin-top`, written in place.

Each page's blocks are taken in order: a block of text is as many
printed lines as its source has (`:source-lines:`), a rule (`'''`) a
rule. On the PDF (built by build.sh): its lines by their words'
baselines (Poppler), the k-th block of text starting at the line its
forerunners' lines leave it; its rules by their ink (the PDF drawn at
400 ppi). On the scan: each block's first line found by its words among
Tesseract's lines (its hOCR), or given in targets.json (`"page/block":
points`: the lines and rules Tesseract doesn't read, measured from the
ink); everything in points from the page's frame's inner corner, the
scan turned upright by its frame (measure.py). Each block moved by how
far it is off, less how far the block before it on its page is; again
until none is off by more than a few tenths of a point.

    python3 -I front.py [ROUNDS] [--report]
"""
import html, json, os, re, statistics, subprocess, sys
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
REPORT = '--report' in sys.argv
ARGS = [a for a in sys.argv[1:] if not a.startswith('--')]
ROUNDS = int(ARGS[0]) if ARGS else 4
del sys.argv[1:]
import hocr, measure
from PIL import Image

FRONT = os.path.join(HERE, '../../test/showcase/poor-richard/text/front.adoc')
PDF = os.path.join(hocr.WORK, 'build', 'poor-richard.pdf')
# The PDF's front pages and their leaves of the scan.
PAGES = {1: 1, 2: 4, 3: 5, 4: 7}
# Each PDF page's frame's inner corner (its images/frame-*.svg).
CORNERS = {1: (45.0, 55.8), 2: (44.9, 60.45), 3: (44.9, 60.45), 4: (44.9, 60.45)}
TARGETS = json.load(open(os.path.join(HERE, 'targets.json')))


def norm(t):
    return re.sub(r'[^0-9a-z]', '', t.lower().replace('ſ', 's')).replace('f', 's')


def blocks():
    """front.adoc's blocks, page by page: each its attribute line's
    index, its kind (`text`, `rule`, `image`), its lines' count and its
    first line's words."""
    lines = open(FRONT, encoding='utf-8').read().split('\n')
    pages, page = {1: []}, 1
    for i, l in enumerate(lines):
        if l == '<<<':
            page += 1
            pages[page] = []
        elif re.match(r'^\[[^\]]*\]$', l) and i + 1 < len(lines) and lines[i + 1] and not lines[i + 1].startswith('['):
            nxt = lines[i + 1]
            if nxt == "'''":
                pages[page].append({'attr': i, 'kind': 'rule'})
            elif nxt.startswith('image::'):
                pages[page].append({'attr': i + 1, 'kind': 'image'})
            elif not nxt.startswith('='):
                n = 0
                while i + 1 + n < len(lines) and lines[i + 1 + n]:
                    n += 1
                text = re.sub(r'\{[a-z]+\}|\[\.[\w-]+\]|[#_]', ' ', nxt)
                pages[page].append({'attr': i, 'kind': 'text', 'lines': n,
                                    'words': [norm(w) for w in text.split() if len(norm(w)) >= 3]})
    return lines, pages


def pdf_lines(page):
    out = subprocess.run(['pdftotext', '-bbox-layout', '-f', str(page), '-l', str(page), PDF, '-'],
                         capture_output=True, text=True, check=True).stdout
    ws = []
    for m in re.finditer(r'<word xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" yMax="([\d.]+)">(.*?)</word>', out):
        x0, y0, x1, y1 = map(float, m.groups()[:4])
        # (Not a drop initial: a letter alone, two lines tall.)
        if len(m.group(5)) == 1 and y1 - y0 > 20 and page != 1:
            continue
        ws.append((html.unescape(m.group(5)), x0, y1 - (y1 - y0) * 260 / 1230, x1))
    lines = []
    for w in sorted(ws, key=lambda w: w[2]):
        if lines and abs(lines[-1][-1][2] - w[2]) < 3:
            lines[-1].append(w)
        else:
            lines.append([w])
    cx, cy = CORNERS[page]
    # (Not the folio under the frame.)
    lines = [l for l in lines if statistics.median(w[2] for w in l) - cy < 530 and not all(w[0].isdigit() for w in l)]
    return [{'base': statistics.median(w[2] for w in l) - cy, 'words': [w[0] for w in sorted(l, key=lambda w: w[1])]}
            for l in lines]


def ink_rules(img, page):
    """The rules across the PDF's page (its ink, drawn at 400 ppi), in
    points from its frame's corner, top to bottom."""
    a = np.asarray(img.convert('L')) < 128
    cx, cy = CORNERS[page]
    # (Across the page, wider than the cut: not its edges.)
    x0, x1 = int((cx + 30) / measure.PT), int((cx + 240) / measure.PT)
    top = int((cy + 2) / measure.PT)
    rows = a[top:, x0:x1].mean(axis=1)
    rules, y = [], 0
    while y < len(rows):
        if rows[y] > 0.9:
            y1 = y
            while y1 + 1 < len(rows) and rows[y1 + 1] > 0.9:
                y1 += 1
            if y1 - y < 12:
                rules.append(round((top + (y + y1 + 1) / 2) * measure.PT - cy, 2))
            y = y1
        y += 1
    return rules


def scan_lines(leaf):
    """Tesseract's lines on [leaf], in points from its frame's inner
    corner, the page turned upright by its frame (measure.py)."""
    img = Image.open(os.path.join(hocr.WORK, 'png', f'{leaf:04d}.png')).convert('L')
    ink, _, k = measure.upright(img)
    left, top = measure.frame(ink)
    h, w = ink.shape
    th = np.arctan(k)

    def up(x, y):
        dx, dy = x - w / 2, y - h / 2
        return ((w / 2 + dx * np.cos(th) - dy * np.sin(th) - left) * hocr.PT,
                (h / 2 + dx * np.sin(th) + dy * np.cos(th) - top) * hocr.PT)
    s = open(os.path.join(hocr.WORK, 'tess', f'{leaf:04d}.hocr'), encoding='utf-8').read()
    out = []
    for m in re.finditer(r"class='ocr_line'[^>]*title=\"bbox (\d+) (\d+) (\d+) (\d+); baseline ([-\d.]+) ([-\d.]+)[^\"]*\"(.*?)</span>\s*</span>", s, re.S):
        x0, y0, x1, y1 = map(int, m.groups()[:4])
        off = float(m.group(6))
        words = [html.unescape(re.sub('<[^>]+>', '', w)) for w in re.findall(r"class='ocrx_word'[^>]*>(.*?)</span>", m.group(7) + '</span>', re.S)]
        _, ly = up(x0, y1 + off)
        out.append({'base': ly, 'words': {norm(w) for w in words if len(norm(w)) >= 3}})
    return out


def margin_of(line):
    m = re.search(r'margin-top=([-\d.]+)pt', line)
    return float(m.group(1)) if m else 0.0


def set_margin(line, value):
    line = re.sub(r',margin-top=[-\d.]+pt', '', line)
    return line if abs(value) < 0.005 else line[:-1] + f',margin-top={value:.2f}pt]'


def round_once(adjust):
    subprocess.run([os.path.join(HERE, 'build.sh')], check=True, stdout=subprocess.DEVNULL)
    lines, pages = blocks()
    worst = 0
    for page, leaf in PAGES.items():
        pl = pdf_lines(page)
        rules = ink_rules(measure.pdf_page(PDF, page), page)
        sl = scan_lines(leaf)
        at, ri, before = 0, 0, None
        for k, b in enumerate(pages[page]):
            key = f'{page}/{k + 1}'
            got = want = None
            label = ''
            if b['kind'] == 'text':
                if at < len(pl):
                    got = pl[at]['base']
                    label = ' '.join(pl[at]['words'])[:40]
                at += b['lines']
                want = TARGETS.get(key)
                if want is None:
                    best = None
                    for s in sl:
                        score = len(set(b['words']) & s['words'])
                        if score and (best is None or score > best[0]):
                            best = (score, s['base'])
                    if best and best[0] >= max(1, 0.5 * len(b['words'])):
                        want = best[1]
            elif b['kind'] == 'rule':
                if ri < len(rules):
                    got = rules[ri]
                ri += 1
                want = TARGETS.get(key)
            if got is None or want is None:
                if REPORT:
                    print(f'  {key} {b["kind"]}: no {"place" if got is None else "target"} {label}')
                continue
            off = got - want
            move = off - (before if before is not None else 0)
            before = off
            worst = max(worst, abs(move))
            if REPORT:
                print(f'  {key} {b["kind"]}: {off:+.2f} (move {move:+.2f})  {label}')
            if adjust and abs(move) > 0.15:
                move = max(-30, min(30, move))
                lines[b['attr']] = set_margin(lines[b['attr']], margin_of(lines[b['attr']]) - move)
    if adjust:
        open(FRONT, 'w', encoding='utf-8').write('\n'.join(lines))
    return worst


if REPORT:
    round_once(False)
else:
    for n in range(ROUNDS):
        worst = round_once(True)
        print(f'round {n + 1}: the most {worst:.2f} pt')
        if worst < 0.3:
            break
