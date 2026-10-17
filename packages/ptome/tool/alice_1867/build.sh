#!/bin/sh
# The work staged with its fetched images (the work cache's
# build/alice/images, tool/showcase.dart's) and built to PDF:
# ALICE_WORK/build/alice/alice.pdf.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=${ALICE_WORK:-$HOME/.cache/asciidart-work/alice-match}
PTOME=${PTOME:-$HOME/.cache/asciidart-work/print-match/ptome}
SRC=$HERE/../../test/showcase/alice
DST=$WORK/build/alice
mkdir -p "$DST/images"
rsync -a --exclude images "$SRC/" "$DST/"
cp "$SRC"/images/* "$DST/images/"
# (The fetched images, tool/showcase.dart's, kept in DST/images.)
cd "$DST" && SOURCE_DATE_EPOCH=1767225600 TZ=UTC "$PTOME" -b pdf alice.adoc
pdfinfo "$DST/alice.pdf" | grep Pages
