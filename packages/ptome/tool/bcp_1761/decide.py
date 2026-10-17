"""Each leaf's lines decided: Tesseract's reading of the leaf (tess.json,
ocr.py's) word by word against the corpus's text of its part (corpus.py),
aligned in order, each part from where the leaf before ended. A word the
corpus has (its letters the same, the long s Tesseract reads as f taken
for an s where the corpus has one): its letters the corpus's, its case
and its stops the scan's. One the corpus hasn't: the scan's, its f's
taken for long s's where that makes a word of the vocabulary
(corpus.py's) and the f's don't, the corpus's word for it where they
are near alike and the scan's isn't a word; else the scan's as read,
listed for reading off the scan (`?`). Each word italic or not by its
slant (slant.py), a short word as its neighbours. Written to
BCP_WORK/draft.json: per leaf its lines, each its words (text, italic,
flag) and the corpus's kind of the block it starts or goes on.

    python3 -I decide.py [PART...]
"""
import difflib, itertools, json, os, re, sys
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from common import WORK, PARTS
from corpus import part_tokens, vocabulary
from slant import slant, SLANT


def core(w):
    """A word's letters, lower case, its stops and quotes gone."""
    return re.sub(r'[^a-z0-9’]', '', w.lower().replace("'", '’')).strip('’')


def key(w):
    """A word's letters as alignment reads them: the long s Tesseract
    reads as f, and a few of its other readings of it, as s."""
    return core(w).replace('f', 's').replace('{', 's')


def s_fixed(w, vocab):
    """[w]'s letters with some of its long s's put right, the fewest that
    make a word of the vocabulary (Tesseract reads the long s as f, and
    now and then as l, i, t or, with the h after it, th): the letters,
    or None if its own are a word or none are found."""
    c = core(w)
    if not c or c in vocab:
        return None
    at = [i for i, ch in enumerate(c) if ch in 'flit']
    if len(at) > 8:
        return None
    for n in range(1, min(3, len(at)) + 1):
        # (The f's first: Tesseract's usual reading.)
        for subset in sorted(itertools.combinations(at, n), key=lambda q: sum(c[i] != 'f' for i in q)):
            t = list(c)
            for i in subset:
                t[i] = 's'
            if ''.join(t) in vocab:
                return ''.join(t)
    return None


# Tesseract's other misreadings of the octavo's letters: the long s
# with t after it read as fi, fl or ft, the ct ligature as & or &t.
SWAPS = [('sf', 's'), ('fs', 's'), ('fl', 's'), ('fi', 's'), ('j', 's'), ('lf', 's'), ('dt', 'st'), ('ff', 'ss'), ('fft', 'sst'), ('é', 'c'),
         ('fi', 'st'), ('fl', 'st'), ('ft', 'st'), ('li', 'st'), ('&t', 'ct'), ('&', 'ct'), ('th', 'sh'), ('rn', 'm'),
         ('ii', 'u'), ('1', 'l'), ('1', 'i'), ('0', 'o')]


def repaired(raw, vocab):
    """[raw]'s letters made a word of the vocabulary by one of SWAPS
    (and the long s's put right), or two words it runs together split
    with a space: the text, or None."""
    c = core(raw)
    for a, b in SWAPS:
        start = 0
        while True:
            i = c.find(a, start)
            if i < 0:
                break
            t = c[:i] + b + c[i + len(a):]
            if t in vocab:
                return t
            f = s_fixed(t, vocab)
            if f:
                return f
            start = i + 1
    return None


def segmented(raw, vocab):
    """[raw] as words of the vocabulary it runs together: the text, or
    None."""
    plain = core(raw).replace("’", '')
    seg = segment(plain, vocab)
    # (Only words of a size: no piece of one letter but a, I, O, the
    # pieces three letters long on the average.)
    if seg and 1 < len(seg) <= 4 and sum(len(w) for w in seg) / len(seg) >= 3:
        return ' '.join(seg)
    return None


def segment(c, vocab):
    """[c] as the fewest words of the vocabulary (each of two letters or
    more, or a, i, o), the long s's put right: the words, or None."""
    best = {0: []}
    for i in range(1, len(c) + 1):
        for j in range(max(0, i - 18), i):
            if j not in best:
                continue
            w = c[j:i]
            if len(w) < 2 and w not in ('a', 'i', 'o'):
                continue
            f = w if w in vocab else s_fixed(w, vocab)
            if f and (i not in best or len(best[j]) + 1 < len(best[i])):
                best[i] = best[j] + [f]
    return best.get(len(c))


def apply(raw, letters):
    """The scan's word [raw] with its letters as [letters] (the same count
    of letters, its case and its stops kept)."""
    out, k = [], 0
    for ch in raw:
        if ch.isalnum() or ch in '{' or ch in "’'" and '’' in letters:
            if k < len(letters):
                n = letters[k]
                out.append(n.upper() if ch.isupper() else n)
            k += 1
        else:
            out.append(ch)
    return ''.join(out)


def variant(a, b):
    """Whether [a] is [b] as the printing may spell it: y for i, an e
    more or less, a consonant single or doubled, -er for -re."""
    if a == b:
        return False
    if a.endswith('er') and b.endswith('re') and a[:-2] == b[:-2]:
        return True
    for op, a1, a2, b1, b2 in difflib.SequenceMatcher(None, a, b, autojunk=False).get_opcodes():
        x, y = a[a1:a2], b[b1:b2]
        if op == 'equal' or {x, y} == {'y', 'i'} or {x, y} == {'e', ''}:
            continue
        if not x and len(y) == 1 and (b[b1 - 1:b1] == y or b[b2:b2 + 1] == y) \
                or not y and len(x) == 1 and (a[a1 - 1:a1] == x or a[a2:a2 + 1] == x):
            continue  # (A consonant doubled or not.)
        if {x, y} == {'er', 're'}:
            continue
        return False
    return True


def spelled(raw, cw):
    """The scan's word [raw] with its long s's read as the corpus's word
    [cw] has them: its letters, small."""
    import itertools
    r, c = core(raw), core(cw)
    at = [k for k, ch in enumerate(r) if ch == 'f'][:4]
    best = max((''.join('s' if k in pick else ch for k, ch in enumerate(r))
                for n in range(len(at) + 1) for pick in itertools.combinations(at, n)),
               key=lambda v: difflib.SequenceMatcher(None, v, c, autojunk=False).ratio())
    r = best
    out = []
    for op, a1, a2, b1, b2 in difflib.SequenceMatcher(None, r, c, autojunk=False).get_opcodes():
        x, y = r[a1:a2], c[b1:b2]
        if op == 'replace' and len(x) == len(y) and all(q == 's' or p == q for p, q in zip(x, y)) \
                and all(p in 'flitj{' for p, q in zip(x, y) if q == 's'):
            out.append(y)
        else:
            out.append(x.replace('{', 's'))
    return ''.join(out)


def decide_word(raw, cw, vocab):
    """The printed word for the scan's [raw], the corpus's word [cw]
    aligned with it (or None): (text, flag). A compound (an inner
    hyphen) decided part by part."""
    raw = raw.replace('{', 's')
    inner = re.match(r'^(\W*)(\w[\w’\']*(?:-[\w’\']+)+)(\W*)$', raw)
    if inner and (cw is None or key(raw) != key(cw)):
        parts = inner.group(2).split('-')
        cws = cw.strip('.,;:?!').split('-') if cw and cw.count('-') == len(parts) - 1 else [None] * len(parts)
        done = [decide_word(p_, c_, vocab) for p_, c_ in zip(parts, cws)]
        return inner.group(1) + '-'.join(t for t, _ in done) + inner.group(3), any(f for _, f in done)
    two = re.match(r"^(\W*)([A-Za-z{]+)['’]([A-Za-z{]{1,}\W*)$", raw)
    if two and two.group(3).rstrip('.,;:?!') not in ('s', 'd', 't', 'st') and key(raw) != key(cw or ''):
        # (Two words Tesseract read as one, a speck between them.)
        a, _ = decide_word(two.group(1) + two.group(2), None, vocab)
        b, _ = decide_word(two.group(3), None, vocab) if core(two.group(3)) not in ('l', '1') else ('I', False)
        if core(a) in vocab and core(b) in vocab | {'i'}:
            return a + ' ' + b, False
    c = core(raw)
    if cw is not None and key(raw) == key(cw) and c:
        # (The corpus's letters, the scan's case and stops.)
        return apply(raw, core(cw)), False
    if not c:
        return raw, False
    if cw is not None and core(cw).isdigit() and len(c) <= 3:
        # (A verse's number: the corpus's, Tesseract reading 9 as g.)
        return re.sub(r'[A-Za-z0-9]+', core(cw), raw, count=1), False
    d = c.replace('1', 'i').replace('0', 'o')
    if d != c and d in vocab:
        return apply(raw, d), False
    if c in vocab or c.isdigit() or ROMAN.match(c) or c.replace('f', 's') in OWN or c in OWN:
        return (apply(raw, c.replace('f', 's')) if c.replace('f', 's') in OWN else raw), False
    fix = s_fixed(raw, vocab)
    if fix is not None:
        return apply(raw, fix), False
    fix = repaired(raw, vocab)
    if fix is not None:
        lead = re.match(r'^[^A-Za-z0-9&]*', raw).group(0)
        tail = re.search(r'[^A-Za-z0-9&]*$', raw).group(0)
        body = raw[len(lead):len(raw) - len(tail)] if tail else raw[len(lead):]
        if ' ' not in fix and len(fix) == len(re.sub(r'[^A-Za-z0-9]', '', body)):
            return apply(raw, fix), False
        if body[:1].isupper():
            fix = fix[0].upper() + fix[1:]
        return lead + fix + tail, False
    if cw is not None and difflib.SequenceMatcher(None, key(raw), key(cw)).ratio() < 0.75:
        fix = segmented(raw, vocab)
        if fix is not None:
            lead = re.match(r'^[^A-Za-z0-9&]*', raw).group(0)
            tail = re.search(r'[^A-Za-z0-9&]*$', raw).group(0)
            body = raw[len(lead):len(raw) - len(tail)] if tail else raw[len(lead):]
            if body[:1].isupper():
                fix = fix[0].upper() + fix[1:]
            return lead + fix + tail, False
    if cw is not None and difflib.SequenceMatcher(None, key(raw), key(cw)).ratio() >= 0.75:
        own = spelled(raw, cw)
        if variant(own, core(cw)):
            # (The printing's own spelling of the corpus's word.)
            lead = re.match(r'^[^A-Za-z0-9{]*', raw).group(0)
            tail = re.search(r'[^A-Za-z0-9{]*$', raw).group(0)
            if raw[len(lead):len(lead) + 1].isupper():
                own = own[0].upper() + own[1:]
            return lead + own + tail, False
        if len(core(cw)) == len(c):
            return apply(raw, core(cw)), False
        # (A word Tesseract read with a letter more or less: the corpus's,
        # the scan's case of its first letter and its stops.)
        lead = re.match(r'^[^A-Za-z0-9]*', raw).group(0)
        tail = re.search(r'[^A-Za-z0-9]*$', raw).group(0)
        w = core(cw)
        if raw[len(lead):len(lead) + 1].isupper():
            w = (w.upper() if raw[len(lead):].rstrip(tail).isupper() and len(c) > 1 else w[0].upper() + w[1:])
        return lead + w + tail, False
    if cw is None:
        fix = segmented(raw, vocab)
        if fix is not None:
            lead = re.match(r'^[^A-Za-z0-9&]*', raw).group(0)
            tail = re.search(r'[^A-Za-z0-9&]*$', raw).group(0)
            body = raw[len(lead):len(raw) - len(tail)] if tail else raw[len(lead):]
            if body[:1].isupper():
                fix = fix[0].upper() + fix[1:]
            return lead + fix + tail, False
    return raw, True


ROMAN = re.compile(r'^[ivxlc]+$')
# (The printing's own: its abbreviations and its running heads' words.)
OWN = {'psal', 'answ', 'pſal', 'matth', 'cor', 'ezek', 'jer', 'dan', 'luke', 'john', 'st', 'ver', 'amen', 'psalms',
       'litany', 'prayer', 'morning', 'evening'}


VOCAB = set()
READINGS = {}
if os.path.exists(os.path.join(HERE, 'readings.tsv')):
    for _line in open(os.path.join(HERE, 'readings.tsv'), encoding='utf-8'):
        _leaf, _at, _text = _line.rstrip('\n').split('\t')
        READINGS[(_leaf, _at)] = _text


def logical(lines):
    """The leaf's words as words: a word a line divides (its first part
    ending in a hyphen) one, an initial Tesseract reads apart from the
    rest of its word one; each its parts, (line, word) each."""
    flat = [(k, j, w) for k, l in enumerate(lines) for j, w in enumerate(l['words'])]
    out = []
    i = 0
    while i < len(flat):
        k, j, w = flat[i]
        parts = [(k, j, w)]
        raw = w['t']
        nxt = flat[i + 1] if i + 1 < len(flat) else None
        if nxt and j == len(lines[k]['words']) - 1 and nxt[0] == k + 1 and raw.endswith('-') and len(raw) >= 2:
            parts.append(nxt)
            i += 1
        elif nxt and j == 0 and len(raw) == 1 and raw.isupper() and nxt[0] == k and nxt[2]['t'][:1].isupper() \
                and (w['box'][3] - w['box'][1]) > 1.6 * (nxt[2]['box'][3] - nxt[2]['box'][1]):
            parts.append(nxt)
            i += 1
        # (Capitals spaced apart, a head's or a word's after its initial:
        # Tesseract's pieces of them one word, where they make one.)
        if len(parts) == 1 and re.fullmatch(r'[A-Z]{1,8}', raw.strip('.,;:')):
            q = i + 1
            run = [parts[0]]
            while q < len(flat) and flat[q][0] == k and re.fullmatch(r'[A-Z]{1,8}[.,;:]?', flat[q][2]['t']) \
                    and not re.search(r'[.,;:]$', run[-1][2]['t']):
                run.append(flat[q])
                q += 1
                word = ''.join(r[2]['t'] for r in run)
                if (core(word) in VOCAB or core(word) in OWN) and len(run) > 1:
                    parts = list(run)
                    i = q - 1
        out.append(parts)
        i += 1
    return out


def joined(parts):
    if len(parts) == 1:
        return parts[0][2]['t']
    texts = [p[2]['t'] for p in parts]
    if len(parts) == 2 and texts[0].endswith('-'):
        return texts[0][:-1] + texts[1]
    return ''.join(texts)


def split_back(text, parts):
    """The decided word [text] cut again as its parts were: the first as
    many letters as it had; spaced capitals one word, on the first part,
    the others empty."""
    if len(parts) == 1:
        return [text]
    if not parts[0][2]['t'].endswith('-') and parts[0][0] == parts[1][0] and len(parts) > 2 or \
            (len(parts) == 2 and not parts[0][2]['t'].endswith('-') and parts[1][2]['t'].isupper() and len(parts[0][2]['t']) > 1):
        return [text] + [''] * (len(parts) - 1)
    a = parts[0][2]['t']
    n = len(re.sub(r'[^A-Za-z0-9{]', '', a))
    cut, seen = len(text), 0
    for q, ch in enumerate(text):
        if ch.isalnum():
            seen += 1
            if seen == n:
                cut = q + 1
                break
    return [text[:cut] + ('-' if a.endswith('-') else ''), text[cut:]]


def main():
    vocab = vocabulary()
    VOCAB.update(vocab)
    tess = json.load(open(os.path.join(WORK, 'tess.json')))
    parts = sys.argv[1:] or list(PARTS)
    path = os.path.join(WORK, 'draft.json')
    draft = json.load(open(path)) if os.path.exists(path) else {}
    for part in parts:
        if part == 'calendar':
            continue
        toks = part_tokens(part)
        tkeys = [key(t['t']) for t in toks]
        cursor = 0
        flagged = 0
        for leaf in PARTS[part]:
            lines = tess.get(str(leaf), [])
            ink = np.asarray(Image.open(os.path.join(WORK, 'upright', f'{leaf:04d}.png'))) < 120
            words = []
            for p_ in logical(lines):
                # (An initial joined to the word after it only where that
                # makes a word: O God, I will, stay apart.)
                if len(p_) == 2 and p_[0][0] == p_[1][0] and core(joined(p_)) not in vocab \
                        and s_fixed(joined(p_), vocab) is None:
                    words += [[p_[0]], [p_[1]]]
                else:
                    words.append(p_)
            okeys = [key(joined(p)) for p in words]
            lo, hi = max(0, cursor - 50), min(len(toks), cursor + 900)
            sm = difflib.SequenceMatcher(None, okeys, tkeys[lo:hi], autojunk=False)
            match = {}
            for op, a0, a1, b0, b1 in sm.get_opcodes():
                if op == 'equal' or (op == 'replace' and a1 - a0 == b1 - b0):
                    for q in range(a1 - a0):
                        match[a0 + q] = lo + b0 + q
                elif op == 'replace':
                    # (Unequal stretches: each OCR word the likest corpus
                    # word after the last paired, if like enough.)
                    b = b0
                    for a in range(a0, a1):
                        best = max(range(b, b1), key=lambda q: difflib.SequenceMatcher(None, okeys[a], tkeys[lo + q]).ratio(),
                                   default=None)
                        if best is not None and difflib.SequenceMatcher(None, okeys[a], tkeys[lo + best]).ratio() >= 0.6:
                            match[a] = lo + best
                            b = best + 1
            if match:
                # (Where the page ends in the corpus: the last of its
                # matches but a few strays, a refrain matched further on.)
                vals = sorted(match.values())
                cursor = vals[int(len(vals) * 0.9)] + 1
            out = [{'box': l['box'], 'ocr': l['ocr'], 'words': [], 'kind': None, 'start': False} for l in lines]
            for i, parts in enumerate(words):
                ti = match.get(i)
                cw = toks[ti]['t'] if ti is not None else None
                text, flag = decide_word(joined(parts), cw, vocab)
                if (flag or ' ' in text) and cw is None or (cw is not None and key(joined(parts)) != key(cw)):
                    # (Words Tesseract ran together: a run of the corpus's
                    # words near here whose letters are its letters.)
                    prev = max((match[q] for q in range(i) if q in match), default=lo)
                    want = key(joined(parts))
                    for at_ in range(max(0, prev - 2), min(len(toks), prev + 4)):
                        hit = None
                        for n_ in (2, 3, 4):
                            run = toks[at_:at_ + n_]
                            if key(''.join(t['t'] for t in run)) == want:
                                hit = ' '.join(t['t'] for t in run)
                                break
                        if hit:
                            raw_ = joined(parts)
                            tail = re.search(r'[^A-Za-z0-9]*$', raw_).group(0)
                            text, flag = hit.rstrip('.,;:?!') + tail, False
                            break
                if flag and parts[0][1] == 0 and re.fullmatch(r'[gq][.,]?', joined(parts)):
                    # (A verse's number 9 read as g.)
                    text, flag = '9', False
                if flag and (parts[0][0] == 0 or parts[0][0] == len(lines) - 1):
                    # (The running head, the foot: set otherwise, as read.)
                    flag = False
                at = f"{parts[0][2]['box'][0]},{parts[0][2]['box'][1]}"
                if (str(leaf), at) in READINGS:
                    # (Read off the scan: readings.tsv.)
                    text, flag = READINGS[(str(leaf), at)], False
                for (k, j, w), piece in zip(parts, split_back(text, parts) if not (str(leaf), at) in READINGS else [text] + [''] * (len(parts) - 1)):
                    x0, y0, x1, y1 = w['box']
                    sl = slant(ink[y0:y1, x0:x1])
                    out[k]['words'].append({'t': piece, 's': round(sl, 3), 'flag': flag, 'box': w['box'],
                                            'raw': w['t']})
                    if ti is not None and out[k]['kind'] is None:
                        out[k]['kind'] = toks[ti]['k']
                        out[k]['start'] = toks[ti]['s'] and j == 0
                flagged += flag
            # (Italic: a word sheared past SLANT; a word of two letters or
            # fewer as the words either side of it, where they agree.)
            for l in out:
                ws = l['words']
                for j, wd in enumerate(ws):
                    wd['i'] = wd['s'] > SLANT
                for j, wd in enumerate(ws):
                    if len(core(wd['t'])) <= 2:
                        near = [ws[q]['i'] for q in (j - 1, j + 1) if 0 <= q < len(ws) and len(core(ws[q]['t'])) > 2]
                        if near and all(n == near[0] for n in near):
                            wd['i'] = near[0]
            draft[str(leaf)] = {'part': part, 'lines': out}
        print(part, flagged, 'words to read off the scan')
    json.dump(draft, open(path, 'w'), ensure_ascii=False, indent=0)


main()
