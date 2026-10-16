"""Lines wider than the measure in the look's face: where the printing
turns each one's last words (up or down, after a bracket), from the
neighbouring lines' ends on the scan."""
import difflib, json, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen
from words import norm, lines_of
from fontTools.ttLib import TTFont
F = {False: TTFont(os.path.expanduser('~/.local/share/fonts/ptome/IMFellDWPica-Regular.ttf')),
     True: TTFont(os.path.expanduser('~/.local/share/fonts/ptome/IMFellDWPica-Italic.ttf'))}
CM = {k: f.getBestCmap() for k, f in F.items()}
HM = {k: f['hmtx'] for k, f in F.items()}


def width(words, size=9.2):
    tot = 0
    for w in words:
        for p, it in w:
            tot += sum(HM[it][CM[it].get(ord(c), CM[it][ord('?')])][0] for c in p)
    tot += HM[False][CM[False][ord(' ')]][0] * (len(words) - 1)
    return tot * size / 2048


def find(ri):
    r = gen.recs[ri]
    words = r.get('words_new', r['words'])
    leaf, li = gen.MAIN.get(ri, (r['leaf'], None))
    if li is None:
        return None
    ls = lines_of(leaf)
    best = None
    for d0 in (-1, 1):
        d = d0
        while 0 <= li + d < len(ls) and len(norm(' '.join(w['t'] for w in ls[li + d]['w']))) < 4:
            d += d0
        if not (0 <= li + d < len(ls)):
            continue
        toks = [w['t'] for w in ls[li + d]['w']]
        for k in (1, 2, 3, 4):
            if k >= len(words):
                break
            tail = norm(' '.join(''.join(p for p, _ in w) for w in words[len(words) - k:]))
            for j in (1, 2, 3, 4):
                if j > len(toks):
                    break
                got = norm(' '.join(toks[len(toks) - j:]))
                sc = difflib.SequenceMatcher(None, tail, got).ratio()
                # (The neighbour line's own last words: no turn.)
                other = gen.LINE_REC.get((leaf, li + d))
                if other is not None and difflib.SequenceMatcher(
                        None, gen.rec_words_text(other, j), got).ratio() >= 0.75:
                    continue
                if sc >= 0.75 and (best is None or sc > best[0]):
                    frag = toks[len(toks) - j:]
                    # (From the bracket, where the OCR read it.)
                    for q in range(len(toks) - 1, max(-1, len(toks) - 5), -1):
                        if toks[q].startswith('('):
                            frag = [t for t in toks[q:] if t != '(']
                            break
                    best = (sc, k, d0, ' '.join(frag))
    return best


if __name__ == '__main__':
    MEASURE = 195
    out = {}
    for ri, r in enumerate(gen.recs):
        if r['kind'] != 'l' or 'poem' not in r['div']:
            continue
        w = width(r.get('words_new', r['words']))
        if w > MEASURE - 1:
            f = find(ri)
            print(ri, r['leaf'], round(w), r['plain'][:50], '->', f)
            if f:
                out[ri] = [f[1], f[2], f[3]]
    json.dump(out, open('turns.json', 'w'))
    print(len(out))
