# Changelog

## 0.1.0-dev (unreleased)

- `ImageFile.read` tells PNG, JPEG, GIF, BMP, WebP and TIFF files by
  their signatures and reads their headers (`PngFile`, `JpegFile`,
  `GifFile`, `BmpFile`, `WebPFile`, `TiffFile`); a format it recognizes
  but doesn't read (AVIF, HEIC, JPEG XL, JPEG 2000, ...) is named in the
  `ImageFormatException`.
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
- TIFF 6.0 and BigTIFF, the first page: strips and tiles, chunky and
  planar samples, either byte order, fill order; bilevel, gray, palette,
  RGB, CMYK, YCbCr (subsampled, through libtiff's conversion) and CIE
  L*a*b* images of 1 to 16 bits a sample, 32-bit integer and 16-, 24-,
  32- and 64-bit floating-point samples (scaled to 16 bits), alpha
  (associated alpha divided out); PackBits, LZW (and old-style LZW),
  Deflate, CCITT RLE, Group 3 (1-D and 2-D) and Group 4 (decoded as
  libtiff decodes them, zero-length runs and all), JPEG (with JPEGTables)
  and WebP compression; the horizontal and floating-point predictors.
  LZMA, Zstandard, old-style JPEG, JPEG 2000, JBIG and LogLuv are named,
  not read. Checked: tiffcp's compressions and layouts of images of each
  kind decode as the uncompressed images, those as ImageMagick decodes
  them, JPEG- and WebP-compressed ones and libtiff's test images as
  tiff2rgba does.
- The OS/2 bitmaps' Huffman compression (T.4's one-dimensional code)
  decodes, with the TIFF fax decoder.
- Checked against ImageMagick on the test images, against package:image
  (a dev dependency only) on 650 seeded random PNG, GIF and BMP files,
  and with damaged copies of every test image (nightly). Decoding is
  1.3 to 3.8 times as fast as package:image's on page-sized images, WebP
  1.35 (lossless) to 2 (lossy with alpha) times, JPEG 1.3 to 1.5 times
  (`benchmark/decode.dart`).
- The same samples compiled to JavaScript as on the Dart VM.
