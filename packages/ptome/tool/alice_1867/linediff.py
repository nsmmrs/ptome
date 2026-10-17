"""The draft's printed lines (out/BOOK/lines.tsv) against Standard
Ebooks' words: each line whose words differ, with SE's, and a sheet of
their scans for review (review/BOOK-diff-NN.png).

    python3 -I linediff.py BOOK [--sheets]
"""
import difflib, json, os, re, sys
from PIL import Image, ImageDraw, ImageFont
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import BOOKS, ROOT, REPO, ocr_path, scan_path
from textdiff import words


def main(book, sheets):
    cfg = BOOKS[book]
    rows = [r.rstrip('\n').split('\t', 1) for r in open(f'{ROOT}/out/{book}/lines.tsv', encoding='utf-8')]
    seen = set()
    draft = []
    for lid, t in rows:
        if lid in seen:
            continue
        seen.add(lid)
        for w in words(t):
            draft.append((w, lid))
    se = []
    for n in range(1, cfg['chapters'] + 1):
        se += words(open(f'{REPO}/text/{book}/chapter-{n}.adoc', encoding='utf-8').read())
    b = [w for w, _ in draft]
    out = []
    for op, i1, i2, j1, j2 in difflib.SequenceMatcher(None, se, b, autojunk=False).get_opcodes():
        if op == 'equal':
            continue
        if ''.join(se[i1:i2]) == ''.join(b[j1:j2]):
            continue
        lid = draft[min(j1, len(draft) - 1)][1]
        out.append((lid, ' '.join(se[i1:i2]), ' '.join(b[j1:j2])))
    for lid, s, d in out:
        print(lid, '|', s, '|', d)
    if sheets:
        pages = json.load(open(ocr_path(cfg)))
        font = ImageFont.truetype('/usr/share/fonts/noto/NotoSans-Regular.ttf', 22)
        text = {lid: t for lid, t in rows}
        for k in range(0, len(out), 16):
            ims = []
            for lid, s, d in out[k:k + 16]:
                leaf, i = (int(x) for x in lid.split('+')[0].split(':'))
                lines = [l for l in pages[leaf]['lines']]
                im = Image.open(scan_path(cfg, leaf)).convert('RGB')
                # (The line by its draft's place: the OCR line it came from.)
                box = lines[i]['b'] if i < len(lines) else [0, 0, im.width, 100]
                crop = im.crop((0, box[1] - 20, im.width, box[3] + 20)).resize((1300, int((box[3] - box[1] + 40) * 1300 / im.width)))
                ims.append((f'{lid}  SE: {s}   draft: {d}', text.get(lid, ''), crop))
            H = sum(c.height + 56 for _, _, c in ims)
            sheet = Image.new('RGB', (1300, H), 'white')
            dr = ImageDraw.Draw(sheet)
            y = 0
            for a, t, c in ims:
                dr.text((4, y), a, fill=(160, 0, 0), font=font)
                dr.text((4, y + 26), t, fill='black', font=font)
                sheet.paste(c, (0, y + 54))
                y += c.height + 56
            sheet.save(f'{ROOT}/review/{book}-diff-{k // 16 + 1:02d}.png')
    print(len(out), 'differences')


if __name__ == '__main__':
    main(sys.argv[1], '--sheets' in sys.argv)
