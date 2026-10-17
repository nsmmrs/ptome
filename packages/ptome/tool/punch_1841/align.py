"""The three issues' text laid on the scan's lines: the words of the
showcase's transcription (test/showcase/punch/text/issue-N.adoc, Project
Gutenberg's, as imported), each with its block (a heading, a paragraph,
a verse's line, a caption, a table's row) and whether it starts it,
aligned letter by letter with the Internet Archive's OCR of each page's
two columns (ocr.json, the leaf turned upright as geometry.py turns it),
column by column, page by page from where the page before ended; each
OCR line's first aligned letter starting a printed line. Written to
PUNCH_WORK/draft.json: for each page and column, its lines, each with
its words, its kind and the OCR's reading, for spec.py.

    python3 -I align.py
"""
import bisect, difflib, html, json, math, os, re

HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.environ.get('PUNCH_WORK', os.path.expanduser('~/.cache/asciidart-work/print-match/punch'))
SRC = os.path.join(HERE, '..', '..', 'test', 'showcase', 'punch', 'text')
# Each issue's leaves (the printed pages are the leaves less 3).
ISSUES = {1: range(4, 16), 2: range(52, 64), 3: range(64, 76)}


def norm(t):
    t = t.replace('__', '').replace('&amp;', '&').lower()
    t = re.sub(r'\[[^\]]*\]#|#', '', t)
    return re.sub(r'[^a-z0-9]', '', t)


def tokens(issue):
    """The issue's words in order: each its text (markup kept), its
    block's kind and whether it starts the block (or a verse's line)."""
    lines = open(os.path.join(SRC, f'issue-{issue}.adoc'), encoding='utf-8').read().split('\n')
    out = []
    i = 0
    kind = None
    in_verse = in_table = False
    caption = None

    def add(text, k, start):
        # (An italic phrase as italic words, each its own: a line may
        # divide the phrase.)
        text = re.sub(r'__(.+?)__', lambda m: ' '.join(f'__{w}__' for w in m.group(1).split()), text)
        first = True
        for w in text.split():
            # (A word joined to the next by an em dash: two, the dash with
            # the first, the second joined to it without a space; the
            # volume breaks its lines after a dash.)
            parts = re.split(r'(?<=—)(?=[^—\s])', w)
            for q, part in enumerate(parts):
                out.append({'t': part, 'k': k, 's': start and first, 'join': q > 0})
                first = False

    while i < len(lines):
        line = lines[i]
        s = line.strip()
        if s.startswith('[') and s.endswith(']') and not in_table:
            if s == '[verse]':
                kind = 'V'
            i += 1
            continue
        if s == '____':
            in_verse = not in_verse
            if not in_verse:
                kind = None
            i += 1
            continue
        if s == '|===':
            in_table = not in_table
            i += 1
            continue
        if s == "'''":
            out.append({'t': '', 'k': 'R', 's': True})
            i += 1
            continue
        if re.match(r'^=+ ', s):
            # (A piece's head, `===`, in the volume's heavy capitals; a head
            # within a piece, `====`, in its small capitals.)
            level = len(s.split(' ', 1)[0])
            add(re.sub(r'^=+ ', '', s), 'H' if level <= 3 else 'h', True)
            i += 1
            continue
        if s.startswith('.') and not s.startswith('..') and i + 1 < len(lines) and lines[i + 1].startswith('image::'):
            caption = s[1:]
            i += 1
            continue
        if s.startswith('image::'):
            out.append({'t': '', 'k': 'I', 's': True, 'img': s})
            if caption:
                add(caption, 'C', True)
                caption = None
            i += 1
            continue
        if not s:
            i += 1
            continue
        if in_table:
            # (A row: its cells' lines until a blank line.)
            row = []
            while i < len(lines) and lines[i].strip():
                row.append(lines[i].strip().lstrip('|').strip())
                i += 1
            add(' '.join(c for c in row if c), 'T', True)
            continue
        if in_verse:
            add(s, 'V', True)
            i += 1
            continue
        # (A paragraph: its lines until a blank line.)
        para = []
        while i < len(lines) and lines[i].strip() and not lines[i].strip() in ('____', '|===', "'''"):
            para.append(lines[i].strip())
            i += 1
        add(' '.join(para), 'P', True)
    return out


def split_at(raw, n):
    """raw cut after its n-th letter (counted as norm counts them)."""
    count = 0
    for i, ch in enumerate(raw):
        if norm(ch):
            count += 1
            if count == n:
                return raw[:i + 1], raw[i + 1:]
    return raw, ''


def piece(toks, owner, c0, c1, hyphen):
    """The words of the text's letters c0 to c1: a word cut at either end
    as the line cuts it, its first part with a hyphen if the line ends
    divided (and has none), its markup closed and opened again."""
    if c0 >= len(owner):
        return []
    t0, t1 = owner[c0], owner[min(c1, len(owner)) - 1]
    out = []
    for ti in range(t0, t1 + 1):
        t = dict(toks[ti])
        raw = t['t']
        first = bisect.bisect_left(owner, ti)
        last = bisect.bisect_right(owner, ti)
        if first == last:
            continue  # (no letters: a rule's or a cut's place)
        # (Its letters within the line: from c0 if it starts before, to c1
        # if it ends after.)
        a = max(c0, first) - first
        b = min(c1, last) - first
        if b <= 0:
            continue
        cut = False
        if a > 0:
            raw = split_at(raw, a)[1].lstrip('-')
            t['s'] = False
            cut = True
        if b < last - first:
            head, tail = split_at(raw, b - a)
            # (A word divided at its own hyphen keeps it at the line's end.)
            raw = head + ('-' if tail.startswith('-') or hyphen else '')
            raw = raw.replace('--', '-')
            cut = True
        if cut and raw.count('__') % 2:
            raw = raw + '__' if not raw.startswith('__') else raw
            if not raw.startswith('__') and raw.endswith('__') is False:
                raw = '__' + raw
        t['t'] = raw
        out.append(t)
    return out


def ocr_lines(ocr, geo, leaf):
    """The leaf's OCR lines with letters, upright, in reading order: the
    first column's, then the second's (by the rule between them)."""
    g = geo[str(leaf)]
    page = ocr[leaf]
    w, h = page['b'][2], page['b'][3]
    cx, cy = w / 2, h / 2
    a = math.atan(g['lean'])
    out = []
    for l in page['lines']:
        text = ' '.join(x['t'] for x in l['w'])
        if sum(c.isalpha() for c in text) < 2:
            continue
        x0, y0, x1, y1 = l['b']
        # (The box turned as the leaf is turned upright.)
        def rot(x, y):
            dx, dy = x - cx, y - cy
            return cx + dx * math.cos(a) - dy * math.sin(a), cy + dx * math.sin(a) + dy * math.cos(a)
        ux0, uy0 = rot(x0, y0)
        ux1, uy1 = rot(x1, y1)
        if g['head'] and uy1 < g['head'][0] + 10:
            continue  # (the running head, set by the look)
        col = 1 if (ux0 + ux1) / 2 < g['rule'] else 2
        words = []
        for wd in l['w']:
            a0, b0 = rot(wd['b'][0], wd['b'][1])
            a1, b1 = rot(wd['b'][2], wd['b'][3])
            words.append({'t': wd['t'], 'box': [round(a0), round(b0), round(a1), round(b1)]})
        out.append({'col': col, 'box': [round(ux0), round(uy0), round(ux1), round(uy1)], 'ocr': text, 'words': words})
    out.sort(key=lambda l: (l['col'], l['box'][3]))
    return out


def main():
    ocr = json.load(open(os.path.join(WORK, 'ocr.json')))
    geo = json.load(open(os.path.join(WORK, 'geometry.json')))
    draft = []
    for issue, leaves in ISSUES.items():
        toks = tokens(issue)
        letters, owner = [], []
        for ti, t in enumerate(toks):
            for ch in norm(t['t']):
                letters.append(ch)
                owner.append(ti)
        cursor = 0
        for leaf in leaves:
            lines = ocr_lines(ocr, geo, leaf)
            o_chars, o_line = [], []
            for k, l in enumerate(lines):
                for ch in norm(l['ocr']):
                    o_chars.append(ch)
                    o_line.append(k)
            if not o_chars:
                draft.append({'issue': issue, 'leaf': leaf, 'page': leaf - 3, 'lines': []})
                continue
            # (The whole issue: Project Gutenberg's order is not always the
            # printing's.)
            cursor = 0
            sm = difflib.SequenceMatcher(None, o_chars, letters, autojunk=False)
            o2p = {}
            for a, b, n in sm.get_matching_blocks():
                for q in range(n):
                    o2p[a + q] = b + q
            first_of = {}
            for i, lk in enumerate(o_line):
                first_of.setdefault(lk, i)
            # (Each OCR line's first letter in the text: its first matched
            # letter's place, less the OCR's letters before it on the line;
            # at a word's start, unless the line before ends divided.)
            starts = []
            for k in range(len(lines)):
                idx = [(i, o2p[i]) for i, lk in enumerate(o_line) if lk == k and i in o2p]
                if len(idx) < 3:
                    starts.append(None)
                    continue
                c = idx[0][1] - (idx[0][0] - first_of[k])
                c = max(0, min(c, len(owner) - 1))
                divided = k > 0 and lines[k - 1]['ocr'].rstrip().endswith('-') and lines[k - 1]['col'] == lines[k]['col']
                if not divided:
                    # (The nearest word's start.)
                    ti = owner[c]
                    lo = c
                    while lo > 0 and owner[lo - 1] == ti:
                        lo -= 1
                    hi = c
                    while hi < len(owner) and owner[hi] == ti:
                        hi += 1
                    c = lo if c - lo <= hi - c else min(hi, len(owner) - 1)
                starts.append(c)
            prev = None
            out_lines = []
            for k, l in enumerate(lines):
                c0 = starts[k]
                if c0 is None or (prev is not None and c0 < prev):
                    out_lines.append(dict(l, words=[], kind='?'))
                    continue
                c1 = next((starts[j] for j in range(k + 1, len(lines)) if starts[j] is not None and starts[j] > c0), None)
                if c1 is None:
                    # (The column's last line: as far as its own letters, no
                    # further than the OCR read of them.)
                    reach = c0 + int(len(norm(l['ocr'])) * 1.2) + 2
                    last = max((o2p[i] for i, lk in enumerate(o_line) if lk == k and i in o2p and o2p[i] < reach), default=c0)
                    t = owner[last]
                    c1 = last
                    while c1 < len(owner) and owner[c1] == t:
                        c1 += 1
                # (Cuts and rules between the last line and this one, which
                # the OCR doesn't read: kept before it.)
                if prev is not None and prev > 0:
                    for t in toks[owner[prev - 1] + 1:owner[min(c0, len(owner) - 1)]]:
                        if t['k'] in ('I', 'R'):
                            out_lines.append(dict(l, words=[t], kind=t['k'], ocr=''))
                seg = piece(toks, owner, c0, c1, l['ocr'].rstrip().endswith('-'))
                kind = seg[0]['k'] if seg else '?'
                out_lines.append(dict(l, words=seg, kind=kind))
                prev = c1
            if o2p:
                cursor = max(cursor, owner[max(o2p.values())] and max(o2p.values()))
                cursor = max(o2p.values()) + 1
            draft.append({'issue': issue, 'leaf': leaf, 'page': leaf - 3, 'lines': out_lines})
            print(issue, leaf, len(lines), 'lines;', sum(1 for l in out_lines if l['kind'] == '?'), 'unread')
    json.dump(draft, open(os.path.join(WORK, 'draft.json'), 'w'), ensure_ascii=False, indent=0)


if __name__ == '__main__':
    main()
