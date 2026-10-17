#!/bin/sh
# The work folder (TRIBUNE_WORK): the Library of Congress's full-size
# scans of the New-York Tribune of 16 April 1912, its first two pages
# (Chronicling America, reel 00206531526, images 0303 and 0304), and
# their OCR (ALTO), each checked against its SHA-256 (scans.sha256);
# then the OCR's lines (alto.py), each region's lines (lines.py, by
# regions.txt) and Tesseract's reading of each line (tess.py).
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=${TRIBUNE_WORK:-$HOME/.cache/asciidart-work/print-match/tribune}
IIIF=https://tile.loc.gov/image-services/iiif/service:ndnp:dlc:batch_dlc_keady_ver01:data:sn83030214:00206531526:1912041601
CA=https://chroniclingamerica.loc.gov/lccn/sn83030214/1912-04-16/ed-1
mkdir -p "$WORK"
cd "$WORK"
[ -f 0303.jpg ] || curl -sfL -o 0303.jpg "$IIIF:0303/full/full/0/default.jpg"
[ -f 0304.jpg ] || curl -sfL -o 0304.jpg "$IIIF:0304/full/full/0/default.jpg"
[ -f seq1.xml ] || curl -sfL -o seq1.xml "$CA/seq-1/ocr.xml"
[ -f seq2.xml ] || curl -sfL -o seq2.xml "$CA/seq-2/ocr.xml"
sha256sum -c --quiet "$HERE/scans.sha256"
python3 -I "$HERE/alto.py"
python3 -I "$HERE/lines.py"
python3 -I "$HERE/tess.py"
