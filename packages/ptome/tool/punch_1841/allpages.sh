#!/bin/sh
# Every page of text fitted alone (page.sh), its summary kept:
# PUNCH_WORK/status.txt.
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=${PUNCH_WORK:-$HOME/.cache/asciidart-work/print-match/punch}
: > "$WORK/status.txt"
for p in 1 2 4 5 6 7 9 10 11 12 49 50 51 52 53 54 55 57 58 59 60 61 62 63 64 65 66 67 69 70 71 72; do
  echo "== $p" >> "$WORK/status.txt"
  "$HERE/page.sh" $p 2>&1 | grep -v "^round" | head -8 >> "$WORK/status.txt"
done
