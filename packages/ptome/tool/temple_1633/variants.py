"""The words where the scan's OCR reads another word of the book than the
TCP text has (a variant of the second edition, or the OCR's misreading
of one word as another): each with its line, for review against the
scan.

    python3 -I variants.py -> variants.json
"""
import difflib, json, os, re, sys, unicodedata
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from align import norm

S = json.load(open('stream.json'))
words = re.compile(r"[^\s]+")


def wnorm(w):
    return norm(w)


vocab = {}
for r in S:
    if 't' in r:
        for w in r['t'].split():
            k = wnorm(w)
            if k:
                vocab[k] = vocab.get(k, 0) + 1
out = []
for k, r in enumerate(S):
    if 'score' not in r or r['score'] < 0.55:
        continue
    tw = r['t'].split()
    ow = r['ocr'].split()
    a = [wnorm(w) for w in tw]
    b = [wnorm(w) for w in ow]
    sm = difflib.SequenceMatcher(None, a, b, autojunk=False)
    for tag, i1, i2, j1, j2 in sm.get_opcodes():
        if tag == 'equal':
            continue
        tx = ' '.join(tw[i1:i2]); ox = ' '.join(ow[j1:j2])
        ta = ''.join(a[i1:i2]); oa = ''.join(b[j1:j2])
        if ta == oa:
            # (The same letters, the words divided otherwise: spacing.)
            continue
        # (A reading that is words of the book: a candidate.)
        known = [x for x in b[j1:j2] if x]
        if known and all(vocab.get(x, 0) >= 1 for x in known) and oa != ta:
            out.append(dict(i=k, leaf=r['leaf'], line=r['line'], tcp=tx, ocr=ox, t=r['t'], o=r['ocr']))
        # (Punctuation and spelling within a word: -ie and -y, a doubled
        # letter; a reading close to the TCP's but another word.)
        elif len(ta) > 3 and len(oa) > 3 and difflib.SequenceMatcher(None, ta, oa).ratio() >= 0.75 and (
                ta.rstrip('e') == oa.rstrip('e') or ta.replace('ie', 'y') == oa.replace('ie', 'y')):
            out.append(dict(i=k, leaf=r['leaf'], line=r['line'], tcp=tx, ocr=ox, t=r['t'], o=r['ocr'], kind='spelling'))
json.dump(out, open('variants.json', 'w'), ensure_ascii=False, indent=0)
print(len(out), 'candidates')
