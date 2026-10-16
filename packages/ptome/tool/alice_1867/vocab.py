"""The vocabulary an OCR word is checked against (a word in it is
English, one not in it most likely misread): the words of the showcase's
committed texts as Standard Ebooks and Project Gutenberg give them, the
Gutenberg texts of both books (pg/*.txt in the work folder: eBooks #11,
#12, #114, #19002, #19033, #28885, fetched from
https://www.gutenberg.org/cache/epub/N/pgN.txt) and the system's word
list (/usr/share/dict/cracklib-small).

    python3 -I vocab.py
"""
import collections, glob, json, os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import ROOT, WORK

words = collections.Counter()
texts = glob.glob(os.path.join(os.path.dirname(WORK), '*', 'text', '**', '*.adoc'), recursive=True)
texts += glob.glob(os.path.join(ROOT, 'pg', '*.txt'))
for path in texts:
    for w in re.findall(r"[A-Za-z]+(?:['’][A-Za-z]+)?", open(path, encoding='utf-8', errors='ignore').read()):
        words[w.lower().replace('’', "'")] += 1
for w in open('/usr/share/dict/cracklib-small', errors='ignore'):
    words[w.strip().lower()] += 1
json.dump(words, open(os.path.join(ROOT, 'vocab.json'), 'w'))
print(len(words), 'words')
