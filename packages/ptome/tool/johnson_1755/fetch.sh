#!/bin/sh
# The work folder (JOHNSON_WORK): the three leaves' scans from the
# Internet Archive's JPEG 2000 files, checked against their SHA-256,
# drawn as PNG (Pillow), read by Tesseract (hOCR), and the item's own OCR
# (ABBYY, its djvu.txt) cut to the three pages' lines (lines.py).
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=${JOHNSON_WORK:-$HOME/.cache/asciidart-work/print-match/johnson}
ITEM=https://archive.org/download/b30451541_0002
mkdir -p "$WORK"
cd "$WORK"
for n in 0046 0047 0048; do
  [ -f b30451541_0002_$n.jp2 ] ||
    curl -sfL -o b30451541_0002_$n.jp2 "$ITEM/b30451541_0002_jp2.zip/b30451541_0002_jp2%2Fb30451541_0002_$n.jp2"
done
sha256sum -c <<'SUMS'
27a04d0e7fafebc2c1285ca6ffb277a659f052b1226a433ba3670fbf6e8634a1  b30451541_0002_0046.jp2
e5f6affe9aacd5f7121883f3921b1eb46578bd5b7378bc5d6c1f6fae69cd15b5  b30451541_0002_0047.jp2
ff5d703e47f3cc4f529fa794b91017408cf5d7c9942cc099f7b0da05250bac7f  b30451541_0002_0048.jp2
SUMS
for n in 0046 0047 0048; do
  [ -f $n.png ] || python3 -I -c "import sys; from PIL import Image; Image.open(sys.argv[1]).save(sys.argv[2])" b30451541_0002_$n.jp2 $n.png
  [ -f $n.hocr ] || tesseract $n.png $n -l eng hocr 2>/dev/null
done
[ -f djvu.txt ] || curl -sfL -o djvu.txt "$ITEM/b30451541_0002_djvu.txt"
python3 -I "$HERE/lines.py"
