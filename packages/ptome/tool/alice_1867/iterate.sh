#!/bin/sh
# Looking-Glass drafted, copied into the work, built, and compared with
# the printing: iterate.sh [--pages]
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
W=${ALICE_WORK:-$HOME/.cache/asciidart-work/alice-match}
cd "$HERE"
python3 -I transcribe.py looking-glass --tesseract > "$W/transcribe-looking-glass.log" 2>&1 || { tail -5 "$W/transcribe-looking-glass.log"; exit 1; }
cp "$W"/out/looking-glass/chapter-*.adoc ../../test/showcase/alice/text/looking-glass/
python3 -I leads.py "$W/transcribe-looking-glass.log" ../../test/showcase/alice/alice-look.yml
./build.sh > /dev/null 2>&1
# (Chapter I's page in the PDF: the twelfth after Wonderland's last.)
FIRST=217
python3 -I compare.py looking-glass "$W/build/alice/alice.pdf" "$FIRST" "$@"
