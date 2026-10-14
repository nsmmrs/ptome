#!/usr/bin/env bash
# Builds the native oracle (oracle.cc) against a HarfBuzz source checkout
# (HARFBUZZ_SRC, by default ~/.cache/asciidart-work/harfbuzz, at the tag
# the shaper follows, 14.6.0): HarfBuzz compiled in full from its
# amalgamated source. Needs a C++ compiler.
set -euo pipefail
cd "$(dirname "$0")"
src="${HARFBUZZ_SRC:-$HOME/.cache/asciidart-work/harfbuzz}"
c++ -std=c++17 -O2 -I"$src/src" -o hb-oracle oracle.cc "$src/src/harfbuzz.cc" -lpthread
echo "built $(pwd)/hb-oracle against $(git -C "$src" describe --tags 2>/dev/null || echo "$src")"
