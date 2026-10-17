"""The Folio's Tempest (test/showcase/tempest/text/folio.adoc) from its
transcription (folio.spec), each line a printed line.

folio.spec: `@page N` starts a page (N the play's page, 1 to 19; `first`
or `last` after it, a page set across, its columns in bands); `@band`
and `@endband` a band of two columns across such a page; `@column` a
column; `@foot SIGNATURE|CATCHWORD` the page's foot line (either may be
empty); `@head` the first page's head (its headpiece, the title, the act
and scene in their box); `@rule` a rule across the page; `@initial X` a decorated initial cut from the
scan before the next line (`tempest-initial-x.png`), `@drop` the next
paragraph's first letter a drop initial; `# …` a comment.

A line starting `H ` is a scene's head (an act's, `H Actus …`, between
two rules), `D ` a line of a stage direction
(set in the middle; lines in a row one direction), `L ` a line set at
the column's edge (its own indent, adjust.json's: a song's lines, a
line the printing sets apart), `T `, `G `, `U ` and `F ` a title's
lines (the Epilogue's, the Scene's, their second lines) and FINIS, `S Speaker.|words` a speech's first line in prose (justified),
`V Speaker.|words` in verse (set flush left), two spaces a line going
on with the paragraph before, `~v ` or `~p ` a line going on in verse
or in prose after the other. In a line: ` @words` at its end set flush
right (a short direction, `Exit.`, on the line it ends); `{v words}`
turned down onto the line below, `{^ words}` up onto the line above,
after a bracket, as the Folio turns a line too long for its column;
`@brace` the tall brace before the Spirits; `_…_` italic.

adjust.json (margins.py's, headfit.py's, indents.py's, tight.py's): a
block's margin-top by its key (`top/page/column/line`, a paragraph's by
its first line; `at/page/k`, the page's k-th block of another kind);
`"page/column/line"`
to `{"in": points}`, a line set in further than its paragraph's others,
or `{"tight": n}`, its letters n tenths of a point closer;
`"block/N"` to a block's margin-top; `"pitch/page/column"` to the
column's lines' pitch (pitch.py's, the scan's).

    python3 -I gen.py [SPEC [OUT]]
"""
import json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
SPEC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, 'folio.spec')
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(HERE, '../../test/showcase/tempest/text/folio.adoc')
ADJUST = json.load(open(os.path.join(HERE, 'adjust.json'))) if os.path.exists(os.path.join(HERE, 'adjust.json')) else {}
SPANS = set()
PITCHES = set()
# (How far the brace stands after Iuno, in tenths of a point.)
BRACE_IN = 320
ROLES = {'H': 'fhead', 'A': 'fact', 'D': 'dir', 'S': 'sp', 'V': 'spv', 'C': 'sp-goes-on', 'CV': 'spv-goes-on',
         'L': 'ln', 'T': 'ftitle', 'U': 'fsub', 'G': 'fscene', 'F': 'finis'}


def inline(text):
    text = re.sub(r'\{v ([^}]*)\}', r'[.turn-down]##\1##', text)
    text = re.sub(r'\{\^ ([^}]*)\}', r'[.turn-up]##\1##', text)
    # (The scenes' heads' ligature, the transcription's `oe`.)
    text = text.replace('Scoena', 'Scœna')
    # (The brace in the list of the actors, clear of its longest name.)
    if '@brace' in text:
        SPANS.add(BRACE_IN)
        text = text.replace('@brace', f'[.i{BRACE_IN}]##{{nbsp}}##image:tempest-brace.svg[pdfwidth=8pt,vertical-align=-29pt]')
    m = re.match(r'^(.*?) ?@(.+)$', text)
    if m:
        text = (m.group(1) + ' ' if m.group(1) else '') + f'[.right]#{m.group(2)}#'
    if text.endswith('-') and not text.endswith('--'):
        text = text[:-1] + '{shy}'
    return text


# (A speech's first line's indent, the look's `sp` and `spv`, in tenths.)
SPEECH_INDENT = 123


class Gen:
    def __init__(self):
        self.out, self.para, self.kind, self.last = [], None, None, None
        self.page = self.col = None
        self.n = 0
        self.block = 0
        self.fit = []
        self.band = False
        self.extra = []
        self.roles = []
        self.section = None
        self.after_initial = None
        self.band_col = 0
        self.others = {}
        self.para_first = self.para_col = None
        self.last_key = None

    def key(self):
        """The key of the block being written in adjust.json: a paragraph's
        its first line's (`top/page/column/line`), which stays the same
        whatever is split or joined before it; another block's its place
        on its page among the blocks that aren't paragraphs (`at/page/k`)."""
        if self.para:
            return f'top/{self.page}/{self.para_col}/{self.para_first}'
        self.others[self.page] = self.others.get(self.page, 0) + 1
        return f'at/{self.page}/{self.others[self.page]}'

    def margin(self, key=None):
        key = key or self.key()
        self.last_key = key
        m = ADJUST.get(key)
        # (The block after an initial drawn up beside it, before it is
        # fitted: the initial's height.)
        if m is None and self.block == self.after_initial and self.para:
            m = -42.0
        return f',margin-top={m}pt' if m else ''

    def flush(self):
        if self.kind:
            self.last = self.kind
        if not self.para:
            self.para = None
            return
        role = ROLES[self.kind] + ''.join('.' + r for r in self.roles)
        # (A scene's head after the first page's: in the acts' italic.)
        if self.kind == 'H' and self.page > 1:
            role = 'fact'
        self.roles = []
        # (The last page's Epilogue and list of the actors: a larger type.)
        if self.page == 19 and self.col > 2 and self.kind == 'L':
            role += '.ep'
        # (The column's lines as far apart as the scan's: its own pitch.)
        pitch = ADJUST.get(f'pitch/{self.page}/{self.col}')
        if pitch and self.kind in ('S', 'V', 'C', 'CV', 'L', 'D'):
            PITCHES.add(round(pitch * 100))
            role += f'.p{round(pitch * 100)}'
        # (A long direction hung and justified, as the Folio sets one that
        # fills its first line; a short one in the middle.)
        if self.kind == 'D' and len(re.sub(r'\[[^]]*\]|[_#{}]', '', self.para[0])) >= 52:
            role = 'dirh'
        key = self.key()
        self.out += [f'[.{role}{self.margin(key)}]', *self.para, '']
        for f in self.fit:
            if f['block'] == self.block and isinstance(f['line'], int):
                f['key'] = key
        self.para = None
        self.block += 1

    def line(self, text):
        self.n += 1
        if not self.para:
            self.para_first, self.para_col = self.n, self.col
        a = ADJUST.get(f'{self.page}/{self.col}/{self.n}', {})
        text = inline(text)
        # (A line the face sets wider than its column, where the printing
        # squeezed it in: its letters set closer, `tight<n>`.)
        if a.get('tight'):
            # (Not over a turned phrase: its own span.)
            head, sep, tail = text.partition('[.turn-')
            space = ' ' if head[-1:].isspace() else ''
            text = f'[.tight{a["tight"]}]##{head.rstrip()}##' + (space + sep + tail if sep else '')
        if a.get('in'):
            w = round(a['in'] * 10)
            SPANS.add(w)
            text = f'[.i{w}]##{{nbsp}}##' + text
        # (FINIS, across the page under the columns: no column's line.)
        col = 0 if self.kind == 'F' else self.col
        self.fit.append({'page': self.page, 'col': col, 'line': self.n, 'block': self.block, 'kind': self.kind})
        return text

    def head_rule(self):
        """A rule over or under a head across its column."""
        self.out += [f'[.rule{self.margin()}]', "'''", '']
        self.fit.append({'page': self.page, 'col': self.col, 'line': 'head-rule', 'block': self.block, 'kind': 'R', 'key': self.last_key})
        self.block += 1

    def start_page(self, n, how):
        if self.band:
            self.end_band()
        if self.page is None or how or self.section in ('first', 'last'):
            # (A page set across, or the pages after the first: a section
            # of its own, which starts its page.)
            name = {'first': 'tempest-first', 'last': 'tempest-last'}.get(how, f'tempest-{n}')
            role = f'.{how}' if how else '.play'
            self.out += [f'[#{name}{role}%notitle]', f'== The Tempest, page {n}', '']
            self.section = how or 'play'
        else:
            self.out += ['<<<', '']
        self.page, self.col = n, 0
        self.out += [f'// page {n}', '']

    def end_band(self):
        self.flush()
        self.out += ['--', '']
        self.band = False

    def head(self):
        """The first page's head across it: its folio, the headpiece, the
        title, the act and scene in their box."""
        self.out += [f'[.folio-line{self.margin()}]', '[.right]#1#', '']
        self.block += 1
        self.out += [f'image::tempest-headpiece.png[role=cut,pdfwidth=423.7pt,align=center{self.margin()}]', '']
        self.block += 1
        for role, text in (('ftitle-the', 'THE'), ('ftitle-tempest', 'TEMPEST.')):
            self.out += [f'[.{role}{self.margin()}]', text, '']
            self.block += 1
        self.out += [f'[.rule{self.margin()}]', "'''", '']
        self.block += 1
        self.out += [f'[.act{self.margin()}]', '_Actus primus, Scena prima._', '']
        self.block += 1
        self.out += [f'[.rule{self.margin()}]', "'''", '']
        self.block += 1

    def run(self, spec):
        for raw in open(spec, encoding='utf-8'):
            raw = raw.rstrip('\n')
            if not raw.strip() or raw.startswith('#'):
                continue
            if raw.startswith('@page'):
                self.flush()
                parts = raw.split()
                self.start_page(int(parts[1]), parts[2] if len(parts) > 2 else None)
            elif raw == '@head':
                self.head()
            elif raw == '@band':
                self.flush()
                self.out += [f'[.columns.band{self.margin()}]', '--', '']
                self.block += 1
                self.band = True
                # (The band's columns numbered on from the band's above it:
                # the last page's second band's are its 3rd and 4th.)
                self.band_col = 0
            elif raw == '@endband':
                self.end_band()
            elif raw == '@rule':
                # (A rule across the page, the printing's.)
                self.flush()
                self.out += [f'[.rule{self.margin()}]', "'''", '']
                self.fit.append({'page': self.page, 'col': 0, 'line': 'rule', 'block': self.block, 'kind': 'R', 'key': self.last_key})
                self.block += 1
            elif raw == '@column':
                carry = self.para is not None and self.kind in ('S', 'C', 'V', 'CV')
                if carry:
                    self.para[-1] += '{ls}'
                self.flush()
                if (self.band_col if self.band else self.col):
                    self.out += ['[.column]', '<<<', '']
                self.col += 1
                self.band_col += 1
                self.n = 0
                self.para_at_top = True
            elif raw.startswith('@foot'):
                if self.band:
                    self.end_band()
                self.flush()
                sig, _, cw = raw[6:].partition('|')
                body = (f'[.sig]#{sig}# ' if sig else '') + (f'[.cw]#{cw}#' if cw else '')
                role = 'foot-line' + ('.foot-across' if self.section in ('first', 'last') else '') \
                    + ('.foot-last' if self.section == 'last' else '')
                self.out += [f'[.{role}{self.margin()}]', body, '']
                self.fit.append({'page': self.page, 'col': self.col, 'line': 'foot', 'block': self.block, 'kind': 'F', 'key': self.last_key})
                self.block += 1
            elif raw.startswith('@initial'):
                self.flush()
                letter = raw.split()[1].lower()
                self.out += [f'image::tempest-initial-{letter}.png[role=initial,pdfwidth=43.7pt,align=left{self.margin()}]', '']
                self.block += 1
                self.after_initial = self.block
            elif raw == '@drop':
                self.flush()
                self.extra.append('drop')
            elif raw.startswith('~v ') or raw.startswith('~p '):
                # (A speech going on from prose into verse, or back.)
                self.flush()
                self.kind = 'CV' if raw[1] == 'v' else 'C'
                self.para = [self.line(raw[3:])]
            elif raw.startswith('  ') and self.para is not None and ADJUST.get(f'split/{self.page}/{self.col}/{self.n + 1}') \
                    and '[.turn-' not in self.para[-1] and '{v ' not in raw and '{^ ' not in raw:
                # (A paragraph split where the scan's lines drift from the
                # pitch, the paper being warped: the line before kept to the
                # measure, the rest a paragraph going on with its own margin.)
                kind = self.kind
                if kind in ('S', 'C'):
                    self.para[-1] += '{ls}'
                self.flush()
                self.kind = 'CV' if kind in ('V', 'CV') else 'C'
                self.para = [self.line(raw[2:])]
            elif raw.startswith('  '):
                if self.para is None:
                    # (A speech going on at a column's top: in verse or in
                    # prose as it was.)
                    self.kind = 'CV' if self.last in ('V', 'CV') else 'C'
                    self.para = []
                self.para.append(self.line(raw[2:]))
            elif raw.startswith('H ') and (raw.startswith('H Actus') or self.page > 1):
                # (An act's head between two rules, in italic; a scene's
                # after the first page's as well; at a column's top, the
                # running head's rule over it.)
                self.flush()
                if self.n:
                    self.head_rule()
                self.kind = 'A'
                # (The act and its first scene a wide space apart.)
                self.para = [self.line(re.sub(r'([.:]) (Sc)', r'\1{nbsp}{nbsp}{nbsp}\2', raw[2:]))]
                self.flush()
                self.head_rule()
            else:
                kind, text = raw[0], raw[2:]
                if kind in ('D', 'L') and self.kind == kind and self.para is not None and not self.extra \
                        and not ADJUST.get(f'split/{self.page}/{self.col}/{self.n + 1}'):
                    self.para.append(self.line(text))
                    continue
                # (A speech whose first line turns its last words up onto
                # the line above, a speech of one line: the two set as one
                # paragraph, the words turned onto a line of their own
                # paragraph; the second speech set in as a speech is.)
                if kind in ('S', 'V') and '{^ ' in text and self.kind == 'S' and self.para is not None \
                        and len(self.para) == 1 and not self.extra:
                    spk, _, words = text.partition('|')
                    SPANS.add(SPEECH_INDENT)
                    self.para.append(f'[.i{SPEECH_INDENT}]##{{nbsp}}##'
                                     + self.line(f'[.spk]#{spk.strip("_")}# {words}'))
                    self.kind = kind
                    continue
                self.flush()
                # (The roles `@drop` gave the paragraph it starts.)
                self.roles, self.extra = self.extra, []
                self.kind = kind
                if kind in ('S', 'V'):
                    spk, _, words = text.partition('|')
                    text = f'[.spk]#{spk.strip("_")}#' + (' ' + words if words else '')
                self.para = [self.line(text)]
        if self.band:
            self.end_band()
        self.flush()


g = Gen()
g.run(SPEC)
head = ['// The Tempest as the First Folio prints it (1623), pages 1-19 of the',
        '// Comedies, line for line: generated from tool/tempest_1623/folio.spec',
        '// by gen.py (the words the Text Creation Partnership\'s, EEBO-TCP',
        '// A11954, laid on the scan\'s lines and read against it). Each page a',
        '// section of its own (its heading hidden), the first and the last set',
        '// across the page, their columns in bands.', '']
open(OUT, 'w', encoding='utf-8').write('\n'.join(head + g.out).rstrip('\n') + '\n')
WORK = os.environ.get('TEMPEST_WORK', os.path.expanduser('~/.cache/asciidart-work/print-match/tempest'))
os.makedirs(WORK, exist_ok=True)
json.dump(g.fit, open(os.path.join(WORK, 'fit.json'), 'w'), indent=0)
# (The spans' widths, the look's `i<tenths>` roles, between its marks.)
LOOK = os.path.join(os.path.dirname(OUT), '..', 'folio-look.yml')
look = open(LOOK, encoding='utf-8').read()
START, END = '    # (The spans: gen.py\'s.)\n', '    # (The spans end.)\n'
if START in look:
    head_, rest = look.split(START, 1)
    _, tail = rest.split(END, 1)
    spans = ''.join(f'    i{w}: {{ width: {w / 10}pt }}\n' for w in sorted(SPANS))
    spans += ''.join(f'    p{p}: {{ line_pitch: {p / 100}pt }}\n' for p in sorted(PITCHES))
    open(LOOK, 'w', encoding='utf-8').write(head_ + START + spans + END + tail)
counts = {}
for f in g.fit:
    if isinstance(f['line'], int):
        counts[(f['page'], f['col'])] = f['line']
print(' '.join(f'{p}/{c}:{n}' for (p, c), n in sorted(counts.items())))
