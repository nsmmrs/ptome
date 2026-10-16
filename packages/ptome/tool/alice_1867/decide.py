"""Turn a sheet's decisions (`N CODE`: s SE, o OCR, x none, i/r italic,
=TEXT) into decisions/BOOK.tsv lines (choice id, value)."""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import ROOT

book, path = sys.argv[1], sys.argv[2]
index = json.load(open(f'{ROOT}/review/{book}-index.json'))
choices = {c['id']: c for c in json.load(open(f'{ROOT}/choices-{book}.json'))}
out = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'decisions', f'{book}.tsv'), 'a', encoding='utf-8')
for line in open(path, encoding='utf-8'):
    line = line.rstrip('\n')
    if not line.strip() or line.startswith('#'):
        continue
    n, _, code = line.partition(' ')
    if n.startswith('line:'):
        out.write(f'{n}\t{code}\n')
        continue
    cid = index[n]
    c = choices[cid]
    if code == 's':
        value = c['se']
    elif code == 'o':
        value = c['ocr']
    elif code == 'x':
        value = ''
    elif code in ('i', 'r'):
        assert c['kind'] == 'italic', (n, c)
        value = code
    elif code.startswith('='):
        value = code[1:]
    else:
        raise SystemExit(f'bad code {line}')
    out.write(f'{cid}\t{value}\n')
