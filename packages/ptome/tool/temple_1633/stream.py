"""The TCP lines as one stream, aligned with the scan's OCR lines leaf by
leaf (a banded alignment, each leaf against the stream from where the
last left off): each TCP line's leaf and OCR line, or none.

    python3 -I stream.py  -> stream.json
"""
import difflib, json, os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from align import P, pages, norm

LEAVES = [0, 2, 3, 4, 6] + list(range(8, 200)) + [200, 201, 202, 203]
stream = []
for n, facs, lines in pages:
    for kind, t in lines:
        stream.append(dict(page=n, kind=kind, t=t))


def sim(a, b):
    if not a or not b:
        return 0.0
    return difflib.SequenceMatcher(None, a, b, autojunk=False).ratio()


ptr = 0
out = []
for leaf in LEAVES:
    ocr = [(i, ' '.join(w['t'] for w in l['w']), l['b']) for i, l in enumerate(P[leaf]['lines'])]
    ocr = [o for o in ocr if len(norm(o[1])) >= 2]
    win = stream[ptr:ptr + len(ocr) + 25]
    A = [norm(s['t']) for s in win]
    B = [norm(o[1]) for o in ocr]
    n, m = len(A), len(B)
    GAP = -0.25
    S = [[0.0] * (m + 1) for _ in range(n + 1)]
    T = [[None] * (m + 1) for _ in range(n + 1)]
    for i in range(1, n + 1):
        S[i][0] = S[i - 1][0] + GAP * 2   # (skipping stream lines costs: they belong to this leaf)
        T[i][0] = 'u'
    for j in range(1, m + 1):
        S[0][j] = S[0][j - 1] + GAP * 0.5  # (OCR noise lines are cheap to skip)
        T[0][j] = 'l'
    for i in range(1, n + 1):
        for j in range(1, m + 1):
            d = S[i - 1][j - 1] + sim(A[i - 1], B[j - 1]) * 2 - 0.8
            u = S[i - 1][j] + GAP
            l = S[i][j - 1] + GAP * 0.5
            S[i][j], T[i][j] = max((d, 'd'), (u, 'u'), (l, 'l'))
    # (The leaf ends where the alignment scores best: the stream's lines
    # past it the next leaf's.)
    end = max(range(n + 1), key=lambda i: S[i][m])
    i, j = end, m
    pairs = []
    while i > 0 or j > 0:
        t = T[i][j]
        if t == 'd':
            pairs.append((i - 1, j - 1)); i -= 1; j -= 1
        elif t == 'u':
            pairs.append((i - 1, None)); i -= 1
        else:
            pairs.append((None, j - 1)); j -= 1
    pairs.reverse()
    for a, b in pairs:
        rec = dict(leaf=leaf)
        if a is not None:
            rec.update(s=ptr + a, t=win[a]['t'], kind=win[a]['kind'], tcp_page=win[a]['page'])
        if b is not None:
            rec.update(ocr=ocr[b][1], line=ocr[b][0], box=ocr[b][2])
        if a is not None and b is not None:
            rec['score'] = round(sim(A[a], B[b]), 3)
        out.append(rec)
    ptr += end
json.dump(out, open('stream.json', 'w'), ensure_ascii=False)
print('stream', len(stream), 'used', ptr)
