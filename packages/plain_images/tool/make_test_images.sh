#!/usr/bin/env bash
# Makes the GIF, BMP and WebP test images in test/images/ with ImageMagick
# 7 (`magick`) and libwebp's tools (cwebp, img2webp, webpmux, dwebp), from
# generated pictures only (what they don't write, such as RLE4, local
# color tables and top-down rows, the tests make by hand). The WebP
# files' expected decoding is dwebp's, recorded as the MD5 of its PAM
# output in test/images/webp/expected.md5 (of an animation, its first
# frame's). Run from the package folder;
# the files are committed, so this is needed only to change them.
set -euo pipefail
cd "$(dirname "$0")/.."
g=test/images/gif
b=test/images/bmp
w=test/images/webp
rm -rf "$g" "$b" "$w"
mkdir -p "$g" "$b" "$w"
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

# WebP.
cwebp -quiet -lossless "$src/many.png" -o "$w/lossless.webp"
cwebp -quiet -lossless -z 9 "$src/alpha.png" -o "$w/lossless-alpha.webp"
cwebp -quiet -q 75 "$src/many.png" -o "$w/lossy.webp"
cwebp -quiet -q 30 -sharp_yuv -segments 4 -sns 80 -f 60 -sharpness 3 \
  "$src/noise.png" -o "$w/lossy-filtered.webp"
cwebp -quiet -q 90 -alpha_filter best "$src/alpha.png" -o "$w/lossy-alpha.webp"
cwebp -quiet -q 90 -alpha_method 0 "$src/alpha.png" -o "$w/lossy-alpha-raw.webp"
magick -size 1x1 xc:teal "$src/one.png"
cwebp -quiet -q 80 "$src/one.png" -o "$w/one-pixel.webp"
# Extended: an ICC profile (made-up bytes: carried, not used) and EXIF
# metadata with orientation 6.
printf 'not really an ICC profile' > "$src/profile.icc"
printf 'MM\0\x2a\0\0\0\x08\0\x01\x01\x12\0\x03\0\0\0\x01\0\x06\0\0\0\0\0\0' > "$src/exif.bin"
webpmux -set icc "$src/profile.icc" "$w/lossy.webp" -o "$src/icc.webp"
webpmux -set exif "$src/exif.bin" "$src/icc.webp" -o "$w/extended.webp"
# An animation whose first frame is smaller than the canvas and off its
# corner (offsets are even).
magick "$src/few.png" -resize 20x14! "$src/f1.png"
magick "$src/many.png" -resize 40x30! "$src/f2.png"
cwebp -quiet -lossless "$src/f1.png" -o "$src/f1.webp"
cwebp -quiet -q 80 "$src/f2.png" -o "$src/f2.webp"
webpmux -frame "$src/f1.webp" +100+6+4 -frame "$src/f2.webp" +100+0+0 \
  -loop 0 -o "$w/animated.webp"
# The expected decoding: dwebp's (an animation's first frame alone).
(
  cd "$w"
  for f in *.webp; do
    if [ "$f" = animated.webp ]; then
      webpmux -get frame 1 "$f" -o "$src/first.webp"
      echo "$(dwebp -quiet "$src/first.webp" -pam -o - | md5sum | cut -c1-32)  $f"
    else
      echo "$(dwebp -quiet "$f" -pam -o - | md5sum | cut -c1-32)  $f"
    fi
  done
) > "$w/expected.md5"
ls -l "$g" "$b" "$w"
