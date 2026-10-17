"""Each page's printed lines decided word by word: Standard Ebooks' words
(the showcase's text before this work, `transcription/`) laid on the
lines of the Internet Archive's OCR of the scan (ABBYY's, ocr.json; the
leaves in the book's order, leaves.json), read against each other by
their letters (the long s, which the OCR reads as f, and the round s
the same letter): where they agree, the transcription's word (its
italics, its small capitals, its quotation marks, its dashes) on the
printing's line, divided where the line divides it; where they don't,
both readings kept for review (`⟦ocr|transcription⟧`). A page's head (its
number) and its foot (its signature and catchword) as the OCR reads them.
Written to TRISTRAM_WORK/draft.json: {page: [{box, text, kind, flag}]}.

    python3 -I decide.py
"""
import difflib, json, os, re, sys, unicodedata

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from variant import variant
from common import WORK

TEXT = os.path.join(HERE, 'transcription')
FILES = ['dedication'] + [f'chapter-1-{n}' for n in range(1, 26)] + [f'chapter-2-{n}' for n in range(1, 12)]
ROMAN = ['', 'I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX']
TENS = ['', 'X', 'XX', 'XXX', 'XL']


def roman(n):
    return TENS[n // 10] + ROMAN[n % 10]


def key(t):
    """A word's letters, small, the long s and the round the same, `&`
    and, accents left off."""
    t = t.lower().replace('ſ', 's').replace('f', 's').replace('&', 'and').replace('æ', 'ae').replace('œ', 'oe')
    t = ''.join(c for c in unicodedata.normalize('NFKD', t) if not unicodedata.combining(c))
    return re.sub(r'[^a-z0-9]', '', t)


DASH = re.compile(r'(⁠?[—⸺⸻]+⁠?)')


def words_of(text, marks):
    """[text]'s words, each with its marks ({italic, sc}); a word joined to
    the next by a dash (`doing;—that`) parted after the dash, `glue` so
    that it joins again on one line."""
    out = []
    for tok in text.split():
        parts = [p for p in DASH.split(tok) if p]
        pieces, cur = [], ''
        for p in parts:
            cur += p.replace('⁠', '')
            if DASH.fullmatch(p):
                pieces.append(cur)
                cur = ''
        if cur:
            pieces.append(cur)
        for k, p in enumerate(pieces):
            out.append({'t': p, 'k': key(p), 'glue': k < len(pieces) - 1, **marks})
    return out


def footnotes(s):
    """The spans of [s]'s footnotes (`footnote:[` to its `]`)."""
    out, at = [], 0
    while (a := s.find('footnote:[', at)) >= 0:
        depth, b = 0, a + len('footnote:[')
        while b < len(s) and (s[b] != ']' or depth):
            depth += {'[': 1, ']': -1}.get(s[b], 0)
            b += 1
        out.append((a, b))
        at = b + 1
    return out


def marked(s, kind):
    """[s]'s words with their marks: italic spans `__…__` (roman words in
    them `[.roman]#…#`), small capitals `[.sc]#…#`."""
    out, pos = [], 0
    for m in re.finditer(r'__(.+?)__|\[\.sc\]#+(.+?)#+', s):
        if m.start() > pos:
            out += words_of(s[pos:m.start()], {})
        if m.group(1) is not None:
            q = 0
            for r in re.finditer(r'\[\.(roman|sc)(?:,[^\]]*)?\]#+(.+?)#+', m.group(1)):
                out += words_of(m.group(1)[q:r.start()], {'i': True})
                out += words_of(r.group(2), {} if r.group(1) == 'roman' else {'i': True, 'sc': True})
                q = r.end()
            out += words_of(m.group(1)[q:], {'i': True})
        else:
            out += words_of(m.group(2), {'sc': True})
        pos = m.end()
    out += words_of(s[pos:], {})
    return [dict(w, kind=kind) for w in out]


def tokens():
    """The transcription's words in order, the chapters' heads as the
    printing numbers them (Book II's chapters after Book I's)."""
    out = []
    for f in FILES:
        lines = open(os.path.join(TEXT, f + '.adoc'), encoding='utf-8').read().split('\n')
        for line in lines:
            s = line.strip()
            if not s or s.startswith(('//', 'image::', '<<<', ':')) or re.fullmatch(r'\[[^\]]*\]', s) \
                    or s in ('____', '--'):
                continue
            m = re.match(r'^== Chap\. ([IVXL]+)\.$', s)
            if m:
                n = {roman(k): k for k in range(1, 50)}[m.group(1)]
                if f.startswith('chapter-2'):
                    n += 25
                out += [dict(w, kind='H') for w in words_of(f'CHAP. {roman(n)}.', {})]
                continue
            if s.startswith('== '):
                out += [dict(w, kind='H') for w in words_of(s[3:], {})]
                continue
            s = s.rstrip(' +')
            s = re.sub(r'\[lang=[\w-]+\]#+(.+?)#+', r'\1', s)
            s = re.sub(r'\[lang=[\w-]+\](?=__)', '', s)
            # (The printing's spellings where the transcription
            # modernises: `Hobby-Horse`.)
            s = s.replace('Hobbyhorse', 'Hobby-Horse')
            s = s.replace('&amp;', '&').replace('&#42;', '*').replace('{empty}', '')
            # (A footnote: its words the note's (`N`), a star after the
            # word it hangs on and before its first.)
            pos = 0
            for a, b in footnotes(s):
                out += marked(s[pos:a], 'P')
                out.append({'t': '*', 'k': '', 'kind': 'P'})
                note = marked(s[a + len('footnote:['):b], 'N')
                if note:
                    note[0]['pre'] = '* '
                out += note
                pos = b + 1
            out += marked(s[pos:], 'P')
            out[-1]['end'] = True if out else None
    # (A mark alone (a comma after an italic word, a bracket before one):
    # the word's beside it.)
    res = []
    for k, w in enumerate(out):
        if not w['k'] and res and not re.match(r'^[(\[‘“]', w['t']) and not DASH.fullmatch(w['t']):
            res[-1]['post'] = res[-1].get('post', '') + w['t']
            res[-1]['glue'] = w.get('glue')
            continue
        if not w['k'] and res and DASH.fullmatch(w['t'].replace('\u2060', '')) is not None:
            res[-1]['post'] = res[-1].get('post', '') + w['t']
            res[-1]['glue'] = True
            continue
        if res and res[-1].get('pending'):
            w = dict(w, pre=res.pop()['t'])
        if not w['k'] and re.match(r'^[(\[‘“]', w['t']):
            w = dict(w, pending=True)
        res.append(w)
    return res


def ocr_words(pages):
    """The pages' text lines' words in order (heads and feet left out),
    each its page and line; a word a line divides at its end (`-`)
    joined with its rest on the next line, the next page's first the
    last's. A footnote's lines read on: the next page's lines of it
    after this page's, before the next page's text, as the transcription
    has it."""
    order, done = [], set()
    for pi, p in enumerate(pages):
        for li, l in enumerate(p['lines']):
            if (pi, li) in done:
                continue
            order.append((pi, li))
            last_note = l.get('note') and all(not x.get('note') for x in p['lines'][li + 1:])
            q = pi + 1
            while last_note and q < len(pages):
                more = [(q, k) for k, x in enumerate(pages[q]['lines']) if x.get('note')]
                if not more or pages[q]['lines'][more[0][1]]['w'][0]['t'].startswith(('*', '†')):
                    break
                order += more
                done |= set(more)
                q += 1
    stream = []
    for pi, li in order:
        l = pages[pi]['lines'][li]
        for w in l['w']:
            t = w['t']
            if not re.search(r'[A-Za-z0-9&]', t):
                continue
            stream.append({'line': li, 't': t, 'k': key(t), 'pi': pi, 'c': w.get('c') or 0,
                           'note': bool(l.get('note')), 'b': w['b']})
    out = []
    for s in stream:
        prev = out[-1] if out else None
        last = prev['parts'][-1] if prev else None
        if last and (last['pi'], last['line']) != (s['pi'], s['line']) and last['note'] == s['note'] \
                and re.search(r'[^\W\d_][-=~¬+–‐][.,]?$', last['t']):
            prev['parts'].append(s)
            prev['k'] += s['k']
            continue
        out.append({'parts': [s], 'k': s['k']})
    for o in out:
        o['t'] = ''.join(p['t'] for p in o['parts'])
        o['c'] = min(p['c'] for p in o['parts'])
    return out


VOCAB = set()


def vocabulary():
    words = set()
    for f in os.listdir(TEXT):
        words |= {w.lower() for w in re.findall(r"[A-Za-z’']+", open(os.path.join(TEXT, f), encoding='utf-8').read())}
    for path in ('/usr/share/dict/words', '/usr/share/dict/cracklib-small'):
        if os.path.exists(path):
            words |= {w.strip().lower() for w in open(path, encoding='utf-8', errors='ignore')}
    words |= {'tho’', 'thro’', '&c', 'shew', 'chuse', 'compleat', 'shewn', 'shewed', 'shews'}
    return {w.replace("'", '’') for w in words}


def long_s(t, prefer=None):
    """The OCR's word with its long s's read: each f that, read as s,
    makes a word of the vocabulary (or [prefer]'s letters)."""
    import itertools
    core = re.sub(r'^[^A-Za-z]*|[^A-Za-z’\']*$', '', t)
    if not core:
        return t
    at = [i for i, c in enumerate(core) if c == 'f'][:4]
    best = None
    for n in range(len(at) + 1):
        for pick in itertools.combinations(at, n):
            v = ''.join('s' if i in pick else c for i, c in enumerate(core))
            if prefer and v.lower() == prefer.lower():
                return t.replace(core, v)
            if best is None and v.lower().replace("'", '’') in VOCAB:
                best = v
    return t.replace(core, best) if best else t


def reconcile(s, tok, other=None):
    """The transcription's word as the printing has it where the OCR reads
    it surely: its own hyphen inside it (`pocket-book`), its capitals
    (`Lady-Day`), its stop after it (a comma, a full stop, a semicolon
    the transcription lacks or has otherwise, the other OCR's word [other]
    with it too)."""
    t = tok['t']
    o = s['t'].replace('ſ', 's')
    if re.fullmatch(r'&[,.;:]?', o) and tok['k'] == 'and':
        return dict(tok, t='&' + t[3:] if t.lower().startswith('and') else '&')
    if s['c'] < 80 or len(s['parts']) > 1:
        return tok
    letters = lambda x: re.sub(r'[^A-Za-z]', '', x)
    # (Inner hyphens and capitals: the OCR's, its letters the same.)
    ob = re.sub(r'^[^A-Za-z]*|[^A-Za-z]*$', '', o)
    tb = re.sub(r'^[^A-Za-z’]*|[^A-Za-z’]*$', '', t)
    if key(ob) == key(tb) and ob and tb:
        if '-' in ob and '-' not in tb and "’" not in tb:
            nb, k = '', 0
            for ch in ob:
                if ch == '-':
                    nb += '-'
                else:
                    nb += tb[k] if k < len(tb) else ''
                    k += 1
            t = t.replace(tb, nb, 1)
            tb = nb
        if letters(ob).lower() == letters(tb).lower().replace('f', 's') or key(ob) == key(tb):
            cap = ''.join((c2.upper() if c1.isupper() else c2.lower()) if c2.isalpha() else c2
                          for c1, c2 in zip(re.sub(r'[’]', '', ob) if len(re.sub(r'[’]', '', ob)) == len(tb) else tb, tb))
            if len(cap) == len(tb):
                t = t.replace(tb, cap, 1)
    # (The stop after it: in the word's text, or after its marks.)
    post = tok.get('post', '')
    whole = t + post
    ostop = re.search(r'[,.;:!?]$', re.sub(r'[\s’”»\)]+$', '', o))
    if ostop and (other is None or not re.sub(r'[\s’”»\)]+$', '', other).endswith(ostop.group(0))):
        ostop = None
    tstop = re.search(r'[,.;:!?]$', re.sub(r'[\s’”\)—⸺⸻]+$', '', whole))
    if ostop and not tstop and not tok.get('glue') and not whole.endswith(('—', '⸺', '⸻')):
        if post:
            post = ostop.group(0) + post
        else:
            m = re.search(r'([’”)]*)$', t)
            t = t[:m.start()] + ostop.group(0) + t[m.start():]
    elif ostop and tstop and ostop.group(0) != tstop.group(0) and ostop.group(0) in ',;:.':
        if tstop.start() >= len(t):
            i = tstop.start() - len(t)
            post = post[:i] + ostop.group(0) + post[i + 1:]
        else:
            t = t[:tstop.start()] + ostop.group(0) + t[tstop.end():]
    return dict(tok, t=t, post=post)


def local_align(ss, tt):
    """The OCR's words [ss] and the transcription's [tt] paired by their
    letters: groups of up to three on either side whose letters run alike,
    a word alone where none fits; [(ocr indices, transcription indices)]."""
    n, m = len(ss), len(tt)
    INF = float('inf')
    D = [[INF] * (m + 1) for _ in range(n + 1)]
    B = [[None] * (m + 1) for _ in range(n + 1)]
    D[0][0] = 0
    for i in range(n + 1):
        for j in range(m + 1):
            if D[i][j] == INF:
                continue
            for a in range(0, 4):
                for b in range(0, 4):
                    if a + b == 0 or i + a > n or j + b > m:
                        continue
                    if a and b:
                        x = ''.join(s['k'] for s in ss[i:i + a])
                        y = ''.join(t['k'] for t in tt[j:j + b])
                        r = difflib.SequenceMatcher(None, x, y).ratio() if x or y else 1
                        cost = (1 - r) * (a + b) + 0.05 * (a + b - 2)
                        if x == y:
                            cost = 0.01 * (a + b - 2)
                    elif a == 0:
                        cost = 0.9 if any(t['k'] for t in tt[j:j + b]) else 0.05
                        if b > 1:
                            continue
                    else:
                        cost = 0.9
                        if a > 1:
                            continue
                    if D[i][j] + cost < D[i + a][j + b]:
                        D[i + a][j + b] = D[i][j] + cost
                        B[i + a][j + b] = (i, j)
    out, i, j = [], n, m
    while (i, j) != (0, 0):
        pi, pj = B[i][j]
        out.append((list(range(pi, i)), list(range(pj, j))))
        i, j = pi, pj
    return out[::-1]


# (The black pages: the printing's two pages of ink, no text.)
BLACK = (67, 68)


def hand_parts(path):
    """A page the OCR cannot read (its paper tinted) or a page of titles,
    read from the scan by hand (pages/PAGE.txt: a line its spec's kind
    before `|` where it is not a line going on, `@foot` the foot, `@rule`
    a rule, `h|` a running title): its lines as an OCR's, sure, each its
    row as written (`raw`)."""
    body, foot = [], None
    for k, row in enumerate(open(path, encoding='utf-8').read().splitlines()):
        if row.startswith('@rule') or row.startswith('h|'):
            continue
        text = re.sub(r'^[^|\s]+(?: \S+)?\|', '', row.removeprefix('@foot ')).replace(' | ', ' ')
        bare = re.sub(r'\[\.\w+\]#+|#+|__', '', text).replace('{shy}', '-').replace('{zwsp}', '')
        ws = [{'t': t, 'b': [0, k, 0, k], 'c': 100} for t in bare.split()]
        if row.startswith('@foot '):
            foot = {'b': [0, k, 0, k], 'w': ws}
        else:
            body.append({'b': [0, k, 0, k], 'w': ws, 'hand': True, 'raw': row})
    return None, body, foot


def page_parts(ocr, leaf):
    """A leaf's head (its number), its text lines, its foot (signature and
    catchword: a last line of a word or two, or one far to the right)."""
    text = lambda l: ' '.join(w['t'] for w in l['w'])
    # (The OCR's lines in order down the page, two on one printed line
    # (the OCR parted it) one.)
    # (A line the OCR made of two printed lines, its words at two heights:
    # parted by its words' middles.)
    # (The OCR's specks and rules left out: a line's box its words'.)
    # (Specks: words in the margins, or low and unsure.)
    every = [w for l in ocr[leaf]['lines'] for w in l['w'] if re.search(r'[A-Za-z0-9&]', w['t'])]
    if len(every) > 20:
        ls_ = sorted(w['b'][0] for w in every)
        rs_ = sorted(w['b'][2] for w in every)
        hs_ = sorted(w['b'][3] - w['b'][1] for w in every)
        left, right, tall = ls_[len(ls_) // 10], rs_[len(rs_) * 9 // 10], hs_[len(hs_) // 2]
    else:
        left, right, tall = -1e9, 1e9, 0
    speck = lambda w: w['b'][2] < left - 15 or w['b'][0] > right + 15 \
        or (w.get('c') or 0) < 60 and w['b'][3] - w['b'][1] < 0.4 * tall
    src = []
    for l in ocr[leaf]['lines']:
        ws = [w for w in l['w'] if re.search(r'[A-Za-z0-9&]', w['t']) and not speck(w)]
        if ws:
            src.append({'b': [min(w['b'][0] for w in ws), min(w['b'][1] for w in ws),
                              max(w['b'][2] for w in ws), max(w['b'][3] for w in ws)], 'w': ws})
    hs = sorted(l['b'][3] - l['b'][1] for l in src) or [40]
    med = hs[len(hs) // 2]
    parted = []
    for l in src:
        if l['b'][3] - l['b'][1] > 1.5 * med and len(l['w']) > 1:
            rows = []
            for w in sorted(l['w'], key=lambda w: (w['b'][1] + w['b'][3]) / 2):
                c = (w['b'][1] + w['b'][3]) / 2
                if rows and abs(c - rows[-1]['c']) < 0.45 * med:
                    rows[-1]['w'].append(w)
                    rows[-1]['c'] = sum((x['b'][1] + x['b'][3]) / 2 for x in rows[-1]['w']) / len(rows[-1]['w'])
                else:
                    rows.append({'c': c, 'w': [w]})
            for r in rows:
                ws = sorted(r['w'], key=lambda w: w['b'][0])
                parted.append({'b': [min(w['b'][0] for w in ws), min(w['b'][1] for w in ws),
                                     max(w['b'][2] for w in ws), max(w['b'][3] for w in ws)], 'w': ws})
        else:
            parted.append(l)
    # (A line's rows its words' middle top and bottom: an initial beside
    # it, two lines high, not of it.)
    def core(l):
        ts = sorted(w['b'][1] for w in l['w'])
        bs = sorted(w['b'][3] for w in l['w'])
        return ts[len(ts) // 2], bs[len(bs) // 2]
    lines = sorted(parted, key=lambda l: sum(core(l)) / 2)
    merged = []
    for l in lines:
        if merged:
            m = merged[-1]
            (mt, mb), (lt, lb) = core(m), core(l)
            ov = min(mb, lb) - max(mt, lt)
            if ov > 0.5 * min(mb - mt, lb - lt):
                ws = sorted(m['w'] + l['w'], key=lambda w: w['b'][0])
                merged[-1] = {'b': [min(m['b'][0], l['b'][0]), min(m['b'][1], l['b'][1]),
                                    max(m['b'][2], l['b'][2]), max(m['b'][3], l['b'][3])], 'w': ws}
                continue
        merged.append(l)
    lines = merged
    # (The head: a short line over the text, about the page's middle.)
    # (Specks over it, a line or two short and set apart, left out.)
    head = None
    if len(lines) > 3:
        wide = max(l['b'][2] for l in lines) - min(l['b'][0] for l in lines)
        mid = (max(l['b'][2] for l in lines) + min(l['b'][0] for l in lines)) / 2
        mids = [sum(core(l)) / 2 for l in lines]
        pitch = sorted(b - a for a, b in zip(mids, mids[1:]))[len(mids) // 2]
        for k in range(min(3, len(lines) - 1)):
            l0 = lines[k]
            short = l0['b'][2] - l0['b'][0] < 0.4 * wide and len(text(l0)) < 14
            if not short:
                break
            centred = abs((l0['b'][0] + l0['b'][2]) / 2 - mid) < 0.25 * wide
            apart = mids[k + 1] - mids[k] > 1.1 * pitch
            few = len(re.sub(r'[^A-Za-z]', '', text(l0))) <= 6
            if centred and (apart or few or re.search(r'[\d()]', text(l0))):
                head = l0
                lines = lines[k:]
                break
    body = lines[1:] if head else list(lines)
    foot = None
    if body:
        last = body[-1]
        words = [w for w in last['w'] if len(re.sub(r'[^A-Za-z0-9]', '', w['t'])) >= 2 or re.fullmatch(r'[A-Z]', w['t'])]
        right = max(l['b'][2] for l in body)
        left = min(l['b'][0] for l in body)
        # (The foot: the catchword at the right, a signature (`A 3`) before
        # it, a speck or two besides.)
        gap = max([b['b'][0] - a['b'][2] for a, b in zip(words, words[1:])] or [0])
        if words and len(words) <= 4 and words[-1]['b'][2] > right - 0.15 * (right - left) \
                and (len(words) == 1 or words[0]['b'][0] > left + 0.25 * (right - left)
                     or gap > 0.2 * (right - left) or len(re.sub(r'[^A-Za-z]', '', words[0]['t'])) <= 2):
            foot = {'b': last['b'], 'w': words}
            body = body[:-1]
    return head, body, foot


def main():
    VOCAB.update(vocabulary())
    abbyy = json.load(open(os.path.join(WORK, 'ocr2.json')))
    tess = json.load(open(os.path.join(WORK, 'tess.json')))
    # (Which reading of each leaf: ABBYY's, or Tesseract's where ABBYY's
    # runs lines together (choice.json, choose.sh's: the one fewer of
    # whose lines disagree with the transcription).)
    mode = os.environ.get('OCR', 'best')
    path = os.path.join(WORK, 'choice.json')
    choice = json.load(open(path)) if mode == 'best' and os.path.exists(path) else {}

    class Pick(dict):
        def __missing__(self, leaf):
            src = choice.get(str(leaf), 'abbyy') if mode == 'best' else mode
            return tess[str(leaf)] if src == 'tess' else abbyy[leaf]
    ocr = Pick()
    leaves = json.load(open(os.path.join(WORK, 'leaves.json')))
    toks = tokens()
    pages = []
    for leaf, page in leaves:
        if page in ('frontispiece', 'title') or page in BLACK:
            continue
        hand = os.path.join(HERE, 'pages', f'{page}.txt')
        if os.path.exists(hand):
            head, body, foot = hand_parts(hand)
        else:
            head, body, foot = page_parts(ocr, leaf)
        pages.append({'leaf': leaf, 'page': page, 'head': head, 'lines': body, 'foot': foot,
                      'hand': hand if os.path.exists(hand) else None})
    # (A footnote's lines: those at the foot of a page under a gap (a
    # line and a half of the text's), their letter smaller than the
    # text's (the book's lines' middle); specks passed over.)
    def size(l):
        ts = sorted(w['b'][1] for w in l['w'])
        bs = sorted(w['b'][3] for w in l['w'])
        return bs[len(bs) // 2] - ts[len(ts) // 2]
    real = lambda l: len(re.sub(r'[^A-Za-z]', '', ' '.join(w['t'] for w in l['w']))) > 2
    sizes = sorted(size(l) for p in pages if not p.get('hand') for l in p['lines'])
    letter = sizes[len(sizes) // 2]
    pitches = []
    for p in pages:
        mids = [(l['b'][1] + l['b'][3]) / 2 for l in p['lines'] if real(l)]
        pitches += [y - x for x, y in zip(mids, mids[1:])]
    pitch = sorted(pitches)[len(pitches) // 2]
    for p in pages:
        if p.get('hand'):
            continue
        ls = [l for l in p['lines'] if real(l)]
        for k in range(len(ls) - 2, 0, -1):
            gap = (ls[k]['b'][1] + ls[k]['b'][3]) / 2 - (ls[k - 1]['b'][1] + ls[k - 1]['b'][3]) / 2
            if gap > 1.4 * pitch:
                below = ls[k:]
                if sum(size(l) for l in below) / len(below) < 0.92 * letter:
                    at = p['lines'].index(ls[k])
                    for l in p['lines'][at:]:
                        l['note'] = True
                break
    stream = ocr_words(pages)

    def other_word(s):
        """The other OCR's word where [s]'s last part is: its text."""
        part = s['parts'][-1]
        leaf = pages[part['pi']]['leaf']
        if pages[part['pi']].get('hand'):
            return part['t']
        src = choice.get(str(leaf), 'abbyy') if mode == 'best' else mode
        lines = abbyy[leaf]['lines'] if src == 'tess' else tess[str(leaf)]['lines']
        x0, y0, x1, y1 = part['b']
        for L in lines:
            for w in L['w']:
                cx, cy = (w['b'][0] + w['b'][2]) / 2, (w['b'][1] + w['b'][3]) / 2
                if x0 - 4 <= cx <= x1 + 4 and y0 - 4 <= cy <= y1 + 4:
                    return w['t']
        return ''
    sm = difflib.SequenceMatcher(None, [s['k'] for s in stream], [t['k'] for t in toks], autojunk=False)
    words = {}  # (page index, line) -> [word]
    flags = set()

    def place(part, tok):
        words.setdefault((part['pi'], part['line']), []).append(tok)

    def put(si, tok, flag=False):
        s = stream[si]
        if len(s['parts']) == 2 and not tok['t'].startswith('⟦'):
            a, b = divide(tok['t'], s['parts'][0]['t'])
            first, rest = dict(tok, t=a, glue=False, post=''), dict(tok, t=b, pre='')
            place(s['parts'][0], dict(first, out=render(first)))
            place(s['parts'][1], dict(rest, out=render(rest)))
        else:
            place(s['parts'][0], dict(tok, out=render(tok)))
        if flag:
            flags.add((s['parts'][0]['pi'], s['parts'][0]['line']))

    def own(si, tok):
        """The OCR's word, the printing's, its long s's read; the
        transcription's marks."""
        s = stream[si]
        t = long_s(s['t'], tok['t'] if tok else None)
        return dict(tok or {}, t=t, k=key(t))

    def group(a1, b1, oi, ti):
        """A group of the OCR's words ([oi]) and the transcription's
        ([ti]) the local alignment paired."""
        ss = [stream[a1 + i] for i in oi]
        tt = [toks[b1 + j] for j in ti]
        if not ss:
            # (Words the OCR lacks: given to the word before, flagged.)
            if a1 + (oi[0] if oi else 0) > 0:
                for t in tt:
                    put(a1 - 1 if not oi else a1 + oi[0] - 1, dict(t, t=f"⟦+{t['t']}⟧"), True)
            return
        if not tt:
            for i in oi:
                s = stream[a1 + i]
                mine = own(a1 + i, None)
                bare = re.sub(r'^[^A-Za-z]*|[^A-Za-z’\']*$', '', mine['t']).lower()
                if s['c'] >= 85 and bare in VOCAB and len(bare) > 1:
                    put(a1 + i, mine, True)
                else:
                    put(a1 + i, {'t': f"⟦{s['t']}|⟧", 'k': ''}, True)
            return
        if len(ss) == 1 and len(tt) == 1:
            s, tok = ss[0], tt[0]
            si = a1 + oi[0]
            mine = own(si, tok)
            bare = re.sub(r'^[^A-Za-z]*|[^A-Za-z’\']*$', '', mine['t']).lower().replace("'", '’')
            good = s['c'] >= 70 and re.fullmatch(r"[(“‘]*[A-Za-z’'-]+[.,;:!?’”)]*", s['t']) and (bare in VOCAB or bare.rstrip('’') in VOCAB and not bare.endswith('’')) \
                and variant(bare, re.sub(r'^[^A-Za-z]*|[^A-Za-z’\']*$', '', tok['t']).lower())
            r = difflib.SequenceMatcher(None, s['k'], tok['k']).ratio()
            if re.fullmatch(r'&c[.,;:]*', s['t']) and tok['t'].startswith('etc'):
                put(si, dict(tok, t='&c.' + tok['t'][4:], k='andc'))
            elif s['k'] == tok['k']:
                put(si, tok)
            elif good and r >= 0.5 and not (r >= 0.7 and tok['t'][:1].isupper()):
                put(si, dict(mine, pre=tok.get('pre', ''), post=''), False)
            elif r >= 0.7:
                # (The OCR sure of another word: the printing's, maybe.)
                other = s['c'] >= 80 and bare in VOCAB and len(bare) > 2
                put(si, dict(tok, t=f"⟦{s['t']}|{tok['t']}⟧") if other else tok, other)
            else:
                put(si, dict(tok, t=f"⟦{s['t']}|{tok['t']}⟧"), True)
            return
        def vocab_words(xs):
            for x in xs:
                w = re.sub(r'[^a-z’]', '', x['t'].lower())
                if len(w) < 2 and w not in ('a', 'i', 'o') or not (w in VOCAB or w.replace('f', 's') in VOCAB):
                    return False
            return True
        if len(ss) == len(tt) and len(ss) > 1:
            # (As many words either side: the transcription's, each on
            # its word's line.)
            for k in range(len(ss)):
                put(a1 + oi[k], tt[k], ss[k]['k'] != tt[k]['k'])
            return
        if len(ss) > len(tt) and (not vocab_words(ss) or ''.join(x['k'] for x in ss) != ''.join(x['k'] for x in tt)):
            # (Words the OCR read in pieces, their letters spaced or their
            # print faint: the transcription's words whole.)
            for t in tt:
                put(a1 + oi[0], t, ''.join(x['k'] for x in ss) != ''.join(x['k'] for x in tt))
            return
        if len(ss) >= len(tt):
            # (The printing divides what the transcription joins: the
            # transcription's letters in the printing's words.)
            joined = ''.join(t['t'] for t in tt)
            pos = 0
            for k, s in enumerate(ss):
                n, got, j = len(s['k']), 0, pos
                while j < len(joined) and got < n:
                    if re.match(r'[A-Za-z0-9]', joined[j]):
                        got += 1
                    j += 1
                while k < len(ss) - 1 and j < len(joined) and joined[j] in '.,;:!?’)':
                    j += 1
                piece = joined[pos:j] if k < len(ss) - 1 else joined[pos:]
                pos = j
                # (The printing's words apart: the transcription's hyphen
                # between them not the printing's.)
                if not len(s['parts']) > 1:
                    piece = piece.strip('-') if piece.strip('-') else piece
                put(a1 + oi[k], dict(tt[0], t=piece, glue=False, pre=tt[0].get('pre', '') if k == 0 else '',
                                     post=tt[-1].get('post', '') if k == len(ss) - 1 else ''),
                    ''.join(x['k'] for x in ss) != ''.join(x['k'] for x in tt))
        else:
            # (The OCR ran words together: the transcription's words.)
            text = join([dict(t, out=render(t)) for t in tt])
            put(a1 + oi[0], dict(tt[0], t=text, glue=tt[-1].get('glue'), i=False, sc=False, pre='', post=''),
                ''.join(x['k'] for x in ss) != ''.join(x['k'] for x in tt))

    for op, a1, a2, b1, b2 in sm.get_opcodes():
        if op == 'equal':
            for k in range(a2 - a1):
                put(a1 + k, reconcile(stream[a1 + k], toks[b1 + k], other_word(stream[a1 + k])))
            continue
        ss, tt = stream[a1:a2], toks[b1:b2]
        for oi, ti in local_align(ss, tt):
            group(a1, b1, oi, ti)
    draft = {}
    for pi, p in enumerate(pages):
        out = []
        if p['head']:
            out.append({'box': p['head']['b'], 'text': ' '.join(w['t'] for w in p['head']['w']), 'kind': 'head', 'flag': False})
        for li, l in enumerate(p['lines']):
            ws = words.get((pi, li), [])
            text = join(ws) if ws else ' '.join(w['t'] for w in l['w'])
            kind = ws[0].get('kind') if ws else 'ocr'
            heads = [w for w in ws if w.get('kind') == 'H']
            if heads and re.search(r'C\s*H\s*A\s*P', ' '.join(w['t'] for w in l['w'])):
                # (A chapter's head: the transcription's, the printing's form.)
                hs = [w['t'].strip('⟦⟧+') for w in heads]
                hs = [h for h in hs if h != '|']
                text = ' '.join(h.split('|')[-1] for h in hs)
                flags.discard((pi, li))
            out.append({'box': l['b'], 'text': text, 'kind': kind, 'flag': (pi, li) in flags or not ws,
                        'ocr': ' '.join(w['t'] for w in l['w']), 'note': bool(l.get('note'))})
        if p['foot']:
            out.append({'box': p['foot']['b'], 'text': ' '.join(long_s(w['t']) for w in p['foot']['w']), 'kind': 'foot',
                        'flag': False})
        # (The transcription spells out what the printing elides,
        # `tho’` `though`, `thro’` `through`: the printing's where the
        # OCR reads it so.)
        for o in out:
            for short, full in (('tho', 'though'), ('thro', 'through')):
                k = len(re.findall(rf'\b{short}[’\']', o.get('ocr') or '', re.I))
                if k:
                    o['text'] = re.sub(rf'(?<![⟦|])\b({full[0]}|{full[0].upper()}){full[1:]}\b(?![|⟧])',
                                       lambda m: m.group(1) + short[1:] + '’', o['text'], count=k)
        # (A word the line divides that the OCR read whole on the line
        # before (its hyphen not read): divided as the OCR reads the line
        # after, its first word the word's end.)
        body = [o for o in out if o['kind'] not in ('head', 'foot')]
        for a, b in zip(body, body[1:]):
            first = (b.get('ocr') or '').split()
            aw = a['text'].split()
            if not first or not aw or '⟦' in a['text'] or '{shy}' in aw[-1]:
                continue
            x = key(first[0])
            if len(x) < 2 or key(b['text']).startswith(x):
                continue
            m = re.match(r'^(.*?)([.,;:!?’”)]*)$', aw[-1])
            core, tail = m.group(1), m.group(2)
            wk = key(core)
            if len(wk) > len(x) + 1 and wk.endswith(x) and not re.search(r'[_#\]]', core):
                # (The core's letters counted from its end.)
                n, at = 0, len(core)
                while at > 0 and n < len(x):
                    at -= 1
                    if re.match(r'[A-Za-z]', core[at]):
                        n += 1
                a['text'] = ' '.join(aw[:-1] + [core[:at] + '{shy}'])
                b['text'] = core[at:] + tail + ' ' + b['text']
        # (A dash the transcription glues to the word before it the
        # printing may set at the next line's start: there where the
        # OCR reads the line from a dash.)
        body = [o for o in out if o['kind'] not in ('head', 'foot')]
        for a, b in zip(body, body[1:]):
            m = re.search(r'[—⸺⸻]+$', a['text'])
            if m and re.match(r'^\W{0,2}(—|--)', b.get('ocr') or ''):
                a['text'] = a['text'][:m.start()].rstrip()
                b['text'] = m.group(0) + b['text']
        if p.get('hand'):
            for o, l in zip([o for o in out if o['kind'] not in ('head', 'foot')], p['lines']):
                o.update(text=l['raw'], flag=False, hand=True)
        draft[p['page']] = {'leaf': p['leaf'], 'lines': out}
    out = os.environ.get('DRAFT', 'draft.json')
    json.dump(draft, open(os.path.join(WORK, out), 'w'), indent=0)
    print(len(draft), 'pages;', sum(l['flag'] for p in draft.values() for l in p['lines']), 'lines flagged of',
          sum(len(p['lines']) for p in draft.values()))


def render(tok):
    t = tok['t']
    if tok.get('i') and not t.startswith('⟦'):
        t = f'__{t}__'
    if tok.get('sc') and not t.startswith('⟦'):
        t = f'[.sc]##{t}##'
    return tok.get('pre', '') + t + tok.get('post', '')


def join(ws):
    """A line's words: those glued by a dash run together."""
    out = ''
    for k, w in enumerate(ws):
        out += w['out']
        if k < len(ws) - 1 and not w.get('glue'):
            out += ' '
    return re.sub(r'__ __', ' ', out).replace('____', '')


def divide(word, first):
    """[word] divided where the line divides it: its first piece as like
    [first] (the line's piece before its hyphen) as can be; a hyphen of
    the word's own kept (`garden-` `walk`), else one added and marked
    (`{shy}`)."""
    f = first.rstrip('-=')
    best, at = -1, max(1, len(f))
    for i in range(1, len(word)):
        r = difflib.SequenceMatcher(None, key(word[:i]), key(f)).ratio()
        if r > best:
            best, at = r, i
    a, b = word[:at], word[at:]
    if a.endswith(' ') or b.startswith(' ') or not b.strip():
        # (Two words, the OCR's hyphen a speck after the first: the
        # line ends between them.)
        return a.rstrip(), b.lstrip()
    if a.endswith('-'):
        return a + '{zwsp}', b
    if b.startswith('-'):
        return a + '-{zwsp}', b[1:]
    return a + '{shy}', b


main()
