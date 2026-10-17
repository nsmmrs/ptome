"""Each column's lines' pitch, the scan's (adjust.json's
`pitch/page/column`, gen.py's `p<hundredths>` roles): the median of the
gaps between the lines of a block on the scan (scan.json), a pitch or
near it. The paper stretches a little differently on each leaf.

    python3 -I pitch.py
"""
import json, os, statistics
HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.environ.get('TEMPEST_WORK', os.path.expanduser('~/.cache/asciidart-work/print-match/tempest'))
fit = json.load(open(os.path.join(WORK, 'fit.json')))
scan = json.load(open(os.path.join(WORK, 'scan.json')))
path = os.path.join(HERE, 'adjust.json')
adjust = json.load(open(path)) if os.path.exists(path) else {}
for page in range(1, 20):
    for c in ((1, 2, 3, 4) if page == 19 else (1, 2)):
        f = [x for x in fit if x['page'] == page and x['col'] == c and isinstance(x['line'], int)]
        s = scan.get(str(page), [[], []])[c - 1]
        if len(s) != len(f):
            continue
        gaps = [s[i]['base'] - s[i - 1]['base'] for i in range(1, len(f)) if f[i]['block'] == f[i - 1]['block']]
        gaps = [g for g in gaps if 11.5 < g < 16.5]
        if len(gaps) > 10:
            adjust[f'pitch/{page}/{c}'] = round(statistics.median(gaps), 2)
json.dump(dict(sorted(adjust.items())), open(path, 'w'), indent=0)
print(sorted({v for k, v in adjust.items() if k.startswith('pitch/')}))
