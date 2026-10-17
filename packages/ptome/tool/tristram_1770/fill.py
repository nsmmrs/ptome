"""The lines ABBYY's OCR missed, read by Tesseract: each page's bands of
ink across its text block (the rows where most of the block's width has
ink, a gap of a row or two bridged) that no OCR line lies on, each band
cut from the scan and read as a line (Tesseract's English model,
segmentation 7, TSV for its words' boxes). Written into
TRISTRAM_WORK/ocr2.json: ocr.json with those lines in their places.

    python3 -I fill.py
"""
import csv, io, json, os, subprocess, sys
from concurrent.futures import ThreadPoolExecutor
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from common import WORK


def bands(ink, x0, x1, y0, y1):
    prof = ink[y0:y1, x0:x1].sum(axis=1)
    on = prof > 0.04 * (x1 - x0)
    out, start, miss = [], None, 0
    for y, v in enumerate(on):
        if v:
            start = y if start is None else start
            miss = 0
        elif start is not None:
            miss += 1
            if miss > 2:
                out.append((y0 + start, y0 + y - miss + 1))
                start, miss = None, 0
    if start is not None:
        out.append((y0 + start, y1))
    return [b for b in out if b[1] - b[0] >= 12]


def read(job):
    path, box, png = job
    im = Image.open(png).convert('L').crop(box)
    im = im.resize((im.width * 2, im.height * 2), Image.LANCZOS)
    im.save(path)
    env = dict(os.environ, OMP_THREAD_LIMIT='1')
    out = subprocess.run(['tesseract', path, '-', '-l', 'eng', '--psm', '7', 'tsv'],
                         capture_output=True, text=True, env=env).stdout
    words = []
    for r in csv.DictReader(io.StringIO(out), delimiter='\t', quoting=csv.QUOTE_NONE):
        if r['level'] == '5' and r['text'].strip():
            x, y, w, h = (int(r[k]) // 2 for k in ('left', 'top', 'width', 'height'))
            words.append({'t': r['text'], 'b': [box[0] + x, box[1] + y, box[0] + x + w, box[1] + y + h],
                          'c': int(float(r['conf']))})
    return words


def main():
    ocr = json.load(open(os.path.join(WORK, 'ocr.json')))
    leaves = json.load(open(os.path.join(WORK, 'leaves.json')))
    os.makedirs(os.path.join(WORK, 'fill'), exist_ok=True)
    jobs, where = [], []
    for leaf, page in leaves:
        lines = ocr[leaf]['lines']
        if len(lines) < 5:
            continue
        png = os.path.join(WORK, 'png', f'{leaf:04d}.png')
        ink = np.asarray(Image.open(png).convert('L')) < 120
        lefts = sorted(l['b'][0] for l in lines)
        rights = sorted(l['b'][2] for l in lines)
        x0, x1 = lefts[len(lefts) // 4], rights[len(rights) * 3 // 4]
        y0, y1 = min(l['b'][1] for l in lines), max(l['b'][3] for l in lines)
        for a, b in bands(ink, x0, x1, y0, y1):
            covered = any(min(b, l['b'][3]) - max(a, l['b'][1]) > 0.5 * (b - a) for l in lines)
            if not covered:
                box = (max(0, x0 - 30), a - 6, min(ink.shape[1], x1 + 30), b + 6)
                jobs.append((os.path.join(WORK, 'fill', f'{leaf:04d}-{a}.png'), box, png))
                where.append(leaf)
    with ThreadPoolExecutor(8) as ex:
        got = list(ex.map(read, jobs))
    added = 0
    for leaf, (path, box, png), words in zip(where, jobs, got):
        words = [w for w in words if w['t'].strip()]
        if not words or not any(c.isalpha() for w in words for c in w['t']):
            continue
        b = [min(w['b'][0] for w in words), min(w['b'][1] for w in words),
             max(w['b'][2] for w in words), max(w['b'][3] for w in words)]
        ocr[leaf]['lines'].append({'b': b, 'w': words, 'filled': True})
        ocr[leaf]['lines'].sort(key=lambda l: (l['b'][1] + l['b'][3]) / 2)
        added += 1
    json.dump(ocr, open(os.path.join(WORK, 'ocr2.json'), 'w'))
    print(added, 'lines added of', len(jobs), 'bands')


main()
