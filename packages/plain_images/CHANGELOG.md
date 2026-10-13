# Changelog

## 0.1.0-dev (unreleased)

- `ImageFile.read` tells PNG, JPEG, GIF and BMP files by their
  signatures and reads their headers (`PngFile`, `JpegFile`, `GifFile`,
  `BmpFile`); a format it recognizes but doesn't read (AVIF, HEIC, JPEG
  XL, WebP, TIFF, ...) is named in the `ImageFormatException`.
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
- Checked against ImageMagick on the test images, against package:image
  (a dev dependency only) on 650 seeded random PNG, GIF and BMP files,
  and with damaged copies of every test image (nightly). Decoding is
  1.3 to 3.8 times as fast as package:image's on page-sized images
  (`benchmark/decode.dart`).
- The same samples compiled to JavaScript as on the Dart VM.
