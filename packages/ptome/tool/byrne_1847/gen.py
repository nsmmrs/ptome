"""Book I as the 1847 printing sets it: each page's lines, diagrams and
initial, each where the scan has it, from text.tsv's lines and the
pictures trace.py traced.

    python3 -I gen.py WORK-DIR [LEAF...] -> WORK-DIR/text/book-1.adoc,
        WORK-DIR/images/, WORK-DIR/byrne-look.yml
"""
import json, os, re, shutil, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from pieces import G, page, picture_name
from seg import OCR, W
T = json.load(open(f'{W}/byrne/traced.json'))
SVG = f'{W}/byrne/svg'

S = 72 / 300                 # points per scan pixel
PAGE_W, PAGE_H = 532.8, 669.6
TOP = 50.0                   # the flow's top (the page's top margin)
HEAD_Y = 28.2                # the running head's baseline
LH, BO = 10.6, 9.063         # a line's block: its height, its baseline below its top




HEADS = json.load(open(f'{HERE}/heads.json'))


def head_of(leaf, p):
    """The running head's centre and baseline (scan px), from its ink
    (heads.py); the opening page's, unheaded, the centre of its "BOOK
    I." and the heads' usual baseline."""
    if leaf in HEADS:
        return HEADS[leaf]['cx'], HEADS[leaf]['base']
    book = next(l for l in p['lines'] if l.get('role') == 'book')
    return (book['x0'] + book['x1']) / 2, 180


def roman(n):
    out = ''
    for v, r in ((40, 'XL'), (10, 'X'), (9, 'IX'), (5, 'V'), (4, 'IV'), (1, 'I')):
        while n >= v:
            out, n = out + r, n - v
    return out


def prop_of(leaf):
    """The proposition a leaf's page sets: one a page, XXVI and XLVII on
    two."""
    n = int(leaf) - 34
    return n if n <= 26 else n - 1 if n <= 48 else n - 2


GAP = '\u2002\u2002'


def head_text(leaf):
    lines = [l for l in OCR[int(leaf)]['lines'] if l['b'][3] < 300]
    return ' '.join(w['t'] for l in lines for w in l['w'])


FONTS = os.path.expanduser('~/.local/share/fonts/ptome')
SIZE = 10.6
_METRICS = {}


def advance(italic, ch):
    """[ch]'s advance in Libre Caslon Text, in ems."""
    if italic not in _METRICS:
        from fontTools.ttLib import TTFont
        f = TTFont(f'{FONTS}/LibreCaslonText-{"Italic" if italic else "Regular"}.ttf')
        hm, upm = f['hmtx'], f['head'].unitsPerEm
        _METRICS[italic] = {c: hm[g][0] / upm for c, g in f.getBestCmap().items()}
    return _METRICS[italic].get(ord(ch), 0.5)


def natural(text):
    """The text's (AsciiDoc, its pictures out) width at the text's size,
    and its letters' count."""
    text = re.sub(r'\{(empty|nbsp)\}', lambda m: '' if m[1] == 'empty' else ' ', text)
    w, n, italic = 0.0, 0, False
    for part in re.split(r'(__)', text):
        if part == '__':
            italic = not italic
            continue
        for ch in part:
            w += advance(italic, ch) * SIZE
            n += ch != ' '
    return w, n


def q(v):
    return round(v * 2) / 2


def canvas(name, box, cx, out):
    """[name]'s drawing on a canvas as wide as the page, where the scan
    has it across the page."""
    src = open(f'{SVG}/{name}').read()
    vb = re.search(r'viewBox="0 0 ([\d.]+) ([\d.]+)"', src)
    w, h = float(vb[1]), float(vb[2])
    inner = re.sub(r'^<svg[^>]*>|</svg>\s*$', '', src.strip())
    full = PAGE_W / S
    dx = box[0] - (cx - full / 2)
    text = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{PAGE_W}pt" height="{h * S:.2f}pt" '
            f'viewBox="0 0 {full:.1f} {h:.1f}"><g transform="translate({dx:.1f},0)">{inner}</g></svg>\n')
    open(f'{out}/images/{name}', 'w').write(text)


# Each page's woodcut initial, the letter it is (its alt text).
INITIALS = dict(zip(
    [str(leaf) for leaf in range(35, 85) if leaf not in (61, 83)],
    'OFFIIIOITTFTWIIIAIIAIGAIIIIIASFISTPPTTEEITTTTUII'))


def main():
    out = sys.argv[1]
    leaves = sys.argv[2:] or sorted(G, key=int)
    os.makedirs(f'{out}/images', exist_ok=True)
    os.makedirs(f'{out}/text', exist_ok=True)
    roles = set()
    lines_out = []
    expect = {}
    for leaf in leaves:
        p = page(leaf)
        tr = T.get(leaf, {})
        cx, hb = head_of(leaf, p)
        n = prop_of(leaf)
        lines_out.append(f'// tag::page-{int(leaf) - 34}[]')
        if n != prop_of(str(int(leaf) - 1)) or leaf == '35':
            if n == 1:
                lines_out += [f'[%notitle#prop-1.opening]', '== Proposition I.', '']
            else:
                kind = 'PROB.' if re.search(r'PROB|PROP\.\s*$', head_text(leaf)) else 'THEOR.'
                lines_out += [f'[%notitle#prop-{n}.prop,running-title="BOOK I.{GAP}PROP. {roman(n)}.{GAP}{kind}"]',
                              f'== Proposition {roman(n)}.', '']
        else:
            lines_out += ['<<<', '']
        def y(px):
            return HEAD_Y + (px - hb) * S
        def x(px):
            return PAGE_W / 2 + (px - cx) * S
        blocks = []
        def picture_block(name, alt):
            b = tr[name]
            blocks.append((y(b[1]), 'image', (name, b, alt), (b[3] - b[1]) * S))
        for di, d in enumerate(p['diagrams']):
            alt = ('A headpiece of ornament' if leaf == '35' and di == 0
                   else f'The diagram of Proposition {roman(n)}')
            picture_block(picture_name(leaf, d), alt)
        if p['initial']:
            picture_block(f'l{leaf}-initial.svg', INITIALS[leaf])
        for l in p['lines']:
            if l.get('undecided'):
                continue
            if l['role'] == 'picture':
                picture_block(f'l{leaf}-line{l["base"]}.svg', ''.join(x[1] for x in l['pieces'] if x[0] == 'text'))
                continue
            for piece in l['pieces']:
                if piece[0] == 'pic' and piece[3]:
                    picture_block(picture_name(leaf, piece[1]), piece[2])
            blocks.append((y(l['base']) - BO, 'line', l, LH))
        blocks.sort(key=lambda b: b[0])
        lines_out.append(f'// page {int(leaf) - 34} (leaf {leaf})')
        expect[leaf] = []
        cursor = TOP
        for top, kind, data, height in blocks:
            margin = top - cursor
            if kind == 'image':
                name, box, alt = data
                canvas(name, box, cx, out)
                alt = alt.replace('"', "'")
                lines_out += [f'[.d,margin-top={margin:.2f}pt]', f'image::{name}["{alt}",pdfwidth={PAGE_W}pt]', '']
            else:
                l = data
                text = ''
                for piece in l['pieces']:
                    if piece[0] == 'text':
                        text += piece[1]
                    elif not piece[3]:
                        name = picture_name(leaf, piece[1])
                        b = tr[name]
                        shutil.copy(f'{SVG}/{name}', f'{out}/images/{name}')
                        w = (b[2] - b[0]) * S
                        bottom = ((piece[4] or l['base']) - b[3]) * S
                        text += (f'image:{name}["{piece[2]}",pdfwidth={w:.2f}pt,'
                                 f'vertical-align={bottom:.2f}pt]')
                text = text.strip()
                # (Not a list's item: "Q. E. D." an alphabetic list's.)
                if re.match(r'[A-Za-z0-9]{1,4}\.\s|[-*.]', text):
                    text = '{empty}' + text
                left = q(x(l['x0']))
                right = q(PAGE_W - x(l['x1']))
                spaced = ' ' in text.replace('{nbsp}', '')
                role = 'j' if spaced else 'l'
                if text.startswith('[.sc]#'):
                    # (A line in small capitals the face makes: its words
                    # as they fall, from its left.)
                    role, spaced = 'l', False
                # (A line in capitals, spaced as the printing spaces them:
                # its letters spread to its width.)
                caps = l['role'] in ('book', 'prop') or bool(re.fullmatch(r'[A-Z][A-Z .,-]{3,}', text))
                # (A line set flush left alone: room to its right, so a
                # word the face sets wider than the printing's isn't broken.)
                if not spaced and not caps:
                    right = 0.0
                pics = sum(float(m) for m in re.findall(r'pdfwidth=([\d.]+)pt', text))
                w, n = natural(re.sub(r'image:[^\[]+\[[^\]]*\]', '', text))
                room = PAGE_W - left - right
                spaces = text.count(' ') * advance(False, ' ') * SIZE
                t = 0
                if caps and n:
                    # (Capitals spaced: their spacing what fills the line,
                    # its spaces as the face's.)
                    t = int((room - w - pics - 2) / n * 100)
                elif spaced and n:
                    # (A line the face sets wider than the printing's: its
                    # letters closed up until it fits, the spaces shrinking
                    # by a third, as the justification lets them; never
                    # broken.)
                    over = w + pics - room + 0.5
                    if over > 0:
                        t = -int(over / n * 100 + 1)
                extra = []
                if t:
                    name = f'T{t}' if t > 0 else f'Tm{-t}'
                    extra.append(name)
                    roles.add((name, 'letter_spacing', t / 100))
                rl, rr = f'L{int(left * 10)}', f'R{int(right * 10)}'
                roles.add((rl, 'margin_left', left))
                roles.add((rr, 'margin_right', right))
                role = '.'.join([role, *extra])
                if l['role'] == 'sig':
                    # (The gathering's signature, in a small size.)
                    role += '.sig'
                lines_out += [f'[.{role}.{rl}.{rr},margin-top={margin:.2f}pt]', text, '']
                if re.sub(r'image:[^\[]+\[[^\]]*\]|\{empty\}|\W', '', text):
                    expect[leaf].append(round(y(l['base']), 1))
            cursor = top + height
        lines_out += [f'// end::page-{int(leaf) - 34}[]', '']
    head = ['// Book I as the 1847 printing sets it, page for page and line for line:',
            '// made by tool/byrne_1847 (gen.py) from text.tsv; not edited by hand.', '']
    open(f'{out}/text/book-1.adoc', 'w').write('\n'.join(head + lines_out))
    # (Every page set: the pictures no page names, gone.)
    if len(leaves) == len(G):
        named = set(re.findall(r'image::?([^\[]+)\[', '\n'.join(lines_out)))
        for name in os.listdir(f'{out}/images'):
            if name not in named:
                os.remove(f'{out}/images/{name}')
    json.dump(expect, open(f'{W}/byrne/expect.json', 'w'))
    look = open(f'{HERE}/look-base.yml').read()
    look = look.replace('    # ROLES\n', ''.join(f'    {r}: {{ {k}: {v} }}\n' for r, k, v in sorted(roles)))
    open(f'{out}/byrne-look.yml', 'w').write(look)
    print(len(lines_out), 'lines;', len(roles), 'roles')


if __name__ == '__main__':
    main()
