#!/usr/bin/env bash
# Fetches libwebp's test data (lossless and lossy files, the VP8
# conformance vectors, and the MD5 of dwebp's output for most of them) at
# a pinned commit, for tool/webp_suite.dart (it has no licence to redistribute
# it, so it is fetched, not committed):
#
#   tool/fetch_webp_tests.sh [DIR]   (default ~/.cache/asciidart-work/libwebp-test-data)
#
# then dart run tool/webp_suite.dart DIR.
set -euo pipefail
commit=06ddd96e276c2c638a72d39d3c0f340afd61978c
dir="${1:-$HOME/.cache/asciidart-work/libwebp-test-data}"
if [ ! -d "$dir/.git" ]; then
  git clone -q --no-checkout https://chromium.googlesource.com/webm/libwebp-test-data "$dir"
fi
cd "$dir"
git fetch -q origin "$commit" 2>/dev/null || true
git checkout -q "$commit"
echo "$dir"
