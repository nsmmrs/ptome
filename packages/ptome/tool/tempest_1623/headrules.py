"""The rules over and under the acts' and the scenes' heads where the scan
has them (adjust.json's `at/page/k`, gen.py's head rules): each rule's
middle on the scan (the rows of ink across most of its column, near its
head, on the PDF's page by scan.py's frame) against the PDF's (Poppler's
rendering), its margin moved by how far it is off less how far the
block before it is moved; then the heads and the paragraphs after them
fitted again (margins.py), a few rounds.

    python3 -I headrules.py [ROUNDS]
"""
import json, os, subprocess, sys
import numpy as np
from PIL import Image
HERE = os.path.dirname(os.path.abspath(__file__))
ROUNDS = int(sys.argv[1]) if len(sys.argv) > 1 else 2
sys.argv = sys.argv[:1]
sys.path.insert(0, HERE)
import scan as S

PATH = os.path.join(HERE, 'adjust.json')
DPI = 300
K = 72 / DPI
# (The columns' edges on the PDF's page, in points.)
EDGES = {1: (47.7, 294.15), 2: (310.95, 557.4)}


def rows_across(ink, x0, x1, y0, y1, to_pt, most=0.5):
    """The middles of the runs of rows with ink across `most` of x0..x1
    (the scan's rules worn and broken: less), between rows y0 and y1, in
    points: thin runs with little ink a few rows over and under them, not
    a line of large type's; runs a few points apart one rule."""
    density = ink[:, x0:x1].mean(axis=1)
    full = density[y0:y1] > most
    out, y = [], 0
    while y < len(full):
        if full[y]:
            e = y
            while e + 1 < len(full) and full[e + 1]:
                e += 1
            a, b = y0 + y, y0 + e
            if b - a <= 12 and density[a - 8] < 0.15 and density[b + 8] < 0.15:
                mid = to_pt((a + b) / 2)
                if out and mid - out[-1] < 3:
                    out[-1] = (out[-1] + mid) / 2
                else:
                    out.append(mid)
            y = e
        y += 1
    return out


def scan_rules(page, col, near):
    left, head, sx, sy = S.geometry(page)
    c = S.cols[str(24 + page)]
    img = Image.open(os.path.join(S.WORK, 'png', f'{24 + page:04d}.png')).convert('L')
    ink = np.asarray(img.rotate(-np.degrees(np.arctan(c['lean'])), resample=Image.BICUBIC, fillcolor=255)) < 115
    x0, x1 = EDGES[col]
    # (The PDF's points to the scan's pixels, and back.)
    px = lambda x: int((x - S.FRAME[0]) / (S.PT * sx) + left)
    py = lambda y: int((y - S.FRAME[1]) / (S.PT * sy) + head)
    a, b = px(x0) + 40, px(x1) - 40
    return rows_across(ink, a, b, py(near - 60), py(near + 35), lambda y: (y - head) * S.PT * sy + S.FRAME[1], 0.3)


def pdf_rules(page, col, near):
    pdf = os.path.join(S.WORK, 'build', 'tempest-folio.pdf')
    base = os.path.join(S.WORK, 'headrules')
    subprocess.run(['pdftoppm', '-r', str(DPI), '-gray', '-png', '-f', str(page), '-l', str(page), '-singlefile', pdf, base],
                   check=True)
    ink = np.asarray(Image.open(base + '.png').convert('L')) < 128
    x0, x1 = EDGES[col]
    return rows_across(ink, int(x0 / K) + 40, int(x1 / K) - 40, int((near - 60) / K), int((near + 35) / K), lambda y: y * K)


def main():
    for n in range(ROUNDS):
        subprocess.run(['python3', '-I', os.path.join(HERE, 'margins.py')], check=True, stdout=subprocess.DEVNULL)
        fit = json.load(open(os.path.join(S.WORK, 'fit.json')))
        scan = json.load(open(os.path.join(S.WORK, 'scan.json')))
        adjust = json.load(open(PATH))
        worst = 0.0
        # (Each head: its line's baseline on the scan, its rules around it.)
        heads = [f for f in fit if f['kind'] == 'A']
        for h in heads:
            near = scan[str(h['page'])][h['col'] - 1][h['line'] - 1]['base']
            rules = [f for f in fit if f['line'] == 'head-rule' and f['page'] == h['page'] and f['col'] == h['col']
                     and f['block'] in (h['block'] - 1, h['block'] + 1)]
            want = scan_rules(h['page'], h['col'], near)
            have = pdf_rules(h['page'], h['col'], near)
            # (The rule over the head: the nearest over its baseline; the
            # rule under it, the nearest under. The head's own place
            # margins.py's, whatever the rule over it does: each rule moved
            # by its own error.)
            for r in rules:
                over = r['block'] < h['block']
                pick = (lambda xs: max((x for x in xs if x < near - 8), default=None)) if over else \
                    (lambda xs: min((x for x in xs if x > near), default=None))
                w, g = pick(want), pick(have)
                if w is None or g is None:
                    print(f"{h['page']}/{h['col']}: rule {'over' if over else 'under'}: "
                          f"the scan's {[round(x, 1) for x in want]}, the PDF's {[round(x, 1) for x in have]}")
                    continue
                off = g - w
                worst = max(worst, abs(off))
                if abs(off) > 0.1:
                    adjust[r['key']] = round(adjust.get(r['key'], 0) - off, 2)
        json.dump(dict(sorted(adjust.items())), open(PATH, 'w'), indent=0)
        print(f'round {n + 1}: the most {worst:.2f} pt')
    subprocess.run(['python3', '-I', os.path.join(HERE, 'margins.py')], check=True, stdout=subprocess.DEVNULL)


main()
