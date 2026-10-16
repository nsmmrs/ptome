"""The TCP text (the first edition, A03058) against the scan's OCR (the
second edition), page by page: each TCP line paired with an OCR line,
the pairs whose words differ beyond the OCR's usual misreadings listed.

    python3 -I align.py > diffs.txt
"""
import difflib, json, re, sys, os, unicodedata
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tcp

W = os.path.join(os.environ.get('TEMPLE_WORK', os.path.expanduser('~/.cache/asciidart-work/print-match')), 'herbert')
P = json.load(open(f'{W}/ocr.json'))
pages = tcp.pages(f'{W}/A03058.xml')


def norm(t):
    t = unicodedata.normalize('NFKD', t)
    t = t.replace('ſ', 's').replace('ﬁ', 'fi').replace('ﬂ', 'fl').replace('æ', 'ae').replace('œ', 'oe')
    t = re.sub(r'[^A-Za-z&]', '', t).lower()
    # (The OCR's usual misreadings: long s as f, c as e, rn as m...)
    return t.replace('f', 's').replace('c', 'e').replace('rn', 'm').replace('vv', 'w').replace('u', 'v')


def ocr_lines(leaf):
    out = []
    for l in P[leaf]['lines']:
        t = ' '.join(w['t'] for w in l['w'])
        if len(norm(t)) >= 2:
            out.append((l['b'], t))
    return out


def main():
    # TCP pages to leaves: numbered pages at leaf = n + 7; the front matter by order.
    tcp_pages = [(p[0], p[2]) for p in pages]
    front_leaves = [0, 2, 3, 4, 6]
    fi = 0
    mapped = []
    for n, lines in tcp_pages:
        if not lines:
            continue
        if n is None or not n.isdigit():
            if fi < len(front_leaves):
                mapped.append((front_leaves[fi], n, lines)); fi += 1
            continue
        mapped.append((int(n) + 7, n, lines))
    total = 0
    flagged = 0
    for leaf, n, lines in mapped:
        o = ocr_lines(leaf)
        a = [norm(t) for _, t in lines]
        b = [norm(t) for _, t in o]
        sm = difflib.SequenceMatcher(None, a, b, autojunk=False)
        for tag, i1, i2, j1, j2 in sm.get_opcodes():
            pass
        # (Each TCP line with its best OCR line, in order.)
        j = 0
        for i, (kind, t) in enumerate(lines):
            total += 1
            best, score, bj = None, 0, j
            for k in range(j, min(len(o), j + 4)):
                r = difflib.SequenceMatcher(None, a[i], b[k]).ratio()
                if r > score:
                    best, score, bj = o[k], r, k
            if best is None:
                print(f'{leaf}\t{n}\tMISSING\t{t}')
                flagged += 1
                continue
            if score < 0.97:
                print(f'{leaf}\t{n}\t{score:.2f}\t{t}\t|\t{best[1]}')
                flagged += 1
            j = bj + 1
    print(f'# {total} lines, {flagged} flagged', file=sys.stderr)


if __name__ == '__main__':
    main()
