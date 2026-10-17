"""Each printed line of the PDF against the scan's (scan.json): its
baseline and its left and right ends, page by page, column by column.
The PDF's lines read with Poppler (`pdftotext -bbox-layout`), the words
of each column (by the rule between them) grouped by baseline, under
the running head; paired with the spec's lines (gen.py's fit.json) in
order.

    python3 -I compare.py [--lines] [PAGE...]
"""
import html, json, os, re, statistics, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.environ.get('PUNCH_WORK', os.path.expanduser('~/.cache/asciidart-work/print-match/punch'))
PDF = os.path.join(WORK, 'build', 'punch.pdf')
DESCENT = 0.238  # Old Standard TT's descent in Poppler's box
RULE = {'verso': 58.8 + 213.5, 'recto': 53.2 + 213.5}
ARGS = [a for a in sys.argv[1:] if not a.startswith('--')]


PAGE_OF = {}


def locate():
    """Each spec page's page in the PDF: the first PDF page, from the page
    before's on, with the page's first line (a page that overflows its
    sheet pushes the pages after it on)."""
    PAGE_OF.clear()
    sys.path.insert(0, HERE)
    from scan import spec_lines
    lines = spec_lines()
    n = int(subprocess.run(['pdfinfo', PDF], capture_output=True, text=True).stdout.split('Pages:')[1].split()[0])
    texts = [re.sub(r'[^a-z]', '', subprocess.run(['pdftotext', '-f', str(i), '-l', str(i), PDF, '-'],
                                                  capture_output=True, text=True).stdout.lower()) for i in range(1, n + 1)]
    at = 0
    for page in sorted({p for p, _ in lines}):
        first = next((re.sub(r'[^a-z]', '', l.lower()) for l in lines.get((page, 1), []) if len(re.sub(r'[^a-z]', '', l.lower())) > 12), None)
        if not first:
            continue
        hit = next((i for i in range(at, n) if first[:20] in texts[i]), None)
        if hit is not None:
            PAGE_OF[page] = hit + 1
            at = hit


def pdf_lines(page):
    only = sorted(int(p) for p in os.environ.get('ONLY', '').split(',') if p)
    if only:
        # (Pages built alone, gen.py's ONLY: the PDF's place in that list.)
        page_pdf = only.index(page) + 1 if page in only else 1
    else:
        if not PAGE_OF:
            locate()
        page_pdf = PAGE_OF.get(page, page)
    if not SPEC_TEXT:
        from scan import spec_lines
        SPEC_TEXT.update(spec_lines())
    out = subprocess.run(['pdftotext', '-bbox', '-f', str(page_pdf), '-l', str(page_pdf), PDF, '-'],
                         capture_output=True, text=True, check=True).stdout
    side = 'verso' if page % 2 == 0 else 'recto'
    cols = {1: [], 2: [], 3: [], 4: []}
    from scan import floats
    edges = floats()
    for m in re.finditer(r'<word xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" yMax="([\d.]+)">(.*?)</word>', out):
        x0, y0, x1, y1 = map(float, m.groups()[:4])
        base = y1 - (y1 - y0) * DESCENT
        # (A page of one column, a plate: all its words the first's, its
        # title where a page of text has its running head.)
        single = (page, 2) not in SPEC_TEXT and (page, 1) in SPEC_TEXT
        if base < 52 and not single:
            continue  # (the running head)
        cols[1 if x0 < RULE[side] or single else 2].append((x0, base, x1, html.unescape(m.group(5))))
    if any(p == page for p, _ in edges):
        # (A block floating at a column's side, a column of its own: its
        # lines the probe's marked ones, the words on their baselines from
        # their left ends on.)
        marks = probe(page_pdf)
        for c in (1, 2):
            keep = []
            for w in cols[c]:
                hit = any(abs(w[1] - b) < 0.6 and w[0] >= x - 2 and (x < RULE[side]) == (c == 1) for b, x in marks)
                (cols[c + 2] if hit else keep).append(w)
            cols[c] = keep
    res = {}
    for c, ws in cols.items():
        rows = []
        for w in sorted(ws, key=lambda w: (w[1], w[0])):
            if rows and abs(rows[-1]['base'] - w[1]) < 2:
                rows[-1]['words'].append(w)
            else:
                rows.append({'base': w[1], 'words': [w]})
        # (A row of a figure, a word or two with it, closer to the next
        # than a line's pitch, a table's figure set between the two lines
        # of its row: one with the nearer of them.)
        for k in range(len(rows) - 1, -1, -1):
            text = ''.join(w[3] for w in rows[k]['words'])
            if len(rows) > 1 and (len(rows[k]['words']) <= 3 and re.search(r'\d', text) or len(text) <= 2):
                near = min((j for j in (k - 1, k + 1) if 0 <= j < len(rows)), key=lambda j: abs(rows[j]['base'] - rows[k]['base']))
                # (A letter or two alone: a superscript, N^o^, nearer than a
                # line.)
                short = len(''.join(w[3] for w in rows[k]['words'])) <= 2
                if abs(rows[near]['base'] - rows[k]['base']) < (5.0 if short else 4.0):
                    rows[near]['words'] += rows[k]['words']
                    del rows[k]
        res[c] = [{'base': r['base'], 'left': min(w[0] for w in r['words']), 'right': max(w[2] for w in r['words']),
                   'text': ' '.join(w[3] for w in sorted(r['words']))} for r in rows]
    return res


PROBES = {}


def probe(page_pdf):
    """The floating blocks' lines on the page: their baselines and left
    ends, read from a build with them marked (gen.py's PROBE), the page
    laid out the same down to its baselines; the build put back."""
    if PDF not in PROBES:
        env = dict(os.environ, PROBE='1', PUNCH_PDF='probe.pdf')
        subprocess.run([os.path.join(HERE, 'build.sh')], env=env, check=True, capture_output=True)
        subprocess.run(['python3', '-I', os.path.join(HERE, 'gen.py')], check=True, capture_output=True)
        PROBES[PDF] = {}
    if page_pdf not in PROBES[PDF]:
        out = subprocess.run(['pdftotext', '-bbox', '-f', str(page_pdf), '-l', str(page_pdf),
                              os.path.join(WORK, 'build', 'probe.pdf'), '-'], capture_output=True, text=True).stdout
        marks = []
        for m in re.finditer(r'<word xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" yMax="([\d.]+)">(.*?)</word>', out):
            if html.unescape(m.group(5)).startswith('§'):
                x0, y0, x1, y1 = map(float, m.groups()[:4])
                marks.append((y1 - (y1 - y0) * DESCENT, x0))
        PROBES[PDF][page_pdf] = marks
    return PROBES[PDF][page_pdf]


def images(page_pdf):
    """The page's images (the cuts) as the PDF places them: their boxes, in
    points from the page's top left, to a third of a point (Poppler's
    `pdftohtml -xml` at `-zoom 4`, three of its units a point)."""
    import tempfile
    with tempfile.TemporaryDirectory() as tmp:
        out = subprocess.run(['pdftohtml', '-xml', '-zoom', '4', '-f', str(page_pdf), '-l', str(page_pdf), '-stdout',
                              PDF, os.path.join(tmp, 'x')], capture_output=True, text=True).stdout
    return [tuple(int(m.group(k)) / 3 for k in (2, 1, 3, 4))
            for m in re.finditer(r'<image top="(-?\d+)" left="(-?\d+)" width="(\d+)" height="(\d+)"', out)]


def page_index(page):
    """The PDF's page for the spec's [page]."""
    only = sorted(int(p) for p in os.environ.get('ONLY', '').split(',') if p)
    if only:
        return only.index(page) + 1 if page in only else 1
    if not PAGE_OF:
        locate()
    return PAGE_OF.get(page, page)


MISMATCHED = set()
SPEC_TEXT = {}


def norm(t):
    t = re.sub(r'\[[^\]]*\]#+|#+|__|\{[a-z]+\}|@', '', html.unescape(t))
    return re.sub(r'[^a-z0-9]', '', t.lower())


def run(pages=None, quiet=False):
    say = (lambda *a: None) if quiet else print
    fit = json.load(open(os.path.join(WORK, 'fit.json')))
    scan = json.load(open(os.path.join(WORK, 'scan.json')))
    MISMATCHED.clear()
    PAGE_OF.clear()
    PROBES.clear()
    sys.path.insert(0, HERE)
    from scan import spec_lines
    SPEC_TEXT.clear()
    SPEC_TEXT.update(spec_lines())
    report = {}
    pages = pages or sorted({f['page'] for f in fit})
    for page in pages:
        if str(page) not in scan:
            continue
        pdf = pdf_lines(page)
        rows = []
        for c in (1, 2, 3, 4):
            spec = [f for f in fit if f['page'] == page and f['col'] == c and isinstance(f['line'], int)]
            lines = pdf[c]
            sc = scan[str(page)].get(str(c), [])
            if c > 2 and not spec and not lines:
                continue
            if len(lines) != len(spec):
                say(f'{page}/{c}: {len(lines)} lines on the PDF, {len(spec)} in the spec')
                MISMATCHED.add((page, c))
            texts = SPEC_TEXT.get((page, c), [])
            for i, (f, s, p) in enumerate(zip(spec, sc, lines)):
                # (Whether the PDF's line is the spec's: their letters' start.)
                want = norm(texts[i]) if i < len(texts) else ''
                got = norm(p['text'])
                same = (want[:10] == got[:10] or want[:6] in got[:12] or (len(want) > 8 and want in got)) if want else not got
                if s and s.get('base') is not None:
                    rows.append({'col': c, 'line': f['line'], 'block': f['block'], 'key': f.get('key'), 'kind': f['kind'],
                                 'same': same,
                                 'base': round(p['base'] - s['base'], 2),
                                 'left': round(p['left'] - s['left'], 2) if s.get('left') is not None else None,
                                 'right': round(p['right'] - s['right'], 2) if s.get('right') is not None else None,
                                 'text': p['text'][:50]})
        report[page] = rows
        if rows:
            wrong = sum(not r['same'] for r in rows)
            say(f"{page}: base off {max(abs(r['base']) for r in rows):.1f} (median {statistics.median(r['base'] for r in rows):+.2f}); "
                f"{sum(abs(r['base']) <= 1 for r in rows)} of {len(rows)} within a point"
                + (f"; {wrong} not the spec's" if wrong else ''))
    return report


def mismatched():
    return set(MISMATCHED)


if __name__ == '__main__':
    report = run([int(a) for a in ARGS] or None)
    if '--lines' in sys.argv:
        for page, rows in report.items():
            for r in rows:
                if abs(r['base']) > 1:
                    print(f"{page}/{r['col']}/{r['line']} {r['kind']} base {r['base']:+.1f}  {r['text']}")
