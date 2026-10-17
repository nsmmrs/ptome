"""Each block's space above it (adjust.json's `top/PAGE/COLUMN/LINE`,
gen.py's, keyed by its first line): its first line's baseline on the PDF
against the scan's (scan.json), its margin moved by its error less what
the blocks above it in its column are moved already; a few rounds.

    python3 -I margins.py [ROUNDS] [PAGE...]
"""
import json, os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ARGS = sys.argv[1:]
ROUNDS = int(ARGS[0]) if ARGS else 2
PAGES = [int(a) for a in ARGS[1:]] or None
sys.argv = sys.argv[:1]
sys.path.insert(0, HERE)
import compare

PATH = os.path.join(HERE, 'adjust.json')


def main():
    for n in range(ROUNDS):
        subprocess.run([os.path.join(HERE, 'build.sh')], check=True, stdout=subprocess.DEVNULL)
        adjust = json.load(open(PATH)) if os.path.exists(PATH) else {}
        report = compare.run(PAGES, quiet=True)
        bad = compare.mismatched()
        worst = 0.0
        # (The cuts first: each image's top on the PDF against the scan's,
        # the page's images and its cuts in order, `cut/ID`; a page whose
        # cuts moved, its text fitted in the next round, round them as
        # they will stand.)
        moved = set()
        fit = json.load(open(os.path.join(compare.WORK, 'fit.json')))
        cuts = json.load(open(os.path.join(compare.WORK, 'cuts.json')))
        boxes = {c['id']: c['pt'] for v in cuts.values() for c in v}
        for page in report:
            ids = [f['cut'] for f in fit if f['page'] == page and f.get('cut')]
            got = sorted(compare.images(compare.page_index(page)), key=lambda b: (b[1], b[0]))
            want = sorted(ids, key=lambda i: (boxes[i][1], boxes[i][0]))
            if len(got) != len(want):
                continue
            for cid, box in zip(want, got):
                # (An image not where its cut is across the page, gone on
                # into the next column for now: left as it is.)
                if abs(box[0] - boxes[cid][0]) > 20:
                    continue
                # (A strip as tall as the column, the alphabet's cuts: where
                # gen.py puts it, under the line over it, no room to fit.)
                if boxes[cid][3] - boxes[cid][1] > 400:
                    continue
                off = box[1] - boxes[cid][1]
                if abs(off) > 0.2:
                    adjust[f'cut/{cid}'] = round(adjust.get(f'cut/{cid}', 0) - off, 2)
                    if abs(off) > 1:
                        moved.add(page)
                worst = max(worst, abs(off))
        for page, rows in report.items():
            if page in moved and n < ROUNDS - 1:
                continue
            # (A page with a block floating at a column's side: the float
            # fitted first, alone, the lines beside it set round it as it
            # will stand.)
            floats = any(r['col'] > 2 for r in rows)
            for c in ((3, 4) if floats and n == 0 else (1, 2, 3, 4)):
                running = 0.0
                seen = set()
                for r in rows:
                    if r['col'] != c or r['block'] in seen or not r['key']:
                        continue
                    # (A column not the spec's: its blocks fitted only while
                    # the PDF's lines are the spec's.)
                    if (page, c) in bad and not r['same']:
                        # (Two lines on one: a block after drawn up onto the
                        # one before by a margin an earlier round gave it,
                        # the column out of step since; that margin
                        # forgotten, to fit again from the look's.)
                        for f in rows:
                            if (f['col'] == c and f['key'] and f['line'] in (r['line'], r['line'] + 1)
                                    and adjust.get(f['key'], 0) < 0):
                                adjust.pop(f['key'])
                        break
                    seen.add(r['block'])
                    off = -r['base'] - running
                    if abs(off) > 0.05:
                        adjust[r['key']] = round(adjust.get(r['key'], 0) + off, 2)
                        running += off
                    worst = max(worst, abs(off))
        json.dump(dict(sorted(adjust.items())), open(PATH, 'w'), indent=0)
        print(f'round {n + 1}: the most {worst:.2f} pt; columns not the spec\'s: {sorted(bad)[:8]}')
    subprocess.run([os.path.join(HERE, 'build.sh')], check=True, stdout=subprocess.DEVNULL)


main()
