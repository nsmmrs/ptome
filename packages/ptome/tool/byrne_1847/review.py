"""A leaf's lines for review: each line's crop from the scan, its
symbols boxed and numbered; and a draft of its text, the OCR's words
corrected to the book's spelling where a word of the dictionary or the
book is near, `{n}` where symbol n stands.

    python3 -I review.py LEAF -> rev/sheet-LEAF.png, prints the drafts
"""
import difflib, json, os, re, sys
import numpy as np
from PIL import Image, ImageDraw
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from seg import SCAN, W

G = json.load(open(f'{HERE}/groups-frozen.json'))
VOCAB = set(w.strip() for w in open('/usr/share/dict/cracklib-small') if w.strip().isalpha())
BOOK = os.path.expanduser('~/Work/ports/ptome/packages/ptome/test/showcase/byrne/text/book-1.adoc')
if os.path.exists(BOOK):
    VOCAB |= set(re.findall(r'[A-Za-z]+', open(BOOK).read()))
VOCAB |= {'ax', 'def', 'pr', 'post', 'const', 'hyp', 'conft', 'Q', 'E', 'D', 'equilateral', 'isosceles',
          'rectilineal', 'parallelogram', 'parallelograms', 'hypotenuse', 'Fig', 'vide'}
LOWER = {w.lower() for w in VOCAB}
ROMAN = {'I': '1', 'l': '1', 'i': '1', 'II': '11', 'O': '0', 'o': '0'}


def fix(word):
    """The OCR's word as the book spells it, its long s a round s."""
    m = re.match(r'^([(\[]*)(.*?)([)\].,;:]*)$', word)
    pre, core, post = m[1], m[2], m[3]
    if not core:
        return word
    # (Numbers: an old-style one, read as I or l.)
    if re.fullmatch(r'[0-9IloO]+', core) and re.search(r'[0-9]', core + post) or re.fullmatch(r'[Il]', core) and post.startswith('.'):
        core = ''.join(ROMAN.get(c, c) for c in core)
        return pre + core + post
    if core.lower() in LOWER:
        return pre + core + post
    # (The book's abbreviations, read wrong.)
    for short in ('post', 'def', 'ax', 'pr', 'const', 'hyp'):
        if difflib.SequenceMatcher(None, core.lower().replace('f', 's'), short).ratio() >= 0.75 and post.startswith('.'):
            return pre + short + post
    # (The long s, read f.)
    cands = {core}
    for i, c in enumerate(core):
        if c == 'f':
            cands |= {s[:i] + 's' + s[i + 1:] for s in list(cands)}
    for c in cands:
        if c.lower() in LOWER:
            return pre + c + post
    best = difflib.get_close_matches(core.lower(), LOWER, n=1, cutoff=0.86)
    if best:
        b = best[0]
        if core[:1].isupper():
            b = b[:1].upper() + b[1:]
        return pre + b + post
    return word


def draft(line):
    out = []
    n = 0
    for it in line['items']:
        if it['kind'] == 'symbol':
            n += 1
            out.append(('sym', '{%d}' % n))
        elif it['kind'] == 'stop':
            out.append(('stop', it['text']))
        else:
            out.append(('word', fix(it['text'].strip())))
    text = ''
    for kind, s in out:
        text += s if (kind == 'stop' or not text) else ' ' + s
    return re.sub(r'\s+', ' ', text)


from PIL import ImageFont
FONT = ImageFont.load_default(size=26)


def sheet(leaf):
    p = G[leaf]
    im = Image.open(SCAN % int(leaf)).convert('RGB')
    rows = []
    for li, l in enumerate(p['lines']):
        items = l['items']
        x0 = max(0, min(it['box'][0] for it in items) - 20)
        x1 = min(im.width, max(it['box'][2] for it in items) + 20)
        y0 = max(0, min(min(it['box'][1] for it in items), l['base'] - 50) - 24)
        y1 = min(im.height, max(max(it['box'][3] for it in items), l['base'] + 18) + 8)
        crop = im.crop((x0, y0, x1, y1)).copy()
        d = ImageDraw.Draw(crop)
        n = 0
        for it in items:
            if it['kind'] == 'symbol':
                n += 1
                b = it['box']
                d.rectangle([b[0] - x0, b[1] - y0, b[2] - x0, b[3] - y0], outline=(0, 160, 0), width=2)
                d.text((b[0] - x0 + 2, b[1] - y0 - 2), str(n), fill=(220, 0, 0), font=FONT)
        scale = min(1.0, 1300 / crop.width)
        crop = crop.resize((int(crop.width * scale), int(crop.height * scale)))
        rows.append((li, crop))
    H = sum(c.height + 22 for _, c in rows)
    out = Image.new('RGB', (1380, H), 'white')
    d = ImageDraw.Draw(out)
    y = 0
    for li, c in rows:
        d.text((4, y + 4), str(G[leaf]['lines'][li]['base']), fill=(0, 0, 200), font=ImageFont.load_default(size=18))
        out.paste(c, (60, y + 18))
        y += c.height + 22
    out.save(f'{W}/byrne/rev/sheet-{leaf}.png')


if __name__ == '__main__':
    for leaf in sys.argv[1:]:
        sheet(leaf)
        for li, l in enumerate(G[leaf]['lines']):
            print(f"{leaf}:{l['base']}\t{draft(l)}")
