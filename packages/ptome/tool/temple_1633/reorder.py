"""Lines whose words the scan prints in another order than the TCP's:
each TCP word matched to the likeliest word of its scan line; where all
match and their order differs, a candidate (the second edition's
order), listed for review."""
import difflib, json, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen
from words import norm, lines_of
out = []
for ri, r in enumerate(gen.recs):
    if r['kind'] != 'l' or ri not in gen.MAIN:
        continue
    leaf, li = gen.MAIN[ri]
    ls = lines_of(leaf)
    if li >= len(ls):
        continue
    ow = [(w['box'][0], norm(w['t']), w['t']) for w in ls[li]['w'] if norm(w['t'])]
    tw = [norm(''.join(p for p, _ in w)) for w in r.get('words_new', r['words'])]
    if len(tw) < 2 or len(ow) < len(tw):
        continue
    pos = []
    used = set()
    ok = True
    for t in tw:
        best, bs = None, 0.0
        for k, (x, o, _) in enumerate(ow):
            if k in used:
                continue
            s = difflib.SequenceMatcher(None, t, o).ratio()
            if s > bs:
                best, bs = k, s
        if best is None or bs < 0.75 or len(t) < 3 and bs < 1:
            ok = False
            break
        used.add(best)
        pos.append(ow[best][0])
    if ok and pos != sorted(pos):
        out.append((ri, leaf, r['plain'], ' '.join(o[2] for o in ow)))
for o in out:
    print(o)
print(len(out))
