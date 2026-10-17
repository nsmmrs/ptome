#!/bin/sh
# The text made from the transcription (gen.py) and the work built to
# PDF: JOHNSON_WORK/build/johnson.pdf.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=${JOHNSON_WORK:-$HOME/.cache/asciidart-work/print-match/johnson}
PTOME=${PTOME:-$HOME/.cache/asciidart-work/print-match/ptome}
SRC=$HERE/../../test/showcase/johnson
DST=$WORK/build
python3 -I "$HERE/gen.py" >/dev/null
mkdir -p "$DST"
rsync -a --delete --exclude expected "$SRC/" "$DST/"
cd "$DST" && SOURCE_DATE_EPOCH=1767225600 TZ=UTC "$PTOME" -b pdf johnson.adoc
pdfinfo "$DST/johnson.pdf" | grep Pages
