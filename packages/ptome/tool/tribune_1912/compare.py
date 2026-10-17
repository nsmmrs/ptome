"""Each printed line of the PDF against the scan's (scan.json), region by
region: the PDF's words (Poppler's `pdftotext -bbox`) given to the
region their middle falls in (regions.txt, the page's points the scan's
pixels over PX), grouped by baseline, paired with the region's spec lines
(gen.py's fit.json) in order; a pair whose letters aren't alike counted,
a region with more or fewer lines than its spec named.

    python3 -I compare.py [--lines] [PAGE/REGION...]
"""
import html, json, os, re, statistics, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from common import WORK, PX
from lines import regions
from scan import spec_lines

PDF = os.path.join(WORK, 'build', os.environ.get('TRIBUNE_PDF', 'tribune.pdf'))
DESCENT = 0.235
MISMATCHED = set()


def norm(t):
    return re.sub(r'[^a-z0-9]', '', html.unescape(t).lower())


def pdf_words(page):
    out = subprocess.run(['pdftotext', '-bbox', '-f', str(page), '-l', str(page), PDF, '-'],
                         capture_output=True, text=True, check=True).stdout
    ws = []
    for m in re.finditer(r'<word xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" yMax="([\d.]+)">(.*?)</word>', out):
        x0, y0, x1, y1 = map(float, m.groups()[:4])
        ws.append((x0, y1 - (y1 - y0) * DESCENT, x1, html.unescape(m.group(5)), y1 - y0))
    return ws


_INK = {}


def page_ink(page):
    """The PDF's page drawn at the scan's resolution: its ink."""
    if page not in _INK:
        import numpy as np
        from PIL import Image
        path = os.path.join(WORK, 'build', f'ink-{page}')
        subprocess.run(['pdftoppm', '-r', f'{72 * PX:.4f}', '-f', str(page), '-l', str(page), '-gray', '-png',
                        '-singlefile', PDF, path], check=True)
        _INK[page] = np.asarray(Image.open(path + '.png').convert('L')) < 128
    return _INK[page]


def ink_base(page, row):
    """A row's baseline where its ink falls off most near where Poppler's
    box puts it, as the scan's are found (scan.py)."""
    import numpy as np
    ink = page_ink(page)
    h = row['height']
    x0, x1 = int(row['left'] * PX), int(row['right'] * PX)
    est = row['base'] * PX
    half = int(0.35 * h * PX) + 2
    y0 = max(0, int(est) - half)
    prof = ink[y0:int(est) + half + 1, x0:x1].sum(axis=1).astype(float)
    if len(prof) < 3 or prof.max() == 0:
        return row['base']
    drop = prof[:-1] - prof[1:]
    k = int(np.argmax(drop))
    return (y0 + k + 1) / PX


def region_rows(words, box):
    """The rows of the words whose middles fall in the region's columns
    (wherever they are down the page: a line set lower or higher than the
    scan's is still the region's)."""
    x0, y0, x1, y1 = (v / PX for v in box)
    ws = [w for w in words if x0 <= (w[0] + w[2]) / 2 < x1]
    rows = []
    for w in sorted(ws, key=lambda w: (w[1], w[0])):
        tol = max(1.5, 0.3 * w[4])
        if rows and abs(rows[-1]['base'] - w[1]) < tol:
            rows[-1]['words'].append(w)
        else:
            rows.append({'base': w[1], 'words': [w]})
    return [{'base': statistics.median(w[1] for w in r['words']),
             'left': min(w[0] for w in r['words']), 'right': max(w[2] for w in r['words']),
             'height': statistics.median(w[4] for w in r['words']),
             'text': ' '.join(w[3] for w in sorted(r['words']))} for r in rows]


def pair(texts, rows):
    """The spec's lines paired with the rows by their letters, in order:
    {spec line: row}."""
    from scan import align
    return align([norm(t) for t in texts], [(norm(r['text']), norm(r['text'])) for r in rows])


def run(only=None, quiet=False):
    say = (lambda *a: None) if quiet else print
    fit = json.load(open(os.path.join(WORK, 'fit.json')))
    scan = json.load(open(os.path.join(WORK, 'scan.json')))
    MISMATCHED.clear()
    report = {}
    _INK.clear()
    for page in sorted(regions()):
        words = pdf_words(page)
        for rid, kind, box in regions()[page]:
            if kind != 'text' or (only and f'{page}/{rid}' not in only):
                continue
            texts, _ = spec_lines(page, rid)
            if not texts:
                continue
            rows = region_rows(words, box)
            match = pair(texts, rows)
            spec = [f for f in fit if f['page'] == page and f['region'] == rid]
            sc = scan[str(page)].get(rid, [])
            if len(match) != len(texts):
                say(f'{page}/{rid}: {len(texts) - len(match)} of its {len(texts)} lines not found on the PDF')
                MISMATCHED.add((page, rid))
            out = []
            for i, (f, s) in enumerate(zip(spec, sc)):
                if i not in match:
                    continue
                p = rows[match[i]]
                p['base'] = ink_base(page, p)
                want, have = norm(texts[i]), norm(p['text'])
                same = want == have
                out.append({'line': f['line'], 'key': f['key'], 'kind': f['kind'], 'same': same,
                            'base': round(p['base'] - s['base'], 2), 'text': p['text'][:60]})
            report[(page, rid)] = out
            if out:
                wrong = sum(not r['same'] for r in out)
                say(f"{page}/{rid}: base off {max(abs(r['base']) for r in out):.1f} "
                    f"(median {statistics.median(r['base'] for r in out):+.2f}); "
                    f"{sum(abs(r['base']) <= 1 for r in out)} of {len(out)} within a point"
                    + (f"; {wrong} not the spec's" if wrong else ''))
    return report


def cut_offsets():
    """Each cut's place on the PDF against the scan's, in points (down
    positive): the shift that best lays its ink's rows (its middle half
    across) on the scan's."""
    import numpy as np
    from PIL import Image
    from common import IMAGES
    out = {}
    for page, rs in regions().items():
        scan = None
        for rid, kind, (x0, y0, x1, y1) in rs:
            if kind != 'cut':
                continue
            if scan is None:
                scan = np.asarray(Image.open(os.path.join(WORK, IMAGES[page] + '.jpg')).convert('L')) < 110
            pdf = page_ink(page)
            a, b = x0 + (x1 - x0) // 4, x1 - (x1 - x0) // 4
            ref = scan[y0:y1, a:b].mean(axis=1)
            best, arg = -1e9, 0
            for d in range(-400, 401, 2):
                if y0 + d < 0 or y1 + d > pdf.shape[0]:
                    continue
                got = pdf[y0 + d:y1 + d, a:b].mean(axis=1)
                v = float(np.dot(ref - ref.mean(), got - got.mean()))
                if v > best:
                    best, arg = v, d
            for d in range(arg - 2, arg + 3):
                if y0 + d < 0 or y1 + d > pdf.shape[0]:
                    continue
                got = pdf[y0 + d:y1 + d, a:b].mean(axis=1)
                v = float(np.dot(ref - ref.mean(), got - got.mean()))
                if v > best:
                    best, arg = v, d
            out[rid] = round(arg / PX, 2)
    return out


def mismatched():
    return set(MISMATCHED)


if __name__ == '__main__':
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    report = run(set(args) or None)
    if '--lines' in sys.argv:
        for (page, rid), rows in report.items():
            for r in rows:
                if abs(r['base']) > 1 or not r['same']:
                    print(f"{page}/{rid}/{r['line']} {r['kind']} base {r['base']:+.1f} {'' if r['same'] else 'NOT '} {r['text']}")
