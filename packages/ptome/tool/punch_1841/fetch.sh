#!/bin/sh
# The work folder (PUNCH_WORK): the Internet Archive's scan of Punch's
# first volume (sim_punch_1841_1), its JPEG 2000 leaves of the three
# issues (leaves 4 to 15 and 52 to 75, the printed page the leaf less
# three) drawn as PNG (Pillow), its page images (the cuts' crops in
# fetch.yml are of them) and its OCR (hOCR, read by
# ../alice_1867/hocr.py into ocr.json), each checked against its SHA-256
# (scans.sha256, pages.sha256); page 3, set sideways, turned to read and
# read by Tesseract (p3/ocr.hocr, p3.py's). Then the leaves turned
# upright and measured (geometry.py).
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=${PUNCH_WORK:-$HOME/.cache/asciidart-work/print-match/punch}
ITEM=https://archive.org/download/sim_punch_1841_1
LEAVES="$(seq 4 15) $(seq 52 75)"
mkdir -p "$WORK/jp2" "$WORK/png" "$WORK/jpg" "$WORK/p3"
cd "$WORK"
[ -f sim_punch_1841_1_hocr.html ] || curl -sfL -O "$ITEM/sim_punch_1841_1_hocr.html"
echo "f446297632025f7729df8716867fdb9a8eb4558ca42d9fcc212e89fd7e0b07f4  sim_punch_1841_1_hocr.html" | sha256sum -c
for n in $LEAVES; do
  f=$(printf %04d "$n")
  [ -f "jp2/$f.jp2" ] || curl -sfL -o "jp2/$f.jp2" "$ITEM/sim_punch_1841_1_jp2.zip/sim_punch_1841_1_jp2%2Fsim_punch_1841_1_$f.jp2"
  [ -f "jpg/n$n.jpg" ] || curl -sfL -o "jpg/n$n.jpg" "$ITEM/page/n$n.jpg"
done
(cd jp2 && sha256sum -c "$HERE/scans.sha256")
(cd jpg && sha256sum -c "$HERE/pages.sha256")
for n in $LEAVES; do
  f=$(printf %04d "$n")
  [ -f "png/$f.png" ] || python3 -I -c "import sys; from PIL import Image; Image.open(sys.argv[1]).convert('L').save(sys.argv[2])" "jp2/$f.jp2" "png/$f.png"
done
[ -f ocr.json ] || python3 -I "$HERE/../alice_1867/hocr.py" sim_punch_1841_1_hocr.html ocr.json
[ -f p3_upright.png ] || python3 -I -c "import sys; from PIL import Image; Image.open(sys.argv[1]).rotate(-90, expand=True).save(sys.argv[2])" png/0006.png p3_upright.png
[ -f p3/ocr.hocr ] || tesseract p3_upright.png p3/ocr -l eng --psm 3 hocr
python3 -I "$HERE/geometry.py"
