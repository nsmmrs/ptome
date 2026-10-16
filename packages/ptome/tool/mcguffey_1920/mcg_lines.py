"""Gutenberg's words (the work's reader.adoc) on the printing's lines (the
scan's OCR): per leaf, each OCR line as the text's words, with the OCR
words the text has no match for flagged.

    python3 -I mcg_lines.py READER.adoc OCR.json FIRST LAST > draft.txt
"""
import difflib, json, re, sys, unicodedata

reader, ocr_path, first, last = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])


def core(t):
    t = unicodedata.normalize('NFKD', t)
    return re.sub(r'[^0-9a-z]', '', t.lower())


# The text's words, markup stripped (tables and images left out).
words = []
skip = False
for line in open(reader, encoding='utf-8'):
    s = line.rstrip('\n')
    if s.startswith('|==='):
        skip = not skip
        continue
    if skip or s.startswith(('image::', '[', '//', 'include::', '____', "'''")) or not s.strip():
        continue
    s = re.sub(r'^=+ ', '', s)
    s = s.replace(' +', '')
    s = re.sub(r'^\. ', '#. ', s)
    for w in s.split():
        if core(w) or w in ('—',):
            words.append(w)

P = json.load(open(ocr_path))
ocr = []  # (leaf, line index, word, the part before the line's end)
for leaf in range(first, last + 1):
    for i, l in enumerate(P[leaf]['lines']):
        for w in l['w']:
            if core(w['t']):
                ocr.append([leaf, i, w['t'], None])
# (A word divided at a line's end: one word, on the first line.)
merged = []
k = 0
while k < len(ocr):
    o = ocr[k]
    if o[2].endswith('-') and k + 1 < len(ocr) and ocr[k + 1][:2] != o[:2]:
        n = ocr[k + 1]
        merged.append([o[0], o[1], o[2][:-1] + n[2], o[2][:-1]])
        k += 2
        continue
    merged.append(o)
    k += 1
ocr = merged

a = [core(w) for w in words]
b = [core(w[2]) for w in ocr]
sm = difflib.SequenceMatcher(None, a, b, autojunk=False)
place = {}  # text word index -> (leaf, line)
sm_index = {}
flags = {}
for tag, i1, i2, j1, j2 in sm.get_opcodes():
    if tag == 'equal' or (tag == 'replace' and i2 - i1 == j2 - j1):
        for k in range(i2 - i1):
            place[i1 + k] = tuple(ocr[j1 + k][:2])
            sm_index[i1 + k] = j1 + k
            if tag == 'replace':
                flags.setdefault(tuple(ocr[j1 + k][:2]), []).append(f'{words[i1 + k]}/{ocr[j1 + k][2]}')
    elif tag == 'replace' or tag == 'insert':
        for k in range(j1, j2):
            flags.setdefault(tuple(ocr[k][:2]), []).append(f'?{ocr[k][2]}')
        if tag == 'replace':
            for k in range(i1, i2):
                place[k] = tuple(ocr[min(j1 + (k - i1), j2 - 1)][:2])
# (Text words with no OCR word: on the line of the word before.)
lines = {}
prev = None
for k, w in enumerate(words):
    p = place.get(k, prev)
    if p is None:
        continue
    j = sm_index.get(k)
    if j is not None and ocr[j][3]:
        # (Divided where the printing divides it: a soft hyphen, or after
        # its own hyphen.)
        head = core(ocr[j][3])
        n = 0
        cut = len(w)
        for ci, ch in enumerate(w):
            if core(ch):
                n += 1
            if n == len(head):
                cut = ci + 1
                break
        w = w[:cut] + ('{zwsp}' if w[cut - 1] == '-' or (cut < len(w) and w[cut] == '-') else '{shy}') + w[cut:].lstrip('-') if cut < len(w) else w
        if '-{zwsp}' not in w and '{zwsp}' in w:
            w = w.replace('{zwsp}', '-{zwsp}', 1)
    lines.setdefault(p, []).append(w)
    prev = p
for leaf in range(first, last + 1):
    print(f'== leaf {leaf}')
    for i, l in enumerate(P[leaf]['lines']):
        text = ' '.join(lines.get((leaf, i), []))
        ocr_text = ' '.join(w['t'] for w in l['w'])
        f = flags.get((leaf, i))
        print(f'{leaf}:{i}\t{l["b"][0]}\t{text}' + (f'\t!! {f}  [{ocr_text}]' if f else ''))
