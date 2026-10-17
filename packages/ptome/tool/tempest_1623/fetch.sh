#!/bin/sh
# The work folder (TEMPEST_WORK): the Text Creation Partnership's
# transcription of the First Folio (EEBO-TCP A11954, CC0) at its last
# commit, the Boston Public Library copy's JPEG 2000 scans of the play's
# nineteen pages (leaves 25 to 43) from the Internet Archive, each
# checked against its SHA-256 (scans.sha256), drawn as PNG (Pillow); the
# columns cut and read by Tesseract (columns.py).
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=${TEMPEST_WORK:-$HOME/.cache/asciidart-work/print-match/tempest}
ITEM=https://archive.org/download/mrvvilliamshakes00shak
mkdir -p "$WORK/jp2" "$WORK/png"
cd "$WORK"
[ -f A11954.xml ] || curl -sfL -O https://raw.githubusercontent.com/textcreationpartnership/A11954/4a2977d77fcb9c2d07f43776e1a8bb092c3ea2c2/A11954.xml
echo "77d50ab149976a6b0ccf2edfa8ec157a3894f62e44214f6072d1019968d110b1  A11954.xml" | sha256sum -c
for n in $(seq 25 43); do
  f=$(printf %04d "$n")
  [ -f "jp2/$f.jp2" ] || curl -sfL -o "jp2/$f.jp2" "$ITEM/mrvvilliamshakes00shak_jp2.zip/mrvvilliamshakes00shak_jp2%2Fmrvvilliamshakes00shak_$f.jp2"
done
(cd jp2 && sha256sum -c "$HERE/scans.sha256")
for n in $(seq 25 43); do
  f=$(printf %04d "$n")
  [ -f "png/$f.png" ] || python3 -I -c "import sys; from PIL import Image; Image.open(sys.argv[1]).convert('L').save(sys.argv[2])" "jp2/$f.jp2" "png/$f.png"
done
python3 -I "$HERE/columns.py"
