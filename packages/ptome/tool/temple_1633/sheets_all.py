"""Every page beside its scan, eight to a sheet: sheets_all.py FIRST LAST OUT-PREFIX."""
import glob, os, subprocess, sys, tempfile
from PIL import Image
W = os.environ.get('TEMPLE_WORK', os.path.expanduser('~/.cache/asciidart-work/print-match'))
D = glob.glob(f'{W}/herbert/*_jp2')[0]
NAME = D.split('/')[-1][:-4]
first, last, out = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
H = 470
with tempfile.TemporaryDirectory() as t:
    subprocess.run(['pdftoppm', '-r', '80', '-png', '-f', str(first), '-l', str(last),
                    f'{W}/build/herbert/herbert.pdf', f'{t}/p'], check=True)
    pngs = sorted(os.listdir(t))
    pairs = []
    for k, page in enumerate(range(first, last + 1)):
        a = Image.open(f'{t}/{pngs[k]}').convert('L'); a = a.resize((int(a.width * H / a.height), H))
        b = Image.open(f'{D}/{NAME}_{page - 1:04d}.jp2').convert('L')
        # (The scan cut to its paper: inside the film's black.)
        import numpy as np
        arr = np.asarray(b) < 60
        cols = np.nonzero(arr.mean(0) < 0.5)[0]; rows = np.nonzero(arr.mean(1) < 0.5)[0]
        b = b.crop((int(cols[0]), int(rows[0]), int(cols[-1]), int(rows[-1])))
        b = b.resize((int(b.width * H / b.height), H))
        im = Image.new('L', (a.width + b.width + 3, H), 0); im.paste(a, (0, 0)); im.paste(b, (a.width + 3, 0))
        pairs.append(im)
    for s in range(0, len(pairs), 8):
        part = pairs[s:s + 8]
        w = max(p.width for p in part)
        sheet = Image.new('L', (4 * (w + 8), 2 * (H + 8)), 128)
        for i, p in enumerate(part):
            sheet.paste(p, ((i % 4) * (w + 8), (i // 4) * (H + 8)))
        sheet.save(f'{out}{first + s:03d}.png')
