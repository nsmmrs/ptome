"""A first folio.spec from align.py's draft (draft.json): each printed
line a line of the spec, its kind from the transcription's element of
its first word: `H` a head, `D` a stage direction (set in the middle),
`S Speaker.|words` a speech's first line in prose, `V` in verse, two
spaces a line going on, `~v ` or `~p ` a line going on in verse or in
prose after the other;
a stage direction ending a line of speech (`Exit.`) after ` @`, set
flush right; the OCR's lines the text has none of (the running head,
the foot) left out, the foot to be written by hand (`@foot`). Read
against the scan by eye and corrected in folio.spec.

    python3 -I spec.py > folio.spec.draft
"""
import json, os, re

WORK = os.environ.get('TEMPEST_WORK', os.path.expanduser('~/.cache/asciidart-work/print-match/tempest'))
rows = json.load(open(os.path.join(WORK, 'draft.json'), encoding='utf-8'))


def word(t):
    return t[0]


def join(ts):
    s = ' '.join(word(t) for t in ts)
    return s.replace('_ _', ' ')


def verse(ts):
    """Whether the line is verse: most of its words a verse line's."""
    v = sum(1 for t in ts if t[1] == 'l')
    return v * 2 > len(ts)


page = col = None
mode = None
for r in rows:
    if r['page'] != page:
        page = r['page']
        col = None
        print(f'@page {page}')
    if r['col'] != col:
        col = r['col']
        print('@column')
    ts = r['tokens']
    if not ts:
        print(f'# ocr: {r["ocr"]}')
        continue
    els = [t[1] for t in ts]
    if els[0] == 'head':
        print('H ' + join(ts))
        mode = None
    elif all(e == 'stage' for e in els):
        print('D ' + join(ts))
        mode = None
    elif els[0] == 'speaker':
        n = 1
        while n < len(ts) and ts[n][1] == 'speaker':
            n += 1
        rest = ts[n:]
        tail = []
        while rest and rest[-1][1] == 'stage':
            tail.insert(0, rest.pop())
        mode = 'V' if verse(rest) else 'S'
        print(mode + ' ' + join(ts[:n]) + '|' + join(rest) + (' @' + join(tail) if tail else ''))
    else:
        rest = list(ts)
        tail = []
        while rest and rest[-1][1] == 'stage' and len(rest) > 1:
            tail.insert(0, rest.pop())
        now = 'V' if verse(rest) else 'S'
        # (A speech going from prose to verse or back: a paragraph of the
        # other kind, not set in.)
        # (After a direction or a head, a speech going on: a paragraph of
        # its own.)
        if mode is None or now != mode:
            print(('~v ' if now == 'V' else '~p ') + join(rest) + (' @' + join(tail) if tail else ''))
            mode = now
            continue
        mode = mode or now
        text = join(rest)
        # (A line wholly in italic going on with a speech: a song's, set
        # apart, its own indent.)
        if re.fullmatch(r'_[^_]+_', text):
            print('L ' + text + (' @' + join(tail) if tail else ''))
            continue
        print('  ' + text + (' @' + join(tail) if tail else ''))
