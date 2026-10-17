"""Each leaf's text read by Tesseract (its LSTM English model, page
segmentation 6, one block of lines): the upright leaf (geometry.py's)
inside its frame of flowers, the frame's outer rule set in by INSET
pixels each side, read as TSV; each line its box and its words' boxes
and text, in the upright leaf's pixels. Written to BCP_WORK/tess.json.

    python3 -I ocr.py [LEAF...]
"""
import csv, io, json, os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from common import WORK, LEAVES

INSET = 56


def read(leaf, frame):
    from PIL import Image
    x0, y0, x1, y1 = frame['outer']
    box = (x0 + INSET, y0 + INSET - 8, x1 - INSET, y1 - INSET + 8)
    crop = Image.open(os.path.join(WORK, 'upright', f'{leaf:04d}.png')).crop(box)
    tmp = os.path.join(WORK, 'tess', f'{leaf:04d}.png')
    crop.save(tmp)
    out = subprocess.run(['tesseract', tmp, '-', '-l', 'eng', '--psm', '6', 'tsv'],
                         capture_output=True, text=True).stdout
    lines = {}
    for r in csv.DictReader(io.StringIO(out), delimiter='\t', quoting=csv.QUOTE_NONE):
        if r['level'] != '5' or not r['text'].strip():
            continue
        key = (int(r['block_num']), int(r['par_num']), int(r['line_num']))
        x, y, w, h = (int(r[k]) for k in ('left', 'top', 'width', 'height'))
        lines.setdefault(key, []).append({'t': r['text'], 'box': [x + box[0], y + box[1], x + w + box[0], y + h + box[1]],
                                          'c': float(r['conf'])})
    res = []
    for key in sorted(lines):
        ws = lines[key]
        res.append({'box': [min(w['box'][0] for w in ws), min(w['box'][1] for w in ws),
                            max(w['box'][2] for w in ws), max(w['box'][3] for w in ws)],
                    'words': ws, 'ocr': ' '.join(w['t'] for w in ws)})
    res.sort(key=lambda l: l['box'][1])
    return res


def main():
    geo = json.load(open(os.path.join(WORK, 'geometry.json')))
    os.makedirs(os.path.join(WORK, 'tess'), exist_ok=True)
    # (TESS_OUT: another file, a share of the leaves read in parallel.)
    path = os.environ.get('TESS_OUT', os.path.join(WORK, 'tess.json'))
    data = json.load(open(path)) if os.path.exists(path) else {}
    for leaf in [int(a) for a in sys.argv[1:]] or LEAVES:
        g = geo[str(leaf)]
        if not g['frame']:
            print(leaf, 'no frame')
            continue
        data[str(leaf)] = read(leaf, g['frame'])
        print(leaf, len(data[str(leaf)]), 'lines')
        json.dump(data, open(path, 'w'))


main()
