"""The titles of the poems (leaves 200-202) as the printing sets them:
two columns of italic titles, each's pages flush right, a letter over
each letter's titles, its first two set beside a capital two lines
high; each block's first line fitted to the scan's (its OCR line in its
column, else the lines' pitch on from the block before).

    python3 -I index.py -> manual/leaf200.adoc, leaf201.adoc, leaf202.adoc
"""
import difflib, json, os, re, sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from words import lines_of, norm

HERE = os.path.dirname(os.path.abspath(__file__))
PITCH_PX = 130.5

# Each page: its columns, each a list of groups: (letter or None, drop
# lines, other lines); a line (title, pages), pages None for a line
# with no number; a title in `roman` set upright.
PAGES = {
    200: [
        [('A', [('AAron', '168'), ('Affliction', '38. 53.')],
          [('  64. 82, 89.', None), ('The Agonie', '29'), ('The Altar', '18'),
           ('Anagram of the Virgin', None), ('  Marie', '69'), ('To all Angels and Saints', None),
           ('  ibid.', None), ('The Answer', '163'), ('A Dialogue-Antheme', None), ('  164', None),
           ('Antiphon', '45. 85'), ('Artillerie', '132'), ('Assurance', '149'), ('Avarice', '69')]),
         ('B', [('THe Bag', '145'), ('The Banquet', '175')],
          [('H. Baptisme', '36'), ('Bitter-sweet', '165'), ('The British Church', '102'),
           ('The Bunch of Grapes', '120'), ('Businesse', '105')])],
        [('C', [('THe Call', '150'), ('Charms and knots', '88')],
          [('Christmas', '72'), ('Church-floore', '58'), ('Church-lock and key', '57'),
           ('Church Militant', '184'), ('Church-monuments', '56'), ('Church-musick', '57'),
           ('Church-porch', '1'), ('Church-rents & schismes', None), ('  134', None),
           ('Church-windows', '59'), ('Clasping of hands', '151'), ('The Collar', '147'),
           ('Coloss. 3. 3. Our life, &c.', None), ('  77', None), ('H. Communion', '43'),
           ('Complaining', '137'), ('Self-condemnation', '165'), ('Confession', '118'),
           ('Conscience', '98'), ('Constancie', '63'), ('Content', '60'), ('The Crosse', '158')])],
    ],
    201: [
        [('D', [('THe Dawning', '104'), ('Death', '180')],
          [('Decay', '91'), ('Deniall', '71'), ('Dialogue', '107'), ('The Discharge', '138'),
           ('Discipline', '173'), ('Divinitie', '127'), ('Dooms-day', '181'), ('Dotage', '161'),
           ('Dulnesse', '108')]),
         ('E', [('EAster', '33'), ('Easter-wings', '34, 35')],
          [('The Elixer', '178'), ('Employment', '49. 70'), ("L'Envoy", '192'),
           ('Ephes. 4. 30. Grieve not,', None), ('  &c.', '128'), ('Evensong', '55')]),
         ('F', [('FAith', '41'), ('The Familie', '130')],
          [('The Flower', '160'), ('The Foil', '170'), ('The Forerunners', 'ibid.'), ('Frailtie', '62')]),
         ('G', [('GIddinesse', '119'), ('The Glance', '166')],
          [('The Glimpse', '148'), ('Good Friday', '30'), ('Grace', '52'), ('Gratefulnesse', '116'),
           ('Grief', '158')])],
        [('H', [('HEaven', '182'), ('The Holdfast', '137')],
          [('Home', '99'), ('Hope', '114'), ('Humilitie', '61'), ('A true Hymne', '162')]),
         ('I', [('JEsu', '105'), ('The Jews', '146')],
          [('The Invitation', '174'), ('Jordan', '48. 95'), ('Josephs coat', '153'),
           ('Judgement', '182'), ('Justice', '88. 135')]),
         ('L', [('LEnt', '78'), ('Life', '87')],
          [('Longing', '142'), ('Love', '45, 46. 183'), ('Love-joy', '109'), ('Love unknown', '121')]),
         ('M', [('MAn', '83'), ('Mans medley', '123')],
          [('S. Marie Magdalene', '168'), ('Mattens', '54'), ('The Method', '126'), ('Miserie', '92'),
           ('Mortification', '90')]),
         (None, [], [('Nature', '37')]),
         ('O', [('OBedience', '96'), ('The Odour', '169')], [('An Offering', '141')])],
    ],
    202: [
        [('P', [('PAradise', '125'), ('A Parodie', '177')],
          [('Peace', '117'), ('The Pearl, Matth. 13.', '81'), ('roman:Perirrhanterium', '1'),
           ('The Pilgrimage', '135'), ('The Posie', '177'), ('Praise', '53. 140. 151'),
           ('Prayer', '43. 95'), ('The Priesthood', '154'), ('Providence', '109'),
           ('The 23 Psalme', '167'), ('The Pulley', '153')]),
         ('Q', [('THe Quidditie', '61'), ('The Quip', '103')], []),
         ('R', [('REdemption', '31'), ('Repentance', '40')],
          [('The Reprisall', '28'), ('The Rose', '172')]),
         ('S', [('THe Sacrifice', '19'), ('Saints, vide Angels', None)],
          [('Schismes, vide Church-', None), ('  rents', None), ('H. Scripture', '50'), ('The Search', '156')])],
        [(None, [], [('Sepulchre', '32'), ('Sighs and grones', '75'), ('Sinne', '37. 55'),
                     ('Sinnes round', '114'), ('The Sinner', '30'), ('Sion', '99'), ('The Size', '131'),
                     ('The Sonne', '162'), ('The Starre', '65'), ('The Storm', '125'), ('Submission', '87'),
                     ('Sunday', '66'), ('roman:Superliminare', '17')]),
         ('T', [('THe Temper', '46, 47'), ('The Thanksgiving', None)],
          [('  27', None), ('Time', '115'), ('Trinitie-Sunday', '59')]),
         ('V', [('VAnitie', '77. 104'), ('Vertue', '18')],
          [('Ungratefulnesse', '74'), ('Unkindnesse', '86')]),
         ('W', [('THe Water-course', '164'), ('Whitsunday', '51')],
          [('The World', '76'), ('A Wreath', '179')])],
    ],
}
# (Each column's left and right on the scan, in pixels, by leaf.)
COLUMNS = {200: [(250, 1540), (1590, 2930)], 201: [(500, 1850), (1900, 3200)], 202: [(240, 1560), (1590, 2900)]}


def esc(t):
    return t


def line(title, pages):
    # (The titles italic, the role's; a title the printing sets upright,
    # its turned figures, upright.)
    if title.startswith('roman:'):
        t = f'[.rm]#{title[6:]}#'
    else:
        ind = len(title) - len(title.lstrip(' '))
        t = title.strip()
        if re.fullmatch(r'[\d. ,]+|ibid\.', t):
            t = f'[.rm]#{t}#'
        t = ('[.i80]##{nbsp}##' if ind else '') + esc(t).replace(' vide ', ' [.rm]#vide# ')
    # (A line opening `S.`, `H.`: not a list's item.)
    if re.match(r'^[A-Z]\. ', t):
        t = '{empty}' + t
    return t + (f' [.ixn]#{pages}#' if pages else '')


def find_base(leaf, col, title, after):
    """The scan's baseline (pixels) for the line [title] in column [col]
    below [after]: its OCR line, where the OCR reads it."""
    x0, x1 = COLUMNS[leaf][col]
    want = norm(title.replace('roman:', ''))[:12]
    best = None
    for l in lines_of(leaf):
        ws = [w for w in l['w'] if x0 - 40 <= w['box'][0] <= x1]
        if not ws:
            continue
        # (Its baseline: its words' feet, a drop's letter, taller, aside.)
        hs = sorted(w['box'][3] - w['box'][1] for w in ws)
        h = hs[len(hs) // 2]
        base = max([w['box'][3] for w in ws if w['box'][3] - w['box'][1] <= 1.5 * h] or [ws[0]['box'][3]])
        if base <= after + 40:
            continue
        have = norm(''.join(w['t'] for w in ws))
        r = difflib.SequenceMatcher(None, want, have[:len(want) + 4]).ratio()
        # (The likeliest: like it, and near where the lines' pitch puts it.)
        score = r - abs(base - (after + PITCH_PX)) / (4 * PITCH_PX)
        if len(want) >= 4 and r > 0.6 and (best is None or score > best[0]):
            best = (score, base)
    return best[1] if best else None


def ocr_bases(leaf, col):
    """The column's OCR lines: (baseline, letters), in its x-range."""
    x0, x1 = COLUMNS[leaf][col]
    out = []
    for l in lines_of(leaf):
        ws = [w for w in l['w'] if x0 - 40 <= w['box'][0] <= x1 - 60]
        if not ws:
            continue
        hs = sorted(w['box'][3] - w['box'][1] for w in ws)
        h = hs[len(hs) // 2]
        base = max([w['box'][3] for w in ws if w['box'][3] - w['box'][1] <= 1.5 * h] or [ws[0]['box'][3]])
        out.append((base, norm(''.join(w['t'] for w in ws))))
    return out


def page(leaf, starts):
    """The blocks of [leaf]'s columns, by their place down the page, each
    its role, its lines and its first line's baseline (pixels): the
    column's lines on a grid, its pitch and start fitted to the lines the
    OCR reads well (the scan's lines stand a pitch apart, but the film's
    skew)."""
    blocks = []
    for col, groups in enumerate(PAGES[leaf]):
        rows = []   # (kind, text)
        for letter, drop, rest in groups:
            if letter:
                rows.append(('letter', letter))
            for t, _ in drop:
                rows.append(('drop', t))
            for t, _ in rest:
                rows.append(('rest', t))
        ocr = ocr_bases(leaf, col)
        anchors = []
        for k, (kind, t) in enumerate(rows):
            want = norm(t.replace('roman:', ''))
            if kind == 'drop' and rows[k - 1][0] != 'drop':
                want = want[1:]
            if len(want) < 5:
                continue
            for base, have in ocr:
                if difflib.SequenceMatcher(None, want, have[:len(want) + 3]).ratio() > 0.8:
                    anchors.append((k, base))
                    break
        # (A line through them, the outliers, a line matched to another
        # of its words, left out.)
        a = np.array(anchors, dtype=float)
        for _ in range(3):
            b, c = np.polyfit(a[:, 0], a[:, 1], 1)
            res = np.abs(a[:, 1] - (b * a[:, 0] + c))
            a = a[res < max(60, 3 * np.median(res))]
        b, c = np.polyfit(a[:, 0], a[:, 1], 1)
        # (Between two anchors, the lines evenly between them: a gap the
        # printing leaves, before Nature, kept; past them, the pitch.)
        kept = sorted({int(k): float(y) for k, y in a}.items())
        def at(k):
            before = [(kk, y) for kk, y in kept if kk <= k]
            after = [(kk, y) for kk, y in kept if kk >= k]
            if before and after:
                (k0, y0), (k1, y1) = before[-1], after[0]
                return y0 if k1 == k0 else y0 + (y1 - y0) * (k - k0) / (k1 - k0)
            if before:
                return before[-1][1] + b * (k - before[-1][0])
            return after[0][1] - b * (after[0][0] - k)
        grid = [at(k) for k in range(len(rows))]
        k = 0
        role = f'ix.ix-{"l" if col == 0 else "r"}'
        for letter, drop, rest in groups:
            if letter:
                blocks.append((grid[k], f'{role}.ix-letter', [letter], 'letter', letter)); k += 1
            if drop:
                body = [line(t, p) for t, p in drop]
                blocks.append((grid[k], f'{role}.ix-drop', body, 'text', drop[0][0][1:])); k += len(drop)
            if rest:
                blocks.append((grid[k], role, [line(t, p) for t, p in rest], 'text',
                               rest[0][0].strip().replace('roman:', ''))); k += len(rest)
    return sorted(blocks, key=lambda b: b[0])


RULES = json.load(open(f'{HERE}/index_rules.json'))


def write(leaf, head, starts):
    out = head[:]
    # (The column rule, in its pieces, each where the scan's is, among
    # the blocks by their places down the page.)
    blocks = page(leaf, starts) + [(r['top'], 'rule-v', [f'image::{r["name"]}[pdfheight={r["height"]}pt]'], 'image', '')
                                   for r in RULES[str(leaf)]]
    for y, role, body, kind, first in sorted(blocks, key=lambda b: b[0]):
        if kind == 'image':
            out += [f'[.{role},top={int(y)}]'] + body + ['']
            continue
        first = re.sub(r'\s+', ' ', first)
        out.append(f'[.{role},base={int(y)},first="{first}",' + ('letter' if kind == 'letter' else 'column') + ']')
        out.extend(body)
        out.append('')
    open(f'{HERE}/manual/leaf{leaf}.adoc', 'w').write('\n'.join(out))


write(200, ['// The titles of the poems, their first page: a band of ornament, the',
            '// title in spaced capitals, the titles in two columns.',
            'ifdef::backend-pdf[]',
            '[.band,top=912]', 'image::temple-band-titles.png[pdfwidth=174.3pt]', '',
            '[.tp-the,base=1500,first="THE"]', 'THE', '',
            '[.ix-title,base=1688,first="TITLES OF THE SEVE-"]', 'TITLES OF THE SEVE-', '',
            '[.ix-title,base=1887,first="RALL POEMS CONTAIN-"]', 'RALL POEMS CONTAIN-', '',
            '[.ix-title,base=2058,first="ED IN THIS BOOK."]', 'ED IN THIS BOOK.', ''],
      [2263, 2263])
write(201, ['// The titles of the poems, their second page.', 'ifdef::backend-pdf[]'], [805, 830])
write(202, ['// The titles of the poems, their last page; FINIS.', 'ifdef::backend-pdf[]'], [834, 838])
for leaf in (200, 201, 202):
    s = open(f'{HERE}/manual/leaf{leaf}.adoc').read().rstrip('\n')
    if leaf == 202:
        s += '\n\n[.finis,base=5117,first="FINIS."]\nFINIS.\n'
    open(f'{HERE}/manual/leaf{leaf}.adoc', 'w').write(s + '\nendif::[]\n')
print('ok')
