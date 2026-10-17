#!/bin/sh
# The table made and fitted, in order: the pages written and built
# (gen.py, build.sh), the differences' column fitted to the rows
# diff.spec gives (diffit.py), each page's rows and figures compared with
# the scan (compare.py).
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE"
python3 -I diffit.py 2 | tail -1
python3 -I compare.py
