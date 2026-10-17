"""The decided pages: each line's text (text.tsv) with its pictures
resolved to the components (seg-frozen.json) they are traced from, and
each diagram's components, less those a line claims.

A picture in a line's text:
    {n}            the line's n-th symbol (groups-frozen.json)
    {B:n}          line B's n-th symbol, moved to this line; {B:n*} a copy
                   of it, as high on this line as on its own
    {n-m#=alt}     all the ink from its n-th symbol's box to its m-th's
    {*+B#=alt}     all the ink of the line's items, and line B's
    {w:TEXT=alt}   all the ink in the box of the line's OCR word TEXT
    {#x0,y0,x1,y1=alt}  all the ink in that box (scan px), the text's too
    {c4+c9}        those components (rev/comps-LEAF.png numbers them)
    {@x0,y0,x1,y1} the components whose centre is in that box (scan px)
    ...!           kept where it is, not in the line (a diagram's piece)
    ...=alt        its alternative text
A symbol not named is ink the text sets. A leaf's key `LEAF:dN` with
`@drop` drops its N-th diagram (from 0); `LEAF:initial` names the
initial's components (`c1`), or `@none`; `LEAF:+BASE` adds a line the
grouping missed, its extent `@at x0,x1` first.
"""
import json, os, re
HERE = os.path.dirname(os.path.abspath(__file__))
SEG = json.load(open(f'{HERE}/seg-frozen.json'))
G = json.load(open(f'{HERE}/groups-frozen.json'))
NAMED = {'therefore': '∴'}


def load_text():
    out = {}
    for row in open(f'{HERE}/text.tsv'):
        row = row.rstrip('\n')
        if not row or row.startswith('#'):
            continue
        k, t = row.split('\t', 1)
        assert k not in out, k
        out[k] = t
    return out


TEXT = load_text()


def inside(c, b, slack=3):
    return c[0] >= b[0] - slack and c[1] >= b[1] - slack and c[2] <= b[2] + slack and c[3] <= b[3] + slack


def owners(leaf):
    g = G[leaf]
    out = []
    for c in SEG[leaf]['comps']:
        own = None
        for li, l in enumerate(g['lines']):
            for ii, it in enumerate(l['items']):
                if it['kind'] == 'symbol' and inside(c['box'], it['box']):
                    own = ('s', li, ii)
        if own is None:
            for di, d in enumerate(g['diagrams']):
                if inside(c['box'], d['box']):
                    own = ('d', di)
        out.append(own)
    # (A symbol's stops and brackets, ink the OCR missed beside it, the
    # text's: thin, upright, black pieces, where the symbol has more.)
    def mark(c):
        b = c['box']
        w, h = b[2] - b[0], b[3] - b[1]
        # (A bracket, or the half of one a light print breaks, or a
        # comma: upright and thin; not a dotted line's round dot.)
        return c['inks']['black'] == c['px'] and (h >= 22 and w <= 20 and h >= 1.8 * w
                                                  or 10 <= h <= 26 and w <= 16 and h >= 1.4 * w)
    comps = SEG[leaf]['comps']
    for key in {o for o in out if o and o[0] == 's'}:
        mine = [ci for ci, o in enumerate(out) if o == key]
        if any(not mark(comps[ci]) for ci in mine):
            for ci in mine:
                if mark(comps[ci]):
                    out[ci] = None
    return out


def box_of(leaf, comps):
    if comps[0] == 'r':
        return list(comps[1:])
    bs = [SEG[leaf]['comps'][i]['box'] for i in comps]
    return [min(b[0] for b in bs), min(b[1] for b in bs), max(b[2] for b in bs), max(b[3] for b in bs)]


# (The inks by the present classify's split of red and yellow.)
INKS = json.load(open(f'{HERE}/inks.json'))


def inks_of(leaf, comps):
    tot = {}
    for i in comps:
        for k, v in INKS[leaf][i].items():
            tot[k] = tot.get(k, 0) + v
    return tot


_MASKS = {}


def comparison(leaf, box):
    """The sign of comparison in [box], by which side its upright is:
    Byrne's ⊏, greater than (open to the right), or ⊐, less than; None
    for another shape."""
    import numpy as np
    from PIL import Image
    if leaf not in _MASKS:
        from seg import W
        _MASKS[leaf] = np.asarray(Image.open(f'{W}/byrne/masks/rest-{leaf}.png')) > 0
    x0, y0, x1, y1 = box
    sub = _MASKS[leaf][y0:y1, x0:x1]
    if not sub.any() or not (25 <= x1 - x0 <= 80 and 20 <= y1 - y0 <= 70):
        return None
    cols = sub.sum(0)
    h = y1 - y0
    left, right = cols[: len(cols) // 4].max(), cols[-(len(cols) // 4):].max()
    middle = cols[len(cols) // 3: 2 * len(cols) // 3].mean()
    if middle > 0.5 * h:
        return None
    if left > 0.7 * h and right < 0.5 * h:
        return 'is greater than'
    if right > 0.7 * h and left < 0.5 * h:
        return 'is less than'
    return None


def alt_of(leaf, comps):
    inks = inks_of(leaf, comps)
    if inks['black'] == sum(inks.values()) and (sign := comparison(leaf, box_of(leaf, comps))):
        return sign
    bs = [SEG[leaf]['comps'][i]['box'] for i in comps]
    if inks['black'] == sum(inks.values()):
        if len(bs) == 2 and all(b[2] - b[0] > 2.5 * (b[3] - b[1]) for b in bs):
            return 'is equal to'
        if len(bs) == 3 and all(b[2] - b[0] < 20 and b[3] - b[1] < 20 for b in bs):
            return 'therefore'
    keep = {k: v for k, v in inks.items() if v > 0.08 * sum(inks.values())}
    names = ' and '.join(sorted(keep, key=lambda k: -keep[k]))
    b = box_of(leaf, comps)
    shape = 'line' if (b[2] - b[0]) > 3 * (b[3] - b[1]) else 'figure'
    return f'a {names} {shape}'


REF = re.compile(r'\{([^{}]+)\}')


def parse(leaf, li, line, text, own):
    """[text]'s pieces: ('text', s) and ('pic', comps, alt, float)."""
    syms = [ii for ii, it in enumerate(line['items']) if it['kind'] == 'symbol'] if line else []
    out = []
    pos = 0
    for m in REF.finditer(text):
        if m.start() > pos:
            out.append(('text', text[pos:m.start()]))
        pos = m.end()
        ref = m[1]
        if ref in NAMED:
            out.append(('text', NAMED[ref]))
            continue
        ref, _, alt = ref.partition('=')
        fl = ref.endswith('!')
        ref = ref.rstrip('!')
        src = None
        if ref.isdigit():
            ii = syms[int(ref) - 1]
            comps = [ci for ci, o in enumerate(own) if o == ('s', li, ii)]
        elif re.fullmatch(r'\d+:\d+\*?', ref):
            # (Another line's symbol: moved here, where it is; or, with
            # `*`, a copy, as high on this line as on its own.)
            base, n = ref.rstrip('*').split(':')
            oli = next(i for i, l in enumerate(G[leaf]['lines']) if l['base'] == int(base))
            osyms = [ii for ii, it in enumerate(G[leaf]['lines'][oli]['items']) if it['kind'] == 'symbol']
            comps = [ci for ci, o in enumerate(own) if o == ('s', oli, osyms[int(n) - 1])]
            if ref.endswith('*'):
                src = int(base)
        elif re.fullmatch(r'\d+-\d+#', ref):
            # (All the ink from the line's n-th symbol to its m-th: a line
            # whose dots the segmentation took for stops.)
            assert alt, (leaf, ref)
            a, b = (int(v) for v in ref[:-1].split('-'))
            bs = [line['items'][syms[i - 1]]['box'] for i in range(a, b + 1)]
            out.append(('pic', ('r', min(x[0] for x in bs) - 2, min(x[1] for x in bs) - 2,
                                max(x[2] for x in bs) + 2, max(x[3] for x in bs) + 2), alt, fl, None))
            continue
        elif re.fullmatch(r'\*(\+\d+)*#', ref):
            # (All the ink of a line of signs, and of the lines given that
            # the grouping split from it.)
            assert alt, (leaf, ref)
            bases = [int(v) for v in ref[1:-1].split('+') if v]
            items = list(line['items']) + [it for l in G[leaf]['lines'] if l['base'] in bases for it in l['items']]
            bs = [it['box'] for it in items]
            out.append(('pic', ('r', min(x[0] for x in bs) - 4, min(x[1] for x in bs) - 4,
                                max(x[2] for x in bs) + 4, max(x[3] for x in bs) + 4), alt, fl, None))
            continue
        elif ref.startswith('w:'):
            # (A word the OCR read that is a sign, ⊥ read `_L`: all the
            # ink in its box.)
            assert alt, (leaf, ref)
            b = next(it['box'] for it in line['items'] if it['kind'] == 'word' and it['text'].strip() == ref[2:])
            # (Its right edge in: the OCR's box runs on to the next ink.)
            out.append(('pic', ('r', b[0] - 2, b[1] - 4, b[2] - 3, b[3] + 4), alt, fl, None))
            continue
        elif ref.startswith('#'):
            # (All the ink in a box, the text's too: a bracketed group.)
            assert alt, (leaf, ref)
            out.append(('pic', ('r', *(int(v) for v in ref[1:].split(','))), alt, fl, None))
            continue
        elif ref.startswith('@'):
            b = [int(v) for v in ref[1:].split(',')]
            comps = [ci for ci, c in enumerate(SEG[leaf]['comps'])
                     if b[0] <= (c['box'][0] + c['box'][2]) / 2 <= b[2] and b[1] <= (c['box'][1] + c['box'][3]) / 2 <= b[3]]
        else:
            comps = [int(v.strip()[1:]) for v in ref.split('+')]
        assert comps, (leaf, li, m[0])
        if alt in ('is greater than', 'is less than'):
            # (A sign of comparison named by hand: by its shape, if it shows.)
            sign = comparison(leaf, box_of(leaf, comps))
            if sign and sign != alt:
                print(f'{leaf}: {m[0]} reads {sign!r}', file=__import__('sys').stderr)
                alt = sign
        out.append(('pic', tuple(sorted(comps)), alt or alt_of(leaf, comps), fl, src))
    if pos < len(text):
        out.append(('text', text[pos:]))
    return out


def page(leaf):
    """[leaf]'s decided page: its lines (base, extent, role, pieces),
    diagrams (comps), initial box; None for a line not decided."""
    g = G[leaf]
    own = owners(leaf)
    initial = g['initial']
    if (t := TEXT.get(f'{leaf}:initial')) is not None:
        # (The initial the grouping missed, or took a symbol for.)
        named = [] if t == '@none' else [int(v.strip()[1:]) for v in t.split('+')]
        initial = dict(box=box_of(leaf, named), comps=named) if named else None
    lines = []
    for li, l in enumerate(g['lines']):
        t = TEXT.get(f'{leaf}:{l["base"]}')
        if t is None:
            lines.append(dict(base=l['base'], undecided=True, items=l['items']))
            continue
        at = None
        if t.startswith('@at '):
            # (Its extent given: words the grouping put in another line.)
            _, a, t = t.split(' ', 2)
            at = [int(v) for v in a.split(',')]
        role = None
        if t.startswith('@'):
            role, _, t = t.partition(' ')
            role = role[1:]
        if role == 'skip':
            continue
        pieces = parse(leaf, li, l, t, own)
        # (The line's extent: its words and pictures, and the symbols not
        # named, ink the text sets, but not those of the initial's frame
        # or a diagram that the grouping gave the line.)
        outside = [initial['box']] if initial else []
        outside += [d['box'] for d in g['diagrams']]
        floats = {c for p in pieces if p[0] == 'pic' and p[3] and p[1][0] != 'r' for c in p[1]}
        outside += [SEG[leaf]['comps'][c]['box'] for c in floats]
        # (A line whose symbols another holds, which the grouping split
        # from it: its items this line's too.)
        moved = {int(b) for b in re.findall(r'\{(\d+):\d+\}', t)}
        items = list(l['items']) + [it for o in g['lines'] if o['base'] in moved for it in o['items']]
        kept = [it for it in items if it['kind'] != 'symbol'
                or not any(inside(it['box'], b, 8) or inside(b, it['box'], 0) for b in outside)]
        x0 = min(it['box'][0] for it in kept)
        x1 = max(it['box'][2] for it in kept)
        for p in pieces:
            if p[0] == 'pic' and not p[3]:
                b = box_of(leaf, p[1])
                x0, x1 = min(x0, b[0]), max(x1, b[2])
        if at:
            x0, x1 = at
        lines.append(dict(base=l['base'], x0=x0, x1=x1, role=role, pieces=pieces,
                          box=[x0, min(it['box'][1] for it in l['items']), x1, max(it['box'][3] for it in l['items'])]))
    for k, t in TEXT.items():
        lf, _, rest = k.partition(':')
        if lf != leaf or not rest.startswith('+'):
            continue
        at, _, t = t.partition(' ')
        assert at == '@at', k
        x0, x1 = (int(v) for v in t.split(' ', 1)[0].split(','))
        t = t.split(' ', 1)[1]
        role = None
        if t.startswith('@'):
            role, _, t = t.partition(' ')
            role = role[1:]
        base = int(rest[1:])
        lines.append(dict(base=base, x0=x0, x1=x1, role=role, pieces=parse(leaf, None, None, t, own),
                          box=[x0, base - 30, x1, base + 8]))
    lines.sort(key=lambda l: l['base'])
    claimed = set(initial.get('comps', ())) if initial else set()
    for l in lines:
        for p in l.get('pieces', ()):
            if p[0] != 'pic':
                continue
            if p[1][0] == 'r':
                claimed |= {ci for ci, c in enumerate(SEG[leaf]['comps']) if inside(c['box'], p[1][1:], 0)}
            else:
                claimed |= set(p[1])
    diagrams = []
    for di in range(len(g['diagrams'])):
        t = TEXT.get(f'{leaf}:d{di}')
        if t == '@drop':
            continue
        comps = tuple(ci for ci, o in enumerate(own) if o == ('d', di) and ci not in claimed)
        if t and t.startswith('-'):
            # (Less those named: the text's ink, an initial, it took in.)
            less = {int(v.strip()[1:]) for v in t[1:].split('+')}
            comps = tuple(c for c in comps if c not in less)
        elif t:
            # (Its components named: a diagram whose box took in lines.)
            comps = tuple(sorted(int(v.strip()[1:]) for v in t.split('+')))
        # (A line's hyphen at its end, which the diagram's box took in:
        # the text's, not the diagram's.)
        def hyphen(ci):
            c = SEG[leaf]['comps'][ci]
            x0, y0, x1, y1 = c['box']
            if c['inks']['black'] < 0.8 * c['px'] or not (8 <= x1 - x0 <= 26 and y1 - y0 <= 10):
                return False
            return any(l.get('x1') is not None and l['base'] - 30 <= y0 and y1 <= l['base'] + 2
                       and l['x1'] - 30 <= x0 <= l['x1'] + 40 and ''.join(
                           p[1] for p in l['pieces'] if p[0] == 'text').rstrip('_ ').endswith('-')
                       for l in lines if not l.get('undecided'))
        comps = tuple(c for c in comps if not hyphen(c))
        if comps:
            diagrams.append(comps)
    return dict(lines=lines, diagrams=diagrams, initial=initial, head=g['head'], size=g['size'])


def picture_name(leaf, comps):
    if comps[0] == 'r':
        return f'l{leaf}-r{comps[1]}x{comps[2]}.svg'
    return f'l{leaf}-c{comps[0]}.svg'
