/// BMP files made by hand (what ImageMagick doesn't write: top-down rows,
/// RLE4, deltas, 2 bits a pixel, alpha in a 32-bit image without masks,
/// masks after a 40-byte header, an embedded PNG), and the ARGB bitmaps
/// ImageMagick decodes wrongly.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:plain_images/plain_images.dart';
import 'package:test/test.dart';

/// A BMP with a 40-byte header: [width] by [height] (negative: top-down),
/// [bits] a pixel, [compression], [palette] (BGRA quads), [masks] after
/// the header, and [pixels] as stored.
Uint8List bmp(
  int width,
  int height,
  int bits,
  List<int> pixels, {
  int compression = 0,
  List<int> palette = const [],
  List<int> masks = const [],
}) {
  final header = ByteData(54 + masks.length * 4)
    ..setUint8(0, 0x42)
    ..setUint8(1, 0x4d)
    ..setUint32(14, 40, Endian.little)
    ..setInt32(18, width, Endian.little)
    ..setInt32(22, height, Endian.little)
    ..setUint16(26, 1, Endian.little)
    ..setUint16(28, bits, Endian.little)
    ..setUint32(30, compression, Endian.little)
    ..setUint32(46, palette.length ~/ 4, Endian.little);
  for (var i = 0; i < masks.length; i++) {
    header.setUint32(54 + 4 * i, masks[i], Endian.little);
  }
  final offset = header.lengthInBytes + palette.length;
  header
    ..setUint32(2, offset + pixels.length, Endian.little)
    ..setUint32(10, offset, Endian.little);
  return Uint8List.fromList([
    ...header.buffer.asUint8List(),
    ...palette,
    ...pixels,
  ]);
}

void main() {
  const quads = [0, 0, 0, 0, 0, 0, 255, 0, 0, 255, 0, 0, 255, 0, 0, 0];

  test('rows bottom to top, or top to bottom with a negative height', () {
    // Two rows of one 24-bit pixel, padded to four bytes: blue, then red.
    const stored = [255, 0, 0, 0, 0, 0, 255, 0];
    expect(ImageFile.read(bmp(1, 2, 24, stored)).decode().samples, [
      255, 0, 0, 0, 0, 255, //
    ]);
    expect(ImageFile.read(bmp(1, -2, 24, stored)).decode().samples, [
      0, 0, 255, 255, 0, 0, //
    ]);
  });

  test('2 bits a pixel', () {
    final raster = ImageFile.read(bmp(4, 1, 2, [0x1b, 0, 0, 0], palette: quads))
        .decode();
    expect(raster.bitDepth, 2);
    expect([for (var x = 0; x < 4; x++) raster.sample(x, 0)], [0, 1, 2, 3]);
    expect(raster.palette!.sublist(0, 12), [
      0,
      0,
      0,
      255,
      0,
      0,
      0,
      255,
      0,
      0,
      0,
      255,
    ]);
  });

  test('RLE4: runs, absolute runs, deltas; what is skipped transparent', () {
    final raster = ImageFile.read(
      bmp(
        6,
        2,
        4,
        [
          // Bottom row: a run of 3 (1 2 1), absolute 0 3 2, end of line.
          3, 0x12, 0, 3, 0x03, 0x20, 0, 0, //
          // Top row: a delta of 2 right, a run of 2 (3 3), end of bitmap.
          0, 2, 2, 0, 2, 0x33, 0, 1,
        ],
        compression: 2,
        palette: quads,
      ),
    ).decode();
    final key = (raster.transparency! as ColorKey).values.single;
    expect(key, 16);
    expect(raster.samples, [
      key, key, 3, 3, key, key, //
      1, 2, 1, 0, 3, 2,
    ]);
  });

  test('32 bits without masks: the fourth byte is alpha unless all 0', () {
    final opaque = ImageFile.read(bmp(2, 1, 32, [1, 2, 3, 0, 4, 5, 6, 0]))
        .decode();
    expect(opaque.transparency, isNull);
    expect(opaque.samples, [3, 2, 1, 6, 5, 4]);
    final alpha = ImageFile.read(bmp(2, 1, 32, [1, 2, 3, 0, 4, 5, 6, 128]))
        .decode();
    expect((alpha.transparency! as AlphaChannel).samples, [0, 128]);
  });

  test('bit field masks after a 40-byte header', () {
    // 16 bits: red 0xf800, green 0x07e0, blue 0x001f (565).
    final raster = ImageFile.read(
      bmp(
        1,
        1,
        16,
        [0x1f, 0xf8, 0, 0],
        compression: 3,
        masks: [0xf800, 0x07e0, 0x001f],
      ),
    ).decode();
    expect(raster.samples, [255, 0, 255]);
  });

  test('an embedded PNG decodes as it', () {
    final png = File('test/images/pngsuite/basn2c08.png').readAsBytesSync();
    final file = ImageFile.read(bmp(32, 32, 0, png, compression: 5));
    expect(file.decode().samples, PngFile.read(png).decode().samples);
  });

  test('ARGB1555 and ARGB4444: alpha bits repeated to fill 8', () {
    Uint8List alphaOf(String name) =>
        (ImageFile.read(File('test/images/bmp/$name.bmp').readAsBytesSync())
                    .decode()
                    .transparency!
                as AlphaChannel)
            .samples;
    expect(alphaOf('argb1555').toSet(), {0, 255});
    // The 50% band is 0x8 in 4 bits: 0x88.
    expect(alphaOf('argb4444').toSet(), containsAll([0, 0x88, 255]));
  });

  test('damage and what is not supported are reported', () {
    expect(
      () => ImageFile.read(bmp(1, 1, 24, const [], compression: 9)),
      throwsA(isA<ImageFormatException>()),
    );
    expect(
      () => ImageFile.read(bmp(0, 1, 24, const [0, 0, 0, 0])),
      throwsA(isA<ImageFormatException>()),
    );
    // Rows cut short: what is there.
    final raster = ImageFile.read(bmp(2, 2, 24, [1, 2, 3])).decode();
    expect(raster.samples.length, 12);
  });
}
