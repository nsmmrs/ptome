#!/bin/sh
# The work folder (BCP_WORK): the Internet Archive's scan of the
# Bayerische Staatsbibliothek's Book of Common Prayer (Cambridge: John
# Baskerville, 1761; 10904662bsb), its JPEG 2000 leaves of the parts the
# work sets (common.py's PARTS: the Calendar, Morning Prayer, the Litany,
# the Psalter), each checked against its SHA-256 (scans.sha256); then the
# leaves turned upright and measured (geometry.py), read by Tesseract
# (ocr.py, its English model; tess.json) and the Calendar's rules
# measured (calgeo.py).
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=${BCP_WORK:-$HOME/.cache/asciidart-work/print-match/bcp}
ITEM=https://archive.org/download/10904662bsb
mkdir -p "$WORK/jp2" "$WORK/tess"
cd "$WORK"
for f in $(cut -c67- "$HERE/scans.sha256"); do
  [ -f "jp2/$f" ] || curl -sfL -o "jp2/$f" "$ITEM/10904662bsb_jp2.zip/10904662bsb_jp2%2F10904662bsb_$f"
done
(cd jp2 && sha256sum -c --quiet "$HERE/scans.sha256")
python3 -I "$HERE/geometry.py"
[ -f tess.json ] || python3 -I "$HERE/ocr.py"
python3 -I "$HERE/calgeo.py" > /dev/null
