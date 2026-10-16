"""The rules and bands of ornament on each leaf of the scan: ink across
the text's width outside every text line and the page's furniture; a
rule thin (under 45 px), a band tall.

    python3 -I rules.py -> rules.json ({leaf: [{kind, box}]}), rules.png
"""
import glob, json, os, sys
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from words import lines_of

W = os.path.join(os.environ.get('TEMPLE_WORK', os.path.expanduser('~/.cache/asciidart-work/print-match')), 'herbert')
D = glob.glob(f'{W}/*_jp2')[0]
NAME = D.split('/')[-1][:-4]
HERE = os.path.dirname(os.path.abspath(__file__))
PAGES = json.load(open(f'{HERE}/pages.json'))
PITCH = 135


def leaf_rules(leaf):
    v = PAGES[str(leaf)]
    a = np.asarray(Image.open(f'{D}/{NAME}_{leaf:04d}.jp2').convert('L')) < 120
    # (Inside the film's black edges: a column or row mostly black is
    # the film's, not the page's.)
    xs = np.nonzero(a.mean(0) < 0.6)[0]
    ys = np.nonzero(a.mean(1) < 0.6)[0]
    if not len(xs) or not len(ys):
        return []
    x0, x1 = int(xs[0]) + 80, int(xs[-1]) - 80
    y0, y1 = int(ys[0]) + 80, int(ys[-1]) - 80
    free = np.ones(a.shape[0], bool)
    free[:y0] = False
    free[y1:] = False
    # (Text lines, the words of every OCR line that holds a word of the
    # text: out, from a pitch above its baseline to a third below.)
    for l in v['lines']:
        if any(w.get('exact') for w in l['words']) and sum(c.isalpha() for c in l['text']) >= 3:
            free[int(l['base'] - 0.85 * PITCH):int(l['base'] + 0.3 * PITCH)] = False
    for f in v['furniture'].values():
        free[int(f['base'] - 0.85 * PITCH):int(f['base'] + 0.35 * PITCH)] = False
    sub = a[:, x0:x1]
    # (A row's ink: its longest run, gaps of up to 12 px bridged.)
    out = []
    rows = np.nonzero(free & (sub.mean(1) > 0.12))[0]
    if not len(rows):
        return []
    groups = np.split(rows, np.nonzero(np.diff(rows) > 3)[0] + 1)
    for g in groups:
        ya, yb = int(g[0]), int(g[-1]) + 1
        if yb - ya < 4:
            continue
        cols = np.nonzero(sub[ya:yb].any(0))[0]
        # (Its width: the longest span of columns with ink, gaps of up to
        # 40 px bridged.)
        spans = np.split(cols, np.nonzero(np.diff(cols) > 40)[0] + 1)
        s = max(spans, key=len)
        xa, xb = int(s[0]) + x0, int(s[-1]) + 1 + x0
        if xb - xa < 900:
            continue
        dens = a[ya:yb, xa:xb].mean()
        prof = a[ya:yb, xa:xb].mean(1)
        h = yb - ya
        # (A rule, a little tilted or broken: ink in most columns, each
        # column's only a few pixels deep; a line of words the OCR missed
        # is a letter's height deep.)
        colh = a[ya:yb, xa:xb].sum(0)
        cover = (colh > 0).mean()
        thick = float(np.median(colh[colh > 0])) if cover else 99
        if cover >= 0.85 and thick <= 32:
            core = np.nonzero(prof > 0.5 * prof.max())[0]
            if core[-1] - core[0] < 42:
                out.append(dict(kind='rule', box=[xa, ya + int(core[0]), xb, ya + int(core[-1]) + 1]))
        elif h >= 150 and dens > 0.12:
            out.append(dict(kind='band', box=[xa, ya, xb, yb]))
    return out


def title_rules(res):
    """The rule over each poem's title not at its page's top that the
    pass over the page missed (an OCR line read over it): the thinnest
    ink across the most columns in the gap above the title."""
    import gen
    fits = json.load(open(f'{HERE}/fit.json'))
    by_page = {}
    for f in fits:
        by_page.setdefault(f['page'], []).append(f)
    added = 0
    for page, fs in by_page.items():
        leaf = page - 1
        for i, f in enumerate(fs):
            if f['kind'] != 'heading' or i == 0:
                continue
            base = (f['target'] - gen.H0) / gen.PX + gen.head_base(leaf)
            have = [r for r in res.get(leaf, []) if r['kind'] == 'rule'
                    and base - 3.4 * PITCH < r['box'][1] < base - 0.6 * PITCH]
            if have:
                continue
            a = np.asarray(Image.open(f'{D}/{NAME}_{leaf:04d}.jp2').convert('L')) < 120
            best = None
            for y in range(int(base - 3.2 * PITCH), int(base - 0.8 * PITCH), 4):
                colh = a[y:y + 30, 500:3100].sum(0)
                cover = (colh > 0).mean()
                thick = np.median(colh[colh > 0]) if cover else 99
                score = cover if thick <= 22 else 0
                if best is None or score > best[0]:
                    best = (score, y)
            if best and best[0] >= 0.8:
                y = best[1]
                prof = a[y:y + 30, 500:3100].mean(1)
                core = np.nonzero(prof > 0.5 * prof.max())[0]
                cols = np.nonzero(a[y + int(core[0]):y + int(core[-1]) + 1, :].any(0))[0]
                cols = cols[(cols > 300) & (cols < 3300)]
                spans = np.split(cols, np.nonzero(np.diff(cols) > 40)[0] + 1)
                sp = max(spans, key=len)
                res.setdefault(leaf, []).append(dict(kind='rule', box=[int(sp[0]), y + int(core[0]), int(sp[-1]) + 1,
                                                                    y + int(core[-1]) + 1]))
                res[leaf].sort(key=lambda r: r['box'][1])
                added += 1
    return added


def main():
    res = {leaf: leaf_rules(leaf) for leaf in range(0, 203)}
    print('over titles, missed by the first pass:', title_rules(res))
    json.dump(res, open(f'{HERE}/rules.json', 'w'))
    import collections
    print(collections.Counter(r['kind'] for rs in res.values() for r in rs))
    tiles = []
    for leaf, rs in res.items():
        if not rs:
            continue
        im = Image.open(f'{D}/{NAME}_{leaf:04d}.jp2').convert('L')
        for r in rs:
            t = im.crop(tuple(r['box']))
            t.thumbnail((300, 60))
            tiles.append((leaf, r['kind'], r['box'][3] - r['box'][1], t))
    from PIL import ImageDraw
    cols = 5
    rows = (len(tiles) + cols - 1) // cols
    sheet = Image.new('L', (cols * 310, rows * 80), 255)
    d = ImageDraw.Draw(sheet)
    for i, (leaf, kind, h, t) in enumerate(tiles):
        x, y = (i % cols) * 310, (i // cols) * 80
        sheet.paste(t, (x, y + 14))
        d.text((x, y), f'{leaf} {kind} h{h}', fill=0)
    sheet.save(f'{HERE}/rules.png')


if __name__ == '__main__':
    main()
