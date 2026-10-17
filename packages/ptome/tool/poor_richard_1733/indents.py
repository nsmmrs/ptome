"""Each line of each month's verse set in as far as the printing sets it
(adjust.json's `month/verse/N`, `{"in": points}`, gen.py's spans): the
PDF built, each verse line's left end on it (its ink, measure.py's) less
the scan's, its indent moved by that, again until no line is off by more
than a few tenths of a point.

    python3 -I indents.py [ROUNDS]
"""
import json, os, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
ROUNDS = int(sys.argv[1]) if len(sys.argv) > 1 else 3
del sys.argv[1:]
import measure

PDF = os.path.join(measure.WORK, 'build', 'poor-richard.pdf')
NAMES = ['january', 'february', 'march', 'april', 'may', 'june', 'july', 'august',
         'september', 'october', 'november', 'december']
path = os.path.join(HERE, 'adjust.json')
scan = json.load(open(os.path.join(measure.WORK, 'measure.json')))
for n in range(ROUNDS):
    adjust = json.load(open(path)) if os.path.exists(path) else {}
    subprocess.run([os.path.join(HERE, 'build.sh')], check=True, stdout=subprocess.DEVNULL)
    worst = 0
    for leaf, name in zip(measure.MONTHS, NAMES):
        page = measure.month_page(PDF, leaf)
        got = measure.pdf_text(PDF, page)
        ends = measure.line_extents(measure.pdf_page(PDF, page), got['verse'])
        for i, (e, want) in enumerate(zip(ends, scan[str(leaf)]['verse_ends'])):
            if not e or not want:
                continue
            off = e[0] - want[0]
            worst = max(worst, abs(off))
            key = f'{name}/verse/{i + 1}'
            if abs(off) > 0.15:
                a = adjust.setdefault(key, {})
                a['in'] = round(max(0, a.get('in', 0) - off), 2)
    json.dump(dict(sorted(adjust.items())), open(path, 'w'), indent=0)
    print(f'round {n + 1}: the most {worst:.2f} pt')
    if worst < 0.3:
        break
