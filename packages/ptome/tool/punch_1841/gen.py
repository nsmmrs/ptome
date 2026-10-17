"""Punch's three issues (test/showcase/punch/text/pages.adoc) from
punch.spec: each page a section of its own (its heading hidden), its two
columns, each source line a printed line (`:source-lines:`); a piece's
head, a paragraph, a verse's lines, a cut's caption, a table's row each
their role; the rules between the pieces and the cuts where the spec
puts them. Each paragraph's space above it from adjust.json (`top/PAGE/
COLUMN/LINE`, keyed by its first line), fitted by margins.py; the pages'
roles (their margins, their folios) written into the look.

    python3 -I gen.py
"""
import json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, '..', '..', 'test', 'showcase', 'punch')
WORK = os.environ.get('PUNCH_WORK', os.path.expanduser('~/.cache/asciidart-work/print-match/punch'))
SPEC = os.path.join(HERE, 'punch.spec')
ADJUST = json.load(open(os.path.join(HERE, 'adjust.json'))) if os.path.exists(os.path.join(HERE, 'adjust.json')) else {}
PITCHES = set()
INDENTS = set()
RINDENTS = set()
SIZES = set()
sys.path.insert(0, HERE)
from scan import floats
EDGES = floats()
# (ONLY=PAGE[,PAGE]: those pages alone.)
PROBE = bool(os.environ.get('PROBE'))
ONLY = {int(p) for p in os.environ.get('ONLY', '').split(',') if p}
CUTS = {c['id']: c for v in json.load(open(os.path.join(WORK, 'cuts.json'))).values() for c in v} \
    if os.path.exists(os.path.join(WORK, 'cuts.json')) else {}
SCAN = json.load(open(os.path.join(WORK, 'scan.json'))) if os.path.exists(os.path.join(WORK, 'scan.json')) else {}
RULE = {'verso': 58.8 + 213.5, 'recto': 53.2 + 213.5}
COLUMN_TOP = 56.0  # (the look's top margin: the columns' top)
ROLES = {'K': 'kh', 'F': 'fn', 'v': 'vh', 'h': 'sh', 'H': 'hd', 'P': 'pa', 'N': 'pa.on', 'C': 'cap', 'V': 'vs', 'T': 'tr', 'W': 'week'}


WEEK = {'July 17, 1841': 'JULY 17, 1841', 'August 14, 1841': 'AUGUST 14, 1841', 'August 21, 1841': 'AUGUST 21, 1841'}


def small_caps(text):
    """A word the transcription sets in capitals (PUNCH, SHALLA-BA-LA)
    as the volume sets it, in small capitals: `[.sc]##Punch##`."""
    def sc(m):
        w = m.group(0)
        return f'[.sc]##{w[0]}{w[1:].lower()}##'
    # (`\WORD`: kept in capitals, as the volume sets GREAT COAT.)
    return re.sub(r'(?<![\w\[#\\])[A-Z][A-Z’\'-]*[A-Z](?![\w#])', sc, text).replace('\\', '')


def inline(text, kind='P'):
    text = text.replace('&amp;', '&')
    # (` @WORDS` at a line's end: set flush right, a signature.)
    m = re.match(r'^(.*?) ?@(\S.*)$', text)
    right = None
    if m and kind != 'T':
        text, right = m.group(1), m.group(2)
    if kind in ('P', 'N', 'V', 'v', 'F'):
        text = small_caps(text)
    if right is not None:
        # (A signature in capitals, the volume's small capitals: the span
        # both, `[.right.sc]`, a capital after a capital lowered, McGUELP
        # McGuelp.)
        if not re.search('[a-z]', re.sub(r'Mc', '', right)):
            low = ''.join(ch.lower() if i and ch.isupper() and right[i - 1].isupper() else ch for i, ch in enumerate(right))
            right = f'[.right.sc]##{low}##'
        else:
            right = f'[.right]#{right}#'
        text = (text + ' ' if text else '') + right
    # (` :::` at a cell's end: dots led to its end, the look's `ldr`.)
    if text.endswith(' :::'):
        text = text[:-4] + '[.ldr]##{nbsp}##'
    # (A line that AsciiDoc would read as a list's item, a footnote's
    # mark or a numbered clause first: `{empty}` before it.)
    if re.match(r'^(\*+|-|\.+|\d+\.|[A-Za-z]\.|[ivxIVX]+\))\s', text):
        text = '{empty}' + text
    if text.endswith('-') and not text.endswith('--'):
        text = text[:-1] + '{shy}'
    return text


def same_indent(a, b):
    """Whether two lines are set in alike: within two points (the scan's
    ink, a quotation mark hung out), or one of them not known."""
    return a is None or b is None or abs(a - b) <= 2


class Gen:
    def __init__(self):
        self.out, self.fit = [], []
        self.para, self.kind = None, None
        self.page = self.col = None
        self.n = 0
        self.block = 0
        self.first = None
        self.skip = False
        self.inner_n = {}
        self.outer = None
        self.boxed = False
        self.framed = False
        self.clear = False
        self.para_indent = None
        self.size = None
        self.table = None
        self.last_page = None
        self.last_tag = None

    def indent(self, n):
        """Line [n] of the column's indent on the scan (scan.json): its left
        end from the column's, to the half point; a line the OCR missed,
        none known."""
        rows = SCAN.get(str(self.page), {}).get(str(self.col), [])
        r = rows[n - 1] if 0 < n <= len(rows) else None
        if not r or r.get('left') is None or r.get('guess'):
            return None
        col = self.col if self.col <= 2 else self.col - 2
        left = (53.2 if self.page % 2 else 58.8) if col == 1 else RULE[self.side] + 2
        if self.col > 2:
            # (A floating block's line: from the block's edge.)
            left = EDGES.get((self.page, col), left)
        return max(0, round((r['left'] - left) * 2) / 2)

    def stanza_gap(self, n):
        """Whether line [n] of the column starts a stanza on the scan: more
        than a point and a half further under the line before than that
        is under its own."""
        rows = SCAN.get(str(self.page), {}).get(str(self.col), [])
        if not 2 < n <= len(rows):
            return False
        a, b, c = rows[n - 3], rows[n - 2], rows[n - 1]
        if not (a and b and c) or any(r.get('base') is None or r.get('guess') for r in (a, b, c)):
            return False
        return (c['base'] - b['base']) - (b['base'] - a['base']) > 1.5

    def centre_shift(self, n):
        """Line [n] of the column's centre on the scan from the column's,
        or None."""
        rows = SCAN.get(str(self.page), {}).get(str(self.col), [])
        r = rows[n - 1] if 0 < n <= len(rows) else None
        if not r or r.get('left') is None or r.get('guess'):
            return None
        col = self.col if self.col <= 2 else self.col - 2
        verso = self.page % 2 == 0
        left = (58.8 if verso else 53.2) if col == 1 else RULE[self.side] + 2
        right = RULE[self.side] - 2 if col == 1 else 530.5 - (43.9 if verso else 51.1)
        # (Only a short line: a long one's centre the column's whatever the
        # OCR's box says.)
        if r['right'] - r['left'] > 0.7 * (right - left):
            return None
        return (r['left'] + r['right']) / 2 - (left + right) / 2

    def key(self):
        return f'top/{self.page}/{self.col}/{self.first}'

    def flush(self, going_on=False):
        if not self.para:
            self.para = None
            return
        if self.kind == 'T':
            # (The rows as a table without rules, a cell a part of the line.)
            cells = [(r + ' ').split(' | ') for r in self.para]
            n = max(len(c) for c in cells)
            m = ADJUST.get(self.key())
            margin = f',margin-top={m}pt' if m else ''
            # (`@table ROLE COLS GRID`: a table of the look's, its columns'
            # widths and specs, its rules; otherwise one without rules.)
            role, cols, grid = self.table or ('', f'{n}*', 'none')
            self.table = None
            self.out += [f'[.rows{"." + role if role else ""},cols="{cols}",grid={grid},frame=none{margin}]', '|===']
            for c in cells:
                c = c + [''] * (n - len(c))
                # (A row of two printed lines, ` // ` between a cell's: a
                # row for each, the cells of one line spanning both.)
                k = max(len(x.split(' // ')) for x in c)
                for j in range(k):
                    row = []
                    for x in c:
                        parts = x.split(' // ')
                        if len(parts) == k:
                            row.append('|' + inline(parts[j].strip(), 'P'))
                        elif j == 0:
                            row.append(f'.{k}+|' + inline(x.strip(), 'P'))
                    self.out.append(' '.join(row))
            self.out += ['|===', '']
            for f in self.fit:
                if f['block'] == self.block:
                    f['key'] = self.key()
            self.para = None
            self.block += 1
            return
        role = ROLES[self.kind] + ('.on' if self.kind in ('P',) and self.going else '')
        # (The block after a boxed list: below it and what floats beside
        # it, the look's `clr`.)
        if self.clear:
            role += '.clr'
            self.clear = False
        # (A verse's lines indented as the scan's, line by line: `m<half
        # points>`, the look's.)
        if self.kind == 'V':
            k = round((self.para_indent if self.para_indent is not None else 20) * 2)
            INDENTS.add(k)
            role += f'.m{k}'
        # (A caption centred where the scan's is, under a cut to a side:
        # a margin on one side twice its centre's distance from the
        # column's.)
        if self.kind == 'C' and not self.boxed:
            shift = self.centre_shift(self.first)
            if shift is not None and abs(shift) > 3:
                k = round(abs(2 * shift) * 2)
                (INDENTS if shift > 0 else RINDENTS).add(k)
                role += f'.m{k}' if shift > 0 else f'.r{k}'
        if self.size:
            role += f'.s{self.size}'
        # (The paragraph's own pitch, the scan's: some pieces set solid,
        # some leaded.)
        pitch = ADJUST.get(f'pitch/{self.key()}')
        if pitch:
            PITCHES.add(round(pitch * 100))
            role += f'.p{round(pitch * 100)}'
        m = ADJUST.get(self.key())
        margin = f',margin-top={m}pt' if m else ''
        if going_on:
            self.para[-1] += '{ls}'
        self.out += [f'[.{role}{margin}]', *self.para, '']
        for f in self.fit:
            if f['block'] == self.block:
                f['key'] = self.key()
        self.para = None
        self.block += 1

    def line(self, text):
        self.n += 1
        if self.para is None or not self.para:
            self.first = self.n
        self.fit.append({'page': self.page, 'col': self.col, 'line': self.n, 'block': self.block, 'kind': self.kind})
        # (PROBE: a floating block's lines marked, `§`, for compare.py to
        # tell them from the lines beside them on the same baselines.)
        return ('§' if self.col > 2 and PROBE else '') + inline(text, self.kind)

    def cut(self, cid, where=None):
        """A cut from the scan (cuts.json): as wide as the scan's, its top
        where the scan's is under the line before it (scan.json); floated
        to its side where the column's lines run beside it."""
        c = CUTS[cid]
        x0, y0, x1, y1 = c['pt']
        # (As wide as its crop of the scan, the crop's margin round the
        # cut and all: the cut itself at the scan's scale.)
        width = round(c['crop'][2] * 72 / 400, 1) if c.get('crop') else round(x1 - x0, 1)
        prev = SCAN.get(str(self.page), {}).get(str(self.col), [])
        above = prev[self.n - 1]['base'] if self.n and self.n - 1 < len(prev) and prev[self.n - 1] and prev[self.n - 1].get('base') else None
        # (Under the line before: its baseline and its descent, 1.7 points;
        # at a column's top, under the column's.)
        top = round((y0 - (above + 1.7) if above is not None else y0 - COLUMN_TOP) + ADJUST.get(f'cut/{cid}', 0), 2)
        attrs = f'pdfwidth={width}pt'
        role = 'cut'
        if where in ('left', 'right'):
            # (`@cut ID left`: floated to that side though the scan's lines
            # beside it run both sides of it, its gap from the lines beside
            # it on the scan.)
            rows = [r for r in prev if r and r.get('left') is not None and y0 < r['base'] < y1 + 6]
            # (The lines' indent beside it, the lower quartile of theirs:
            # an OCR box reaching into the cut's ink no matter, nor a verse's
            # turnovers hung further in.)
            gap = (sorted(r['left'] for r in rows)[len(rows) // 4] - x1) if where == 'left' and rows else \
                  (x0 - sorted(r['right'] for r in rows)[-1 - len(rows) // 4]) if rows else 4
            c = dict(c, side=where, gap=round(max(0.0, gap), 2))
        if c.get('side') and where != 'center':
            # (Floated to its side by the look's `cutl` or `cutr`, the lines
            # beside it as far from it as the scan's.)
            role += '.cutl' if c['side'] == 'left' else '.cutr'
            # (The gap less the crop's margin, six of the scan's pixels,
            # the image that much wider than the cut each side.)
            gap = max(0.0, c['gap'] - (6 * 72 / 400 if c.get('crop') else 0))
            role += f",float-width={width}pt,float-gap={round(gap, 2)}pt"
        else:
            attrs += ',align=center'
        # (No space under it of its own, the lines below it where the
        # scan's are; floated, down to the foot of the last line beside it
        # (its baseline and the foot of its line's box, 2.6 points, and
        # margins.py's fit, `foot/ID`), which the volume sets reaching past
        # the cut's foot: the lines after it at the full width from there.)
        bottom = 0.0
        if c.get('side') and where != 'center':
            # (A line set in from the column's edge at the cut's side: the
            # OCR's box a little into the cut's ink no matter.)
            col_left = (53.2 if self.page % 2 else 58.8) if self.col == 1 else RULE[self.side] + 2
            col_right = RULE[self.side] - 2 if self.col == 1 else 530.5 - (43.9 if self.page % 2 == 0 else 51.1)
            beside = [r['base'] for r in prev if r and r.get('base') is not None and y0 < r['base'] < y1 + 6
                      and r.get('left') is not None
                      and (r['left'] > col_left + 20 if c['side'] == 'left' else r['right'] < col_right - 20)]
            if beside:
                # (The image as set: the crop's height at its width, a
                # little more than the cut's, the crop's margin round it.)
                shown = width * c['crop'][3] / c['crop'][2]
                bottom = round(max(0.0, max(beside) + 2.6 + ADJUST.get(f'foot/{cid}', 0) - (y0 + shown)), 2)
        bottom = f'{bottom}pt'
        self.out += [f'[.{role},margin-top={top}pt,margin-bottom={bottom}]', f'image::{cid}.png[{attrs}]', '']
        self.fit.append({'page': self.page, 'col': self.col, 'line': 'cut', 'block': self.block, 'kind': 'I', 'cut': cid,
                         'after': self.n, 'float': bool(c.get('side')) and where != 'center'})
        self.block += 1

    def run(self):
        raws = [r.rstrip('\n') for r in open(SPEC, encoding='utf-8')]
        # (A run of verse whose long lines the column turns: each line
        # with its turnover a block of its own, hung, `vh`.)
        hang, run, turned = set(), [], False
        for i, raw in enumerate(raws + ['@end']):
            if raw.startswith('V ') or (run and raw.startswith('  ')):
                run.append(i)
                turned = turned or raw.startswith('  ')
            elif raw.startswith('#'):
                continue
            else:
                if turned:
                    hang.update(run)
                run, turned = [], False
        for i, raw in enumerate(raws):
            if not raw.strip() or raw.startswith('#'):
                continue
            if raw.startswith('@page'):
                self.flush()
                self.page = int(raw.split()[1])
                self.skip = bool(ONLY) and self.page not in ONLY
                self.col = 0
                side = 'verso' if self.page % 2 == 0 else 'recto'
                self.side = side
                # (`plate`: a page of one column, an engraving and its
                # title and captions, no running head; `blank`: its back,
                # nothing on it.)
                kind = raw.split()[4] if len(raw.split()) > 4 else side
                # (A page the volume doesn't number on from the one before,
                # an issue after the pages between left out: its own folio.)
                start = f',folio-start={self.page}' if self.last_page is not None and self.page != self.last_page + 1 else ''
                self.last_page = self.page
                if self.last_tag is not None:
                    self.out += [f'// end::page-{self.last_tag}[]', '']
                self.last_tag = self.page
                self.out += [f'// page {self.page}', f'// tag::page-{self.page}[]', f'[.p{self.page}.{kind}%notitle{start}]',
                             f'== Page {self.page}', '']
                if kind in ('blank', 'drawn'):
                    # (`drawn`: a page its role's background draws whole,
                    # the Synopsis of Voting, p3.py's.)
                    self.out += ['{empty}', '']
                continue
            if raw == '@column':
                # (A paragraph going on into the next column: its last line
                # here justified.)
                going = self.para is not None and self.kind == 'P'
                self.flush(going_on=going)
                if self.col:
                    self.out += ['[.column]', '<<<', '']
                self.col += 1
                self.n = 0
                self.going = going
                continue
            if raw.startswith('@rule'):
                # (`@rule wide`: the long rule over a table, the look's
                # `trule`.)
                self.flush()
                self.out += ["[.trule]" if raw.endswith('wide') else "[.rule]", "'''", '']
                self.block += 1
                continue
            if raw.startswith('@float'):
                # (A block floating to the column's side, the lines beside it
                # running round it: a catalogue's remarks beside its list.)
                self.flush()
                _, side, width, gap = raw.split()
                self.out += [f'[.cut{side[0]},float-width={width}pt,float-gap={gap}pt]', '--', '']
                self.outer = (self.col, self.n)
                self.col += 2
                self.n = self.inner_n.get((self.page, self.col), 0)
                continue
            if raw.startswith('@table'):
                self.flush()
                _, role, cols, grid = raw.split()
                self.table = (role, cols, grid)
                continue
            if raw.startswith('@size'):
                # (The blocks after it in a size of type of their own, the
                # scan's (`s<tenths>`, the look's), to the next `@size`.)
                self.flush()
                parts = raw.split()
                self.size = round(float(parts[1]) * 10) if len(parts) > 1 else None
                if self.size:
                    SIZES.add(self.size)
                continue
            if raw.startswith('@box'):
                # (A block of the column's lines floating to its side, as
                # wide as the scan's: a catalogue's list beside its brace,
                # its lines kept to its width whatever floats beside it.)
                self.flush()
                parts = raw.split()
                side, width = parts[1], parts[2]
                # (`framed`: ruled round, a letter boxed in a playbill: a
                # table of one cell, the look's `lbox`.)
                self.framed = 'framed' in parts
                self.out += [f'[.cut{side[0]},float-width={width}pt,float-gap=0pt]', '--', '']
                if self.framed:
                    self.out += ['[.lbox,cols="1",frame=all,grid=none,margin-bottom=0pt]', '|===', 'a|', '']
                self.boxed = True
                continue
            if raw == '@end':
                self.flush()
                if self.boxed and self.framed:
                    self.out += ['|===', '']
                    self.framed = False
                self.out += ['--', '']
                if self.boxed:
                    self.boxed = False
                    self.clear = True
                    continue
                self.inner_n[(self.page, self.col)] = self.n
                self.col, self.n = self.outer
                continue
            if raw.startswith('@cut'):
                # (A cut breaking into a paragraph: its line before the cut
                # justified, the paragraph going on after it.)
                going = self.para is not None and self.kind == 'P'
                self.flush(going_on=going)
                if going:
                    self.para, self.going = None, True
                self.cut(*raw.split()[1:])
                continue
            if raw.startswith('  '):
                if self.para is None:
                    self.kind, self.para = 'P', []
                    self.going = True
                self.para.append(self.line(raw[2:]))
                continue
            kind, text = raw[0], raw[2:]
            if kind == 'T':
                # (A row of cells, ` | ` between them: a printed line of two
                # things side by side, a poem's two columns, a catalogue's.)
                if self.kind != 'T' or self.para is None:
                    self.flush()
                    self.kind, self.going = 'T', False
                    self.para = []
                for _ in range(text.count(' // ') + 1):
                    self.line(text)
                self.para.append(text)
                continue
            # (The issue's date: the volume's line over its first page.)
            if kind == 'H' and text in WEEK:
                kind, text = 'W', f'FOR THE WEEK ENDING {WEEK[text]}.'
            if kind == 'V' and i in hang:
                self.flush()
                self.kind, self.going = 'v', False
                self.para_indent = self.indent(self.n + 1)
                self.para = [self.line(text)]
                continue
            if kind == 'V' and self.kind == 'V' and self.para is not None and same_indent(self.indent(self.n + 1), self.para_indent) \
                    and not self.stanza_gap(self.n + 1):
                self.para.append(self.line(text))
                continue
            self.flush()
            self.kind, self.going = kind, False
            self.para_indent = self.indent(self.n + 1)
            self.para = [self.line(text)]
        self.flush()
        if self.last_tag is not None:
            self.out += [f'// end::page-{self.last_tag}[]']


def main():
    g = Gen()
    g.run()
    head = ['// Punch, 17 July, 14 and 21 August 1841, as the first volume prints',
            '// them, page for page and line for line: generated from',
            '// tool/punch_1841/punch.spec by gen.py.', '']
    out = g.out
    if ONLY:
        # (A page alone, to fit it without the pages before it: its own
        # folio.)
        keep, mine = [], False
        for line in out:
            if line.startswith('// page '):
                mine = int(line.split()[2]) in ONLY
            if mine:
                keep.append(line)
        out = [f':folio-start: {min(ONLY)}', ''] + keep
    open(os.path.join(SRC, 'text', 'pages.adoc'), 'w', encoding='utf-8').write('\n'.join(head + out) + '\n')
    json.dump(g.fit, open(os.path.join(WORK, 'fit.json'), 'w'), indent=0)
    # (The pitches' roles, between the look's marks.)
    look = os.path.join(SRC, 'punch-look.yml')
    s = open(look, encoding='utf-8').read()
    START, END = "    # (The pitches: gen.py's.)\n", '    # (The pitches end.)\n'
    if START in s:
        a, rest = s.split(START, 1)
        _, b = rest.split(END, 1)
        roles = ''.join(f'    p{p}: {{ line_pitch: {p / 100}pt }}\n' for p in sorted(PITCHES))
        roles += ''.join(f'    m{k}: {{ margin_left: {k / 2} }}\n' for k in sorted(INDENTS))
        roles += ''.join(f'    r{k}: {{ margin_right: {k / 2} }}\n' for k in sorted(RINDENTS))
        roles += ''.join(f'    s{k}: {{ font_size: {k / 10} }}\n' for k in sorted(SIZES))
        open(look, 'w', encoding='utf-8').write(a + START + roles + END + b)


main()
