"""Each printed line of the PDF against the scan's (scan.json): its
baseline and its ends, page by page. The PDF's lines read with Poppler
(`pdftotext -bbox`), its words grouped by baseline, paired with the
spec's lines (gen.py's fit.json) in order; a pair whose letters aren't
alike counted: a line set otherwise than the spec's.

    python3 -I compare.py [--lines] [LEAF...]
"""
import html, json, os, re, statistics, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from common import WORK

PDF = os.path.join(WORK, 'build', os.environ.get('BCP_PDF', 'bcp.pdf'))
DESCENT = 0.215
ARGS = [a for a in sys.argv[1:] if not a.startswith('--')]
PAGE_OF = {}
MISMATCHED = set()


def norm(t):
    t = re.sub(r'\[[^\]]*\]#+|#+|__|\{[a-z]+\}|[⟦⟧@]', '', html.unescape(t))
    return re.sub(r'[^a-z0-9]', '', t.lower())


def locate(lines):
    """Each leaf's page in the PDF: the first page from the leaf before's
    on that has the leaf's first line of text."""
    PAGE_OF.clear()
    n = int(subprocess.run(['pdfinfo', PDF], capture_output=True, text=True).stdout.split('Pages:')[1].split()[0])
    texts = [norm(subprocess.run(['pdftotext', '-f', str(i), '-l', str(i), PDF, '-'],
                                 capture_output=True, text=True).stdout) for i in range(1, n + 1)]
    at = 0
    if n == len(lines):
        # (A page to a leaf: none ran over.)
        PAGE_OF.update({leaf: i + 1 for i, leaf in enumerate(sorted(lines))})
        return
    for leaf in sorted(lines):
        first = next((norm(l) for l in lines[leaf][1:] if len(norm(l)) > 24), None)
        if leaf <= 34:
            # (A month's page: its month's head, the titles above it the
            # same on every month's.)
            first = norm(next(l for l in lines[leaf] if 'hath' in l))
        if not first:
            continue
        hit = next((i for i in range(at, n) if 0 <= texts[i].find(first[:40]) < 60), None)
        if hit is not None:
            PAGE_OF[leaf] = hit + 1
            at = hit


def page_index(leaf):
    only = sorted(int(p) for p in os.environ.get('ONLY', '').split(',') if p)
    if only:
        return only.index(leaf) + 1 if leaf in only else 1
    return PAGE_OF.get(leaf)


def pdf_lines(leaf):
    out = subprocess.run(['pdftotext', '-bbox', '-f', str(page_index(leaf)), '-l', str(page_index(leaf)), PDF, '-'],
                         capture_output=True, text=True, check=True).stdout
    ws = []
    for m in re.finditer(r'<word xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" yMax="([\d.]+)">(.*?)</word>', out):
        x0, y0, x1, y1 = map(float, m.groups()[:4])
        ws.append((x0, y1 - (y1 - y0) * DESCENT, x1, html.unescape(m.group(5)), y1 - y0))
    rows = []
    for w in sorted(ws, key=lambda w: (w[1], w[0])):
        if rows and abs(rows[-1]['base'] - w[1]) < 3.5:
            rows[-1]['words'].append(w)
        else:
            rows.append({'base': w[1], 'words': [w]})
    # (A drop initial: its own row, taller than a line; the line it opens
    # the row beside its top.)
    res = []
    for r in rows:
        big = [w for w in r['words'] if w[4] > 30]
        rest = [w for w in r['words'] if w[4] <= 30]
        if big and not rest and (len(big) == 1 and len(big[0][3]) == 1 and big[0][3].isalpha()):
            continue  # (A drop initial: one letter alone; a title's line in its size is a line.)
        rest = rest or big
        base = statistics.median(w[1] for w in rest)
        res.append({'base': base, 'left': min(w[0] for w in r['words']), 'right': max(w[2] for w in r['words']),
                    'text': ' '.join(w[3] for w in sorted(r['words']))})
    return res


def run(leaves=None, quiet=False):
    say = (lambda *a: None) if quiet else print
    sys.path.insert(0, HERE)
    from scan import spec_lines
    lines = spec_lines()
    fit = json.load(open(os.path.join(WORK, 'fit.json')))
    scan = json.load(open(os.path.join(WORK, 'scan.json')))
    MISMATCHED.clear()
    if not os.environ.get('ONLY'):
        locate(lines)
    report = {}
    for leaf in leaves or sorted({f['page'] for f in fit}):
        if str(leaf) not in scan:
            continue
        if page_index(leaf) is None:
            say(f'{leaf}: not found in the PDF')
            MISMATCHED.add(leaf)
            continue
        got = pdf_lines(leaf)
        spec = [f for f in fit if f['page'] == leaf]
        sc = scan[str(leaf)]
        texts = lines.get(leaf, [])
        if len(got) != len(spec) and leaf > 34:
            say(f'{leaf}: {len(got)} lines on the PDF, {len(spec)} in the spec')
            MISMATCHED.add(leaf)
        rows = []
        # (A line of rules alone, a Calendar's blank day, has no text to
        # read: left out of the pairing.)
        keep = [i for i in range(len(spec)) if i >= len(texts) or norm(texts[i]) or leaf > 34]
        spec = [spec[i] for i in keep]
        sc = [sc[i] for i in keep if i < len(sc)]
        texts = [texts[i] for i in keep if i < len(texts)]
        if len(got) != len(spec) and leaf <= 34:
            say(f'{leaf}: {len(got)} lines on the PDF, {len(spec)} in the spec (read)')
            MISMATCHED.add(leaf)
        for i, (f, s, p) in enumerate(zip(spec, sc, got)):
            want = norm(texts[i]) if i < len(texts) else ''
            have = norm(p['text'])
            # (A drop initial is a row of its own: the line without it.)
            same = (want[:8] == have[:8] or want[:5] in have[:12] or (len(want) > 6 and want in have)
                    or want[1:8] == have[:7]) if want else not have
            if s and s.get('base') is not None:
                rows.append({'line': f['line'], 'block': f['block'], 'key': f.get('key'), 'kind': f['kind'], 'same': same,
                             'base': round(p['base'] - s['base'], 2),
                             'left': round(p['left'] - s['left'], 2) if s.get('left') is not None else None,
                             'right': round(p['right'] - s['right'], 2) if s.get('right') is not None else None,
                             'text': p['text'][:50]})
        report[leaf] = rows
        if rows:
            wrong = sum(not r['same'] for r in rows)
            say(f"{leaf}: base off {max(abs(r['base']) for r in rows):.1f} (median {statistics.median(r['base'] for r in rows):+.2f}); "
                f"{sum(abs(r['base']) <= 1 for r in rows)} of {len(rows)} within a point" + (f"; {wrong} not the spec's" if wrong else ''))
    return report


def mismatched():
    return set(MISMATCHED)


if __name__ == '__main__':
    report = run([int(a) for a in ARGS] or None)
    if '--lines' in sys.argv:
        for leaf, rows in report.items():
            for r in rows:
                if abs(r['base']) > 1 or not r['same']:
                    print(f"{leaf}/{r['line']} {r['kind']} base {r['base']:+.1f} {'' if r['same'] else 'NOT '} {r['text']}")
