"""The units corpus's Prayer Book (test/units/corpus/liturgy/bcp-1662),
each part as the scan's words are read against: its words in order,
each with its block's kind (`H` a head, `R` a rubric, `P` a paragraph,
`V` a verse of a psalm or a canticle, `T` a psalm's title) and whether
it starts the block; a psalm's verses numbered as the printing numbers
them (the first not: its initial), the Litany's responses printed after
each petition as the printing prints them. And the vocabulary the words
are checked against: the corpus's words and the King James Bible's.

    from corpus import part_tokens, vocabulary
"""
import os, re

HERE = os.path.dirname(os.path.abspath(__file__))
CORPUS = os.path.join(HERE, '..', '..', 'test', 'units', 'corpus')
BCP = os.path.join(CORPUS, 'liturgy', 'bcp-1662')
ORDINALS = [''] + ('FIRST SECOND THIRD FOURTH FIFTH SIXTH SEVENTH EIGHTH NINTH TENTH ELEVENTH TWELFTH '
                    'THIRTEENTH FOURTEENTH FIFTEENTH SIXTEENTH SEVENTEENTH EIGHTEENTH NINETEENTH TWENTIETH').split() + \
    [f'TWENTY-{w}' for w in 'FIRST SECOND THIRD FOURTH FIFTH SIXTH SEVENTH EIGHTH NINTH'.split()] + ['THIRTIETH']
ROMAN = ['', 'i', 'ii', 'iii', 'iv', 'v', 'vi', 'vii', 'viii', 'ix']
TENS = ['', 'x', 'xx', 'xxx', 'xl', 'l', 'lx', 'lxx', 'lxxx', 'xc']


def roman(n):
    return 'c' * (n // 100) + TENS[n % 100 // 10] + ROMAN[n % 10]


def plain(text):
    """A corpus line's words, its markup gone: a cross-reference its
    label, a role's span its text."""
    text = re.sub(r'<<[^,>]*,([^>]*)>>', r'\1', text)
    text = re.sub(r'\[\.[^\]]*\]#(.*?)#', r'\1', text)
    text = re.sub(r'\[[^\]]*\]', '', text)
    text = text.replace(' +', '').replace('__', '').replace('_', '').replace('*', '')
    text = text.replace('&#91;', '[').replace('&#93;', ']').replace("'", '’')
    return text


def words(text, kind, out):
    first = True
    for w in plain(text).split():
        out.append({'t': w, 'k': kind, 's': first})
        first = False


# (Psalm cxix.'s parts, each under its Latin, its verses numbered afresh.)
PARTS_119 = ('Beati immaculati.', 'In quo corriget?', 'Retribue servo tuo.', 'Adhaesit pavimento.',
             'Legem pone.', 'Et veniat super me.', 'Memor esto servi tui.', 'Portio mea, Domine.',
             'Bonitatem fecisti.', 'Manus tuae fecerunt me.', 'Defecit anima mea.',
             'In aeternum, Domine.', 'Quomodo dilexi!', 'Lucerna pedibus meis.', 'Iniquos odio habui.',
             'Feci judicium.', 'Mirabilia.', 'Justus es, Domine.', 'Clamavi in toto corde meo.',
             'Vide humilitatem.', 'Principes persecuti sunt.', 'Appropinquet deprecatio.')


def psalter():
    out = []
    days = {}
    for line in open(os.path.join(BCP, 'days.adoc'), encoding='utf-8'):
        m = re.match(r'Day (\d+), (Morning|Evening) Prayer:: (\d+)', line)
        if m:
            days[int(m.group(3))] = (int(m.group(1)), m.group(2))
    n = 0
    verse = 0
    part = 0
    for line in open(os.path.join(BCP, 'psalter.adoc'), encoding='utf-8'):
        line = line.rstrip('\n')
        m = re.match(r'^== @ (.*)$', line)
        if m:
            n += 1
            verse = 0
            if n in days:
                day, when = days[n]
                if when == 'Morning':
                    words(f'THE {ORDINALS[day]} DAY.', 'D', out)
                words(f'{when.upper()} PRAYER.', 'D', out)
            words(f'PSAL. {roman(n)}. {m.group(1)}', 'T', out)
            continue
        m = re.match(r'^@ (.*)$', line)
        if m:
            if n == 119 and verse == 8:
                part += 1
                verse = 0
                words(PARTS_119[part], 'S', out)
            verse += 1
            words((f'{verse} ' if verse > 1 else '') + m.group(1).replace(' :', ':'), 'V', out)
    return out


def office(name):
    out = []
    lines = open(os.path.join(BCP, f'{name}.adoc'), encoding='utf-8').read().split('\n')
    kind, response = 'P', None
    for line in lines:
        s = line.strip()
        if not s or s.startswith(':units:') or s.startswith(':works:') or s.startswith(':sectids') or s.startswith('= '):
            continue
        if s.startswith(':response:'):
            response = s.split(':', 2)[2].strip()
            continue
        if s == '[.rubric]':
            kind = 'R'
            continue
        if s.startswith('['):
            continue
        if s.startswith('== '):
            words(s[3:], 'H', out)
            kind = 'P'
            continue
        if s.startswith('@ '):
            words(s[2:], 'P', out)
            if response:
                words(response, 'S', out)
            continue
        words(s, kind, out)
        kind = 'P'
    return out


def part_tokens(part):
    if part == 'psalter':
        return psalter()
    return office(part)


_VOCAB = None


def vocabulary():
    global _VOCAB
    if _VOCAB is None:
        vocab = set()
        sources = [os.path.join(BCP, f) for f in os.listdir(BCP) if f.endswith('.adoc')]
        books = os.path.join(CORPUS, 'bible', 'kjv', 'books')
        sources += [os.path.join(books, f) for f in os.listdir(books)]
        for path in sources:
            for w in re.findall(r"[A-Za-z’']+", open(path, encoding='utf-8').read()):
                vocab.add(w.lower().replace("'", '’'))
        _VOCAB = vocab
    return _VOCAB
