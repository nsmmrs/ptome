"""The Folio's Tempest line by line: the Text Creation Partnership's
transcription of the First Folio (EEBO-TCP A11954, CC0; its words, its
spelling, its long s, its italics, its pages) laid on the scan's lines
(Tesseract's, columns.py): each page's words aligned with the OCR's of
its two columns (by their letters, long s, u and v, i and j alike), each
OCR line's first aligned word starting a printed line. Written to
TEMPEST_WORK/draft.tsv: page, column, line, kind (`head`, `stage`,
`speech` where a speaker's name starts the line, `text`), the line's
words (TCP's, italics in `_`), the OCR's line, and how many of its
words matched — a draft read against the scan by eye into folio.spec.

    python3 -I align.py
"""
import difflib, html, os, re, sys

WORK = os.environ.get('TEMPEST_WORK', os.path.expanduser('~/.cache/asciidart-work/print-match/tempest'))
LEAF_OF_PAGE = {p: 24 + p for p in range(1, 20)}


def tcp_tokens():
    """The play's words in order: each its page, its text (italic parts
    in `_`), its element (`speaker`, `stage`, `l`, `p`, `head`…), whether
    it starts its element (a speech, a verse line, a direction)."""
    s = open(os.path.join(WORK, 'A11954.xml'), encoding='utf-8').read()
    i = s.index('<head>THE TEMPEST.</head>')
    start = s.rfind('<div type="play"', 0, i)
    end = s.index('<div type="play"', i)
    play = s[start:end]
    play = re.sub(r'<g ref="char:EOLhyphen"/>', '\u00ad', play)
    play = re.sub(r'<g ref="char:V">Ʋ</g>', 'V', play)
    play = re.sub(r'<g ref="char:cmbAbbrStroke">̄</g>', '\u0304', play)
    # (A letter set above the line, `yͤ`: AsciiDoc's superscript.)
    play = re.sub(r'<hi rend="sup">(\w+)</hi>', '\x03\\1\x04', play)
    play = re.sub(r'<gap[^>]*>.*?</gap>', '•', play, flags=re.S)
    play = re.sub(r'<desc>.*?</desc>', '', play, flags=re.S)
    # (Character by character: a word's parts across tags one word.)
    chars = []
    page, stack, hi = 1, [], []
    starting = False
    for m in re.finditer(r'<(/?)(\w+)([^>]*?)(/?)>|([^<]+)', play):
        close, tag, attrs, selfclose, text = m.groups()
        if text is not None:
            el = next((t for t in reversed(stack) if t in ('head', 'stage', 'speaker', 'p', 'l', 'item', 'trailer')), 'text')
            for ch in html.unescape(text):
                chars.append((ch, page, el, len(hi), starting and not ch.isspace()))
                if not ch.isspace():
                    starting = False
            continue
        if tag == 'pb':
            n = re.search(r'n="(\d+)"', attrs)
            if n:
                page = int(n.group(1))
            continue
        if selfclose:
            continue
        if close:
            if stack and stack[-1] == tag:
                stack.pop()
            if tag == 'hi' and hi:
                hi.pop()
            chars.append((' ', page, 'text', 0, False))
            continue
        stack.append(tag)
        if tag == 'hi':
            hi.append(len(chars))
        elif tag in ('l', 'p', 'stage', 'speaker', 'head', 'item', 'trailer'):
            chars.append((' ', page, 'text', 0, False))
            starting = True
    # (A stage direction is italic, the names in it roman: but a <hi>
    # about the whole direction is the direction's own italic.)
    words, cur = [], []

    def emit():
        if not cur:
            return
        el = cur[0][2]
        text = ''
        for ch, _, e, depth, _ in cur:
            it = (e in ('stage', 'speaker')) != (depth % 2 == 1)
            text += ('\x01' if it else '\x02') + ch
        # (Runs of italic letters wrapped in `_`.)
        out, mode = '', None
        for k in range(0, len(text), 2):
            it = text[k] == '\x01'
            if it != mode:
                if mode:
                    out += '_'
                if it:
                    out += '_'
                mode = it
            out += text[k + 1]
        if mode:
            out += '_'
        out = out.replace('\x03', '^').replace('\x04', '^')
        words.append({'page': cur[0][1], 'text': out, 'el': el, 'lstart': cur[0][4]})

    # (Each direction's italic: see below.)
    fixed = []
    k = 0
    while k < len(chars):
        if chars[k][2] == 'stage':
            j = k
            while j < len(chars) and chars[j][2] in ('stage',) or (j < len(chars) and chars[j][0] == ' ' and chars[j][2] == 'text' and j + 1 < len(chars) and chars[j + 1][2] == 'stage'):
                j += 1
            seg = chars[k:j]
            letters = [c for c in seg if not c[0].isspace()]
            # (The transcription marks a direction's italic one of two
            # ways: the direction plain and its names in <hi>, or its
            # italic in <hi> and its names plain; most of it is italic.)
            if letters and sum(c[3] % 2 for c in letters) * 2 > len(letters):
                seg = [(c[0], c[1], c[2], c[3] - 1, c[4]) for c in seg]
            fixed += seg
            k = j
        else:
            fixed.append(chars[k])
            k += 1
    for c in fixed:
        if c[0].isspace():
            emit()
            cur = []
        else:
            cur.append(c)
    emit()
    out = []
    for t in words:
        if '\u00ad' in t['text']:
            a, b = t['text'].split('\u00ad', 1)
            if a.count('_') % 2:
                a, b = a + '_', '_' + b
            a = a[:-1] + '-_' if a.endswith('_') else a + '-'
            out.append(dict(t, text=a))
            out.append(dict(t, text=b, lstart=False))
        else:
            out.append(t)
    return out


def norm(w):
    w = w.replace('_', '').lower().replace('ſ', 's').replace('v', 'u').replace('j', 'i').replace('ﬅ', 'st')
    # (The long s read as f, a ct ligature as &: alike.)
    return re.sub(r'[^a-z0-9]', '', w).replace('f', 's')


def ocr_lines(leaf, col):
    path = os.path.join(WORK, 'cols', f'{leaf:04d}-{col}.hocr')
    s = open(path, encoding='utf-8').read()
    out = []
    for m in re.finditer(r"class='ocr_line'[^>]*title=\"bbox (\d+) (\d+) (\d+) (\d+)[^\"]*\"(.*?)</span>\s*</span>", s, re.S):
        words = [html.unescape(re.sub('<[^>]+>', '', w)) for w in re.findall(r"class='ocrx_word'[^>]*>(.*?)</span>", m.group(5) + '</span>', re.S)]
        words = [w for w in words if w.strip()]
        if words:
            out.append({'box': tuple(map(int, m.groups()[:4])), 'words': words})
    return out


def main():
    tokens = tcp_tokens()
    rows = []
    spans = []
    for page in range(1, 20):
        leaf = LEAF_OF_PAGE[page]
        pt = [t for t in tokens if t['page'] == page]
        lines = []
        for col in (1, 2):
            for l in ocr_lines(leaf, col):
                lines.append((col, l))
        # (Letter by letter: the OCR runs words together and splits them;
        # its letters and the text's are aligned, each OCR line's first
        # letter mapped to the text's, the line starting at the text's
        # word nearest it.)
        o_chars, o_line = [], []
        for k, (col, l) in enumerate(lines):
            for w in l['words']:
                for ch in norm(w):
                    o_chars.append(ch)
                    o_line.append(k)
        p_chars, p_word, word_start = [], [], []
        for wi, t in enumerate(pt):
            word_start.append(len(p_chars))
            for ch in norm(t['text']):
                p_chars.append(ch)
                p_word.append(wi)
        sm = difflib.SequenceMatcher(None, o_chars, p_chars, autojunk=False)
        o2p = {}
        for a, b, n in sm.get_matching_blocks():
            for i in range(n):
                o2p[a + i] = b + i
        first_of = {}
        for i, lk in enumerate(o_line):
            first_of.setdefault(lk, i)
        starts, matched = [], []
        for k in range(len(lines)):
            idx = [(i, o2p[i]) for i, lk in enumerate(o_line) if lk == k and i in o2p]
            matched.append(len(idx))
            if len(idx) < 3:
                starts.append(None)
                continue
            # (The text's letter for the line's first: its first matched
            # letter's, less the OCR's letters before it on the line.)
            c = idx[0][1] - (idx[0][0] - first_of[k])
            c = max(0, min(c, len(p_chars) - 1))
            # (The word nearest: the one starting closest to it; then a
            # speech's, a verse line's or a direction's first word within
            # two words of it, where the printed lines start.)
            wi = min(range(len(word_start)), key=lambda wi: abs(word_start[wi] - c))
            near = [j for j in range(max(0, wi - 2), min(len(pt), wi + 3)) if pt[j]['lstart']]
            if near:
                wi = min(near, key=lambda j: (abs(j - wi), pt[j]['el'] != 'speaker'))
            # (A speech's words start their line with their speaker.)
            while wi > 0 and pt[wi - 1]['el'] == 'speaker':
                wi -= 1
            starts.append(wi)
        # (A line none of whose words matched (the running head, the foot,
        # a misreading): no start of its own.)
        prev = 0
        for k, (col, l) in enumerate(lines):
            s0 = starts[k]
            nxt = next((starts[j] for j in range(k + 1, len(lines)) if starts[j] is not None and starts[j] > (s0 or prev)), len(pt))
            if s0 is None or s0 < prev:
                rows.append((page, col, k, 'none', '', ' '.join(l['words']), 0))
                spans.append({'page': page, 'col': col, 'k': k, 'box': l['box'], 'ocr': ' '.join(l['words']), 'tokens': []})
                continue
            # (Words between the last line's end and this line's first
            # match, unmatched: this line's.)
            begin = prev if prev < s0 else s0
            seg = pt[begin:nxt]
            prev = nxt
            kind = 'speech' if seg and seg[0]['el'] == 'speaker' else seg[0]['el'] if seg else 'text'
            text = ' '.join(t['text'] for t in seg).replace('_ _', ' ')
            rows.append((page, col, k, kind, text, ' '.join(l['words']), matched[k]))
            spans.append({'page': page, 'col': col, 'k': k, 'box': l['box'], 'ocr': ' '.join(l['words']),
                          'tokens': [[t['text'], t['el'], False, t.get('lstart', False)] for t in seg]})
    with open(os.path.join(WORK, 'draft.tsv'), 'w', encoding='utf-8') as f:
        for r in rows:
            f.write('\t'.join(str(x) for x in r) + '\n')
    import json
    json.dump(spans, open(os.path.join(WORK, 'draft.json'), 'w'), ensure_ascii=False)
    weak = sum(1 for r in rows if r[6] < 3)
    print(len(rows), 'lines;', weak, 'with fewer than three letters matched')


main()
