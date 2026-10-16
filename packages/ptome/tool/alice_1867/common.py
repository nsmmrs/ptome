"""Draft a transcription of a printing from its OCR, aligned with the
Standard Ebooks text: the printing's words and lines, Standard Ebooks'
spelling, quotation marks and markup where the two agree, every
disagreement flagged for review against the scan.

    python3 -I transcribe.py BOOK

BOOK is `wonderland` or `looking-glass` (settings below). Writes
out/BOOK/*.adoc (the chapters, their lines the printing's) and
out/BOOK/flags.json (the lines to review), applying
corrections/BOOK.tsv (reviewed lines: `LINE-ID<TAB>text`).
"""
import json, os, re, sys, difflib, unicodedata

HERE = os.path.dirname(os.path.abspath(__file__))
# The work folder: the scans, the OCR, the Standard Ebooks texts, the
# drafts (README.md).
ROOT = os.environ.get('ALICE_WORK', os.path.expanduser('~/.cache/asciidart-work/alice-match'))
# Standard Ebooks' text as imported (git HEAD before the transcription).
REPO = os.path.join(ROOT, 'se')
# The work's folder in the repository.
WORK = os.path.join(os.path.dirname(os.path.dirname(HERE)), 'test', 'showcase', 'alice')

BOOKS = {
    'wonderland': dict(id='alicesadventu00carr', first=17, last=208, offset=16,
                       chapters=12,
                       # (The prefatory poem, its three pages before the
                       # contents.)
                       front_files=['epigraph'], front_leaves=[11, 12, 13],
                       # (The Mouse's Tale, set by hand from its measures.)
                       skip={53: (3, 999)},
                       # (The printing's rows of asterisks, after the line
                       # they follow: each row's stars' centres, in the
                       # scan's pixels.)
                       stars={'27:5': [[472, 989, 1504, 2023], [726, 1230, 1731],
                                       [475, 984, 1496, 2005]],
                              '30:5': [[522, 1042, 1559, 2078], [772, 1291, 1810],
                                       [523, 1006, 1560, 2089]],
                              '85:19': [[420, 847, 1278, 1707, 2137],
                                        [637, 1063, 1493, 1923],
                                        [423, 850, 1278, 1706, 2136]]},
                       # (Where the printing ends a page early, inside a
                       # paragraph: after these lines.)
                       page_breaks=['146:13', '178:11', '205:18'],
                       # (Lines set apart at the end: their roles.)
                       end_lines={'208:19': 'the-end', '208:20': 'imprint'},
                       # (Chapters whose opening sets more than its first
                       # word in small capitals: VIII's "A LARGE".)
                       opening_words={8: 2},
                       # (Each chapter's running title, divided across the
                       # spread where the printing divides it.)
                       running=['Down the|Rabbit-Hole.', 'The Pool|of Tears.',
                                'A Caucus-Race|and a Long Tale.',
                                'The Rabbit Sends|in a Little Bill.',
                                'Advice from a|Caterpillar.', 'Pig and Pepper.',
                                'A Mad Tea-Party.', 'The Queen’s|Croquet-Ground.',
                                'The Mock|Turtle’s Story.', 'The Lobster|Quadrille.',
                                'Who Stole|the Tarts?', 'Alice’s Evidence.']),
    'looking-glass': dict(id='throughlookinggl01carr', first=19, last=241,
                          offset=18, chapters=12),
}

VOCAB = json.load(open(os.path.join(ROOT, 'vocab.json')))  # vocab.py

# ---------------------------------------------------------------- tokens

def core(text):
    t = unicodedata.normalize('NFKD', text)
    return re.sub(r'[^0-9A-Za-z]', '', t).lower()


def hyphens(text):
    """The word's letters with its hyphens (its form)."""
    t = unicodedata.normalize('NFKD', text)
    return re.sub(r'[^0-9A-Za-z-]', '', t).lower().strip('-')


PUNCT_MAP = str.maketrans({'“': '"', '”': '"', '‘': "'", '’': "'",
                           '⁠': '', ' ': ' '})


def punct(text):
    """The word's punctuation, quotes made straight, apostrophes inside
    the word left out."""
    t = text.translate(PUNCT_MAP)
    t = re.sub(r"(?<=[A-Za-z])'(?=[A-Za-z])", '', t)
    return re.sub(r'[0-9A-Za-z\s-]', '', t)


def in_vocab(word):
    w = word.lower().replace('’', "'").strip("'")
    parts = [p for p in re.split(r'-', w) if p]
    return bool(parts) and all(
        (p in VOCAB) or (p.rstrip("'s") in VOCAB) or p.isdigit() for p in parts)


class Tok:
    __slots__ = ('text', 'italic', 'sc', 'block', 'core')

    def __init__(self, text, italic=False, sc=False, block=None):
        self.text, self.italic, self.sc, self.block = text, italic, sc, block
        self.core = core(text)

    def __repr__(self):
        return self.text


def styled_tokens(text, block):
    """The words of a paragraph's markup, each with its style."""
    toks = []
    italic = sc = False
    word, w_italic, w_sc = [], False, False
    i = 0
    def flush():
        nonlocal word
        if word:
            toks.append(Tok(''.join(word), w_italic, w_sc, block))
            word = []
    while i < len(text):
        if text.startswith('__', i):
            italic = not italic
            i += 2
            continue
        if text.startswith('[.sc]#', i):
            sc = True
            i += 6
            continue
        if text[i] == '#' and sc:
            sc = False
            i += 1
            continue
        c = text[i]
        if c.isspace():
            flush()
        else:
            if not word:
                w_italic, w_sc = italic, sc
            else:
                w_italic = w_italic or italic
                w_sc = w_sc or sc
            word.append(c)
        i += 1
    flush()
    return toks

# ---------------------------------------------------------------- SE text

def se_blocks(book):
    """Each chapter's blocks: (kind, raw lines, tokens)."""
    chapters = []
    n = BOOKS[book]['chapters']
    names = [(f, None) for f in BOOKS[book].get('front_files', [])] + \
        [(f'chapter-{c}', c) for c in range(1, n + 1)]
    for name, number in names:
        path = f'{REPO}/text/{book}/{name}.adoc'
        lines = [l for l in open(path, encoding='utf-8').read().split('\n')
                 if not re.match(r'^//( |$)', l)]
        blocks = []
        i = 0
        while i < len(lines):
            line = lines[i]
            if not line.strip():
                i += 1
                continue
            start = i
            if line.startswith('____') or (line.startswith('[') and i + 1 < len(lines)
                                           and (lines[i + 1].startswith('____')
                                                or lines[i + 1].startswith('['))
                                           and any(l.startswith('____') for l in lines[i:i + 3])):
                # a delimited block with its attribute lines
                j = i
                while not lines[j].startswith('____'):
                    j += 1
                k = j + 1
                while not lines[k].startswith('____'):
                    k += 1
                raw = lines[start:k + 1]
                body = lines[j + 1:k]
                kind = 'verse' if any('verse' in l for l in lines[start:j]) else 'quote'
                if any('tale' in l for l in lines[start:j]):
                    kind = 'other'
                blocks.append(dict(kind=kind, head=lines[start:j + 1], body=body,
                                   raw=raw))
                i = k + 1
                continue
            j = i
            while j < len(lines) and lines[j].strip():
                j += 1
            raw = lines[i:j]
            if raw[0].startswith(('image::', '==', '[#', '[', '//', 'include::')) and len(raw) <= 2 and (
                    raw[0].startswith(('image::', '==', '[#', '//', 'include::')) or raw[-1].startswith('==')):
                blocks.append(dict(kind='other', raw=raw))
            else:
                blocks.append(dict(kind='para', raw=raw))
            i = j
        for b in blocks:
            if b['kind'] == 'para':
                b['toks'] = styled_tokens(' '.join(b['raw']), b)
            elif b['kind'] == 'verse':
                b['toks'] = []
                for line in b['body']:
                    b['toks'] += styled_tokens(line, b)
            else:
                b['toks'] = []
        chapters.append(dict(path=path, blocks=blocks, name=name, number=number))
    return chapters

# ---------------------------------------------------------------- OCR

def ocr_lines(book):
    cfg = BOOKS[book]
    pages = json.load(open(os.path.join(ROOT, cfg['id'] + '.ocr.json')))
    out = []
    for leaf in list(cfg.get('front_leaves', [])) + list(range(cfg['first'], cfg['last'] + 1)):
        p = pages[leaf]
        H = p['b'][3]
        lines = p['lines']
        for i, l in enumerate(lines):
            x0, y0, x1, y1 = l['b']
            text = ' '.join(w['t'].strip() for w in l['w'])
            if y0 < 0.1 * H:
                continue  # running head
            if y0 > 0.925 * H and len(text.replace(' ', '')) <= 6:
                continue  # signature
            lo, hi = cfg.get('skip', {}).get(leaf, (999, 0))
            if lo <= i <= hi:
                continue
            if re.match(r'^CHAP', text):
                kind = 'chapter'
            elif (text.replace(' ', '').replace("'", '').isupper()
                  and out and out[-1]['kind'] == 'chapter'):
                kind = 'title'
            else:
                kind = 'body'
            out.append(dict(id=f'{leaf}:{i}', leaf=leaf, page=leaf - cfg['offset'],
                            index=i, box=l['b'], words=l['w'], kind=kind))
    return out


class OTok:
    __slots__ = ('text', 'line', 'conf', 'box', 'split', 'core', 'boxes', 'cont')

    def __init__(self, text, line, conf, box):
        self.text, self.line, self.conf, self.box = text, line, conf, box
        self.split = None   # (index into text of the line-end hyphen)
        self.boxes = [box]
        self.cont = None    # (line, box) of the part after the division
        self.core = core(text)

    def __repr__(self):
        return self.text


def ocr_tokens(lines):
    toks = []
    body = [l for l in lines if l['kind'] == 'body']
    for n, line in enumerate(body):
        words = []
        for w in line['words']:
            text = w['t'].strip()
            if not text:
                continue
            # (ABBYY's word with spaces in it: a word each, the box divided
            # by their letters.)
            parts = text.split()
            x0, y0, x1, y1 = w['b']
            total = sum(len(p) for p in parts) + len(parts) - 1
            at = 0
            for part in parts:
                a = x0 + (x1 - x0) * at / total
                at += len(part)
                b = x0 + (x1 - x0) * at / total
                at += 1
                words.append(OTok(part, line, w['c'], [int(a), y0, int(b), y1]))
        # (A hyphen standing alone, or starting or ending a word inside the
        # line: one word, "daisy - chain".)
        merged = []
        for w in words:
            if merged and (w.text == '-' or w.text.startswith('-')
                           or (merged[-1].text.endswith('-') and merged[-1] is not words[-1])):
                prev = merged[-1]
                prev.text += w.text
                prev.boxes.append(w.box)
                prev.core = core(prev.text)
            else:
                merged.append(w)
        line['toks'] = merged
    # (A word divided at the line's end: one word, on the line it starts;
    # only where the line reaches the text's right edge, a verse line's
    # dash not a division.)
    right = {}
    for line in body:
        right[line['leaf']] = max(right.get(line['leaf'], 0), line['box'][2])
    for n, line in enumerate(body):
        toks_here = line['toks']
        if not toks_here:
            continue
        last = toks_here[-1]
        nxt_first = next((t.text for t in body[n + 1]['toks'] if t.core), '') \
            if n + 1 < len(body) else ''
        if last.text.endswith('-') and len(last.core) > 0 and n + 1 < len(body) \
                and (line['box'][2] >= right[line['leaf']] - 90
                     or re.match(r'^[a-z]', nxt_first)):
            nxt = body[n + 1]['toks']
            if nxt and nxt[0].core:
                first = nxt.pop(0)
                last.split = len(last.text) - 1
                last.cont = (first.line, first.box)
                last.text = last.text + first.text
                last.boxes += first.boxes
                last.core = core(last.text)
    for line in body:
        toks.extend(line['toks'])
    return toks

# ---------------------------------------------------------------- output

def curly(text):
    t = re.sub(r'^"', '“', text)
    t = re.sub(r'"$', '”', t)
    t = re.sub(r"^'", '‘', t)
    t = t.replace("'", '’').replace('"', '”')
    return t


def ocr_form(otok):
    """An OCR word as text: curly quotes, its line-end hyphen kept as the
    printing's division."""
    return curly(otok.text)


def punct_agrees(otoks, k, text):
    """Whether the OCR word k's punctuation, with the marks standing
    apart next to it (\u201c I\u201d, \u201cAlice ;\u201d), is SE's."""
    pre = ''
    j = k - 1
    while j >= 0 and not otoks[j].core and otoks[j].line is otoks[k].line:
        pre = punct(otoks[j].text) + pre
        j -= 1
    post = ''
    j = k + 1
    while j < len(otoks) and not otoks[j].core and otoks[j].line is otoks[k].line:
        post += punct(otoks[j].text)
        j += 1
    own, want = punct(otoks[k].text), punct(text)
    for a in range(len(pre) + 1):
        for b in range(len(post) + 1):
            if pre[a:] + own + post[:b] == want:
                return True
    return False


