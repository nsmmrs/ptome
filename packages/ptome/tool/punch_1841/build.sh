#!/bin/sh
# The issues made from the spec (gen.py) and built in the volume's look:
# PUNCH_WORK/build/punch.pdf.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=${PUNCH_WORK:-$HOME/.cache/asciidart-work/print-match/punch}
PTOME=${PTOME:-$HOME/.cache/asciidart-work/print-match/ptome}
SRC=$HERE/../../test/showcase/punch
python3 -I "$HERE/gen.py"
mkdir -p "$WORK/build"
rsync -a --exclude expected "$SRC/" "$WORK/build/"
# (The cuts, fetch.yml's, staged by tool/showcase.dart once.)
if [ ! -d "$WORK/stage/punch/images" ]; then
  (cd "$HERE/../.." && dart run tool/showcase.dart --out "$WORK/stage" punch >/dev/null) || true
fi
mkdir -p "$WORK/build/images"
cp "$WORK"/stage/punch/images/* "$WORK/build/images/" 2>/dev/null || true
OUT=${PUNCH_PDF:-punch.pdf}
cd "$WORK/build" && SOURCE_DATE_EPOCH=1767225600 TZ=UTC "$PTOME" -b pdf -o "$OUT" punch.adoc
pdfinfo "$WORK/build/$OUT" | grep Pages
