"""The paragraphs split where the scan's lines drift from the pitch
(adjust.json's `split/page/column/line`, gen.py's): for each line of a
block on the PDF more than 1.5 pt off the scan's after its block's
margin is fitted (margins.py), a split before the first such line of
each run; then the margins fitted again, a few rounds.

    python3 -I splits.py [ROUNDS]
"""
import json, os, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
ROUNDS = int(sys.argv[1]) if len(sys.argv) > 1 else 3
del sys.argv[1:]
sys.path.insert(0, HERE)
import compare

path = os.path.join(HERE, 'adjust.json')
for n in range(ROUNDS):
    subprocess.run(['python3', '-I', os.path.join(HERE, 'margins.py')], check=True, stdout=subprocess.DEVNULL)
    adjust = json.load(open(path))
    report = compare.run(quiet=True)
    bad = compare.mismatched()
    # (Only from a state whose columns are all the spec's: splits read off
    # a page overflowing would be wrong.)
    if bad:
        print('columns not the spec\'s:', sorted(bad))
        break
    added = 0
    for page, r in report.items():
        for c in (1, 2):
            if (page, c) in bad:
                continue
            xs = [x for x in r['lines'] if x['col'] == c]
            prev = None
            for x in xs:
                if prev is not None and prev['block'] == x['block'] and abs(x['base'] - prev_off) > 1.0 \
                        and x['kind'] in ('S', 'V', 'C', 'CV', 'L'):
                    key = f"split/{page}/{c}/{x['line']}"
                    if not adjust.get(key):
                        adjust[key] = True
                        added += 1
                    prev_off = x['base']
                elif prev is None or prev['block'] != x['block']:
                    prev_off = x['base']
                prev = x
    json.dump(dict(sorted(adjust.items())), open(path, 'w'), indent=0)
    print(f'round {n + 1}: {added} splits added')
    if not added:
        break
subprocess.run(['python3', '-I', os.path.join(HERE, 'margins.py')], check=True, stdout=subprocess.DEVNULL)
