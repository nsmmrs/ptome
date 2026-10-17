"""The showcase's text (test/showcase/johnson/text/pages.adoc) from the
transcription (johnson.spec), and JOHNSON_WORK/fit.json, each line's
place in it.

johnson.spec: each line a printed line, in the order the printing sets
them; `@page N` starts a page (N the scan's leaf), `@column` a column,
`@folio X` and `@foot SIGNATURE|CATCHWORD` the page's foot. A line
starting `E `, `S `, `C ` or `V ` starts an entry, a sense, a quotation
in prose or one in verse; a line starting with two spaces goes on with
the paragraph before (at a column's top, the paragraph the column before
left off). In a line, `{…}` is an entry's headword (its anchor, the
first three letters the running heads take); ` @…` at its end, or alone
on its line, a quotation's author, flush right, in italic but for its
`{…}`; a `-` ending a line a word divided there.

indents.json (fit.py): the lines set in further than their paragraph's
other lines, `"page/column/line": points`, each given a span that wide
before its first word.

    python3 -I gen.py [SPEC [OUT]]
"""
import json, os, re, sys, unicodedata

HERE = os.path.dirname(os.path.abspath(__file__))
SPEC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, 'johnson.spec')
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(HERE, '../../test/showcase/johnson/text/pages.adoc')
ROLES = {'E': 'entry', 'S': 'sense', 'C': 'cite', 'V': 'verse'}


def load(name):
    path = os.path.join(HERE, name)
    return json.load(open(path)) if os.path.exists(path) else {}


INDENTS = load('indents.json')
FLAT = set(INDENTS.pop('flat', []))
MARGINS = load('margins.json')


def author(text):
    """The author's words in italic but for their `{…}`, in the author
    span (flush right)."""
    parts = re.split(r'(\{[^}]*\})', text)
    out = []
    for part in parts:
        if not part:
            continue
        if part.startswith('{'):
            out.append(part[1:-1])
        else:
            lead, core, trail = re.match(r'^(\s*)(.*?)(\s*)$', part).groups()
            out.append(f'{lead}__{core}__{trail}' if core else part)
    return '[.author]#' + ''.join(out) + '#'


def slug(word):
    word = unicodedata.normalize('NFKD', word.replace('’', ''))
    word = ''.join(c for c in word if c.isalpha() or c == ' ').lower()
    return re.sub(r'\s+', '-', word.strip())


class Gen:
    def __init__(self):
        self.out = []
        self.anchors = set()
        self.fit = []      # each printed line: page, column, n, block
        self.page = self.column = None
        self.n = 0         # the line's number in its column
        self.para = None   # the paragraph being written: its lines
        self.block = 0

    def line(self, text):
        """A printed line's source: its headword, author, divided word."""
        def hw(m):
            word = m.group(1)
            key = slug(word.strip('_').rstrip('.'))
            anchor, k = f'w-{key}', 2
            while anchor in self.anchors:
                anchor, k = f'w-{key}-{k}', k + 1
            self.anchors.add(anchor)
            self.pending_anchor = (anchor, re.sub('[^A-Z]', '', word.upper())[:3])
            return f'[.hw]#{word}#'
        text = re.sub(r'\{([^}]*)\}', hw, text, count=1) if self.kind == 'E' and not self.para else text
        m = re.match(r'^(.*?)(?:^| )@(.*)$', text)
        if m:
            text = (m.group(1) + ' ' if m.group(1) else '') + author(m.group(2))
        if text.endswith('-') and not text.endswith('--'):
            text = text[:-1] + '{shy}'
        width = INDENTS.get(f'{self.page}/{self.column}/{self.n}')
        if width:
            text = f'[.i{round(width * 10)}]##{{nbsp}}##{text}'
        return text

    def break_paragraph(self):
        self.flush()

    def carry_over(self):
        """A paragraph going on at a column's top: its last line in the
        column before kept to the measure (ended with a line separator),
        the rest set on as it goes on."""
        self.out[self.last_line] += '{ls}'
        self.start(self.last_kind, goes_on=True)

    def start(self, kind, goes_on=False):
        self.flush()
        self.kind = kind
        self.pending_anchor = None
        self.para = []
        self.goes_on = goes_on

    def add(self, text):
        self.n += 1
        self.para.append(self.line(text))
        self.fit.append({'page': self.page, 'column': self.column, 'line': self.n, 'block': self.block,
                         'kind': self.kind, 'first': len(self.para) == 1 and not self.goes_on,
                         'author': '[.author]' in self.para[-1], 'text': text})

    def flush(self):
        if not self.para:
            return
        roles = ROLES[self.kind] + ('.goes-on' if self.goes_on else '')
        if f'{self.page}/{self.column}/{self.block}' in FLAT:
            roles += '.flat'
        # (A verse quotation's lines its own in HTML too.)
        attrs = [f'.{roles}' + ('%hardbreaks' if self.kind == 'V' else '')]
        margin = MARGINS.get(str(self.block))
        if margin:
            attrs.append(f'margin-top={margin}pt')
        if self.pending_anchor:
            self.out.append(f'[[{self.pending_anchor[0]},{self.pending_anchor[1]}]]')
        self.out.append(f'[{",".join(attrs)}]')
        if re.match(r'\d+\.', self.para[0]):
            # (A sense's number, not a list's.)
            self.para[0] = '{empty}' + self.para[0]
        self.out.extend(self.para)
        self.last_line, self.last_kind = len(self.out) - 1, self.kind
        self.out.append('')
        self.para = None
        self.block += 1

    def foot(self, kind, text):
        self.break_paragraph()
        attrs = ['.foot-folio' if kind == 'folio' else '.foot-line']
        margin = MARGINS.get(str(self.block))
        if margin:
            attrs.append(f'margin-top={margin}pt')
        if kind == 'foot':
            sig, _, cw = text.partition('|') if '|' in text else ('', '', text)
            body = (f'[.sig]#{sig}# ' if sig else '') + f'[.cw]#{cw}#'
        else:
            body = text
        self.out += [f'[{",".join(attrs)}]', body, '']
        self.fit.append({'page': self.page, 'column': self.column, 'line': kind, 'block': self.block})
        self.block += 1

    def run(self, spec):
        self.kind = None
        for raw in open(spec, encoding='utf-8'):
            raw = raw.rstrip('\n')
            if not raw.strip() or raw.startswith('#'):
                continue
            if raw.startswith('@page'):
                self.flush()
                if self.page is not None:
                    self.out += [f'// end::page-{self.page}[]', '', '<<<', '']
                self.page, self.column = int(raw.split()[1]), 0
                self.out += [f'// page {self.page}', f'// tag::page-{self.page}[]', '']
            elif raw == '@column':
                self.break_paragraph()
                if self.column:
                    self.out += ['[.column]', '<<<', '']
                self.column += 1
                self.n = 0
            elif raw.startswith('@folio'):
                self.foot('folio', raw.split(None, 1)[1])
            elif raw.startswith('@foot'):
                self.foot('foot', raw.split(None, 1)[1])
            elif raw.startswith('  '):
                if self.para is None:
                    self.carry_over()
                self.add(raw[2:])
            else:
                kind, text = raw[0], raw[2:]
                self.start(kind)
                self.add(text)
        self.flush()
        self.out += [f'// end::page-{self.page}[]']


g = Gen()
g.run(SPEC)
head = ['// The three pages of the first edition from LEVEL to LICENTIOUSLY',
        '// (volume II, the Wellcome Collection\'s copy, its scans n44–n46),',
        '// line for line: generated from tool/johnson_1755/johnson.spec by',
        '// gen.py. Each entry anchored by its word, its reference text the',
        '// first three letters the running heads take; each page tagged',
        '// (`page-46`…).', '']
open(OUT, 'w', encoding='utf-8').write('\n'.join(head + g.out).rstrip('\n') + '\n')
WORK = os.environ.get('JOHNSON_WORK', os.path.expanduser('~/.cache/asciidart-work/print-match/johnson'))
os.makedirs(WORK, exist_ok=True)
json.dump(g.fit, open(os.path.join(WORK, 'fit.json'), 'w'), indent=0)

# (The spans' widths, the look's `i<tenths>` roles, between its marks.)
LOOK = os.path.join(os.path.dirname(OUT), '..', 'johnson-look.yml')
look = open(LOOK, encoding='utf-8').read()
START = '    # (The lines the printing sets in further than their paragraph\'s\n'
END = '    # (The spans end.)\n'
spans = ''.join(f'    i{w}: {{ width: {w / 10}pt }}\n'
                for w in sorted({round(v * 10) for v in INDENTS.values()}))
head, rest = look.split(START, 1)
_, tail = rest.split(END, 1)
block = (START + "    # others, each its own span that wide, `[.i<tenths>]`: gen.py's.)\n"
         + spans + END)
open(LOOK, 'w', encoding='utf-8').write(head + block + tail)
counts = {}
for f in g.fit:
    if isinstance(f['line'], int):
        counts[(f['page'], f['column'])] = f['line']
print(' '.join(f'{p}/{c}:{n}' for (p, c), n in counts.items()))
