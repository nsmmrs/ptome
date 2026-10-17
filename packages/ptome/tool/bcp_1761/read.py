"""Readings off the scan for the words decide.py flagged: from a sheet's
numbers (sheets.py's index) to readings.tsv (leaf, the word's box's top
left, the reading), which decide.py takes before anything else; an
empty reading, no word there (a mark of the frame Tesseract read).

    python3 -I read.py < N<TAB>READING lines
"""
import os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from common import WORK

index = {}
for line in open(os.path.join(WORK, 'sheets', 'index.tsv'), encoding='utf-8'):
    n, leaf, at, text = line.rstrip('\n').split('\t')
    index[n] = (leaf, at)
path = os.path.join(HERE, 'readings.tsv')
have = {}
if os.path.exists(path):
    for line in open(path, encoding='utf-8'):
        leaf, at, text = line.rstrip('\n').split('\t')
        have[(leaf, at)] = text
for line in sys.stdin:
    if not line.strip():
        continue
    n, _, text = line.rstrip('\n').partition('\t')
    have[index[n.strip()]] = text
open(path, 'w', encoding='utf-8').write(''.join(f'{l}\t{a}\t{t}\n' for (l, a), t in sorted(have.items(), key=lambda kv: (int(kv[0][0]), kv[0][1]))))
print(len(have), 'readings')
