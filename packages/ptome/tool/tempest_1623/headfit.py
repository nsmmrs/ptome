"""The first page's head where the scan has it: the headpiece's top, the
title's two lines' baselines, the act's, the rules' (adjust.json's
`block/1` to `block/6`, gen.py's head), each block moved by how far it
is off less how far the block before it is, a few rounds. The scan's
places measured from its ink (head1.py's bands), in the PDF's points.

    python3 -I headfit.py
"""
import html, json, os, re, subprocess, sys
import numpy as np
from PIL import Image
HERE = os.path.dirname(os.path.abspath(__file__))
sys.argv = sys.argv[:1]
sys.path.insert(0, HERE)
import scan as S

# The scan's: the headpiece's top, THE's and TEMPEST.'s baselines, the
# rule's middle, the act's baseline, the second rule's middle.
TARGETS = {1: 72.0, 2: 217.3, 3: 263.1, 4: 284.7, 5: 305.8, 6: 318.0}
path = os.path.join(HERE, 'adjust.json')


def places():
    pdf = os.path.join(S.WORK, 'build', 'tempest-folio.pdf')
    out = subprocess.run(['pdftotext', '-bbox-layout', '-f', '1', '-l', '1', pdf, '-'], capture_output=True, text=True).stdout
    words = {}
    for m in re.finditer(r'<word xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" yMax="([\d.]+)">(.*?)</word>', out):
        x0, y0, x1, y1 = map(float, m.groups()[:4])
        words.setdefault(html.unescape(m.group(5)), (y1 - (y1 - y0) * 0.243))
    base = os.path.join(S.WORK, 'headfit')
    subprocess.run(['pdftoppm', '-r', '300', '-gray', '-png', '-f', '1', '-l', '1', '-singlefile', pdf, base], check=True)
    ink = np.asarray(Image.open(base + '.png').convert('L')) < 128
    k = 72 / 300
    rows = ink[:, int(150 / k):int(450 / k)].mean(axis=1)
    top = next(y for y in range(int(66 / k), len(rows)) if rows[y] > 0.02) * k
    # (The rules: the rows of ink across the page, under the title.)
    full = ink[:, int(60 / k):int(540 / k)].mean(axis=1)
    rules = [y * k for y in range(int(270 / k), int(340 / k)) if full[y] > 0.6]
    groups = []
    for r in rules:
        if groups and r - groups[-1][-1] < 2:
            groups[-1].append(r)
        else:
            groups.append([r])
    mids = [sum(g) / len(g) for g in groups]
    got = {1: top, 2: words.get('THE'), 3: words.get('TEMPEST.'), 5: words.get('Actus')}
    if len(mids) >= 2:
        got[4], got[6] = mids[0], mids[1]
    return got


# The last page's: its three rules under the second band, around FINIS,
# FINIS's baseline, the catchword's (the scan's, measured from its ink).
LAST = [('rule', 650.3), ('rule', 730.7), ('F', 756.5), ('rule', 768.8), ('foot', 845.2)]


def last_page():
    """The last page's blocks under its bands, where the PDF has them."""
    pdf = os.path.join(S.WORK, 'build', 'tempest-folio.pdf')
    n = int(subprocess.run(['pdfinfo', pdf], capture_output=True, text=True).stdout.split('Pages:')[1].split()[0])
    out = subprocess.run(['pdftotext', '-bbox-layout', '-f', str(n), '-l', str(n), pdf, '-'], capture_output=True, text=True).stdout
    words = {}
    for m in re.finditer(r'<word xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" yMax="([\d.]+)">(.*?)</word>', out):
        x0, y0, x1, y1 = map(float, m.groups()[:4])
        words[html.unescape(m.group(5))] = y1 - (y1 - y0) * 0.243
    base = os.path.join(S.WORK, 'lastfit')
    subprocess.run(['pdftoppm', '-r', '300', '-gray', '-png', '-f', str(n), '-l', str(n), '-singlefile', pdf, base], check=True)
    ink = np.asarray(Image.open(base + '.png').convert('L')) < 128
    k = 72 / 300
    full = ink[:, int(60 / k):int(540 / k)].mean(axis=1)
    rules = [y * k for y in range(int(600 / k), int(820 / k)) if full[y] > 0.6]
    groups = []
    for r in rules:
        if groups and r - groups[-1][-1] < 2:
            groups[-1].append(r)
        else:
            groups.append([r])
    mids = [sum(g) / len(g) for g in groups]
    return mids, words.get('FINIS.'), words.get('THE')


fit = json.load(open(os.path.join(S.WORK, 'fit.json')))
last = [f for f in fit if f['page'] == 19 and (f['line'] in ('rule', 'foot') or f['kind'] == 'F')]
blocks = [f.get('key') for f in last][-5:]

for n in range(5):
    subprocess.run([os.path.join(HERE, 'build.sh')], check=True, stdout=subprocess.DEVNULL)
    adjust = json.load(open(path)) if os.path.exists(path) else {}
    got = places()
    before, worst = 0, 0
    for b in sorted(TARGETS):
        if got.get(b) is None:
            print('not found', b)
            continue
        off = got[b] - TARGETS[b]
        move = off - before
        before = off
        worst = max(worst, abs(move))
        if abs(move) > 0.1:
            key = f'at/1/{b + 1}'
            adjust[key] = round(adjust.get(key, 0) - move, 2)
    # (The last page's foot.)
    mids, finis, the = last_page()
    found = mids[-3:-1] + [finis] + mids[-1:] + [the] if len(mids) >= 3 else []
    before = 0
    for (what, want), b, have in zip(LAST, blocks, found):
        if have is None:
            continue
        off = have - want
        move = off - before
        before = off
        worst = max(worst, abs(move))
        if abs(move) > 0.1:
            adjust[b] = round(adjust.get(b, 0) - move, 2)
    json.dump(dict(sorted(adjust.items())), open(path, 'w'), indent=0)
    print(f'round {n + 1}: the most {worst:.2f}', {b: round(v, 1) for b, v in got.items() if v}, [round(p, 1) for p in found if p])
    if worst < 0.3:
        break
