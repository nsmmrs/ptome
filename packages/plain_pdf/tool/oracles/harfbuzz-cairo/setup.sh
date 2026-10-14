#!/usr/bin/env bash
# Builds the rendering oracle (render.cc) against a HarfBuzz source
# checkout (HARFBUZZ_SRC, by default ~/.cache/asciidart-work/harfbuzz, at
# 14.6.0) with its cairo glue, and the system's cairo (1.18: the color
# glyph functions). Needs a C++ compiler and cairo's development files.
#
# hb-cairo-utils.cc is built with one line fixed: it reads a PNG's height
# as its width (`height = cairo_image_surface_get_width`), so a bitmap
# glyph that isn't square (Noto Color Emoji's, 136 by 128) is drawn
# squashed into its extents.
set -euo pipefail
cd "$(dirname "$0")"
src="${HARFBUZZ_SRC:-$HOME/.cache/asciidart-work/harfbuzz}"
fixed="$(mktemp -d)"
trap 'rm -r "${fixed:?}"' EXIT
sed 's/height = cairo_image_surface_get_width (surface);/height = cairo_image_surface_get_height (surface);/' \
  "$src/src/hb-cairo-utils.cc" > "$fixed/hb-cairo-utils.cc"
grep -q 'height = cairo_image_surface_get_height' "$fixed/hb-cairo-utils.cc"
c++ -std=c++17 -O2 -DHAVE_CAIRO -DHAVE_CAIRO_USER_FONT_FACE_SET_RENDER_COLOR_GLYPH_FUNC \
  -DHAVE_CAIRO_FONT_OPTIONS_GET_CUSTOM_PALETTE_COLOR \
  -DHAVE_CAIRO_USER_SCALED_FONT_GET_FOREGROUND_SOURCE \
  -I"$src/src" $(pkg-config --cflags cairo) \
  -o hb-render render.cc "$src/src/harfbuzz.cc" "$src/src/hb-cairo.cc" \
  "$fixed/hb-cairo-utils.cc" $(pkg-config --libs cairo) -lpthread
echo "built $(pwd)/hb-render against $(git -C "$src" describe --tags 2>/dev/null || echo "$src")"
