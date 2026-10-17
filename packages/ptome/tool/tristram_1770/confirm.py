"""A flagged line settled by the other reading: each flagged line's two
choices (`⟦ocr|transcription⟧`, `⟦+word⟧` a word the OCR lacks) tried
against the line as the other OCR reads it (Tesseract's where ABBYY's
was used, ABBYY's where Tesseract's), its letters: the choice whose
letters are that reading's (all but a letter or two in a long line)
taken. Writes draft.json again.

    python3 -I confirm.py
"""
import difflib, itertools, json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from common import WORK
from variant import variant


def key(t):
    t = re.sub(r'\[\.\w+\]#+|#+|__|\{\w+\}', '', t)
    return re.sub(r'[^a-z0-9]', '', t.lower().replace('ſ', 's').replace('f', 's').replace('&', 'and'))


def other_line(lines, box):
    """The other reading's line on [box]: its words whose middles lie in
    the box's rows, left to right."""
    y0, y1 = box[1], box[3]
    ws = []
    for l in lines:
        for w in l['w']:
            c = (w['b'][1] + w['b'][3]) / 2
            if y0 <= c <= y1 and box[0] - 40 <= w['b'][0] <= box[2] + 40:
                ws.append(w)
    return ' '.join(w['t'] for w in sorted(ws, key=lambda w: w['b'][0]))


def bare(w):
    return re.sub(r'^[^A-Za-z]*|[^A-Za-z’\']*$', '', re.sub(r'\[\.\w+\]#+|#+|__|\{\w+\}', '', w)).lower()


def choices(text):
    """The line's readings: each ⟦a|b⟧ either side, each ⟦+w⟧ in or out;
    the OCR's side only where it spells the transcription's word
    otherwise (another word, or a word more or less, the review's)."""
    parts = re.split(r'(⟦[^⟧]*⟧)', text)
    opts = []
    for p in parts:
        if p.startswith('⟦+'):
            opts.append([p[2:-1]])
        elif p.startswith('⟦'):
            a, _, b = p[1:-1].partition('|')
            opts.append([b, a] if b and variant(bare(a), bare(b)) else [b])
        else:
            opts.append([p])
    n = 1
    for o in opts:
        n *= len(o)
    if n > 256:
        return []
    return [''.join(c) for c in itertools.product(*opts)]


def main():
    draft = json.load(open(os.path.join(WORK, 'draft.json')))
    abbyy = json.load(open(os.path.join(WORK, 'ocr2.json')))
    tess = json.load(open(os.path.join(WORK, 'tess.json')))
    choice = json.load(open(os.path.join(WORK, 'choice.json')))
    settled = 0
    for p, v in draft.items():
        leaf = v['leaf']
        other = abbyy[leaf]['lines'] if choice.get(str(leaf)) == 'tess' else tess[str(leaf)]['lines']
        for l in v['lines']:
            if not l['flag'] or l.get('kind') in ('head', 'foot'):
                continue
            o = key(other_line(other, l['box']))
            if len(o) < 8:
                continue
            best, arg = 0, None
            for c in choices(l['text']):
                r = difflib.SequenceMatcher(None, key(c), o, autojunk=False).ratio()
                if r > best:
                    best, arg = r, c
            if arg is not None and best >= 0.98 and abs(len(key(arg)) - len(o)) <= 2:
                l['text'] = re.sub(r'\s+', ' ', arg).strip()
                l['flag'] = False
                l['confirmed'] = round(best, 3)
                settled += 1
    json.dump(draft, open(os.path.join(WORK, 'draft.json'), 'w'), indent=0)
    print(settled, 'lines settled;', sum(l['flag'] for v in draft.values() for l in v['lines']), 'still flagged')


if __name__ == "__main__":
    main()
