"""How wide the PDF sets the words and the lines it doesn't justify
against the scan: the median ratio of each word's width on the PDF to
its width on the scan (Tesseract's boxes, its sure words of seven
letters or more without an f, an l or a long s that it might misread),
and of each unjustified line's (a verse line's, a paragraph's last,
without an author). The type's size goes by the first, the spaces
between the words by the second.

    python3 -I widths.py [PDF]
"""
import collections, html, json, os, re, statistics, subprocess, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import compare

WORK = compare.WORK
PDF = compare.PDF


def hocr_words(page):
    s = open(os.path.join(WORK, f'{page:04d}.hocr'), encoding='utf-8').read()
    for m in re.finditer(r"class='ocrx_word'[^>]*title='bbox (\d+) (\d+) (\d+) (\d+); x_wconf (\d+)'[^>]*>(.*?)</span>", s):
        x0, y0, x1, y1, conf = map(int, m.groups()[:5])
        if conf > 85:
            yield html.unescape(re.sub('<[^>]+>', '', m.group(6))), (x1 - x0) * compare.PT if hasattr(compare, 'PT') else (x1 - x0) * 0.24


out = subprocess.run(['pdftotext', '-bbox-layout', PDF, '-'], capture_output=True, text=True, check=True).stdout
pdf_words = collections.defaultdict(list)
for m in re.finditer(r'<word xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" yMax="([\d.]+)">(.*?)</word>', out):
    pdf_words[html.unescape(m.group(5))].append(float(m.group(3)) - float(m.group(1)))
words = [statistics.median(pdf_words[t]) / w
         for p in compare.PAGES for t, w in hocr_words(p)
         if len(t) >= 7 and t.isalpha() and not set(t) & set('flſ') and t in pdf_words]

fit = json.load(open(os.path.join(compare.WORK, 'fit.json')))
scan = json.load(open(os.path.join(WORK, 'scan.json')))
pdf = compare.pdf_lines()
lines = []
for pi, page in enumerate(compare.PAGES):
    for c in (1, 2):
        spec = [(i, f) for i, f in enumerate(fit) if f['page'] == page and f['column'] == c and isinstance(f['line'], int)]
        for (i, f), s, p in zip(spec, scan[str(page)][c - 1], pdf[pi][c - 1]):
            last = i + 1 == len(fit) or fit[i + 1]['block'] != f['block']
            if (f['kind'] == 'V' or last) and not f['author'] and s['right'] - s['left'] > 120:
                lines.append((p['right'] - p['left']) / (s['right'] - s['left']))
print(f'words {statistics.median(words):.4f} ({len(words)}); unjustified lines {statistics.median(lines):.4f} ({len(lines)})')
