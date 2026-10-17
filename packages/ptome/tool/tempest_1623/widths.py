"""How wide the PDF sets the words against the scan: the median ratio of
each word's width on the PDF to its width on the scan (Tesseract's
boxes of the columns, columns.py's; its sure words of six letters or
more without an f, an l, an s or a long s it might misread), by the
size the PDF sets it in. The type's size goes by it.

    python3 -I widths.py [PDF]
"""
import collections, glob, html, os, re, statistics, subprocess, sys

WORK = os.environ.get('TEMPEST_WORK', os.path.expanduser('~/.cache/asciidart-work/print-match/tempest'))
PDF = sys.argv[1] if len(sys.argv) > 1 else os.path.join(WORK, 'build', 'tempest-folio.pdf')
PT = 0.24
scan = collections.defaultdict(list)
for path in glob.glob(os.path.join(WORK, 'cols', '*.hocr')):
    s = open(path, encoding='utf-8').read()
    for m in re.finditer(r"class='ocrx_word'[^>]*title='bbox (\d+) (\d+) (\d+) (\d+); x_wconf (\d+)'[^>]*>(.*?)</span>", s):
        x0, y0, x1, y1, conf = map(int, m.groups()[:5])
        t = html.unescape(re.sub('<[^>]+>', '', m.group(6)))
        if conf >= 85 and len(t) >= 6 and t.isalpha() and not set(t) & set('flsſ'):
            scan[t].append((x1 - x0) * PT)
out = subprocess.run(['pdftotext', '-bbox-layout', PDF, '-'], capture_output=True, text=True, check=True).stdout
by = collections.defaultdict(list)
for m in re.finditer(r'<word xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" yMax="([\d.]+)">(.*?)</word>', out):
    x0, y0, x1, y1 = map(float, m.groups()[:4])
    t = html.unescape(m.group(5)).strip('.,;:?!')
    if t in scan:
        size = round((y1 - y0) / 1.2, 1)
        by[size].append((x1 - x0) / statistics.median(scan[t]))
for size, v in sorted(by.items()):
    if len(v) >= 5:
        print(f'box {size}: {statistics.median(v):.3f} ({len(v)})')
