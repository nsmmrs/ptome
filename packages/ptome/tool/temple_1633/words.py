"""Each TCP word on the scan: aligned with the OCR's words leaf by leaf
(the TCP's leaf, its neighbours' words allowed past the page's ends),
each word given the OCR line it is printed on and its box; a word the
OCR divides at a line's end (`in-` and `hance`) joined, where it divides
it kept.

    python3 -I words.py  -> placed.json
"""
import difflib, json, os, re, sys, unicodedata
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tcp2

W = os.path.join(os.environ.get('TEMPLE_WORK', os.path.expanduser('~/.cache/asciidart-work/print-match')), 'herbert')
P = json.load(open(f'{W}/ocr.json'))


def norm(t):
    t = unicodedata.normalize('NFKD', t)
    t = t.replace('ſ', 's').replace('ﬁ', 'fi').replace('ﬂ', 'fl').replace('æ', 'ae').replace('œ', 'oe')
    t = re.sub(r'[^A-Za-z]', '', t).lower()
    return t.replace('f', 's').replace('c', 'e').replace('rn', 'm').replace('vv', 'w').replace('u', 'v')


def segment(leaf):
    """The leaf's lines: the OCR's, which follow a skewed page's lines,
    but those of twice a line's height or more (a short line run into
    the next, beside an initial) split by their words' places."""
    raw = []
    for l in P[leaf]['lines']:
        ws = [dict(t=w['t'], box=w['b']) for w in l['w'] if norm(w['t']) or re.search(r'[\w¶]', w['t'])]
        if ws:
            raw.append((l['b'], ws))
    if not raw:
        return []
    hs = sorted(b[3] - b[1] for b, _ in raw)
    typical = hs[len(hs) // 2]
    lines = []
    for b, ws in raw:
        if b[3] - b[1] < 1.6 * typical or len(ws) < 2:
            lines.append(dict(yc=(b[1] + b[3]) / 2, w=sorted(ws, key=lambda w: w['box'][0])))
            continue
        for w in ws:
            x0, y0, x1, y1 = w['box']
            w['yc'] = (y0 + y1) / 2 if y1 - y0 < 1.5 * typical else y1 - typical / 2
        ws.sort(key=lambda w: w['yc'])
        parts = []
        for w in ws:
            if parts and abs(w['yc'] - parts[-1]['yc']) < typical * 0.45:
                parts[-1]['w'].append(w)
            else:
                parts.append(dict(yc=w['yc'], w=[w]))
        for part in parts:
            part['w'].sort(key=lambda w: w['box'][0])
            lines.append(part)
    lines.sort(key=lambda l: l['yc'])
    return lines


LINES = {}


def lines_of(leaf):
    if leaf not in LINES:
        LINES[leaf] = segment(leaf)
    return LINES[leaf]


def furniture(leaf, lines):
    """The leaf's lines that are no text of the book's: its running head
    (or folio), its catchword and signature at the foot."""
    skip = set()
    if not lines:
        return skip
    first = ' '.join(w['t'] for w in lines[0]['w'])
    if re.search(r'(?i)ch[uv]r|porch|milit|^\W*\d+\W*$', first) or len(norm(first)) <= 3:
        skip.add(0)
    # (The foot: a line of a word or two at the right, or a signature.)
    xs = [w['box'][0] for l in lines for w in l['w']]
    right = max((w['box'][2] for l in lines for w in l['w']), default=0)
    left = min(xs, default=0)
    last = lines[-1]['w']
    if len(last) <= 3 and last[0]['box'][0] > left + 0.45 * (right - left):
        skip.add(len(lines) - 1)
    return skip


def ocr_words(leaf):
    out = []
    lines = lines_of(leaf)
    skip = furniture(leaf, lines)
    for li, l in enumerate(lines):
        if li in skip:
            continue
        for wi, w in enumerate(l['w']):
            if norm(w['t']):
                out.append(dict(line=li, t=w['t'], box=w['box']))
    # (A word divided at a line's end: one, its pieces' places kept.)
    merged = []
    k = 0
    while k < len(out):
        o = out[k]
        if o['t'].endswith('-') and k + 1 < len(out) and out[k + 1]['line'] != o['line']:
            n = out[k + 1]
            merged.append(dict(line=o['line'], t=o['t'][:-1] + n['t'], box=o['box'],
                               split=norm(o['t']), line2=n['line'], box2=n['box']))
            k += 2
            continue
        merged.append(o)
        k += 1
    return merged


def main():
    recs = tcp2.records(f'{W}/A03058.xml')
    words = []  # (rec, word index, norm)
    for ri, r in enumerate(recs):
        for wi, w in enumerate(r['words']):
            words.append((ri, wi, norm(''.join(p for p, _ in w)), r['leaf']))
    placed = {}
    ptr = 0
    leaves = sorted({r['leaf'] for r in recs if r['leaf'] is not None})
    for leaf in leaves:
        own = [k for k, w in enumerate(words) if w[3] == leaf]
        if not own:
            continue
        lo = max(ptr, own[0] - 40)
        hi = min(len(words), own[-1] + 40)
        win = words[lo:hi]
        ocr = ocr_words(leaf)
        a = [w[2] for w in win]
        b = [norm(o['t']) for o in ocr]
        sm = difflib.SequenceMatcher(None, a, b, autojunk=False)
        last = None
        for tag, i1, i2, j1, j2 in sm.get_opcodes():
            if tag == 'equal' or (tag == 'replace' and i2 - i1 == j2 - j1):
                for k in range(i2 - i1):
                    gi = lo + i1 + k
                    # (A word outside its own page placed there only when
                    # matched exactly: a page's end belongs to its page.)
                    # (And then only in a run of three or more: a common
                    # word alone is no page's end.)
                    if words[gi][3] != leaf and (tag != 'equal' or i2 - i1 < 3):
                        continue
                    if gi in placed:
                        continue
                    placed[gi] = dict(leaf=leaf, **ocr[j1 + k], exact=tag == 'equal')
                    last = gi
            elif tag == 'replace':
                # (Unequal runs: each TCP word with the OCR word in its
                # proportion of the run, its line; its own page's only.)
                for k in range(i2 - i1):
                    gi = lo + i1 + k
                    if words[gi][3] != leaf or gi in placed:
                        continue
                    j = j1 + min(j2 - j1 - 1, int(k * (j2 - j1) / (i2 - i1)))
                    o = dict(ocr[j]); o.pop('split', None)
                    placed[gi] = dict(leaf=leaf, **o, exact=False, approx=True)
                    last = gi
        if last is not None:
            ptr = max(ptr, last + 1)
    # (Words the OCR missed: the line of the word before them in their
    # record, else after.)
    out = []
    for gi, (ri, wi, nm, leaf) in enumerate(words):
        p = placed.get(gi)
        out.append(dict(rec=ri, word=wi, leaf=leaf, place=p))
    json.dump(dict(words=out, lines={str(k): [dict(yc=l['yc'], words=[dict(t=w['t'], box=w['box']) for w in l['w']])
                                              for l in v] for k, v in LINES.items()}),
              open('placed.json', 'w'), ensure_ascii=False)
    n = len(words); m = len(placed); ex = sum(1 for p in placed.values() if p.get('exact'))
    print(f'{n} words, {m} placed ({ex} exactly), {n - m} not')


if __name__ == '__main__':
    main()
