"""Each printed line of the PDF (the Folio's look) against the scan's
(scan.json): its baseline and its left and right ends, column by column,
the last page's bands' columns its 3rd and 4th. The PDF's lines read with
Poppler (`pdftotext -bbox-layout`), the words of each column grouped by
baseline, under the running head and above the foot line; the scan's
already on the PDF's page, set there by its frame (scan.py), no fit.

    python3 -I compare.py [PDF] [--lines] [--json=OUT]
"""
import html, json, os, re, statistics, subprocess, sys
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.environ.get('TEMPEST_WORK', os.path.expanduser('~/.cache/asciidart-work/print-match/tempest'))
args = [a for a in sys.argv[1:] if not a.startswith('--')]
PDF = args[0] if args else os.path.join(WORK, 'build', 'tempest-folio.pdf')
SPLIT = 302  # the PDF's columns' divide, in points
DESCENT = 0.243  # IM Fell DW Pica's descent in Poppler's box


def pdf_lines():
    out = subprocess.run(['pdftotext', '-bbox-layout', PDF, '-'], capture_output=True, text=True, check=True).stdout
    pages = []
    for page in re.findall(r'<page[^>]*>(.*?)</page>', out, re.S):
        cols = [[], []]
        for m in re.finditer(r'<word xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" yMax="([\d.]+)">(.*?)</word>', page):
            x0, y0, x1, y1 = map(float, m.groups()[:4])
            base = y1 - (y1 - y0) * DESCENT
            if base < 66 or base > 930:
                continue
            cols[0 if x0 < SPLIT else 1].append((x0, base, x1, html.unescape(m.group(5))))
        page_cols = []
        for ws in cols:
            rows = []
            for w in sorted(ws, key=lambda w: (w[1], w[0])):
                if rows and abs(rows[-1]['base'] - w[1]) < 3:
                    rows[-1]['words'].append(w)
                else:
                    rows.append({'base': w[1], 'words': [w]})
            # (A letter set above the line, `y^e^`: its line's.)
            merged = []
            for r in rows:
                small = all(len(w[3]) <= 2 for w in r['words'])
                if small and merged and False:
                    pass
                merged.append(r)
            k = 0
            while k < len(merged):
                r = merged[k]
                if all(len(w[3]) <= 2 for w in r['words']) and len(merged) > 1:
                    near = [j for j in (k - 1, k + 1) if 0 <= j < len(merged) and abs(merged[j]['base'] - r['base']) < 8]
                    if near:
                        merged[near[-1]]['words'] += r['words']
                        merged.pop(k)
                        continue
                k += 1
            rows = merged
            page_cols.append([{'base': r['base'], 'left': min(w[0] for w in r['words']),
                               'right': max(w[2] for w in r['words']),
                               'text': ' '.join(w[3] for w in sorted(r['words']))} for r in rows])
        pages.append(page_cols)
    return pages


MISMATCHED = set()


def mismatched():
    """The columns whose PDF lines aren't the spec's (the last run's)."""
    return set(MISMATCHED)


def first_lines():
    """Each page's columns' first lines' words in folio.spec."""
    out, page, col = {}, None, 0
    for line in open(os.path.join(HERE, 'folio.spec'), encoding='utf-8'):
        line = line.rstrip('\n')
        if line.startswith('@page'):
            page, col = int(line.split()[1]), 0
        elif line == '@column':
            col += 1
        elif line and not line.startswith(('@', '#')) and (page, col) not in out:
            out[(page, col)] = line[2:].split('|')[-1]
    return out


def column_lines(pdf, page, c, spec, spec_text):
    """The PDF's lines of the column that stand for the spec's: not the
    first page's head over its columns, nor the foot under the second."""
    # (The last page's second band: its columns the 3rd and 4th, under
    # the first's, from the line its first words start.)
    if c > 2:
        lines = pdf[page - 1][c - 3]
        key = re.sub(r'[^a-zA-Zſ]', '', (spec_text.get((page, c)) or ''))[:6]
        k = next((i for i, l in enumerate(lines) if key and key in re.sub(r'[^a-zA-Zſ]', '', l['text'])), len(lines))
        lines = lines[k:k + len(spec)]
        return lines
    lines = pdf[page - 1][c - 1]
    # (The last page's first band: its lines down to the gap over the
    # rule under it.)
    if page == 19:
        k = next((i for i in range(1, len(lines)) if lines[i]['base'] - lines[i - 1]['base'] > 30), len(lines))
        lines = lines[:k][:len(spec)]
    if page == 1:
        key = re.sub(r'[^a-zA-Zſ]', '', (spec_text.get((page, c)) or ''))[:6]
        while lines and key and key not in re.sub(r'[^a-zA-Zſ]', '', lines[0]['text']):
            lines = lines[1:]
    # (The foot line under the columns: its signature under the first
    # column on a page set across, its catchword under the second.)
    if len(lines) == len(spec) + 1:
        lines = lines[:-1]
    return lines


def run(quiet=False):
    say = (lambda *a: None) if quiet else print
    fit = json.load(open(os.path.join(WORK, 'fit.json')))
    scan = json.load(open(os.path.join(WORK, 'scan.json')))
    pdf = pdf_lines()
    spec_text = first_lines()
    MISMATCHED.clear()
    report = {}
    for page in range(1, 20):
        if str(page) not in scan or page - 1 >= len(pdf):
            continue
        rows = []
        for c in ((1, 2, 3, 4) if page == 19 else (1, 2)):
            spec = [f for f in fit if f['page'] == page and f['col'] == c and isinstance(f['line'], int)]
            lines = column_lines(pdf, page, c, spec, spec_text)
            if len(lines) != len(spec):
                say(f'{page}/{c}: {len(lines)} lines on the PDF, {len(spec)} in the spec')
                MISMATCHED.add((page, c))
            for f, s, p in zip(spec, scan[str(page)][c - 1], lines):
                rows.append((c, f, s, p))
        # (The scan already on the PDF's page, set by its frame.)
        def place(x, y):
            return x, y
        report[page] = {'lines': []}
        for c, f, s, p in rows:
            sl, sb = place(s['left'], s['base'])
            sr, _ = place(s['right'], s['base'])
            report[page]['lines'].append({'col': c, 'line': f['line'], 'block': f['block'], 'kind': f['kind'],
                                          'base': round(p['base'] - sb, 2), 'left': round(p['left'] - sl, 2),
                                          'right': round(p['right'] - sr, 2), 'text': p['text'][:50]})
        d = report[page]['lines']
        say(f"{page}: base off {max(abs(x['base']) for x in d):.1f} (median {statistics.median(x['base'] for x in d):+.2f}); "
            f"left >1.5 {sum(abs(x['left']) > 1.5 for x in d)}, right >1.5 {sum(abs(x['right']) > 1.5 for x in d)} of {len(d)}")
    return report


def main():
    report = run()
    if '--lines' in sys.argv:
        for page, r in report.items():
            for x in r['lines']:
                if abs(x['base']) > 1.5 or abs(x['left']) > 1.5:
                    print(f"{page}/{x['col']}/{x['line']} {x['kind']} base {x['base']:+.1f} left {x['left']:+.1f} right {x['right']:+.1f}  {x['text']}")
    for a in sys.argv:
        if a.startswith('--json='):
            json.dump(report, open(a[7:], 'w'), indent=0)


if __name__ == '__main__':
    main()
