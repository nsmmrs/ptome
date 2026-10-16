"""Each leaf of the scan as the generator reads it: its paper's top, its
furniture (running head or folio, catchword, signature) and its text
lines, each with its baseline (from the ink), its left edge, and the
TCP's words on it; its pictures (ornaments.json).

    python3 -I pages.py -> pages.json
"""
import glob, json, os, re, sys
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from words import lines_of, furniture, norm

W = os.path.join(os.environ.get('TEMPLE_WORK', os.path.expanduser('~/.cache/asciidart-work/print-match')), 'herbert')
D = glob.glob(f'{W}/*_jp2')[0]
NAME = D.split('/')[-1][:-4]
HERE = os.path.dirname(os.path.abspath(__file__))
placed = json.load(open(f'{HERE}/placed.json'))
PAPER = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'paper.json')))


def baseline(a, words):
    """A line's baseline: the bottom of its x-height band, from its words'
    ink (a tall box, an initial's, left out)."""
    hs = sorted(w['box'][3] - w['box'][1] for w in words)
    typical = hs[len(hs) // 2]
    ys = []
    for w in words:
        x0, y0, x1, y1 = w['box']
        if y1 - y0 > 1.6 * typical:
            continue
        prof = a[max(0, y0 - 6):y1 + 6, x0:x1].sum(1)
        if prof.max() == 0:
            continue
        band = np.nonzero(prof > 0.35 * prof.max())[0]
        ys.append(max(0, y0 - 6) + band[-1])
    return float(np.median(ys)) if ys else float(np.median([w['box'][3] for w in words]))


def main():
    by_leaf = {}
    for w in placed['words']:
        p = w['place']
        if p:
            by_leaf.setdefault(p['leaf'], []).append((p['line'], w['rec'], w['word'], p.get('split'), p.get('line2'),
                                                       p['box'][0], p.get('exact', False)))
    out = {}
    for leaf in range(0, 205):
        ls = lines_of(leaf)
        if not ls:
            out[leaf] = dict(lines=[], furniture={})
            continue
        a = np.asarray(Image.open(f'{D}/{NAME}_{leaf:04d}.jp2').convert('L')) < 120
        skip = furniture(leaf, ls)
        fur = {}
        lines = []
        on = {}
        for li, rec, word, split, line2, x, exact in by_leaf.get(leaf, []):
            on.setdefault(li, []).append(dict(rec=rec, word=word, split=split, x=x, exact=exact))
            if line2 is not None:
                on.setdefault(line2, []).append(dict(rec=rec, word=word, tail=True, x=0, exact=exact))
        for li, l in enumerate(ls):
            base = baseline(a, l['w'])
            text = ' '.join(w['t'] for w in l['w'])
            if li in skip:
                fur['head' if li == 0 else 'foot'] = dict(base=base, text=text, x0=l['w'][0]['box'][0],
                                                          x1=l['w'][-1]['box'][2])
                continue
            ws = sorted(on.get(li, []), key=lambda w: (w['rec'], w['word']))
            lines.append(dict(i=li, base=base, x0=l['w'][0]['box'][0], x1=l['w'][-1]['box'][2],
                              h=float(np.median([w['box'][3] - w['box'][1] for w in l['w']])),
                              text=text, words=ws))
        out[leaf] = dict(lines=lines, furniture=fur, paper=PAPER[str(leaf)])
        print(leaf, len(lines), end='; ', flush=True)
    json.dump(out, open(f'{HERE}/pages.json', 'w'))


if __name__ == '__main__':
    main()
