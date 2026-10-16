"""The Temple's text, page for page and line for line as the 1633 second
edition sets it: the TCP's words (corrected by review) on the scan's
lines, each page's lines its lines, each line's indent its indent; a
word the printing turns up into the line above after a bracket set
there flush right; a line too long beside an initial wrapped as the
printing wraps it.

    python3 -I render.py OUT-DIR [MARGINS.json]

Writes OUT-DIR/front.adoc, temple.adoc, titles.adoc and fit.json (each
fitted block's key, page, kind, first words and target baseline).
"""
import json, os, re, statistics, sys, unicodedata
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tcp2
from words import norm, lines_of

W = os.path.join(os.environ.get('TEMPLE_WORK', os.path.expanduser('~/.cache/asciidart-work/print-match')), 'herbert')
HERE = os.path.dirname(os.path.abspath(__file__))
PX = 72 / 800 * 0.8189          # points (the book's) per scan pixel
recs = tcp2.records(f'{W}/A03058.xml')
placed = json.load(open(f'{HERE}/placed.json'))
WORDS = placed['words']
LINES = {int(k): v for k, v in placed['lines'].items()}
OVERRIDES_PATH = f'{HERE}/overrides.json'
OVERRIDES = json.load(open(OVERRIDES_PATH)) if os.path.exists(OVERRIDES_PATH) else {}

# ---------------------------------------------------------------- review

def apply_review():
    """The reviewed lines' text in place of the TCP's: decisions.tsv (by
    review sheet number), the gaps settled without review (choices.json),
    mapped from the first stream's lines to these records by their
    letters on their leaf."""
    stream = json.load(open(f'{HERE}/stream.json'))
    index = json.load(open(f'{HERE}/review/index.json'))
    choices = json.load(open(f'{HERE}/choices.json'))
    old = {}
    for k, r in enumerate(stream):
        if 't' in r:
            old[k] = (r['leaf'], r['t'])
    new_text = {}
    for c in choices:
        if c['kind'] == 'gap' and not c['open'] and c['value'] != c['tcp']:
            new_text[c['i']] = c['value']
    for line in open(f'{HERE}/decisions.tsv', encoding='utf-8'):
        n, _, text = line.rstrip('\n').partition('\t')
        if text and text != '=':
            new_text[index[n]] = text
    by_leaf = {}
    for ri, r in enumerate(recs):
        by_leaf.setdefault(r['leaf'], []).append(ri)
    applied = 0
    for si, text in new_text.items():
        leaf, t = old[si]
        key = norm(t.replace('-', ''))
        for ri in by_leaf.get(leaf, []):
            r = recs[ri]
            if norm(r['plain']) == key and not r.get('reviewed'):
                retext(r, text)
                applied += 1
                break
    return applied, len(new_text)


def retext(r, text):
    """Record [r]'s words from [text], each word's italic its original
    word's where their letters agree."""
    old = [(norm(''.join(p for p, _ in w)), w) for w in r['words']]
    out = []
    j = 0
    for word in text.split():
        nw = norm(word)
        italic = False
        for k in range(j, min(len(old), j + 3)):
            if old[k][0] == nw or (nw and old[k][0] and (old[k][0] in nw or nw in old[k][0])):
                italic = all(it for _, it in old[k][1]) and bool(old[k][1])
                j = k + 1
                break
        # (A gap's letter's case the TCP's: `I•` filled `If`, not `if`.)
        if j > 0 and old[j - 1][1] and old[j - 1][1][0][0][:1].isupper() and word[:1].islower() \
                and '•' in ''.join(p for p, _ in old[j - 1][1]):
            word = word[:1].upper() + word[1:]
        out.append([(word, italic)])
    # (A word placed on the scan keeps its place: words beyond the old
    # count share the last one's.)
    r['words_new'] = out
    r['reviewed'] = True


# ---------------------------------------------------------------- places

def places():
    """Each record's words' (leaf, line): the words matched exactly at
    theirs, the others at the one before them in their record, else the
    one after; a record with none after the record before it."""
    by_rec = {}
    for w in WORDS:
        by_rec.setdefault(w['rec'], []).append(w)
    out = {}
    prev = None
    for ri in range(len(recs)):
        ws = by_rec.get(ri, [])
        pl = [(w['place']['leaf'], w['place']['line']) if w['place'] and w['place'].get('exact') else None
              for w in ws]
        approx = [(w['place']['leaf'], w['place']['line']) if w['place'] else None for w in ws]
        if not any(pl):
            pl = approx
        last = None
        for k in range(len(pl)):
            if pl[k] is None:
                pl[k] = last
            last = pl[k]
        nxt = None
        for k in reversed(range(len(pl))):
            if pl[k] is None:
                pl[k] = nxt
            nxt = pl[k]
        if not any(pl):
            pl = [prev] * len(ws)
        out[ri] = pl
        if pl and pl[-1]:
            prev = pl[-1]
    return out


# ---------------------------------------------------------------- markup

SPECIAL = re.compile(r'([*_#+`^~{}\[\]])')


def esc(t):
    t = t.replace('<<', '\\<<')
    return SPECIAL.sub(lambda m: '{plus}' if m[1] == '+' else ('\\' + m[1] if m[1] in '*_#`^~' else m[1]), t)


def markup(words):
    """Words (each a list of (text, italic) pieces) as AsciiDoc, the
    italic runs in `__`."""
    out = []
    run = []
    def close():
        if run:
            out.append('__' + ' '.join(run) + '__')
            run.clear()
    for w in words:
        if all(it for _, it in w):
            run.append(esc(''.join(p for p, _ in w)))
            continue
        close()
        out.append(''.join(('__' + esc(p) + '__') if it else esc(p) for p, it in w))
    close()
    return ' '.join(out)


# ---------------------------------------------------------------- pages

def leaf_geometry(leaf):
    """The leaf's text edge (pixels): the left of most lines' first
    words, its running head's baseline."""
    ls = LINES.get(leaf, [])
    xs = [round(l['words'][0]['box'][0] / 20) * 20 for l in ls if len(l['words']) >= 4]
    left = statistics.mode(xs) if xs else (min((l['words'][0]['box'][0] for l in ls), default=0))
    # (Lines starting a little in from the mode: the edge the least of
    # those within 30 px of it.)
    near = [l['words'][0]['box'][0] for l in ls if len(l['words']) >= 4 and abs(l['words'][0]['box'][0] - left) < 40]
    left = min(near) if near else left
    head = ls[0]['words'][0]['box'][3] if ls else 0
    return left, head


def build(out_dir, margins):
    applied, total = apply_review()
    pass
    pl = places()
    fits = []
    # (Each record: its words, and their places.)
    pages = {}
    for ri, r in enumerate(recs):
        words = r.get('words_new', r['words'])
        p = pl[ri]
        if len(p) < len(words):
            p = p + [p[-1] if p else None] * (len(words) - len(p))
        for wi, w in enumerate(words):
            where = p[wi] if p else None
            if where is None:
                where = (r['leaf'], 9999)
            leaf, line = where
            pages.setdefault(leaf, {}).setdefault(line, []).append((ri, wi, w))
    json.dump({str(k): {str(l): [(ri, wi) for ri, wi, _ in v] for l, v in lines.items()}
               for k, lines in pages.items()}, open(f'{out_dir}/layout.json', 'w'))
    return pages, fits


if __name__ == '__main__':
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    pages, fits = build(out, {})
    for leaf in (8, 10, 33):
        print('== leaf', leaf)
        for line in sorted(pages[leaf]):
            ws = pages[leaf][line]
            recs_on = sorted({ri for ri, _, _ in ws})
            print(f'  {line:4d} {recs_on} {markup([w for _, _, w in ws])[:90]}')
