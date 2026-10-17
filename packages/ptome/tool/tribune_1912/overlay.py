"""A page of the PDF over the scan's (red the scan, blue the PDF, black
where both), cut into strips to read by eye: TRIBUNE_WORK/overlay/.

    python3 -I overlay.py PAGE [X0 Y0 X1 Y1]   (a part, in the scan's pixels)
"""
import os, subprocess, sys
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from common import WORK, PX, IMAGES


def main():
    page = int(sys.argv[1])
    box = tuple(int(v) for v in sys.argv[2:6]) if len(sys.argv) >= 6 else None
    out = os.path.join(WORK, 'overlay')
    os.makedirs(out, exist_ok=True)
    pdf = os.path.join(WORK, 'build', 'tribune.pdf')
    dpi = 72 * PX / 2
    subprocess.run(['pdftoppm', '-r', f'{dpi:.3f}', '-f', str(page), '-l', str(page), '-png', '-singlefile', '-gray',
                    pdf, os.path.join(out, 'pdf')], check=True)
    a = Image.open(os.path.join(out, 'pdf.png')).convert('L')
    b = Image.open(os.path.join(WORK, IMAGES[page] + '.jpg')).convert('L')
    b = b.resize((b.width // 2, b.height // 2))
    w, h = min(a.width, b.width), min(a.height, b.height)
    a, b = a.crop((0, 0, w, h)), b.crop((0, 0, w, h))
    im = Image.merge('RGB', (a, b, b)) if False else Image.merge('RGB', (b.point(lambda v: 255 if v > 150 else v), a, a))
    if box:
        im = im.crop(tuple(v // 2 for v in box))
    im.save(os.path.join(out, f'p{page}.png'))
    print(os.path.join(out, f'p{page}.png'), im.size)


main()
