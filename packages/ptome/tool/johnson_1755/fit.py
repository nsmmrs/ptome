"""Each block's space above it (margins.json, gen.py's `margin-top`),
fitted so that the PDF sets its lines where the scan has them: the
text made and built (build.sh), its lines compared with the scan's
(compare.py), each block moved by how far its lines are off, less how
far the block before it in its column is, again until no block is off
by more than a few tenths of a point. A column's first block is moved
by how far it is off itself.

    python3 -I fit.py [ROUNDS]
"""
import json, os, statistics, subprocess, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
ROUNDS = int(sys.argv[1]) if len(sys.argv) > 1 else 6
del sys.argv[1:]
import compare

HERE = compare.HERE


def build():
    subprocess.run([os.path.join(HERE, 'build.sh')], check=True, stdout=subprocess.DEVNULL)


def main():
    path = os.path.join(HERE, 'margins.json')
    margins = json.load(open(path)) if os.path.exists(path) else {}
    for n in range(ROUNDS):
        build()
        report = compare.run(quiet=True)
        report.pop('bad_words')
        moved = 0
        worst = 0
        for page, r in report.items():
            for c in (1, 2):
                lines = [d for d in r['lines'] if d['column'] == c]
                blocks = {}
                for d in lines:
                    blocks.setdefault(d['block'], []).append(d['base'])
                before = None
                for block, offs in blocks.items():
                    off = statistics.median(offs)
                    move = off - (before if before is not None else 0)
                    worst = max(worst, abs(move))
                    if abs(move) > 0.15:
                        key = str(block)
                        margins[key] = round(margins.get(key, 0) - move, 2)
                        if margins[key] == 0:
                            del margins[key]
                        moved += 1
                    before = off
        json.dump(dict(sorted(margins.items(), key=lambda kv: int(kv[0]))), open(path, 'w'), indent=0)
        print(f'round {n + 1}: {moved} blocks moved, the most {worst:.2f} pt')
        if worst < 0.3:
            break
    build()


main()
