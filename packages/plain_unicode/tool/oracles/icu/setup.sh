#!/usr/bin/env bash
# Builds the ICU oracles, line breaks (icubreak.cc) and case mapping
# (icucase.cc), against the system's ICU
# (its development files, found by pkg-config): the dictionary word breaks
# follow ICU 78.3, so that is the version to compare with. Needs a C++
# compiler.
set -euo pipefail
cd "$(dirname "$0")"
version="$(pkg-config --modversion icu-uc)"
c++ -std=c++17 -O2 -o icubreak icubreak.cc $(pkg-config --cflags --libs icu-uc icu-i18n)
c++ -std=c++17 -O2 -o icucase icucase.cc $(pkg-config --cflags --libs icu-uc icu-i18n)
echo "built $(pwd)/icubreak and icucase against ICU $version"
[ "$version" = 78.3 ] || echo "warning: ICU $version, not 78.3" >&2
