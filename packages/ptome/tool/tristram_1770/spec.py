"""tristram.spec from decide.py's draft (draft.json) and what was read off
the scan (fixes.tsv, pages/): each page (`@page PAGE LEAF`) its printed
lines in order, each by its kind:

  `h ` the head (the page's number, or a running title), centred;
  `X ROLE ` a title's line in its own size (the look's role);
  `C ` a centred line (a chapter's head); `Y ` the line in its frame of
       rules (Yorick's epitaph); `R ` a line flush right (a catchword on
       a line of its own);
  `I ` a chapter's first line, its initial two lines deep;
  `P ` a paragraph's first line, set in; `N ` one not set in;
  `V+N ` a line set in N points (the dedication's subscription);
  `F ` a footnote's first line, `n ` its lines going on;
  two spaces a line going on; `@rule` the rule under the title;
  `@black` the black page; `f ` the foot (the signature ` | ` the
  catchword; the first leaf of a gathering `VOL. I. | B | catch`).

Each line's kind by where the scan sets it (its box's indent and its
ends against the page's text, draft.json's boxes); a line read by hand
its kind as written. Each spec line's box on its leaf, or None, to
where.json (scan.py's).

    python3 -I spec.py
"""
import json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from common import WORK, PX

# (The leaves the printing signs and their signatures: an octavo of
# sixteen pages a gathering, the first three rectos signed, the first with
# the volume's direction line; the gatherings' first pages as the scan
# shows them, P a half-sheet.)
GATHERINGS = {11: 'B', 27: 'C', 43: 'D', 59: 'E', 75: 'F', 91: 'G', 107: 'H', 123: 'I', 139: 'K', 155: 'L',
              171: 'M', 187: 'N', 203: 'O', 219: 'P', 227: 'Q'}
FRONT_SIGNATURES = {'dedication-1': 'A 3', '1': 'A 4'}
# (The press figures at the foot, where the signature would be.)
FIGURES = {78: '2', 195: '1', 218: '1', 225: '1'}
BLACK = (67, 68)


def signature(page):
    if page in FRONT_SIGNATURES:
        return FRONT_SIGNATURES[page]
    if not page.isdigit():
        return None
    n = int(page)
    if n in FIGURES:
        return FIGURES[n]
    starts = [s for s in GATHERINGS if s <= n]
    if not starts:
        return None
    s = max(starts)
    k = n - s
    if k % 2 or k > 4:
        return None
    letter = GATHERINGS[s]
    return f'VOL. I. | {letter}' if k == 0 else f'{letter} {k // 2 + 1}'


def fixes():
    out = {}
    for row in open(os.path.join(HERE, 'fixes.tsv'), encoding='utf-8'):
        row = row.rstrip('\n')
        if row and not row.startswith('#'):
            k, t = row.split('\t', 1)
            out[k] = t
    return out




def ink_ends(ink, box):
    """A line's ink's ends on the scan, in its box's middle rows (the
    OCR's box may begin after a quote or end before a stop): the first
    and last columns with ink, a speck's aside."""
    import numpy as np
    x0, y0, x1, y1 = box
    h = y1 - y0
    band = ink[y0 + h // 4:y1 - h // 6, max(0, x0 - 90):min(ink.shape[1], x1 + 60)]
    cols = np.nonzero(band.sum(axis=0) >= 2)[0]
    if not len(cols):
        return x0, x1
    # (Runs of columns with ink, a gap of a word space breaking them;
    # the runs of a few columns far from the rest specks.)
    runs, start = [], cols[0]
    for a, b in zip(cols, cols[1:]):
        if b - a > 30:
            runs.append((start, a))
            start = b
    runs.append((start, cols[-1]))
    runs = [r for r in runs if r[1] - r[0] >= 6 or (x0 - 90 + r[0] >= x0 - 40)]
    off = max(0, x0 - 90)
    return off + runs[0][0], off + runs[-1][1]




def local_edge(points, sign):
    """The text's edge about each line: among the eleven lines nearest
    it, the third furthest out ([sign] +1 the left edge, -1 the right),
    the leaf curling or lying aslant, a line or two set out aside."""
    pts = sorted(points)

    def at(y):
        near = sorted(pts, key=lambda p: abs(p[0] - y))[:11]
        xs = sorted((p[1] for p in near), reverse=sign < 0)
        return xs[min(2, len(xs) - 1)]
    return at


def kinds(rows, ink=None):
    """Each body row's kind (rows: (draft line, its text as read)) from
    its ink's ends on the scan ([ink], the leaf's; else the OCR's box):
    set in, set in further (`V+N`), centred, flush right, a chapter's
    initial, a footnote's, going on."""
    real = [l for l, t in rows if l['box'][2] > l['box'][0] and l['kind'] not in ('head', 'foot')]
    if len(real) < 4:
        return [' '] * len(rows)
    ends = {id(l): (ink_ends(ink, l['box']) if ink is not None else (l['box'][0], l['box'][2])) for l in real}
    # (The text's edges: lines through where its lines start and end,
    # the leaf lying aslant or curling; the lines set in, short or
    # centred aside.)
    mid = {id(l): (l['box'][1] + l['box'][3]) / 2 for l in real}
    left_at = local_edge([(mid[k], e[0]) for k, e in ends.items()], +1)
    right_at = local_edge([(mid[k], e[1]) for k, e in ends.items()], -1)
    out, prev, seen = [], None, set()
    for l, t in rows:
        if id(l) in seen or l['box'][2] <= l['box'][0]:
            # (The second of two lines a fix made of one: going on.)
            out.append('C' if t.startswith('CHAP.') else ' ')
            continue
        seen.add(id(l))
        m = re.match(r'^(V\+\d+|[PNCIRFn ])\|', t)
        if m:
            out.append(m.group(1))
            prev = (t[m.end():], 0, m.group(1), 0)
            continue
        a, b = ends[id(l)]
        ind, rr = a - left_at(mid[id(l)]), right_at(mid[id(l)]) - b
        # (A paragraph ended above it: the line before short, or a head;
        # a page's first line goes on unless set in.)
        ended = prev is not None and (prev[1] > 40 or prev[0].startswith('CHAP.'))
        if t.startswith('CHAP.'):
            k = 'C'
        elif prev and prev[0].startswith('CHAP.') and t[:1].isalpha():
            k = 'I'
        elif prev and prev[2] == 'I':
            # (The initial's second line, beside it.)
            k = ' '
        elif t.startswith(('* ', '† ')) and ind < 80:
            k = 'F'
        elif prev and (prev[2] in ('F', 'n') or prev[2] == 'R' and len(prev[0].split()) == 1):
            # (A footnote's lines going on: after its first, or after the
            # text's catchword on a page the footnote runs on to.)
            k = 'n'
        elif ind > 350 and rr < 20:
            k = 'R'
        elif ind > 50 and abs(ind - rr) < 45 and rr > 50:
            k = 'C'
        elif ind > 80 and (ended or rr > 40 and (prev is None or prev[3] < 40)):
            # (A line set in further, a paragraph's first or a short one;
            # a full line going on set in only by the leaf's curl.)
            k = f'V+{round(ind / PX)}'
        elif 22 <= ind <= 80 and (ended or not t.startswith('“')):
            k = 'P'
        elif ended and ind < 22:
            k = 'N'
        else:
            k = ' '
        out.append(k)
        prev = (t, rr, k, ind)
    return out


def catchword(line):
    """A page's catchword from the next page's first line (a spec line):
    its first word (its running quote with it; a word of one letter with
    the word after it), up to a dash, in italic or small capitals where
    the word is."""
    text = line[2:] if line[:2] in ('  ', 'P ', 'N ', 'C ', 'I ') else line.split(' ', 1)[-1]
    words = text.split()
    k = 2 if words and words[0] == '“' else 1
    if len(words) > k and len(re.sub(r'[^A-Za-z]', '', words[k - 1])) == 1 and words[k - 1][0].isalpha():
        k += 1
    span = ' '.join(words[:k])
    plain = re.sub(r'\[\.\w+\]#+|#+|__', '', span).replace('{shy}', '-').replace('{zwsp}', '')
    plain = re.split(r'[—⸺⸻]', plain)[0] or plain
    # (Its marks: those open where its word ends.)
    end = text.find(span) + len(span)
    before = text[:end]
    last = words[k - 1]
    if before.count('__') % 2 or last.startswith('__') or before.endswith('__'):
        plain = f'__{plain}__' if not plain.startswith('“') else '“ __' + plain[2:] + '__'
    elif re.search(r'\[\.sc\]#+[^#]*$', before) or re.search(r'\[\.sc\]#+[^#]+#+$', before):
        plain = f'[.sc]#{plain}#'
    return plain


# (The catchwords the printing sets otherwise than the next page's first
# word: a footnote's catchword, the half of a word, a misprint, a page
# with no page after it in the scan.)
CATCH = {'25': '“ will', '42': 'I', '61': 'A', '66': 'CHAP.', '134': 'I', '115': 'treamly', '121': 'in', '210': '“ some-', '219': 'him-', '227': 'on'}


def main():
    draft = json.load(open(os.path.join(WORK, 'draft.json')))
    leaves = json.load(open(os.path.join(WORK, 'leaves.json')))
    fx = fixes()
    pages = []  # [(page, leaf, [(spec line, box)], foot or None)]
    for leaf, page in leaves:
        page = str(page)
        out = []
        foot = None
        hand = os.path.join(HERE, 'pages', f'{page}.txt')
        if page in ('frontispiece', 'title'):
            if page == 'title':
                out += [(row_line(r), None) for r in open(hand, encoding='utf-8').read().splitlines()]
            else:
                out.append(('@frontispiece', None))
            pages.append((page, leaf, out, None))
            continue
        if page.isdigit() and int(page) in BLACK:
            pages.append((page, leaf, [(f'h ( {page} )', None), ('@black', None)], None))
            continue
        lines = draft[page]['lines']
        if os.path.exists(hand):
            # (A page read by hand: its kinds as written, its head and
            # rule where they stand.)
            raw = open(hand, encoding='utf-8').read().splitlines()
            if page.isdigit() and page != '1':
                out.append((f'h ( {page} )', None))
            for r in raw:
                if r.startswith('@foot '):
                    foot = (r[6:], None)
                else:
                    out.append((row_line(r, page), None))
            pages.append((page, leaf, out, foot))
            continue
        # (The lines as read: fixes.tsv's by their places in the draft.)
        rows = []
        for i, l in enumerate(lines):
            new = fx.get(f'{page}:{i}')
            for part in ([l['text']] if new is None else new.split(' // ') if new else []):
                rows.append((l, part))
        head = next((l for l in lines if l['kind'] == 'head'), None)
        if page.isdigit():
            out.append((f'h ( {page} )', head['box'] if head else None))
        body = []
        for l, t in rows:
            if l['kind'] == 'head':
                continue
            if t.startswith('@foot ') or l['kind'] == 'foot':
                foot = (t.removeprefix('@foot '), l['box'])
                continue
            body.append((l, t))
        import numpy as np
        from PIL import Image
        ink = np.asarray(Image.open(os.path.join(WORK, 'png', f'{leaf:04d}.png')).convert('L')) < 120
        ks = kinds([(l, t) for l, t in body], ink)
        if body and ks[-1] == 'R' and (foot is None or not catch_key(foot[0]) or len(body[-1][1].split()) == 1):
            # (The page's last line flush right: its catchword, the foot
            # not read.)
            l, t = body.pop()
            ks.pop()
            foot = (t, l['box'])
        boxed = set()
        for (l, t), k in zip(body, ks):
            t = t.strip()
            # (A line a fix made of two: the box the first's.)
            box = l['box'] if l['box'][2] > l['box'][0] and id(l) not in boxed else None
            boxed.add(id(l))
            m = re.match(r'^(V\+\d+|[PNCIRFn ])\|(.*)$', t)
            if m:
                # (A line read off the scan its kind as written.)
                k, t = m.group(1), m.group(2)
            if t.startswith('@catch '):
                out.append(('R ' + t[7:], box))
            elif t.startswith('@note '):
                b = t[6:]
                out.append((('F ' if b.startswith(('*', '†')) else 'n ') + b, box))
            elif t.startswith('@yorick '):
                out.append(('Y ' + t[8:], box))
            else:
                if t.startswith('CHAP.'):
                    # (A chapter's head: its number in capitals, a full
                    # stop after it.)
                    t = 'CHAP. ' + re.sub(r'[^IVXLivxl]', '', t[5:]).upper() + '.'
                out.append((f'{k} {t}' if k != ' ' else f'  {t}', box))
        pages.append((page, leaf, out, foot))
    spec, where, odd = [], [], []
    for n, (page, leaf, out, foot) in enumerate(pages):
        spec.append(f'@page {page} {leaf}')
        where.append(None)
        for line, box in out:
            spec.append(line)
            where.append(box)
        # (The foot: its signature by the gatherings, its catchword the
        # next page's first word, as the printing's are.)
        sig = signature(page)
        if foot is None and not sig and (page in NO_CATCH or not nxt_text(pages, n)
                                         or any(ln.startswith('R ') for ln, b in out)):
            # (No foot: none printed, or the text's catchword above a
            # footnote the page ends with.)
            continue
        nxt = next((ln for ln, b in pages[n + 1][2] if not ln.startswith(('h ', '@'))), '') if n + 1 < len(pages) else ''
        catch = catchword(nxt) if nxt and page not in NO_CATCH else ''
        if page in CATCH:
            catch = CATCH[page]
        elif foot and '|' in foot[0]:
            catch = foot[0].split('|')[-1].strip()
        elif foot and len(catch_key(foot[0])) and catch_key(catch) != catch_key(foot[0].split()[-1] if foot[0].split() else ''):
            odd.append(f'{page}: the scan\'s {foot[0]!r}, the next page\'s {catch!r}')
        spec.append('f ' + ' | '.join(x for x in (sig, catch) if x))
        where.append(foot[1] if foot else None)
    open(os.path.join(HERE, 'tristram.spec'), 'w', encoding='utf-8').write('\n'.join(spec) + '\n')
    json.dump(where, open(os.path.join(WORK, 'where.json'), 'w'))
    for o in odd:
        print('catchword:', o)
    print(sum(1 for s in spec if s.startswith('@page')), 'pages,', len(spec), 'spec lines')


# (The pages the printing sets no catchword on: the dedication's last,
# the title, the frontispiece.)
NO_CATCH = ('frontispiece', 'title', 'dedication-2') + tuple(str(p) for p in BLACK)


def nxt_text(pages, n):
    return n + 1 < len(pages) and any(not ln.startswith(('h ', '@')) for ln, b in pages[n + 1][2])


def catch_key(t):
    return re.sub(r'[^a-z]', '', t.lower().replace('f', 's'))


def row_line(row, page=None):
    """A hand-read row as a spec line: `K|text` its kind, `X ROLE|text` a
    title's line, `V+N|text`, `@foot SIG | catch`, `@rule`, `h|text`."""
    if row.startswith('@foot '):
        body = row[6:]
        sig = signature(page) if page else None
        if sig and '|' not in body:
            return f'f {sig} | {body}'
        return 'f ' + body
    if row.startswith('@'):
        return row
    m = re.match(r'^([^|\s]+(?: \S+)?)\|(.*)$', row)
    if not m:
        return '  ' + row
    return f'{m.group(1)} {m.group(2)}'


if __name__ == '__main__':
    main()
