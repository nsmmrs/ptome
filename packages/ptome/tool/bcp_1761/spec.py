"""A first bcp.spec from decide.py's draft (draft.json): each page
(`@page LEAF PART`) its printed lines, each by its kind, read against
the scan afterwards (fixes.txt, fixes.py):

  `h ` the running head (its parts ` | ` apart: the middle's and the
       right's), `f ` the foot (the signature ` | ` the catchword),
  `D ` a day's or an office's head, `T ` a psalm's title or a head,
  `I ` a paragraph's first line opening with an initial two lines deep,
  `P ` one set in, `N ` one not, `R ` a rubric's, `C ` a centred line,
  two spaces a line going on; `# ? WORDS` a word read off the scan.

A word in italic `__so__`; a word Tesseract read that neither the corpus
nor the vocabulary has marked `⟦so⟧`, to be read off the scan.

    python3 -I spec.py > bcp.spec.draft
"""
import json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from common import WORK, PARTS, PX
from corpus import ORDINALS, roman, BCP, PARTS_119

ROMAN_OF = {roman(n): n for n in range(1, 40)}

INDENT = 18  # (points: a line starting further in than this is set in)


def text_of(words, roman=False):
    """The line's words, italic where the scan's are (none, [roman]: a
    psalm's verses, which the Psalter never sets in italic)."""
    out = []
    for w in words:
        # (The flowers of the frame and the paper's specks Tesseract read
        # as marks: no word of the printing's.)
        t = re.sub(r'^[‘\'"»«`\\|~=_]+(?=\w)', '', w['t'])
        t = re.sub(r'(?<=[\w.,:;?!])[\'"»«`\\|~=_\]]+$', '', t)
        if not t or not re.search(r'[A-Za-z0-9&]', t):
            continue
        if w.get('flag'):
            t = f'⟦{t}⟧'
        if w.get('i') and not roman:
            t = f'__{t}__'
        out.append(t)
    s = ' '.join(out)
    # (Italic words side by side: one italic phrase.)
    return re.sub(r'__ __', ' ', s)


def ink_left(im, box, lo):
    """Where a word's ink starts on the upright leaf (Tesseract's box
    can reach left into the frame's flowers): the first column from `lo`
    with ink in the word's rows."""
    import numpy as np
    x0, y0, x1, y1 = box
    a = np.asarray(im.crop((int(lo), y0, x1, y1))) < 110
    cols = np.nonzero(a.sum(axis=0) >= 3)[0]
    return lo + cols[0] if len(cols) else x0


def head(part, leaf, day):
    """The page's running head: the Psalter's the day's (flush right on a
    recto, `h`; flush left on a verso, `H`), the offices' their names
    centred (`c`)."""
    if part == 'psalter':
        d = f'__The__ {roman(day)}. __Day.__'
        return f'h __PSALMS.__ | {d}' if leaf % 2 else f'H {d} | __PSALMS.__'
    if part == 'litany':
        return 'c __The LITANY.__'
    return 'c __MORNING PRAYER.__'


# (Where the printing's Latin is not the corpus's, as the scan reads it.)
LATIN = {
    2: 'Quare fremuerunt?', 19: 'Cœli enarrant.', 21: 'Domine, in virtute.', 35: 'Judica me, Domine.',
    37: 'Noli æmulari.', 63: 'Deus; Deus meus.', 72: 'Deus, Judicium.', 101: 'Misericordiam.',
    109: 'Deus laudum.', 121: 'Levavi oculos meos.', 123: 'Ad te levavi.', 136: 'Confitemini Domino.',
}


def titles():
    """Each psalm's title as the printing sets it: `PSAL.` and its number
    in roman, its Latin in italic (the corpus's, a full stop after it,
    or the printing's own); psalm xcix.'s `PSAL` the printing's, without
    its stop."""
    out = [None]
    for line in open(os.path.join(BCP, 'psalter.adoc'), encoding='utf-8'):
        m = re.match(r'^== @ (.*)$', line.rstrip('\n'))
        if m:
            n = len(out)
            latin = m.group(1) if m.group(1)[-1] in '?!.' else m.group(1) + '.'
            out.append(f'T PSAL{"" if n == 99 else "."} {roman(n)}. __{LATIN.get(n, latin)}__')
    return out


TITLE = re.compile(r'P\s*S\s*A\s*L|SAL\.|PSA')


def office_like(txt):
    """A line in spaced capitals, not a psalm's title: an office's head."""
    letters = re.sub(r'[^A-Za-z]', '', txt)
    return len(letters) >= 5 and letters.isupper() and 'PSAL' not in letters and 'DAY' not in letters \
        and len(txt) < 40


def is_title(line):
    """A psalm's title as Tesseract read it: `PSAL.` near the line's
    start, two words after it (not the running head, not a catchword)."""
    return line[:2] in ('T ', 'P ', '  ') and TITLE.search(line[2:14]) and 'PSALMS' not in line \
        and re.search(r'(PSAL|AL)\S*\s+\S+\s+\S', line[2:])


def office_starts():
    """The psalms an office's head stands over (days.adoc)."""
    return {int(m.group(1)) for m in re.finditer(r'Prayer:: (\d+)', open(os.path.join(BCP, 'days.adoc')).read())}


OFFICE_STARTS = office_starts()


def corpus_verses():
    """Each psalm's verses (psalm cxix. each of its parts'), in order,
    from the corpus, as lists of words."""
    from corpus import plain
    psalms = []
    for line in open(os.path.join(BCP, 'psalter.adoc'), encoding='utf-8'):
        line = line.rstrip('\n')
        if line.startswith('== @'):
            psalms.append([])
        elif line.startswith('@ '):
            psalms[-1].append(norm(plain(line[2:])))
    out = []
    for n, vs in enumerate(psalms, 1):
        out += [vs[k:k + 8] for k in range(0, len(vs), 8)] if n == 119 else [vs]
    return out


def norm(text):
    """A line's words, letters only, small."""
    text = re.sub(r'[⟦⟧_]', '', text)
    text = re.sub(r'\b([Tt]o)[- ](day|morrow)\b', r'\1\2', text)
    ws = re.sub(r'^\s*\d+\.(?=[A-Z])', '', text).split()
    while ws and (re.search(r'\d', ws[0]) or re.fullmatch(r'\W*[b-hj-np-z]?\W*', ws[0])
                  or len(ws) > 1 and ws[0] in ('ii', 'li', 'il', 'Il', 'Ii', 'll') and ws[1][:1].isupper()):
        ws = ws[1:]  # (A verse's number, read or misread.)
    return [w for w in (re.sub(r'[^a-z]', '', w.lower()) for w in ws) if w]


def starts(block, vs):
    """Which of a psalm's lines (`block`: (index, text)) start a verse:
    the lines' words aligned with the corpus's, a line starting a verse
    where its first word is a verse's first."""
    import difflib
    words, first, carry = [], {}, ''
    for k, (i, t) in enumerate(block):
        t = t.split(' @ ')[0]
        ws = norm(t)
        if carry and ws:
            # (A word divided at the line's end: the line goes on with it,
            # starting no verse.)
            words[-1] += ws[0]
            ws = ws[1:]
        else:
            first[i] = len(words)
        words += ws
        carry = re.search(r'[A-Za-z]-$', t.rstrip()) and ws
    cwords, cstart = [], set()
    for v in vs:
        cstart.add(len(cwords))
        cwords += v
    sm = difflib.SequenceMatcher(None, words, cwords, autojunk=False)
    at = {}
    for a, b, size in sm.get_matching_blocks():
        for d in range(size):
            at[a + d] = b + d
    res = set()
    for i, j in first.items():
        # (The line's first word, or the first of its words matched, less
        # the words before it.)
        for d in range(4):
            if j + d in at:
                c = at[j + d] - d
                if c > 0 and (c in cstart or c - 1 in cstart and cwords[c - 1] in ('i', 'o')):
                    # (Or a verse's `I` or `O` Tesseract lost.)
                    res.add(i)
                break
    return res


def clean(out, block, vs):
    """A psalm's lines (`block`: (index, text)) read against its verses
    (`vs`): a mark at a line's either end that is no word of the verse
    (the frame's flowers, a speck: an `e`, a `t`, a `⟦oo⟧`) dropped, an
    `I` Tesseract read as `T` put right."""
    import difflib
    toks = []  # (line index, token number, key)
    split = {}
    for i, t in block:
        body, _, tail = out[i][2:].partition(' @ ')
        split[i] = (body.split(' '), tail)
        for n, tok in enumerate(split[i][0]):
            key = re.sub(r'[^a-z]', '', re.sub(r'[⟦⟧_]', '', tok).lower())
            if key and not re.search(r'\d', tok):
                toks.append((i, n, key))
    cw = [w for v in vs for w in v]
    keys = [k for _, _, k in toks]
    drop, swap = set(), {}
    for op, a1, a2, b1, b2 in difflib.SequenceMatcher(None, keys, cw, autojunk=False).get_opcodes():
        if op == 'replace' and a2 - a1 == 1 and b2 - b1 == 1 and keys[a1] == 't' and cw[b1] == 'i':
            swap[toks[a1][:2]] = 'I'
        if op != 'delete' and not (op == 'replace' and a2 - a1 > b2 - b1):
            continue
        for a in range(a1, a2):
            i, n, key = toks[a]
            words = [x for x in toks if x[0] == i]
            edge = toks[a] in (words[0], words[-1]) or all(x in toks[a1:a2] for x in words[words.index(toks[a]):])
            if edge and (len(key) <= 3 or '⟦' in split[i][0][n]) and ''.join(keys[a1:a2]) != ''.join(cw[b1:b2]) \
                    and not re.search(r'[a-z]-⟧?$', split[i][0][n]):
                drop.add((i, n))
    for i, (body, tail) in split.items():
        ws = [swap.get((i, n), w) for n, w in enumerate(body) if (i, n) not in drop]
        if not [w for w in ws if w] and not tail:
            continue
        out[i] = out[i][:2] + ' '.join(ws) + (' @ ' + tail if tail else '')


def initial_word(line):
    """An initial's line: its first word whole, as Tesseract parts it
    (`B LESSED`, `T H E`) where the word it makes is one."""
    from corpus import vocabulary
    ws = line[2:].split(' ')
    for n in range(len(ws), 1, -1):
        head = ws[:n]
        if all(re.fullmatch(r'[A-Z]+', w) for w in head[:-1]) and re.fullmatch(r'[A-Z]+[,.;:]?', head[-1]) \
                and len(head[0]) == 1:
            word = ''.join(head)
            if word.rstrip(',.;:').lower() in vocabulary():
                return line[:2] + ' '.join([word] + ws[n:])
    return line


def verses(out):
    """The Psalter's verse numbers in their order: after a psalm's title
    (or a part's of psalm cxix.) its first verse (an initial, unnumbered),
    then each verse's number the one before's and one, whatever Tesseract
    read; psalm cxix.'s parts, the line over each initial, their Latin."""
    out = list(out)
    part, psalm = None, 0

    for k, line in enumerate(out):
        if line.startswith('@page'):
            part = line.split()[2]
        elif part == 'psalter' and is_title(line):
            psalm += 1
            # (An office's head Tesseract could not read over the psalm
            # that starts it: the line over the title, no words of its own.)
            prev = out[k - 1]
            if psalm in OFFICE_STARTS and prev[:2] in ('P ', '  ', 'T ') \
                    and len(re.findall(r'\b[a-z]{3,}\b', prev)) < 2:
                out[k - 1] = 'O ' + prev[2:]
        elif psalm == 119 and line[:2] in ('S ', 'T ', '  ') and 'PRAYER' not in line \
                and k + 1 < len(out) and out[k + 1].startswith('I '):
            out[k] = 'S ' + line[2:]
    # (A psalm's first line, or a part's, its initial's.)
    for k, line in enumerate(out[1:], 1):
        if (out[k - 1].startswith('S ') or is_title(out[k - 1])) and line[:2] in ('P ', '  '):
            out[k] = 'I ' + line[2:]
    # (Which lines start a verse: each psalm's, each part's, lines read
    # against its verses.)
    vss = iter(corpus_verses())
    block, part, vs = None, None, None
    for k, line in enumerate(out + ['@end end']):
        if line.startswith('@page'):
            part = line.split()[2]
        if part != 'psalter' and block is None:
            continue
        if line.startswith('S ') or (part == 'psalter' and is_title(line)) or line.startswith('@end'):
            if block is not None:
                clean(out, block, vs)
                block = [(i, out[i][2:]) for i, _ in block]
                for i in starts(block, vs):
                    if not out[i].startswith('I '):
                        out[i] = 'P ' + out[i][2:]
                for i, t in block:
                    if out[i].startswith('P ') and i not in starts(block, vs):
                        out[i] = '  ' + re.sub(r'^(\S*\d\S*\s+)+', '', out[i][2:])
            block, vs = [], next(vss, [])
        elif block is not None and line[:2] in ('P ', '  ', 'I '):
            block.append((k, line[2:]))
    out = [initial_word(l) if l.startswith('I ') else l for l in out]
    # (An initial's second line goes on its paragraph.)
    out = ['  ' + l[2:] if l.startswith('I ') and k and out[k - 1].startswith('I ') else l for k, l in enumerate(out)]
    res, part, n, psalm, sec, names = [], None, None, 0, 0, titles()
    offices = 0
    for line in out:
        if line.startswith('@page'):
            part = line.split()[2]
        elif line.startswith('O '):
            line = 'T __EVENING PRAYER.__' if offices % 2 else 'T __MORNING PRAYER.__'
            offices += 1
        elif part == 'psalter' and is_title(line):
            psalm += 1
            line = names[psalm]
            n = 1
        elif part == 'psalter' and line.startswith('S '):
            sec += 1
            line = f'T __{PARTS_119[sec]}__'
            n = 1
        elif part == 'psalter' and n is not None and line.startswith('P '):
            # (A verse's first line: its number, whatever Tesseract read
            # there, a mark or two of noise before it.)
            rest = line[2:].split(' ')
            while rest and len(rest) > 1 and (re.search(r'\d', rest[0]) or not re.search(r'[A-Za-z]', rest[0])
                                               or rest[0] in ('g', 'q', 'o', 'ii', 'li', 'Ii', 'il', 'l', 'A', 'Z')
                                               and rest[1][:1].isupper()):
                rest = rest[1:]
            n += 1
            line = f'P {n} ' + ' '.join(rest)
        res.append(line)
    return res


def main():
    draft = json.load(open(os.path.join(WORK, 'draft.json')))
    geo = json.load(open(os.path.join(WORK, 'geometry.json')))
    out, where = [], []
    day = 0

    def put(line, box=None):
        out.append(line)
        where.append([leaf, box])

    for part, leaves in PARTS.items():
        if part == 'calendar':
            continue
        for leaf in leaves:
            d = draft.get(str(leaf))
            if not d:
                continue
            g = geo[str(leaf)]['frame']['outer']
            left = g[0] + 17 * PX  # (the text's edge: 17 points in from the rule)
            right = g[2] - 17 * PX
            put(f'@page {leaf} {part}')
            lines = d['lines']
            # (The day: Morning Prayer's head starts each; the page's head
            # the day at its top or, where a day starts on it, the new
            # one, as its own roman reads.)
            office = [k for k, l in enumerate(lines) if k and re.search(r'MORN', ' '.join(w['t'] for w in l['words']))]
            ends = day + len(office) if part == 'psalter' else day
            read = re.search(r'([ivxl]+)\s*\.?\s*D', ' '.join(w['t'] for w in lines[0]['words'])) if lines else None
            shown = day
            if read and read.group(1) in ROMAN_OF and day <= ROMAN_OF[read.group(1)] <= ends + 2:
                # (The head as legible: the day it reads, a Morning Prayer's
                # head the OCR missed taken as there.)
                shown = ROMAN_OF[read.group(1)]
                ends = max(ends, shown)
            self_day = ends
            wh = sorted(w['box'][3] - w['box'][1] for l in lines for w in l['words'] if len(w['t']) > 3)
            tall = wh[len(wh) // 2] * 1.6 if wh else 999
            after_initial = False
            # (The text's left edge on the scan: where most full lines start.)
            from PIL import Image
            im = Image.open(os.path.join(WORK, 'upright', f'{leaf:04d}.png')).convert('L')
            lo = left - 8 * PX
            firsts = [ink_left(im, l['words'][0]['box'], max(lo, l['words'][0]['box'][0])) if l['words'] else 0 for l in lines]
            starts = sorted(firsts[k] for k, l in enumerate(lines[1:-1], 1)
                            if l['words'] and (l['box'][2] - l['box'][0]) > 0.6 * (right - left))
            base = starts[len(starts) // 5] if starts else left
            for k, l in enumerate(lines):
                x0, y0, x1, y1 = box = l['box']
                ws = l['words']
                if not ws:
                    continue
                txt = ' '.join(w['t'] for w in ws)
                t = text_of(ws, roman=part == 'psalter' and not re.search(r'P\s*S\s*A\s*L|PRAY|MORN|EVEN', txt))
                ind = (x0 - left) / PX
                centred = abs((x0 + x1) / 2 - (left + right) / 2) < 12 * PX and ind > 25 and (right - x1) / PX > 25
                if k == 0 and (part != 'psalter' or leaf > 415) and not (part == 'morning-prayer' and leaf == 45) \
                        and not (part == 'litany' and leaf == 78):
                    put(head(part, leaf, shown), box)
                    continue
                tail = ''
                gaps = [(ws[j + 1]['box'][0] - ws[j]['box'][2]) / PX for j in range(len(ws) - 1)]
                if k == len(lines) - 1 and gaps and max(gaps) > 60 and abs(firsts[k] - base) / PX < 30 \
                        and (right - ws[-1]['box'][2]) / PX < 8 \
                        and any(re.search(r'[a-z]{3}', w['t']) for w in ws[:gaps.index(max(gaps)) + 1]):
                    # (A short last line, the catchword at its right on the
                    # line itself: ` @ ` before it.)
                    # (The catchword: the words at the right close together;
                    # a signature between it and the text.)
                    c = len(ws) - 1
                    while c > 0 and gaps[c - 1] < 15:
                        c -= 1
                    cut = next(j for j in range(len(ws)) if j == c - 1 or gaps[j] > 40) + 1
                    word = lambda w: re.search(r'[A-Za-z0-9]', w['t'])
                    sig = ' '.join(w['t'] for w in ws[cut:c] if word(w))
                    tail = ' @ ' + (sig + ' | ' if sig else '') + ' '.join(w['t'] for w in ws[c:] if word(w))
                    ws = ws[:cut]
                    x1 = ws[-1]['box'][2]
                    txt = ' '.join(w['t'] for w in ws)
                    t = text_of(ws, roman=part == 'psalter')
                elif k == len(lines) - 1 and (right - ws[-1]['box'][2]) / PX < 8 and len(ws) <= 5 \
                        and len([w for w in ws if re.search(r'[A-Za-z]{2}', w['t'])]) <= 3:
                    # (The foot: a catchword at the right, a signature
                    # before it.)
                    catch = [w for w in ws if (right - w['box'][2]) / PX < 8 or w is ws[-1]]
                    if len(ws) > 1 and re.match(r'^\d+$', ws[-2]['t']) and (ws[-1]['box'][0] - ws[-2]['box'][2]) / PX < 8:
                        catch = ws[-2:]  # (A verse's number caught with its word.)
                    sig = [w for w in ws if w not in catch and re.search(r'[A-Za-z0-9]', w['t'])]
                    t = ' '.join(w['t'] for w in sig)
                    put('f ' + (t + ' | ' if t else '') + ' '.join(w['t'] for w in catch), box)
                    continue
                elif ws[0]['box'][3] - ws[0]['box'][1] > tall and ws[0]['t'][:1].isupper():
                    kind = 'I'
                elif after_initial:
                    # (The line beside an initial: its paragraph's.)
                    kind = ' '
                elif part == 'psalter' and (re.search(r'(MORN|EVEN)', t) and len(ws) <= 4 or office_like(txt)):
                    # (Morning's and Evening's heads alternate: verses() names them.)
                    put('O ' + t, box)
                    continue
                elif part == 'psalter' and l.get('kind') == 'S':
                    kind = 'S'
                elif part == 'psalter' and 9 < (firsts[k] - base) / PX < 30:
                    kind = 'P'
                elif part == 'psalter' and not centred:
                    kind = ' '
                elif centred:
                    kind = 'T'
                elif ind > INDENT * 0.5 and ind < 50:
                    kind = 'P'
                elif l.get('start') and l.get('kind') in ('R',):
                    kind = 'R'
                else:
                    kind = ' '
                after_initial = kind == 'I'
                put(f'{kind} {t}{tail}', box)
            day = self_day if part == 'psalter' else 0
    json.dump(where, open(os.path.join(WORK, 'where.json'), 'w'))
    print('\n'.join(verses(out)))


main()
