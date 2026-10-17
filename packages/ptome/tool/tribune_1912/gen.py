"""The Tribune's two pages (test/showcase/tribune/text/pages.adoc) from the
regions' specs (regions/PAGE-ID.spec): each page a section of its own,
its regions in the cells of a table whose columns are the scan's (the
rules between them its grid), each source line a printed line
(`:source-lines:`); each region's text inside its column where the
scan's is (`r-<id>`: its margins), each line's size from its width on
the scan (`z<hundredths>`), each block's space above it and its pitch
from adjust.json (margins.py's, pitch.py's), keyed by its first line
(`top/PAGE/REGION/LINE`); the cuts cut from the scan (fetch.yml). The
roles it makes written into the look.

    python3 -I gen.py
"""
import json, os, re, statistics, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from common import WORK, PX
from lines import regions

SRC = os.path.join(HERE, '..', '..', 'test', 'showcase', 'tribune')
ADJ = os.path.join(HERE, 'adjust.json')
ADJUST = json.load(open(ADJ)) if os.path.exists(ADJ) else {}
FONTS = os.path.expanduser('~/.local/share/fonts/ptome')

# (Each style of line: its face (for its width), its look's role, its
# letters' spacing in ems.)
FACE = {
    'roman': 'OldStandardTT-Regular.ttf', 'bold': 'OldStandardTT-Bold.ttf', 'italic': 'OldStandardTT-Italic.ttf',
    'gothic': 'FiraSansCondensed-SemiBold.ttf', 'gothicl': 'LibreFranklin-Regular.ttf',
    'xc': 'LeagueGothic-Regular.ttf',
}
STYLES = {
    # style: (face, align, letter spacing)
    'xc': ('xc', 'center', 0), 'xc>': ('xc', 'right', 0), 'xc<': ('xc', 'left', 0),
    'gc': ('gothic', 'center', 0), 'gcc': ('gothic', 'center', 0),
    'gb': ('gothic', 'center', 0), 'gb<': ('gothic', 'left', 0), 'gb>': ('gothic', 'right', 0),
    'sb': ('gothic', 'center', 0), 'ban<': ('bold', 'left', 0), 'ban>': ('bold', 'right', 0),
    'rb': ('bold', 'center', 0), 'cb': ('bold', 'center', 0), 'cbn': ('bold', 'center', 0),
    'cbc': ('bold', 'center', 0), 'adb': ('bold', 'center', 0),
    'ch': ('roman', 'center', 0), 'chc': ('roman', 'center', 0), 'chs': ('roman', 'center', 0),
    'rl<': ('roman', 'left', 0), 'rl>': ('roman', 'right', 0), 'rd': ('roman', 'center', 0),
    'cr': ('roman', 'center', 0), 'cap': ('roman', 'center', 0.12), 'capt': ('roman', 'center', 0),
    'capi': ('italic', 'center', 0), 'adi': ('italic', 'center', 0), 'jump': ('bold', 'center', 0),
    'ad': ('gothic', 'center', 0.1),
    'tv0': ('roman', 'center', 0.04), 'tv2': ('roman', 'center', 0.04), 'tv3': ('bold', 'center', 0),
    'tv4': ('bold', 'center', 0), 'tv5': ('bold', 'center', 0),
    'hm0': ('roman', 'center', 0), 'hm1': ('roman', 'center', 0), 'hm2': ('roman', 'center', 0),
}
# (A region's body: the face its paragraphs are set in, by the spec's
# `@role`.)
BODY = {'b8n': 'gothicl', 'tv1': 'bold', 'hm1': 'roman'}

ROLES = {'z': set(), 'p': set(), 'in': set(), 'r': {}}
_W = {}


def advance(text, face, spacing=0.0):
    """[text]'s width set in [face] at one point (its letters spaced
    [spacing] em more)."""
    from fontTools.ttLib import TTFont
    if face not in _W:
        f = TTFont(os.path.join(FONTS, FACE[face]))
        _W[face] = (f.getBestCmap(), f['hmtx'], f['head'].unitsPerEm)
    cmap, hmtx, upm = _W[face]
    t = text.replace('__', '')
    w = sum(hmtx[cmap[ord(c)]][0] if ord(c) in cmap else upm * 0.5 for c in t) / upm
    return w + spacing * max(0, len(t) - 1)


def inline(text):
    """A spec line's text as AsciiDoc: its marks taken literally."""
    t = text.replace('*', '{asterisk}').replace('#', '{hash}')
    t = re.sub(r'\^([^^]+)\^', r'^\1^', t)
    if re.match(r'^(\[|\.|-|\d+\.\s|[A-Za-z]\.\s|=)', t):
        t = '{empty}' + t
    if t.endswith(' +'):
        t = t[:-2] + '{nbsp}+'
    return t


def size_role(pt):
    n = max(300, round(pt * 100))
    ROLES['z'].add(n)
    return f'z{n}'


def spec(page, rid):
    path = os.path.join(HERE, 'regions', f'{page}-{rid}.spec')
    if not os.path.exists(path):
        return None, []
    lines = open(path, encoding='utf-8').read().rstrip('\n').split('\n')
    return lines[0].split()[2:], lines[1:]


def region_edges(lines, scan):
    """The region's text edges on the scan, in points: the left of its
    lines not set in, the right of its full lines."""
    lefts, rights = [], []
    k = 0
    for line in lines:
        if line.startswith('@'):
            continue
        s = scan[k] if k < len(scan) else None
        k += 1
        if not s or s.get('left') is None:
            continue
        if line.startswith('  '):
            lefts.append(s['left'])
        if not line.startswith('S '):
            rights.append(s['right'])
    if not lefts and not rights:
        # (A region of heads alone: its margins the left of its lines set
        # flush left, the right of those set flush right, else none.)
        k = 0
        ls, rs = [], []
        for line in lines:
            if line.startswith('@'):
                continue
            s = scan[k] if k < len(scan) else None
            k += 1
            if s and s.get('left') is not None and line.startswith('S '):
                style = line.split()[1]
                if '<' in style:
                    ls.append(s['left'])
                if '>' in style:
                    rs.append(s['right'])
        return (min(ls) if ls else None), (max(rs) if rs else None)
    if not lefts:
        lefts = [s['left'] for s in scan if s and s.get('left') is not None]
    if not rights:
        rights = [s['right'] for s in scan if s and s.get('right') is not None]
    if not lefts or not rights:
        return None
    lefts.sort()
    rights.sort()
    # (The right edge: the furthest right that three lines reach, the
    # full lines of a list of names among its short ones.)
    right = next((r for r in reversed(rights) if sum(1 for q in rights if abs(q - r) < 2) >= 3),
                 rights[len(rights) * 3 // 4])
    return lefts[len(lefts) // 5], right


class Region:
    """A region's AsciiDoc: its blocks, each its lines; and the lines'
    places for the fit (fit.json)."""

    def __init__(self, page, rid, cell, fit):
        self.page, self.rid = page, rid
        self.args, self.lines = spec(page, rid)
        sc = json.load(open(os.path.join(WORK, 'scan.json'))).get(str(page), {}).get(rid, [])
        self.scan = sc
        self.fit = fit
        self.cell = cell
        self.out = []
        if not self.lines:
            return
        left, right = region_edges(self.lines, sc) or (None, None)
        left = cell[0] if left is None else left
        right = cell[1] if right is None else right
        # (Its text inside the cell: as far in from the cell's edges as the
        # scan's is.)
        ml, mr = round(left - cell[0], 2), round(cell[1] - right, 2)
        ROLES['r'][f'r-{page}-{rid}'] = (max(0, ml), max(0, mr))
        self.measure = right - left
        self.body = self.body_size()
        self.track = self.tracking() if 'names' in (self.args or []) else 0

    def texts(self):
        return [l for l in self.lines if not l.startswith('@')]

    def body_size(self):
        """The region's text size: the size at which its full lines' words
        fill their measure, the fullest but a few."""
        sizes = []
        k = 0
        role = 'b8n' if 'names' in (self.args or []) else None
        for line in self.lines:
            if line.startswith('@role '):
                role = line.split()[1]
                continue
            if line.startswith('@'):
                continue
            s = self.scan[k] if k < len(self.scan) else None
            k += 1
            if not s or s.get('left') is None or line.startswith(('S ', 'L', 'F')):
                continue
            text = line[2:]
            face = BODY.get(role, 'roman')
            w = s['right'] - s['left']
            if w > 0.9 * self.measure:
                sizes.append(w / advance(text, face))
        if not sizes:
            return 7.0
        sizes.sort()
        return sizes[len(sizes) // 4] * 0.985

    def tracking(self):
        """A list of names' letter spacing (thousandths of an em): what
        its lines not justified (a name, a paragraph's last line) need to be
        as wide as the scan's at the region's size."""
        face = 'gothicl'
        ts = []
        k = 0
        lines = [l for l in self.lines if not l.startswith('@')]
        for i, line in enumerate(lines):
            s = self.scan[i] if i < len(self.scan) else None
            nxt = lines[i + 1] if i + 1 < len(lines) else 'P '
            if not s or s.get('left') is None or line.startswith(('S ', 'L', 'F', 'R')):
                continue
            if not nxt.startswith(('P ', 'N ', 'S ', '@')):
                continue  # (A line justified: its spaces stretched.)
            text = line[2:]
            n = len(text) - 1
            w = s['right'] - s['left']
            if n > 5 and w < 0.95 * self.measure:
                ts.append((w / self.body - advance(text, face)) / n)
        if not ts:
            return 0
        ts.sort()
        t = round(ts[len(ts) // 2] * 1000)
        ROLES.setdefault('tk', set()).add(t)
        return t

    def block(self, role, lines, kind, k0):
        """A block of [lines] (the region's lines from [k0]) with [role]."""
        key = f'top/{self.page}/{self.rid}/{k0 + 1}'
        m = ADJUST.get(key)
        pitch = ADJUST.get(f'pitch/{key}')
        roles = [f'r-{self.page}-{self.rid}'] + role
        if pitch:
            ROLES['p'].add(round(pitch * 100))
            roles.append(f'p{round(pitch * 100)}')
        attrs = '.' + '.'.join(roles) + (f',margin-top={m}pt' if m else '')
        self.out += [f'[{attrs}]'] + lines + ['']
        for i in range(len(lines)):
            self.fit.append({'page': self.page, 'region': self.rid, 'line': k0 + i + 1,
                             'block': key, 'kind': kind, 'key': key})

    def adoc(self):
        if not self.lines:
            return []
        k = 0
        # (A list of names: in the gothic, as the paper sets its lists.)
        role = 'b8n' if 'names' in (self.args or []) else None
        para, pk, pstart = [], None, 0
        indent = self.indent()

        def flush():
            nonlocal para
            if para:
                face = BODY.get(role, 'roman')
                # (A paragraph whose lines the scan sets at more than one
                # pitch, the scan bowed or the type changed: a block to each
                # run of lines on one pitch, all but the last justified to
                # their ends.)
                for a, b in self.segments(pstart, len(para)):
                    roles = [f'f-{face}', size_role(self.body)] + ([f'tk{self.track}'] if self.track else [])
                    if pk == 'P' and a == 0:
                        ROLES['in'].add(indent)
                        roles.append(f'in{indent}')
                    else:
                        roles.append('in0')
                    if b < len(para):
                        roles.append('jl')
                    self.block(roles, [inline(t) for t in para[a:b]], 'P', pstart + a)
                para = []

        for line in self.lines:
            if line.startswith('@role '):
                flush()
                role = line.split()[1]
                continue
            if line.startswith('@'):
                continue
            s = self.scan[k] if k < len(self.scan) else None
            if line.startswith('S '):
                flush()
                _, style, text = line.split(' ', 2)
                m = re.match(r'^(.*)@(\d+)-(\d+)$', style)
                span = None
                if m:
                    style, span = m.group(1), (int(m.group(2)) / PX, int(m.group(3)) / PX)
                face, align, sp = STYLES[style]
                w = (span[1] - span[0]) if span else \
                    (s['right'] - s['left']) if s and s.get('left') is not None else self.measure
                z = w / advance(text, face, sp)
                z = min(z * 0.99, 200)
                self.block([f's-{style.replace("<", "l").replace(">", "r")}', size_role(z)], [inline(text)], 'S', k)
            elif line.startswith('L'):
                flush()
                text, num = [x.strip() for x in line.split(' ', 1)[1].split('|')]
                z = self.body * 1.05
                role_ = 'tally-in' if line.startswith('L+') else 'tally'
                self.block([role_, size_role(z)], [f'{inline(text)} [.dots]#{num}#'], 'L', k)
            elif line.startswith('R '):
                flush()
                self.block(['in0'], self.row(line[2:]), 'R', k)
            elif line.startswith('F'):
                flush()
                # (Two parts of a line, the first at the left, the second
                # flush right, in the small bold, their size the measure's
                # less a gap.)
                parts = [p.strip() for p in line.split(' ', 1)[1].split('|')]
                z = self.measure / (sum(advance(p, 'bold') for p in parts) * 1.25)
                self.block(['folio2', 'f-bold', size_role(z)],
                           [inline(parts[0]) + ''.join(f' [.right]#{inline(p)}#' for p in parts[1:])], 'F', k)
            elif line.startswith(('P ', 'N ')):
                flush()
                pk, pstart, para = line[0], k, [line[2:]]
            else:
                if not para:
                    pk, pstart = ' ', k
                para.append(line[2:])
            k += 1
        flush()
        return self.out

    def segments(self, start, n):
        """The runs of a paragraph's [n] lines (from the region's line
        [start]) each on one pitch on the scan: [(from, to)]."""
        bases = [self.scan[start + i]['base'] if start + i < len(self.scan) else None for i in range(n)]
        out, a = [], 0
        for i in range(2, n):
            seg = [(j, bases[j]) for j in range(a, i + 1) if bases[j] is not None]
            if len(seg) < 3:
                continue
            xs, ys = [p[0] for p in seg], [p[1] for p in seg]
            mx, my = sum(xs) / len(xs), sum(ys) / len(ys)
            den = sum((x - mx) ** 2 for x in xs) or 1
            sl = sum((x - mx) * (y - my) for x, y in seg) / den
            if max(abs(y - (my + sl * (x - mx))) for x, y in seg) > 0.9 and i - a >= 3:
                out.append((a, i))
                a = i
        out.append((a, n))
        return out

    def row(self, text):
        """A row of cells, each where the scan's is (`X0-X1` its extent in
        the scan's pixels, `s` before it a cell of two small lines, ` // `
        between them), its text sized to fill it: a table of its own."""
        cells = []
        for c in text.split(' | '):
            m = re.match(r'^(s?)(\d+)-(\d+) (.*)$', c)
            small, x0, x1, body = m.group(1) == 's', int(m.group(2)) / PX, int(m.group(3)) / PX, m.group(4)
            cells.append((small, x0, x1, body))
        edges, cols, content = [self.cell[0]], [], []
        for small, x0, x1, body in cells:
            if x0 > edges[-1] + 0.5:
                cols.append(x0 - edges[-1])
                content.append('a|')
            cols.append(x1 - x0)
            lines = [b.strip() for b in body.split(' // ')]
            face = 'roman'
            z = min((x1 - x0) / advance(l.replace('^', ''), face) for l in lines) * 0.985
            align = 'center' if small else 'justify'
            content.append(f'a|[.{size_role(z)}.c-{align}]\n' + ' +\n'.join(inline(l) for l in lines))
            edges.append(x1)
        if edges[-1] < self.cell[1] - 0.5:
            cols.append(self.cell[1] - edges[-1])
            content.append('a|')
        spec = ','.join(str(max(1, round(c * 100))) for c in cols)
        return [f'[.folio,cols="{spec}",grid=none,frame=none]', '!===', *content, '!===']

    def indent(self):
        """A paragraph's first line's indent, in tenths of a point: the
        scan's, the median of the region's."""
        ins = []
        k = 0
        lefts = sorted(s['left'] for s in self.scan if s and s.get('left') is not None)
        base = lefts[len(lefts) // 5] if lefts else 0
        for line in self.lines:
            if line.startswith('@'):
                continue
            s = self.scan[k] if k < len(self.scan) else None
            k += 1
            if line.startswith('P ') and s and s.get('left') is not None:
                ins.append(s['left'] - base)
        return round(statistics.median(ins) * 10) if ins else 0


def cut(name, box, cell):
    """A cut from the scan: as wide as the scan's, where it is in its cell
    (its margin above it adjust.json's `cut/NAME`, cuts.py's fit)."""
    x0, y0, x1, y1 = box
    w = (x1 - x0) / PX
    m = ADJUST.get(f'cut/{name}')
    attrs = f'pdfwidth={w:.2f}pt,role=cut' + (f',margin-top={m}pt' if m else '')
    return [f'[{attrs.split(",", 1)[1].replace("role=cut", ".cut").replace(",margin-top", ",margin-top")}]'
            if False else '', f'image::{name}.jpg[{attrs}]', '']


def main():
    regs = {p: {rid: (kind, box) for rid, kind, box in rs} for p, rs in regions().items()}
    fit = []
    out = ['// The New-York Tribune of 16 April 1912, its first two pages as the',
           '// paper prints them: generated from tool/tribune_1912/regions by gen.py.', '']
    pt = lambda x: round(x / PX, 2)

    def region(page, rid, cell):
        body = Region(page, rid, (pt(cell[0]), pt(cell[1])), fit).adoc()
        return [f'// tag::r-{page}-{rid}[]'] + body + [f'// end::r-{page}-{rid}[]', ''] if body else []

    # Page 1: the title, the folio line, the banner, then the columns.
    p = 1
    W = 6256
    A, B, C, D, E, F = 0, 965, 1840, 2708, 3578, 4452
    out += ['// page 1', '// tag::page-1[]', '[.page1%notitle]', '== Page 1', '',
            'image::blank.svg[role=spacer,pdfwidth=1pt,pdfheight=0.01pt]', '']
    out += cut('masthead', regs[1]['masthead'][1], (0, W))
    out += region(1, 'folio', (0, W))
    out += region(1, 'banner', (0, W))
    cols = ','.join(str(round(x)) for x in (B - A, F - B, W - F))
    out += [f'[.front,cols="{cols}",grid=cols,frame=none]', '|===', 'a|']
    out += region(1, 'crowd', (A, B))
    out += ['a|']
    out += region(1, 'art-head', (B, F))
    out += cut('art', regs[1]['art'][1], (B, F))
    out += ['[.captions,cols="1,1",grid=none,frame=none]', '!===', 'a!']
    out += region(1, 'caption-l', (B, (B + F) / 2))
    out += ['a!']
    out += region(1, 'caption-r', ((B + F) / 2, F))
    out += ['!===', '']
    ncols = ','.join(str(round(x)) for x in (C - B, D - C, E - D, F - E))
    out += [f'[.lower,cols="{ncols}",grid=cols,frame=none]', '!===', '2+a!']
    out += region(1, 'names-head', (B, D))
    out += ['2.2+a!']
    out += region(1, 'loss', (D, F))
    out += ['.2+a!']
    out += region(1, 'names-a', (B, C))
    out += ['.2+a!']
    out += region(1, 'names-b', (C, D))
    out += ['a!']
    out += region(1, 'deep', (D, E))
    out += ['a!']
    out += region(1, 'pearls', (E, F))
    out += ['!===', '', 'a|']
    out += region(1, 'lead', (F, W))
    out += ['|===', '', '// end::page-1[]', '']

    # Page 2: the folio, the section of the ship across the page, the
    # columns under it.
    A, B, C, D, E = 0, 1836, 3578, 4466, 5334
    out += ['// page 2', '// tag::page-2[]', '[.page2%notitle]', '== Page 2', '',
            'image::blank.svg[role=spacer,pdfwidth=1pt,pdfheight=0.01pt]', '']
    out += region(2, 'folio', (0, W))
    out += region(2, 'section-head', (0, W))
    out += cut('section', regs[2]['section'][1], (0, W))
    cols = ','.join(str(round(x)) for x in (B - A, C - B, W - C))
    out += [f'[.inside,cols="{cols}",grid=cols,frame=none]', '|===', 'a|']
    out += region(2, 'c12', (A, B))
    hcols = ','.join(str(round(x)) for x in (950, B - 950))
    out += [f'[.ads,cols="{hcols}",grid=cols,frame=none]', '!===', 'a!']
    out += cut('hunyadi', regs[2]['hunyadi'][1], (A, 950))
    out += ['a!']
    out += region(2, 'hardman', (950, B))
    out += ['!===', '', 'a|']
    out += region(2, 'c34', (B, C))
    out += ['a|']
    rcols = ','.join(str(round(x)) for x in (D - C, E - D, W - E))
    out += [f'[.right,cols="{rcols}",grid=cols,frame=none]', '!===', '2+a!']
    out += region(2, 'c56', (C, E))
    out += ['a!']
    out += region(2, 'sos', (E, W))
    out += ['a!']
    out += region(2, 'names-cont', (C, D))
    out += ['2+a!']
    out += region(2, 'travelers', (D, W))
    out += cut('hudson', regs[2]['hudson'][1], (D, W))
    out += ['!===', '', '|===', '', '// end::page-2[]', '']

    os.makedirs(os.path.join(SRC, 'text'), exist_ok=True)
    open(os.path.join(SRC, 'text', 'pages.adoc'), 'w', encoding='utf-8').write('\n'.join(out) + '\n')
    json.dump(fit, open(os.path.join(WORK, 'fit.json'), 'w'), indent=0)
    look = os.path.join(SRC, 'tribune-look.yml')
    s = open(look, encoding='utf-8').read()
    start, end = "    # (gen.py's roles.)\n", "    # (gen.py's roles end.)\n"
    if start in s:
        a, rest = s.split(start, 1)
        _, b = rest.split(end, 1)
        roles = ''.join(f'    z{n}: {{ font_size: {n / 100} }}\n' for n in sorted(ROLES['z']))
        roles += ''.join(f'    p{n}: {{ line_pitch: {n / 100}pt }}\n' for n in sorted(ROLES['p']))
        roles += ''.join(f'    in{n}: {{ text_indent: {n / 10} }}\n' for n in sorted(ROLES['in']))
        roles += '    in0: { text_indent: 0 }\n'
        roles += ''.join(f'    tk{t}: {{ letter_spacing: {t / 1000}em }}\n' for t in sorted(ROLES.get('tk', ())))
        roles += ''.join(f'    {r}: {{ margin_left: {ml}, margin_right: {mr} }}\n'
                         for r, (ml, mr) in sorted(ROLES['r'].items()))
        open(look, 'w', encoding='utf-8').write(a + start + roles + end + b)


main()
