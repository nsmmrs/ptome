#!/bin/sh
# The Tribune made from the regions' specs (gen.py) and built in its look:
# TRIBUNE_WORK/build/tribune.pdf, the cuts cut from the scan into the
# build's images.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=${TRIBUNE_WORK:-$HOME/.cache/asciidart-work/print-match/tribune}
PTOME=${PTOME:-$HOME/.cache/asciidart-work/print-match/ptome}
SRC=$HERE/../../test/showcase/tribune
python3 -I "$HERE/gen.py"
mkdir -p "$WORK/build"
rsync -a --delete --exclude expected "$SRC/" "$WORK/build/"
python3 -I "$HERE/cuts.py" "$WORK/build/images"
cd "$WORK/build" && SOURCE_DATE_EPOCH=1767225600 TZ=UTC "$PTOME" -b pdf -o tribune.pdf tribune.adoc
pdfinfo "$WORK/build/tribune.pdf" | grep Pages
