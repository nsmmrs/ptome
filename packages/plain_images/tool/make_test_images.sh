#!/usr/bin/env bash
# Makes the GIF and BMP test images in test/images/ with ImageMagick 7
# (`magick`), from generated pictures only (what ImageMagick doesn't
# write, such as RLE4, local color tables and top-down rows, the tests
# make by hand). Run from the package folder;
# the files are committed, so this is needed only to change them.
set -euo pipefail
cd "$(dirname "$0")/.."
g=test/images/gif
b=test/images/bmp
rm -rf "$g" "$b"
mkdir -p "$g" "$b"
src=$(mktemp -d)
trap 'rm -rf "$src"' EXIT
# A picture with many colors, one with few, one with alpha.
magick -size 61x37 gradient:navy-gold -swirl 90 "$src/many.png"
magick -size 23x17 xc:white -fill red -draw 'circle 11,8 11,2' \
  -fill blue -draw 'rectangle 0,0 5,5' "$src/few.png"
magick -size 31x29 xc:none -fill 'rgba(200,40,40,1)' -draw 'circle 15,14 15,2' \
  -fill 'rgba(20,90,200,0.5)' -draw 'rectangle 0,20 30,28' "$src/alpha.png"
# Noise: the LZW table fills up (and the encoder clears it or doesn't).
magick -seed 7 -size 97x89 xc: +noise Random -colors 256 "$src/noise.png"

# GIF.
magick "$src/many.png" -colors 256 "$g/many.gif"
magick "$src/many.png" -colors 256 -interlace GIF "$g/interlaced.gif"
magick "$src/few.png" -colors 4 "$g/few.gif"
magick "$src/few.png" -monochrome "$g/bilevel.gif"
magick "$src/alpha.png" -channel A -threshold 50% +channel "$g/transparent.gif"
magick "$src/noise.png" "$g/noise.gif"
magick "$src/few.png" -colors 4 GIF87:"$g/gif87a.gif"
# An animation whose first frame is smaller than the screen and off its
# corner, then a frame over all of it.
magick -dispose none -delay 10 \
  \( "$src/few.png" -colors 8 -repage 40x30+7+5 \) \
  \( "$src/many.png" -resize 40x30! -colors 64 -repage 40x30+0+0 \) \
  "$g/animated-offset.gif"

# BMP.
magick "$src/many.png" -type truecolor BMP3:"$b/rgb24.bmp"
magick "$src/many.png" -colors 256 -type palette -compress None BMP3:"$b/pal8.bmp"
magick "$src/few.png" -colors 16 -type palette BMP3:"$b/pal4.bmp"
magick "$src/few.png" -monochrome -type bilevel BMP3:"$b/pal1.bmp"
magick "$src/many.png" -colors 200 -type palette -compress RLE BMP3:"$b/rle8.bmp"
magick "$src/many.png" -type truecolor BMP2:"$b/os2-rgb24.bmp"
magick "$src/few.png" -colors 16 -type palette BMP2:"$b/os2-pal4.bmp"
magick "$src/alpha.png" -type truecolormatte BMP:"$b/rgba32-v5.bmp"
magick "$src/many.png" -define bmp:subtype=RGB565 BMP:"$b/rgb565.bmp"
magick "$src/many.png" -define bmp:subtype=RGB555 BMP:"$b/rgb555.bmp"
magick "$src/alpha.png" -define bmp:subtype=ARGB4444 BMP:"$b/argb4444.bmp"
magick "$src/alpha.png" -define bmp:subtype=ARGB1555 BMP:"$b/argb1555.bmp"
ls -l "$g" "$b"
