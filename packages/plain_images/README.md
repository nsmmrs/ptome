# plain_images

Raster image files read in pure Dart: PNG, JPEG, GIF and BMP, decoded to
typed samples with their palette, transparency, ICC profile and
orientation.

```dart
import 'package:plain_images/plain_images.dart';

final file = ImageFile.read(bytes); // PngFile, JpegFile, GifFile, BmpFile
print('${file.format.label} ${file.width} x ${file.height}');
final raster = file.decode();
switch (raster.transparency) {
  case AlphaChannel(:final samples, :final bitDepth):
    print('alpha, $bitDepth bits');
  case ColorKey(:final values):
    print('transparent where the samples are $values');
  case null:
    print('opaque');
}
final rgba = raster.toRgba8();
```

- `ImageFile.read` tells the format by the file's signature and reads its
  header only; `decode` reads the samples. A format it recognizes but
  doesn't read (AVIF, HEIC, JPEG XL, ...) is named in the
  `ImageFormatException`, whose `unsupportedFormat` says which.
- A `Raster` keeps the samples as the file has them where it can: a
  palette stays a palette (`ColorModel.indexed`), 1-, 2- and 4-bit samples
  stay packed, 16-bit samples stay 16-bit, alpha is a separate plane, a
  single transparent color is a `ColorKey`. That is what a PDF image
  needs (plain_pdf writes it without converting it), and `toRgba8` gives
  8-bit RGBA when that is what is wanted.
- PNG: every color type and bit depth, interlacing, `tRNS`, `iCCP` and
  `eXIf`. GIF: the first frame on the logical screen, transparent where
  it has no pixels. BMP: every Windows and OS/2 header, 1 to 32 bits a
  pixel, bit fields, RLE4 and RLE8. JPEG: the header (size, components,
  precision, progressive, Adobe and EXIF segments).

Tested against ImageMagick (PngSuite and generated GIF and BMP files),
against package:image on seeded random files, and with damaged files;
the same results compiled to JavaScript as on the Dart VM.

[plain_pdf](https://github.com/nsmmrs/ptome/tree/master/packages/plain_pdf)
embeds any image plain_images reads. The library lives in the
[ptome](https://github.com/nsmmrs/ptome) workspace.

Status: in development; not published to pub.dev.

## License

MIT; see [LICENSE](LICENSE). The PngSuite test images are Willem van
Schaik's, under their own terms (`test/images/pngsuite/PngSuite.LICENSE`).
