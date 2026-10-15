#!/usr/bin/env bash
# Fetches resvg's reference-render tests (an SVG and the PNG resvg draws of
# it, for each case) at a pinned commit, for tool/resvg_suite.dart and for
# recording test/resvg_test.dart's comparisons:
#
#   tool/fetch_resvg_tests.sh [DIR]   (default ~/.cache/asciidart-work/resvg)
#
# then RESVG_TESTS=DIR/repo/crates/resvg/tests/tests (their default).
set -euo pipefail
commit=77b12f4951a7b75d759c42e8c9497cff7c839c3c
dir="${1:-$HOME/.cache/asciidart-work/resvg}"
mkdir -p "$dir"
if [ ! -d "$dir/repo/.git" ]; then
  git clone -q --filter=blob:none --no-checkout https://github.com/linebender/resvg.git "$dir/repo"
fi
cd "$dir/repo"
git sparse-checkout set crates/resvg/tests/tests
git fetch -q origin "$commit"
git checkout -q "$commit"
echo "$dir/repo/crates/resvg/tests/tests"
