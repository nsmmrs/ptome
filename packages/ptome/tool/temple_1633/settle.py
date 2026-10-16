"""Settle what can be settled without a reviewer: each TCP gap (• a
letter, 〈◊〉 a word) filled where the book's own words fitting it include
the OCR's reading; each candidate variant read again by Tesseract (its
line's crop), kept where Tesseract reads the TCP's word, open where it
reads the OCR's or neither.

    python3 -I settle.py  -> choices.json (open ones for review sheets)
"""
import difflib, glob, json, os, re, subprocess, sys, tempfile
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from align import norm
from PIL import Image

W = os.path.join(os.environ.get('TEMPLE_WORK', os.path.expanduser('~/.cache/asciidart-work/print-match')), 'herbert')
D = glob.glob(f'{W}/*_jp2')[0]
NAME = D.split('/')[-1][:-4]
S = json.load(open('stream.json'))
V = json.load(open('variants.json'))
cache_path = 'tesseract.json'
cache = json.load(open(cache_path)) if os.path.exists(cache_path) else {}
images = {}


def tess(leaf, box):
    key = f'{leaf}:{box}'
    if key in cache:
        return cache[key]
    if leaf not in images:
        images.clear()
        images[leaf] = Image.open(f'{D}/{NAME}_{leaf:04d}.jp2').convert('L')
    x0, y0, x1, y1 = box
    crop = images[leaf].crop((max(0, x0 - 20), max(0, y0 - 20), x1 + 20, y1 + 20))
    with tempfile.NamedTemporaryFile(suffix='.png') as f:
        crop.save(f.name)
        r = subprocess.run(['tesseract', f.name, '-', '--psm', '7', '-l', 'eng'],
                           capture_output=True, text=True)
    cache[key] = r.stdout.strip()
    return cache[key]


def spelling(w):
    """A word's letters as the editions' spellings vary them: -ie and -y,
    a final e, doubled letters, an apostrophe for an e."""
    t = w.lower().replace('ſ', 's').replace('’', "'")
    t = re.sub(r'[^a-z\']', '', t)
    t = t.replace("'", 'e').replace('ie', 'y')
    t = re.sub(r'(.)\1', r'\1', t)
    return t.rstrip('e')


vocab = set()
for r in S:
    if 't' in r:
        for w in r['t'].split():
            vocab.add(re.sub(r'[^\w•]', '', w))
choices = []
# 1. The gaps.
for k, r in enumerate(S):
    t = r.get('t', '')
    if '•' not in t and '〈◊〉' not in t:
        continue
    reading = ' '.join(x for x in [r.get('ocr', ''), tess(r['leaf'], r['box']) if 'box' in r else ''] if x)
    filled = t
    open_ = False
    for m in list(re.finditer(r"[\w'’]*•[\w•'’]*", t)):
        word = m.group(0)
        rx = re.compile('^' + re.escape(word).replace('•', '.') + '$', re.I)
        fits = sorted({v for v in vocab if '•' not in v and rx.match(v)})
        seen = [f for f in fits if norm(f) and norm(f) in norm(reading)]
        # (The readings' own words that fit the gap: the OCR's, Tesseract's.)
        read = [x.replace('ſ', 's') for x in re.findall(r"[\w'’ſ]+", reading)]
        read = [x for x in read if rx.match(x)]
        if len(seen) == 1 or (len(fits) == 1 and not seen):
            filled = filled.replace(word, (seen or fits)[0], 1)
        elif read and len({x.lower() for x in read}) == 1:
            filled = filled.replace(word, read[0], 1)
        else:
            open_ = True
    if '〈◊〉' in filled:
        open_ = True
    choices.append(dict(i=k, leaf=r['leaf'], box=r.get('box'), kind='gap', tcp=t, value=filled,
                        ocr=r.get('ocr', ''), tess=tess(r['leaf'], r['box']) if 'box' in r else '',
                        open=open_))
# 2. The candidate variants.
for v in V:
    r = S[v['i']]
    if '•' in r['t'] or '〈◊〉' in r['t']:
        continue
    tl = tess(r['leaf'], r['box'])
    nt = norm(tl)
    a = difflib.SequenceMatcher(None, norm(r['t']), nt).ratio()
    variant_line = r['t'].replace(v['tcp'], v['ocr'], 1) if v['tcp'] else r['t'] + ' ' + v['ocr']
    b = difflib.SequenceMatcher(None, norm(variant_line), nt).ratio()
    tw, ow = norm(v['tcp']), norm(v['ocr'])
    t_has = bool(tw) and tw in nt
    o_has = bool(ow) and ow in nt
    value = v['tcp']
    if (t_has and not o_has) or a > b + 0.03:
        how, open_ = 'tesseract-tcp', False
    elif o_has and not t_has and spelling(v['tcp']) == spelling(v['ocr']) and v['tcp'] != v['ocr'] \
            and not re.search(r'[()|]', v['ocr']):
        # (Two readings of the scan agree on a word the TCP hasn't: the
        # second edition's.)
        how, open_, value = 'tesseract-ocr', False, v['ocr']
    elif len(tw) <= 4 and len(ow) <= 4 and difflib.SequenceMatcher(None, tw, ow).ratio() >= 0.5:
        # (A short word one letter off: the OCR's misreading.)
        how, open_ = 'short', False
    else:
        how, open_ = None, True
    choices.append(dict(i=v['i'], leaf=r['leaf'], box=r['box'], kind=v.get('kind', 'word'), tcp=v['tcp'],
                        ocr=v['ocr'], tess=tl, value=value, open=open_, how=how, t=r['t']))
json.dump(cache, open(cache_path, 'w'))
json.dump(choices, open('choices.json', 'w'), ensure_ascii=False, indent=0)
print(len(choices), 'choices,', sum(c['open'] for c in choices), 'open')
