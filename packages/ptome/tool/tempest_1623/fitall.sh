#!/bin/sh
# The Folio's text fitted to the scan, in order: the spec made (fixes.py,
# from align.py's draft and fixes.txt), the scan's lines found
# (scan.py), each column's pitch (pitch.py), the lines too wide set
# closer (tight.py), the first page's head and the last page's foot
# placed (headfit.py), each paragraph's margin (margins.py), the
# paragraphs split where the warped paper's lines drift (splits.py), the
# lines set in (indents.py), the rules over and under the acts' and the
# scenes' heads placed (headrules.py), and the margins again.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE"
python3 -I fixes.py
python3 -I gen.py >/dev/null
python3 -I scan.py >/dev/null 2>&1
python3 -I pitch.py >/dev/null
python3 -I tight.py 6 | tail -1
python3 -I headfit.py | tail -1
python3 -I margins.py | tail -1
python3 -I margins.py | tail -1
python3 -I splits.py 3 | tail -1
python3 -I indents.py 2 | tail -1
python3 -I headfit.py | tail -1
python3 -I headrules.py 2 | tail -1
python3 -I margins.py | tail -1
python3 -I compare.py | tail -20
