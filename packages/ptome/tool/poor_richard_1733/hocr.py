"""The work folder and the scans' scale: PR_WORK (by default
~/.cache/asciidart-work/print-match/poor-richard), its leaves drawn at
400 ppi, 0.18 pt a pixel; each leaf's words as Tesseract reads them
(`tesseract png/NNNN.png tess/NNNN -l eng hocr`, fetch.sh), with their
boxes in points."""
import html, os, re

WORK = os.environ.get('PR_WORK', os.path.expanduser('~/.cache/asciidart-work/print-match/poor-richard'))
PT = 72 / 400


def words(leaf):
    """The leaf's words: (text, x0, y0, x1, y1) in points; those
    Tesseract is unsure of left out."""
    s = open(os.path.join(WORK, 'tess', f'{leaf:04d}.hocr'), encoding='utf-8').read()
    out = []
    for m in re.finditer(r"class='ocrx_word'[^>]*title='bbox (\d+) (\d+) (\d+) (\d+); x_wconf (\d+)'[^>]*>(.*?)</span>", s, re.S):
        text = html.unescape(re.sub('<[^>]+>', '', m.group(6))).strip()
        if text and int(m.group(5)) >= 50:
            x0, y0, x1, y1 = (int(v) * PT for v in m.groups()[:4])
            out.append((text, x0, y0, x1, y1))
    return out
