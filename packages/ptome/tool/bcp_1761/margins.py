"""Each block's space above it (adjust.json's `top/LEAF/LINE`, gen.py's,
keyed by its first line): its first line's baseline on the PDF against
the scan's (scan.json), its margin moved by its error less what the
blocks above it on the page are moved already; a few rounds, the page
built each (build.sh). A page whose lines are not the spec's fitted only
while they are.

    python3 -I margins.py [ROUNDS] [LEAF...]
"""
import json, os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ARGS = sys.argv[1:]
ROUNDS = int(ARGS[0]) if ARGS else 2
LEAVES = [int(a) for a in ARGS[1:]] or None
sys.argv = sys.argv[:1]
sys.path.insert(0, HERE)
import compare

PATH = os.path.join(HERE, 'adjust.json')


def main():
    for n in range(ROUNDS):
        subprocess.run([os.path.join(HERE, 'build.sh')], check=True, stdout=subprocess.DEVNULL)
        adjust = json.load(open(PATH)) if os.path.exists(PATH) else {}
        report = compare.run(LEAVES, quiet=True)
        bad = compare.mismatched()
        worst = 0.0
        for leaf, rows in report.items():
            running, seen = 0.0, set()
            for r in rows:
                if r['block'] in seen or not r['key']:
                    continue
                if leaf in bad and not r['same']:
                    break
                seen.add(r['block'])
                off = -r['base'] - running
                if abs(off) > 0.05:
                    adjust[r['key']] = round(adjust.get(r['key'], 0) + off, 2)
                    running += off
                worst = max(worst, abs(off))
        json.dump(dict(sorted(adjust.items())), open(PATH, 'w'), indent=0)
        print(f'round {n + 1}: the most {worst:.2f} pt; pages not the spec\'s: {sorted(bad)[:8]}')
    subprocess.run([os.path.join(HERE, 'build.sh')], check=True, stdout=subprocess.DEVNULL)


main()
