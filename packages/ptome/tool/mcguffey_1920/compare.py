"""Each printed page against the PDF's page of its number: every line the
scan's OCR reads on it (its words, roughly: the OCR's own errors aside)
found on the PDF's page, near its baseline; its first and last lines the
PDF page's first and last.

    python3 -I compare.py [--lines]
"""
import difflib, json, re, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fit import pdf_lines, core, WORK
from build import offsets_of

B = json.load(open(f'{WORK}/mcguffey/out/blocks.json'))
offsets = offsets_of(B)
pages = pdf_lines()
detail = '--lines' in sys.argv
bad_pages = 0
for page in range(1, 49):
    leaf = str(page + 4)
    off = offsets.get(page, -1.0)
    scan = [l for l in B[leaf]['lines']
            if not (l['base'] < 40 and re.search(r'ECLECTIC|SECOND|PREFACE|CONTENTS|^\d+$', l['t']))
            and len(core(l['t'])) >= 4]
    pdf = [l for l in pages[page - 1] if l['y0'] > 36 and not re.fullmatch(r'\(?[ivx\d]+\)?|2, \d+\.', l['t'].strip())]
    used = set()
    misses = []
    offs = []
    for l in scan:
        want = core(l['t'])
        best, score = None, 0
        for n, p in enumerate(pdf):
            if n in used:
                continue
            r = difflib.SequenceMatcher(None, want, core(p['t'])).ratio()
            if r > score:
                best, score = n, r
        if best is not None and score >= 0.6:
            used.add(best)
            p = pdf[best]
            base = p['y0'] + (p['y1'] - p['y0']) * 0.7313
            offs.append(base - (l['base'] + off))
        else:
            misses.append(l['t'][:50])
    extra = [pdf[n]['t'][:50] for n in range(len(pdf)) if n not in used]
    first_ok = bool(scan and pdf) and difflib.SequenceMatcher(None, core(scan[0]['t']), core(pdf[0]['t'])).ratio() >= 0.6
    last_ok = bool(scan and pdf) and difflib.SequenceMatcher(None, core(scan[-1]['t']), core(pdf[-1]['t'])).ratio() >= 0.6
    worst = max((abs(o) for o in offs), default=0)
    flag = 'ok ' if first_ok and last_ok and not misses else 'BAD'
    if flag == 'BAD':
        bad_pages += 1
    if detail or flag == 'BAD':
        print(f'{flag} p.{page:2d}: {len(scan)} scan lines, {len(pdf)} pdf lines, worst offset {worst:.1f} pt'
              + ('' if first_ok else f' | first {scan[0]["t"][:25]!r} / {pdf[0]["t"][:25]!r}' if scan and pdf else '')
              + ('' if last_ok else f' | last {scan[-1]["t"][:25]!r} / {pdf[-1]["t"][:25]!r}' if scan and pdf else ''))
        for m in misses[:6]:
            print(f'      unmatched scan line: {m!r}')
print(f'{48 - bad_pages} of 48 pages agree (by the OCR, roughly)')
