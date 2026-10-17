"""The three pages' printed lines, column by column, from the Internet
Archive's OCR (ABBYY, `b30451541_0002_djvu.txt`), in reading order: each
page's first and second columns between their heads and its foot line.

    python3 -I lines.py -> JOHNSON_WORK/lines.tsv (page, column, n, text)
"""
import os, re
WORK = os.environ.get('JOHNSON_WORK', os.path.expanduser('~/.cache/asciidart-work/print-match/johnson'))

# (Each column's lines in the OCR: first and last line numbers, the
# heads and feet left out.)
COLUMNS = {(46, 1): (11230, 11373), (46, 2): (11375, 11542),
           (47, 1): (11547, 11693), (47, 2): (11695, 11842),
           (48, 1): (11853, 11991), (48, 2): (11992, 12130)}


def main():
    raw = open(f'{WORK}/djvu.txt', encoding='utf-8').read().split('\n')
    out = []
    for (page, col), (a, b) in sorted(COLUMNS.items()):
        n = 0
        for line in raw[a - 1:b]:
            t = re.sub(r'\s+', ' ', line).strip()
            if not t:
                continue
            n += 1
            out.append(f'{page}\t{col}\t{n}\t{t}')
    open(f'{WORK}/lines.tsv', 'w', encoding='utf-8').write('\n'.join(out) + '\n')
    for key in sorted(COLUMNS):
        print(key, sum(1 for l in out if l.startswith(f'{key[0]}\t{key[1]}\t')))


if __name__ == '__main__':
    main()
