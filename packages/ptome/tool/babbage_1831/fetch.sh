#!/bin/sh
# The work folder (BABBAGE_WORK): the Internet Archive's page images of
# Oxford's copy of the 1831 printing (Google's scan), the table's pages 6
# to 25 (n30 to n49), each checked against its SHA-256 (scans.sha256);
# then each page's frame found and the page turned upright (frame.py).
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=${BABBAGE_WORK:-$HOME/.cache/asciidart-work/print-match/babbage}
mkdir -p "$WORK/jpg"
cd "$WORK/jpg"
for n in $(seq 30 49); do
  [ -f "n$n.jpg" ] || curl -sfL -o "n$n.jpg" "https://archive.org/download/tablelogarithms00babbgoog/page/n$n.jpg"
done
sha256sum -c "$HERE/scans.sha256"
python3 -I "$HERE/frame.py"
