"""The showcase's months (test/showcase/poor-richard/text/NN-month.adoc)
from the transcription (months.spec), with adjust.json's settings for
each line and cell.

months.spec: `@month NAME LEAF` starts a month (LEAF its leaf of the
scan); `@head` its heading's two parts (`XI Mon.|January hath xxxi
days.`); `@verse` its lines (`.` before a line a title, centred in
italic; `^` a line centred), each a printed line; `@thead` the
calendar's head, when the printing has one (each cell's lines apart by
`/`); `@rows` the calendar's rows, a day each, their cells apart by `|`
(the Sun's rising and setting written `7 14 5`).

adjust.json (fit.py's): `"month/verse/N"` or `"month/R/C"` (row,
column) to how the printing sets that line or cell: `{"in": points}`
set in that much further, `{"justify": true}` spread to the cell's
width; `"month/margin/PART"`, a part's space above it.

    python3 -I gen.py [SPEC [OUTDIR]]
"""
import json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
SPEC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, 'months.spec')
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(HERE, '../../test/showcase/poor-richard/text')
WRAPS = json.load(open(os.path.join(HERE, 'wraps.json'))) if os.path.exists(os.path.join(HERE, 'wraps.json')) else {}
ADJUST = json.load(open(os.path.join(HERE, 'adjust.json'))) if os.path.exists(os.path.join(HERE, 'adjust.json')) else {}
NAMES = ['january', 'february', 'march', 'april', 'may', 'june', 'july', 'august',
         'september', 'october', 'november', 'december']
# The calendar's columns, their widths in points as the printing's (the
# day of the month, of the week, the remarkable days, high water, the
# Moon's place, the Sun's rising and setting, the lunations) and how each
# aligns its cells.
COLUMNS = [(16.16, '>'), (14.26, '>'), (93.6, '<'), (14.6, '<'), (14.4, '^'), (38.1, '<'), (85.2, '<')]
SPANS = set()
PITCHES = set()
# The calendar's line height at its size that sets its rows 12.021 pt
# apart (measured), and so the pitch to the line height.
BASE_HEIGHT, BASE_PITCH = 0.933, 12.021


def span(width):
    SPANS.add(round(width * 10))
    return f'[.i{round(width * 10)}]##{{nbsp}}##'


def line(text, key):
    a = ADJUST.get(key, {})
    if a.get('in'):
        text = span(a['in']) + text
    if a.get('justify'):
        text += '{ls}'
    return text


def sun(cell):
    """The Sun's rising and setting, its three figures where the printing
    sets them in the column: the hour at the left, the minutes in the
    middle, the hour of setting at the right."""
    parts = cell.split()
    if len(parts) != 3:
        return cell
    return ''.join(f'[.{r}]##{p}##' for r, p in zip(('sh', 'sm', 'ss'), parts))


def month(name, leaf, head, verse, thead, rows):
    # (Its pages numbered as the printing numbers them: January the 7th,
    # the planets' motions and the table of kings left out before it.)
    start = ',folio-start=7' if name == 'january' else ''
    out = ['<<<', '', f'[#{name}.month,leaf={leaf}{start}]', f'== [.mon]#{head[0]}# {head[1]}', '']
    # (The verse where the printing sets it: a blank as tall as the room
    # above it, a block's own margin not counting first in its section.)
    space = ADJUST.get(f'{name}/margin/verse', 0) + 20
    out += [f'image::blank.svg[role=spacer,pdfwidth=1pt,pdfheight={max(space, 0.01):.2f}pt]', '']
    block = []

    def flush():
        if block:
            role, lines = block[0], block[1]
            attrs = f'.{role}' + (f',margin-top={margin_of(role)}pt' if margin_of(role) else '')
            out.extend([f'[{attrs}]', *lines, ''])
            block.clear()

    def margin_of(role):
        return None

    role_index = [0]
    n = 0
    for raw in verse:
        n += 1
        kind = 'verse-title' if raw.startswith('.') else 'verse-line'
        text = raw[1:] if kind == 'verse-title' else raw.strip()
        text = line(text, f'{name}/verse/{n}')
        if block and block[0] == kind:
            block[1].append(text)
        else:
            flush()
            role_index[0] += 1
            block[:] = [kind, [text]]
    flush()
    cols = ','.join(f'{a}{round(w * 10)}' for w, a in COLUMNS)
    tm = ADJUST.get(f'{name}/margin/table')
    # (Its rows as far apart as the printing's: its own pitch, a role
    # the look gives its line height, gen.py's.)
    pitch = round(ADJUST.get(f'{name}/pitch', 11.81) * 100)
    PITCHES.add(pitch)
    attrs = f'.calendar.p{pitch},cols="{cols}",frame=topbot,grid=cols' + (',options=header' if thead else '')
    attrs += f',margin-top={tm}pt' if tm else ''
    out += [f'[{attrs}]', '|===']
    if thead:
        out.append(' '.join('|' + ' +\n'.join(c.split('/')) for c in thead))
        out.append('')
    for r, cells in enumerate(rows, 1):
        cells = cells + [''] * (7 - len(cells))
        cells[5] = sun(cells[5])
        # (A row the PDF would set on two lines where the printing has
        # one: its words set closer, `tight<n>`, wraps.py's.)
        if WRAPS.get(f'{name}/{r}'):
            n = min(WRAPS[f'{name}/{r}'], 6)
            cells = [f'[.tight{n}]##{c}##' if i in (2, 6) and c else c for i, c in enumerate(cells)]
        out.append(' '.join('|' + (line(c, f'{name}/{r}/{i}') if c else '') for i, c in enumerate(cells)))
    out += ['|===', '']
    return '\n'.join(out)


def main():
    months, cur = [], None
    section = None
    for raw in open(SPEC, encoding='utf-8'):
        raw = raw.rstrip('\n')
        if raw.startswith('@month'):
            _, name, leaf = raw.split()
            cur = {'name': name, 'leaf': leaf, 'verse': [], 'thead': None, 'rows': []}
            months.append(cur)
        elif raw.startswith('@head'):
            cur['head'] = raw[6:].split('|')
        elif raw == '@verse':
            section = 'verse'
        elif raw.startswith('@thead'):
            cur['thead'] = raw[7:].split('|')
        elif raw == '@rows':
            section = 'rows'
        elif raw.strip():
            if section == 'verse':
                cur['verse'].append(raw)
            else:
                cur['rows'].append(raw.split('|'))
    for i, m in enumerate(months):
        path = os.path.join(OUT, f'{i + 1:02d}-{m["name"]}.adoc')
        open(path, 'w', encoding='utf-8').write(
            '// Generated by tool/poor_richard_1733/gen.py from months.spec.\n'
            + month(m['name'], m['leaf'], m['head'], m['verse'], m['thead'], m['rows']))
    print(len(months), 'months;', len(SPANS), 'spans')
    # (The spans' widths, the look's `i<tenths>` roles, between its marks.)
    look_path = os.path.join(OUT, '..', 'poor-richard-look.yml')
    look = open(look_path, encoding='utf-8').read()
    start = '    # (The spans: gen.py\'s.)\n'
    end = '    # (The spans end.)\n'
    head, rest = look.split(start, 1)
    _, tail = rest.split(end, 1)
    spans = ''.join(f'    i{w}: {{ width: {w / 10}pt }}\n' for w in sorted(SPANS))
    look = head + start + spans + end + tail
    start, end = '      # (The pitches: gen.py\'s.)\n', '      # (The pitches end.)\n'
    head, rest = look.split(start, 1)
    _, tail = rest.split(end, 1)
    pitches = ''.join(f'      p{p}: {{ line_height: {BASE_HEIGHT * p / 100 / BASE_PITCH:.4f} }}\n' for p in sorted(PITCHES))
    open(look_path, 'w', encoding='utf-8').write(head + start + pitches + end + tail)


main()
