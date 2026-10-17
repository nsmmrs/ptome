"""The scan's leaves in the book's order, each printed page once: the
Bayerische Staatsbibliothek's copy has a run of pages bound in twice
(and a leaf of the first chapter's), and the Internet Archive scanned
them all. Each leaf's printed page number read off its head (ABBYY's
OCR, ocr.json), a leaf whose first lines are a leaf's already kept left
out. Written to TRISTRAM_WORK/leaves.json: [[leaf, page or a name]].

    python3 -I leaves.py
"""
import difflib, json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from common import WORK

# (The leaves before the text: the frontispiece, the title page, the
# dedication; after it the scan's last leaves, blank and the library's.)
FRONT = [(7, 'frontispiece'), (8, 'title'), (10, 'dedication-1'), (11, 'dedication-2')]
FIRST, LAST = 12, 290
# (The leaves bound in twice, the scan's second copies: pages 14 to 17 again
# (leaves 29 to 32), pages 138 to 153 and 130 to 159 again (leaves 177 to
# 222), as their heads and their first lines read.)
TWICE = set(range(29, 33)) | set(range(177, 223))


def key(t):
    return re.sub(r'[^a-z]', '', t.lower().replace('f', 's'))


def number(lines):
    """The page number its head reads, or None: digits in brackets, alone."""
    for l in lines[:2]:
        t = l.replace(' ', '')
        m = re.fullmatch(r'[^\w]*[({\[]?(\d{1,3})[)}\]]?[^\w]*', t)
        if m and len(t) < 12:
            return int(m.group(1))
    return None


def main():
    ocr = json.load(open(os.path.join(WORK, 'ocr.json')))
    text = {leaf: [' '.join(w['t'] for w in l['w']) for l in ocr[leaf]['lines']] for leaf in range(FIRST, LAST + 1)}
    read = {leaf: number(text[leaf]) for leaf in text}
    # (A leaf bound in twice: its text a leaf's before it.)
    seen, dup = [], set()
    for leaf in range(FIRST, LAST + 1):
        body = key(' '.join(text[leaf][1:7]))
        if leaf in TWICE or len(body) > 80 and any(difflib.SequenceMatcher(None, body, s, autojunk=False).ratio() > 0.85 for s in seen[-40:]):
            dup.add(leaf)
            continue
        seen.append(body)
    # (The leaves left, the pages in order: each its place.)
    kept = [(leaf, n) for n, leaf in enumerate([l for l in range(FIRST, LAST + 1) if l not in dup], 1)]
    have = {n for _, n in kept}
    off = [(leaf, n, read[leaf]) for leaf, n in kept if read[leaf] is not None and read[leaf] != n]
    print('heads read otherwise:', off)
    missing = [n for n in range(1, max(have) + 1) if n not in have]
    order = [n for _, n in kept]
    json.dump(FRONT + kept, open(os.path.join(WORK, 'leaves.json'), 'w'))
    print(len(kept), 'pages; missing', missing, '; out of order', [(a, b) for a, b in zip(order, order[1:]) if b != a + 1])


main()
