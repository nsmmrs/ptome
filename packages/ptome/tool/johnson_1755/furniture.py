"""The heads over the columns and the foot of each page (the folio, the
signature, the catchword) on the PDF against the scan: each one's
middle and baseline on the scan (Tesseract's boxes; the folio 5, which
it misses, from the ink), mapped onto the PDF's page as compare.py maps
the text, less where the PDF sets it. With `--fit`, the foot's blocks
moved by how far they are off (margins.json).

    python3 -I furniture.py [--fit]
"""
import html, json, os, re, statistics, subprocess, sys
FIT = '--fit' in sys.argv
del sys.argv[1:]
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import compare

PT = 72 / 300
# Each page's heads and foot on the scan: the word, its box (pixels).
SCAN = {
    46: {'head': [('LEV', (734, 364, 1044, 438)), ('LEW', (2121, 346, 2467, 424))],
         'foot': [('Before', (2903, 5595, 3042, 5642))]},
    47: {'head': [('LIB', (690, 408, 965, 503)), ('LIB', (2187, 413, 2462, 494))],
         'foot': [('4', (846, 5604, 873, 5641)), ('One', (2906, 5583, 2999, 5631))]},
    48: {'head': [('LIB', (740, 349, 1014, 429)), ('LIC', (2176, 336, 2463, 409))],
         'foot': [('5', (886, 5603, 912, 5643)), ('K', (2388, 5518, 2429, 5558)),
                  ('The', (2980, 5515, 3075, 5558))]},
}


def pdf_words(page_index):
    out = subprocess.run(['pdftotext', '-bbox-layout', '-f', str(page_index + 1), '-l', str(page_index + 1),
                          compare.PDF, '-'], capture_output=True, text=True, check=True).stdout
    for m in re.finditer(r'<word xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" yMax="([\d.]+)">(.*?)</word>', out):
        x0, y0, x1, y1 = map(float, m.groups()[:4])
        yield html.unescape(m.group(5)), x0, x1, y1 - (y1 - y0) * 260 / 1230


def main():
    report = compare.run(quiet=True)
    report.pop('bad_words')
    fit = json.load(open(os.path.join(compare.WORK, 'fit.json')))
    path = os.path.join(compare.HERE, 'margins.json')
    margins = json.load(open(path)) if os.path.exists(path) else {}
    heads = []
    for pi, page in enumerate(compare.PAGES):
        ax, bx, cx, ay, by, cy = report[page]['transform']
        words = list(pdf_words(pi))
        for part in ('head', 'foot'):
            for c, (word, (x0, y0, x1, y1)) in enumerate(SCAN[page][part]):
                sx, sy = (x0 + x1) / 2 * PT, y1 * PT
                px, py = ax * sx + bx * sy + cx, ay * sx + by * sy + cy
                if part == 'head':
                    # (The head's letters, each a word to Poppler.)
                    side = [w for w in words if w[3] < 115 and (w[1] < compare.SPLIT) == (c == 0)]
                    mid = (min(w[1] for w in side) + max(w[2] for w in side)) / 2
                    base = statistics.median(w[3] for w in side)
                    heads.append((mid - px, base - py))
                    print(f'{page} head {word}: PDF {mid - px:+.1f} pt across, {base - py:+.1f} down')
                else:
                    w = min((w for w in words if w[0] == word or w[0].endswith(word)),
                            key=lambda w: abs(w[3] - py) + abs((w[1] + w[2]) / 2 - px))
                    dx, dy = (w[1] + w[2]) / 2 - px, w[3] - py
                    print(f'{page} foot {word}: PDF {dx:+.1f} pt across, {dy:+.1f} down')
                    if FIT:
                        kind = 'folio' if word in ('4', '5') else 'foot'
                        block = next(f['block'] for f in fit if f['page'] == page and f['line'] == kind)
                        if kind == 'foot' and word == 'K':
                            continue
                        margins[str(block)] = round(margins.get(str(block), 0) - dy, 2)
    print(f'heads: median {statistics.median(h[0] for h in heads[0::2]):+.1f} / '
          f'{statistics.median(h[0] for h in heads[1::2]):+.1f} pt across, '
          f'{statistics.median(h[1] for h in heads):+.1f} down')
    if FIT:
        json.dump(dict(sorted(margins.items(), key=lambda kv: int(kv[0]))), open(path, 'w'), indent=0)


main()
