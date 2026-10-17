"""The lines the printing sets in otherwise than their paragraph: each
line's left end on the scan (scan.json) against the PDF's (compare.py),
and for the lines the scan has further in by more than 2 pt than the PDF
sets them, a span that sets them in that much more (adjust.json's
`{"in": points}`, gen.py's `[.iNN]`), to the half point; a line set in
already moved by how far it is off. A song's lines, a direction's, a
line turned or the first of a column going on.

    python3 -I indents.py [ROUNDS]
"""
import json, os, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
ROUNDS = int(sys.argv[1]) if len(sys.argv) > 1 else 3
del sys.argv[1:]
sys.path.insert(0, HERE)
import compare

path = os.path.join(HERE, 'adjust.json')
for n in range(ROUNDS):
    subprocess.run([os.path.join(HERE, 'build.sh')], check=True, stdout=subprocess.DEVNULL)
    adjust = json.load(open(path)) if os.path.exists(path) else {}
    report = compare.run(quiet=True)
    bad = compare.mismatched()
    changed = 0
    for page, r in report.items():
        for x in r['lines']:
            if (page, x['col']) in bad or abs(x['base']) > 3:
                continue
            key = f"{page}/{x['col']}/{x['line']}"
            a = adjust.get(key, {})
            own = a.get('in', 0)
            more = -x['left']
            if (more > 2 or own) and abs(more) > 0.3:
                w = round(max(0, own + more) * 2) / 2
                if w:
                    adjust.setdefault(key, {})['in'] = w
                else:
                    adjust.get(key, {}).pop('in', None)
                changed += 1
    json.dump(dict(sorted(adjust.items(), key=lambda kv: kv[0])), open(path, 'w'), indent=0)
    print(f'round {n + 1}: {changed} lines set in')
    if not changed:
        break
