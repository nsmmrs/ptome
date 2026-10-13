# Changelog

## 0.1.0-dev (unreleased)

- `ImageFile.read` tells PNG, JPEG, GIF, BMP and WebP files by their
  signatures and reads their headers (`PngFile`, `JpegFile`, `GifFile`,
  `BmpFile`, `WebPFile`); a format it recognizes but doesn't read (AVIF,
  HEIC, JPEG XL, TIFF, ...) is named in the `ImageFormatException`.
- `decode` gives a `Raster`: packed samples (gray, RGB, CMYK or palette
  indices, 1 to 16 bits), transparency apart (an `AlphaChannel` or a
  `ColorKey`), the ICC profile and the EXIF orientation; `toRgba8` for
  8-bit RGBA. At most `ImageFile.maxPixels` pixels.
- PNG (moved from plain_pdf with its history): every color type, bit
  depth and Adam7 interlacing, `tRNS`, `iCCP`, `eXIf`; PngSuite decodes
  as ImageMagick decodes it, and to the same samples as in plain_pdf.
- GIF 87a and 89a: the first frame on the logical screen (later frames
  of an animation counted, not read), local and global color tables,
  interlacing, the transparent index; LZW with a full table kept until
  the next clear code. Damaged data decodes as far as it goes.
- BMP: OS/2 1.x and 2.x and Windows version 1 to 5 headers; 1, 2, 4, 8,
  16, 24 and 32 bits a pixel; bit field masks (alpha too, low bit counts
  expanded by repeating them as browsers do); RLE8 and RLE4 (pixels
  they skip transparent); top-down rows; embedded ICC profiles and PNG
  images.
- WebP (RFC 9649): lossless (VP8L: every transform, color caches, meta
  prefix codes) and lossy (VP8 key frames, RFC 6386: segments, both loop
  filters, every intra mode; its tables generated from the RFC's text),
  lossy alpha (raw or lossless-compressed, each filter), the extended
  format's ICC profile and EXIF orientation, and an animation's first
  frame on its canvas. Decoded to the byte as libwebp's dwebp decodes
  (its YUV to RGB conversion and "fancy" chroma upsampling): all 131
  files of libwebp's test data (the VP8 conformance vectors among them;
  `tool/fetch_webp_tests.sh`), and seeded random images through cwebp
  with random settings.
- JPEG decoding (ITU-T T.81): baseline, extended 12-bit, progressive
  and lossless, Huffman or arithmetic coded, restart intervals, any
  sampling factors, gray, YCbCr, RGB, CMYK and YCCK (an Adobe file's
  inverted CMYK turned back), multi-segment ICC profiles. The samples are
  libjpeg-turbo's default decoding to the byte (its accurate integer
  inverse DCT, "fancy" upsampling and YCbCr to RGB tables): test images
  of each layout, coding and precision made by cjpeg, and seeded random
  images through cjpeg with random settings, against djpeg. 12-bit and
  lossless samples fill 16 bits. A BMP holding a JPEG decodes as it.
- Checked against ImageMagick on the test images, against package:image
  (a dev dependency only) on 650 seeded random PNG, GIF and BMP files,
  and with damaged copies of every test image (nightly). Decoding is
  1.3 to 3.8 times as fast as package:image's on page-sized images, WebP
  1.35 (lossless) to 2 (lossy with alpha) times, JPEG 1.3 to 1.5 times
  (`benchmark/decode.dart`).
- The same samples compiled to JavaScript as on the Dart VM.
