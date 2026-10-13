/// Every test image decoded and compared with ImageMagick's decoding of
/// it, both composited on white: PngSuite, the GIF and BMP images
/// `tool/make_test_images.sh` makes, bmpsuite's good BMP files, and the
/// valid GIF files of imazen's GIF conformance suite.
/// Skipped without ImageMagick.
@Tags(['tools'])
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:plain_images/plain_images.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  final magick = magickCommand();
  for (final (folder, extension) in [
    ('pngsuite', '.png'),
    ('gif', '.gif'),
    ('bmp', '.bmp'),
    ('bmpsuite/g', '.bmp'),
    ('gif-conformance/valid', '.gif'),
    ('gif-conformance/edge-cases', '.gif'),
  ]) {
    group(folder, () {
      for (final file in testImages(folder, extension)) {
        final name = file.uri.pathSegments.last;
        // PngSuite's x*.png files are damaged on purpose; ImageMagick
        // expands 1- and 4-bit alpha wrongly (to 128, and by 16 rather
        // than 17), so the ARGB1555 and ARGB4444 bitmaps are checked in
        // bmp_test.dart instead.
        if (folder == 'pngsuite' && name.startsWith('x')) continue;
        if (name.startsWith('argb')) continue;
        test('$name decodes as ImageMagick decodes it', () {
          final raster = ImageFile.read(file.readAsBytesSync()).decode();
          final (mean, max) = difference(
            onWhite(raster.width, raster.height, raster.toRgba8()),
            magickOnWhite(magick!, file.path),
          );
          expect(mean, lessThan(0.5), reason: 'mean difference');
          expect(max, lessThanOrEqualTo(2), reason: 'largest difference');
        }, skip: magick == null ? 'needs ImageMagick' : false);
      }
    });
  }

  test("the GIF conformance suite's invalid files", () {
    Uint8List read(String name) =>
        File('test/images/gif-conformance/invalid/$name').readAsBytesSync();
    for (final name in [
      'bad_magic.gif',
      'truncated_header.gif',
      'empty.gif',
      'zero_dimensions.gif',
    ]) {
      expect(
        () => ImageFile.read(read(name)).decode(),
        throwsA(isA<ImageFormatException>()),
        reason: name,
      );
    }
    // Read as far as they go.
    for (final name in [
      'truncated_lzw.gif',
      'bad_lzw_code.gif',
      'no_trailer.gif',
    ]) {
      expect(ImageFile.read(read(name)).decode().toRgba8(), isNotEmpty);
    }
  });

  test('damaged PngSuite files are rejected', () {
    for (final file in testImages('pngsuite', '.png')) {
      final name = file.uri.pathSegments.last;
      if (!name.startsWith('x')) continue;
      expect(
        () => ImageFile.read(file.readAsBytesSync()).decode(),
        throwsA(isA<ImageFormatException>()),
        reason: name,
      );
    }
  });
}

/// The width, height and RGB samples of [rgba] composited on white.
(int, int, Uint8List) onWhite(int width, int height, Uint8List rgba) {
  final out = Uint8List(width * height * 3);
  for (var p = 0; p < width * height; p++) {
    final a = rgba[4 * p + 3];
    for (var c = 0; c < 3; c++) {
      out[3 * p + c] = (rgba[4 * p + c] * a + 255 * (255 - a) + 127) ~/ 255;
    }
  }
  return (width, height, out);
}
