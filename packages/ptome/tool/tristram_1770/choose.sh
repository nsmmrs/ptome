#!/bin/sh
# Each leaf's reading (choice.json): decide.py run on ABBYY's OCR and on
# Tesseract's, each page the one fewer of whose lines are flagged (or
# missing).
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=${TRISTRAM_WORK:-$HOME/.cache/asciidart-work/print-match/tristram}
# (Chosen once: the review's lines (fixes.tsv, by their places) kept in
# their places; CHOOSE=1 to choose again.)
if [ ! -f "$WORK/choice.json" ] || [ -n "$CHOOSE" ]; then
OCR=abbyy DRAFT=draft-abbyy.json python3 -I "$HERE/decide.py"
OCR=tess DRAFT=draft-tess.json python3 -I "$HERE/decide.py"
python3 -I - "$WORK" <<'PY'
import json, os, sys
w = sys.argv[1]
a = json.load(open(os.path.join(w, 'draft-abbyy.json')))
t = json.load(open(os.path.join(w, 'draft-tess.json')))
# (A reading short of the other's lines (a page it could not read) the
# worse by each.)
bad = lambda p, o: sum(l['flag'] for l in p['lines']) + sum(l['text'].count('⟦') for l in p['lines']) * 0.5 \
    + 2 * max(0, len(o['lines']) - len(p['lines']) - 1)
choice = {str(a[p]['leaf']): ('tess' if bad(t[p], a[p]) < bad(a[p], t[p]) else 'abbyy') for p in a}
json.dump(choice, open(os.path.join(w, 'choice.json'), 'w'))
print(sum(v == 'tess' for v in choice.values()), 'leaves from Tesseract')
PY
fi
python3 -I "$HERE/decide.py"
python3 -I "$HERE/confirm.py"
python3 -I "$HERE/lineread.py"
python3 -I "$HERE/quotes.py"
