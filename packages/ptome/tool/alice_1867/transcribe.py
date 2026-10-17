"""Draft a transcription of a printing from its OCR, aligned with the
Standard Ebooks text: the printing's words and lines, Standard Ebooks'
spelling, quotation marks and markup where the two agree; each
disagreement a choice, settled by a second reading (Tesseract on the
word's crop) or by review (decisions/BOOK.tsv: `CHOICE-ID<TAB>text`).

    python3 -I transcribe.py BOOK [--tesseract]

Writes out/BOOK/chapter-N.adoc and choices-BOOK.json.
"""
import json, os, re, sys, difflib, subprocess, tempfile
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import *
from slant import slant
import numpy as np
from PIL import Image

SC_RX = re.compile(r'[0-9A-Za-z]')


def norm(text):
    t = text.translate(PUNCT_MAP).replace('{shy}', '').replace('{zwsp}', '')
    t = t.replace('—', '-').replace('–', '-')
    return re.sub(r'\s+', '', t)


class Choice:
    def __init__(self, cid, kind, se, ocr, default, line, boxes):
        self.id, self.kind, self.se, self.ocr = cid, kind, se, ocr
        self.default, self.line, self.boxes = default, line, boxes
        self.value = None   # settled
        self.how = None
        self.reading = None

    def get(self):
        return self.value if self.value is not None else self.default

    def json(self):
        return dict(id=self.id, kind=self.kind, se=self.se, ocr=self.ocr,
                    default=self.default, value=self.value, how=self.how,
                    reading=self.reading, line=self.line['id'], boxes=self.boxes)


def context_text(otoks, k):
    """The OCR word k with the marks standing apart next to it."""
    pre, post = '', ''
    j = k - 1
    while j >= 0 and not otoks[j].core and otoks[j].line is otoks[k].line:
        pre = otoks[j].text + pre
        j -= 1
    j = k + 1
    while j < len(otoks) and not otoks[j].core and otoks[j].line is otoks[k].line:
        post += otoks[j].text
        j += 1
    return pre + otoks[k].text + post


def context_boxes(otoks, k):
    boxes = [otoks[k].boxes[0]]
    j = k - 1
    while j >= 0 and not otoks[j].core and otoks[j].line is otoks[k].line:
        boxes.append(otoks[j].box)
        j -= 1
    j = k + 1
    while j < len(otoks) and not otoks[j].core and otoks[j].line is otoks[k].line:
        boxes.append(otoks[j].box)
        j += 1
    return boxes


def union(boxes):
    return [min(b[0] for b in boxes), min(b[1] for b in boxes),
            max(b[2] for b in boxes), max(b[3] for b in boxes)]


def recase(it, ocr):
    """The printing's capitals for SE's word where only their case
    differs (`white rabbit`, `DRINK ME` in capitals, not small ones);
    not where the OCR's case is its own error (`IVe`, `alL`, `i`)."""
    o = re.sub(r'[^A-Za-z]', '', ocr)
    text = it['text']
    s_letters = re.sub(r'[^A-Za-z]', '', text)
    if o == s_letters or o.lower() != s_letters.lower() or len(o) < 2:
        return
    if re.search(r'[a-z][A-Z]', o):
        return
    out, at = [], 0
    for ch in text:
        if ch.isalpha() and ch.isascii():
            out.append(o[at])
            at += 1
        else:
            out.append(ch)
    it['text'] = ''.join(out)
    if o.isupper() and it['sc']:
        it['sc'] = False


def build(book):
    chapters = se_blocks(book)
    lines = ocr_lines(book)
    otoks = ocr_tokens(lines)
    stoks = [t for ch in chapters for b in ch['blocks'] for t in b['toks']]
    o_idx = [i for i, t in enumerate(otoks) if t.core]
    st_next = {id(t): (stoks[i + 1].text if i + 1 < len(stoks) else '')
               for i, t in enumerate(stoks)}
    sm = difflib.SequenceMatcher(None, [otoks[i].core for i in o_idx],
                                 [t.core for t in stoks], autojunk=False)
    # Each OCR word's item: its text (or a choice), style, block.
    items = [dict(k=k, tok=t, text='', italic=False, sc=False, block=None,
                  choice=None, inserts=[]) for k, t in enumerate(otoks)]
    choices = []

    def choose(kind, se, ocr, default, k, boxes):
        t = otoks[k]
        pos = t.line['toks'].index(t)
        c = Choice(f'{t.line["id"]}:{pos}:{kind}', kind, se, ocr, default, t.line, boxes)
        c.old_id = f'{t.line["id"]}:{k}:{kind}'
        # (The part after a division: read too, from its own line.)
        c.cont = t.cont if kind in ('word', 'words', 'extra') else None
        choices.append(c)
        return c

    for op, i1, i2, j1, j2 in sm.get_opcodes():
        ks = [o_idx[i] for i in range(i1, i2)]
        ss = stoks[j1:j2]
        block = (ss[0].block if ss else
                 stoks[j1 - 1].block if j1 > 0 else stoks[0].block)
        if op == 'equal':
            for k, st in zip(ks, ss):
                it = items[k]
                it.update(text=st.text, italic=st.italic, sc=st.sc, block=st.block)
                ot = otoks[k]
                recase(it, ot.text)
                ocr = curly(context_text(otoks, k))
                of = hyphens(ot.text)
                if ot.split is not None and of[ot.split:ot.split + 1] == '-':
                    of_div = of[:ot.split] + of[ot.split + 1:]
                else:
                    of_div = of
                form_ok = hyphens(st.text) in (of, of_div)
                if not form_ok or not punct_agrees(otoks, k, st.text):
                    it['choice'] = choose('word', st.text, ocr, st.text, k,
                                          context_boxes(otoks, k))
                    nxt = stoks.index(st) + 1 if False else None
                    it['choice'].se_next = st_next.get(id(st), '')
            continue
        if op == 'insert':
            # SE's words the OCR lacks: kept out unless the scan has them.
            k = o_idx[i1 - 1] if i1 > 0 else o_idx[0]
            c = choose('insert', ' '.join(s.text for s in ss), '', '', k,
                       [otoks[k].line['box']])
            items[k]['inserts'].append((c, ss))
            continue
        os_ = [otoks[k] for k in ks]
        vocab_ok = all(in_vocab(t.text.strip('"\'()—-,.;:!?*')) for t in os_)
        if op == 'replace' and len(ks) == len(ss):
            for k, st in zip(ks, ss):
                ot = otoks[k]
                ocr = curly(context_text(otoks, k))
                ok = in_vocab(ot.text.strip('"\'()—-,.;:!?*'))
                items[k].update(italic=st.italic, sc=st.sc, block=st.block)
                items[k]['choice'] = choose('word', st.text, ocr, ocr if ok else st.text,
                                            k, context_boxes(otoks, k))
            continue
        if op == 'replace':
            k = ks[0]
            ocr = ' '.join(curly(context_text(otoks, j)) for j in ks)
            se = ' '.join(s.text for s in ss)
            items[k].update(italic=ss[0].italic, sc=ss[0].sc, block=block)
            boxes = [b for j in ks for b in context_boxes(otoks, j)
                     if otoks[j].line is otoks[k].line]
            items[k]['choice'] = choose('words', se, ocr, ocr if vocab_ok else se, k, boxes)
            # (Each OCR word in the block of the SE word it matches, the
            # rest in their neighbours': a run across a block's end.)
            sm2 = difflib.SequenceMatcher(None, [otoks[j].core for j in ks],
                                          [t.core for t in ss], autojunk=False)
            match = {}
            for a2, b2, size in sm2.get_matching_blocks():
                for d in range(size):
                    match[a2 + d] = ss[b2 + d].block
            last_block = None
            for n2, j in enumerate(ks):
                blk = match.get(n2, last_block)
                if blk is None:
                    blk = next((match[m] for m in range(n2, len(ks)) if m in match), block)
                items[j].update(block=blk)
                last_block = blk
            # (SE's words over the OCR words' lines, where they run on to
            # the next: each where its OCR word is.)
            if len({otoks[j].line['id'] for j in ks}) > 1:
                items[k]['region'] = (ks, ss)
            continue
        # delete: words the printing has that SE lacks
        for k in ks:
            ot = otoks[k]
            ok = in_vocab(ot.text.strip('"\'()—-,.;:!?*'))
            ocr = curly(context_text(otoks, k))
            items[k].update(block=block)
            items[k]['choice'] = choose('extra', '', ocr, ocr if ok else '', k,
                                        context_boxes(otoks, k))
    # Words without letters: their block the one before.
    last = stoks[0].block
    for it in items:
        if it['block'] is None:
            it['block'] = last
        last = it['block']
    # Italics the scan shows that SE doesn't, or the reverse.
    gray = {}
    cfg = BOOKS[book]
    for it in items:
        t = it['tok']
        if not t.core or len(t.core) < 2:
            continue
        leaf = t.line['leaf']
        if leaf not in gray:
            gray.clear()
            path = scan_path(cfg, leaf)
            gray[leaf] = np.asarray(Image.open(path).convert('L'))
        a = slant(gray[leaf], t.boxes[0])
        if a is None:
            continue
        scan = 'i' if a >= 12 else 'r' if a <= 6 else '?'
        have = 'i' if it['italic'] else 'r'
        if scan != have:
            it['ichoice'] = choose('italic', have, scan, scan if scan != '?' else have,
                                   it['k'], [t.boxes[0]])
    # (A word too short to measure between two italic ones: italic.)
    for n, it in enumerate(items):
        t = it['tok']
        if t.core and len(t.core) < 2 and not it['italic']:
            def side(d):
                j = n + d
                while 0 <= j < len(items) and not items[j]['tok'].core:
                    j += d
                if not 0 <= j < len(items):
                    return False
                o = items[j]
                c = o.get('ichoice')
                return (c.ocr == 'i') if c else o['italic']
            if side(-1) and side(1) and t.line is items[n - 1]['tok'].line:
                it['italic'] = True
    # (A confident slant that its neighbours share settles; a single word
    # that differs alone is reviewed.)
    flips = [it for it in items if 'ichoice' in it]
    flipped = {it['k'] for it in flips}
    for it in flips:
        c = it['ichoice']
        k = it['k']
        def near(d):
            j = k + d
            while 0 <= j < len(items) and not items[j]['tok'].core:
                j += d
            return j in flipped
        if c.ocr != '?' and (near(-1) or near(1)):
            c.value, c.how = c.ocr, 'run'
    return chapters, lines, otoks, items, choices


# ---------------------------------------------------------------- settling

def tesseract(img, box, pad=12):
    x0, y0, x1, y1 = box
    crop = img.crop((max(0, x0 - pad), max(0, y0 - pad), x1 + pad, y1 + pad))
    with tempfile.NamedTemporaryFile(suffix='.png', dir=os.environ.get('TMPDIR')) as f:
        crop.save(f.name)
        r = subprocess.run(['tesseract', f.name, '-', '--psm', '7', '-l', 'eng'],
                           capture_output=True, text=True)
    return r.stdout.strip()


# (A contraction the printing sets apart from its word, `that 's`: a
# punctuation space, the measured gap, the word joiners keeping it on the
# line. Looking-Glass's printing does, for these endings alone.)
SPACED = re.compile(r"(?<=[A-Za-z])’(?=(s|m|re|d|ve)\b)")
APART = '\u2060\u2008\u2060'


def spaced_or_dashed(c):
    """SE's words where the OCR read them but for the printing's ways:
    a dash it lost (`purr no` for `purr⁠—no`), a contraction set apart
    (`I ‘m`); with the contraction apart where the printing sets it so.
    None where the words differ otherwise."""
    def flat(t):
        t = t.replace('\u2060', '').replace('\u2008', ' ').replace('■', ' ')
        t = t.translate(PUNCT_MAP)
        t = re.sub(r'\s*[—–-]{2,}\s*|\s*—\s*', ' ', t)
        return re.sub(r'\s+', ' ', t).strip()
    o, s = flat(c.ocr), flat(c.se)
    if '—' in c.se and o == s:
        return c.se
    apart = SPACED.sub(APART + '’', c.se)
    if apart != c.se and o == re.sub(r"(?<=[A-Za-z])'(?=(s|m|re|d|ve)\b)", " '", s):
        return apart
    return None


def settle(book, choices, use_tesseract):
    cache_path = os.path.join(HERE, 'decisions', f'tesseract-{book}.json')
    cache = json.load(open(cache_path)) if os.path.exists(cache_path) else {}
    decisions = {}
    dpath = os.path.join(HERE, 'decisions', f'{book}.tsv')
    if os.path.exists(dpath):
        for line in open(dpath, encoding='utf-8'):
            line = line.rstrip('\n')
            if not line or line.startswith('#'):
                continue
            cid, _, value = line.partition('\t')
            decisions[cid] = value
    cfg = BOOKS[book]
    images = {}
    for c in choices:
        if c.id in decisions:
            c.value, c.how = decisions[c.id], 'review'
            continue
        if c.kind not in ('word', 'words', 'extra'):
            continue
        if c.kind in ('word', 'words') and c.se and cfg.get('apart') \
                and (v := spaced_or_dashed(c)) is not None:
            c.value, c.how = v, 'rule'
            continue
        # (An engraving's hatching read as letters: no word of the
        # vocabulary, its second reading none either.)
        if c.kind == 'extra' and not in_vocab(c.ocr.strip('“”‘’"\'()—-,.;:!?*')) \
                and not re.search(r'[A-Za-z]{2}', c.ocr):
            c.value, c.how = '', 'rule'
            continue
        def read(leaf, box):
            key = f'{leaf}:{box}'
            if key not in cache and use_tesseract:
                if leaf not in images:
                    if len(images) > 2:
                        images.clear()
                    images[leaf] = Image.open(
                        scan_path(cfg, leaf)).convert('L')
                cache[key] = tesseract(images[leaf], box)
            return cache.get(key)
        reading = read(c.line['leaf'], union(c.boxes))
        if reading is not None and getattr(c, 'cont', None):
            line, box = c.cont
            more = read(line['leaf'], box)
            if more is None:
                reading = None
            else:
                # (Joined at the division: its hyphen dropped where the
                # word has none there, as the candidates are compared.)
                reading = reading.rstrip(' |.:') + more
        c.reading = reading
        if reading is None:
            continue
        # (Marks the crop's edges caught, standing apart at its ends.)
        # (Tesseract's spaced question mark: `wonder ?2”`, `then 27`.)
        reading = re.sub(r'(?<=\w) (\?2|27|77|2|7|¢|%)(?=[”’"\s]|$)', ' ?', reading)
        words = reading.split()
        while words and set(words[-1]) <= set('|_~¢«»^`-'):
            words.pop()
        while words and set(words[0]) <= set('|_~¢«»^`'):
            words.pop(0)
        r = norm(' '.join(words))
        def bare(t):
            return re.sub(r'["\']', '', norm(t))
        # (OCR's misread letters: a word not in the vocabulary, much like
        # SE's, which is.)
        if c.kind == 'word' and c.se:
            o_letters = re.sub(r'[^A-Za-z]', '', c.ocr)
            s_letters = re.sub(r'[^A-Za-z]', '', c.se)
            if (not in_vocab(c.ocr.strip('“”‘’"\'()—-,.;:!?*')) and in_vocab(s_letters)
                    and difflib.SequenceMatcher(None, o_letters.lower(), s_letters.lower()).ratio() >= 0.6):
                c.value, c.how = c.se, 'rule'
                continue
            # (A dash the OCR read as two, around a space.)
        if c.kind in ('word', 'words') and c.se:
            def dashless(t):
                return re.sub(r'\s*[—-]+\s*[—-]*\s*', '—', norm(t).replace('\u2060', ''))
            if dashless(c.ocr) == dashless(c.se):
                c.value, c.how = c.se, 'rule'
                continue
        if c.kind == 'word' and c.se:
            # (`I’ll` read `111`, `Fll`; `I’m` read `Fm`.)
            if re.search(r'[’\']', c.se) and re.search(r'(^|[^A-Za-z])(1|11|111|F)(ll|m|ve)?([^A-Za-z]|$)|^\W*F(ll|m|ve)', c.ocr):
                c.value, c.how = c.se, 'rule'
                continue
        # (The next word's opening quotation mark, standing apart, taken
        # for this one's closing: the word without it, where the second
        # reading agrees.)
        if (c.kind == 'word' and c.ocr.endswith('”')
                and getattr(c, 'se_next', '').startswith(('“', '‘'))):
            cand = c.ocr[:-1]
            if bare(' '.join(words)) == bare(cand):
                c.value, c.how = cand, 'rule'
                continue
        if getattr(c, 'cont', None):
            r_joined = r
            se_n, ocr_n = norm(c.se), norm(c.ocr)
            # the division's hyphen: in the reading, maybe not in the word
            if c.se and (r == se_n or r.replace('-', '', 1) == se_n):
                c.value, c.how = c.se, 'tesseract'
                continue
            if c.ocr and (r == ocr_n):
                c.value, c.how = c.ocr, 'tesseract'
                continue
        # (A word divided at the line's end: its first part read.)
        if c.kind in ('word', 'words') and c.boxes and '-' in c.ocr:
            pass
        if c.se and r == norm(c.se):
            c.value, c.how = c.se, 'tesseract'
        elif c.se and c.kind == 'word' and bare(' '.join(words)) == bare(c.se):
            # (Quotation marks apart from the word, the second reading's
            # letters and stops SE's.)
            c.value, c.how = c.se, 'tesseract'
        elif c.ocr and r == norm(c.ocr) and c.kind != 'extra':
            c.value, c.how = c.ocr, 'tesseract'
        elif c.kind == 'extra' and c.ocr and r == norm(c.ocr):
            c.value, c.how = c.ocr, 'tesseract'
    json.dump(cache, open(cache_path, 'w'), ensure_ascii=False)
    # (The italics of words left out don't matter.)
    out_of = {c.line['id'] + ':' + c.id.split(':')[2] for c in choices
              if c.kind == 'extra' and c.get() == ''}
    for c in choices:
        if c.kind == 'italic' and c.value is None and \
                c.line['id'] + ':' + c.id.split(':')[2] in out_of:
            c.value, c.how = 'r', 'rule'


# ---------------------------------------------------------------- writing

def styled(words):
    """Words (text, italic, sc) as markup: a run of italic words in
    `__…__` from its first letter to its last, small capitals in
    `[.sc]##…##`."""
    out = []
    n = len(words)
    i = 0
    while i < n:
        text, italic, sc = words[i]
        if not (italic or sc):
            out.append(text)
            i += 1
            continue
        j = i
        while j + 1 < n and words[j + 1][1] == italic and words[j + 1][2] == sc and words[j + 1][0]:
            j += 1
        run = ' '.join(w[0] for w in words[i:j + 1])
        m1 = SC_RX.search(run)
        m2 = None
        for m2 in SC_RX.finditer(run):
            pass
        if m1 is None:
            out.append(run)
        else:
            a, b = m1.start(), m2.end()
            open_, close = ('__', '__') if italic and not sc else \
                ('[.sc]##', '##') if sc and not italic else ('[.sc]##__', '__##')
            out.append(run[:a] + open_ + run[a:b] + close + run[b:])
        i = j + 1
    return ' '.join(out)


def divided(text, ocr_text, split):
    """[text] marked where the printing divided its word at the line's
    end: `{shy}` after the letters before the division, or `{zwsp}`
    after the word's own hyphen there."""
    letters = len(core(ocr_text[:split]))
    count = 0
    for i, ch in enumerate(text):
        if SC_RX.match(unicodedata.normalize('NFKD', ch)[:1] or ' '):
            count += 1
            if count == letters:
                rest = text[i + 1:]
                if rest.startswith('-'):
                    return text[:i + 2] + '{zwsp}' + text[i + 2:]
                return text[:i + 1] + '{shy}' + rest
    return text


def line_words(items, line_id):
    pass


# The width of a space in the PDF's verse (0.28 em of Old Standard TT) in
# the scan's pixels, at the size whose x-height is the printing's.
VERSE_PT = 10     # the verse's size (and the asterisks')
LEADS = set()     # the leaded stanzas' pitch roles used
SPACE_PX = 0.28 * VERSE_PT * DPI / 72


def text_lefts(lines):
    """Each leaf's text edge: where its full lines start."""
    by_leaf = {}
    for l in lines:
        if l['kind'] != 'body':
            continue
        x0, _, x1, _ = l['box']
        by_leaf.setdefault(l['leaf'], []).append((x0, x1 - x0))
    out = {}
    for leaf, rows in by_leaf.items():
        widest = max(w for _, w in rows)
        full = sorted(x for x, w in rows if w >= 0.9 * widest and widest > 1900)
        if full and BOOKS[BOOK].get('left_from_least'):
            # (The lines that start at the edge, not a paragraph's first,
            # set in: those near the least start.)
            full = [x for x in full if x < full[0] + 60]
        if full:
            out[leaf] = full[len(full) // 2]
    for leaf in by_leaf:
        if leaf not in out:
            same = [v for k, v in out.items() if k % 2 == leaf % 2]
            out[leaf] = sorted(same)[len(same) // 2] if same else 170
    return out


def verse_italic(bl):
    flags = [w[1] for _, lid, ws in bl if '+' not in lid and lid not in OVERRIDDEN
             for w in ws if re.search(r'[A-Za-z]', w[0])]
    return bool(flags) and sum(flags) >= 0.6 * len(flags)


LEAF_PITCH = json.load(open(os.path.join(ROOT, f'pitch-{BOOK}.json')))
PROSE_PT = 11.2   # the text's size


def leaf_pt(leaf, px):
    """[px] of the scan of [leaf] in points, the leaf's own scale made the
    printing's (its line pitch PITCH_PX)."""
    pitch = LEAF_PITCH.get(str(leaf), PITCH_PX)
    return px * PITCH_PX / pitch * PT


from fontTools.ttLib import TTFont
_FACES = {}


def width_em(text, italic):
    """[text]'s width in ems of Old Standard TT (its advances)."""
    style = 'Italic' if italic else 'Regular'
    if style not in _FACES:
        f = TTFont(os.path.join(os.environ.get('PTOME_FONTS', os.path.expanduser('~/.local/share/fonts/ptome')), f'OldStandardTT-{style}.ttf'))
        _FACES[style] = (f.getBestCmap(), f['hmtx'])
    cmap, hmtx = _FACES[style]
    return sum(hmtx[cmap[ord(c)]][0] if ord(c) in cmap else 500 for c in text) / 1000


def verse_metrics(size, pitch):
    """A verse line's room above and below its baseline (ptome's text
    box: its ascent and descent, half its leading each side)."""
    lead = (pitch - size) / 2
    return 0.762 * size + lead, 0.238 * size + lead


def verse_text(b, bl, marked, lines_by_id, lefts, italic=None, around=None):
    """A verse block as the printing sets it: each printed line a line,
    set in by spaces as far as the printing sets it in; each stanza a
    block of its own, its size from its line pitch (the role `v<size>`),
    its spaces above and below the printing's (`margin-top`,
    `margin-bottom`); a poem printed in italic throughout given the role
    `italic`, its words unmarked."""
    rows = []
    at = 0
    for pg, lid, ws in bl:
        rows.append((lid, marked[at:at + len(ws)], ws))
        at += len(ws)
    if italic is None:
        italic = verse_italic(bl)
    # The stanzas: where the printing leaves a gap.
    stanzas = [[]]
    prev = None
    for row in rows:
        line = lines_by_id[row[0].split('+')[0]]
        # (A new stanza where the printing leaves a gap, or turns the page:
        # the next page's lines a block of their own, placed as that page
        # places them.)
        if prev is not None and '+' not in row[0] and (
                line['leaf'] != prev['leaf'] or line['box'][1] - prev['box'][1] > 1.45 * 137):
            stanzas.append([])
        stanzas[-1].append(row)
        prev = line
    out = []
    before = around[0] if around else None
    for k, stanza in enumerate(stanzas):
        ls = [lines_by_id[lid.split('+')[0]] for lid, _, _ in stanza]
        tops = [l['box'][1] for l in ls]
        diffs = sorted(b2 - a2 for a2, b2 in zip(tops, tops[1:]) if 0 < b2 - a2 < 180)
        pitch_px = diffs[len(diffs) // 2] if diffs else 137
        pitch = leaf_pt(ls[0]['leaf'], pitch_px)
        size = round(pitch / 1.52 * 2) / 2
        # (Within half a point of the poems' 10: the poems' size, the rest
        # measurement's noise; their pitch the chapters' poems' 15.2, or
        # the prefatory poem's 15.6, a role of its own, `loose`.)
        if 9.25 <= size <= 10.75:
            size = 10.0
        loose = size == 10.0 and ls[0]['leaf'] in BOOKS_FRONT
        pitch = 15.57 if loose else size * 1.52
        lead = None
        if BOOKS[BOOK].get('verse_leaded') and len(ls) > 1:
            # (Its type the poems' 10 pt, its lines as far apart as the
            # printing leads them: a role of their pitch, `lh<tenths>`.)
            pitch = round(leaf_pt(ls[0]['leaf'], pitch_px), 1)
            size = 10.0
            lead = f'lh{int(round(pitch * 10))}'
            LEADS.add(lead)
        asc, desc = verse_metrics(size, pitch)
        attrs = []
        # (Its space above: from the line before, on its page, unless a
        # cut stands between them.)
        if before is not None and before['leaf'] == ls[0]['leaf'] and \
                not (k == 0 and ls[0]['id'] in CUT_TARGETS):
            gap = leaf_pt(ls[0]['leaf'], ls[0]['box'][1] - before['box'][1])
            if k == 0:
                below_prev = 0.238 * PROSE_PT + (GRID - PROSE_PT) / 2
            else:
                below_prev = prev_desc
            attrs.append(f'margin-top={max(0, gap - below_prev - asc):.1f}pt')
        elif not (k == 0 and ls[0]['id'] in CUT_TARGETS):
            # (At the top of its page: as far down as the printing sets it,
            # by a spacer in the PDF, a page's top margin dropped.)
            top = baseline_pt(ls[0], size) - asc - PAGE_TOP
            if top > 0.5:
                out += ['ifdef::backend-pdf[]',
                        f'image::blank.svg["",role=cut,pdfwidth=1pt,pdfheight={top:.1f}pt]',
                        'endif::[]', '']
        # (Below: to the line after, after the last stanza.)
        after = around[1] if around else None
        if k == len(stanzas) - 1 and after is not None and after['leaf'] == ls[-1]['leaf'] \
                and after['id'] not in CUT_TARGETS:
            gap = leaf_pt(ls[-1]['leaf'], after['box'][1] - ls[-1]['box'][1])
            above_next = 0.762 * PROSE_PT + (GRID - PROSE_PT) / 2
            attrs.append(f'margin-bottom={max(0, gap - desc - above_next):.1f}pt')
        else:
            attrs.append('margin-bottom=0')
        role = 'v' + (f'{size:.1f}'.replace('.0', '').replace('.', ''))
        # (One attribute line: the style, SE's roles, the size's, italic.)
        roles = []
        style = 'verse'
        for h in b['head'][:-1]:
            m = re.fullmatch(r'\[([a-z]*)((?:\.[\w-]+)*)(%\w+)?\]', h.strip())
            if m:
                style = m.group(1) or style
                roles += [r for r in m.group(2).split('.') if r]
        roles += [role] + ([lead] if lead else []) + (['loose'] if loose else []) + (['italic'] if italic else [])
        # (The prefatory poem's stanzas whole, as the printing keeps them:
        # one it turns the page in is two blocks already; a chapter's verse
        # broken where its lines fall, its last line in the foot's margin
        # as the printing has it.)
        keep = '%unbreakable' if loose else ''
        out.append(f'[{style}.{".".join(roles)}{keep}{"".join("," + a for a in attrs)}]')
        out.append(b['head'][-1])
        space_px = 0.28 * size / PT
        for lid, words, ws in stanza:
            line = lines_by_id[lid.split('+')[0]]
            text = ' '.join(words)
            if italic:
                text = text.replace('__', '')
            spaces = max(0, round((line['box'][0] - lefts[line['leaf']]) / space_px))
            # (A line Old Standard sets wider than the measure, where the
            # printing's face fits it: tracked in a little, `tight`.)
            plain = re.sub(r'__|\[\.[a-z0-9-]+\]#+|#', '', text)
            if (spaces * 0.28 + width_em(plain, italic)) * size > MEASURE * PT:
                text = f'[.tight]#{text}#'
            out.append(' ' * spaces + text)
        out.append('____')
        out.append('')
        before = ls[-1]
        prev_desc = desc
    return '\n'.join(out).rstrip('\n')


OVERRIDDEN = set()
CUT_TARGETS = set()   # the lines a cut is set before
BOOKS_FRONT = set(BOOKS[BOOK].get('front_leaves', []))

# The tale's first line on the paragraph's last: back up one line.
TALE_MARGIN = -14.4

PT = 72 / DPI     # the scan's pixels in points
PITCH = BOOKS[BOOK].get('layout_pitch', 151)       # the printing's line pitch in pixels
GRID = 16.82     # the PDF's line pitch (the look's leading), the printing's 151.9 px, in points
MEASURE = BOOKS[BOOK].get('measure', 2256)    # its measure


def indented(line, lefts, cut):
    """Whether [line] starts a paragraph set in (beside a cut, from the
    edge of the lines beside it)."""
    edge = cut.get('text_left', lefts[line['leaf']])
    return line['box'][0] - edge > 0.4 * PITCH


PROSE_ASC = 0.762 * 11.2 + (16.82 - 11.2) / 2     # a prose line's room above its baseline
PROSE_DESC = 0.238 * 11.2 + (16.82 - 11.2) / 2    # and below
VERSE_ASC, VERSE_DESC = 0.762 * 10 + 2.6, 0.238 * 10 + 2.6
PAGE_TOP = 48.8


def baseline_pt(line, size):
    """[line]'s baseline down the page in points, from its OCR box's top
    (its ascenders, 0.8 of its size above the baseline)."""
    return line['box'][1] * PT + 0.8 * size


def place_cuts(book, lines, block_lines, lefts, verse_ids=frozenset()):
    """Where each cut goes and how it is set, from its box on the scan:
    `target`, the line it goes before (beside it, or after it); `chapter`
    for a cut above or beside its chapter's heading; its width, height,
    float side and gap in points."""
    cuts = json.load(open(f'{ROOT}/cuts-{book}.json'))
    present = {lid for bl in block_lines.values() for _, lid, _ in bl}
    by_leaf = {}
    chapter_lines = {}
    count = 0
    for l in lines:
        if l['kind'] == 'body' and l['id'] in present:
            by_leaf.setdefault(l['leaf'], []).append(l)
        if l['kind'] == 'chapter':
            count += 1
            chapter_lines[l['leaf']] = (count, l)
    # (A page's text top and bottom: where its first and twenty-second
    # lines start, on a full page.)
    tops = sorted(ls[0]['box'][1] for ls in by_leaf.values() if len(ls) >= 20)
    top0 = tops[len(tops) // 2]
    for c in cuts:
        x0, y0, x1, y1 = c['box']
        leaf = c['leaf']
        if leaf not in lefts:
            # (A page of a cut alone: its text edge its side's.)
            same = sorted(v for k, v in lefts.items() if k % 2 == leaf % 2)
            lefts[leaf] = same[len(same) // 2]
        left = lefts[leaf]
        right = left + MEASURE
        ls = sorted(by_leaf.get(leaf, []), key=lambda l: l['box'][1])
        beside = [l for l in ls if l['box'][1] < y1 - 30 and l['box'][3] > y0 + 30]
        c['width'] = (x1 - x0) * PT
        if BOOKS[book].get('cut_within_measure'):
            # (A drawing a little wider than the measure, its hatching
            # reaching past the text: the measure's width, as the layout
            # would push it off its page otherwise.)
            c['width'] = min(c['width'], MEASURE * PT)
        if leaf in chapter_lines and y0 < chapter_lines[leaf][1]['box'][1]:
            c['chapter'] = chapter_lines[leaf][0]
        if beside:
            # (The lines beside it: on above and below while they keep to
            # the column beside it; each line's edges its words', specks
            # the OCR read in the cut left out.)
            def real(w):
                return core(w['t']) and in_vocab(w['t'].strip().strip('"\'()—-,.;:!?*‘’“”'))
            def x_left(l):
                xs = [w['b'][0] for w in l['words'] if real(w)]
                return min(xs) if xs else l['box'][0]
            def x_right(l):
                xs = [w['b'][2] for w in l['words'] if real(w)]
                return max(xs) if xs else l['box'][2]
            xs = [x_left(l) for l in beside]
            on_left = min(xs) > x0 + 100
            edge = min(x1, min(xs)) - 40
            def aside(l):
                return x_left(l) > edge if on_left else x_right(l) < x0 + 40
            i = ls.index(beside[0])
            while i > 0 and aside(ls[i - 1]):
                i -= 1
            j = ls.index(beside[-1])
            # (Not past the drawing's foot: a short line below it, a
            # paragraph's last, is across the page.)
            while j + 1 < len(ls) and aside(ls[j + 1]) and (
                    not BOOKS[book].get('beside_within_cut') or ls[j + 1]['box'][1] < y1 + 0.3 * PITCH):
                j += 1
            beside = ls[i:j + 1]
            xs = [x_left(l) for l in beside]
            # (Its upper or lower part across the page: an L or a Γ.)
            spans = x1 > min(xs) + 40
            below = spans and y1 > beside[-1]['box'][3] + 0.5 * PITCH
            above = spans and y0 < beside[0]['box'][1] - 0.5 * PITCH
            # (Where the drawing meets the text beside it: its tight box's
            # edge, or the text's less the usual gap where that box runs
            # under the text.)
            inner_x1 = c.get('inner', c['box'])[2]
            side_x1 = inner_x1 if inner_x1 < min(xs) - 20 else min(xs) - 81
            if on_left and above:
                # (A cut across the page above the text beside its lower
                # part: drawn whole from a float across the page, the
                # part beside the text a spacer's.)
                c['side'] = 'left'
                # (Wider than the measure: the layout clamps it to the
                # measure, no room left beside it.)
                c['float_width'] = 2 * MEASURE * PT
                c['gap'] = 0
                c['overflow'] = True
                first = beside[0]['box'][1]
                c['height'] = max(1, round((first - top0) / PITCH)) * GRID + 0.1 \
                    if y0 < top0 + PITCH else max(1, round((first - y0) / PITCH)) * GRID + 0.1
                c['under'] = dict(float_width=(side_x1 - left) * PT,
                                  gap=(min(xs) - side_x1) * PT,
                                  height=len(beside) * GRID + 0.1)
                c['text_left'] = min(xs)
            elif on_left and below:
                # (A cut the text runs beside in part, its lower part
                # across the page: drawn whole from a float as wide as its
                # upper part, a spacer the height of the rest under it.)
                c['side'] = 'left'
                c['float_width'] = (side_x1 - left) * PT
                c['gap'] = (min(xs) - side_x1) * PT
                c['text_left'] = min(xs)
                c['overflow'] = True
                after = [l for l in ls if l['box'][1] > y1 - 10]
                below = after[0]['box'][1] if after else top0 + 22 * PITCH
                rest = below - (beside[-1]['box'][1] + PITCH)
                c['spacer'] = max(1, round(rest / PITCH)) * GRID
            elif on_left:
                c['side'] = 'left'
                c['float_width'] = (side_x1 - left) * PT
                c['gap'] = (min(xs) - side_x1) * PT
                c['text_left'] = min(xs)
            else:
                c['side'] = 'right'
                c['float_width'] = (right - x0) * PT
                c['gap'] = (x0 - max(x_right(l) for l in beside)) * PT
            # (As tall as its lines: each line beside it whole, the next
            # below it.)
            # (A tenth of a point to spare: rounded, its lines might not.)
            if 'under' not in c:
                c['height'] = len(beside) * GRID + 0.1
            if 'chapter' in c:
                # (Before its chapter's heading, from the page's top: down
                # to the slot of its last line.)
                c['height'] = (round((beside[-1]['box'][1] - top0) / PITCH) + 1) * GRID + 0.1
            if 'chapter' not in c:
                c['target'] = beside[0]['id']
        else:
            prev = [l for l in ls if l['box'][3] < y0 + 10]
            nxt = [l for l in ls if l['box'][1] > y1 - 10]
            top = prev[-1]['box'][1] + PITCH if prev else top0
            bottom = nxt[0]['box'][1] if nxt else top0 + 22 * PITCH
            # (A chapter's cut above its heading: its own height, the
            # heading's spaces the look's.)
            # (In whole lines, the text after it on the grid; next to verse,
            # from the baselines either side.)
            if 'chapter' in c:
                c['height'] = (y1 - y0) * PT
            elif (nxt and nxt[0]['id'] in verse_ids) or (prev and prev[-1]['id'] in verse_ids):
                if nxt:
                    v = nxt[0]['id'] in verse_ids
                    end = baseline_pt(nxt[0], 10 if v else 11.2) - (VERSE_ASC if v else PROSE_ASC)
                else:
                    end = PAGE_TOP + 22 * GRID
                if prev:
                    v = prev[-1]['id'] in verse_ids
                    start = baseline_pt(prev[-1], 10 if v else 11.2) + (VERSE_DESC if v else PROSE_DESC)
                else:
                    start = PAGE_TOP
                c['height'] = end - start
                c['exact'] = True
                c['start'] = start
            else:
                c['height'] = max(1, round((bottom - top) / PITCH)) * GRID
            mid = (x0 + x1) / 2 - (left + right) / 2
            c['align'] = 'center' if abs(mid) < 80 else 'left' if mid < 0 else 'right'
            if 'chapter' not in c:
                if nxt:
                    c['target'] = nxt[0]['id']
                else:
                    # (At the page's foot: before the next page's first line.)
                    later = [l for k in sorted(by_leaf) if k > leaf for l in by_leaf[k]]
                    c['target'] = later[0]['id'] if later else None
        # Where the drawing stands in its box, from the scan: the box's
        # top the line's top beside or below it (its OCR top less 3.7 pt,
        # a line's room above its ascenders), or the line's end above it
        # (its OCR top and 13.12 pt), or the page's top.
        if 'chapter' not in c:
            leaf_px = lambda px: leaf_pt(leaf, px)
            ls_prev = [l for l in ls if l['box'][3] < y0 + 10]
            if 'side' in c and 'under' not in c:
                ref = beside[0]['box'][1]
                fit = leaf_px(y0 - ref) + 3.70
            elif c.get('exact'):
                fit = y0 * PT - c['start']
            elif ls_prev:
                fit = leaf_px(y0 - ls_prev[-1]['box'][1]) - 13.12
            else:
                fit = leaf_px(y0 - top0) + 3.70
            drawn = c['width'] * (y1 - y0) / max(1, x1 - x0)
            if not c.get('overflow'):
                fit = min(fit, c['height'] - drawn)
            c['fit_top'] = max(0.0, fit)
    json.dump(cuts, open(f'{ROOT}/placed-{book}.json', 'w'), indent=0)
    return cuts


def stars_block(rows, left, ys=None, lid=None, lines_by_id=None):
    """The printing's rows of asterisks as a verse block, each star set
    in by spaces to where the printing has it; with [ys], each row's
    centre down the scan, its rows as far apart and as far from the
    lines either side as the printing sets them (a leaded role, `lh<n>`)."""
    star = 0.502 / 0.28   # an asterisk's width in spaces
    out = ['[verse.stars]', '____']
    if ys:
        line = lines_by_id[lid]
        leaf = line['leaf']
        nxt = [l for l in lines_by_id.values() if l['leaf'] == leaf and l['kind'] == 'body'
               and l['box'][1] > ys[-1]]
        pitch = round(leaf_pt(leaf, (ys[-1] - ys[0]) / (len(ys) - 1)), 1)
        lead = f'lh{int(round(pitch * 10))}'
        LEADS.add(lead)
        # (A star's middle half a line's height less 1.9 pt below its line's
        # top; a prose line's foot 14 pt below its letters' top.)
        top = leaf_pt(leaf, ys[0] - line['box'][1]) - 14.0 - (pitch / 2 - 1.9)
        bottom = (leaf_pt(leaf, min(l['box'][1] for l in nxt) - ys[-1]) - (pitch / 2 + 1.9) - 2.8
                  if nxt else 0)
        out[0] = f'[verse.stars.{lead},margin-top={top:.1f}pt,margin-bottom={max(0, bottom):.1f}pt]'
    for row in rows:
        line = ''
        at = 0.0
        for x in row:
            want = (x - left) / SPACE_PX - star / 2
            n = max(1 if line else 0, round(want - at))
            line += ' ' * n + '*'
            at += n + star
        out.append(line)
    out.append('____')
    return '\n'.join(out)


def opening_word(out, n, lines_by_id, caps=True, words=1):
    """The chapter's first paragraph as the printing opens it: its first
    word in capitals and small capitals (`[.sc]`; chapter VIII's first two),
    chapter I's in capitals after a larger initial (`[.initial]`,
    `[.caps]`); indented (`[.indent]`) where the printing indents it. A
    paragraph in two branches (a page the printing ends early) styled in
    both."""
    word_rx = re.compile(r'^([“‘(]*)([A-Za-z’]+' + r'(?: [A-Za-z’]+)' * (words - 1) + r')(.*)$')

    def style(row):
        m = word_rx.match(row)
        if not m:
            return row
        lead, word, rest = m.groups()
        if n == 1:
            return f'{lead}[.initial]##{word[0]}##[.caps]##{word[1:]}##{rest}'
        return f'{lead}[.sc]##{word}##{rest}' if caps else row

    for k, chunk in enumerate(out):
        rows = chunk.split('\n')
        if not rows or rows[0].startswith(('[#', '==', 'image::', '[verse')):
            continue
        # (Each branch's first line of text: past directives, comments,
        # attribute lines.)
        firsts = []
        expect = True
        for i, r in enumerate(rows):
            if r.startswith(('ifdef::', 'ifndef::')):
                expect = True
                continue
            if r.startswith(('//', '[', 'endif::')) or not r.strip():
                continue
            if expect:
                firsts.append(i)
                expect = False
        if not firsts:
            continue
        for i in reversed(firsts):
            rows[i] = style(rows[i])
            if n != 1 and not any(r == '[.indent]' for r in rows[max(0, i - 3):i]):
                rows.insert(i, '[.indent]')
        out[k] = '\n'.join(rows)
        return out
    return out


# (What the end lines' margins are off by in the PDF, measured: the
# OCR's estimate of the last text line's baseline is the scan's, the PDF's
# on its grid.)
END_FIT = {'the-end': 4.3, 'imprint': 8.0}


def end_blocks(end_lines, lines_by_id, block_lines):
    """The lines the printing sets apart at the book's end ("THE END.",
    the printer's imprint), each a block of its role, as far below the
    line before as the printing sets it."""
    present = sorted({lid for bls in block_lines.values() for _, lid, _ in bls if '+' not in lid},
                     key=lambda l: tuple(int(x) for x in l.split(':')))
    sizes = {'the-end': 8.5, 'imprint': 6.5}
    out = []
    prev = lines_by_id[present[-1]]
    prev_bottom = baseline_pt(prev, 11.2) + PROSE_DESC
    for lid, role in end_lines.items():
        line = lines_by_id[lid]
        size = sizes[role]
        text = ' '.join(w['t'].strip() for w in line['words'] if w['t'].strip())
        if role == 'imprint':
            # (`{empty}`: not an ordered list's `R.`.)
            text = '{empty}R. Clay, Son, and Taylor, Printers, Bread Street Hill.'
        cap = (line['box'][3] - line['box'][1]) * PT
        base = line['box'][1] * PT + cap
        lead = size * (1.50179 - 1) / 2 if role != 'imprint' else 0
        asc = 0.762 * size + lead
        # (No lower than the page's last line can go: the imprint in the
        # printing's foot margin, a point or two higher.)
        base = min(base, PAGE_TOP + 21 * GRID + 0.762 * 11.2 + 2.8 - 0.238 * size)
        margin = base - asc - prev_bottom + END_FIT[role]
        out.append(f'[.{role},margin-top={margin:.1f}pt,margin-bottom=0]\n{text}')
        prev_bottom = base + 0.238 * size + lead
    return out


def cut_macro(c, se_images):
    target, alt = se_images[c['n']]
    roles = []
    attrs = []
    if 'chapter' in c:
        roles.append('opener')
    if 'side' in c:
        roles.append(f'cut-{c["side"]}')
        attrs += [f'float-width={c["float_width"]:.1f}pt', f'float-gap={c["gap"]:.1f}pt',
                  f'align={"right" if c["side"] == "left" else "left"}']
        if c.get('overflow'):
            attrs.append('fit=none')
    else:
        roles.append('cut')
        attrs.append(f'align={c["align"]}')
    if 'fit_top' in c:
        attrs.append(f'fit-top={c["fit_top"]:.1f}pt')
    attrs = [f'id={target[:-4]}', f'role="{" ".join(roles)}"' if len(roles) > 1 else f'role={roles[0]}',
             f'pdfwidth={c["width"]:.1f}pt', f'pdfheight={c["height"]:.1f}pt'] + attrs
    macro = f'image::{target}["{alt}",{",".join(attrs)}]'
    if c.get('under'):
        # (The part the text runs beside, under the cut drawn across the
        # page, in the PDF alone.)
        u = c['under']
        macro += ('\n\nifdef::backend-pdf[]\n'
                  f'image::blank.svg["",role=cut-{c["side"]},float-width={u["float_width"]:.1f}pt,'
                  f'float-gap={u["gap"]:.1f}pt,pdfwidth=1pt,pdfheight={u["height"]:.1f}pt]\n'
                  'endif::[]')
    if c.get('spacer'):
        # (The room the cut's lower part takes across the page, in the PDF
        # alone.)
        macro += ('\n\nifdef::backend-pdf[]\n'
                  f'image::blank.svg["",role=cut-{c["side"]},float-width={2 * MEASURE * PT:.1f}pt,'
                  f'float-gap=0,pdfwidth=1pt,pdfheight={c["spacer"]:.1f}pt]\n'
                  'endif::[]')
    return macro



def line_overrides(book):
    out = {}
    dpath = os.path.join(HERE, 'decisions', f'{book}.tsv')
    if os.path.exists(dpath):
        for line in open(dpath, encoding='utf-8'):
            cid, _, value = line.rstrip('\n').partition('\t')
            if cid.startswith('line:'):
                out[cid[5:]] = value
    return out


def apply_patches(book, name, text):
    """[text] with decisions/BOOK.patches applied: a block that the
    transcription can't make from its lines (a sum set as a table, a
    verse block's continuation), as the printing sets it. Each patch:
    `@@ NAME`, the text as drafted, `=>`, the text as it should be, `@@`.
    A patch that doesn't apply stops the draft."""
    # (Standard Ebooks' scene break, read into the line before it: the
    # printing's rows of asterisks stand for it.)
    text = re.sub(r" '''$", '', text, flags=re.M)
    path = os.path.join(HERE, 'decisions', f'{book}.patches')
    if not os.path.exists(path):
        return text
    for m in re.finditer(r'^@@ (\S+)\n(.*?)\n=>\n(.*?)\n@@$', open(path, encoding='utf-8').read(), re.S | re.M):
        if m[1] != name:
            continue
        # (The draft's measures, `margin-top=58.0pt`, as they come: a
        # patch matches whatever they are.)
        parts = re.split(r'(?<=-top=|ttom=)[\d.]+(?=pt)', m[2])
        pattern = r'[\d.]+'.join(re.escape(p) for p in parts)
        assert re.search(pattern, text), (name, m[2])
        text = re.sub(pattern, lambda _: m[3], text)
    return text


def write(book, chapters, lines, otoks, items, choices):
    overrides = line_overrides(book)
    OVERRIDDEN.update(overrides)
    by_line = {}
    for it in items:
        by_line.setdefault(it['tok'].line['id'], []).append(it)
    # Each block's printed lines: [(page, line id, words)]
    block_lines = {}
    done_overrides = set()
    end_lines = BOOKS[book].get('end_lines', {})
    for line in lines:
        if line['kind'] != 'body' or line['id'] in end_lines:
            continue
        if line['id'] in overrides:
            # (A line reviewed whole: its text as given, in the block of its
            # first word; once, where the OCR read it as two lines of one
            # id; none, given empty, where its words are another line's.)
            first = next((it for it in by_line.get(line['id'], []) if it['tok'].core), None)
            if first is None or line['id'] in done_overrides or not overrides[line['id']]:
                continue
            done_overrides.add(line['id'])
            bl = block_lines.setdefault(id(first['block']), [])
            # (`\n` in it: a line the OCR missed, after this one.)
            for n, text in enumerate(overrides[line['id']].split('\\n')):
                bl.append([line['page'], line['id'] + ('' if n == 0 else f'+{n}'),
                           [(w, False, False) for w in text.split()]])
            continue
        for it in by_line.get(line['id'], []):
            c = it['choice']
            text = c.get() if c else it['text']
            if it.get('spread') is not None:
                text = it['spread']
            elif 'region' in it and c.get() == c.se:
                # SE's words spread over the region's OCR words' lines.
                ks, ss = it['region']
                # (Each SE word in pieces after its dashes, `woman⁠—` `but`,
                # for a line may end after one.)
                pieces = []
                for n, t in enumerate(ss):
                    for piece in re.findall(r'[^—]*—+(?=.)|[^—]+$|[^—]*—+$', t.text):
                        pieces.append((n, piece))
                sm = difflib.SequenceMatcher(None, [otoks[j].core for j in ks],
                                             [core(p) for _, p in pieces], autojunk=False)
                at = [None] * len(pieces)
                for a, b, size in sm.get_matching_blocks():
                    for d in range(size):
                        at[b + d] = a + d
                last = 0
                where = []
                for m, _ in enumerate(pieces):
                    if at[m] is not None:
                        last = at[m]
                    where.append(last)
                spread = {j: [] for j in ks}
                for n, t in enumerate(ss):
                    mine = [m for m, (o, _) in enumerate(pieces) if o == n]
                    text = ''
                    for m in mine:
                        if text and otoks[ks[where[m]]].line is not otoks[ks[where[mine[0]]]].line \
                                and '{zwsp}' not in text:
                            text += '{zwsp}'
                        text += pieces[m][1]
                    spread[ks[where[mine[0]]]].append(text)
                for j in ks:
                    items[j]['spread'] = ' '.join(spread[j])
                text = it['spread']
            italic = it['italic']
            if 'ichoice' in it:
                v = it['ichoice'].get()
                italic = italic if v == '?' else (v == 'i')
            sc = it['sc']
            # (Small capitals in SE, capitals in the printing.)
            letters = re.sub(r'[^A-Za-z]', '', it['tok'].text)
            if sc and text and len(letters) >= 1 and letters.isupper():
                text, sc = text.upper(), False
            if text and it['tok'].split is not None:
                text = divided(text, it['tok'].text, it['tok'].split)
            words = [(w, italic, sc) for w in text.split()] if text else []
            for ic, ss in it['inserts']:
                if ic.get():
                    words += [(s.text, s.italic, s.sc) for s in ss]
            if not words:
                continue
            key = id(it['block'])
            bl = block_lines.setdefault(key, [])
            if not bl or bl[-1][1] != line['id']:
                bl.append([line['page'], line['id'], []])
            bl[-1][2].extend(words)
    os.makedirs(f'{ROOT}/out/{book}', exist_ok=True)
    report = []
    debug = []
    lines_by_id = {l['id']: l for l in lines}
    lefts = text_lefts(lines)
    order = [l['id'] for l in lines if l['kind'] == 'body']
    where = {lid: n for n, lid in enumerate(order)}

    def around_of(seg):
        """The printed lines just before and after [seg]'s, with text."""
        present = {lid for bls in block_lines.values() for _, lid, _ in bls}
        first, last = seg[0][1].split('+')[0], seg[-1][1].split('+')[0]
        i = where[first] - 1
        while i >= 0 and order[i] not in present:
            i -= 1
        j = where[last] + 1
        while j < len(order) and order[j] not in present:
            j += 1
        return (lines_by_id[order[i]] if i >= 0 else None,
                lines_by_id[order[j]] if j < len(order) else None)
    verse_ids = {lid for ch in chapters for b in ch['blocks'] if b['kind'] == 'verse'
                 for _, lid, _ in block_lines.get(id(b), [])}
    cuts = place_cuts(book, lines, block_lines, lefts, verse_ids)
    # Whether each chapter's first word is in capitals in the printing.
    opening_caps = {}
    count = 0
    for i, l in enumerate(lines):
        if l['kind'] == 'chapter':
            count += 1
            body = next((m for m in lines[i + 1:] if m['kind'] == 'body'), None)
            if body:
                word = next((w['t'].strip() for w in body['words'] if core(w['t'])), '')
                letters = re.sub(r'[^A-Za-z]', '', word)
                opening_caps[count] = len(letters) > 1 and letters[1:].isupper()
    CUT_TARGETS.clear()
    CUT_TARGETS.update(c['target'] for c in cuts if c.get('target'))
    # Each chapter's sink: its "CHAPTER" line's baseline from the page's
    # top, in points (its caps 0.96 of its OCR box).
    sinks = {}
    count = 0
    for l in lines:
        if l['kind'] == 'chapter':
            count += 1
            x0, y0, x1, y1 = l['box']
            sinks[count] = round((y0 + 0.96 * (y1 - y0)) * PT)
    by_target = {c['target']: c for c in cuts if c.get('target')}
    openers = {c['chapter']: c for c in cuts if c.get('chapter')}
    se_images = {}
    for ch in chapters:
        for b in ch['blocks']:
            m = re.match(r'image::(\S+?-illustration-(\d+)\.svg)\["([^"]*)"', b['raw'][0]) \
                if b['kind'] == 'other' else None
            if m:
                se_images[int(m.group(2))] = (m.group(1), m.group(3))
    pending_break = []
    force_indent = []
    last_number = max(ch['number'] for ch in chapters if ch['number'])
    for ch in chapters:
        n = ch['number']
        out = []
        page = None
        for b in ch['blocks']:
            if b['kind'] == 'other' or not b['toks']:
                if b['raw'][0].startswith('image::'):
                    continue  # (placed where the printing has it)
                if any('verse.tale' in r for r in b['raw']):
                    import tale
                    # (Tagged from the paragraph whose last line it shares:
                    # the excerpt's.)
                    out[-1] = '// tag::tale[]\n' + out[-1]
                    out.append(tale.block(TALE_MARGIN))
                    continue
                raw = list(b['raw'])
                if raw[0].startswith('[#') and raw[-1].startswith('=='):
                    # (Its running title, and its heading sunk as far as the
                    # printing sinks it: the role `sink-<points>`.)
                    attrs = [f'running-title="{BOOKS[book]["running"][n - 1]}"',
                             f'role={BOOKS[book].get("opening_role", "opening")}{n}']
                    raw[0] = raw[0][:-1] + ',' + ','.join(attrs) + ']'
                out.append('\n'.join(raw))
                if b['raw'][-1].startswith('==') and n in openers:
                    out.append(cut_macro(openers[n], se_images))
                continue
            bl = block_lines.get(id(b), [])
            if not bl:
                report.append(f'chapter {n}: a block the printing lacks: {b["raw"][0][:60]}')
                continue
            if pending_break:
                # (A page the printing ends after a paragraph, the next
                # starting as far down its page as the printing sets it.)
                first_line = lines_by_id[bl[0][1].split('+')[0]]
                sink = baseline_pt(first_line, 11.2) - PROSE_ASC - PAGE_TOP
                out.append('\n'.join(['ifdef::backend-pdf[]', '<<<', ''] + (
                    [f'image::blank.svg["",role=cut,pdfwidth=1pt,pdfheight={sink:.1f}pt]']
                    if sink > 0.5 else []) + ['endif::[]']))
                pending_break.clear()
                if b['kind'] == 'para' and first_line['box'][0] - lefts[first_line['leaf']] > 0.4 * PITCH:
                    force_indent.append(True)
            # (The markup across the block's lines: styled as one, then cut
            # where its lines end.)
            flat = [w for _, _, ws in bl for w in ws]
            marked = styled(flat).split(' ')
            assert len(marked) == len(flat), (len(marked), len(flat))
            italic = verse_italic(bl) if b['kind'] != 'para' else None
            # The block in pieces where the printing sets a cut in it.
            pieces = [[]]
            at = 0
            for k, (pg, lid, ws) in enumerate(bl):
                debug.append(f'{lid}\t{" ".join(marked[at:at + len(ws)])}')
                if lid in by_target:
                    pieces.append(('cut', by_target[lid]))
                    pieces.append([])
                pieces[-1].append((pg, lid, ws, marked[at:at + len(ws)]))
                at += len(ws)
                if lid in BOOKS[book].get('stars', {}):
                    pieces.append(('stars', BOOKS[book]['stars'][lid], lid))
                    pieces.append([])
            first_piece = True
            for piece in pieces:
                if isinstance(piece, tuple) and piece[0] == 'stars':
                    out.append(stars_block(piece[1], lefts[int(piece[2].split(':')[0])],
                                           BOOKS[book].get('stars_y', {}).get(piece[2]), piece[2],
                                           lines_by_id))
                    continue
                if isinstance(piece, tuple):
                    out.append(cut_macro(piece[1], se_images))
                    continue
                if not piece:
                    continue
                if b['kind'] == 'para' and any(
                        lid in BOOKS[book].get('page_breaks', ()) for _, lid, _, _ in piece[:-1]):
                    # (A page the printing ends early inside the paragraph:
                    # in the PDF, the paragraph in two at that line, a page
                    # break between, the first's last line justified, the
                    # second not indented; elsewhere whole.)
                    at = next(i for i, (_, lid, _, _) in enumerate(piece)
                              if lid in BOOKS[book]['page_breaks'])
                    def body(rows):
                        return [' '.join(mk) for _, _, _, mk in rows]
                    first, second = piece[:at + 1], piece[at + 1:]
                    out.append('\n'.join(
                        ['ifdef::backend-pdf[]'] + body(first)[:-1] + [body(first)[-1] + '{ls}', '',
                         '<<<', '', '[.cont]', f'// page {second[0][0]}'] + body(second) +
                        ['endif::[]', 'ifndef::backend-pdf[]'] + body(piece) + ['endif::[]']))
                    page = second[-1][0]
                    first_piece = False
                    continue
                if b['kind'] == 'para' and piece[-1][1] in BOOKS[book].get('page_breaks', ()) \
                        and piece is pieces[-1]:
                    pending_break.append(piece[-1][1])
                if b['kind'] == 'para':
                    # (A word divided where the piece ends: its rest goes on
                    # in the next piece, after the cut.)
                    k = pieces.index(piece)
                    later = next((q for q in pieces[k + 1:] if isinstance(q, list) and q), None)
                    last_mk = piece[-1][3]
                    if later is not None and last_mk and re.search(r'\{(shy|zwsp)\}', last_mk[-1]):
                        word = last_mk[-1]
                        m = list(re.finditer(r'\{(shy|zwsp)\}', word))[-1]
                        head, rest = word[:m.start()], word[m.end():]
                        if m.group(1) == 'shy':
                            head += '-'
                        piece[-1] = (piece[-1][0], piece[-1][1], piece[-1][2], last_mk[:-1] + [head])
                        q0 = later[0]
                        later[0] = (q0[0], q0[1], q0[2], [rest] + q0[3])
                    text_lines = ['[.indent]'] if force_indent else []
                    force_indent.clear()
                    # (A paragraph the printing starts after a cut, indented
                    # there: the role `indent`; one going on after it, none.)
                    if not first_piece or (piece[0][1] in by_target):
                        if piece is pieces[-1] or True:
                            pass
                    lid0 = piece[0][1]
                    if lid0 in by_target and pieces[0] == [] and first_piece:
                        if indented(lines_by_id[lid0.split('+')[0]], lefts, by_target[lid0]):
                            text_lines.append('[.indent]')
                    for pg, lid, ws, mk in piece:
                        if pg != page:
                            if pg > 0:
                                text_lines.append(f'// page {pg}')
                            page = pg
                        text_lines.append(' '.join(mk))
                    out.append('\n'.join(text_lines))
                else:
                    seg = [(pg, lid, ws) for pg, lid, ws, _ in piece]
                    mk = [w for _, _, _, m in piece for w in m]
                    out.append(verse_text(b, seg, mk, lines_by_id, lefts, italic,
                                          around_of(seg)))
                    page = piece[-1][0]
                first_piece = False
        if n:
            out = opening_word(out, n, lines_by_id, True, BOOKS[book].get('opening_words', {}).get(n, 1))
        if n == last_number and end_lines:
            out.extend(end_blocks(end_lines, lines_by_id, block_lines))
        text = apply_patches(book, ch['name'], '\n\n'.join(out) + '\n')
        open(f'{ROOT}/out/{book}/{ch["name"]}.adoc', 'w', encoding='utf-8').write(text)
    debug.sort(key=lambda l: tuple(float(x.replace('+', '.')) for x in l.split('\t')[0].split(':')))
    open(f'{ROOT}/out/{book}/lines.tsv', 'w', encoding='utf-8').write('\n'.join(debug) + '\n')
    return report


def main(book, use_tesseract):
    chapters, lines, otoks, items, choices = build(book)
    settle(book, choices, use_tesseract)
    report = write(book, chapters, lines, otoks, items, choices)
    json.dump([c.json() for c in choices], open(f'{ROOT}/choices-{book}.json', 'w'),
              ensure_ascii=False, indent=0)
    from collections import Counter
    print(book, 'choices', len(choices), Counter(c.kind for c in choices))
    print('settled', Counter((c.kind, c.how) for c in choices if c.how))
    open_ = [c for c in choices if c.how is None and not (c.kind == 'italic' and c.ocr != '?' and False)]
    print('open', Counter(c.kind for c in open_), 'on lines', len({c.line['id'] for c in open_}))
    for r in report:
        print(r)
    if LEADS:
        # (The look's roles for them: 10 pt Old Standard's line, 1.284 its
        # 15.2 pt, so a line height of pitch / 11.84.)
        print('leads:', ' '.join(f'{l}: {{ line_height: {int(l[2:]) / 118.4:.4f} }}' for l in sorted(LEADS)))


if __name__ == '__main__':
    main(sys.argv[1], '--tesseract' in sys.argv)
