#!/usr/bin/env bash
# Fetches libtiff's test images (test/images: each photometric, bit depth
# and compression, fax, old-style LZW, tiles) at a pinned commit, for
# test/tiff_test.dart:
#
#   tool/fetch_tiff_tests.sh [DIR]   (default ~/.cache/asciidart-work/libtiff)
#
# then TIFF_TESTS=DIR/test/images (the test's default).
set -euo pipefail
commit=9dff73bebc5661f2dace6f16e14cf9e857172f4e
dir="${1:-$HOME/.cache/asciidart-work/libtiff}"
if [ ! -d "$dir/.git" ]; then
  git clone -q --filter=blob:none --no-checkout https://gitlab.com/libtiff/libtiff.git "$dir"
fi
cd "$dir"
git sparse-checkout set test/images
git fetch -q origin "$commit" 2>/dev/null || true
git checkout -q "$commit"
echo "$dir/test/images"
