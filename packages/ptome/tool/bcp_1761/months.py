"""The Calendar (leaves 23-34) from calendar.spec: each month's page, its
lines in order (for the fit and the comparison), its rules drawn where
the scan's are (images/cal-LEAF.svg: the double frame, the rules across
under the titles and the table's head, the rules down between the
table's columns, from calgeo.py's cal.json), its lines' baselines on the
scan, and its AsciiDoc: the titles, the table's head and body as tables
whose columns are the scan's, a day to a row at the scan's pitch, a cell's
rule a leader of rules (`-`), the notes and the foot.

    from months import pages, page_lines, scan_baselines, adoc, svg

(Named so as not to stand for the standard library's calendar.)
"""
import json, os, re, statistics, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from common import WORK

PAGE = (425.2, 669.0)
TOP = 40.0  # (the frame's top on the page)
SIZE = 10.2  # (the table's type: Long Primer, its names' widths the scan's)
PAD = 1.0  # (a cell's padding either side)
SQUEEZE = set()  # (the names set closer: their letter spacing, thousandths of an em)
_FONTS = {}

# (The months whose notes are set otherwise than January's: their blocks
# of lines and each's role.)
NOTES = {25: [('c-n8h', range(0, 2)), ('c-n8', range(2, 7))], 33: [('c-n8c', range(0, 2))]}


def width(text, size=SIZE):
    """[text]'s width in Baskervville at [size], its italic between `__`."""
    from fontTools.ttLib import TTFont
    total = 0.0
    for k, part in enumerate(text.split('__')):
        style = 'Italic' if k % 2 else 'Regular'
        if style not in _FONTS:
            f = TTFont(os.path.expanduser(f'~/.local/share/fonts/ptome/Baskervville-{style}.ttf'))
            _FONTS[style] = (f.getBestCmap(), f['hmtx'])
        cmap, hmtx = _FONTS[style]
        # (A character Baskervville lacks, from the fallback: as wide as an M.)
        total += sum(hmtx[cmap[ord(c)]][0] if ord(c) in cmap else 750 for c in part) / 1000 * size
    return total


def fitted(text, room):
    """A name the printing set closer than its type sets it: its letters
    drawn together so that it fits its cell (`[.sqN]`, N thousandths of an
    em less after each)."""
    plain = text.rstrip('—')
    w = width(plain)
    if w <= room:
        return text
    n = len(plain.replace('__', ''))
    k = int((w - room + 3) / n / SIZE * 1000) + 3
    SQUEEZE.add(k)
    return f'[.sq{k}]##{plain}##' + text[len(plain):]


def pages():
    """calendar.spec's months: {leaf, titles, rows, notes, foot}."""
    out, page = [], None
    for raw in open(os.path.join(HERE, 'calendar.spec'), encoding='utf-8'):
        raw = raw.rstrip('\n')
        if not raw or raw.startswith('#'):
            continue
        if raw.startswith('@month'):
            page = {'leaf': int(raw.split()[1]), 'titles': [], 'rows': [], 'notes': [], 'foot': None}
            out.append(page)
        elif raw.startswith(('@title1 ', '@title2 ', '@head ', '@head2 ')):
            kind, _, text = raw[1:].partition(' ')
            page['titles'].append((kind, text))
        elif raw.startswith('@note'):
            text = raw.split(' ', 1)[1]
            if ' @ ' in text:
                text, catch = text.split(' @ ')
                page['foot'] = ('', catch)
            page['notes'].append(text)
        elif raw.startswith('@foot'):
            sig, _, catch = raw.split(' ', 1)[1].partition('|')
            page['foot'] = (sig.strip(), catch.strip())
        else:
            cells = raw.split('|')
            gold, _, day = cells[0].rpartition('/')
            page['rows'].append([gold, day] + cells[1:])
    return out


def golden(page):
    """Whether the month's days carry golden numbers (March, April)."""
    return any(r[0] for r in page['rows'])


def plain(cell):
    """A cell's text as a reader reads it: its rules gone."""
    t = re.sub(r'__', '', cell)
    t = t.replace('>', ' ')
    t = re.sub(r'^-', '', t)
    return t.replace('—', ' ').strip()


def page_has_catch_on_note(page):
    """March's catchword set on its note's last line."""
    return bool(page['notes']) and page['foot'] is not None and not page['foot'][0] and page['leaf'] == 25


def page_lines(page):
    """The page's printed lines in order, their text."""
    out = [t for _, t in page['titles']]
    out += ['Morning Evening', 'Prayer. Prayer.', '1 Less. 2 Less. 1 Less. 2 Less.']
    for r in page['rows']:
        out.append(' '.join(plain(c) for c in r if plain(c)))
    notes = list(page['notes'])
    if page_has_catch_on_note(page):
        notes[-1] += ' ' + page['foot'][1]
    out += notes
    if page['foot'] and not page_has_catch_on_note(page):
        out.append(' '.join(p for p in page['foot'] if p))
    return out


def geometry():
    return json.load(open(os.path.join(WORK, 'cal.json')))


def place(geo):
    """Where the frame's outer top left goes on the page."""
    w, h = geo['frame']
    return ((PAGE[0] - w) / 2, TOP)


def head_rules(geo):
    """The rules over the table: the month's (under its head) and the
    head's (under Morning and Evening Prayer); and its foot's."""
    rules = [r[0] for r in geo['rules']]
    head = max(r for r in rules if r < 200)
    month = max(r for r in rules if r < head - 5)
    bottom = min([r for r in rules if r > 400] or [max(c[2] for c in geo['columns'])])
    return month, head, bottom


def scan_baselines(page, geo):
    """Each of the page's lines' baselines on the scan, in points from the
    frame's top (calgeo.py's), the body's rows on the line of best fit
    through those measured (a row's g, its descender, misread); and the
    rows' pitch."""
    lines = geo['lines']
    month, head, bottom = head_rules(geo)
    n_titles = len(page['titles'])
    titles = [b for b in lines if 12 < b < month][:n_titles]
    # (Morning's line and Prayer's under it, a line apart.)
    p0 = geo['prayer'][0]
    prayer = [p0, next((b for b in geo['prayer'] if 9 < b - p0 < 15), p0 + 12.0)]
    rows = len(page['rows'])
    body = [b for b in lines if prayer and b > prayer[-1] + 20]
    steps = [b - a for a, b in zip(body, body[1:]) if 11 < b - a < 13]
    p = statistics.median(steps) if steps else 12.0
    # (The first row: the first line under the head's; then the line of
    # best fit through the rows that lie on its grid, twice.)
    first = body[0] if body else head + 30
    for tolerance in (2.5, 1.2):
        pts = []
        for c in body:
            j = round((c - first) / p)
            if 0 <= j < rows and abs(c - (first + j * p)) < tolerance:
                pts.append((j, c))
        if len(pts) >= 3:
            mx = sum(j for j, _ in pts) / len(pts)
            my = sum(c for _, c in pts) / len(pts)
            den = sum((j - mx) ** 2 for j, _ in pts)
            p = sum((j - mx) * (c - my) for j, c in pts) / den
            first = my - p * mx
    rowlines = [first + j * p for j in range(rows)]
    less = geo['less'][0] if geo['less'] else rowlines[0] - 21.0
    # (Under the table: the notes, the strongest falls of ink under the
    # table's foot, as many as there are; the foot, the catchword's.)
    n_notes = len(page['notes'])
    notes = sorted(b for b in geo['below'] if b > rowlines[-1] + 6)[:0] if not n_notes else \
        sorted([b for b in geo['below'] if b > rowlines[-1] + 6][:n_notes])
    foot = [geo['catch']] if page['foot'] and not page_has_catch_on_note(page) else []
    return titles + prayer + [less] + rowlines + notes + foot, p


def cell(text, numeric, room=999):
    """A cell's AsciiDoc: `-` a rule across, `-X` a rule and X flush right,
    `X>N` X and N flush right, a name's closing `—` a rule to the end."""
    if not text:
        return ''
    if text == '-':
        return '[.ld]##{nbsp}##'
    if text.startswith('-') and len(text) > 1:
        return f'[.ld]##{text[1:].replace(">", " ").strip()}##'
    if '>' in text:
        a, b = text.split('>', 1)
        if a.endswith('—'):
            return f'{a[:-1]}[.ld]##{b}##'
        # (A book's name and its chapter: closer where the cell is narrow.)
        room_a = room - width(b) - 5
        return f'{fitted(a, room_a)}[.right]##{b}##'
    if text.endswith('—') and not numeric:
        # (A name's closing rule: where there's room for it after the name.)
        name = text[:-1].rstrip()
        if width(name) > room - 8:
            return fitted(name, room)
        return name + '[.ld]##{nbsp}##'
    return fitted(text, room)


def adoc(page, geo, adjust, fit, n0):
    """The page's AsciiDoc and its lines' places for the fit (gen.py's
    fit.json), each block's key `top/LEAF/LINE`; and its rows' pitch."""
    leaf = page['leaf']
    xs = [round(c[0], 2) for c in geo['columns']]
    w = geo['frame'][0]
    left, right = 5.6, w - 5.6
    edges = [left] + xs + [right]
    widths = [max(round((b - a) * 100), 1) for a, b in zip(edges, edges[1:])]
    cols = ','.join(f'{c}' for c in widths)
    gold = golden(page)
    lead = 4 if gold else 3
    out = [f'// page {leaf}', f'// tag::page-{leaf}[]', f'[.cal{leaf}%notitle]', f'== Leaf {leaf}', '',
           'image::blank.svg[role=spacer,pdfwidth=1pt,pdfheight=0.01pt]', '']
    n = 0

    def block(lines, kind):
        nonlocal n
        n += 1
        first = n
        key = f'top/{leaf}/{first}'
        m = adjust.get(key)
        n += len(lines) - 1
        for k in range(first, n + 1):
            fit.append({'page': leaf, 'line': k, 'block': f'{leaf}/{first}', 'kind': kind, 'key': key})
        return key, (f',margin-top={m}pt' if m else '')

    for kind, text in page['titles']:
        key, m = block([text], 'X')
        if kind == 'head':
            # (The month's name in capitals, spaced.)
            text = re.sub(r'^([A-Z]{3,})', r'[.csp]##\1##', text)
        out += [f'[.c-{kind}{m}]', text, '']
    # (The table's head: Morning and Evening Prayer over their lessons.)
    key, m = block(['', ''], 'T')
    out += [f'[.calh,cols="{cols}",grid=none,frame=none{m}]', '|===',
            f'{lead}+| 2+^|Morning +', 'Prayer. 2+^|Evening +', 'Prayer.', '|===', '']
    key, m = block([''], 'T')
    out += [f'[.calh,cols="{cols}",grid=none,frame=none{m}]', '|===',
            f'{lead}+| ^|1 Less. ^|2 Less. ^|1 Less. ^|2 Less.', '|===', '']
    pitch = adjust.get(f'calpitch/{leaf}', 12.0)
    key, m = block(page['rows'], 'R')
    out += [f'[.calb.cp{round(pitch * 100)},cols="{cols}",grid=none,frame=none{m}]', '|===']
    for r in page['rows']:
        cells = ([r[0]] if gold else []) + r[1:]
        out.append(' '.join(f'|{cell(c, k >= lead, (edges[k + 1] - edges[k]) - 2 * PAD - 0.5)}'
                            for k, c in enumerate(cells)))
    out += ['|===', '']
    # (The notes under the table: a block of lines each, in the look's
    # role for it: January's centred in the table's type, March's and
    # November's in Brevier, March's first two lines hanging.)
    notes = list(page['notes'])
    if page_has_catch_on_note(page):
        notes[-1] = f'{notes[-1]} [.right]##{page["foot"][1]}##'
    for role, part in NOTES.get(leaf, [('c-n10c', range(len(notes)))] if notes else []):
        lines = [notes[i] for i in part]
        key, m = block(lines, 'N')
        out += [f'[.{role}{m}]'] + [('{empty}' + t if t.startswith(('(', '☞')) else t) for t in lines] + ['']
    if page['foot'] and not page_has_catch_on_note(page):
        sig, catch = page['foot']
        key, m = block([''], 'f')
        body = (f'[.w{round(adjust.get(f"sig/{leaf}", 150) * 2)}]##{{nbsp}}##{sig}' if sig else '{empty}')
        body += f' [.right]#{catch}#' if catch else ''
        out += [f'[.ft{m}]', body, '']
    out.append(f'// end::page-{leaf}[]')
    return out, pitch


def svg(page, geo):
    """The page's rules, drawn where the scan's are: an SVG the page's
    size."""
    fx, fy = place(geo)
    w, h = geo['frame']
    rects = []

    def rect(x, y, rw, rh):
        rects.append(f'<rect x="{fx + x:.2f}" y="{fy + y:.2f}" width="{rw:.2f}" height="{rh:.2f}"/>')

    # (The frame: a heavy rule outside, a fine one inside it.)
    t, i, ti = 1.6, 4.0, 0.6
    rect(0, 0, w, t), rect(0, h - t, w, t), rect(0, 0, t, h), rect(w - t, 0, t, h)
    rect(i, i, w - 2 * i, ti), rect(i, h - i - ti, w - 2 * i, ti)
    rect(i, i, ti, h - 2 * i), rect(w - i - ti, i, ti, h - 2 * i)
    for y, a, b, th in geo['rules']:
        rect(i, y - 0.3, w - 2 * i, 0.6)
    # (The rules down: from the rule under the table's head to its foot;
    # the one between Morning and Evening Prayer from the month's rule.)
    month, head, bottom = head_rules(geo)
    xs = [c[0] for c in geo['columns']]
    between = xs[-3] if len(xs) >= 5 else None
    for x in xs:
        top = month if x == between else head
        rect(x - 0.3, top, 0.6, bottom - top)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{PAGE[0]}pt" height="{PAGE[1]}pt" '
            f'viewBox="0 0 {PAGE[0]} {PAGE[1]}"><g fill="#1A1A1A">' + ''.join(rects) + '</g></svg>\n')
