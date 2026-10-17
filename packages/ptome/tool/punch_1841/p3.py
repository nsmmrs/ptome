"""Page 3, the Synopsis of Voting, set sideways across the page as a
tree of heads and lists joined by bracket rules: drawn as an SVG, the
page's background (images/synopsis.svg), each line of its text set where
the scan sets it. The leaf turned to read (a quarter clockwise); its
lines and words Tesseract's (`tesseract p3_upright.png p3/ocr -l eng
hocr`, the Internet Archive's OCR having read it upside down), each
line's words the transcription's (text/issue-1.adoc's synopsis, the
OCR's letters found in it by their five-letter runs), its numbers the
OCR's; its baseline where its words' ink falls off most sharply; its
size from its height, its spaces stretched or shrunk to the scan's
width; the rules the long dark runs of the leaf's rows and columns.
Corrections read off the scan in p3-fixes.txt (`OCR TEXT -- TEXT`).

    python3 -I p3.py   # images/synopsis.svg, PUNCH_WORK/p3/lines.json
"""
import html, json, os, re, sys
from collections import Counter
import numpy as np
from PIL import Image
from fontTools.ttLib import TTFont

HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.environ.get('PUNCH_WORK', os.path.expanduser('~/.cache/asciidart-work/print-match/punch'))
SRC = os.path.join(HERE, '..', '..', 'test', 'showcase', 'punch')
PT = 72 / 400
W, H = 676.4, 530.5  # (the page turned: its height across)
FONTS = os.path.expanduser('~/.local/share/fonts/ptome')


def runs(mask, least):
    out, start = [], None
    for i, v in enumerate(mask):
        if v and start is None:
            start = i
        elif not v and start is not None:
            if i - start >= least:
                out.append((start, i))
            start = None
    if start is not None and len(mask) - start >= least:
        out.append((start, len(mask)))
    return out


def hocr_lines():
    """Tesseract's lines: each its box and its words (their boxes and
    text), in the hOCR's order."""
    import xml.etree.ElementTree as ET
    root = ET.parse(os.path.join(WORK, 'p3', 'ocr.hocr')).getroot()
    ns = {'h': 'http://www.w3.org/1999/xhtml'}
    bbox = lambda e: list(map(int, re.search(r'bbox (\d+) (\d+) (\d+) (\d+)', e.get('title')).groups()))
    out = []
    for e in root.iter('{http://www.w3.org/1999/xhtml}span'):
        if e.get('class') not in ('ocr_line', 'ocr_header', 'ocr_caption', 'ocr_textfloat'):
            continue
        words = []
        for wd in e.findall('h:span', ns):
            if wd.get('class') == 'ocrx_word':
                t = ''.join(wd.itertext()).strip()
                if t:
                    words.append((bbox(wd), t))
        if words:
            out.append({'box': bbox(e), 'words': words, 'ocr': ' '.join(t for _, t in words)})
    return out


def transcription():
    """The synopsis as the transcription has it: its text, its letters
    (lower case), each letter's place in the text."""
    lines = open(os.path.join(SRC, 'text', 'issue-1.adoc'), encoding='utf-8').read().split('\n')
    start = max(i for i, l in enumerate(lines) if l.startswith('=== A SYNOPSIS OF VOTING'))
    end = next(i for i in range(start + 1, len(lines)) if lines[i].startswith("'''"))
    text = ' '.join(l.lstrip('* ').replace('[discrete]', '').replace('==== ', '').replace('=== ', '')
                    for l in lines[start:end] if l.strip())
    text = re.sub(r'\s+', ' ', html.unescape(text.replace('&#91;', '[').replace('&#93;', ']')))
    letters, where = [], []
    for i, ch in enumerate(text):
        if ch.isalnum():
            letters.append(ch.lower())
            where.append(i)
    return text, ''.join(letters), where


def letters_of(t):
    return ''.join(ch.lower() for ch in t if ch.isalnum())


def place(ocr, text, letters, where):
    """The transcription's text for an OCR line: the start its five-letter
    runs agree on most, of those whose letters are most like the line's
    (difflib's ratio, at least four fifths, the span's end let run a few
    letters either way); None where none is."""
    import difflib
    ol = letters_of(ocr)
    if len(ol) < 3:
        return None
    votes = Counter()
    k = 5 if len(ol) >= 8 else 3
    for i in range(len(ol) - k + 1):
        gram = ol[i:i + k]
        j = letters.find(gram)
        while j >= 0:
            votes[j - i] += 1
            j = letters.find(gram, j + 1)
    best = None
    for off, n in votes.most_common(40):
        for d0 in (0, 1, -1, 2, -2):
            for d in (0, -1, 1, -2, 2, -3, 3):
                a, b = max(0, off + d0), min(len(letters), off + len(ol) + d)
                if b <= a:
                    continue
                r = difflib.SequenceMatcher(None, ol, letters[a:b], autojunk=False).ratio()
                # (A span that starts and ends with a word, a little the
                # better: the line's words whole.)
                if where[a] == 0 or text[where[a] - 1] == ' ':
                    r += 0.02
                if b == len(letters) or not text[where[b - 1] + 1:where[b - 1] + 2].isalnum():
                    r += 0.02
                if best is None or r > best[0]:
                    best = (r, a, b)
    if best is None or best[0] < 0.82:
        return None
    _, a, b = best
    i0 = where[a]
    # (A word the OCR lost the first letter of, a worn capital: whole.)
    while i0 > 0 and text[i0 - 1].isalnum():
        i0 -= 1
    i1 = where[b - 1] + 1
    while i1 < len(text) and not text[i1].isspace() and not text[i1].isalnum():
        i1 += 1
    return text[i0:i1]


def main():
    up = np.asarray(Image.open(os.path.join(WORK, 'p3_upright.png')).convert('L'))
    ink = up < 110
    h, w = ink.shape
    # (The paper: the bright run of the columns' and rows' medians.)
    colmed = np.median(up[int(h * .3):int(h * .7):4], axis=0)
    rowmed = np.median(up[:, int(w * .3):int(w * .7):4], axis=1)
    px0 = runs(colmed > 110, 50)[0][0]
    py0 = runs(rowmed > 110, 50)[1][0] if runs(rowmed > 110, 50)[0][1] < 200 else runs(rowmed > 110, 50)[0][0]
    to_x = lambda x: (x - px0) * PT
    to_y = lambda y: (y - py0) * PT
    fixes = {}
    path = os.path.join(HERE, 'p3-fixes.txt')
    if os.path.exists(path):
        for raw in open(path, encoding='utf-8'):
            if ' -- ' in raw:
                a, b = raw.rstrip('\n').split(' -- ', 1)
                fixes[a] = b
    text, letters, where = transcription()
    font = TTFont(os.path.join(FONTS, 'OldStandardTT-Regular.ttf'))
    cmap, hmtx, upem = font.getBestCmap(), font['hmtx'], font['head'].unitsPerEm

    def natural(t):
        return sum(hmtx[cmap[ord(c)]][0] / upem if ord(c) in cmap else 0.5 for c in t)

    out, missing = [], []
    lines = []
    queue = hocr_lines()
    while queue:
        l = queue.pop(0)
        if ' || ' in fixes.get(l['ocr'], ''):
            # (A fix in two parts: the line split at its widest gap.)
            ws = l['words']
            k = max(range(1, len(ws)), key=lambda i: ws[i][0][0] - ws[i - 1][0][2])
            for part, text_ in zip((ws[:k], ws[k:]), fixes[l['ocr']].split(' || ')):
                box = [min(b[0] for b, _ in part), min(b[1] for b, _ in part),
                       max(b[2] for b, _ in part), max(b[3] for b, _ in part)]
                ocr_ = ' '.join(t for _, t in part)
                fixes[ocr_] = text_
                lines.append({'box': box, 'words': part, 'ocr': ocr_})
            continue
        # (A line the OCR ran across two blocks side by side, not found
        # whole in the transcription: split where its words part by more
        # than a few spaces, each part a line, looked at again.)
        if l['ocr'] not in fixes and place(l['ocr'], text, letters, where) is None:
            group, parts = [], []
            for wd in l['words'] + [None]:
                if group and (wd is None or wd[0][0] - group[-1][0][2] > 28):
                    box = [min(b[0] for b, _ in group), min(b[1] for b, _ in group),
                           max(b[2] for b, _ in group), max(b[3] for b, _ in group)]
                    parts.append({'box': box, 'words': group, 'ocr': ' '.join(t for _, t in group)})
                    group = []
                if wd is not None:
                    group.append(wd)
            if len(parts) > 1:
                queue[:0] = parts
                continue
        lines.append(l)
    for l in lines:
        x0, y0, x1, y1 = l['box']
        if y1 - y0 < 12:
            continue
        ocr = l['ocr']
        # (A bracket's tick read as a letter, a stray mark: no line.)
        if ocr in fixes and not fixes[ocr].strip() or sum(c.isalpha() for c in ocr) < 2 and ocr not in fixes:
            continue
        if ocr in fixes:
            body = fixes[ocr]
        else:
            body = place(ocr, text, letters, where)
            if body is None:
                body = ocr
                missing.append(ocr)
            # (The list's numbers: the OCR's, the transcription has none.)
            num = re.match(r'^(\d+\.|\d+(st|nd|rd|th)\.)\s', ocr)
            if num and not body.startswith(num.group(1)):
                body = num.group(1) + ' ' + body
            if ocr.rstrip().endswith('-') and not body.endswith('-'):
                body += '-'
            # (The line's last stop, the OCR's, where the span stops short.)
            if ocr.rstrip()[-1:] in '.,;:' and body[-1:].isalnum():
                body += ocr.rstrip()[-1]
        # (Its baseline: the strongest fall of its words' ink.)
        feet = []
        for (a0, b0, a1, b1), t in l['words']:
            pr = ink[max(0, b0 - 3):b1 + 4, a0:a1].mean(axis=1)
            if len(pr) > 6 and sum(c.isalpha() for c in t) >= 2:
                feet.append(max(0, b0 - 3) + int(np.argmin(pr[1:] - pr[:-1])) + 1)
        base = int(np.median(feet)) if feet else y1 - 6
        # (Its size: its tall letters' height over the baseline, capitals
        # and ascenders, three quarters up the words' heights, Old
        # Standard's capitals 0.7 of its em.)
        tops = sorted(base - b0 for (a0, b0, a1, b1), t in l['words'] if b0 < base)
        rise = tops[int(len(tops) * 0.75)] if tops else base - y0
        size = min(14.0, max(4.0, rise * PT / 0.70))
        width = (x1 - x0) * PT
        # (Or no bigger than the line's width allows, its spaces a third of
        # an em: a short line's few tall letters no guide.)
        fit = width / max(natural(body) + body.count(' ') * 0.05, 0.1)
        size = round(min(size, fit * 1.08), 1)
        bold = size > 9
        nat = natural(body) * size
        spaces = body.count(' ')
        # (Its width the scan's: the spaces stretched or shrunk to it, or
        # the size taken down where they would close up.)
        ws = (width - nat) / spaces if spaces else 0
        ls = 0.0
        # (A line the OCR saw only part of: its own spaces.)
        if not 0.8 < width / max(nat, 1) < 1.6:
            ws = 0
        elif spaces and ws < -0.25 * size * 0.25:
            size = round(size * width / (nat - spaces * 0.06 * size), 2)
            ws = (width - natural(body) * size) / spaces
        # (A head letterspaced, VOTING MAY BE: its letters spread, the
        # room over a third of an em a space shared out among them.)
        if ws > 0.6 * size and body.upper() == body:
            gaps = len(body) - 1
            ls = round((width - natural(body) * size - spaces * size / 3) / gaps, 3)
            ws = 0
        out.append({'text': body, 'ocr': ocr, 'x': round(to_x(x0), 2), 'y': round(to_y(base), 2),
                    'size': size, 'ws': round(ws, 3) if abs(ws) > 0.02 else 0, 'ls': ls, 'bold': bold})
    # (The rules: rows and columns of the leaf dark for a long run, a thin
    # band of them.)
    segs = []
    body = ink.copy()
    for horizontal in (True, False):
        a = body if horizontal else body.T
        found = []
        for i in range(a.shape[0]):
            for r0, r1 in runs(a[i], 90 if horizontal else 30):
                found.append((i, r0, r1))
        found.sort()
        merged = []
        for i, r0, r1 in found:
            m = next((m for m in merged if i - m[1] <= 2 and abs(m[2] - r0) < 12 and abs(m[3] - r1) < 12), None)
            if m:
                m[1] = i
            else:
                merged.append([i, i, r0, r1])
        for i0, i1, r0, r1 in merged:
            if i1 - i0 > 8:
                continue  # (not a rule: a band of type)
            mid = (i0 + i1) / 2
            if horizontal:
                segs.append((to_x(r0), to_y(mid), to_x(r1), to_y(mid), (i1 - i0 + 1) * PT))
            else:
                segs.append((to_x(mid), to_y(r0), to_x(mid), to_y(r1), (i1 - i0 + 1) * PT))
    json.dump({'lines': out, 'rules': segs}, open(os.path.join(WORK, 'p3', 'lines.json'), 'w'), indent=0, ensure_ascii=False)
    svg = [f'<svg xmlns="http://www.w3.org/2000/svg" width="530.5pt" height="676.4pt" viewBox="0 0 530.5 676.4">',
           '<!-- Punch, page 3: the Synopsis of Voting, turned a quarter to the left; tool/punch_1841/p3.py. -->',
           f'<g transform="translate(0 {W}) rotate(-90)" fill="#1A1A1A" font-family="Old Standard TT">']
    for x0, y0, x1, y1, sw in segs:
        svg.append(f'<line x1="{x0:.2f}" y1="{y0:.2f}" x2="{x1:.2f}" y2="{y1:.2f}" stroke="#1A1A1A" stroke-width="{max(0.35, sw):.2f}"/>')
    for l in out:
        t = html.escape(l['text'], quote=False)
        t = re.sub(r'__(.+?)__', r'<tspan font-style="italic">\1</tspan>', t)
        attrs = f'x="{l["x"]}" y="{l["y"]}" font-size="{l["size"]}"'
        if l['ws']:
            attrs += f' word-spacing="{l["ws"]}"'
        if l['ls']:
            attrs += f' letter-spacing="{l["ls"]}"'
        if l['bold']:
            attrs += ' font-weight="bold"'
        svg.append(f'<text {attrs}>{t}</text>')
    svg += ['</g>', '</svg>']
    open(os.path.join(SRC, 'images', 'synopsis.svg'), 'w', encoding='utf-8').write('\n'.join(svg) + '\n')
    print(len(out), 'lines;', len(segs), 'rules;', len(missing), 'not found in the transcription')
    for u in missing[:60]:
        print('  ?', u)


main()
