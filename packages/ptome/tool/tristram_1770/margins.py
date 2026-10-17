"""Each block's space above it (adjust.json's `top/PAGE/LINE`, gen.py's,
keyed by its first line): its first line's baseline on the PDF against
the scan's (scan.json), its margin moved by its error less what the
blocks above it on the page are moved already; a few rounds, the book
built each (build.sh). A page whose lines are not the spec's fitted only
while they are.

    python3 -I margins.py [ROUNDS] [PAGE...]   (SPLIT=PT the line's error that
                                               parts its paragraph, 0 none)
"""
import json, os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ARGS = sys.argv[1:]
ROUNDS = int(ARGS[0]) if ARGS else 2
PAGES = ARGS[1:] or None
sys.argv = sys.argv[:1]
sys.path.insert(0, HERE)
import compare

PATH = os.path.join(HERE, 'adjust.json')
# (A line further than this off its scan's after the fit: its paragraph
# parted there; SPLIT=0 none.)
SPLIT = float(os.environ.get('SPLIT', '0.9'))


def main():
    for n in range(ROUNDS):
        subprocess.run([os.path.join(HERE, 'build.sh')], check=True, stdout=subprocess.DEVNULL)
        adjust = json.load(open(PATH)) if os.path.exists(PATH) else {}
        report = compare.run(PAGES, quiet=True)
        bad = compare.mismatched()
        worst = 0.0
        for page, rows in report.items():
            running, seen = 0.0, set()
            for r in rows:
                if r['block'] in seen or not r['key']:
                    continue
                if page in bad and not r['same']:
                    # (The page set otherwise from here: its margins from
                    # here on forgotten, fitted again once it is the spec's.)
                    for q in rows:
                        if q['line'] >= r['line'] and q['key'] and q['block'] not in seen:
                            adjust.pop(q['key'], None)
                    break
                seen.add(r['block'])
                off = -r['base'] - running
                if abs(off) > 0.05:
                    # (A margin no less than the page lets: the first
                    # block's from the page's top margin.)
                    new = round(adjust.get(r['key'], 0) + off, 2)
                    adjust[r['key']] = max(new, -30.0)
                    running += off
                worst = max(worst, abs(off))
        if SPLIT and n < ROUNDS - 1:
            # (A paragraph's line still more than a point off once its
            # first line is fitted: the paragraph parted there (gen.py),
            # the part below fitted on its own; an initial's two lines
            # kept together.)
            parts = 0
            for page, rows in report.items():
                if page in bad:
                    continue
                first = {}
                for r in rows:
                    first.setdefault(r['block'], r)
                for r in rows:
                    f = first[r['block']]
                    if r is f or abs(r['base']) <= SPLIT or r['kind'] in ('h', 'f', 'X', 'Y', 'C', 'R'):
                        continue
                    if f['kind'] == 'I' and r['line'] <= f['line'] + 1:
                        # (An initial's second line off: its paragraph
                        # parted after it, the two lines' pitch the scan's.)
                        key = f"split/{page}/{f['line'] + 2}"
                        if not adjust.get(key) and any(q['line'] == f['line'] + 2 for q in rows):
                            adjust[key] = 1
                            parts += 1
                            break
                        continue
                    key = f"split/{page}/{r['line']}"
                    if not adjust.get(key):
                        adjust[key] = 1
                        parts += 1
                        break
            print(f'  {parts} paragraphs parted')
        json.dump(dict(sorted(adjust.items())), open(PATH, 'w'), indent=0)
        print(f'round {n + 1}: the most {worst:.2f} pt; pages not the spec\'s: {sorted(bad)[:8]}')
    subprocess.run([os.path.join(HERE, 'build.sh')], check=True, stdout=subprocess.DEVNULL)


main()
