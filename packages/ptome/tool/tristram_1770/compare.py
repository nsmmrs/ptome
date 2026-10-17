"""Each printed line of the PDF against the scan's (scan.json): its
baseline and its ends, page by page. The PDF's lines read with Poppler
(`pdftotext -bbox`), its words grouped by baseline, paired with the
spec's lines (gen.py's fit.json) in order; a pair whose letters aren't
alike counted: a line set otherwise than the spec's (a line set on two).

    python3 -I compare.py [--lines] [PAGE...]
"""
import html, json, os, re, statistics, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from common import WORK

PDF = os.path.join(WORK, 'build', os.environ.get('TRISTRAM_PDF', 'tristram.pdf'))
DESCENT = 0.215
ARGS = [a for a in sys.argv[1:] if not a.startswith('--')]
PAGE_OF = {}
MISMATCHED = set()


def norm(t):
    t = re.sub(r'\[[^\]]*\]#+|#+|__|\{[a-z]+\}|[⟦⟧@]', '', html.unescape(t))
    return re.sub(r'[^a-z0-9]', '', t.lower())


def spec_lines():
    """tristram.spec's printed lines by page, in order."""
    out, page = {}, None
    for raw in open(os.path.join(HERE, 'tristram.spec'), encoding='utf-8'):
        raw = raw.rstrip('\n')
        if raw.startswith('@page'):
            page = raw.split()[1]
            out[page] = []
        elif raw and not raw.startswith(('@', '#')) and page is not None:
            # (The line's text, its kind before it left off.)
            out[page].append(re.sub(r'^(?:X \S+|V\+\d+|.) ', '', raw).replace(' | ', ' '))
    return out


def locate(lines):
    """Each page's page in the PDF: a page to a spec page when none ran
    over; else the first page from the page before's on that has the
    page's first long line."""
    PAGE_OF.clear()
    n = int(subprocess.run(['pdfinfo', PDF], capture_output=True, text=True).stdout.split('Pages:')[1].split()[0])
    order = list(lines)
    if n == len(order):
        PAGE_OF.update({p: i + 1 for i, p in enumerate(order)})
        return
    texts = [norm(subprocess.run(['pdftotext', '-f', str(i), '-l', str(i), PDF, '-'],
                                 capture_output=True, text=True).stdout) for i in range(1, n + 1)]
    at = 0
    for p in order:
        first = next((norm(l)[2:] for l in lines[p] if len(norm(l)) > 20 and not l.startswith('I ')), None)
        if not first:
            PAGE_OF[p] = at + 1
            at += 1
            continue
        hit = next((i for i in range(at, n) if first[:30] in texts[i]), None)
        if hit is not None:
            PAGE_OF[p] = hit + 1
            at = hit + 1


def page_index(page):
    only = [p for p in os.environ.get('ONLY', '').split(',') if p]
    if only:
        return only.index(page) + 1 if page in only else 1
    return PAGE_OF.get(page)


def pdf_lines(page):
    out = subprocess.run(['pdftotext', '-bbox', '-f', str(page_index(page)), '-l', str(page_index(page)), PDF, '-'],
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
    # (A drop initial: its own row, a letter alone taller than a line.)
    res = []
    for r in rows:
        # (A drop initial: a letter alone taller than a line, in a row of
        # its own or the row of its paragraph's second line.)
        small = [w for w in r['words'] if w[4] <= 22]
        r['words'] = [w for w in r['words']
                      if not (w[4] > 22 and len(w[3]) == 1 and w[3].isalpha() and (len(small) >= 3 or len(r['words']) == 1))]
        if not r['words']:
            continue
        big = [w for w in r['words'] if w[4] > 22]
        rest = [w for w in r['words'] if w[4] <= 22]
        rest = rest or big
        base = statistics.median(w[1] for w in rest)
        res.append({'base': base, 'left': min(w[0] for w in r['words']), 'right': max(w[2] for w in r['words']),
                    'text': ' '.join(w[3] for w in sorted(r['words']))})
    return res


def run(pages=None, quiet=False):
    say = (lambda *a: None) if quiet else print
    lines = spec_lines()
    fit = json.load(open(os.path.join(WORK, 'fit.json')))
    scan = json.load(open(os.path.join(WORK, 'scan.json')))
    MISMATCHED.clear()
    if not os.environ.get('ONLY'):
        locate(lines)
    report = {}
    for page in pages or list(lines):
        if page not in scan or not lines.get(page):
            continue
        if page_index(page) is None:
            say(f'{page}: not found in the PDF')
            MISMATCHED.add(page)
            continue
        got = pdf_lines(page)
        spec = [f for f in fit if f['page'] == page]
        sc = scan[page]
        texts = lines[page]
        if len(got) != len(spec):
            say(f'{page}: {len(got)} lines on the PDF, {len(spec)} in the spec')
            MISMATCHED.add(page)
        rows = []
        for i, (f, s, p) in enumerate(zip(spec, sc, got)):
            want = norm(texts[i]) if i < len(texts) else ''
            have = norm(p['text'])
            same = (want[:8] == have[:8] or want[:5] in have[:12] or (len(want) > 6 and want in have)
                    or want[1:8] == have[:7]) if want else not have
            if s and s.get('base') is not None:
                rows.append({'line': f['line'], 'block': f['block'], 'key': f.get('key'), 'kind': f['kind'], 'same': same,
                             'base': round(p['base'] - s['base'], 2),
                             'left': round(p['left'] - s['left'], 2) if s.get('left') is not None else None,
                             'right': round(p['right'] - s['right'], 2) if s.get('right') is not None else None,
                             'text': p['text'][:50]})
        report[page] = rows
        if rows:
            wrong = sum(not r['same'] for r in rows)
            say(f"{page}: base off {max(abs(r['base']) for r in rows):.1f} (median {statistics.median(r['base'] for r in rows):+.2f}); "
                f"{sum(abs(r['base']) <= 1 for r in rows)} of {len(rows)} within a point" + (f"; {wrong} not the spec's" if wrong else ''))
    return report


def mismatched():
    return set(MISMATCHED)


if __name__ == '__main__':
    report = run(ARGS or None)
    total = sum(len(r) for r in report.values())
    within = sum(abs(x['base']) <= 1 for r in report.values() for x in r)
    print(f'{within} of {total} lines within a point; {len(MISMATCHED)} pages not the spec\'s: {sorted(MISMATCHED, key=lambda p: (len(p), p))[:20]}')
    if '--lines' in sys.argv:
        for page, rows in report.items():
            for r in rows:
                if abs(r['base']) > 1 or not r['same']:
                    print(f"{page}/{r['line']} {r['kind']} base {r['base']:+.1f} {'' if r['same'] else 'NOT '} {r['text']}")
