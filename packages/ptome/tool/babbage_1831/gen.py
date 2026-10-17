"""Babbage's table of logarithms, pages 6 to 25 (the numbers 10,000 to
19,999), as the 1831 stereotype sets them: test/showcase/babbage/
text/pages.adoc, each page a section of its own (its heading hidden),
its table's rows the printing's, and images/frame-NN.svg, each page's
rules.

The logarithms are computed (to 40 places, rounded to seven): each row
the logarithms of ten numbers, its number in the Num. column (the whole
of it every tenth row, its last figure otherwise), the first column the
whole logarithm where its first three figures change from the row
before's (and on a page's first row), its last four figures otherwise,
the other columns their last four figures. As the printing marks them:
a figure rounded up has a dot under it; an entry whose first three
figures are no longer its row's has its first figure set small. The two
columns at the left are the arcs whose seconds the number counts: the
number's seconds (every fifth row) and ten times them (every row), the
minutes where they change, the degrees and minutes at the head. The
differences and their proportional parts in the column at the right,
where the printing has them (diff.spec, read against the scan).

    python3 -I gen.py
"""
import json, os, re
from decimal import Decimal, getcontext

HERE = os.path.dirname(os.path.abspath(__file__))
import sys as _sys
_sys.path.insert(0, HERE)
from common import EDGES, FOOT_RULE, HEAD_RULE, OUTER, PAGE, RULES, THICK, WORK
SRC = os.path.join(HERE, '..', '..', 'test', 'showcase', 'babbage')
getcontext().prec = 40
LN10 = Decimal(10).ln()
PAGES = range(6, 26)  # the printing's pages; page p holds rows 1000 + 50 (p - 6) on
ROWS = 50

RULES_TOP = 61.0
# (The page's margins, a verso's and a recto's: the table's outer edges
# where the thick rule puts them, 374.1 points across.)
MARGIN = {side: [39.23, round(416.3 - (t + EDGES[-1]), 2), 5, round(t + OUTER[side], 2)]
          for side, t in THICK.items()}
ADJUST = json.load(open(os.path.join(HERE, 'adjust.json'))) if os.path.exists(os.path.join(HERE, 'adjust.json')) else {}


def log7(n):
    """The logarithm's seven figures after the point, rounded, and
    whether rounding put the last one up."""
    v = (Decimal(n).ln() / LN10 - Decimal(4)) * Decimal(10 ** 7)
    r = int((v + Decimal('0.5')).to_integral_value(rounding='ROUND_FLOOR'))
    return r, r > v


def figures(digits, up, small_first=False):
    """Figures as the printing sets them: the last dotted under if put
    up, the first small if marked."""
    out = digits
    if small_first:
        out = f'[.sf]##{out[0]}##' + out[1:]
    if up:
        # (The dot under the last figure: an emphasis mark under it, the
        # look's `up` role.)
        out = out[:-1] + f'[.up]##{out[-1]}##'
    return out


def arc(seconds):
    s = seconds % 60
    m = seconds // 60 % 60
    d = seconds // 3600
    return d, m, s


def page_rows(p):
    first = 1000 + ROWS * (p - 6)
    rows = []
    prev_lead = None
    for i in range(ROWS):
        r = first + i
        logs = [log7(10 * r + c) for c in range(10)]
        lead = logs[0][0] // 10 ** 4
        cells = []
        whole = i == 0 or lead != prev_lead
        v, up = logs[0]
        cells.append(figures(f'{v:07d}', up) if whole else figures(f'{v % 10 ** 4:04d}', up))
        for v, up in logs[1:]:
            cells.append(figures(f'{v % 10 ** 4:04d}', up, v // 10 ** 4 != lead))
        prev_lead = lead
        # (The arcs: the number's seconds, and ten times them.)
        a = ''
        if r % 5 == 0:
            d, m, s = arc(r)
            a = f'[.min]##{m}′##' if s == 0 else f'[.arc]##{s}″##'
        d, m, s = arc(10 * r)
        if s == 0 and m == 0:
            b = f'[.min]##{d}°##'
        elif s == 0:
            b = f'[.min]##{m}′##'
        else:
            b = f'[.arc]##{s}″##' if i == 0 else f'[.arc]##{s}##'
        # (Every row's line as high as the larger number's, each row's
        # cell holding a space in its size, before its figure: the rows evenly
        # apart.)
        num = f'[.num]##{r}##' if r % 10 == 0 else f'[.num]##{{nbsp}}##{r % 10}'
        rows.append((a, b, num, cells))
    return first, rows


def head(p, first):
    lead = log7(10 * first)[0] // 10 ** 4
    return f'Log. {lead:03d}.', f'N. {first // 10}.'


def diff_spec():
    """diff.spec: each page's differences' column, its items in order."""
    pages, page = {}, None
    for line in open(os.path.join(HERE, 'diff.spec'), encoding='utf-8'):
        line = line.split('#', 1)[0].strip()
        if not line:
            continue
        if line.startswith('@page'):
            page = int(line.split()[1])
            pages[page] = []
            continue
        f = line.split()
        if f[0].startswith('+'):
            # (`+L D k-9 ROW`: the parts going on from the page before.)
            a, b = map(int, f[2].split('-'))
            pages[page].append({'side': f[0][1], 'd': int(f[1]), 'row': float(f[3]), 'parts': (a, b), 'on': True})
        else:
            parts = None
            if len(f) > 3:
                a, b = map(int, f[3][1:].split('-')) if '-' in f[3] else (1, 9)
                parts = (a, b)
            pages[page].append({'side': f[0], 'd': int(f[1]), 'row': float(f[2]), 'parts': parts, 'on': False})
    return pages


SPEC = diff_spec() if os.path.exists(os.path.join(HERE, 'diff.spec')) else {}


# How the column's blocks stack with no margins (measured on the PDF):
# the first's baseline under the first row's (a difference's, a table of
# parts going on from the page before's), a difference's line, its
# first part's under it, the parts' pitch, a difference after the ninth
# part; and how far the printing sets a difference's first part under it.
FIRST, FIRST_PARTS, D_LINE, TO_PART, PART, AFTER_PARTS = 0.86, -1.54, 9.89, 7.41, 7.35, 9.82
PART_GAP = 8.3
PITCH, GAP = 9.9, 4.9
FIRST_BASE = 95.25  # the first row's baseline, the scans'


def row_base(row):
    """A row of the table (fractional) as a baseline, in points under
    the first row's, the gaps between fives counted."""
    i = int(row // 1)
    if i < 0:
        return row * PITCH
    return i * PITCH + i // 5 * GAP + (row - i) * PITCH


def diff_cells(p):
    """The two cells of the differences' column, each its differences
    and their proportional parts in order down the page, each where the
    scan has it: its margin above worked out from how the blocks stack,
    and adjust.json's `d/PAGE/SIDE/K` (diffit.py's) on it."""
    out = []
    for side in ('L', 'R'):
        blocks = []
        base, after = None, None
        for k, it in enumerate(i for i in SPEC.get(p, []) if i['side'] == side):
            target = row_base(it['row'])
            natural = (FIRST_PARTS if it['on'] else FIRST) if base is None else base + (AFTER_PARTS if after == 'parts' else D_LINE)
            m = round(target - natural + ADJUST.get(f'd/{p}/{side}/{k}', 0), 2)
            margin = f',margin-top={m}pt' if m else ''
            if not it['on']:
                # (A difference with its parts at the left of its half, one
                # without them on the right further in.)
                role = 'd' + side.lower() + ('' if it['parts'] else 'a')
                blocks.append(f'[.{role}{margin}]\n{it["d"]}')
                base, after = target, 'd'
                margin = f',margin-top={PART_GAP - TO_PART:.2f}pt'
            else:
                base = target
            if it['parts']:
                a, b = it['parts']
                rows = ''.join(f'!{k} !{(it["d"] * k + 5) // 10}\n' for k in range(a, b + 1))
                # (The tenths against their rule, 8.1 points in from the
                # half's edge on the left, 8.4 on the right; the rule under
                # the ninth part, where the table ends.)
                role = 'parts' + side.lower() + ('.ends' if b == 9 else '')
                cols = '>34,>66' if side == 'L' else '>37,>63'
                # (On the right their figures ending 1.2 points further in.)
                width = '' if side == 'L' else ',width=94%'
                blocks.append(f'[.{role},cols="{cols}"{width},grid=cols,frame=none{margin}]\n!===\n{rows}!===')
                base = (base + PART_GAP if not it['on'] else base) + (b - a) * PART
                after = 'parts'
        out.append('\n\n'.join(blocks) or '{nbsp}')
    return out


def frame(p, side):
    """The page's rules: down the table, the thick ones heavier; across
    under the heads and over the figures at the foot."""
    t = THICK[side]
    x = [t + e for e in [OUTER[side]] + RULES[1:]]
    # (The rule before the differences down beside the figures at the
    # foot, or as far as the differences run past them.)
    stream_end = FOOT_RULE + 12
    for it in SPEC.get(p, []):
        b = FIRST_BASE + row_base(it['row'])
        if it['parts']:
            a, z = it['parts']
            b += (0 if it['on'] else PART_GAP) + (z - a) * PART + 2.5
        stream_end = max(stream_end, b + 1.5)
    lines = []

    def down(xx, y0, y1, w):
        lines.append(f'<rect x="{xx - w / 2:.2f}" y="{y0:.2f}" width="{w:.2f}" height="{y1 - y0:.2f}"/>')

    def across(x0, x1, y, w):
        lines.append(f'<rect x="{x0:.2f}" y="{y - w / 2:.2f}" width="{x1 - x0:.2f}" height="{w:.2f}"/>')

    down(x[0], RULES_TOP, FOOT_RULE, 1.0)
    down(x[1], RULES_TOP, FOOT_RULE, 1.2)
    down(x[2], RULES_TOP, FOOT_RULE, 3.2)
    for k in range(3, 13):
        if k == 8:
            continue
        down(x[k], HEAD_RULE, FOOT_RULE, 0.8)
    # (Between the fifth and sixth columns a heavier rule, and a bar in
    # the heads' row and the figures' at the foot.)
    down(x[8], HEAD_RULE, FOOT_RULE, 1.6)
    down(x[8], 66.0, 80.0, 1.6)
    down(x[8], 631.0, 645.0, 1.6)
    down(x[13], RULES_TOP, stream_end, 1.6)
    across(x[0], x[14], HEAD_RULE, 1.5)
    across(x[0], x[13], FOOT_RULE, 1.4)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{PAGE[0]}pt" height="{PAGE[1]}pt" '
            f'viewBox="0 0 {PAGE[0]} {PAGE[1]}"><g fill="#1a1a1a">' + ''.join(lines) + '</g></svg>\n')


def main():
    cols = {}
    for side in THICK:
        edges = [OUTER[side]] + EDGES[1:]
        widths = [edges[k + 1] - edges[k] for k in range(len(edges) - 1)]
        # (Diff.'s two halves: the left 23.1 points, its parts' figures
        # ending where the printing's do; the right 21.9.)
        widths = widths[:-1] + [23.1, widths[-1] - 23.1]
        # (The arcs centred, the numbers and the figures to the right.)
        align = ['^', '^'] + ['>'] * 11 + ['<', '<']
        cols[side] = ','.join(f'{a}{w * 100:.0f}' for a, w in zip(align, widths))
    out = ['// Babbage\'s table of logarithms, pages 6 to 25 of the 1831 printing:',
           '// generated by tool/babbage_1831/gen.py, do not edit.', '']
    roles = []
    for p in PAGES:
        side = 'verso' if p % 2 == 0 else 'recto'
        first, rows = page_rows(p)
        log_head, n_head = head(p, first)
        d0 = arc(first)
        d1 = arc(10 * first)
        out += [f'// page {p}', f'// tag::page-{p}[]', f'[.p{p}.{side}%notitle]', f'== Page {p}', '',
                f'[.loghead.{side}]', f'{log_head}{{nbsp}}{{nbsp}} [.logn]#{n_head}#', '',
                f'[.logs,cols="{cols[side]}",options=header,grid=none,frame=none]', '|===',
                f'^.>|[.archd]##{d0[0]}°## +\n[.archd]##{d0[1]}′## ^.>|[.archd]##{d1[0]}°## +\n[.archd]##{d1[1]}′## '
                '^.>|Num. ' + ' '.join(f'>.>|{c}[.hs{138 if c == 0 else 62}]##{{nbsp}}##' for c in range(10)) + ' 2+^.>|Diff.', '']
        left, right = diff_cells(p)
        for i, (a, b, num, cells) in enumerate(rows):
            arcs = ' '.join(f'|{x}' if x else '|' for x in (a, b))
            line = f'{arcs} |{num} ' + ' '.join(f'|{c}' for c in cells)
            if i == 0:
                line += f'\n.{ROWS + 3}+a|\n{left}\n.{ROWS + 3}+a|\n{right}\n'
            out += [line, '']
        # (The figures at the foot, under the foot's rule; two rows under
        # them for the differences running on below them, the first with
        # the folio under the second column of arcs.)
        # (The heads of the columns and the figures at the foot over the
        # middle of their columns' figures: each set to the right, a space
        # after it, `hs<tenths>`, half the figures' width less its own.)
        out += ['3+| ' + ' '.join(f'|[.foot]##{c}##[.hs{134 if c == 0 else 58}]##{{nbsp}}##' for c in range(10)), '',
                f'| |[.folio]#{p}# 11+| ', '', '13+| ', '', '|===', f'// end::page-{p}[]', '']
        svg = frame(p, side)
        open(os.path.join(SRC, 'images', f'frame-{p}.svg'), 'w').write(svg)
        m = ', '.join(f'{v:g}' for v in MARGIN[side])
        roles.append(f"      p{p}: {{ page_background_image: 'image:images/frame-{p}.svg[]', "
                     f"page_margin: [{m}], page_running_content: none }}\n")
    open(os.path.join(SRC, 'text', 'pages.adoc'), 'w', encoding='utf-8').write('\n'.join(out))
    look = os.path.join(SRC, 'babbage-look.yml')
    s = open(look, encoding='utf-8').read()
    START, END = '      # (The pages\' frames: gen.py\'s.)\n', '      # (The frames end.)\n'
    if START in s:
        a, rest = s.split(START, 1)
        _, b = rest.split(END, 1)
        open(look, 'w', encoding='utf-8').write(a + START + ''.join(roles) + END + b)


if __name__ == "__main__":
    main()
