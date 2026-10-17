"""The Book of Common Prayer's pages (test/showcase/bcp/text/pages.adoc)
from bcp.spec: each page a section of its own (its heading hidden, the
frame of flowers its background), each source line a printed line
(`:source-lines:`): the running head, set flush right on a recto and
flush left on a verso, its two parts the printing's gap apart; the
foot, its signature where the scan's is and its catchword flush right;
the heads and the psalms' titles centred; a paragraph's first line set
in, or opening with an initial two lines deep; a rubric, an Amen, a
reference in italic where the scan's is. Each block's space above it
and its pitch from adjust.json (margins.py's, pitch.py's), keyed by its
first line; the roles they take written into the look.

    python3 -I gen.py   (ONLY=LEAF[,LEAF] those pages alone)
"""
import json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from common import WORK

SRC = os.path.join(HERE, '..', '..', 'test', 'showcase', 'bcp')
SPEC = os.path.join(HERE, 'bcp.spec')
ADJ = os.path.join(HERE, 'adjust.json')
ADJUST = json.load(open(ADJ)) if os.path.exists(ADJ) else {}
ONLY = {int(p) for p in os.environ.get('ONLY', '').split(',') if p}
ROLES = {'T': 'ct', 'I': 'ini', 'P': 'pa', 'N': 'pa.on', 'R': 'rb', 'r': 'rl', 'Q': 'qc', 'C': 'ct', ' ': 'pa.on'}
INDENTS = set()
PITCHES, WIDTHS = set(), set()


def spaced(text):
    """A word in capitals (two letters or more) spaced, as the printing
    spaces its capitals: `[.caps]`."""
    return re.sub(r'(?<![A-Za-z0-9#\[.])([A-Z][A-Z]+)(?![A-Za-z#\]])', r'[.caps]##\1##', text)


def inline(text):
    text = text.replace('⟦', '').replace('⟧', '')
    # (` | `: the running head's or the foot's parts.)
    if text.endswith('-') and not text.endswith('--'):
        text = text[:-1] + '{shy}'
    if re.match(r'^(\*+|-|\.+|\d+\.|[A-Za-z]\.|[ivxIVX]+\))\s', text):
        text = '{empty}' + text
    return text


_FONTS = {}


def width(text, size=14.6):
    """[text]'s width set in Baskervville at [size] (its italic between
    `__`), its capitals spaced as the look spaces them: points."""
    from fontTools.ttLib import TTFont
    total = 0.0
    for k, part in enumerate(text.split('__')):
        style = 'Italic' if k % 2 else 'Regular'
        if style not in _FONTS:
            f = TTFont(os.path.expanduser(f'~/.local/share/fonts/ptome/Baskervville-{style}.ttf'))
            _FONTS[style] = (f.getBestCmap(), f['hmtx'])
        cmap, hmtx = _FONTS[style]
        total += sum(hmtx[cmap[ord(c)]][0] for c in part if ord(c) in cmap) / 1000 * size
        total += sum(len(w) * 0.12 * size for w in re.findall(r'\b[A-Z]{2,}\b', part))
    return total


class Gen:
    def __init__(self):
        self.out, self.fit = [], []
        self.para, self.kind, self.first = None, None, None
        self.page = self.n = None
        self.block = 0
        self.align = 'hc'

    def key(self):
        return f'top/{self.page}/{self.first}'

    def flush(self):
        if not self.para:
            self.para = None
            return
        role = ROLES[self.kind] if self.kind in ROLES else self.role
        pitch = ADJUST.get(f'pitch/{self.key()}')
        if pitch:
            PITCHES.add(round(pitch * 100))
            role += f'.p{round(pitch * 100)}'
        m = ADJUST.get(self.key())
        margin = f',margin-top={m}pt' if m else ''
        self.out += [f'[.{role}{margin}]', *self.para, '']
        for f in self.fit:
            if f['block'] == self.block:
                f['key'] = self.key()
        self.para = None
        self.block += 1

    def line(self, text):
        self.n += 1
        if not self.para:
            self.first = self.n
        self.fit.append({'page': self.page, 'line': self.n, 'block': self.block, 'kind': self.kind})
        if self.kind not in ('X',):
            text = spaced(text)
        if ' @ ' in text:
            # (A page's last line short, the foot on it: the signature
            # where the scan's is, the catchword flush right.)
            text, _, foot = text.partition(' @ ')
            parts = [p.strip() for p in re.split(r'\s*\|\s*', foot)]
            sig, catch = (parts + [''])[:2] if len(parts) > 1 else ('', parts[0])
            tail = ''
            if sig:
                indent = 17.5 if self.kind == 'P' and not self.para else 0
                gap = max(ADJUST.get(f'sig/{self.page}', 140) - indent - width(text), 4)
                w = round(gap * 2)
                WIDTHS.add(w)
                tail += f' [.w{w}]##{{nbsp}}##{inline(sig)}'
            if catch:
                tail += f' [.right]#{catch}#'
            return inline(text) + tail
        return inline(text)

    def head(self, text):
        """The running head: its parts the printing's gap apart, flush
        right on a recto (an odd leaf), flush left on a verso."""
        self.flush()
        parts = [p.strip() for p in text.split(' | ')]
        # (Its words in capitals spaced wide, as the printing's are.)
        parts = [re.sub(r'(?<![A-Za-z0-9#])([A-Z][A-Z]+\.?)', r'[.sp]##\1##', p) for p in parts]
        body = '[.gap]##{nbsp}##'.join(inline(p) for p in parts)
        self.kind = 'h'
        self.para = [self.line(body)]
        side = self.align
        m = ADJUST.get(f'top/{self.page}/{self.first}')
        margin = f',margin-top={m}pt' if m else ''
        self.out += [f'[.{side}{margin}]', *self.para, '']
        for f in self.fit:
            if f['block'] == self.block:
                f['key'] = self.key()
        self.para = None
        self.block += 1

    def foot(self, text):
        """The foot: the signature where the scan's is (`w<half points>`
        of space before it, adjust.json's `sig/LEAF`), the catchword
        flush right."""
        self.flush()
        parts = [p.strip() for p in text.split(' | ')]
        sig, catch = (parts + [''])[:2] if len(parts) > 1 else ('', parts[0])
        lead = ''
        if sig:
            w = round(ADJUST.get(f'sig/{self.page}', 140) * 2)
            WIDTHS.add(w)
            lead = f'[.w{w}]##{{nbsp}}##{inline(sig)}'
        # (The catchword as printed, its hyphen kept.)
        body = (lead or '{empty}') + (f' [.right]#{catch}#' if catch else '')
        self.kind = 'f'
        self.para = [self.line(body)]
        m = ADJUST.get(f'top/{self.page}/{self.first}')
        margin = f',margin-top={m}pt' if m else ''
        self.out += [f'[.ft{margin}]', *self.para, '']
        for f in self.fit:
            if f['block'] == self.block:
                f['key'] = self.key()
        self.para = None
        self.block += 1

    def run(self):
        for raw in open(SPEC, encoding='utf-8'):
            raw = raw.rstrip('\n')
            if not raw.strip() or raw.startswith('#'):
                continue
            if raw.startswith('@page'):
                self.flush()
                _, leaf, part = raw.split()[:3]
                self.page, self.n = int(leaf), 0
                side = 'recto' if self.page % 2 else 'verso'
                # (A spacer first on the page: the first block's margin
                # holds only after a block.)
                self.out += [f'// page {self.page}', f'// tag::page-{self.page}[]',
                             f'[.leaf.{side}%notitle]', f'== Leaf {self.page}', '',
                             'image::blank.svg[role=spacer,pdfwidth=1pt,pdfheight=0.01pt]', '']
                continue
            if raw.startswith('@end'):
                continue
            kind, text = raw[0], raw[2:]
            if kind in 'hHc' and raw[1] == ' ' and kind in ('h', 'H', 'c'):
                # (`h` flush right, `H` flush left, `c` centred.)
                self.align = {'h': 'hr', 'H': 'hv', 'c': 'hc'}[kind]
                self.head(text)
                continue
            if kind == 'f':
                self.foot(text)
                continue
            if raw.startswith('@rule'):
                # (The double rule under a title.)
                self.flush()
                self.out += ['[.rule2]', 'image::rule2.svg[]', '']
                continue
            if kind == ' ':
                if self.para is None:
                    self.kind, self.para = ' ', []
                self.para.append(self.line(text))
                continue
            self.flush()
            m = re.match(r'^V\+(\d+) (.*)$', raw)
            if m:
                # (A short line set in so far: a versicle, a response.)
                INDENTS.add(int(m.group(1)))
                self.kind, self.role = 'V', f'in{m.group(1)}'
                self.para = [self.line(m.group(2))]
                self.flush()
                continue
            m = re.match(r'^X (\S+) (.*)$', raw)
            if m:
                # (A title's line in its own size: its role the look's.)
                self.kind, self.role = 'X', m.group(1)
                self.para = [self.line(m.group(2))]
                self.flush()
                continue
            if kind == 'T' and re.fullmatch(r'__(MORNING|EVENING) PRAYER\.__', text):
                # (The Psalter's offices: their heads in the larger italic
                # capitals.)
                self.kind, self.role = 'X', 'office'
                self.para = [self.line(text)]
                self.flush()
                continue
            self.kind = kind
            self.para = [self.line(text)]
            if kind in ('T', 'C'):
                self.flush()
        self.flush()


def calendar(fit):
    """The Calendar's months (months.py): their pages' AsciiDoc, their
    rules' SVGs, the look's section roles that put each month on its
    page of rules, the table's pitches."""
    import months
    geo = months.geometry()
    out, sections, pitches = [], [], set()
    for page in months.pages():
        leaf = page['leaf']
        if ONLY and leaf not in ONLY:
            continue
        g = geo[str(leaf)]
        lines, pitch = months.adoc(page, g, ADJUST, fit, 0)
        WIDTHS.add(round(ADJUST.get(f'sig/{leaf}', 150) * 2))
        out += lines
        pitches.add(round(pitch * 100))
        open(os.path.join(SRC, 'images', f'cal-{leaf}.svg'), 'w').write(months.svg(page, g))
        fx, fy = months.place(g)
        w, h = g['frame']
        # (The page's margins: the frame's inside less a little.)
        top, left = fy + 2, fx + 5.6
        right = months.PAGE[0] - (fx + w) + 5.6
        bottom = months.PAGE[1] - (fy + h) - 2
        sections.append(f"      cal{leaf}: {{ page_background_image: 'image:images/cal-{leaf}.svg[]', "
                        f"page_running_content: none, page_margin: [{top:.2f}, {right:.2f}, {bottom:.2f}, {left:.2f}] }}\n")
    return out, sections, pitches


def main():
    import months
    g = Gen()
    cal, sections, calpitches = calendar(g.fit)
    g.run()
    # (Each page's tag closed before the next's.)
    res, current = [], None
    for line in g.out:
        if line.startswith('// page '):
            if current is not None:
                res.append(f'// end::page-{current}[]')
            current = int(line.split()[2])
        res.append(line)
    if current is not None:
        res.append(f'// end::page-{current}[]')
    res = cal + res
    if ONLY:
        keep, mine = [], False
        for line in res:
            if line.startswith('// page '):
                mine = int(line.split()[2]) in ONLY
            if mine:
                keep.append(line)
        res = keep
    head = ['// The Book of Common Prayer (Cambridge: Baskerville, 1761), its pages as',
            '// the octavo prints them: generated from tool/bcp_1761/bcp.spec by gen.py.', '']
    os.makedirs(os.path.join(SRC, 'text'), exist_ok=True)
    open(os.path.join(SRC, 'text', 'pages.adoc'), 'w', encoding='utf-8').write('\n'.join(head + res) + '\n')
    json.dump(g.fit, open(os.path.join(WORK, 'fit.json'), 'w'), indent=0)
    look = os.path.join(SRC, 'bcp-look.yml')
    s = open(look, encoding='utf-8').read()
    start, end = "    # (gen.py's roles.)\n", "    # (gen.py's roles end.)\n"
    if start in s:
        a, rest = s.split(start, 1)
        _, b = rest.split(end, 1)
        roles = ''.join(f'    p{p}: {{ line_pitch: {p / 100}pt }}\n' for p in sorted(PITCHES))
        roles += ''.join(f'    w{w}: {{ width: {w / 2} }}\n' for w in sorted(WIDTHS))
        roles += ''.join(f'    in{n}: {{ text_align: left, text_indent: {n} }}\n' for n in sorted(INDENTS))
        s = a + start + roles + end + b
        # (The Calendar's: each month's page of rules and its table's pitch.)
        cstart, cend = "      # (gen.py's calendar sections.)\n", "      # (gen.py's calendar sections end.)\n"
        if cstart in s:
            a, rest = s.split(cstart, 1)
            _, b = rest.split(cend, 1)
            s = a + cstart + ''.join(sections) + cend + b
        tstart, tend = "      # (gen.py's calendar pitches.)\n", "      # (gen.py's calendar pitches end.)\n"
        if tstart in s:
            a, rest = s.split(tstart, 1)
            _, b = rest.split(tend, 1)
            s = a + tstart + ''.join(f'      cp{p}: {{ line_pitch: {p / 100}pt }}\n' for p in sorted(calpitches)) + tend + b
        qstart, qend = "    # (gen.py's calendar squeezes.)\n", "    # (gen.py's calendar squeezes end.)\n"
        if qstart in s:
            a, rest = s.split(qstart, 1)
            _, b = rest.split(qend, 1)
            s = a + qstart + ''.join(f'    sq{k}: {{ letter_spacing: -{k / 1000}em }}\n' for k in sorted(months.SQUEEZE)) + qend + b
        open(look, 'w', encoding='utf-8').write(s)


main()
