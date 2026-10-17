"""Each leaf's line pitch in the scan's pixels: the median distance
between its prose lines' baselines (the OCR's lines' bottoms, those a
line apart), what transcribe.py scales each leaf's measures by.

    python3 -I pitch.py BOOK -> pitch-BOOK.json
"""
import json, os, statistics, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import BOOKS, ROOT, ocr_path, scan_path


def main(book):
    cfg = BOOKS[book]
    pages = json.load(open(ocr_path(cfg)))
    out = {}
    for leaf in range(cfg['first'], cfg['last'] + 1):
        # (Prose lines alone, full ones: not a poem's, leaded otherwise.)
        lines = sorted((l for l in pages[leaf]['lines'] if l['b'][2] - l['b'][0] > cfg.get('full_px', 0)),
                       key=lambda l: l['b'][3])
        lo, hi = (120, 190)
        gaps = [b['b'][3] - a['b'][3] for a, b in zip(lines, lines[1:])
                if lo <= b['b'][3] - a['b'][3] <= hi]
        if len(gaps) >= 4:
            out[str(leaf)] = statistics.median(gaps)
    json.dump(out, open(f'{ROOT}/pitch-{book}.json', 'w'), indent=0)
    print(len(out), 'leaves')


if __name__ == '__main__':
    main(sys.argv[1])
