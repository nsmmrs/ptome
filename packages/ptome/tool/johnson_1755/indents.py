"""The lines the printing sets in otherwise than their paragraph's
others (a verse quotation's half line, a verse line's turned word, a verse quotation's first line set no further in
than the rest): each
line's left end on the scan against the PDF's (compare.py), and for the
lines the scan has further in by more than 3 pt than the PDF sets them,
the span that sets them in that much more (indents.json, gen.py's
`[.iNN]` spans), to the half point; the verse quotations the scan sets
flat, their first line 8 pt or more further out than the PDF's, given
the role `flat` (indents.json's `flat`, page/column/block). With `--roles`, the median of each
kind of line instead: how far the look's indents are off.

    python3 -I indents.py [--roles]
"""
import collections, json, os, statistics, sys
ROLES = '--roles' in sys.argv
del sys.argv[1:]
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import compare

HERE = compare.HERE
path = os.path.join(HERE, 'indents.json')
indents = json.load(open(path)) if os.path.exists(path) else {}
fit = json.load(open(os.path.join(compare.WORK, 'fit.json')))
lines = {(f['page'], f['column'], f['line']): f for f in fit if isinstance(f['line'], int)}
report = compare.run(quiet=True)
report.pop('bad_words')
kinds = collections.defaultdict(list)
for page, r in report.items():
    for d in r['lines']:
        f = lines[(page, d['column'], d['line'])]
        key = f'{page}/{d["column"]}/{d["line"]}'
        own = indents.get(key, 0) if key != 'flat' else 0
        kind = f['kind'] + ('1' if f['first'] else 'n') + ('a' if f['text'].startswith('@') else '')
        if not own:
            kinds[kind].append(d['left'])
        # (The PDF's left end less the scan's: how much further in the
        # scan sets the line.)
        more = -d['left']
        # (A verse quotation's first line the printing sets no further
        # in than the rest: the paragraph's first line flat.)
        flat = f'{page}/{d["column"]}/{f["block"]}'
        if not ROLES and kind == 'V1' and more < -8 and flat not in indents.get('flat', []):
            indents.setdefault('flat', []).append(flat)
            continue
        if not ROLES and kind[-1] != 'a' and more > 3 or own and abs(more) > 0.3:
            width = round((own + more) * 2) / 2
            if width > 0:
                indents[key] = width
            else:
                indents.pop(key, None)
if ROLES:
    for k, v in sorted(kinds.items()):
        print(k, len(v), f'{statistics.median(v):+.2f}')
else:
    flat = sorted(indents.pop('flat', []), key=lambda k: [int(x) for x in k.split('/')])
    spans = sorted(indents.items(), key=lambda kv: [int(x) for x in kv[0].split('/')])
    json.dump(dict(spans, flat=flat), open(path, 'w'), indent=0)
    print(len(spans), 'lines set in;', len(flat), 'verse quotations flat')
