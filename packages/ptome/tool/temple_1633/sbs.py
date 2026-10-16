"""PDF pages beside the scan's leaves: sbs.py FIRST LAST OUT (PDF pages)."""
import glob, os, subprocess, sys, tempfile
from PIL import Image
W = os.environ.get('TEMPLE_WORK', os.path.expanduser('~/.cache/asciidart-work/print-match'))
D = glob.glob(f'{W}/herbert/*_jp2')[0]
NAME = D.split('/')[-1][:-4]
first, last, out = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
H = 560
with tempfile.TemporaryDirectory() as t:
    subprocess.run(['pdftoppm', '-r', '100', '-png', '-f', str(first), '-l', str(last), f'{W}/build/herbert/herbert.pdf', f'{t}/p'], check=True)
    pngs = sorted(os.listdir(t))
    pairs = []
    for k, page in enumerate(range(first, last + 1)):
        a = Image.open(f'{t}/{pngs[k]}').convert('RGB'); a = a.resize((int(a.width * H / a.height), H))
        b = Image.open(f'{D}/{NAME}_{page - 1:04d}.jp2').convert('RGB'); b.thumbnail((2000, H))
        im = Image.new('RGB', (a.width + b.width + 4, H), 'red'); im.paste(a, (0, 0)); im.paste(b, (a.width + 4, 0))
        pairs.append(im)
    sheet = Image.new('RGB', (sum(p.width for p in pairs) + 10 * len(pairs), H), 'gray')
    x = 0
    for p in pairs:
        sheet.paste(p, (x, 0)); x += p.width + 10
    sheet.save(out)
