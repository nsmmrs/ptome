"""Each month's verse and calendar moved to where the scan has them
(adjust.json's `month/margin/verse`, `month/margin/table`): the PDF
built (build.sh), measured as the scan is (measure.py), each block moved
by how far its lines are off (the verse by its lines' median, the
calendar by its rows'), again until none is off by more than a few
tenths of a point.

    python3 -I fit.py [ROUNDS]
"""
import json, os, statistics, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
ROUNDS = int(sys.argv[1]) if len(sys.argv) > 1 else 5
del sys.argv[1:]
import measure
from PIL import Image

PDF = os.path.join(measure.WORK, 'build', 'poor-richard.pdf')
NAMES = ['january', 'february', 'march', 'april', 'may', 'june', 'july', 'august',
         'september', 'october', 'november', 'december']


def main():
    path = os.path.join(HERE, 'adjust.json')
    adjust = json.load(open(path)) if os.path.exists(path) else {}
    scan = json.load(open(os.path.join(measure.WORK, 'measure.json')))
    c = measure.counts()
    for n in range(ROUNDS):
        subprocess.run([os.path.join(HERE, 'build.sh')], check=True, stdout=subprocess.DEVNULL)
        worst = 0
        for leaf, name in zip(measure.MONTHS, NAMES):
            got = measure.pdf_text(PDF, measure.month_page(PDF, leaf))
            want = scan[str(leaf)]
            r = {'head': got['head'][0] - want['head'][0],
                 'verse': [a - b for a, b in zip(got['verse'], want['verse'])],
                 'rows': [a - b for a, b in zip(got['rows'], want['rows'])]}
            verse = statistics.median(r['verse'])
            # (The calendar moved by its rows less the verse's move, which
            # moves it too.)
            rows = statistics.median(r['rows']) - verse
            for key, off in ((f'{name}/margin/verse', verse), (f'{name}/margin/table', rows)):
                worst = max(worst, abs(off))
                if abs(off) > 0.1:
                    adjust[key] = round(adjust.get(key, 0) - off, 2)
            print(f'  {name}: verse {verse:+.2f}, rows {rows:+.2f}, head {r["head"]:+.2f}')
        json.dump(dict(sorted(adjust.items())), open(path, 'w'), indent=0)
        print(f'round {n + 1}: the most {worst:.2f} pt')
        if worst < 0.3:
            break


main()
