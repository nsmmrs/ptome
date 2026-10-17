"""Each printed line's place on the scan: its baseline and the left and
right ends of its ink, in points from the page's top left (the scans are
300 ppi, 0.24 pt a pixel), column by column. The page leans and bows on
the scan, so each column is cut in strips across, each strip turned
level by the slope of Tesseract's baselines in it (its hOCR, `tesseract
NNNN.png NNNN -l eng hocr`); a line is a band of ink the x-height
deep, its baseline the band's foot, its ends its words' (Tesseract's).

    python3 -I scan.py   # JOHNSON_WORK/scan.json
"""
import json, os, re, statistics
import numpy as np
from PIL import Image

WORK = os.environ.get('JOHNSON_WORK', os.path.expanduser('~/.cache/asciidart-work/print-match/johnson'))
PT = 72 / 300
# Each page's columns' left and right limits and the text's top and
# bottom on the scan, in pixels (the heads above, the foot below), and
# how many lines each column holds (johnson.spec).
PAGES = {
    46: {'columns': [(150, 1611), (1611, 3100)], 'top': 470, 'bottom': 5600, 'lines': [92, 91]},
    47: {'columns': [(130, 1586), (1586, 3060)], 'top': 500, 'bottom': 5600, 'lines': [90, 90]},
    48: {'columns': [(150, 1640), (1640, 3120)], 'top': 460, 'bottom': 5530, 'lines': [90, 90]},
}


def slopes(page, left, right):
    hocr = open(os.path.join(WORK, f'{page:04d}.hocr'), encoding='utf-8').read()
    found = []
    for m in re.finditer(r"bbox (\d+) (\d+) (\d+) (\d+); baseline ([-\d.]+) ([-\d.]+)", hocr):
        x0, y0, x1, y1 = map(int, m.groups()[:4])
        if left <= (x0 + x1) / 2 < right and x1 - x0 > 600:
            found.append(float(m.group(5)))
    return statistics.median(found)


def words(page):
    """Tesseract's words on the page: their boxes."""
    hocr = open(os.path.join(WORK, f'{page:04d}.hocr'), encoding='utf-8').read()
    # (Its sure ones with a letter or a figure: a speck or the other
    # side's print read as a word is a word Tesseract is unsure of, or a
    # stop.)
    return [tuple(map(int, m.groups()[:4])) for m in
            re.finditer(r"class='ocrx_word'[^>]*title='bbox (\d+) (\d+) (\d+) (\d+); x_wconf (\d+)'[^>]*>(.*?)</span>", hocr)
            if int(m.group(5)) >= 60 and re.search(r'\w', re.sub('<[^>]+>', '', m.group(6)))]


def bands(profile, count):
    """The [count] lines in [profile] (ink by row): its [count] highest
    peaks at least 35 rows (8.4 pt) apart, each line's band the rows
    from above its peak down to where its ink falls off (its baseline)."""
    smooth = np.convolve(profile, np.ones(7) / 7, mode='same')
    peaks = [y for y in range(1, len(smooth) - 1)
             if smooth[y] >= smooth[y - 1] and smooth[y] > smooth[y + 1]]
    chosen = []
    for y in sorted(peaks, key=lambda y: -smooth[y]):
        if all(abs(y - c) >= 35 for c in chosen):
            chosen.append(y)
        if len(chosen) == count:
            break
    if len(chosen) < count:
        raise SystemExit(f'found {len(chosen)} lines, not {count}')
    runs = []
    for y in sorted(chosen):
        # (The foot of the x-height, where the ink falls off most
        # steeply below the peak, less the 3 rows that finds below the
        # baseline on the PDF's own page drawn at 300 ppi: the baseline.)
        fall = np.diff(smooth[y: y + 30])
        foot = y + int(np.argmin(fall)) + 1 - 3
        runs.append((max(0, y - 20), foot))
    return runs


def column(img, page, left, right, count):
    spec = PAGES[page]
    slope = slopes(page, left, right)
    crop = img.crop((left, spec['top'], right, spec['bottom']))
    level = crop.rotate(np.degrees(np.arctan(slope)), resample=Image.BICUBIC, fillcolor=255)
    a = np.asarray(level).astype(float)
    ink = a < 120
    # (The core of each line: the ink of its x-height, found from the
    # rows' ink right of the hung numbers.)
    w = ink.shape[1]
    profile = ink[:, 60:].sum(axis=1).astype(float)
    cx, cy = w / 2, ink.shape[0] / 2
    th = np.arctan(slope)

    def back(x, y):
        """A point of the levelled strip on the cut column."""
        dx, dy = x - cx, y - cy
        return (cx + dx * np.cos(th) - dy * np.sin(th), cy + dx * np.sin(th) + dy * np.cos(th))

    def level(x, y):
        """A point of the cut column on the levelled strip."""
        dx, dy = x - cx, y - cy
        return (cx + dx * np.cos(th) + dy * np.sin(th), cy - dx * np.sin(th) + dy * np.cos(th))

    feet = [foot for _, foot in bands(profile, count)]
    # (Each line's ends: its words', Tesseract's, each word on the line
    # whose baseline is nearest its foot.)
    ends = [[None, None] for _ in feet]
    for x0, y0, x1, y1 in words(page):
        if not (left <= (x0 + x1) / 2 < right):
            continue
        lx0, ly = level(x0 - left, y1 - spec['top'])
        lx1, _ = level(x1 - left, y1 - spec['top'])
        i = int(np.argmin([abs(ly - f) for f in feet]))
        if abs(ly - feet[i]) > 22 or x1 - x0 < 6:
            continue
        e = ends[i]
        e[0] = lx0 if e[0] is None else min(e[0], lx0)
        e[1] = lx1 if e[1] is None else max(e[1], lx1)
    # (And its ink's: the dark ink of its x-height, where a stroke is,
    # not a speck or the other side's print showing through; the line's
    # ends the farther of the two.)
    dark = a < 95
    rows = []
    for foot, (x0, x1) in zip(feet, ends):
        zone = dark[max(0, foot - 22): foot + 1]
        strokes = np.convolve(zone.sum(axis=0), np.ones(5), mode='same') >= 40
        xs = np.where(strokes)[0]
        if len(xs):
            x0 = xs[0] if x0 is None else min(x0, xs[0] - 2)
            x1 = xs[-1] if x1 is None else max(x1, xs[-1] + 2)
        if x0 is None:
            raise SystemExit(f'{page}: no words on the line at {foot}')
        bx0, by0 = back(x0, foot)
        bx1, _ = back(x1, foot)
        rows.append({'base': round((spec['top'] + by0) * PT, 2),
                     'left': round((left + bx0) * PT, 2),
                     'right': round((left + bx1) * PT, 2)})
    return rows


if __name__ == '__main__':
    data = {}
    for page, spec in PAGES.items():
        img = Image.open(os.path.join(WORK, f'{page:04d}.png')).convert('L')
        data[str(page)] = [column(img, page, l, r, n) for (l, r), n in zip(spec['columns'], spec['lines'])]
    json.dump(data, open(os.path.join(WORK, 'scan.json'), 'w'), indent=0)
    for p, cols in data.items():
        for c in cols:
            b = [r['base'] for r in c]
            d = [round(b[i + 1] - b[i], 1) for i in range(len(b) - 1)]
            print(p, len(c), b[0], b[-1], statistics.median(d), [(i, x) for i, x in enumerate(d) if abs(x - statistics.median(d)) > 2])
