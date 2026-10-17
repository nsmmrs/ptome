#!/bin/sh
# One page fitted alone: built without the pages before it (gen.py's
# ONLY), its paragraphs' margins fitted (margins.py), compared with the
# scan (compare.py) and its lines the PDF sets on two listed (wraps.py).
#   ./page.sh PAGE
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE"
export ONLY=$1
python3 -I gen.py && python3 -I pitch.py >/dev/null
python3 -I margins.py 6 "$1" | tail -1
python3 -I compare.py "$1"
python3 -I wraps.py "$1"
