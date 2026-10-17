"""Each leaf read again by Tesseract (its English model, segmentation 6:
one block of lines), the scan twice its size: its lines, their words and
boxes in the scan's pixels, the form of ocr.json. Written to
TRISTRAM_WORK/tess.json, by leaf. ABBYY's OCR runs a few pages' lines
together; decide.py reads those pages from this.

    python3 -I tess.py
"""
import csv, io, json, os, subprocess, sys
from concurrent.futures import ThreadPoolExecutor
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from common import WORK


def read(leaf):
    png = os.path.join(WORK, 'png', f'{leaf:04d}.png')
    tmp = os.path.join(WORK, 'tess', f'{leaf:04d}.png')
    im = Image.open(png).convert('L')
    im.resize((im.width * 2, im.height * 2), Image.LANCZOS).save(tmp)
    env = dict(os.environ, OMP_THREAD_LIMIT='1')
    out = subprocess.run(['tesseract', tmp, '-', '-l', 'eng', '--psm', '6', 'tsv'],
                         capture_output=True, text=True, env=env).stdout
    lines = {}
    for r in csv.DictReader(io.StringIO(out), delimiter='\t', quoting=csv.QUOTE_NONE):
        if r['level'] != '5' or not r['text'].strip():
            continue
        k = (int(r['block_num']), int(r['par_num']), int(r['line_num']))
        x, y, w, h = (int(r[c]) // 2 for c in ('left', 'top', 'width', 'height'))
        lines.setdefault(k, []).append({'t': r['text'], 'b': [x, y, x + w, y + h], 'c': int(float(r['conf']))})
    res = []
    for k in sorted(lines):
        ws = lines[k]
        res.append({'b': [min(w['b'][0] for w in ws), min(w['b'][1] for w in ws),
                          max(w['b'][2] for w in ws), max(w['b'][3] for w in ws)], 'w': ws})
    return leaf, res


def main():
    leaves = json.load(open(os.path.join(WORK, 'leaves.json')))
    os.makedirs(os.path.join(WORK, 'tess'), exist_ok=True)
    with ThreadPoolExecutor(8) as ex:
        got = dict(ex.map(read, [leaf for leaf, _ in leaves]))
    json.dump({str(k): {'lines': v} for k, v in got.items()}, open(os.path.join(WORK, 'tess.json'), 'w'))
    print(len(got), 'leaves read')


main()
