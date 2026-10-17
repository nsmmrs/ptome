"""The calendar's cells the PDF sets on two lines where the printing
sets them on one: each row whose next row's day is more than a pitch
and a half below it, with its text; written to wraps.json for gen.py,
which sets their letters closer (`[.tight]`, the look's) until they fit.

    python3 -I wraps.py
"""
import json, os, re, subprocess, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import measure

PDF = os.path.join(measure.WORK, 'build', 'poor-richard.pdf')
NAMES = ['january', 'february', 'march', 'april', 'may', 'june', 'july', 'august',
         'september', 'october', 'november', 'december']
path = os.path.join(measure.HERE, 'wraps.json')
wraps = json.load(open(path)) if os.path.exists(path) else {}
found = 0
for leaf, name in zip(measure.MONTHS, NAMES):
    g = measure.pdf_text(PDF, measure.month_page(PDF, leaf))
    rows = g['rows']
    # (A last row carried to the next page: wrapped, the page too full.)
    if len(rows) < measure.counts()[leaf]['rows']:
        key = f'{name}/{len(rows) + 1}'
        wraps[key] = wraps.get(key, 0) + 1
        found += 1
        print(key, '(carried over)')
    for day in range(1, len(rows)):
        if rows[day] - rows[day - 1] > 16:
            key = f'{name}/{day}'
            wraps[key] = wraps.get(key, 0) + 1
            found += 1
            print(key)
json.dump(dict(sorted(wraps.items())), open(path, 'w'), indent=0)
print(found, 'rows wrapped')
