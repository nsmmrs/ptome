"""Each printed line of the PDF against the scan's (scan.json): its
words (the transcription's, fit.json), its baseline, its left and right
ends, column by column, page by page. The PDF's lines are read with
Poppler (`pdftotext -bbox-layout`), its words grouped by baseline in each
column; the scan's page is set on the PDF's by the offset that puts the
two pages' lines most nearly together (the scans are not cut alike).

    python3 -I compare.py [PDF]           # a summary of each column
    python3 -I compare.py [PDF] --lines   # every line off by more than 1 pt
    python3 -I compare.py [PDF] --json=OUT

A line's words on the PDF must be the transcription's (no line set on
two lines, none run together); each line's left and right within 1 pt
and its baseline within 1 pt of the scan's, after the page's offset.
"""
import html, json, os, re, statistics, subprocess, sys
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.environ.get('JOHNSON_WORK', os.path.expanduser('~/.cache/asciidart-work/print-match/johnson'))
args = [a for a in sys.argv[1:] if not a.startswith('--')]
PDF = args[0] if args else os.path.join(WORK, 'build', 'johnson.pdf')
SPLIT = 387  # the PDF's columns' divide, in points
PAGES = [46, 47, 48]


def pdf_lines():
    """Each page's columns' lines: their words, baseline, left, right."""
    out = subprocess.run(['pdftotext', '-bbox-layout', PDF, '-'], capture_output=True, text=True, check=True).stdout
    pages = []
    for page in re.findall(r'<page[^>]*>(.*?)</page>', out, re.S):
        words = []
        for m in re.finditer(r'<word xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" yMax="([\d.]+)">(.*?)</word>', page):
            x0, y0, x1, y1 = map(float, m.groups()[:4])
            # (Poppler's box runs from the face's ascent to its descent:
            # the baseline is the descent up from its foot, Libre Caslon's
            # 260 of the 1230 units.)
            base = y1 - (y1 - y0) * 260 / 1230
            words.append((x0, y0, x1, base, html.unescape(m.group(5))))
        cols = [[], []]
        for w in words:
            cols[0 if w[0] < SPLIT else 1].append(w)
        page_cols = []
        for ws in cols:
            rows = []
            # (Below the heads.)
            for w in sorted((w for w in ws if w[3] > 115), key=lambda w: (w[3], w[0])):
                if rows and abs(rows[-1]['y'] - w[3]) < 3:
                    rows[-1]['words'].append(w)
                else:
                    rows.append({'y': w[3], 'words': [w]})
            lines = []
            for r in rows:
                ws = sorted(r['words'])
                lines.append({'base': r['y'], 'left': ws[0][0], 'right': max(w[2] for w in ws),
                              'text': ' '.join(w[4] for w in ws)})
            page_cols.append(lines)
        pages.append(page_cols)
    return pages


def plain(text):
    text = re.sub(r'\{(?:shy|ls|empty|nbsp)\}', '', text)
    text = re.sub(r'\[\.[\w.-]+\]#+|#+|_+|\[\[[^]]*\]\]', '', text)
    text = re.sub(r'\{([^}]*)\}', r'\1', text)
    return re.sub(r'\s+', ' ', text.replace('@', '')).strip()


def words(text):
    # (The Hebrew read in the order it is drawn: left out.)
    return re.sub(r'[^\w]|[\u0590-\u05ff]', '', text.replace('ſ', 's')).lower()


def run(quiet=False):
    """The comparison: each page's transform and lines (printed unless
    [quiet])."""
    say = (lambda *a: None) if quiet else print
    fit = json.load(open(os.path.join(WORK, 'fit.json')))
    scan = json.load(open(os.path.join(WORK, 'scan.json')))
    pdf = pdf_lines()
    report = {}
    worst = 0
    bad_words = 0
    lasts = [f for i, f in enumerate(fit) if isinstance(f['line'], int)
             and (i + 1 == len(fit) or fit[i + 1]['block'] != f['block'])]
    for pi, page in enumerate(PAGES):
        rows = []
        for c in (1, 2):
            spec = [f for f in fit if f['page'] == page and f['column'] == c and isinstance(f['line'], int)]
            lines = pdf[pi][c - 1][:len(spec)]
            for f, s, p in zip(spec, scan[str(page)][c - 1], lines):
                rows.append((c, f, s, p))
        # (The scan's page set on the PDF's: the affine map that puts the
        # scan's headwords' and senses' left ends and its full lines' right
        # ends, on their baselines, most nearly on the PDF's, by least
        # squares; a scan is stretched a little more one way than the
        # other, and leans.)
        pts = []
        last = {id(f) for f in lasts}
        for c, f, s, p in rows:
            if f['kind'] in 'ES' and f['first']:
                pts.append(((s['left'], s['base']), (p['left'], p['base'])))
            if f['kind'] in 'ESC' and id(f) not in last and not f['author']:
                pts.append(((s['right'], s['base']), (p['right'], p['base'])))
        A = np.array([[x, y, 1] for (x, y), _ in pts])
        mx = np.linalg.lstsq(A, np.array([u for _, (u, v) in pts]), rcond=None)[0]
        my = np.linalg.lstsq(A, np.array([v for _, (u, v) in pts]), rcond=None)[0]

        def place(x, y):
            return mx[0] * x + mx[1] * y + mx[2], my[0] * x + my[1] * y + my[2]
        report[page] = {'scale': [round(float(mx[0]), 4), round(float(my[1]), 4)],
                        'shear': [round(float(mx[1]), 4), round(float(my[0]), 4)],
                        'transform': [float(v) for v in (*mx, *my)], 'lines': []}
        for c in (1, 2):
            col = [(f, s, p) for cc, f, s, p in rows if cc == c]
            spec_n = len([f for f in fit if f['page'] == page and f['column'] == c and isinstance(f['line'], int)])
            if len(pdf[pi][c - 1]) < spec_n:
                say(f'{page}/{c}: {len(pdf[pi][c - 1])} lines on the PDF, {spec_n} in the text')
            offs = []
            for f, s, p in col:
                sl, sb = place(s['left'], s['base'])
                sr, _ = place(s['right'], s['base'])
                s = {'left': sl, 'right': sr, 'base': sb}
                same = words(plain(f['text'])) == words(p['text'])
                d = {'line': f['line'], 'block': f['block'], 'kind': f['kind'],
                     'base': round(p['base'] - s['base'], 2),
                     'left': round(p['left'] - s['left'], 2),
                     'right': round(p['right'] - s['right'], 2),
                     'same': same, 'pdf': p['text'], 'text': plain(f['text'])}
                if not same:
                    bad_words += 1
                report[page]['lines'].append(dict(d, column=c))
                offs.append(d)
                worst = max(worst, abs(d['base']))
            if offs:
                say(f"{page}/{c}: {len(offs)} lines; base off {max(abs(o['base']) for o in offs):.1f} "
                      f"(median {statistics.median(o['base'] for o in offs):+.1f}); "
                      f"left off >1pt {sum(abs(o['left']) > 1 for o in offs)}, right >1pt {sum(abs(o['right']) > 1 for o in offs)}; "
                      f"words differ {sum(not o['same'] for o in offs)}")
    report['bad_words'] = bad_words
    return report


def main():
    report = run()
    bad_words = report.pop('bad_words')
    if '--lines' in sys.argv:
        for page, r in report.items():
            for d in r['lines']:
                if not d['same'] or abs(d['base']) > 1 or abs(d['left']) > 1 or abs(d['right']) > 1:
                    print(f"{page}/{d['column']}/{d['line']} {d['kind']} base {d['base']:+.1f} left {d['left']:+.1f} right {d['right']:+.1f}"
                          + ('' if d['same'] else f"\n   pdf:  {d['pdf']}\n   text: {d['text']}"))
    for a in sys.argv:
        if a.startswith('--json='):
            json.dump(report, open(a[7:], 'w'), indent=0)
    print(f'words differ on {bad_words} lines')


if __name__ == "__main__":
    main()
