"""Each chapter opening's heading spaces, from the scan: where "CHAPTER"
stands, the gap to its title, and the text below as far down as the
printing sets the page's last line (its lines counted from the
transcription). Prints the look's `opening<n>` roles."""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import BOOKS, ROOT, BOOK, DPI, PITCH_PX, ocr_path, scan_path

book = sys.argv[1]
cfg = BOOKS[book]
P = json.load(open(ocr_path(cfg)))
cuts = json.load(open(f'{ROOT}/placed-{book}.json'))
present = {}
for row in open(f'{ROOT}/out/{book}/lines.tsv', encoding='utf-8'):
    lid = row.split('\t')[0]
    leaf, i = lid.split(':')[0], lid.split(':')[1].split('+')[0]
    present.setdefault(int(leaf), set()).add(int(i))
PT = 72 / DPI
GRID = 16.82
page_top = 48.8
last_base = 60.7 + 21 * GRID
openers = [leaf for leaf in range(cfg['first'], cfg['last'] + 1)
           if any(' '.join(w['t'] for w in l['w']).strip().startswith('CHAP')
                  for l in P[leaf]['lines'])]
for n, leaf in enumerate(openers, 1):
    L = P[leaf]['lines']
    i = next(k for k, l in enumerate(L)
             if ' '.join(w['t'] for w in l['w']).strip().startswith('CHAP'))
    ch, ti = L[i], L[i + 1]
    ks = [k for k in sorted(present.get(leaf, ())) if k > i + 1]
    # (Every line from the first to the last, one with only a divided
    # word's rest included.)
    body = [L[k] for k in range(ks[0], ks[-1] + 1)]
    S = (ch['b'][1] + 75) * PT
    T = (ti['b'][1] + 55) * PT
    Bl = min(last_base, (body[-1]['b'][1] + 77) * PT)
    N = len(body) + (1 if leaf in cfg.get('opening_extra_line', ()) else 0)
    Bf = Bl - (N - 1) * GRID
    G1, G2 = T - S, Bf - T
    half = (G1 - 14.03) / 2
    mb = G2 - 13.70 - half
    cut = next((c for c in cuts if c.get('chapter') == n and 'side' not in c), None)
    if cut:
        k = f'heading_h2_margin_top: {S - (page_top + cut["height"]) - 11.47 - half:.1f}'
    else:
        k = f'heading_h2_margin_page_top: {S - (page_top + 11.47) - half:.1f}'
    print(f'      {cfg.get("opening_role", "opening")}{n}: {{ {k}, heading_h2_line_pitch: {G1:.1f}, '
          f'heading_h2_margin_bottom: {mb:.1f} }}  # {N} lines')
