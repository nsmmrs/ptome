"""The frame of printers' flowers the octavo sets round each page (a
lozenge and a star in turn, a fleuron at each corner, inside a rule),
traced from one leaf of the scan (FRAME_LEAF, upright): the frame's
band, the text inside it whitened, its ink traced by potrace into an
SVG of the page's size whose user unit is the point (the scan's PX
pixels a point), the frame's outer rule's top left at (FX, FY). Written to the showcase's
images/frame.svg; the frame's size in points printed, the look's.

    python3 -I frame.py
"""
import json, os, subprocess, sys
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from common import WORK, PX, PAGE, FX, FY

OUT = os.path.join(HERE, '..', '..', 'test', 'showcase', 'bcp', 'images', 'frame.svg')
FRAME_LEAF = 417
BAND = 62  # (the band's depth in pixels: the rule and the flowers)


def main():
    g = json.load(open(os.path.join(WORK, 'geometry.json')))[str(FRAME_LEAF)]
    x0, y0, x1, y1 = g['frame']['outer']
    a = np.asarray(Image.open(os.path.join(WORK, 'upright', f'{FRAME_LEAF:04d}.png')))
    pad = 4
    crop = a[y0 - pad:y1 + pad + 1, x0 - pad:x1 + pad + 1].copy()
    ink = crop < 120
    ink[pad + BAND:-pad - BAND, pad + BAND:-pad - BAND] = False
    pbm = os.path.join(WORK, 'frame.pbm')
    Image.fromarray(((~ink) * 255).astype(np.uint8)).convert('1').save(pbm)
    dpi = PX * 72
    svg = subprocess.run(['potrace', pbm, '-s', '-o', '-', '-r', f'{dpi:.4f}', '-t', '4', '-a', '1.0', '-O', '0.4',
                          '--flat'], capture_output=True, text=True, check=True).stdout
    # (Its origin the outer rule's top left: the pad taken off.)
    w, h = (x1 - x0) / PX, (y1 - y0) / PX
    body = svg[svg.index('<g'):svg.rindex('</svg>')]
    off = pad / PX
    out = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{PAGE[0]}pt" height="{PAGE[1]}pt" '
           f'viewBox="0 0 {PAGE[0]} {PAGE[1]}">\n'
           f'<!-- The Cambridge octavo\'s frame of flowers (1761), traced from the Internet Archive\'s scan '
           f'(10904662bsb, leaf {FRAME_LEAF}) by tool/bcp_1761/frame.py. -->\n'
           f'<g transform="translate({FX - off:.3f} {FY - off:.3f})">\n{body}</g>\n</svg>\n')
    out = out.replace('fill="#000000"', 'fill="#1a1a1a"')
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    open(OUT, 'w').write(out)
    print(f'frame {w:.2f} x {h:.2f} pt; {len(out)} bytes')


main()
