"""The Second Reader's text from its specs, each block where the printing
sets it.

    python3 -I build.py SPEC-DIR OUT-DIR [MARGINS.json]

Each SPEC-DIR/NAME.spec becomes OUT-DIR/NAME.adoc: the spec's AsciiDoc as
it is, but

- a `@words ATTRS` block (rows of `X word | X word`, X the word's left
  edge from the text's, in points; `@end`) a table of the lesson's new
  words, its columns the edges of every row's words, merged within 2 pt,
  a word spanning to the next edge its row uses;
- a `@key` or `@subs` block (rows of cells divided by `|`, the halves by
  `||`; a row of one cell spans both) a table of the key's marks: its
  halves either side of a rule, each cell in a width of its own;
- each block's own space above it (`margin-top`) the one that puts its
  first line's baseline (an image's top) where the printing's is: from
  MARGINS.json (fit.py fits them), keyed by the block's place in its
  spec. The printing's places are the scan's (blocks.json, blocks.py),
  found by the block's first words on its page (`// page N`), or given
  (`at=` a baseline, `top=` an image's top, in points from the page's
  top, the scan's); both are moved by the page's offset (where its
  running head is against the PDF's).

Writes OUT-DIR/fit.json: each fitted block's key, page, kind, its first
words and its target.
"""
import json, os, re, sys, unicodedata

WORK = os.environ.get('MCG_WORK', os.path.expanduser('~/.cache/asciidart-work/print-match'))
MEASURE = 252.0
# (The PDF's running head's baseline; the scan's page by page.)
HEAD = 26.0
ROMAN = ['i', 'ii', 'iii', 'iv', 'v', 'vi']
SPECS = ['title-page', 'preface', 'contents', 'introduction', 'lessons']


def core(text):
    t = unicodedata.normalize('NFKD', text)
    # (A cross reference's text.)
    t = re.sub(r'<<[^,>]*,([^>]*)>>', r'\1', t)
    t = re.sub(r'\[\.[^\]]*\]|#|_|pass:\[[^\]]*\]|<[^>]*>|\{[a-z]+\}', '', t)
    # (A leading numeral aside: a contents' or a list's.)
    return re.sub(r'^[0-9]+', '', re.sub(r'[^a-z0-9]', '', t.lower()))


def page_number(token):
    return ROMAN.index(token) + 1 if token in ROMAN else int(token)


def words_table(attrs, rows):
    edges = sorted({round(x, 1) for row in rows for x, _ in row})
    merged = []
    for e in edges:
        if merged and e - merged[-1] < 2:
            continue
        merged.append(e)
    if merged[0] > 0.5:
        merged.insert(0, 0.0)
    else:
        merged[0] = 0.0

    def col(x):
        return min(range(len(merged)), key=lambda i: abs(merged[i] - x))

    widths = [b - a for a, b in zip(merged, merged[1:] + [MEASURE])]
    # (AsciiDoc's column widths are whole numbers, in proportion: tenths
    # of a point.)
    out = [f'[{attrs},cols="{",".join(str(round(w * 10)) for w in widths)}",frame=none,grid=none]', '|===']
    for row in rows:
        cells = []
        at = 0
        placed = [(col(x), w) for x, w in row]
        for k, (c, w) in enumerate(placed):
            if c > at:
                cells.append(f'{c - at}+|' if c - at > 1 else '|')
            end = placed[k + 1][0] if k + 1 < len(placed) else len(merged)
            span = end - c
            cells.append(f'{span}+|{w}' if span > 1 else f'|{w}')
            at = end
        if at < len(merged):
            cells.append(f'{len(merged) - at}+|' if len(merged) - at > 1 else '|')
        out.append(' '.join(cells))
    out.append('|===')
    return out


# The key's tables: the rule's place from the text's left edge, each
# half's cells' roles (their widths in the look) and the insets that set
# each half's first cell where the printing sets it.
KEY = dict(role='key', rule=125.0, cells=['k-l', 'k-as', None], insets=['k-left', 'k-right'])
SUBS = dict(role='key.subs', rule=128.1, cells=['s-l', 's-for', 's-snd', 's-as', None],
            insets=['s-left', 's-right'])


def key_table(kind, attrs, rows):
    spec = KEY if kind == 'key' else SUBS
    role = '.' + spec['role']
    out = [f'[{role}{("," + attrs) if attrs else ""},cols="{round(spec["rule"] * 10)},{round((MEASURE - spec["rule"]) * 10)}",'
           f'frame=none,grid=cols]', '|===']

    def half(cells, inset):
        parts = [f'[.{inset}]##{{nbsp}}##']
        for cell_role, cell in zip(spec['cells'], cells):
            parts.append(f'[.{cell_role}]##{cell}##' if cell_role else cell)
        return ''.join(parts)

    for row in rows:
        if '||' not in row:
            out.append(f'2+^|{row}')
            continue
        left, right = row.split('||')
        out.append(f'|{half(left.split("|"), spec["insets"][0])} '
                   f'|{half(right.split("|"), spec["insets"][1])}')
    out.append('|===')
    return out


ATTR_RX = re.compile(r'^\[[^\[].*\]$')


def split_attrs(body):
    """An attribute list's entries (without its brackets), `at=` and
    `top=` taken out."""
    entries = []
    cur = ''
    quoted = False
    for ch in body:
        if ch == '"':
            quoted = not quoted
        if ch == ',' and not quoted:
            entries.append(cur)
            cur = ''
            continue
        cur += ch
    entries.append(cur)
    target = {}
    kept = []
    for e in entries:
        m = re.match(r'^(at|top)=([-\d.]+)$', e.strip())
        if m:
            target[m[1]] = float(m[2])
        elif e != '' or kept:
            kept.append(e)
    return kept, target


def with_margin(entries, margin):
    entries = [e for e in entries if not e.strip().startswith('margin-top=')]
    return entries + [f'margin-top={margin:.2f}pt']


class Builder:
    def __init__(self, margins, measured, offsets):
        self.margins = margins
        self.measured = measured
        self.offsets = offsets
        self.fits = []

    def target(self, page, kind, first, explicit, used, pics_used):
        if page is None:
            return None
        off = self.offsets.get(page, -1.0)
        if 'at' in explicit:
            return explicit['at'] + off
        if 'top' in explicit:
            return explicit['top'] + off
        data = self.measured.get(str(page + 4))
        if data is None:
            return None
        if kind == 'image':
            pics = sorted([p for p in data['pics'] if p['x1'] - p['x0'] > 120], key=lambda p: p['top'])
            k = pics_used.get(page, 0)
            if k < len(pics):
                pics_used[page] = k + 1
                return pics[k]['top'] + off
            return None
        taken = used.setdefault(page, set())
        want = core(first)
        for n, l in enumerate(data['lines']):
            if n in taken:
                continue
            if kind == 'heading':
                if core(l['t']).startswith('lesson'):
                    taken.add(n)
                    return l['base'] + off
                continue
            have = core(re.sub(r'^\s*\(?[0-9Il]{1,3}[.,]\s*', '', l['t']))
            k = min(len(want), len(have), 8)
            # (A short line, a title, whole: not the start of a longer.)
            if len(want) < 10 and want != have and kind != 'table':
                continue
            if k >= 3 and want[:k] == have[:k]:
                taken.add(n)
                return l['base'] + off
        return None

    def build(self, spec_path, out_path):
        name = os.path.splitext(os.path.basename(spec_path))[0]
        lines = open(spec_path, encoding='utf-8').read().split('\n')
        out = []
        page = None
        used, pics_used = {}, {}
        index = 0
        i = 0
        while i < len(lines):
            line = lines[i]
            m = re.match(r'^// page (\w+)$', line)
            if m:
                # (A page the printing starts between blocks: a break,
                # unless one comes before it already.)
                before = [o for o in out if o.strip() and not o.startswith('//')]
                if page is not None and before and before[-1] != '<<<':
                    out.extend(['<<<', ''])
                page = page_number(m[1])
                out.append(line)
                i += 1
                continue
            if line.startswith('##'):
                i += 1
                continue
            if not line.strip() or line.startswith('//'):
                out.append(line)
                i += 1
                continue
            # A block: its attribute lines, then its content.
            attr_lines = []
            while i < len(lines) and ATTR_RX.match(lines[i]):
                attr_lines.append(lines[i])
                i += 1
            head = lines[i]
            entries, explicit = split_attrs(attr_lines[-1][1:-1]) if attr_lines else ([], {})
            first = ''
            if head.startswith('== '):
                kind, block, first = 'heading', [head], head
                i += 1
            elif head.startswith('image::'):
                kind = 'image'
                m = re.match(r'^image::([^\[]+)\[(.*)\]$', head)
                ientries, iexplicit = split_attrs(m[2])
                explicit.update(iexplicit)
                block = (m[1], ientries)
                i += 1
            elif head.startswith('@'):
                kind = 'table'
                directive, _, rest = head.partition(' ')
                tattrs, texplicit = split_attrs(rest) if rest else ([], {})
                explicit.update(texplicit)
                rows = []
                i += 1
                while lines[i] != '@end':
                    rows.append(lines[i])
                    i += 1
                i += 1
                if directive == '@words':
                    first = re.sub(r'^[\d.]+ ', '', rows[0].split(' | ')[0].strip())
                else:
                    first = rows[0].replace('||', ' ').replace('|', ' ')
                block = (directive, ','.join(a for a in tattrs if a), rows)
            elif head in ("'''", '<<<'):
                kind, block = ('rule' if head == "'''" else 'break'), [head]
                i += 1
            else:
                kind = 'text'
                block = []
                delimited = head == '____'
                while i < len(lines):
                    block.append(lines[i])
                    i += 1
                    if delimited:
                        if len(block) > 1 and block[-1] == '____':
                            break
                    elif i < len(lines) and lines[i] == '':
                        break
                first = re.sub(r'^\. ', '', block[1] if delimited else head)
                # (A page that starts within the block: the next block's.)
                inner = [re.match(r'^// page (\w+)$', b) for b in block]
                inner = [x for x in inner if x]
            key = f'{name}:{index}'
            index += 1
            target = None
            # (A contents' entries follow from the first on each page, one
            # pitch apart: only those given a place are fitted.)
            auto = not any('toc-entry' in a for a in attr_lines)
            if (kind in ('heading', 'image', 'table', 'text') and auto) or explicit:
                target = self.target(page, 'text' if kind == 'rule' else kind, first, explicit,
                                     used, pics_used)
            margin = None
            if target is None and auto and kind in ('heading', 'image', 'table', 'text') and page is not None:
                print(f'unplaced: {key} p.{page} {kind} {first[:40]!r}')
            if target is not None:
                margin = self.margins.get(key, 0.0)
                font = ('heading' if kind == 'heading' else
                        'script' if any('script' in a for a in attr_lines) else 'text')
                self.fits.append(dict(key=key, page=page, kind=kind, first=first, target=target, font=font))
            # Write the block.
            if kind == 'image':
                path, ientries = block
                out.extend(attr_lines)
                if margin is not None:
                    ientries = with_margin(ientries, margin)
                out.append(f'image::{path}[{",".join(ientries)}]')
                continue
            if kind == 'table':
                directive, tattrs, rows = block
                out.extend(attr_lines)
                if margin is not None:
                    tattrs = ','.join(a for a in [tattrs, f'margin-top={margin:.2f}pt'] if a)
                if directive == '@words':
                    parsed = [[(float(x), w) for x, _, w in (c.strip().partition(' ') for c in row.split(' | '))]
                              for row in rows]
                    out.extend(words_table(tattrs, parsed))
                else:
                    out.extend(key_table(directive[1:], tattrs, rows))
                continue
            if attr_lines:
                out.extend(attr_lines[:-1])
                kept = entries if margin is None else with_margin(entries, margin)
                out.append('[' + ','.join(kept) + ']')
            elif margin is not None:
                out.append(f'[margin-top={margin:.2f}pt]')
            out.extend(block)
            if kind == 'text' and inner:
                page = page_number(inner[-1][1])
        open(out_path, 'w', encoding='utf-8').write('\n'.join(out).rstrip('\n') + '\n')


def offsets_of(measured):
    offsets = {}
    for leaf, v in measured.items():
        page = int(leaf) - 4
        heads = [l for l in v['lines'] if l['base'] < 40 and page > 1 and
                 re.search(r'ECLECTIC|SECOND|PREFACE|CONTENTS', l['t'])]
        if heads:
            offsets[page] = HEAD - heads[0]['base']
    return offsets


def main(spec_dir, out_dir, margins_path=None):
    margins = json.load(open(margins_path)) if margins_path and os.path.exists(margins_path) else {}
    measured = json.load(open(f'{WORK}/mcguffey/out/blocks.json'))
    builder = Builder(margins, measured, offsets_of(measured))
    for spec in SPECS:
        builder.build(f'{spec_dir}/{spec}.spec', f'{out_dir}/{spec}.adoc')
    json.dump(builder.fits, open(f'{out_dir}/fit.json', 'w'), ensure_ascii=False, indent=1)
    missing = [f for f in builder.fits if f['target'] is None]
    print(len(builder.fits), 'blocks fitted')


if __name__ == '__main__':
    main(*sys.argv[1:])
