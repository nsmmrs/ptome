# Test images

- `pngsuite/`: PngSuite (2017-07-19) by Willem van Schaik, the PNG
  conformance suite: every color type, bit depth, interlacing, palettes,
  transparency, ancillary chunks and damaged files (`x*.png`). Its terms
  are in `pngsuite/PngSuite.LICENSE` ("Permission to use, copy, modify and
  distribute these images for any purpose and without fee is hereby
  granted"); http://www.schaik.com/pngsuite/.
- `jpeg/`: made for these tests with ImageMagick 7 from a generated
  gradient (`magick -size 48x32 gradient:red-blue ...`): gray, baseline
  and progressive RGB, 4:2:0 chroma subsampling, CMYK (with an Adobe
  segment), and `exif-orientation-6.jpg`, the baseline file with an EXIF
  segment (orientation 6) inserted after the start-of-image marker.
- `gif/` and `bmp/`: made by `tool/make_test_images.sh` with ImageMagick 7
  from generated pictures: GIF with many and few colors, interlaced,
  transparent, 87a, a full LZW table (noise), and an animation whose
  first frame is off the screen's corner; BMP of 1, 4, 8, 16 (555, 565,
  ARGB1555, ARGB4444), 24 and 32 bits, RLE8, and OS/2 bitmaps.
- `bmpsuite/`: BMP Suite 2.8 by Jason Summers
  (https://entropymine.com/jason/bmpsuite/): its good (`g/`),
  questionable (`q/`) and bad (`b/`) files, which its `readme.txt` puts in
  the public domain (but for embedded ICC profiles: the files with them,
  `*prof*.bmp`, are left out), and the reference images its page shows
  for them (`ref/`, mapped in `references.txt`).
- `gif-conformance/`: imazen's GIF conformance suite
  (https://github.com/imazen/codec-corpus, `gif-conformance/` at
  ac980c29), generated test data its README puts in the public domain
  (CC0): valid files, edge cases and invalid files.
- `webp/`: made by `tool/make_test_images.sh` with libwebp's tools from
  the same generated pictures: lossless (with and without alpha), lossy
  (with segments and the filter, with alpha raw and compressed, one
  pixel), an extended file with an ICC profile and EXIF orientation, and
  an animation whose first frame is off the canvas's corner;
  `expected.md5` holds dwebp's decoding of each (an animation's first
  frame's).
