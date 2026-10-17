"""The front pages' lines that the printing doesn't spread to the
measure (centred or short), the PDF's width of each against the scan's
(both from their ink, measure.py; front.py's places): how far each
line's type is too wide or narrow. Its own size goes by it.

    python3 -I widths_front.py
"""
import os, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.argv = sys.argv[:1]
sys.path.insert(0, HERE)
src = open(os.path.join(HERE, 'front.py')).read()
g = {'__name__': 'front', '__file__': os.path.join(HERE, 'front.py')}
exec(compile(src[:src.rindex('\nif REPORT:')], 'front.py', 'exec'), g)
import measure
from PIL import Image

lines, pages = g['blocks']()
for page, leaf in g['PAGES'].items():
    pl = g['pdf_lines'](page)
    ink, _, _ = measure.upright(Image.open(os.path.join(measure.WORK, 'png', f'{leaf:04d}.png')).convert('L'))
    left, top = measure.frame(ink)
    pink, _, _ = measure.upright(measure.pdf_page(g['PDF'], page).convert('L'))
    pleft, ptop = measure.frame(pink)
    sl = g['scan_lines'](leaf)
    at = 0
    for k, b in enumerate(pages[page]):
        if b['kind'] != 'text':
            continue
        got = pl[at]['base']
        at += b['lines']
        want = g['TARGETS'].get(f'{page}/{k + 1}')
        if want is None:
            best = None
            for s in sl:
                sc = len(set(b['words']) & s['words'])
                if sc and (best is None or sc > best[0]):
                    best = (sc, s['base'])
            want = best[1] if best else None
        if want is None:
            continue
        a = measure.extents(pink, pleft, ptop + int(got / measure.PT), width=266)
        c = measure.extents(ink, left, top + int(want / measure.PT), width=266)
        if a and c and a[1] < 262 and c[1] < 262:
            print(f'{page}/{k + 1} {lines[b["attr"]][:24]:24} pdf {a[0]:6.1f}..{a[1]:6.1f} scan {c[0]:6.1f}..{c[1]:6.1f} '
                  f'width {(a[1] - a[0]) / (c[1] - c[0]):.3f}')
