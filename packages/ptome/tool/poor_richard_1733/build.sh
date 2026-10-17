#!/bin/sh
# The months made from the transcription (gen.py) and the work staged
# by tool/showcase.dart (its woodcut fetched and cut) and built to PDF:
# PR_WORK/build/poor-richard.pdf.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=${PR_WORK:-$HOME/.cache/asciidart-work/print-match/poor-richard}
PTOME=${PTOME:-$HOME/.cache/asciidart-work/print-match/ptome}
SRC=$HERE/../../test/showcase/poor-richard
python3 -I "$HERE/gen.py" >/dev/null
mkdir -p "$WORK/build"
if [ ! -f "$WORK/build/images/anatomy.png" ]; then
  (cd "$HERE/../.." && dart run tool/showcase.dart --out "$WORK/stage" poor-richard >/dev/null)
  mkdir -p "$WORK/build/images" && cp "$WORK/stage/poor-richard/images/anatomy.png" "$WORK/build/images/"
fi
rsync -a --exclude expected "$SRC/" "$WORK/build/"
cd "$WORK/build" && SOURCE_DATE_EPOCH=1767225600 TZ=UTC "$PTOME" -b pdf poor-richard.adoc
pdfinfo "$WORK/build/poor-richard.pdf" | grep Pages
