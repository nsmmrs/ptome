"""Each region's printed lines decided word by word (draft.json): the
lines Tesseract read (tess.json) and the Library of Congress's OCR
(lines.json); a region the work's earlier transcription covers
(test/showcase/tribune/text, made from the same scans: REFS) read
against it, its words the transcription's, divided where the line
divides them; elsewhere a word where the two readings agree, or the
one of them a word of the vocabulary (the showcase's texts and the
transcription), else flagged `⟦so⟧`, to be read off the scan.

    python3 -I decide.py
"""
import difflib, json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from common import WORK

SHOW = os.path.join(HERE, '..', '..', 'test', 'showcase')
TEXT = os.path.join(HERE, 'transcription')
# (The regions the transcription covers: its files, in order.)
REFS = {
    (1, 'crowd'): ['crowd'], (1, 'lead'): ['lead'], (1, 'names-head'): ['names'],
    (1, 'names-a'): ['names'], (1, 'names-b'): ['names'], (1, 'loss'): ['olympic'],
    (1, 'deep'): ['deep'], (1, 'pearls'): ['pearls'], (2, 'c12'): ['lead-continued'],
    (2, 'names-cont'): ['names-continued'],
}


def plain(text):
    """The transcription's words, its markup gone."""
    out = []
    for line in text.split('\n'):
        s = line.strip()
        if not s or s.startswith(('[', '//', ':', 'include::', '|===', '!===', '<<', 'image::')) or s in ('--', '****'):
            continue
        s = re.sub(r'^=+ ', '', s)
        s = re.sub(r'\[\.[^\]]*\]#+(.*?)#+', r'\1', s)
        s = re.sub(r'\*+|__?|\^|\+$', '', s)
        s = re.sub(r'<<[^>]*>>', '', s)
        out.append(s)
    return ' '.join(out).split()


def key(w):
    return re.sub(r'[^a-z0-9]', '', w.lower().replace('’', "'"))


def vocabulary():
    words = set()
    for root, _, files in os.walk(SHOW):
        for f in files:
            if f.endswith('.adoc'):
                for w in re.findall(r"[A-Za-z]+", open(os.path.join(root, f), encoding='utf-8').read()):
                    words.add(w.lower())
    for path in ('/usr/share/dict/words', '/usr/share/dict/cracklib-small'):
        if os.path.exists(path):
            words |= {w.strip().lower() for w in open(path, encoding='utf-8', errors='ignore')}
    return words


def tokens(text):
    return [t for t in text.split() if re.search(r'[A-Za-z0-9]', t)]


def split_like(ref, first):
    """[ref] divided where the line divides it: its first piece as like
    [first] (the line's piece before the hyphen) as can be."""
    best, at = -1, len(first)
    for i in range(1, len(ref)):
        r = difflib.SequenceMatcher(None, key(ref[:i]), key(first)).ratio()
        if r > best:
            best, at = r, i
    return ref[:at] + '-', ref[at:]


def read_lines(texts, altos=None, refkeys=frozenset()):
    """A region's lines as a stream of words to align: each word its line
    and its place; a word divided at a line's end joined with its rest
    (its hyphen read, by Tesseract or the other reading, or the two
    pieces a word of the transcription's where each alone is not)."""
    stream = []
    for li, t in enumerate(texts):
        for wi, w in enumerate(tokens(t)):
            stream.append({'line': li, 't': w, 'k': key(w)})
    joined = []
    for s in stream:
        prev = joined[-1] if joined else None
        last = prev['parts'][-1] if prev else None
        hyphen = last and (last['t'].endswith('-') and not last['t'].endswith('--')
                           or altos and altos[last['line']].rstrip().endswith('-')
                           or prev['k'] + s['k'] in refkeys and prev['k'] not in refkeys)
        if prev and last['line'] < s['line'] and hyphen and len(prev['parts']) == 1 \
                and last is [x for x in stream if x['line'] == last['line']][-1]:
            prev['parts'].append(s)
            prev['k'] += s['k']
            continue
        joined.append({'parts': [s], 'k': s['k']})
    return joined


def decide_ref(texts, ref, altos=None):
    """The region's lines (Tesseract's) read against its transcription:
    {line: [words]} and the lines with a word that is not the
    transcription's (flagged)."""
    rk = [key(w) for w in ref]
    stream = read_lines(texts, altos, frozenset(rk))
    sm = difflib.SequenceMatcher(None, [s['k'] for s in stream], rk, autojunk=False)
    out = {li: [] for li in range(len(texts))}
    flagged = set()

    def put(s, word):
        if len(s['parts']) == 2:
            a, b = split_like(word, s['parts'][0]['t'].rstrip('-'))
            out[s['parts'][0]['line']].append(a)
            out[s['parts'][1]['line']].append(b)
        else:
            out[s['parts'][0]['line']].append(word)

    for op, a1, a2, b1, b2 in sm.get_opcodes():
        if op == 'equal':
            for k in range(a2 - a1):
                put(stream[a1 + k], ref[b1 + k])
        elif op == 'replace' and a2 - a1 == b2 - b1:
            for k in range(a2 - a1):
                s, r = stream[a1 + k], ref[b1 + k]
                put(s, r)
                if difflib.SequenceMatcher(None, s['k'], key(r)).ratio() < 0.5:
                    flagged.add(s['parts'][0]['line'])
        else:
            # (A run the line's words and the transcription's part on: the
            # transcription's, spread over the lines the run is on, a word
            # divided at a line's end divided as the line divides it; the
            # line flagged where a word of it, a word the vocabulary has,
            # is not the transcription's, or the run is at the region's
            # edge, where the transcription may hold more than the lines.)
            ss, rr = stream[a1:a2], ref[b1:b2]
            if not ss:
                li = stream[a1 - 1]['parts'][-1]['line'] if a1 else 0
                if 0 < a1 < len(stream):
                    li = stream[a1 - 1]['parts'][-1]['line']
                    for r in rr:
                        out[li].append(r)
                else:
                    for r in rr:
                        out[li].append(f'⟦+{r}⟧')
                    flagged.add(li)
                continue
            if not rr:
                for s_ in ss:
                    for p in s_['parts']:
                        out[p['line']].append(f'⟦{p["t"]}⟧')
                        flagged.add(p['line'])
                continue
            for q, r in enumerate(rr):
                s_ = ss[min(len(ss) - 1, q * len(ss) // len(rr))]
                if len(s_['parts']) == 2 and q == len(rr) - 1 or len(s_['parts']) == 2 and \
                        ss.index(s_) != min(len(ss) - 1, (q + 1) * len(ss) // len(rr)):
                    put(s_, r)
                else:
                    out[s_['parts'][0]['line']].append(r)
            for s_ in ss:
                good = [p for p in s_['parts'] if re.fullmatch(r'[A-Za-z]+[.,;:]?', p['t']) and key(p['t']) in VOCAB]
                if good and not any(difflib.SequenceMatcher(None, s_['k'], key(r)).ratio() > 0.75 for r in rr):
                    flagged.add(s_['parts'][0]['line'])
            if a1 == 0 or a2 == len(stream):
                flagged.add(ss[0]['parts'][0]['line'])
    return out, flagged


def decide_free(texts, altos, vocab):
    out, flagged = {}, set()
    for li, (t, a) in enumerate(zip(texts, altos)):
        tt, at = tokens(t), tokens(a)
        words = []
        sm = difflib.SequenceMatcher(None, [key(w) for w in tt], [key(w) for w in at], autojunk=False)
        for op, a1, a2, b1, b2 in sm.get_opcodes():
            if op == 'equal':
                words += tt[a1:a2]
                continue
            for k in range(a1, a2):
                w = tt[k]
                ks = re.findall(r'[a-z]+', w.lower())
                if all(x in vocab for x in ks) and not re.search(r'[^A-Za-z0-9.,;:?!\'’"“”()$&%\-—]', w):
                    words.append(w)
                else:
                    alt = at[b1 + (k - a1)] if b1 + (k - a1) < b2 else None
                    ka = re.findall(r'[a-z]+', alt.lower()) if alt else []
                    if alt and ka and all(x in vocab for x in ka) and not re.search(r'[?*<>=]', alt):
                        words.append(alt)
                    else:
                        words.append(f'⟦{w}⟧')
                        flagged.add(li)
        out[li] = words
    return out, flagged


VOCAB = set()


def better(t, a):
    """Of a line's two readings, the one more of whose words are words."""
    score = lambda x: sum(key(w) in VOCAB or key(w).isdigit() for w in tokens(x)) - 0.5 * len(re.findall(r'[;:‘’"]{2,}|[^\x00-\x7f“”’‘—]', x))
    return t if score(t) >= score(a) else a


def main():
    VOCAB.update(vocabulary())
    lines = json.load(open(os.path.join(WORK, 'lines.json')))
    tess = json.load(open(os.path.join(WORK, 'tess.json')))
    vocab = vocabulary()
    draft, nflag = {}, 0
    for page, regs in lines.items():
        draft[page] = {}
        for rid, rows in regs.items():
            texts = tess[page].get(rid, [])
            altos = [' '.join(w['t'] for w in r['words']) for r in rows]
            refs = REFS.get((int(page), rid))
            if refs:
                ref = []
                for f in refs:
                    ref += plain(open(os.path.join(TEXT, f + '.adoc'), encoding='utf-8').read())
                # (The region's part of the transcription: where its first
                # and last lines' words are found.)
                best = [better(t, a) for t, a in zip(texts, altos)]
                words, flagged = decide_ref(best, window(ref, best), altos)
                # (A line the transcription hasn't, most of its words not
                # its: decided as an untranscribed one's are.)
                free, fflag = decide_free(texts, altos, vocab)
                for k in list(words):
                    n = len(words[k]) or 1
                    if sum(w.startswith('⟦') for w in words[k]) / n >= 0.6:
                        words[k] = free[k]
                        flagged.discard(k)
                        if k in fflag:
                            flagged.add(k)
            else:
                words, flagged = decide_free(texts, altos, vocab)
            # (A word the line divides at its end, whole on the line: divided
            # as the scan divides it, its rest the next line's first.)
            for k in range(len(rows) - 1):
                ws, nx = words.get(k, []), words.get(k + 1, [])
                end = [t for t in (texts[k] + ' ' + altos[k]).split() if t]
                if ws and not ws[-1].endswith('-') and any(t.rstrip('|').endswith('-') for t in tokens(texts[k])[-1:] + tokens(altos[k])[-1:]):
                    piece = next(t for t in tokens(texts[k])[-1:] + tokens(altos[k])[-1:] if t.rstrip('|').endswith('-')).rstrip('|')[:-1]
                    w = ws[-1]
                    if len(key(piece)) < len(key(w)) and key(w).startswith(key(piece)[:2]):
                        a, b = split_like(w, piece)
                        ws[-1] = a
                        if nx and key(nx[0]) == key(w)[len(key(a)):]:
                            nx[0] = b
                        else:
                            nx.insert(0, b)
                        words[k + 1] = nx
            # (A column's rule, a speck at a line's end, read as a letter or
            # two: dropped.)
            for k in words:
                ws = words[k]
                while ws and re.fullmatch(r'⟦[^⟧]{1,2}⟧', ws[-1]) and not re.fullmatch(r'⟦[A-Z]\.⟧', ws[-1]):
                    ws.pop()
                while ws and re.fullmatch(r'⟦[^⟧A-Za-z0-9]{1,2}⟧|⟦[IiljtH|!1]⟧', ws[0]):
                    ws.pop(0)
                if not any('⟦' in w for w in ws):
                    flagged.discard(k)
            draft[page][rid] = [{'box': r['box'], 'text': ' '.join(words[k]), 'tess': texts[k], 'alto': altos[k],
                                 'flag': k in flagged} for k, r in enumerate(rows)]
            nflag += len(flagged)
    json.dump(draft, open(os.path.join(WORK, 'draft.json'), 'w'), indent=0)
    print(nflag, 'lines flagged of', sum(len(r) for p in draft.values() for r in p.values()))


def window(ref, texts):
    """The part of [ref] the region's lines hold: from the first to the
    last of its words the lines' words match (runs of three or more)."""
    rk = [key(w) for w in ref]
    sk = [key(w) for w in tokens(' '.join(texts))]
    sm = difflib.SequenceMatcher(None, sk, rk, autojunk=False)
    hits = [(a, b, n) for a, b, n in sm.get_matching_blocks() if n >= 3]
    if not hits:
        return ref
    # (As many of the transcription's words before the first run and after
    # the last as the lines have words there.)
    a0, b0, _ = hits[0]
    a1, b1, n1 = hits[-1]
    return ref[max(0, b0 - a0):b1 + n1 + (len(sk) - a1 - n1)]

main()
