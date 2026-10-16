"""The Temple's text as the 1633 second edition prints it, page for page
and line for line, from the TCP's transcription (reviewed against the
scan) and the scan's lines.

    python3 -I gen.py OUT-DIR [MARGINS.json]

Writes OUT-DIR/temple.adoc (the book from the Church-porch on; the front
matter and the index by hand, front.adoc and titles.adoc) and
OUT-DIR/fit.json: each block with a place to fit, its page (the PDF's),
its kind, its first words and the baseline of its first line (points
from the page's top).
"""
import collections, json, os, re, statistics, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tcp2
from words import norm
import render

HERE = os.path.dirname(os.path.abspath(__file__))
W = os.path.join(os.environ.get('TEMPLE_WORK', os.path.expanduser('~/.cache/asciidart-work/print-match')), 'herbert')
PX = 72 / 800 * 0.8189        # the book's points per scan pixel
SHAPES = {}   # (poem, stanza length, line) -> the lines' indents, the first pass's
MEASURE = 195.0               # the text's width (241 pt less 23 pt each side)
PITCH = 9.62                  # the look's line pitch (9.2 pt, leading 1.0457)
H0 = 25.9                     # the running head's baseline, from the page's top
PAGES = json.load(open(f'{HERE}/pages.json'))
# (The bands of ornament on the pages the generator sets, by leaf, in
# their order down the page: fetch.yml's names; None, a band's second row,
# cut with its first.)
BAND_FILES = {24: ['temple-band-superliminare.png', None, 'temple-band-superliminare-foot.png'],
              25: ['temple-band-altar.png', 'temple-band-altar-foot.png'],
              199: ['temple-band-envoy.png']}
# (Other pictures on the pages the generator sets: the Church-porch's
# end, two flowers; fetch.yml's names and their boxes on the scan.)
PICTURES = {23: [('temple-flowers-porch.png', [1136, 3752, 2561, 4710])]}
# (A rule the pass over the pages missed: Superliminare's, between its
# stanzas, thick and broken.)
EXTRA_RULES = {24: [[500, 3000, 3100, 3040]]}
RULES = json.load(open(f'{HERE}/rules.json')) if os.path.exists(f'{HERE}/rules.json') else {}
PLACED = json.load(open(f'{HERE}/placed.json'))['words']
recs = render.recs
render.apply_review()
# (Lines the review of variants missed: words the second edition sets in
# another order, or adds; overrides.json, by record.)
OVERRIDES = json.load(open(f'{HERE}/overrides.json')) if os.path.exists(f'{HERE}/overrides.json') else {}
for _k, _t in OVERRIDES.items():
    render.retext(recs[int(_k)], _t)

# ---------------------------------------------------------------- places

def record_lines():
    """Each record's (leaf, OCR line index) by its words: the line most of
    its exactly matched words are on (else its words matched at all);
    records with none interpolated from their neighbours."""
    by = collections.defaultdict(list)
    for w in PLACED:
        p = w['place']
        if p:
            by[w['rec']].append((w['word'], p['leaf'], p['line'], bool(p.get('exact')), p['box'][0]))
    main = {}
    for ri in range(len(recs)):
        ws = by.get(ri, [])
        ex = [w for w in ws if w[3]] or ws
        if not ex:
            continue
        c = collections.Counter((w[1], w[2]) for w in ex)
        main[ri] = c.most_common(1)[0][0]
    return main, by


MAIN, BY = record_lines()


def fix_heading_lines():
    """A poem title's OCR line by its place: between the lines of the
    records before and after it on its leaf, the line most like it (the
    OCR reads a short title, `II.`, badly, and its words may match
    elsewhere)."""
    import difflib
    for ri, r in enumerate(recs):
        if r['kind'] != 'head' or 'poem' not in r['div']:
            continue
        leaf = r['leaf']
        before = next((MAIN[j] for j in range(ri - 1, max(-1, ri - 6), -1)
                       if j in MAIN and MAIN[j][0] == leaf), None)
        after = next((MAIN[j] for j in range(ri + 1, min(len(recs), ri + 6))
                      if j in MAIN and MAIN[j][0] == leaf and recs[j]['kind'] != 'head'), None)
        lo = before[1] if before else -1
        hi = after[1] if after else 10 ** 6
        cands = [l for l in PAGES[str(leaf)]['lines'] if lo < l['i'] < hi]
        if not cands:
            continue
        want = norm(r['plain'])
        best = max(cands, key=lambda l: (difflib.SequenceMatcher(None, want, norm(l['text'])).ratio(), l['h']))
        MAIN[ri] = (leaf, best['i'])


fix_heading_lines()
LINE = {}
for _ri, _w in MAIN.items():
    pass
for leaf, v in PAGES.items():
    for l in v['lines']:
        LINE[(int(leaf), l['i'])] = l


# (A running head as the OCR reads it: The Church., The Church-porch.,
# The Church Militant., a folio.)
HEADLIKE = re.compile(r'(?i)(\bthe\s*c\w|ch\w{0,3}[ct]?h\b|c\s?h\s?u\s?r|porc|port|milit|^\W*\d{1,3}(\W|$))')
# (A poem's title the head pattern would take, `The Collar.`: not a head.)
NOT_HEAD = re.compile(r'(?i)collar|call\b|crosse|church-|clasping')


# (The pages whose running head the OCR doesn't read at all, a stanza
# at their top: the head a line and a tenth above it, as on the pages
# whose head it reads.)
HEAD_BASE = {51: 768, 105: 713}


def head_lines(leaf):
    """The page's lines the OCR read its running head as (in pieces
    side by side, `The Chitych-` `porch,`), among its first lines."""
    ls = PAGES[str(leaf)]['lines'][:5]
    if not ls:
        return []
    first = [l for l in ls if HEADLIKE.search(l['text']) and not NOT_HEAD.search(l['text'])
             and sum(c.isalpha() for c in l['text']) >= 3]
    if not first:
        return []
    base = first[0]['base']
    return [l for l in ls if abs(l['base'] - base) < 60 and HEADLIKE.search(l['text'])]


def head_base(leaf):
    """The leaf's running head's baseline (pixels), else where it would be;
    a hand-set page's own (`// head-base: PX`)."""
    mp = f'{HERE}/manual/leaf{leaf}.adoc'
    if os.path.exists(mp):
        m = re.search(r'^// head-base: (\d+)', open(mp, encoding='utf-8').read(), re.M)
        if m:
            return int(m[1])
    if leaf in HEAD_BASE:
        return HEAD_BASE[leaf]
    v = PAGES[str(leaf)]
    h = v['furniture'].get('head')
    if h and HEADLIKE.search(h['text']):
        return h['base']
    # (The OCR's running head among the page's first lines, where the
    # furniture its words were taken for is something else, a speck.)
    heads = [l['base'] for l in head_lines(leaf)]
    if heads:
        return statistics.median(heads)
    if h:
        return h['base']
    p = v.get('paper')
    if p and 5500 < p['y1'] - p['y0'] < 6100:
        return p['y0'] + 351
    # (From the leaves either side.)
    for d in (1, -1, 2, -2):
        h = PAGES.get(str(leaf + d), {}).get('furniture', {}).get('head')
        if h:
            return h['base']
    return 900


def edge(leaf):
    """The text's left edge (pixels): the lowest of the left edges most
    lines start at."""
    xs = []
    for l in PAGES[str(leaf)]['lines']:
        ws = [w for w in l['words'] if w.get('exact') and not w.get('tail')]
        if len(ws) >= 3:
            xs.append(min(w['x'] for w in ws))
    if not xs:
        return None
    xs.sort()
    # (The first cluster of three within 25 px.)
    for i in range(len(xs) - 2):
        if xs[i + 2] - xs[i] < 25:
            return xs[i]
    return xs[0]


EDGES = {}
for leaf in range(205):
    EDGES[leaf] = edge(leaf)


def edge_of(leaf):
    e = EDGES.get(leaf)
    # (A page whose every line is set in, a shaped poem's: its neighbours'
    # edge of the same side, relative to the running head's left.)
    if e is None or not PAGES[str(leaf)]['lines']:
        return None
    return e


# ---------------------------------------------------------------- turns

import difflib
from words import lines_of


def turn_tokens(leaf, li):
    """The words the printing turns onto OCR line [li] of [leaf]: from a
    word opening with a bracket in the line's right half, to its end."""
    ls = lines_of(leaf)
    if li is None or li < 0 or li >= len(ls):
        return None
    ws = ls[li]['w']
    e = EDGES.get(leaf) or 0
    for k, w in enumerate(ws):
        if w['t'].startswith('(') and w['box'][0] > e + 1100 and k > 0:
            return [x['t'].lstrip('(') for x in ws[k:]]
    return None


LINE_REC = {where: ri for ri, where in MAIN.items()}
# (Lines too wide for the measure, where the printing turns their last
# words: turns.py.)
TURN_TEXT = {}
SPEAKERS = {}
TURNS = json.load(open(f'{HERE}/turns.json')) if os.path.exists(f'{HERE}/turns.json') else {}


def own_tail_present(leaf, li, tail):
    """Whether OCR line [li] of [leaf] ends with [tail] (letters) itself,
    before any bracketed words."""
    ls = lines_of(leaf)
    if li is None or li < 0 or li >= len(ls):
        return False
    toks = []
    for w in ls[li]['w']:
        if w['t'].startswith('(') and toks:
            break
        toks.append(w['t'])
    got = norm(' '.join(toks))[-len(tail) - 2:]
    return bool(tail) and difflib.SequenceMatcher(None, tail, got).ratio() >= 0.75


def rec_words_text(ri, k):
    ws = recs[ri].get('words_new', recs[ri]['words'])
    return norm(' '.join(''.join(p for p, _ in w) for w in ws[len(ws) - k:]))


def turned(ri, leaf, li, words):
    """The record's last words the printing turns up or down, after a
    bracket at the end of the line above or below: (k, direction), else
    None. A bracket the OCR reads for a long s (`(word` for `sword`), the
    neighbour line's own word, is none."""
    n = len(words)
    ls = lines_of(leaf)
    for d0 in (-1, 1):
        # (The next line of text up or down, past the OCR's specks.)
        d = d0
        while 0 <= li + d < len(ls) and len(norm(' '.join(w['t'] for w in ls[li + d]['w']))) < 4:
            d += d0
        toks = turn_tokens(leaf, li + d)
        if not toks:
            continue
        got = norm(' '.join(toks))
        # (The neighbour's own last words: a long s misread.)
        other = LINE_REC.get((leaf, li + d))
        if other is not None:
            last = rec_words_text(other, 1)
            if last.startswith('s') and difflib.SequenceMatcher(None, last[1:], got).ratio() >= 0.75:
                continue
        for k in (1, 2, 3):
            if k >= n:
                break
            tail = norm(' '.join(''.join(p for p, _ in w) for w in words[n - k:]))
            if tail and difflib.SequenceMatcher(None, tail, got).ratio() >= 0.7 \
                    and not own_tail_present(leaf, li, tail):
                TURN_TEXT[(ri, d0)] = ' '.join(toks)
                return k, d0
    return None


# ---------------------------------------------------------------- output

def target(leaf, base_px):
    return (base_px - head_base(leaf)) * PX + H0


def pdf_line_count(body):
    """How many lines [body] sets in the PDF."""
    n, other = 0, False
    for ln in body:
        if ln.startswith('ifndef::backend-pdf'):
            other = True
        elif ln.startswith('endif::'):
            other = False
        elif not other and ln.strip() and not ln.startswith(('ifdef', '//')):
            n += 1
    return max(1, n)


def block_key(page, kind, first, tgt):
    letters = re.sub(r'[^a-z]', '', first.lower())[:24]
    return f'{page}:{kind}:{letters}' if letters else f'{page}:{kind}:{int(tgt)}'


FOOT_ROLES = set()


class Out:
    def __init__(self, margins):
        self.lines = []
        self.fits = []
        self.margins = margins
        self.n_seen = {}
        self.ruled = set()
        self.last_line = {}

    def key(self, page, kind, first, tgt):
        """A fitted block's key, the same while the text above it on its
        page changes: its page, kind and first letters (a rule's, its
        target's point), a second of the same on its page numbered."""
        k = block_key(page, kind, first, tgt)
        self.n_seen[k] = self.n_seen.get(k, 0) + 1
        return k if self.n_seen[k] == 1 else f'{k}#{self.n_seen[k]}'

    def rules(self, leaf, below=None):
        """The leaf's rules (the scan's, rules.json) above [below] (points
        from the page's top; all where None) not yet set: each a thematic
        break fitted to the rule's top."""
        if os.path.exists(f'{HERE}/manual/leaf{leaf}.adoc'):
            return
        bands = [r for r in RULES.get(str(leaf), []) if r['kind'] == 'band']
        pictures = sorted(RULES.get(str(leaf), []) + [dict(kind='band', box=b, name=n) for n, b in PICTURES.get(leaf, [])]
                          + [dict(kind='rule', box=b) for b in EXTRA_RULES.get(leaf, [])],
                          key=lambda r: r['box'][1])
        for r in pictures:
            if (leaf, r['box'][1]) in self.ruled:
                continue
            if r['kind'] == 'band' and (leaf in BAND_FILES or 'name' in r):
                # (A band of ornament: the scan's, cut out (fetch.yml), as
                # wide as the printing's, its top fitted.)
                tgt = target(leaf, r['box'][1])
                if below is not None and tgt >= below:
                    continue
                self.ruled.add((leaf, r['box'][1]))
                name = r['name'] if 'name' in r else BAND_FILES[leaf][bands.index(r)]
                if name is None:
                    continue
                k = self.key(leaf + 1, 'image', '', tgt)
                self.fits.append(dict(key=k, page=leaf + 1, kind='image', first='', target=round(tgt, 2)))
                self.lines.extend(['ifdef::backend-pdf[]', f'[.band,margin-top={self.margins.get(k, 0.0):.2f}pt]',
                                   f'image::{name}[pdfwidth={(r["box"][2] - r["box"][0]) * PX:.1f}pt]',
                                   'endif::[]', ''])
                continue
            if r['kind'] != 'rule':
                continue
            tgt = target(leaf, (r['box'][1] + r['box'][3]) / 2)
            if below is not None and tgt >= below:
                continue
            self.ruled.add((leaf, r['box'][1]))
            k = self.key(leaf + 1, 'rule', '', tgt)
            self.fits.append(dict(key=k, page=leaf + 1, kind='rule', first='', target=round(tgt, 2)))
            self.lines.append(f'[.poem-rule,margin-top={self.margins.get(k, 0.0):.2f}pt]')
            self.lines.extend(["'''", ''])

    def foot(self, leaf, catch, sig=None):
        """The leaf's foot line, in the PDF: its catchword at the right
        (fitted to the scan's), its signature at the same line."""
        if catch is None:
            return
        cw = catch.get(leaf)
        sig = sig or signature(leaf)
        tgt = foot_target(leaf, cw, self.last_line.get(leaf))
        if tgt is None or (cw is None and sig is None):
            return
        self.lines.append('ifdef::backend-pdf[]')
        first = True
        for role, text in (('foot-cw', cw), ('foot-sig', sig)):
            if text is None:
                continue
            if first:
                k = self.key(leaf + 1, 'foot', text, tgt)
                self.fits.append(dict(key=k, page=leaf + 1, kind='foot', first=text, target=round(tgt, 2)))
                self.lines.append(f'[.{role},margin-top={self.margins.get(k, 0.0):.2f}pt]')
            else:
                # (On the catchword's line.)
                self.lines.append(f'[.{role},margin-top=-{PITCH:.2f}pt]')
            if role == 'foot-sig':
                # (Its middle where the printing's are, 118 pt in.)
                width = sum(4.6 if c.isdigit() else 2.3 if c == ' ' else 6.6 for c in text)
                q = round((118.0 - width / 2) * 2) / 2
                self.lines.append(f'[.i{int(q * 10)}]##{{nbsp}}##{render.esc(text)}')
                FOOT_ROLES.add((f'i{int(q * 10)}', q))
            else:
                self.lines.append(f'{render.esc(text)}[.i15]##{{nbsp}}##')
                FOOT_ROLES.add(('i15', 1.5))
            self.lines.append('')
            first = False
        self.lines.extend(['endif::[]', ''])

    def block(self, attrs, body, fit=None):
        """A block: its attribute list's entries (a role first), its lines;
        its own margin-top fitted where [fit] (page, kind, first, target);
        the rules above it on its page first."""
        if fit:
            self.rules(fit[0] - 1, fit[3])
        if fit:
            page, kind, first, tgt = fit
            # (Its last line's baseline, for the foot line under it.)
            m_ = re.search(r'\.p(\d{3,4})\b', attrs[0]) if attrs else None
            pitch = int(m_[1]) / 100 if m_ else PITCH
            self.last_line[page - 1] = max(self.last_line.get(page - 1, 0.0),
                                           tgt + (pdf_line_count(body) - 1) * pitch)
            k = self.key(page, kind, first, tgt)
            self.fits.append(dict(key=k, page=page, kind=kind, first=first, target=round(tgt, 2)))
            attrs = attrs + [f'margin-top={self.margins.get(k, 0.0):.2f}pt']
        if attrs:
            self.lines.append('[' + ','.join(attrs) + ']')
        self.lines.extend(body)
        self.lines.append('')


# (Poems whose first capital the printing sets larger in its line, not
# dropped.)
NO_DROP = ('O Do not use me', 'MY God, I heard this day', 'O What a cunning guest', 'OH, what a thing is man',
           'WHen God at first made man', 'COme away')
# (Stanzas whose first capital the printing drops that the TCP doesn't
# mark: Superliminare's second, the Foil's.)
FORCE_DROP = ('AVoid', 'If we could see below')
INITIAL_EXCEPT = ('A broken ALTAR', 'Lord, who createdst', 'My tender age', 'If we could see')


def opens_with_initial(ri):
    """Whether the poem's first line opens with a capital two lines high:
    its first word in two capitals (`THou`), or a capital alone before a
    capitalized word (`I Have`, `O My`)."""
    r = recs[ri]
    plain = r['plain']
    if plain.startswith(INITIAL_EXCEPT) or r['decor']:
        return bool(r['decor'])
    ws = plain.split()
    if not ws:
        return False
    if re.match(r'^[A-Z]{2}', ws[0]):
        return True
    return len(ws) > 1 and re.fullmatch(r'[AIO]', ws[0]) is not None and ws[1][:1].isupper() and ws[1][1:2].islower()


def indent_role(pts):
    q = max(0.0, round(pts * 2) / 2)
    if q < 0.75:
        return None, 0
    return f'i{int(round(q * 10))}', q


# (The titles the printing marks with a section sign, not a pilcrow: by
# the PDF's page and their letters.)
SECTION_TITLES = {(83, 'sighsandgrones'), (131, 'mansmedley'), (133, 'paradise'), (138, 'thefamilie'),
                  (143, 'justice'), (143, 'thepilgrimage'), (155, 'thecollar'), (157, 'assurance'),
                  (158, 'thecall'), (161, 'josephscoat'), (162, 'thepriesthood'), (174, 'theglance'),
                  (175, 'thepsalme')}

# (Lines the second edition sets in italic, the first in roman: Justice's
# antitheses, and others.)
ITALIC_LINES = ('Lord, thou didst make me, yet', 'Lord, thou dost wound me, yet', 'Lord, thou relievest, yet',
                'Lord, thou dost kill me, yet', 'For, I do praise thee, yet', 'My prayers mean thee, yet',
                'I would do well, yet sinne', 'My soul doth love thee, yet',
                # (Dialogue's Saviour.)
                'What (childe) is the ballance thine', 'Thine the poise and measure', 'If I say, Thou shalt be mine',
                'Finger not my treasure', 'What the gains in having thee', 'Do amount to, onely he,',
                'Who for man was sold, can see', "That transferr'd th' accounts to me", 'That is all, if that I could',
                'Get without repining', 'And my clay my creature would', 'Follow my resigning',
                'That as I did freely part', 'With my glorie and desert', 'Left all joyes to feel all smart',
                # (Love unknown's friend; the Method's answers.)
                'For ought I heare, your Master shows', 'More favour then you wot of', 'The Font did onely, what was old',
                'The Caldron suppled', 'The thorns did quicken', 'All did but strive to mend',
                "Wherefore be cheer'd", 'Each day, each houre, each moment', 'Who fain would have you be',
                'Late when I would have something done', 'I had a motion to forbear', 'Glad heart rejoyce.',
                # (The Size's close; Artillerie's starre.)
                "These fears are tears, and heav'n the haven.", 'Do as thou usest, disobey,',
                'Expell good motions from thy breast,', 'Which have the face of fire, but end in rest.',
                # (The Church Militant's refrain; L'Envoy's close.)
                'How deare to me, O God, thy counsels are', 'Who may with thee compare?',
                'Blessed be God alone,', 'Thrice blessed Three in One.',
                # (Heaven's echoes.)
                'Echo.',
                # (Miserie's refrain, Jordan's close.)
                'Man is but grasse,', 'He knows it, fill the glasse.',
                "There is in love a sweetnesse ready penn'd", 'Copie out onely that, and save expense.')

# (The Sacrifice's refrain, which the printing sets in italic.)
REFRAINS = ('Was ever grief like mine?', 'Was ever grief, &c.', 'Never was grief like mine.',
            'But thou shalt answer, Lord, for me.')


def line_text(ri, words):
    plain = ' '.join(''.join(p for p, _ in w) for w in words)
    if plain in REFRAINS or plain.startswith(ITALIC_LINES):
        words = [[(p, True) for p, _ in w] for w in words]
    # (A word in capitals, ALTAR, SACRIFICE: in spaced capitals, as the
    # printing sets them.)
    return re.sub(r"(?<![\w\[#])(?!FINIS)([A-Z])([A-Z]{2,})(?=[,.;:?!']*(\s|$))", r'[.spaced-cap]##\1##[.spaced]##\2##',
                  render.markup(words))


def manual(o, leaf):
    """A page set by hand (manual/leafNN.adoc): its blocks as written, a
    block whose attribute list holds `ocr=N` fitted to OCR line N's
    baseline (`top=PX` to a picture's top, in the scan's pixels)."""
    lines = open(f'{HERE}/manual/leaf{leaf}.adoc', encoding='utf-8').read().split('\n')
    # (Its last line of text, for the foot line: the scan's.)
    texts = [l for l in PAGES[str(leaf)]['lines'] if sum(c.isalpha() for c in l['text']) >= 6]
    if texts:
        o.last_line[leaf] = target(leaf, texts[-1]['base'])
    for line in lines:
        m = re.match(r'^\[(.*)\]$', line)
        if m and re.search(r'(^|,)(ocr|top|base)=', m[1]):
            entries = [e for e in re.sub(r'(^|,)first="[^"]*"', '', m[1]).split(',')
                       if e and not re.match(r'^(ocr|top|base)=', e)]
            ocr = re.search(r'(?:^|,)ocr=(\d+)', m[1])
            top = re.search(r'(?:^|,)top=(\d+)', m[1])
            base = re.search(r'(?:^|,)base=(\d+)', m[1])
            first = re.search(r'(?:^|,)first="([^"]*)"', m[1])
            letter = 'letter' in entries
            column = 'column' in entries
            entries = [e for e in entries if e not in ('letter', 'column')]
            if base:
                # (A line's baseline measured on the scan, in pixels.)
                tgt = target(leaf, int(base[1]))
                kind = 'heading' if lines[lines.index(line) + 1].startswith('=') else 'letter' if letter \
                    else 'column' if column else 'text'
            elif ocr:
                l = next(x for x in PAGES[str(leaf)]['lines'] if x['i'] == int(ocr[1]))
                tgt = target(leaf, l['base'])
                kind = 'text'
            else:
                tgt = target(leaf, int(top[1]))
                kind = 'heading' if lines[lines.index(line) + 1].startswith('=') else 'image'
            k = o.key(leaf + 1, kind, first[1] if first else '', tgt)
            o.fits.append(dict(key=k, page=leaf + 1, kind=kind, first=first[1] if first else '', target=round(tgt, 2)))
            entries.append(f'margin-top={o.margins.get(k, 0.0):.2f}pt')
            o.lines.append('[' + ','.join(entries) + ']')
        else:
            o.lines.append(line)


LOOK = os.path.join(os.environ.get('TEMPLE_HERBERT', os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'test', 'showcase', 'herbert')), 'herbert-look.yml')


def update_look(roles):
    """The look's indent roles, one for each indent the text uses."""
    lines = open(LOOK, encoding='utf-8').read().split('\n')
    start = next(i for i, l in enumerate(lines) if 'generated.)' in l)
    end = start + 1
    while end < len(lines) and re.match(r'^    [ip]\d+: \{ (width|line_pitch): ', lines[end]):
        end += 1
    gen_lines = [f'    {r}: {{ width: {q}pt }}' for r, q in sorted(roles, key=lambda x: x[1]) if r[0] == 'i']
    gen_lines += [f'    {r}: {{ line_pitch: {q}pt }}' for r, q in sorted(roles, key=lambda x: x[1]) if r[0] == 'p']
    lines[start + 1:end] = gen_lines
    # (In HTML and EPUB, each indent a space of its width: one rule, after
    # the look's own.)
    css = '  ' + ''.join(f'.{r}{{display:inline-block;width:{q}pt}}' for r, q in sorted(roles, key=lambda x: x[1])
                         if r[0] == 'i')
    for key in ('css: |', 'epub-css: |'):
        i = lines.index(key)
        j = i + 1
        while j < len(lines) and lines[j].startswith('  '):
            j += 1
        block = [l for l in lines[i + 1:j] if not l.startswith('  .i')]
        lines[i + 1:j] = block + [css]
    open(LOOK, 'w', encoding='utf-8').write('\n'.join(lines))


def sub_fit(leaf, where, text):
    """A title's second line's place: the scan's next line after the
    title's."""
    if where[1] is None:
        return None
    nxt = [l for l in PAGES[str(leaf)]['lines'] if l['i'] > where[1]]
    if not nxt:
        return None
    return (leaf + 1, 'text', text, target(leaf, nxt[0]['base']))


# (The sheets' signature letters: the alphabet of the time, without J,
# U and W.)
LETTERS = 'ABCDEFGHIKLMNOPQRSTVXYZ'
CATCH_PATH = f'{HERE}/catchwords.json'
# (Catchwords the printing sets otherwise than the next page's first word:
# cut short, `¶ Un-`, or with a section sign for the pilcrow, `§ The`; by
# the PDF's page, from the review of the scan's feet.)
CATCH = json.load(open(CATCH_PATH)) if os.path.exists(CATCH_PATH) else {}


def signature(leaf):
    """The leaf's signature: the first five leaves of each sheet of 24
    pages signed on their rectos, `A`, `A 2` ... `A 5`."""
    p = leaf - 7
    if p < 1 or p % 2 == 0:
        return None
    k = ((p - 1) % 24) // 2 + 1
    if k > 5:
        return None
    letter = LETTERS[(p - 1) // 24]
    return letter if k == 1 else f'{letter} {k}'


def first_word(lines):
    """The first word a page's lines set (in the PDF), as a catchword:
    a title's pilcrow with the word after it; a word after a drop initial
    in its own case (`LOrd,`, `Lord,`)."""
    other = False
    notitle = False
    for ln in lines:
        # (A title the PDF doesn't show, `%notitle`: not read.)
        if ln.startswith('[') and '%notitle' in ln:
            notitle = True
            continue
        if notitle and ln.startswith('='):
            notitle = False
            continue
        if ln.startswith('ifndef::backend-pdf'):
            other = True
            continue
        if ln.startswith('endif::'):
            other = False
            continue
        if other or not ln.strip() or re.match(r'^\[[^\]]*\]$', ln) \
                or ln.startswith(('//', 'ifdef', 'image::', "'''", '<<<', '____')):
            continue
        t = ln.lstrip('=').strip() if ln.startswith('=') else ln
        t = re.sub(r'\[\.[^\]]*\]##\{nbsp\}##', ' ', t)
        t = re.sub(r'\[\.[^\]]*\]##([^#]*)##', r'\1 ', t)
        t = re.sub(r'\[\.turn\]#\([^#]*#', '', t)
        t = t.replace('__', '').replace('{nbsp}', ' ').replace('{plus}', '+')
        t = re.sub(r'\\(.)', r'\1', t)
        words = t.split()
        if not words:
            continue
        w = f'{words[0]} {words[1]}' if words[0] in ('¶', '§') and len(words) > 1 else words[0]
        if re.match(r'^[A-Z][A-Z][a-z]', w):
            w = w[0] + w[1].lower() + w[2:]
        return w
    return None


# (The foot lines of the pages whose lines the OCR can't read, Easter-
# wings' sideways stanzas, and of those under a band of ornament:
# measured on the scan.)
FOOT_BASE = {41: 4966, 42: 4786, 24: 5150, 25: 5352, 200: 5541, 201: 5667}


def foot_target(leaf, cw, last):
    """The leaf's foot line's baseline (points): the scan's, where the
    OCR read the catchword on a line a little below the page's last line
    of text ([last], points), else a line and a tenth below that."""
    if leaf in FOOT_BASE:
        return target(leaf, FOOT_BASE[leaf])
    if last is None:
        return None
    want = norm(cw or '')[:3]
    cands = list(PAGES[str(leaf)]['lines'])
    if PAGES[str(leaf)]['furniture'].get('foot'):
        cands.append(dict(PAGES[str(leaf)]['furniture']['foot']))
    for l in cands:
        y = target(leaf, l['base'])
        # (The catchword's line: few letters but the catchword's and a
        # signature's, the OCR's reading of a text line's end aside.)
        if want and last + 7.5 < y < last + 16 and want in norm(l['text']) \
                and len(norm(l['text'])) <= len(norm(cw)) + 6:
            return y
    return last + 10.5


def foot_base(leaf):
    """The leaf's foot line's baseline (pixels): the scan's catchword
    line's, else a line and a tenth below its last line of text."""
    if leaf in FOOT_BASE:
        return FOOT_BASE[leaf]
    f = PAGES[str(leaf)]['furniture'].get('foot')
    ls = [l for l in PAGES[str(leaf)]['lines'] if sum(c.isalpha() for c in l['text']) >= 6]
    last = ls[-1]['base'] if ls else None
    if f and (last is None or 2.0 < (f['base'] - last) * PX < 20.0):
        return f['base']
    return last + 10.5 / PX if last is not None else None


# (A two-line drop's width with the gap after it, roughly, by its
# letter: the room the lines beside it start past.)
def after_drop(pre, text):
    """A dropped line's text with its indent after the drop's letter,
    the room it leaves beside the drop."""
    if not pre:
        return text
    m = re.match(r'^(__)?([A-Za-z])', text)
    if not m:
        return pre + text
    return m[2] + pre + (m[1] or '') + text[m.end():].lstrip()


def drop_width(letter):
    w = {'I': 9.0, 'J': 9.0, 'M': 23.0, 'W': 24.0, 'O': 18.0, 'Q': 18.0, 'C': 17.0, 'G': 18.0, 'D': 18.0}
    return w.get(letter, 16.0) + 2.8


_SCANS = {}
_EDGE_FITS = {}


def line_left(leaf, l):
    """Where an OCR line's letters start (pixels): the ink's start on
    the scan where it is near the OCR's first word's (a shadow, a speck
    left of it, not), else the OCR's."""
    x = ink_left(leaf, l['base'])
    if x is not None and abs(x - l['x0']) <= 40:
        return x
    return l['x0']


def local_edge(leaf, base):
    """The text's left edge at a line's baseline (pixels): the film's
    skew and the page's curl bend it, so the lower envelope of where the
    page's lines start, a curve down the page (its lines set in left out
    in turn)."""
    import numpy as np
    if leaf not in _EDGE_FITS:
        pts = []
        for l in PAGES[str(leaf)]['lines']:
            # (Lines of the text the OCR read, not its readings of specks.)
            if sum(c.isalpha() for c in l['text']) >= 6 and sum(1 for w in l['words'] if w.get('exact')) >= 2:
                pts.append((l['base'], line_left(leaf, l)))
        fit = None
        if len(pts) >= 6:
            a = np.array(pts, dtype=float)
            deg = 2 if len(pts) >= 12 else 1
            for _ in range(5):
                c = np.polyfit(a[:, 0], a[:, 1], deg)
                res = a[:, 1] - np.polyval(c, a[:, 0])
                keep = a[res <= 12]
                if len(keep) < deg + 3:
                    break
                a = keep
            c = np.polyfit(a[:, 0], a[:, 1], deg)
            # (A page whose every line is set in: its edge where the
            # pages around it have theirs.)
            e = edge_of(leaf)
            mid = float(np.polyval(c, np.median([p[0] for p in pts])))
            if e is not None and mid - e > 40:
                c[-1] -= mid - e
            fit = c
        _EDGE_FITS[leaf] = fit
    c = _EDGE_FITS[leaf]
    if c is None:
        return edge_of(leaf)
    import numpy as np
    return float(np.polyval(c, base))


_INK_PATH = f'{HERE}/ink.json'
_INK = json.load(open(_INK_PATH)) if os.path.exists(_INK_PATH) else {}


def ink_left(leaf, base):
    """Where a line's letters start on the scan (pixels): the first
    run of columns, a letter's width, with ink enough for letters (not a
    speck) in the band from its ascenders to its baseline (kept in
    ink.json, measured once)."""
    key = f'{leaf}:{int(base)}'
    if key not in _INK:
        _INK[key] = _ink_left(leaf, base)
        json.dump(_INK, open(_INK_PATH, 'w'))
    return _INK[key]


def _ink_left(leaf, base):
    import numpy as np
    from PIL import Image
    if leaf not in _SCANS:
        import glob
        d = glob.glob(f'{W}/*_jp2')[0]
        _SCANS.clear()
        _SCANS[leaf] = np.asarray(Image.open(f'{d}/{d.split("/")[-1][:-4]}_{leaf:04d}.jp2').convert('L')) < 120
    a = _SCANS[leaf]
    e = edge_of(leaf)
    if e is None:
        return None
    y0, y1 = int(base - 80), int(base + 4)
    x0 = max(0, e - 160)
    x1 = min(a.shape[1], e + 2800)
    # (Columns dark from the line above's baseline to the line below's
    # ascenders: the film's edge, the gutter's shadow; no letter is so
    # tall.)
    tall = a[int(base - 130):int(base + 60), x0:x1].mean(0) > 0.7
    # (And the shadow's blurred edges beside it.)
    tall = np.convolve(tall.astype(int), np.ones(13, dtype=int), mode='same') > 0
    band = a[y0:y1, x0:x1].sum(0) * ~tall
    run = np.convolve(band, np.ones(30, dtype=int), mode='valid')
    hits = np.nonzero(run >= 60)[0]
    if not len(hits):
        return None
    k = int(hits[0])
    # (The first column of ink in that run.)
    cols = np.nonzero(band[k:k + 30] > 0)[0]
    return x0 + k + int(cols[0]) if len(cols) else None


def generate(out_dir, margins):
    """The text twice: once for each page's first word, then with each
    page's foot line, its catchword the next page's first word."""
    pages = generate_pass(out_dir, margins, None)
    catch = {}
    for leaf, lines in pages.items():
        nxt = pages.get(leaf + 1)
        if nxt is not None:
            catch[leaf] = CATCH.get(str(leaf + 1), first_word(nxt))
    generate_pass(out_dir, margins, catch)


def generate_pass(out_dir, margins, catch):
    o = Out(margins)
    roles = set()
    # The records to set: the Church-porch on, to the end of L'Envoy.
    first = next(i for i, r in enumerate(recs) if r['kind'] == 'head' and 'Church-porch' in r['plain'])
    last = max(i for i, r in enumerate(recs) if 'poem' in r['div'])
    page = None
    poem = None
    stanza = []   # (ri, leaf, line, words)
    poem_start = [True]
    n_turns = [0]
    speaker = [None]
    stanza_key = None

    def raw_x(ri, line):
        """The line's left edge on the scan: where its letters' ink starts
        (near the OCR's first word, a shadow left of it aside); else its
        first word's, where the OCR matched it."""
        ws = BY.get(ri, [])
        w0 = [w for w in ws if w[0] == 0]
        l = LINE.get(line)
        if l:
            return line_left(line[0], l)
        return w0[0][4] if w0 else None

    pending = []   # the stanzas of the current poem, set when it ends

    def flush():
        nonlocal stanza
        if not stanza:
            return
        pending.append(list(stanza))
        stanza = []

    def end_poem():
        """The poem's stanzas, each line's indent clustered with the
        poem's others (within 2.5 pt one indent, its median)."""
        flush()
        raw = []
        for st in pending:
            for ri, leaf, line, words in st:
                x = raw_x(ri, (leaf, line))
                l_ = LINE.get((leaf, line))
                e = local_edge(leaf, l_['base']) if l_ else edge_of(leaf)
                raw.append(None if x is None or e is None else (x - e) * PX)
        # (A refrain set in as far as the page's other refrains, their
        # median: the OCR puts one on another line now and then.)
        plains = [(leaf, ' '.join(''.join(p for p, _ in w) for w in words))
                  for st in pending for _, leaf, _, words in st]
        for j, (lf, pl) in enumerate(plains):
            if pl in REFRAINS:
                same = [raw[i] for i, (lf2, pl2) in enumerate(plains)
                        if lf2 == lf and pl2 in REFRAINS and raw[i] is not None]
                if same:
                    raw[j] = statistics.median(same)
        # (A line set in otherwise than the same line of the poem's other
        # stanzas of its shape, where four in five of them agree (the
        # whole poem's, gathered on the first pass): the OCR's error, a
        # word read off its line; the stanzas' indent.)
        k2 = 0
        for st in pending:
            n = len(st)
            poem_id = recs[st[0][0]]['poem']
            for j in range(n):
                key_ = (poem_id, n, j)
                if catch is None:
                    if raw[k2 + j] is not None:
                        SHAPES.setdefault(key_, []).append(raw[k2 + j])
                else:
                    vs = SHAPES.get(key_, [])
                    if len(vs) >= 5:
                        med = statistics.median(vs)
                        agree = sum(abs(v - med) <= 2.5 for v in vs) / len(vs)
                        v = raw[k2 + j]
                        if agree >= 0.8 and (v is None or abs(v - med) > 5.0):
                            raw[k2 + j] = med
            k2 += n
        vals = sorted(v for v in raw if v is not None)
        clusters = []
        for v in vals:
            if clusters and v - clusters[-1][-1] <= 2.5:
                clusters[-1].append(v)
            else:
                clusters.append([v])
        def snap(v):
            if v is None:
                return 0.0
            for c in clusters:
                if c[0] - 1e-9 <= v <= c[-1] + 1e-9:
                    m = statistics.median(c)
                    return 0.0 if m < 2.5 else m
            return v
        k = 0
        for si, st in enumerate(pending):
            ri0, leaf0, line0, _ = st[0]
            l0 = LINE.get((leaf0, line0))
            body = []
            drop = (si == 0 and opens_with_initial(ri0) and ri0 not in SPEAKERS
                    and not recs[ri0]['plain'].startswith(NO_DROP)) or recs[ri0]['plain'].startswith(FORCE_DROP)
            pdf_body = []
            turns = {}
            for li_, (ri, leaf, line, words) in enumerate(st):
                t = turned(ri, leaf, line, words) if line is not None else None
                if str(ri) in TURNS:
                    k_, d_, frag_ = TURNS[str(ri)]
                    t = (k_, d_)
                    TURN_TEXT[(ri, d_)] = frag_.lstrip('(')
                if t and 0 <= li_ + t[1] < len(st):
                    turns[li_] = t
            moved = {}   # line index -> turned text appended to it
            drop_inds = [0.0, 0.0]
            if drop:
                # (Beside the drop, the poem's other stanzas' indents for
                # those lines, less the drop's width: the first stanza
                # set as the rest.)
                others = [q for q in pending if q is not st and len(q) == len(st)]
                letter = (''.join(p for p, _ in st[0][3][0])[:1] if st[0][3] else '').upper()
                base = sum(len(o) for o in pending[:pending.index(st)])
                for li2 in range(min(2, len(st))):
                    vals2 = []
                    for oth in others:
                        b2 = sum(len(q) for q in pending[:pending.index(oth)])
                        v2 = snap(raw[b2 + li2])
                        vals2.append(v2)
                    if vals2:
                        own = statistics.median(vals2) - drop_width(letter)
                        drop_inds[li2] = round(own * 2) / 2 if own >= 2.5 else 0.0
            for li_, (ri, leaf, line, words) in enumerate(st):
                ind = snap(raw[k]); k += 1
                # (An indent that would carry the line past the measure:
                # the OCR's place for another line's; none.)
                if ind + 4.1 * len(render.markup(words).replace('__', '')) > MEASURE + 20:
                    ind = 0.0
                # (Beside the drop: set in past it as far as the line is
                # past the nearer of the two lines beside it, the drop's
                # edge.)
                if drop and li_ < 2:
                    ind = drop_inds[li_]
                role, q = indent_role(ind)
                pre = ''
                if role:
                    roles.add((role, q))
                    pre = f'[.{role}]##{{nbsp}}##'
                if ri in SPEAKERS:
                    # (A dialogue's speaker in the margin the line's indent
                    # leaves.)
                    pre = f'[.{role}]##{SPEAKERS[ri]}##' if role else SPEAKERS[ri] + ' '
                body.append(after_drop(pre, line_text(ri, words)) if drop and li_ == 0 else pre + line_text(ri, words))
                if li_ in turns:
                    kk, d = turns[li_]
                    head_words, tail_words = words[:len(words) - kk], words[len(words) - kk:]
                    # (A word divided, its end turned: `men-` on its line,
                    # `(tion,` turned, as the scan shows it.)
                    frag = TURN_TEXT.get((ri, d))
                    # (The scan's own line ending in the word's first part,
                    # `im-`: the rest turned.)
                    own = lines_of(leaf)[line]['w'] if line is not None and line < len(lines_of(leaf)) else []
                    if kk == 1 and own and own[-1]['t'].endswith('-'):
                        whole_ = ''.join(p for p, _ in tail_words[0])
                        if norm(whole_).startswith(norm(own[-1]['t'])) and len(norm(own[-1]['t'])) >= 2:
                            frag = whole_[len(own[-1]['t']) - 1:]
                    if kk == 1 and frag:
                        whole = ''.join(p for p, _ in tail_words[0])
                        nf = norm(frag)
                        nw = norm(whole)
                        if nw.endswith(nf) and len(nf) <= len(nw) - 2:
                            cut = len(whole)
                            letters = 0
                            for ci in range(len(whole) - 1, -1, -1):
                                if norm(whole[ci]):
                                    letters += 1
                                if letters == len(nf):
                                    cut = ci
                                    break
                            it = tail_words[0][0][1]
                            head_words = head_words + [[(whole[:cut] + '-', it)]]
                            tail_words = [[(whole[cut:], it)]]
                    moved[li_ + d] = line_text(ri, tail_words)
                    pdf_body.append([pre + line_text(ri, head_words), None])
                else:
                    pdf_body.append([after_drop(pre, line_text(ri, words)) if drop and li_ == 0
                                     else pre + line_text(ri, words), None])
            for idx, t in moved.items():
                pdf_body[idx][1] = t
            if turns:
                n_turns[0] += len(turns)
                pdf_lines = [a + (f' [.turn]#({t}#' if t else '') for a, t in pdf_body]
                body = ['ifdef::backend-pdf[]'] + pdf_lines + ['endif::[]', 'ifndef::backend-pdf[]'] + body + ['endif::[]']
            tgt = target(leaf0, l0['base']) if l0 else None
            # (Its first line's place from all its lines where the OCR put
            # the first on another line: each line's baseline less as many
            # lines as come before it, their median.)
            starts = [LINE[(lf, ln)]['base'] - j * PITCH / PX for j, (_, lf, ln, _) in enumerate(st)
                      if lf == leaf0 and ln is not None and (lf, ln) in LINE]
            if l0 and len(starts) >= 3:
                mid = statistics.median(starts)
                if abs(mid - l0['base']) > 0.5 * PITCH / PX:
                    tgt = target(leaf0, mid)
            # (The first text on its page: the page's first line of text.)
            if l0 and not any(f['page'] == leaf0 + 1 and f['kind'] in ('text', 'heading') for f in o.fits):
                hl = {l['i'] for l in head_lines(leaf0)}
                texts = [l for l in PAGES[str(leaf0)]['lines']
                         if sum(c.isalpha() for c in l['text']) >= 3 and l['i'] not in hl]
                if texts and abs(texts[0]['base'] - l0['base']) > 0.5 * PITCH / PX \
                        and texts[0]['base'] < l0['base']:
                    tgt = target(leaf0, texts[0]['base'])
            pos = len(o.lines)
            first_words = ' '.join(''.join(p for p, _ in w) for w in st[0][3])
            if drop:
                first_words = first_words[1:].lstrip()
            # (A long stanza's lines as far apart as the printing's on its
            # page: the paper's shrinking, the press's, vary it.)
            role_ = '.v.dropcap' if drop else '.v'
            ls_ = [LINE.get((leaf, line)) for _, leaf, line, _ in st]
            if len(st) >= 8 and all(ls_) and all(leaf == leaf0 for _, leaf, _, _ in st) \
                    and len({l['i'] for l in ls_}) == len(st):
                ys = [l['base'] * PX for l in ls_]
                xs = list(range(len(ys)))
                mx, my = statistics.mean(xs), statistics.mean(ys)
                slope = sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / sum((x - mx) ** 2 for x in xs)
                resid = max(abs(y - (my + slope * (x - mx))) for x, y in zip(xs, ys))
                pitch = round(slope, 2)
                if abs(pitch - PITCH) >= 0.02 and 9.0 < pitch < 10.2 and resid < 2.0:
                    roles.add((f'p{int(round(pitch * 100))}', pitch))
                    role_ += f'.p{int(round(pitch * 100))}'
            o.block([role_], body,
                    fit=(leaf0 + 1, 'text', first_words, tgt) if tgt is not None else None)
            if tgt is not None and len(st) > 1:
                o.fits[-1]['second'] = ' '.join(''.join(p for p, _ in w) for w in st[1][3])
        pending.clear()

    # (The front matter, hand-set: the title page, the Printers to the
    # Reader, the Dedication, and the blanks between, a page each.)
    for leaf in range(0, 8):
        o.lines.append(f'// page {leaf + 1} (leaf {leaf})')
        manual(o, leaf)
        # (The Printers to the Reader's feet: its catchwords, its first
        # leaf's signature, ¶ 2.)
        if leaf in (2, 3):
            o.foot(leaf, catch, sig='¶ 2' if leaf == 2 else None)
        o.lines.extend(['', '<<<', ''])
    for ri in range(first, last + 1):
        r = recs[ri]
        words = r.get('words_new', r['words'])
        leaf = r['leaf']
        where = MAIN.get(ri, (leaf, None))
        if leaf != page:
            end_poem()
            if page is not None:
                o.rules(page)
                o.foot(page, catch)
                o.lines.extend(['<<<', ''])
            o.lines.append(f'// page {leaf + 1} (leaf {leaf})')
            page = leaf
            if os.path.exists(f'{HERE}/manual/leaf{leaf}.adoc'):
                manual(o, leaf)
        if os.path.exists(f'{HERE}/manual/leaf{leaf}.adoc'):
            continue
        if r['kind'] == 'head':
            end_poem()
            l = LINE.get(where)
            tgt = target(leaf, l['base']) if l else None
            plain = r['plain']
            fit = (leaf + 1, 'heading', plain, tgt) if tgt else None
            if 'Church-porch' in plain:
                # (The Church-porch's title, its second line in italic, a
                # part's: its first page an opening page.)
                o.block(['#church-porch', 'running-title="The Church-porch."'],
                        ['== The Church-porch.'], fit=(leaf + 1, 'heading', 'The Church-porch.', tgt) if tgt else None)
                o.block(['.subhead'], ['Perirrhanterium.'], fit=sub_fit(leaf, where, 'Perirrhanterium.'))
                continue
            if 'Church Militant' in plain:
                o.block(['#church-militant', 'running-title="The Church Militant."'],
                        [f'== {line_text(ri, words)}'], fit=fit)
                continue
            m = re.match(r'^(Coloss\.|Ephes\.) ([\d.]+) (.*)$', plain)
            if m:
                # (A verse of Scripture: its reference the title, its text
                # the title's second line, in italic.)
                ref = m[1] + ' ' + ' '.join(re.findall(r'\d+\.', m[2]))
                # (Its two lines the scan's two most like them about the
                # title's.)
                import difflib
                near = [l for l in PAGES[str(leaf)]['lines'] if where[1] is not None and abs(l['i'] - where[1]) <= 2]
                def like(t):
                    return max(near, key=lambda l: difflib.SequenceMatcher(None, norm(t), norm(l['text'])).ratio()) \
                        if near else None
                l1, l2 = like(ref), like(m[3])
                o.block([], [f'=== {ref}'], fit=(leaf + 1, 'heading', ref, target(leaf, l1['base'])) if l1 else None)
                o.block(['.subhead'], [m[3]], fit=(leaf + 1, 'text', m[3], target(leaf, l2['base'])) if l2 else None)
                continue
            if plain.startswith('Superliminare'):
                o.block(['%notitle', '#church', 'running-title="The Church."'], ['== The Church'])
                o.block(['.opener'], [f'=== {line_text(ri, words)}'], fit=fit)
                continue
            # (L'Envoy's title as the printing sets it, the article
            # against the noun.)
            title = re.sub(r'\[\.spaced(-cap)?\]##([^#]*)##', r'\2', line_text(ri, words)).replace("L' Envoy", "L'Envoy")
            # (A title the printing marks with a section sign, for want of
            # pilcrows.)
            if (leaf + 1, re.sub(r'[^a-z]', '', plain.lower())) in SECTION_TITLES:
                title = title.replace('¶', '§', 1)
            # (The Sacrifice's title, which the printing sets without its
            # pilcrow, as the Altar's.)
            if (leaf + 1, re.sub(r'[^a-z]', '', plain.lower())) == (27, 'thesacrifice'):
                title = title.replace('¶ ', '', 1)
            o.block([], [f'=== {title}'], fit=fit)
            poem_start[0] = True
            continue
        if r['kind'] in ('stage', 'trailer', 'q'):
            # (A dialogue's speakers, FINIS., the Gloria: a line of their
            # own, centred.)
            end_poem()
            l = LINE.get(where)
            tgt = target(leaf, l['base']) if l else None
            role = {'stage': '.stage', 'trailer': '.finis', 'q': '.gloria'}[r['kind']]
            body = [line_text(ri, words)]
            if r['kind'] == 'q':
                # (Its lines the printing's: two.)
                ws = [''.join(p for p, _ in w) for w in words]
                cut = ws.index('earth') + 1 if 'earth' in ws else len(ws)
                body = [line_text(ri, words[:cut]), line_text(ri, words[cut:])]
            o.block([role], body, fit=(leaf + 1, 'text', r['plain'], tgt) if tgt else None)
            continue
        if r['kind'] == 'speaker':
            speaker[0] = line_text(ri, words).replace('Chor.', 'Cho.')
            continue
        key = (r['poem'], r['lg'])
        if stanza and key != stanza_key:
            flush()
        # (A gap the printing leaves between two lines of one of the TCP's
        # stanzas: two stanzas.)
        elif stanza and where[1] is not None and stanza[-1][2] is not None and where[0] == stanza[-1][1]:
            a_, b_ = LINE.get(stanza[-1][1:3]), LINE.get(where)
            # (Two lines next to each other on the scan: no line of text
            # between them, where the OCR put one on another's line.)
            between = [l for l in PAGES[str(where[0])]['lines'] if a_ and b_ and a_['i'] < l['i'] < b_['i']
                       and sum(c.isalpha() for c in l['text']) >= 3]
            # (Both lines read by the OCR: their words matched exactly,
            # not placed by their neighbours'.)
            def read(ri_):
                return sum(1 for w in BY.get(ri_, []) if w[3]) >= 2
            if a_ and b_ and b_['base'] - a_['base'] > 1.4 * PITCH / PX and not between \
                    and read(stanza[-1][0]) and read(ri):
                flush()
        stanza_key = key
        stanza.append((ri, where[0], where[1], words))
        if speaker[0]:
            SPEAKERS[ri] = speaker[0]
            speaker[0] = None
    end_poem()
    o.rules(page)
    o.foot(page, catch)
    # (The titles of the poems, hand-set: three pages.)
    for leaf in (200, 201, 202):
        o.lines.extend(['<<<', '', f'// page {leaf + 1} (leaf {leaf})'])
        if leaf == 200:
            # (A part of its own, its title the page's own lines, no
            # running head: the printing's has none.)
            o.lines.extend(['[#titles%notitle%noheader]', '== The Titles of the Severall Poems', ''])
        manual(o, leaf)
        if leaf < 202:
            o.foot(leaf, catch)
    page = 202
    if catch is None:
        # (Each page's lines, for its first word.)
        pages, cur = {}, None
        for ln in o.lines:
            m = re.match(r'^// page \d+ \(leaf (\d+)\)', ln)
            if m:
                cur = int(m[1])
                pages[cur] = []
            elif cur is not None:
                pages[cur].append(ln)
        return pages
    # (A title the OCR didn't read, given its poem's first line: a title's
    # usual height above that line.)
    for a, b in zip(o.fits, o.fits[1:]):
        if a['kind'] == 'heading' and b['kind'] == 'text' and a['page'] == b['page'] \
                and abs(a['target'] - b['target']) < 1.0:
            a['target'] = round(b['target'] - 16.4, 2)
    with open(f'{out_dir}/temple.adoc', 'w', encoding='utf-8') as f:
        f.write('\n'.join(o.lines))
    json.dump(o.fits, open(f'{out_dir}/fit.json', 'w'), ensure_ascii=False, indent=0)
    # (The hand-set pages' indents too.)
    for name in os.listdir(f'{HERE}/manual'):
        text = open(f'{HERE}/manual/{name}', encoding='utf-8').read()
        for m in re.finditer(r'\[\.i(\d+)\]', text):
            roles.add((f'i{m[1]}', int(m[1]) / 10))
        for m in re.finditer(r'\.p(\d{3,4})\b', text):
            roles.add((f'p{m[1]}', int(m[1]) / 100))
    roles |= FOOT_ROLES
    json.dump(sorted(roles), open(f'{HERE}/indents.json', 'w'))
    update_look(sorted(roles))
    print(len(o.fits), 'blocks;', len(roles), 'indents;', n_turns[0], 'turned lines')


if __name__ == '__main__':
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    m = json.load(open(sys.argv[2])) if len(sys.argv) > 2 and os.path.exists(sys.argv[2]) else {}
    generate(out, m)
