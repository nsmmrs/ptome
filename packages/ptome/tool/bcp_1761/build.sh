#!/bin/sh
# The Prayer Book made from the spec (gen.py) and built in its look:
# BCP_WORK/build/bcp.pdf (PTOME_FONT_PATH the work's fonts, Baskervville
# until `ptome doctor --look bcp` installs it).
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=${BCP_WORK:-$HOME/.cache/asciidart-work/print-match/bcp}
PTOME=${PTOME:-$HOME/.cache/asciidart-work/print-match/ptome}
SRC=$HERE/../../test/showcase/bcp
python3 -I "$HERE/gen.py"
mkdir -p "$WORK/build"
rsync -a --delete --exclude expected "$SRC/" "$WORK/build/"
OUT=${BCP_PDF:-bcp.pdf}
cd "$WORK/build" && SOURCE_DATE_EPOCH=1767225600 TZ=UTC "$PTOME" -b pdf -o "$OUT" bcp.adoc
pdfinfo "$WORK/build/$OUT" | grep Pages
