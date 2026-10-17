"""A second reading of each region's lines (lines.py's): its box cut from
the scan, a little room round it, the lines above and below blanked,
twice its size, read by Tesseract as a line (its LSTM English model,
segmentation 7). Written to TRIBUNE_WORK/tess.json, by page and region,
in lines.json's order.

    python3 -I tess.py
"""
import json, os, subprocess, sys
from concurrent.futures import ThreadPoolExecutor
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from common import WORK, IMAGES

PAD = 8


def read(job):
    im, box, path = job
    import numpy as np
    x0, y0, x1, y1 = box
    crop = im.crop((x0 - PAD, y0 - PAD, x1 + PAD, y1 + PAD))
    # (The line alone: the rows of ink round the box's middle, those of
    # the lines above and below, which the box takes a piece of, blanked.)
    a = np.asarray(crop).copy()
    # (A column's rule at the side: whitened, no line's ink.)
    dark = a < 120
    rule = dark.mean(axis=0) > 0.7
    a[:, rule] = 255
    dark[:, rule] = False
    rows = dark.sum(axis=1) > max(2, 0.01 * a.shape[1])
    # (The bands of rows with ink, a row or two without bridged: the line
    # the one that holds most of the box's own rows.)
    bands, start, miss = [], None, 0
    for y, r in enumerate(rows):
        if r:
            start = y if start is None else start
            miss = 0
        elif start is not None:
            miss += 1
            if miss > 2:
                bands.append((start, y - miss + 1))
                start, miss = None, 0
    if start is not None:
        bands.append((start, len(rows)))
    inner = (PAD, len(rows) - PAD)
    if bands:
        top, bottom = max(bands, key=lambda b: min(b[1], inner[1]) - max(b[0], inner[0]) + 0.001 * dark[b[0]:b[1]].sum())
        a[:max(0, top - 2)] = 255
        a[bottom + 2:] = 255
    crop = Image.fromarray(a)
    crop = crop.resize((crop.width * 2, crop.height * 2), Image.LANCZOS)
    crop.save(path)
    env = dict(os.environ, OMP_THREAD_LIMIT='1')
    out = subprocess.run(['tesseract', path, '-', '-l', 'eng', '--psm', '7'],
                         capture_output=True, text=True, env=env).stdout
    return ' '.join(out.split())


def main():
    lines = json.load(open(os.path.join(WORK, 'lines.json')))
    os.makedirs(os.path.join(WORK, 'lines'), exist_ok=True)
    res = {}
    for page, regs in lines.items():
        im = Image.open(os.path.join(WORK, IMAGES[int(page)] + '.jpg'))
        im.load()
        jobs, keys = [], []
        for rid, rows in regs.items():
            for k, r in enumerate(rows):
                jobs.append((im, r['box'], os.path.join(WORK, 'lines', f'{page}-{rid}-{k:03d}.png')))
                keys.append(rid)
        with ThreadPoolExecutor(8) as ex:
            got = list(ex.map(read, jobs))
        res[page] = {}
        for rid, text in zip(keys, got):
            res[page].setdefault(rid, []).append(text)
    json.dump(res, open(os.path.join(WORK, 'tess.json'), 'w'))
    print(sum(len(v) for p in res.values() for v in p.values()), 'lines read')


main()
