"""A book's scan and OCR resampled to Wonderland's 650 ppi (the book's
`scale`), so the measures tuned on Wonderland's scan hold: each leaf a
JPEG in ROOT/ID_650/, the OCR's boxes scaled in ROOT/ID_650.ocr.json.

    python3 -I rescale.py BOOK
"""
import json, os, sys
from concurrent.futures import ProcessPoolExecutor
from PIL import Image
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import BOOKS, ROOT, ocr_path, scan_path

Image.MAX_IMAGE_PIXELS = None


def scaled(node, f):
    if isinstance(node, dict):
        return {k: ([round(v * f) for v in x] if k == 'b' else scaled(x, f)) for k, x in node.items()}
    if isinstance(node, list):
        return [scaled(x, f) for x in node]
    return node


def leaf(args):
    cfg, n = args
    src = f'{ROOT}/{cfg["id"]}/{cfg["id"]}_jp2/{cfg["id"]}_{n:04d}.jp2'
    im = Image.open(src).convert('RGB')
    f = cfg['scale']
    im.resize((round(im.width * f), round(im.height * f)), Image.LANCZOS).save(
        scan_path(cfg, n), quality=92)


def main(book):
    cfg = BOOKS[book]
    os.makedirs(f'{ROOT}/{cfg["id"]}_650', exist_ok=True)
    pages = json.load(open(f'{ROOT}/{cfg["id"]}.ocr.json'))
    json.dump(scaled(pages, cfg['scale']), open(ocr_path(cfg), 'w'))
    with ProcessPoolExecutor(6) as ex:
        list(ex.map(leaf, [(cfg, n) for n in range(len(pages))]))
    print(len(pages), 'leaves')


if __name__ == '__main__':
    main(sys.argv[1])
