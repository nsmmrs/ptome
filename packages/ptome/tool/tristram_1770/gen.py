"""Tristram Shandy's pages (test/showcase/tristram/text/pages.adoc) from
tristram.spec: each page a section of its own (its heading hidden), each
source line a printed line (`:source-lines:`): the head, the page's
number in brackets, centred; a chapter's head centred, its capitals
spaced, its first line opening with an initial two lines deep; a
paragraph's first line set in; a line set in further by the scan's
measure (`V+N`); the footnotes in the smaller size; the foot, the
signature where the scan's is and the catchword flush right; the title
page's lines each in its own size; the frontispiece and the black pages
their images. Each block's space above it and its pitch from adjust.json
(margins.py's, pitch.py's), keyed by its first line; the roles they take
written into the look.

    python3 -I gen.py   (ONLY=PAGE[,PAGE] those pages alone)
"""
import json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from common import WORK, MEASURE, SIZE, NOTE, DEDICATION

SRC = os.path.join(HERE, '..', '..', 'test', 'showcase', 'tristram')
SPEC = os.path.join(HERE, 'tristram.spec')
ADJ = os.path.join(HERE, 'adjust.json')
ADJUST = json.load(open(ADJ)) if os.path.exists(ADJ) else {}
ONLY = {p for p in os.environ.get('ONLY', '').split(',') if p}
ROLES = {'P': 'pa', 'N': 'pa.on', ' ': 'pa.on', 'C': 'ct', 'I': 'ini', 'R': 'rt', 'F': 'fn', 'n': 'fn.on', 'Y': 'yk'}
PITCHES, WIDTHS, INDENTS, SQUEEZES = set(), set(), set(), set()

_FONTS = {}


def width(text, size=SIZE):
    """[text]'s width set in Libre Caslon Text at [size] (its italic
    between `__`, its small capitals at four fifths of the size): points."""
    from fontTools.ttLib import TTFont
    total = 0.0
    text = text.replace('{shy}', '-').replace('{zwsp}', '').replace('{nbsp}', ' ')
    for k, part in enumerate(text.split('__')):
        style = 'Italic' if k % 2 else 'Regular'
        if style not in _FONTS:
            f = TTFont(os.path.expanduser(f'~/.local/share/fonts/ptome/LibreCaslonText-{style}.ttf'))
            _FONTS[style] = (f.getBestCmap(), f['hmtx'], f['head'].unitsPerEm)
        cmap, hmtx, upem = _FONTS[style]
        for piece in re.split(r'(\[\.\w+\]#+[^#]*#+)', part):
            m = re.match(r'\[\.(\w+)\]#+([^#]*)#+', piece)
            scale, s = 1.0, piece
            if m:
                s = m.group(2)
                if m.group(1) == 'sc':
                    s, scale = s.upper(), 0.8
            total += sum(hmtx[cmap[ord(c)]][0] for c in s if ord(c) in cmap) / upem * size * scale
    return total


def spaced(text):
    """A word in capitals (two letters or more) spaced, as the printing
    spaces its capitals: `[.caps]`."""
    return re.sub(r'(?<![A-Za-z0-9#\[.’])([A-Z][A-Z’]+)(?![a-z#\]])', r'[.caps]##\1##', text)


def inline(text):
    text = text.replace('⟦', '').replace('⟧', '')
    # (Sterne's two- and three-em dashes, which Caslon's revival lacks:
    # its em dashes run together, the line's pitch kept.)
    text = text.replace('⸻', '———').replace('⸺', '——')
    if re.match(r'^(\*+|-|\.+|\d+\.|[A-Za-z]\.|[ivxIVX]+\))\s', text):
        text = '{empty}' + text
    return text


class Gen:
    def __init__(self):
        self.out, self.fit = [], []
        self.para, self.kind, self.first = None, None, None
        self.page = self.n = None
        self.block = 0
        self.role = None
        self.squeeze = 0

    def key(self):
        return f'top/{self.page}/{self.first}'

    def flush(self):
        if not self.para:
            self.para = None
            return
        role = self.role or ROLES[self.kind]
        if str(self.page).startswith('dedication') and self.kind in ('P', 'N', ' ', 'I', 'V', 'R'):
            # (The dedication in the larger size.)
            role += '.dd'
        pitch = ADJUST.get(f'pitch/{self.key()}')
        if pitch:
            PITCHES.add(round(pitch * 100))
            role += f'.p{round(pitch * 100)}'
        if self.squeeze:
            SQUEEZES.add(self.squeeze)
            role += f'.sq{self.squeeze}'
        m = ADJUST.get(self.key())
        margin = f',margin-top={m}pt' if m else ''
        # (A block's last line dividing its last word: the hyphen set, the
        # block's end no break for a soft one to show at.)
        self.para[-1] = re.sub(r'\{shy\}((?:__|#+)?)$', r'-\1', self.para[-1])
        self.out += [f'[.{role}{margin}]', *self.para, '']
        for f in self.fit:
            if f['block'] == self.block:
                f['key'] = self.key()
        self.para, self.role, self.squeeze = None, None, 0
        self.block += 1

    def start(self, kind, role=None):
        self.flush()
        self.kind, self.role, self.para = kind, role, []

    def line(self, text, measure=MEASURE, size=SIZE):
        if str(self.page).startswith('dedication') and size == SIZE:
            size = DEDICATION
        if self.para and self.kind in ('P', 'N', ' ', 'I', 'F', 'n') and ADJUST.get(f'split/{self.page}/{self.n + 1}'):
            # (A paragraph whose lines lie unevenly on the scan, the leaf
            # curling: parted, its part above justified to its last line,
            # the part below going on.)
            kind = 'n' if self.kind in ('F', 'n') else ' '
            self.role = (self.role or ROLES[self.kind]) + '.jl'
            self.start(kind)
        self.n += 1
        if not self.para:
            self.first = self.n
        self.fit.append({'page': self.page, 'line': self.n, 'block': self.block, 'kind': self.kind})
        # (A line wider than the measure set closer: its paragraph's
        # letters drawn together by as much as it needs, the face's own
        # narrowing (four percent) first.)
        if self.kind not in ('X', 'h', 'f', 'C', 'R', 'Y'):
            over = width(text, size) * 0.965 - measure
            if over > 0:
                n = max(1, len(re.sub(r'\[\.\w+\]#+|#+|__|\{\w+\}', '', text)))
                self.squeeze = max(self.squeeze, int(over / n / size * 1000) + 1)
        self.para.append(inline(text))

    def foot(self, text):
        """The foot: the volume's direction line at the left, the signature
        where the scan's is (adjust.json's `sig/PAGE`, points from the
        text's left), the catchword flush right."""
        parts = [p.strip() for p in text.split(' | ')]
        catch = parts[-1] if len(parts) > 1 or not re.fullmatch(r'[A-Z]( \d)?|\d', parts[0]) else ''
        marks = parts[:-1] if catch else parts
        lead = ''
        at = 0.0
        for k, mark in enumerate(marks):
            if mark.startswith('VOL'):
                x = ADJUST.get(f'dir/{self.page}', 16.0)
            else:
                x = ADJUST.get(f'sig/{self.page}', 100.0)
            gap = max(x - at, 1)
            w = round(gap * 2)
            WIDTHS.add(w)
            lead += f'[.w{w}]##{{nbsp}}##{spaced(mark)}'
            at = x + width(mark)
        body = (lead or '{empty}') + (f' [.right]#{catch}#' if catch else '')
        self.start('f', 'ft')
        self.line(body)
        self.flush()

    def run(self):
        page_open = False
        for raw in open(SPEC, encoding='utf-8'):
            raw = raw.rstrip('\n')
            if not raw.strip() or raw.startswith('#'):
                continue
            if raw.startswith('@page'):
                self.flush()
                _, page, leaf = raw.split()[:3]
                self.page, self.n = page, 0
                side = 'recto' if int(leaf) % 2 == 0 else 'verso'
                margin = RECTO if side == 'recto' else VERSO
                if page == 'frontispiece':
                    # (The frontispiece: the plate as the scan shows it,
                    # the page its background.)
                    side = 'front'
                elif page == '1':
                    # (The first page: the rule under its title where the
                    # scan's is, drawn behind it.)
                    side = 'first'
                    rule_page(margin)
                elif page in BLACK:
                    # (A black page: its ink where the scan's is, drawn
                    # behind the page's head.)
                    side = f'black{page}'
                    black_page(page, margin)
                # (A spacer first on the page: the first block's margin
                # holds only after a block.)
                self.out += [f'// page {page}', f'// tag::page-{page}[]',
                             f'[.{side}%notitle]', f'== Page {page}', '',
                             'image::blank.svg[role=spacer,pdfwidth=1pt,pdfheight=0.01pt]', '']
                continue
            if raw in ('@frontispiece', '@black'):
                continue
            if raw == '@rule':
                continue
            if raw.startswith('f '):
                self.foot(raw[2:])
                continue
            if raw.startswith('h '):
                # (The head: the page's number in brackets, or a running
                # title, its capitals spaced.)
                numbered = re.fullmatch(r'\( \d+ \)', raw[2:])
                self.start('h', 'hd' if numbered else 't-ded')
                self.line(spaced(raw[2:]) if numbered else raw[2:])
                self.flush()
                continue
            m = re.match(r'^X (\S+) (.*)$', raw)
            if m:
                self.start('X', m.group(1))
                self.line(m.group(2))
                self.flush()
                continue
            m = re.match(r'^V\+(\d+) (.*)$', raw)
            if m:
                INDENTS.add(int(m.group(1)))
                self.start('V', f'in{m.group(1)}')
                self.line(m.group(2))
                self.flush()
                continue
            kind, text = raw[0], raw[2:]
            if kind == ' ':
                if self.para is None or self.kind in ('h', 'X', 'V', 'C', 'R', 'Y', 'f'):
                    self.start(' ')
                self.line(text)
                continue
            if kind == 'n':
                if self.para is None or self.kind not in ('F', 'n'):
                    self.start('n')
                self.line(text, size=NOTE)
                continue
            if kind == 'C':
                self.start('C')
                self.line(spaced(text) if text.startswith('CHAP.') else spaced(text))
                self.flush()
                continue
            if kind == 'Y':
                # (Yorick's epitaph in its frame of rules: a table of one
                # cell, its rules the frame.)
                self.flush()
                self.n += 1
                self.fit.append({'page': self.page, 'line': self.n, 'block': self.block, 'kind': 'Y',
                                 'key': f'top/{self.page}/{self.n}'})
                m = ADJUST.get(f'top/{self.page}/{self.n}')
                margin = f',margin-top={m}pt' if m else ''
                self.out += [f'[.yk,cols=1,frame=all,grid=none,align=center,width=68%{margin}]', '|===',
                             f'|{spaced(text)}', '|===', '']
                self.block += 1
                continue
            if kind == 'R':
                self.start(kind)
                self.line(spaced(text))
                self.flush()
                continue
            self.start(kind)
            self.line(text, size=NOTE if kind == 'F' else SIZE)
        self.flush()


BLACK = ('67', '68')
# (A recto's margins and a verso's: the binding's side the narrower,
# the text's left edge where the scan's is set (common.py's LEFT).)
RECTO = '[30, 53.6, 40, 42]'
VERSO = '[30, 42, 40, 53.6]'
SECTIONS = []


def rule_page(margin):
    """The first page's background (images/rule-1.svg, the page's size):
    the rule under the title where the scan's is (scan.json's `rule/1`)."""
    from common import PAGE_PT
    scan = json.load(open(os.path.join(WORK, 'scan.json')))
    x, y, w, h = scan.get('rule/1', [40.0, 170.0, 218.5, 1.4])
    W, H = PAGE_PT
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}pt" height="{H}pt" viewBox="0 0 {W} {H}">'
           f'<rect x="{x:.2f}" y="{y:.2f}" width="{w:.2f}" height="{h:.2f}" fill="#1A1A1A"/></svg>\n')
    open(os.path.join(SRC, 'images', 'rule-1.svg'), 'w').write(svg)
    SECTIONS.append(f"      first: {{ page_background_image: 'image:images/rule-1.svg[]', page_running_content: none, page_margin: {margin} }}\n")


def black_page(page, margin):
    """The black page's background (images/black-PAGE.svg, the page's
    size): its ink where the scan's is (scan.json's `black/PAGE`)."""
    from common import PAGE_PT
    scan = json.load(open(os.path.join(WORK, 'scan.json')))
    x, y, w, h = scan.get(f'black/{page}', [47.0, 59.0, 212.8, 365.6])
    W, H = PAGE_PT
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}pt" height="{H}pt" viewBox="0 0 {W} {H}">'
           f'<rect x="{x:.2f}" y="{y:.2f}" width="{w:.2f}" height="{h:.2f}" fill="#1A1A1A"/></svg>\n')
    open(os.path.join(SRC, 'images', f'black-{page}.svg'), 'w').write(svg)
    SECTIONS.append(f"      black{page}: {{ page_background_image: 'image:images/black-{page}.svg[]', page_running_content: none, page_margin: {margin} }}\n")


def main():
    g = Gen()
    g.run()
    # (Each page's tag closed before the next's.)
    res, current = [], None
    for line in g.out:
        if line.startswith('// page '):
            if current is not None:
                res.append(f'// end::page-{current}[]')
            current = line.split()[2]
        res.append(line)
    if current is not None:
        res.append(f'// end::page-{current}[]')
    if ONLY:
        keep, mine = [], False
        for line in res:
            if line.startswith('// page '):
                mine = line.split()[2] in ONLY
            if mine:
                keep.append(line)
        res = keep
    head = ['// The Life and Opinions of Tristram Shandy, Gentleman, Vol. I (London: J. Dodsley,',
            '// 1770), its pages as the octavo prints them: generated from',
            '// tool/tristram_1770/tristram.spec by gen.py.', '']
    os.makedirs(os.path.join(SRC, 'text'), exist_ok=True)
    open(os.path.join(SRC, 'text', 'pages.adoc'), 'w', encoding='utf-8').write('\n'.join(head + res) + '\n')
    json.dump(g.fit, open(os.path.join(WORK, 'fit.json'), 'w'), indent=0)
    look = os.path.join(SRC, 'tristram-look.yml')
    s = open(look, encoding='utf-8').read()
    start, end = "    # (gen.py's roles.)\n", "    # (gen.py's roles end.)\n"
    if start in s:
        a, rest = s.split(start, 1)
        _, b = rest.split(end, 1)
        roles = ''.join(f'    p{p}: {{ line_pitch: {p / 100}pt }}\n' for p in sorted(PITCHES))
        roles += ''.join(f'    w{w}: {{ width: {w / 2} }}\n' for w in sorted(WIDTHS))
        roles += ''.join(f'    in{n}: {{ text_align: left, text_indent: {n} }}\n' for n in sorted(INDENTS))
        roles += ''.join(f'    sq{k}: {{ letter_spacing: -{k / 1000}em }}\n' for k in sorted(SQUEEZES))
        s = a + start + roles + end + b
        sstart, send = "      # (gen.py's sections.)\n", "      # (gen.py's sections end.)\n"
        a, rest = s.split(sstart, 1)
        _, b = rest.split(send, 1)
        open(look, 'w', encoding='utf-8').write(a + sstart + ''.join(SECTIONS) + send + b)
    print(len(g.fit), 'lines;', len(SQUEEZES), 'squeezes')


main()
