#!/bin/sh
# The Folio's text made from the transcription (gen.py) and the work
# built in the Folio's look: TEMPEST_WORK/build/tempest-folio.pdf.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=${TEMPEST_WORK:-$HOME/.cache/asciidart-work/print-match/tempest}
PTOME=${PTOME:-$HOME/.cache/asciidart-work/print-match/ptome}
SRC=$HERE/../../test/showcase/tempest
python3 -I "$HERE/gen.py" >/dev/null
# (The scan's lines, as many as the spec's: scan.py's, when the spec
# changes how many a column has.)
[ "$HERE/folio.spec" -nt "$WORK/scan.json" ] && python3 -I "$HERE/scan.py" >/dev/null 2>&1 || true
mkdir -p "$WORK/build"
rsync -a --exclude expected "$SRC/" "$WORK/build/"
# (The headpiece and the initial cut from the scan, fetch.yml's, staged
# by tool/showcase.dart once.)
if [ ! -f "$WORK/stage/tempest/images/tempest-headpiece.png" ]; then
  (cd "$HERE/../.." && dart run tool/showcase.dart --out "$WORK/stage" tempest >/dev/null) || true
fi
cp "$WORK"/stage/tempest/images/tempest-*.png "$WORK/build/images/"
cd "$WORK/build" && SOURCE_DATE_EPOCH=1767225600 TZ=UTC "$PTOME" -b pdf -a look=folio -o tempest-folio.pdf tempest.adoc
pdfinfo "$WORK/build/tempest-folio.pdf" | grep Pages
