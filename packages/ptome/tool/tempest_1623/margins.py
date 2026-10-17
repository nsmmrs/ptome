"""Each paragraph's space above it (adjust.json's `top/page/column/line`,
gen.py's, keyed by its first line): its first line's baseline on the PDF
against the scan's (scan.json), its margin moved by its error less what
the paragraphs above it in its column are moved already. Two rounds take
up what the first leaves.

    python3 -I margins.py
"""
import json, os, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.argv = sys.argv[:1]
sys.path.insert(0, HERE)
import compare

path = os.path.join(HERE, 'adjust.json')
adjust = json.load(open(path)) if os.path.exists(path) else {}
for n in range(2):
    json.dump(dict(sorted(adjust.items())), open(path, 'w'), indent=0)
    subprocess.run([os.path.join(HERE, 'build.sh')], check=True, stdout=subprocess.DEVNULL)
    fit = json.load(open(os.path.join(compare.WORK, 'fit.json')))
    scan = json.load(open(os.path.join(compare.WORK, 'scan.json')))
    pdf = compare.pdf_lines()
    spec_text = compare.first_lines()
    worst = 0
    for page in range(1, 20):
        for c in ((1, 2, 3, 4) if page == 19 else (1, 2)):
            spec = [f for f in fit if f['page'] == page and f['col'] == c and isinstance(f['line'], int)]
            lines = compare.column_lines(pdf, page, c, spec, spec_text)
            if len(lines) != len(spec):
                print(f'{page}/{c}: {len(lines)} lines on the PDF, {len(spec)} in the spec')
                continue
            s = scan[str(page)][c - 1]
            if len(s) != len(spec):
                print(f'{page}/{c}: {len(s)} lines on the scan, {len(spec)} in the spec')
                continue
            # (Each block's first line set where the scan has it: its margin
            # moved by its line's error less what the blocks above it in
            # the column are moved already.)
            running = 0.0
            for k, f in enumerate(spec):
                if k and spec[k - 1]['block'] == f['block']:
                    continue
                off = (s[k]['base'] - lines[k]['base']) - running
                key = f['key']
                if abs(off) > 0.05:
                    adjust[key] = round(adjust.get(key, 0) + off, 2)
                    running += off
                worst = max(worst, abs(off))
    print(f'round {n + 1}: the most {worst:.2f} pt')
json.dump(dict(sorted(adjust.items())), open(path, 'w'), indent=0)
subprocess.run([os.path.join(HERE, 'build.sh')], check=True, stdout=subprocess.DEVNULL)
