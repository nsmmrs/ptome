#!/bin/sh
# One leaf fitted alone (gen.py's ONLY): its paragraphs' pitches
# (pitch.py) and margins (margins.py), then compared with the scan.
#   ./page.sh LEAF
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE"
export ONLY=$1
python3 -I gen.py && python3 -I pitch.py >/dev/null
python3 -I margins.py 4 "$1" | tail -1
python3 -I compare.py "$1"
