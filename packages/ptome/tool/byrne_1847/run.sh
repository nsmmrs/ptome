#!/bin/sh
# The leaves given (all of Book I, 35-84, if none) traced, the work
# generated into the showcase's folder, built, and its pages compared with
# the scans: rev/cmp-LEAF.png (the scan, the page, their blend) and
# rev/cmpc-LEAF.png (in colour), and each page's lines checked as set.
#
#   tool/byrne_1847/run.sh [LEAF...]
#
# BYRNE_WORK the work folder (~/.cache/asciidart-work/print-match), PYTHON
# its Python (BYRNE_WORK/venv/bin/python), PTOME a ptome executable
# (BYRNE_WORK/ptome); NOTRACE=1 leaves the pictures as traced.
set -e
export PYTHONDONTWRITEBYTECODE=1
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=${BYRNE_WORK:-$HOME/.cache/asciidart-work/print-match}
PY=${PYTHON:-$WORK/venv/bin/python}
PTOME=${PTOME:-$WORK/ptome}
OUT=$HERE/../../test/showcase/byrne
BUILD=$WORK/byrne/build
[ $# -gt 0 ] || set -- $(seq 35 84)
mkdir -p "$BUILD" "$WORK/byrne/rev"
quiet() { grep -v 'RuntimeWarning' || true; }
# (Every page up to the last asked for set, so each has its number.)
LAST=$(printf '%s\n' "$@" | sort -n | tail -1)
[ -n "$NOTRACE" ] || $PY -I "$HERE/trace.py" "$WORK/byrne/svg" \
  $( (printf '%s\n' "$@"; $PY -I "$HERE/stale.py" 2>/dev/null) | sort -u) 2>&1 | quiet | tr '\n' ' '
echo
$PY -I "$HERE/gen.py" "$OUT" $(seq 35 "$LAST") 2>&1 | quiet
SOURCE_DATE_EPOCH=1767225600 TZ=UTC "$PTOME" -b pdf -o "$BUILD/byrne.pdf" "$OUT/byrne.adoc"
rm -f "$BUILD"/pg-*.png
pdftoppm -r 100 -png "$BUILD/byrne.pdf" "$BUILD/pg"
for leaf in "$@"; do
  f=$(ls "$BUILD"/pg-*.png | sort -V | sed -n "$((leaf - 34))p")
  $PY -I "$HERE/compare.py" "$f" "$leaf" "$WORK/byrne/rev/cmp-$leaf.png" 2>&1 | quiet
done
$PY -I "$HERE/check.py" "$BUILD/byrne.pdf" "$WORK/byrne/expect.json" 2>&1 | quiet
