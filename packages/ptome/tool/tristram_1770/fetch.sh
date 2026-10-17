#!/bin/sh
# The work folder (TRISTRAM_WORK): the Internet Archive's scan of the
# Bayerische Staatsbibliothek's Tristram Shandy, Vol. I (London: J.
# Dodsley, 1770; 10931855bsb), its JPEG 2000 leaves of the pages the work
# sets and the Archive's hOCR (ABBYY's OCR), each checked against its
# SHA-256 (scans.sha256); then the leaves drawn grey (png/), the hOCR
# read (ocr.json, alice_1867/hocr.py), the leaves put in the book's order
# (leaves.py), the lines ABBYY missed read by Tesseract (fill.py), every
# leaf read again by Tesseract (tess.py) and the text decided (choose.sh).
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=${TRISTRAM_WORK:-$HOME/.cache/asciidart-work/print-match/tristram}
ITEM=https://archive.org/download/10931855bsb
mkdir -p "$WORK/jp2" "$WORK/png"
cd "$WORK"
for f in $(cut -c67- "$HERE/scans.sha256" | grep '\.jp2$'); do
  [ -f "jp2/$f" ] || curl -sfL -o "jp2/$f" "$ITEM/10931855bsb_jp2.zip/10931855bsb_jp2%2F10931855bsb_$f"
done
[ -f 10931855bsb_hocr.html ] || curl -sfL -o 10931855bsb_hocr.html "$ITEM/10931855bsb_hocr.html"
grep '\.jp2$' "$HERE/scans.sha256" | (cd jp2 && sha256sum -c --quiet -)
grep 'hocr' "$HERE/scans.sha256" | sha256sum -c --quiet -
python3 -I - "$WORK" <<'PY'
import os, sys
from PIL import Image
w = sys.argv[1]
for f in sorted(os.listdir(os.path.join(w, 'jp2'))):
    out = os.path.join(w, 'png', f.replace('.jp2', '.png'))
    if not os.path.exists(out):
        Image.open(os.path.join(w, 'jp2', f)).convert('L').save(out)
PY
[ -f ocr.json ] || python3 -I "$HERE/../alice_1867/hocr.py" 10931855bsb_hocr.html ocr.json
python3 -I "$HERE/leaves.py"
[ -f ocr2.json ] || python3 -I "$HERE/fill.py"
[ -f tess.json ] || python3 -I "$HERE/tess.py"
CHOOSE=1 sh "$HERE/choose.sh"
