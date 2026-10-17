"""The draft's words against Standard Ebooks': where they differ, by
chapter, letters only (case, punctuation and markup aside), with the
draft's line ids, for review.

    python3 -I textdiff.py BOOK
"""
import difflib, os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import BOOKS, ROOT, REPO


def words(text):
    text = re.sub(r'^//.*$|^\[.*\]$|^image::.*$|^=+ .*$|^\'\'\'$', '', text, flags=re.M)
    text = re.sub(r'\{(shy|zwsp|nbsp)\}', '', text).replace('⁠', '').replace(' ', '')
    return [w for w in (re.sub(r'[^0-9a-z]', '', t.lower()) for t in re.split(r'[\s—-]+', text)) if w]


def main(book):
    lines = {}
    for row in open(f'{ROOT}/out/{book}/lines.tsv', encoding='utf-8'):
        lid, _, t = row.rstrip('\n').partition('\t')
        lines.setdefault(lid, t)
    for n in range(1, BOOKS[book]['chapters'] + 1):
        d = open(f'{ROOT}/out/{book}/chapter-{n}.adoc', encoding='utf-8').read()
        s = open(f'{REPO}/text/{book}/chapter-{n}.adoc', encoding='utf-8').read()
        a, b = words(s), words(d)
        sm = difflib.SequenceMatcher(None, a, b, autojunk=False)
        for op, i1, i2, j1, j2 in sm.get_opcodes():
            if op != 'equal':
                print(f'ch{n} {op}: SE {" ".join(a[max(0,i1-3):i2+3])!r} | draft {" ".join(b[max(0,j1-3):j2+3])!r}')


if __name__ == '__main__':
    main(sys.argv[1])
