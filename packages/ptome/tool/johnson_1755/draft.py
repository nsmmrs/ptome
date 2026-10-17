"""A first draft of each printed line (lines.tsv, the OCR's lines) with
the long s read as round s: an OCR word not in the vocabulary
(tool/alice_1867/vocab.py's vocab.json) whose f's or l's (the long s and
its ligatures, ſt read as ll or ft) read as s make a word in it, the
likeliest such word. The draft is then read against the scan by eye.

    python3 -I draft.py   # JOHNSON_WORK/draft.tsv
"""
import itertools, json, os, re

WORK = os.environ.get('JOHNSON_WORK', os.path.expanduser('~/.cache/asciidart-work/print-match/johnson'))
VOCAB = json.load(open(os.path.expanduser('~/.cache/asciidart-work/alice-match/vocab.json')))


def count(w):
    return VOCAB.get(w.lower(), 0)


def variants(w, letters):
    spots = [i for i, c in enumerate(w) if c in letters]
    if len(spots) > 4:
        return
    for k in range(1, len(spots) + 1):
        for pick in itertools.combinations(spots, k):
            yield ''.join('s' if i in pick else c for i, c in enumerate(w))


def fix(w):
    have = count(w)
    best, n = w, have
    # an l read as s only where the word is no word at all: laid, lie
    for v in variants(w, 'fl' if have == 0 else 'f'):
        if count(v) > max(n, 5 * have):
            best, n = v, count(v)
    return best


def line(text):
    return re.sub(r"[A-Za-z]+", lambda m: fix(m.group()), text)


with open(os.path.join(WORK, 'lines.tsv')) as src, open(os.path.join(WORK, 'draft.tsv'), 'w') as out:
    for row in src:
        page, col, n, text = row.rstrip('\n').split('\t', 3)
        out.write(f'{page}\t{col}\t{n}\t{line(text)}\n')
