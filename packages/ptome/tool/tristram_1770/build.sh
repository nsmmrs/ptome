#!/bin/sh
# Tristram Shandy made from the spec (gen.py) and built in its look:
# TRISTRAM_WORK/build/tristram.pdf; the frontispiece cut from the scan as
# test/showcase/tristram/fetch.yml has it (tool/showcase.dart's way).
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=${TRISTRAM_WORK:-$HOME/.cache/asciidart-work/print-match/tristram}
PTOME=${PTOME:-$HOME/.cache/asciidart-work/print-match/ptome}
SRC=$HERE/../../test/showcase/tristram
python3 -I "$HERE/gen.py" > /dev/null
mkdir -p "$WORK/build"
rsync -a --delete --exclude expected "$SRC/" "$WORK/build/"
[ -f "$WORK/n7.jpg" ] || curl -sfL -o "$WORK/n7.jpg" https://archive.org/download/10931855bsb/page/n7.jpg
python3 -I - "$WORK/n7.jpg" "$WORK/build/images/frontispiece.png" <<'PY'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert('L')
im = im.point(lambda v: max(0, min(255, (v - 30) * 255 // 145)))
im.crop((20, 8, 20 + 1120, 8 + 1815)).save(sys.argv[2])
PY
OUT=${TRISTRAM_PDF:-tristram.pdf}
cd "$WORK/build" && SOURCE_DATE_EPOCH=1767225600 TZ=UTC "$PTOME" -b pdf -o "$OUT" tristram.adoc
pdfinfo "$WORK/build/$OUT" | grep Pages
