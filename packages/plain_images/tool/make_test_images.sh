#!/usr/bin/env bash
# Makes the GIF, BMP, WebP, JPEG and TIFF test images in test/images/ with
# ImageMagick 7 (`magick`), libwebp's tools (cwebp, img2webp, webpmux,
# dwebp), libjpeg-turbo's (cjpeg, djpeg) and libtiff's (tiffcp,
# tiff2rgba), from generated pictures only (what they don't write, such as
# RLE4, local color tables and top-down rows, the tests make by hand). The
# WebP and JPEG files' expected decoding is dwebp's and djpeg's, recorded
# as the MD5 of their PAM or PNM output in expected.md5 beside them (of an
# animation, its first frame's); a TIFF file compressed without loss
# decodes as the uncompressed one it was made from, a JPEG- or
# WebP-compressed one as tiff2rgba decodes it (the MD5 of its RGBA). Run from the package folder;
# the files are committed, so this is needed only to change them.
set -euo pipefail
cd "$(dirname "$0")/.."
g=test/images/gif
b=test/images/bmp
w=test/images/webp
j=test/images/jpeg-suite
t=test/images/tiff
rm -rf "$g" "$b" "$w" "$j" "$t"
mkdir -p "$g" "$b" "$w" "$j" "$t"
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

# JPEG, by cjpeg: each sampling layout, restarts, progressive, optimized
# tables, arithmetic coding, 12 bits, lossless of several precisions, RGB
# and gray.
magick "$src/many.png" "$src/many.ppm"
magick "$src/noise.png" "$src/noise.ppm"
magick "$src/many.png" -colorspace gray "$src/gray.pgm"
for s in 1x1 2x1 1x2 2x2 4x1 1x4 4x2 2x4 3x1 1x3 3x2; do
  cjpeg -quality 80 -sample "$s" -outfile "$j/sample-$s.jpg" "$src/many.ppm"
done
cjpeg -quality 60 -restart 1 -outfile "$j/restart-rows.jpg" "$src/many.ppm"
cjpeg -quality 60 -restart 3B -sample 2x2 -outfile "$j/restart-blocks.jpg" "$src/noise.ppm"
cjpeg -quality 85 -progressive -sample 2x2 -outfile "$j/progressive.jpg" "$src/noise.ppm"
cjpeg -quality 85 -progressive -restart 2B -outfile "$j/progressive-restart.jpg" "$src/many.ppm"
cjpeg -quality 95 -optimize -outfile "$j/optimized.jpg" "$src/noise.ppm"
cjpeg -quality 70 -arithmetic -outfile "$j/arithmetic.jpg" "$src/noise.ppm"
cjpeg -quality 70 -arithmetic -progressive -sample 2x1 -outfile "$j/arithmetic-progressive.jpg" "$src/many.ppm"
cjpeg -quality 70 -arithmetic -restart 2B -outfile "$j/arithmetic-restart.jpg" "$src/many.ppm"
cjpeg -quality 90 -precision 12 -outfile "$j/precision-12.jpg" "$src/noise.ppm"
cjpeg -quality 90 -precision 12 -progressive -outfile "$j/precision-12-progressive.jpg" "$src/many.ppm"
cjpeg -lossless 1 -outfile "$j/lossless-1.jpg" "$src/many.ppm"
cjpeg -lossless 7,2 -outfile "$j/lossless-7-pt2.jpg" "$src/noise.ppm"
cjpeg -lossless 4 -precision 12 -outfile "$j/lossless-12.jpg" "$src/many.ppm"
cjpeg -lossless 6 -precision 16 -restart 1 -outfile "$j/lossless-16-restart.jpg" "$src/noise.ppm"
cjpeg -lossless 5 -precision 4 -grayscale -outfile "$j/lossless-4-gray.jpg" "$src/gray.pgm"
cjpeg -quality 75 -rgb -outfile "$j/rgb.jpg" "$src/many.ppm"
cjpeg -quality 75 -grayscale -outfile "$j/gray.jpg" "$src/gray.pgm"
(
  cd "$j"
  for f in *.jpg; do
    echo "$(djpeg -pnm "$f" | md5sum | cut -c1-32)  $f"
  done
) > "$j/expected.md5"

# TIFF: uncompressed images of each kind (ImageMagick), then tiffcp's
# compressions and layouts of them.
magick "$src/many.png" -colorspace gray -depth 8 -compress none "$t/gray8.tif"
magick "$src/many.png" -colorspace gray -depth 16 -compress none "$t/gray16.tif"
magick "$src/many.png" -depth 8 -compress none "$t/rgb8.tif"
magick "$src/many.png" -depth 16 -compress none "$t/rgb16.tif"
magick "$src/many.png" -colors 16 -type palette -depth 4 -compress none "$t/pal4.tif"
magick "$src/many.png" -colors 200 -type palette -compress none "$t/pal8.tif"
magick -seed 3 -size 300x41 xc: +noise Random -threshold 50% -type bilevel -depth 1 \
  -compress none "$t/bw.tif"
magick "$src/alpha.png" -depth 8 -compress none "$t/rgba8.tif"
magick "$src/many.png" -colorspace cmyk -depth 8 -compress none "$t/cmyk8.tif"
magick "$src/many.png" -depth 32 -define quantum:format=floating-point \
  -compress none "$t/float32.tif"
magick "$src/many.png" -colorspace gray -alpha set -channel A -fx 'i/w' \
  +channel -depth 8 -compress none "$t/graya8.tif"
variant() { # base name options...
  local base=$1 name=$2
  shift 2
  tiffcp "$@" "$t/$base.tif" "$t/$base-$name.tif"
}
for base in rgb8 gray16 rgba8; do
  variant $base packbits -c packbits
  variant $base lzw -c lzw
  variant $base lzw-predictor -c lzw:2
  variant $base zip-predictor -c zip:2
  variant $base tiles -c lzw -t -w 16 -l 16
  variant $base strips -c zip -s -r 5
  variant $base big-endian -c lzw:2 -B
  variant $base bigtiff -c zip -8
done
variant rgb8 planar -c lzw -p separate
variant rgb8 planar-tiles -c zip -p separate -t -w 16 -l 32
variant rgba8 planar -c lzw:2 -p separate
variant rgb16 zip -c zip:2
variant cmyk8 lzw -c lzw:2
variant pal4 lzw -c lzw
variant pal8 zip -c zip
variant graya8 packbits -c packbits
variant float32 float-predictor -c zip:3
variant float32 float-predictor-lzw -c lzw:3
variant bw packbits -c packbits
variant bw g3 -c g3
variant bw g3-2d -c g3:2d
variant bw g3-fill -c g3:fill
variant bw g3-2d-fill -c g3:2d:fill
variant bw g4 -c g4
variant bw g4-lsb -c g4 -f lsb2msb
variant bw g4-tiles -c g4 -t -w 32 -l 16
variant bw g3-2d-strips -c g3:2d -s -r 7
# Lossy: decoded as tiff2rgba decodes them.
variant rgb8 jpeg -c jpeg:75
variant rgb8 jpeg-tiles -c jpeg:90 -t -w 16 -l 16
variant rgb8 jpeg-rgb -c jpeg:r:75
variant gray8 jpeg -c jpeg
variant rgb8 webp -c webp
# Not read: named.
variant rgb8 lzma -c lzma
variant rgb8 zstd -c zstd
(
  cd "$t"
  for f in *-jpeg*.tif *-webp.tif; do
    tiff2rgba -c none "$f" "$src/rgba.tif"
    echo "$(magick "$src/rgba.tif" -depth 8 rgba:- | md5sum | cut -c1-32)  $f"
  done
) > "$t/expected.md5"
ls -l "$g" "$b" "$w" "$j" "$t"
