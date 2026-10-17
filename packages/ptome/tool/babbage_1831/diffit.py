"""The differences' column fitted to the scan: each item's space above
it (adjust.json's `d/PAGE/SIDE/K`, gen.py's) moved until its first line
(a difference's figures, or a continued table's first part) stands on
the row diff.spec gives it, a few rounds; each item moved by its error
less what the items above it in its half of the column are moved.

    python3 -I diffit.py [ROUNDS]
"""
import html, json, math, os, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
ROUNDS = int(sys.argv[1]) if len(sys.argv) > 1 else 3
sys.argv = sys.argv[:1]
from common import EDGES, THICK, WORK
from gen import SPEC

PDF = os.path.join(WORK, 'build', 'babbage.pdf')
PATH = os.path.join(HERE, 'adjust.json')
FIRST_BASE, PITCH, GAP = 95.25, 9.9, 4.9


def row_base(row):
    """A row of the table (fractional) as a baseline in points."""
    i = math.floor(row)
    if i < 0:
        return FIRST_BASE + row * PITCH
    return FIRST_BASE + i * PITCH + i // 5 * GAP + (row - i) * PITCH


def words(page):
    out = subprocess.run(['pdftotext', '-bbox', '-f', str(page - 5), '-l', str(page - 5), PDF, '-'],
                         capture_output=True, text=True, check=True).stdout
    ws = []
    for m in re.finditer(r'<word xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" yMax="([\d.]+)">(.*?)</word>', out):
        x0, y0, x1, y1 = map(float, m.groups()[:4])
        ws.append((x0, y1 - (y1 - y0) * 0.238, x1, y1 - y0, html.unescape(m.group(5))))
    return ws


def placed(page):
    """Each item's first line on the PDF: (side, k) to its baseline."""
    side_of = 'verso' if page % 2 == 0 else 'recto'
    t = THICK[side_of]
    x0, xm = t + EDGES[13], t + (EDGES[13] + EDGES[14]) / 2
    ws = words(page)
    out = {}
    for side in ('L', 'R'):
        items = [i for i in SPEC.get(page, []) if i['side'] == side]
        inside = [w for w in ws if (x0 < w[0] < xm if side == 'L' else xm - 2 < w[0] < t + EDGES[14] + 8)]
        used = set()
        for k, it in enumerate(items):
            if it['on']:
                # (The first part's tenth, or the tenth and its part run
                # together by Poppler.)
                a = it['parts'][0]
                want = (str(a), f"{a}{(it['d'] * a + 5) // 10}")
                cands = [w for w in inside if w[4] in want and w[3] < 7.5]
            else:
                cands = [w for w in inside if w[4] == str(it['d']) and w[3] > 7.5]
            cands = [w for w in cands if w not in used]
            if cands:
                w = min(cands, key=lambda w: abs(w[1] - row_base(it['row'])))
                used.add(w)
                out[(side, k)] = w[1]
    return out


def main():
    for n in range(ROUNDS):
        subprocess.run([os.path.join(HERE, 'build.sh')], check=True, stdout=subprocess.DEVNULL)
        adjust = json.load(open(PATH)) if os.path.exists(PATH) else {}
        worst, lost = 0.0, 0
        for page in sorted(SPEC):
            got = placed(page)
            for side in ('L', 'R'):
                items = [i for i in SPEC[page] if i['side'] == side]
                running = 0.0
                for k, it in enumerate(items):
                    if (side, k) not in got:
                        lost += 1
                        continue
                    off = got[(side, k)] - row_base(it['row']) + running
                    key = f'd/{page}/{side}/{k}'
                    if abs(off) > 0.05:
                        adjust[key] = round(adjust.get(key, 0) - off, 2)
                        running -= off
                    worst = max(worst, abs(off))
        json.dump(dict(sorted(adjust.items())), open(PATH, 'w'), indent=0)
        print(f'round {n + 1}: the most {worst:.2f} pt; {lost} not found')
    subprocess.run([os.path.join(HERE, 'build.sh')], check=True, stdout=subprocess.DEVNULL)


if __name__ == '__main__':
    main()
