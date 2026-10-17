"""Looking-Glass's front matter as the 1872 printing sets it, page for
page: the Dramatis Personae, the chess problem and its moves, the
frontispiece, the title page and its blank verso, the prefatory poem on
three pages, the printer's device, the contents and their blank verso.
Each printed line (each part of a line the printing sets apart: a column,
a page number) a paragraph of its own, of its own size, style and
measure, where the scan has it: its `margin-top` fitted against the PDF
(built, measured, corrected) until each line's top is within a fifth of
a point of the scan's. Writes text/looking-glass/front.adoc and the
look's `lgf-*` roles (between its `# lgf-begin` and `# lgf-end` lines).

    python3 -I front_lg.py
"""
import json, os, re, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from front import advance, lines_of

REPO = os.path.dirname(os.path.dirname(HERE))
WORK = os.path.join(REPO, 'test', 'showcase', 'alice')
ROOT = os.environ.get('ALICE_WORK', os.path.expanduser('~/.cache/asciidart-work/alice-match'))
OUT = f'{WORK}/text/looking-glass/front.adoc'
LOOK = f'{WORK}/alice-look.yml'

PAGE_TOP = 48.8          # the text area's top
LEFT, RIGHT = 18.6, 268.7
CENTRE = (LEFT + RIGHT) / 2
CAP = 0.712              # Old Standard's capitals' height, in ems
BODY_DX = -6.2           # a text page's scan x less the PDF's


def plain(text):
    return re.sub(r'__|\[\.[\w-]+\]#|#|\{nbsp\}', '', text)


def width(text, size, style='Regular', sc=False):
    return advance(plain(text), style, size, sc)


class Line:
    """A printed line (or a part of one): its text, where its letters'
    tops are down the page (scan points), its left and right (scan
    points, or None to centre it), its size, style and alignment."""

    def __init__(self, text, top, x0=None, x1=None, size=10.0, style='n', align='l',
                 sc=False, track=0.0, dots=None, needle=None):
        self.text, self.top, self.x0, self.x1 = text, top, x0, x1
        self.size, self.style, self.align, self.sc = size, style, align, sc
        self.track, self.dots = track, dots
        self.needle = needle or re.sub(r'[^\w’\'.]', '', plain(text).split()[0]) if plain(text).split() else None


class Picture:
    """An image on the page, its top (scan points) and its width."""

    def __init__(self, name, top, width, height, alt=''):
        self.name, self.top, self.width, self.height, self.alt = name, top, width, height, alt


def face_of(line):
    return 'Italic' if line.style == 'i' else 'Regular'


def fill_dots(line):
    """[line]'s text with as many spaced stops after it as fill its
    measure (its `dots`: the text before them), one fewer for room."""
    room = (line.x1 - line.x0) - width(line.text, line.size, face_of(line), line.sc)
    unit = advance(' .', 'Regular', line.size)
    n = max(1, int(room / unit) - 1)
    return line.text + ' .' * n


# The pages, each a list of its lines and pictures, in order down the page,
# with its scan x offset (its x less the PDF's) and its parity.
P = 72 / 650


def half_title():
    # (Its scan wider: its title's middle the page's.)
    dx = CENTRE - (31.9 + 274.7) / 2
    size = round(86 * P / CAP, 2)
    t = 'THROUGH THE LOOKING-GLASS,'
    size = min(size, round((274.7 - 31.9) / width(t, 10) * 10, 2))
    track = max(0.0, round(((274.7 - 31.9) - width(t, size)) / (len(t) - 1), 2))
    s2 = round(56 * P / CAP, 2)
    t2 = '__AND WHAT ALICE FOUND THERE.__'
    track2 = max(0.0, round(((238.4 - 64.6) - width(t2, s2, 'Italic')) / (len(plain(t2)) - 1), 2))
    return dict(pages=[[Line(t, 217.1, 31.9, 274.7, size=size, align='c', track=track),
                        Line(t2, 247.9, 64.6, 238.4, size=s2, style='i', align='c', track=track2,
                             needle='AND')]], dx=dx, leaf=5)


def dramatis():
    dx = BODY_DX
    out = [Line('DRAMATIS PERSONÆ.', 123.0, 99.6, 207.0, size=10.3, align='c'),
           Line('__(As arranged before commencement of game.)__', 148.7, 74.9, 230.6,
                size=8.0, style='i', align='c', needle='(As'),
           Picture('dramatis-rules.svg', 177.9, 250.1, 163.5),
           Line('[.sc]#White.#', 200.2, 72.2, 97.7, size=9.0, align='c', needle='White.'),
           Line('[.sc]#Red.#', 200.4, 211.9, 227.2, size=9.0, align='c', needle='Red.'),
           Line('PIECES.', 225.3, 26.6, 49.0, size=4.6, align='l'),
           Line('PAWNS.', 225.3, 116.1, 139.7, size=4.6, align='l'),
           Line('PAWNS.', 225.5, 161.1, 185.5, size=4.6, align='l'),
           Line('PIECES.', 225.5, 241.3, 264.6, size=4.6, align='l')]
    rows = [('Tweedledee', 'Daisy.', 'Daisy', 'Humpty Dumpty.'),
            ('Unicorn', 'Haigha.', 'Messenger', 'Carpenter.'),
            ('Sheep', 'Oyster.', 'Oyster', 'Walrus.'),
            ('W. Queen', '“Lily.”', 'Tiger-lily', 'R. Queen.'),
            ('W. King', 'Fawn.', 'Rose', 'R. King.'),
            ('Aged man', 'Oyster.', 'Oyster', 'Crow.'),
            ('W. Knight', 'Hatta.', 'Frog', 'R. Knight.'),
            ('Tweedledum', 'Daisy.', 'Daisy', 'Lion.')]
    tops = [234.4, 248.0, 262.1, 276.1, 290.0, 303.8, 317.7, 331.4]
    for (a, b, c, d), top in zip(rows, tops):
        out += [Line(a, top, 18.5, 113.0, size=8.6, align='j', dots=True),
                Line(b, top, 115.6, 145.0, size=8.6, align='l'),
                Line(c, top, 161.3, 213.0, size=8.6, align='j', dots=True),
                Line(d, top, 216.0, 285.0, size=8.6, align='l')]
    return dict(pages=[out], dx=dx, leaf=6)


def moves():
    # (Its scan shifted: its content's middle the page's.)
    dx = CENTRE - (9.9 + 260.9) / 2
    grid = 284.2
    pitch = 8.43
    out = [Picture('looking-glass-illustration-1.svg', 75.5, 117.9, 143.4,
                   'A chess problem. Red has pieces as follows: Ng8, Ke4, Qe2. White has pieces as '
                   'follows: Kc6, Nf5, Pd2, Qc1, Rf1.'),
           Line('__White Pawn__ (__Alice__) __to play, and win in eleven moves.__', 245.5, 33.1, 238.5,
                size=8.0, style='i', align='c', needle='White'),
           Line('PAGE', 279.1, 115.4, 129.3, size=4.0, align='r'),
           Line('PAGE', 279.4, 247.5, 261.5, size=4.0, align='r')]
    L0, L1, LP, R0, R1, RP = 9.9, 113.0, 129.2, 140.6, 244.0, 260.6
    left = [('1. Alice meets R. Q.', '35', 0), ('2. Alice through Q.’s 3d (__by__', None, 0),
            ('__railway__)', '48', 2), ('to Q.’s 4th (__Tweedledum__', None, 1),
            ('__and Tweedledee__)', '54', 2), ('3. Alice meets W. Q. (__with__', None, 0),
            ('__shawl__)', '91', 1), ('4. Alice to Q.’s 5th (__shop,__', None, 0),
            ('__river, shop__)', '101', 1), ('5. Alice to Q.’s 6th (__Humpty__', None, 0),
            ('__Dumpty__)', '112', 1), ('6. Alice to Q.’s 7th (__forest__)', '155', 0),
            ('7. W. Kt. takes R. Kt.', '161', 0), ('8. Alice to Q.’s 8th (__coro-__', None, 0),
            ('__nation__)', '183', 1), ('9. Alice becomes Queen', '196', 0),
            ('10. Alice castles (__feast__)', '204', 0), ('11. Alice takes R.Q. & wins', '215', 0)]
    right = {0: ('1. R.Q. to K.R.’s 4th', '45', 0), 2: ('2. W. Q. to Q. B.’s 4th (__after__', None, 0),
             3: ('__shawl__)', '91', 1), 5: ('3. W. Q. to Q. B.’s 5th (__be-__', None, 0),
             6: ('__comes sheep__)', '100', 1), 7: ('4. W. Q. to K. B.’s 8th', None, 0),
             8: ('(__leaves egg on shelf__)', '111', 1), 9: ('5. W. Q. to Q. B.’s 8th (__fly-__', None, 0),
             10: ('__ing from R. Kt.__)', '149', 1), 11: ('6. R. Kt. to K.’s 2nd (__ch.__)', '158', 0),
             12: ('7. W. Kt. to K. B.’s 5th', '182', 0), 13: ('8. R. Q. to K.’s sq. (__exami-__', None, 0),
             14: ('__nation__)', '186', 1), 15: ('9. Queens castle', '199', 0),
             16: ('10. W.Q. to Q.R.’s 6th (__soup__)', '211', 0)}
    # (A line's indent: 0, its number's; 1, a turned line's 16 pt;
    # 2, 28 pt.)
    indents = {0: 3.6, 1: 20.3, 2: 28.6}
    for i in range(18):
        top = grid + i * pitch
        for (text, page, ind), x0, x1, xp in ((left[i], L0, L1, LP),) + (
                ((right[i], R0, R1, RP),) if i in right else ()):
            if ind:
                a = x0 + indents[ind]
            else:
                # (A move's number: two figures flush with the column's edge,
                # one a figure's width in.)
                a = x0 + (0 if text.split()[0] in ('10.', '11.') else 4.2)
            if page:
                out.append(Line(text, top, a, x1, size=7.4, align='j', dots=True))
                out.append(Line(page, top, xp - 13, xp, size=7.4, align='r'))
            else:
                out.append(Line(text, top, a, x1 + 13, size=7.4, align='l'))
    return dict(pages=[out], dx=dx, leaf=7)


def poem():
    stanzas = [
        (13, 158.7, 70.8, ['[.sc]#Child# of the pure unclouded brow', '  And dreaming eyes of wonder!',
                           'Though time be fleet, and I and thou', '  Are half a life asunder,',
                           'Thy loving smile will surely hail', 'The love-gift of a fairy-tale.']),
        (13, 281.9, 70.8, ['I have not seen thy sunny face,', '  Nor heard thy silver laughter;',
                           'No thought of me shall find a place', '  In thy young life’s hereafter⁠—',
                           'Enough that now thou wilt not fail', 'To listen to my fairy-tale.']),
        (14, 34.9, 64.5, ['A tale begun in other days,', '  When summer suns were glowing⁠—',
                          'A simple chime, that served to time', '  The rhythm of our rowing⁠—',
                          'Whose echoes live in memory yet,', 'Though envious years would say ‘forget.’']),
        (14, 161.1, 64.5, ['Come, hearken then, ere voice of dread,', '  With bitter tidings laden,',
                           'Shall summon to unwelcome bed', '  A melancholy maiden!',
                           'We are but older children, dear,', 'Who fret to find our bedtime near.']),
        (14, 296.6, 63.7, ['Without, the frost, the blinding snow,', '  The storm-wind’s moody madness⁠—',
                           'Within, the firelight’s ruddy glow,', '  And childhood’s nest of gladness.',
                           'The magic words shall hold thee fast:', 'Thou shalt not heed the raving blast.']),
        (15, 34.9, 71.7, ['And though the shadow of a sigh', '  May tremble through the story,',
                          'For ‘happy summer days’ gone by,', '  And vanish’d summer glory⁠—',
                          'It shall not touch with breath of bale', 'The pleasance of our fairy-tale.'])]
    pages = []
    for leaf in (13, 14, 15):
        items = []
        if leaf == 13:
            items.append(Picture('double-rule.svg', 135.5, 64.8, 2.0))
        for lf, top, x0, lines in stanzas:
            if lf == leaf:
                items.append(('stanza', top, x0, lines))
        pages.append(items)
    return dict(pages=pages, dx=BODY_DX, leaf=13)


def title():
    # (Its own crop: its lines' gaps closed in proportion from the text
    # area's top to its foot, each line its own size, centred.)
    raw = [('THROUGH THE LOOKING-GLASS,', 34.6, 25.3, 276.1, 'cap', 125),
           ('AND WHAT ALICE FOUND THERE.', 86.4, 48.3, 252.8, 'cap', 90),
           ('BY', 160.6, 146.2, 154.3, 'cap', 35),
           ('LEWIS CARROLL,', 175.7, 96.8, 198.1, 'cap', 72),
           ('[.sc]#Author of “Alice’s Adventures in Wonderland.”#', 194.7, 63.4, 236.8, 'scw', 0),
           ('__WITH FIFTY ILLUSTRATIONS__', 266.4, 71.8, 231.6, 'cap', 57),
           ('__BY JOHN TENNIEL.__', 286.2, 97.4, 199.9, 'cap', 55),
           ('[.blackletter]#London:#', 392.9, 133.6, 165.3, 'fixed', 9.5),
           ('MACMILLAN AND CO.', 407.2, 81.5, 211.5, 'cap', 71),
           ('1872.', 423.1, 137.0, 157.2, 'fixed', 9.6),
           ('__[The Right of Translation and Reproduction is reserved.]__', 455.4, 48.6, 247.7, 'width', 0)]
    first, last = 62.0, 416.0
    k = (last - first) / (raw[-1][1] - raw[0][1])
    out = []
    for text, top, x0, x1, kind, v in raw:
        y = first + (top - raw[0][1]) * k
        style = 'i' if text.startswith('__') else 'n'
        face = 'Italic' if style == 'i' else 'Regular'
        if kind == 'cap':
            size = round(v * P / CAP, 2)
            # (No wider than the printing's line: a face wider than its
            # type set smaller.)
            size = min(size, round((x1 - x0) / width(text, 10, face) * 10, 2))
            track = max(0.0, ((x1 - x0) - width(text, size, face)) / max(1, len(plain(text)) - 1))
        elif kind == 'scw':
            size = round((x1 - x0) / width(text, 10, face, True) * 10, 2)
            track = 0.0
        elif kind == 'fixed':
            size, track = v, 0.0
        else:
            size = round((x1 - x0) / width(text, 10, face) * 10, 2)
            track = 0.0
        out.append(Line(text, y, None, None, size=size, style=style, align='c', track=round(track, 2),
                        sc=kind == 'scw',
                        needle={'[.blackletter]#London:#': 'London:'}.get(text)))
    return dict(pages=[out], dx=0.0, leaf=11, scaled=True)


def device():
    return dict(pages=[[Picture('looking-glass-device.png', 200.7, 59.0, 57.4, 'The printer’s device')]],
                dx=BODY_DX, leaf=16)


def contents():
    out = [Line('CONTENTS.', 94.2, 109.8, 191.2, size=12.3, align='c', track=0.5),
           Line('CHAPTER', 126.2, 24.1, 45.0, size=4.6, align='l', track=0.3),
           Line('PAGE', 126.2, 263.0, 277.0, size=4.6, align='r', track=0.3)]
    entries = [('I.', 'Looking-Glass House', 1), ('II.', 'The Garden of Live Flowers', 26),
               ('III.', 'Looking-Glass Insects', 46), ('IV.', 'Tweedledum and Tweedledee', 66),
               ('V.', 'Wool and Water', 91), ('VI.', 'Humpty Dumpty', 113),
               ('VII.', 'The Lion and the Unicorn', 137), ('VIII.', '“It’s my own Invention”', 157),
               ('IX.', 'Queen Alice', 185), ('X.', 'Shaking', 215), ('XI.', 'Waking', 216),
               ('XII.', 'Which Dreamed it?', 218)]
    tops = [137.6, 157.7, 178.2, 198.5, 219.1, 239.6, 259.8, 279.6, 300.6, 320.8, 341.1, 361.1]
    for (num, name, page), top in zip(entries, tops):
        out += [Line(num, top, 20.0, 41.3, size=7.4, align='r'),
                Line(f'[.sc]#{name}#', top, 48.3, 262.0, size=7.4, align='j', dots=True, sc=True,
                     needle=re.sub(r'[^\w]', '', name.split()[0].upper())),
                Line(f'{page}', top, 262.0, 277.5, size=7.4, align='r')]
    return dict(pages=[out], dx=BODY_DX, leaf=17)


# ------------------------------------------------------------- writing

def role_for(line, dx, roles, text):
    """The role setting [line] where the scan has it: a left-aligned line
    from its left, its measure on to the page's right; a right-aligned
    one to its right; a centred one about its middle, as wide as it may
    be; a justified one its own measure, its letters closed up where the
    face sets it wider."""
    face = 'italic' if line.style == 'i' else 'normal'
    natural = width(text, line.size, face_of(line), line.sc) + line.track * max(0, len(plain(text)) - 1)
    track = line.track
    if line.x0 is None:
        ml = mr = -20.0
    elif line.align == 'l':
        ml, mr = line.x0 + dx - LEFT, -20.0
    elif line.align == 'r':
        ml, mr = -20.0, RIGHT - (line.x1 + dx)
    elif line.align == 'c':
        c = (line.x0 + line.x1) / 2 + dx
        h = natural / 2 + 20
        ml, mr = c - h - LEFT, RIGHT - (c + h)
    else:
        ml, mr = line.x0 + dx - LEFT, RIGHT - (line.x1 + dx)
        room = line.x1 - line.x0
        if natural > room - 0.5:
            track = round(track - (natural - room + 0.5) / max(1, len(plain(text)) - 1) - 0.005, 2)
    ml, mr = round(ml, 1), round(mr, 1)
    align = {'l': 'left', 'r': 'right', 'c': 'center', 'j': 'justify'}[line.align]
    name = (f'lgf-{int(round(line.size * 100))}-{line.style}-{line.align}'
            f'-t{int(round(track * 100))}-l{int(round(ml * 10))}-r{int(round(mr * 10))}').replace('-t-', '-tm').replace('-l-', '-lm').replace('-r-', '-rm')
    spec = {'font_size': line.size, 'font_style': face, 'text_align': align, 'text_indent': 0,
            'line_height': 1, 'margin_left': ml, 'margin_right': mr, 'hyphens': 'false'}
    if line.align == 'j':
        spec['text_align_last'] = 'justify'
    if track:
        spec['letter_spacing'] = f'{track}pt'
    roles[name] = spec
    return name


def build_pages():
    return [half_title(), dramatis(), moves(), 'frontispiece', title(), 'blank', poem(), device(), contents(), 'blank']


# A line paragraph's block (line height 1): 1.236 of its size, its
# letters' top (Poppler's) 0.236 of its size below the block's top; a
# leaded stanza's lines 15.7 pt apart, its first's letters 4.03 pt down.
BLOCK, INK = 1.236, 0.236
STANZA_PITCH, STANZA_INK = 15.7, 4.03


def write():
    """front.adoc, each block's `margin-top` the room from the block
    before it to where the scan has it."""
    roles = {}
    out = ['// Looking-Glass\'s front matter as the 1872 printing sets it (Macmillan,',
           '// the first edition; tool/alice_1867/front_lg.py, from the scan): each',
           '// page the printing\'s, each line where it sets it. Not edited by hand.',
           '']
    first_page = True

    def place(top, cursor, first):
        """The spacer or margin putting a block's top at [top]."""
        m = top - cursor
        if first:
            return [f'image::blank.svg["",role=cut,pdfwidth=1pt,pdfheight={max(0.1, m):.2f}pt]', ''], 0.0
        return [], m

    for spec in build_pages():
        if spec == 'frontispiece':
            out += ['<<<', '', 'include::frontispiece.adoc[]', '']
            continue
        if spec == 'blank':
            out += ['ifdef::backend-pdf[]', '<<<', '', 'image::blank.svg["",role=cut,pdfwidth=1pt,pdfheight=1pt]',
                    'endif::[]', '']
            continue
        pdf_only = spec['leaf'] in (11, 16, 17)
        for page in spec['pages']:
            if pdf_only:
                out.append('ifdef::backend-pdf[]')
            if not first_page:
                out += ['<<<', '']
            first_page = False
            dx = spec['dx']
            cursor = PAGE_TOP
            first = True
            for item in page:
                if isinstance(item, Picture):
                    pre, m = place(item.top, cursor, first)
                    out += pre + [f'[.lgf-pic,margin-top={m:.2f}pt]',
                                  f'image::{item.name}["{item.alt}",role=cut,pdfwidth={item.width}pt,align=center]', '']
                    cursor = item.top + item.height
                elif isinstance(item, tuple):
                    _, top, x0, lines = item
                    spaces = max(0, round((x0 + dx - LEFT - 18) / 2.8))
                    btop = top - 0.18 * 10 - STANZA_INK
                    pre, m = place(btop, cursor, first)
                    out += pre + [f'[verse.poem.v10.lh157,margin-top={m:.2f}pt,margin-bottom=0]', '____']
                    out += [' ' * (spaces + (3 if l.startswith('  ') else 0)) + l.strip() for l in lines]
                    out += ['____', '']
                    cursor = btop + STANZA_PITCH * len(lines)
                else:
                    line = item
                    text = fill_dots(line) if line.dots else line.text
                    role = role_for(line, dx, roles, text)
                    # (Not a list's item: "1." an ordered list's, "W." an
                    # alphabetic one's.)
                    if re.match(r'[A-Za-z0-9]{1,4}\.(\s|$)|[-*.]', text):
                        text = '{empty}' + text
                    btop = line.top - 0.18 * line.size - INK * line.size
                    pre, m = place(btop, cursor, first)
                    out += pre + [f'[.{role},margin-top={m:.2f}pt,margin-bottom=0]', text, '']
                    cursor = btop + BLOCK * line.size
                first = False
            if pdf_only:
                out.append('endif::[]')
            out.append('')
    open(OUT, 'w', encoding='utf-8').write('\n'.join(out) + '\n')
    look = open(LOOK).read()
    body = ''.join('    ' + name + ': { ' + ', '.join(f'{k}: {v}' for k, v in spec.items()) + ' }\n'
                   for name, spec in sorted(roles.items()))
    look = re.sub(r'(    # lgf-begin\n).*?(    # lgf-end\n)', lambda mm: mm[1] + body + mm[2], look, flags=re.S)
    open(LOOK, 'w').write(look)


if __name__ == '__main__':
    write()
