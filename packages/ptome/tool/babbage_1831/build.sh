#!/bin/sh
# The table made (gen.py) and built in the printing's look:
# BABBAGE_WORK/build/babbage.pdf.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=${BABBAGE_WORK:-$HOME/.cache/asciidart-work/print-match/babbage}
PTOME=${PTOME:-$HOME/.cache/asciidart-work/print-match/ptome}
SRC=$HERE/../../test/showcase/babbage
python3 -I "$HERE/gen.py"
mkdir -p "$WORK/build"
rsync -a --delete --exclude expected "$SRC/" "$WORK/build/"
cd "$WORK/build" && SOURCE_DATE_EPOCH=1767225600 TZ=UTC "$PTOME" -b pdf -o babbage.pdf babbage.adoc
pdfinfo "$WORK/build/babbage.pdf" | grep Pages
