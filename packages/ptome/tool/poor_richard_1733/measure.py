"""A month's page measured from its ink, the same way on the scan and on
the PDF drawn at the scan's 400 ppi, so that the two compare without a
face's metrics between them: the page turned upright by its frame's left
rule; the frame's top left corner; the rules across (the heading's, the
calendar's top, the frame's foot); the lines of text between them, each
its baseline (the foot of its x-height's ink); the calendar's rules down.
Everything in points from the frame's corner.

    python3 -I measure.py [LEAF...]   # PR_WORK/measure.json
"""
import json, os, re, subprocess, sys
import numpy as np
from PIL import Image, ImageFilter

WORK = os.environ.get('PR_WORK', os.path.expanduser('~/.cache/asciidart-work/print-match/poor-richard'))
HERE = os.path.dirname(os.path.abspath(__file__))
PPI = 400
PT = 72 / PPI
MONTHS = list(range(9, 21))


def lean(ink):
    """The page's lean: the slope of its frame's left rule (its x down
    the page, band by band, fitted by least squares)."""
    h, w = ink.shape
    pts = []
    for y0 in range(int(h * 0.2), int(h * 0.85), 100):
        prof = ink[y0:y0 + 100, : w // 3].mean(axis=0)
        xs = np.where(prof > 0.6)[0]
        if len(xs):
            pts.append((y0 + 50, xs[0]))
    if len(pts) < 3:
        return 0.0
    a = np.array(pts, dtype=float)
    return float(np.polyfit(a[:, 0], a[:, 1], 1)[0])


def upright(img):
    """The page turned upright, its ink (darker than 0.55 of the paper
    about it) and its tone (each pixel's share of the paper's, so that a
    dark scan and a light one read alike)."""
    paper = np.asarray(img.filter(ImageFilter.GaussianBlur(40))).astype(float)
    tone = np.clip(np.asarray(img).astype(float) / np.maximum(paper, 1), 0, 1)
    k = lean(tone < 0.55)
    timg = Image.fromarray((tone * 255).astype(np.uint8))
    # (A rule leaning right going down: turned back by its angle.)
    turned = np.asarray(timg.rotate(-np.degrees(np.arctan(k)), resample=Image.BICUBIC, fillcolor=255)) / 255
    return turned < 0.55, turned, k


def frame(ink):
    """The frame's left rule's inner edge and its top rule's foot."""
    h, w = ink.shape
    prof = ink[int(h * 0.2):int(h * 0.85), : w // 3].mean(axis=0)
    xs = np.where(prof > 0.6)[0]
    left = int(xs[-1]) + 1 if len(xs) else 0
    # (The rule's run: from its first column on, while its columns are ink.)
    if len(xs):
        x = int(xs[0])
        while x + 1 < len(prof) and prof[x + 1] > 0.6:
            x += 1
        left = x + 1
    rows = ink[:, left + 20:left + int(110 / PT)].mean(axis=1)
    ys = np.where(rows[: h // 4] > 0.6)[0]
    # (The frame's top rule: the last of the first run of rows across.)
    y = int(ys[0])
    while y + 1 < h and rows[y + 1] > 0.6:
        y += 1
    return left, y + 1


def longest_run(row):
    """The longest run of ink in [row]."""
    padded = np.concatenate(([False], row, [False]))
    d = np.diff(padded.astype(int))
    starts, ends = np.where(d == 1)[0], np.where(d == -1)[0]
    return int((ends - starts).max()) if len(starts) else 0


def rule_near(gray, left, near, reach, thick=14):
    """The rule across the frame nearest to row [near], within [reach]
    rows of it: the row where the ink across a strip at the frame's left
    (pale too: a thin rule prints light and broken; the paper is warped,
    a rule across the page bends by points, but little over a strip)
    peaks in a band thinner than a line of text's x-height."""
    ink = gray[:, left + 10:left + int(110 / PT)] < 0.8
    prof = np.convolve(ink.mean(axis=1), np.ones(3) / 3, mode='same')
    best = None
    for y in range(max(2, near - reach), min(len(prof) - 2, near + reach)):
        if prof[y] > 0.15 and prof[y] == prof[max(0, y - 10):y + 11].max():
            half = prof[y] / 2
            a = y
            while a > 0 and prof[a - 1] > half:
                a -= 1
            b = y
            while b + 1 < len(prof) and prof[b + 1] > half:
                b += 1
            if b - a <= thick and (best is None or prof[y] > best[0]):
                best = (prof[y], a, b + 1)
    if best is None:
        raise SystemExit(f'no rule near {near * PT:.1f} pt')
    return best[1], best[2]


def text_lines(ink, top, bottom, x0, x1, count=None):
    """The baselines of the lines of text between [top] and [bottom]:
    the profile's peaks (the x-heights), [count] of them if given, each
    line's baseline the steepest fall of its ink below its peak."""
    prof = ink[top:bottom, x0:x1].sum(axis=1).astype(float)
    sm = np.convolve(prof, np.ones(9) / 9, mode='same')
    peaks = [y for y in range(1, len(sm) - 1) if sm[y] >= sm[y - 1] and sm[y] > sm[y + 1] and sm[y] > sm.max() * 0.25]
    chosen = []
    for y in sorted(peaks, key=lambda y: -sm[y]):
        if all(abs(y - c) >= 55 for c in chosen):
            chosen.append(y)
        if count and len(chosen) == count:
            break
    out = []
    for y in sorted(chosen):
        fall = np.diff(sm[y:y + 45])
        out.append(top + y + int(np.argmin(fall)) + 1)
    return out


def comb(ink, top, bottom, x0, x1, count, first=None, slack=8):
    """The baselines of [count] rows set a pitch apart (a table's): the
    first row and the pitch that put the most ink on the rows' x-heights,
    each row's baseline then found near its place (the paper's warp moves
    it a little), the steepest fall of its ink below its peak."""
    prof = ink[top:bottom, x0:x1].sum(axis=1).astype(float)
    sm = np.convolve(prof, np.ones(9) / 9, mode='same')
    best = None
    for pitch10 in range(int(10.8 / PT * 10), int(12.6 / PT * 10)):
        pitch = pitch10 / 10
        starts = range(0, int(len(sm) - pitch * (count - 1)))
        if first is not None:
            starts = range(max(0, first[0]), min(int(len(sm) - pitch * (count - 1)), first[1]))
        for y0 in starts:
            ys = (y0 + pitch * np.arange(count)).astype(int)
            score = sm[ys].sum()
            if best is None or score > best[0]:
                best = (score, y0, pitch)
    _, y0, pitch = best
    out = []
    for k in range(count):
        y = int(y0 + pitch * k)
        a, b = max(0, y - slack), min(len(sm) - 1, y + slack)
        peak = a + int(np.argmax(sm[a:b]))
        fall = np.diff(sm[peak:peak + 45])
        out.append(top + peak + int(np.argmin(fall)) + 1)
    return out


def rules_down(ink, top, bottom, left, right):
    prof = ink[top:bottom, left:right].mean(axis=0)
    xs, x = [], 0
    while x < len(prof):
        if prof[x] > 0.7:
            x1 = x
            while x1 + 1 < len(prof) and prof[x1 + 1] > 0.7:
                x1 += 1
            xs.append(left + (x + x1 + 1) / 2)
            x = x1 + 1
        x += 1
    return xs


def measure(img, rows, verse, thead=False, reach=16):
    ink, gray, k = upright(img.convert('L'))
    left, top = frame(ink)
    # (The heading's rule, the calendar's top rule (under its head, where
    # it has one) and the frame's foot, each near where the facsimile's
    # forme has it.)
    head_rule = rule_near(gray, left, top + int(24 / PT), int(8 / PT))
    cal_rule = rule_near(gray, left, top + int((158 if thead else 132) / PT), int(reach / PT))
    foot = rule_near(gray, left, top + int(502 / PT), int(30 / PT), thick=40)
    right = left + int(275 / PT)
    head = text_lines(ink, top + int(4 / PT), head_rule[0] - 2, left + 10, right, 1)
    # (The verse's lines, a pitch apart but a title's, which may stand a
    # little apart.)
    # (Above the calendar's head, where it has one: two lines and a rule.)
    verse_bottom = cal_rule[0] - (int(31 / PT) if thead else 2)
    verse_lines = comb(ink, head_rule[1] + 4, verse_bottom, left + 10, left + int(250 / PT), verse, slack=16)
    # (The rules down the calendar, in its upper half.)
    downs = rules_down(ink, cal_rule[1] + 20, (cal_rule[1] + foot[0]) // 2, left, right + 60)
    # (A row's ink across the whole calendar but its rules.)
    row_ink = ink.copy()
    for x in downs:
        row_ink[:, int(x) - 6:int(x) + 7] = False
    # (The rows in a strip at the left: the days, the week days and the
    # remarkable days.)
    # (The first row a little below the calendar's rule: 8 to 17 pt.)
    row_lines = comb(row_ink, cal_rule[1] + 4, foot[0] - 2, left + 4, left + int(120 / PT), rows,
                     first=(int(5 / PT), int(14 / PT)))

    def pt(v, origin):
        return round((v - origin) * PT, 2)
    return {'lean': round(k, 5), 'corner': [round(left * PT, 2), round(top * PT, 2)],
            'verse_ends': [extents(ink, left, y) for y in verse_lines],
            'head_ends': [extents(ink, left, y) for y in head],
            'head_rule': pt(head_rule[0], top), 'cal_rule': pt(cal_rule[0], top), 'foot': pt(foot[0], top),
            'head': [pt(y, top) for y in head], 'verse': [pt(y, top) for y in verse_lines],
            'rows': [pt(y, top) for y in row_lines], 'downs': [pt(x, left) for x in downs]}


def counts():
    """Each month's rows and verse lines, from months.spec."""
    out, cur = [], None
    for line in open(os.path.join(HERE, 'months.spec'), encoding='utf-8'):
        line = line.rstrip('\n')
        if line.startswith('@month'):
            cur = {'leaf': int(line.split()[2]), 'verse': 0, 'rows': 0}
            out.append(cur)
            section = None
        elif line in ('@verse', '@rows'):
            section = line[1:]
        elif line.startswith('@thead'):
            cur['thead'] = True
        elif line.strip() and not line.startswith('@') and section:
            cur[section] += 1
    return {c['leaf']: c for c in out}


def month_page(pdf, leaf):
    """The PDF's page that starts the month on [leaf] (its heading)."""
    name = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August',
            'September', 'October', 'November', 'December'][leaf - 9]
    n = int(subprocess.run(['pdfinfo', pdf], capture_output=True, text=True).stdout.split('Pages:')[1].split()[0])
    for page in range(1, n + 1):
        text = subprocess.run(['pdftotext', '-f', str(page), '-l', str(page), pdf, '-'],
                              capture_output=True, text=True).stdout
        if re.search(rf'{name}\s+hath', text):
            return page
    raise SystemExit(f'{name} not on the PDF')


def pdf_page(pdf, page):
    base = os.path.join(WORK, 'tmp-page')
    subprocess.run(['pdftoppm', '-r', str(PPI), '-gray', '-png', '-f', str(page), '-l', str(page),
                    '-singlefile', pdf, base], check=True)
    img = Image.open(base + '.png')
    img.load()
    os.remove(base + '.png')
    return img


# (The ink's baseline, the steepest fall of a line's ink, lies this far
# below the type's own: measured on the PDF drawn at 400 ppi.)
INK_BIAS = 0.4
# The PDF's frame's corner: its left rule's inner edge, its top rule's
# foot (images/frame-month.svg).
CORNER = (44.9, 60.45)


def pdf_text(pdf, page):
    """A month's page of the PDF from its text, as measure() reads the
    scan: the heading's baseline, the verse's lines' and the rows' (each
    day of the month in the first column), from the frame's corner, as
    the ink would put them (INK_BIAS lower)."""
    import html as h
    out = subprocess.run(['pdftotext', '-bbox-layout', '-f', str(page), '-l', str(page), pdf, '-'],
                         capture_output=True, text=True, check=True).stdout
    ws = []
    for m in re.finditer(r'<word xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" yMax="([\d.]+)">(.*?)</word>', out):
        x0, y0, x1, y1 = map(float, m.groups()[:4])
        ws.append((h.unescape(m.group(5)), x0, y1 - (y1 - y0) * 260 / 1230 - CORNER[1] + INK_BIAS, x1))
    head = next(w[2] for w in ws if w[0] == 'Mon.')
    days = {}
    for w in sorted(ws, key=lambda w: w[2]):
        if w[3] < CORNER[0] + 17 and w[0].isdigit() and w[2] > head + 20 and int(w[0]) not in days:
            days[int(w[0])] = w[2]
    first = min(days.values())
    lines = []
    for w in sorted((w for w in ws if head + 3 < w[2] < first - 12), key=lambda w: w[2]):
        if not lines or w[2] - lines[-1] > 3:
            lines.append(w[2])
    # (A calendar's head, two lines above its first row: not the verse.)
    if any(w[0] == 'Remarkable' for w in ws):
        lines = lines[:-2]
    return {'head': [head], 'verse': lines, 'rows': [days[k] for k in sorted(days)]}


def extents(ink, left, base, width=275):
    """The left and right ends of the ink of the line whose baseline is
    row [base], within the frame (from [left] on, [width] points), each
    an end where a few pixels' ink stand together, not a speck."""
    band = ink[base - int(6.5 / PT):base + 1, left + int(1.2 / PT):left + int(width / PT)]
    cols = np.convolve(band.sum(axis=0) > 0, np.ones(5), mode='same') >= 4
    xs = np.where(cols)[0]
    if not len(xs):
        return None
    return round((xs[0] + int(1.2 / PT)) * PT, 2), round((xs[-1] + int(1.2 / PT)) * PT, 2)


def line_extents(img, ys):
    """[ys] (baselines in points from the frame's corner) and each line's
    ends, from [img]'s ink, turned upright and set by its frame."""
    ink, _, _ = upright(img.convert('L'))
    left, top = frame(ink)
    return [extents(ink, left, top + int(y / PT)) for y in ys]


def report(a, b):
    """[a] (the PDF's) less [b] (the scan's), feature by feature."""
    def d(x, y):
        return round(x - y, 2)
    out = {'head': d(a['head'][0], b['head'][0]), 'head_rule': d(a['head_rule'], b['head_rule']),
           'cal_rule': d(a['cal_rule'], b['cal_rule']), 'foot': d(a['foot'], b['foot']),
           'verse': [d(x, y) for x, y in zip(a['verse'], b['verse'])],
           'rows': [d(x, y) for x, y in zip(a['rows'], b['rows'])]}
    return out


if __name__ == '__main__':
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    pdf = next((a[6:] for a in sys.argv if a.startswith('--pdf=')), None)
    leaves = [int(a) for a in args] or MONTHS
    c = counts()
    path = os.path.join(WORK, 'measure.json')
    data = json.load(open(path)) if os.path.exists(path) else {}
    for leaf in leaves:
        if pdf:
            # (The month's page of the PDF: the four of the front matter,
            # then the months.)
            img = pdf_page(pdf, month_page(pdf, leaf))
            got = measure(img, c[leaf]['rows'], c[leaf]['verse'], c[leaf].get('thead', False), reach=80)
            data[f'pdf-{leaf}'] = got
            r = report(got, data[str(leaf)])
            rows = r['rows']
            print(f"{leaf}: head {r['head']:+.2f} rules {r['head_rule']:+.2f} {r['cal_rule']:+.2f} {r['foot']:+.2f} "
                  f"verse {' '.join(f'{x:+.1f}' for x in r['verse'])} rows {min(rows, default=0):+.1f}..{max(rows, default=0):+.1f} "
                  f"(first {rows[0] if rows else 0:+.1f}, last {rows[-1] if rows else 0:+.1f})")
            continue
        img = Image.open(os.path.join(WORK, 'png', f'{leaf:04d}.png'))
        data[str(leaf)] = measure(img, c[leaf]['rows'], c[leaf]['verse'], c[leaf].get('thead', False))
        d = data[str(leaf)]
        print(leaf, d['corner'], 'lean', d['lean'], 'head', d['head'], 'rules', d['head_rule'], d['cal_rule'], d['foot'])
        print('   verse', d['verse'])
        print('   rows', d['rows'][:3], '...', d['rows'][-2:], len(d['rows']))
        print('   downs', d['downs'])
    json.dump(data, open(path, 'w'), indent=0)
