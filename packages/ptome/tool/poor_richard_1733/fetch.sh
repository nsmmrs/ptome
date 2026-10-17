#!/bin/sh
# The work folder (PR_WORK): the facsimile's JPEG 2000 scans from the
# Internet Archive, checked against their SHA-1 (the item's own), its
# leaves drawn as PNG (Pillow) and read by Tesseract (hOCR).
set -e
WORK=${PR_WORK:-$HOME/.cache/asciidart-work/print-match/poor-richard}
ITEM=https://archive.org/download/poorrichardalman00fran
mkdir -p "$WORK/png" "$WORK/tess" "$WORK/jp2"
cd "$WORK"
[ -f poorrichardalman00fran_jp2.zip ] || curl -sfL -O "$ITEM/poorrichardalman00fran_jp2.zip"
echo "1d625cbccf8b2e274f62681e283c9ffe35c45265  poorrichardalman00fran_jp2.zip" | sha1sum -c
python3 -I -c "import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" poorrichardalman00fran_jp2.zip jp2
for n in 0001 0004 0005 0007 0009 0010 0011 0012 0013 0014 0015 0016 0017 0018 0019 0020; do
  [ -f png/$n.png ] || python3 -I -c "import sys; from PIL import Image; Image.open(sys.argv[1]).convert('L').save(sys.argv[2])" jp2/poorrichardalman00fran_jp2/poorrichardalman00fran_$n.jp2 png/$n.png
  [ -f tess/$n.hocr ] || tesseract png/$n.png tess/$n -l eng hocr 2>/dev/null
done
