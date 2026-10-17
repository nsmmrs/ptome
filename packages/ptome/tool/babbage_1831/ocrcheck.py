"""The figures of each row on the scan (Tesseract's, the columns read run
together) against the computed table's, row by row: a row whose figures
differ beyond a misread small figure or two (the marked first figures
Tesseract reads as others) is listed. A check that the logarithms, the
whole entries where the first three figures change and the rows of each
page are the printing's.

    python3 -I ocrcheck.py [PAGE...]
"""
import difflib, json, os, re, subprocess, sys
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from common import FOOT_RULE, HEAD_RULE, WORK

PAGES = [int(a) for a in sys.argv[1:]] or list(range(6, 26))
SRC = os.path.join(HERE, '..', '..', 'test', 'showcase', 'babbage', 'text', 'pages.adoc')


def computed(page):
    """The page's rows' figures run together, from pages.adoc."""
    text = open(SRC, encoding='utf-8').read()
    part = text.split(f'// page {page}\n', 1)[1].split('// page ', 1)[0]
    rows = []
    for line in part.split('\n'):
        if line.startswith('|') and ('[.num]' in line):
            cells = line.split("|")[4:14]
            rows.append(''.join(re.sub(r'\[[^]]*\]|[^0-9]', '', c) for c in cells))
    return rows


def main():
    frames = json.load(open(os.path.join(WORK, 'frame.json')))
    os.makedirs(os.path.join(WORK, 'ocr'), exist_ok=True)
    bad = 0
    for page in PAGES:
        n = page + 24
        f = frames[str(n)]
        k = (f['foot'] - f['head']) / (FOOT_RULE - HEAD_RULE)
        im = Image.open(os.path.join(WORK, 'upright', f'n{n}.png'))
        base = os.path.join(WORK, 'ocr', f'n{n}')
        im.crop((int(f['thick'] + 28 * k), int(f['head'] + 4 * k), int(f['thick'] + 291 * k), int(f['foot'] - k))).save(base + '.png')
        subprocess.run(['tesseract', base + '.png', base, '--psm', '6', '-c', 'tessedit_char_whitelist=0123456789'],
                       check=True, capture_output=True)
        ocr = [l.strip() for l in open(base + '.txt') if l.strip()]
        want = computed(page)
        # (Each computed row with the OCR's line most like it, in order.)
        sm = difflib.SequenceMatcher(None, [w[:12] for w in want], [o[:12] for o in ocr], autojunk=False)
        worst = []
        j = 0
        for i, w in enumerate(want):
            cands = ocr[max(0, j - 2):j + 4]
            o = max(cands, key=lambda o: difflib.SequenceMatcher(None, w, o).ratio(), default='')
            if o in ocr:
                j = ocr.index(o) + 1
            r = difflib.SequenceMatcher(None, w, o).ratio()
            if r < 0.93 or abs(len(w) - len(o)) >= 3:
                worst.append((i, round(r, 2), w, o))
        bad += len(worst)
        print(f'{page}: {len(want)} rows, {len(ocr)} lines read; {len(worst)} unlike')
        for i, r, w, o in worst:
            print(f'   row {i}: {r}  computed {w}\n            read     {o}')
    print('rows unlike in all:', bad)


main()
