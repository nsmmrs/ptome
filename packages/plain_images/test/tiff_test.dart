/// TIFF: every file `tool/make_test_images.sh` made by tiffcp without
/// loss decodes as the uncompressed one it was made from (PackBits, LZW,
/// Deflate, the predictors, CCITT Group 3 and 4, tiles, strips, planar,
/// big-endian, BigTIFF, fill order); JPEG- and WebP-compressed ones as
/// libtiff's tiff2rgba decodes them; the uncompressed ones as ImageMagick
/// does; a YCbCr image made by hand as tiff2rgba does; and libtiff's test
/// images (test/images/libtiff) as tiff2rgba does. ImageMagick's and
/// tiff2rgba's answers are recorded in test/oracles/tiff.json
/// (test/support/oracles.dart; ORACLES=record asks them again).
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:plain_images/plain_images.dart';
import 'package:test/test.dart';

import 'decode_test.dart' show onWhite;
import 'support.dart';
import 'support/oracles.dart';

const String _dir = 'test/images/tiff';

Raster _decode(String path) =>
    ImageFile.read(File(path).readAsBytesSync()).decode();

/// libtiff, which its answers depend on.
const String _libtiff = 'libtiff 4.7.2';

/// tiff2rgba's RGBA of the TIFF [bytes], or null where it can't make one.
Uint8List? tiff2rgba(Uint8List bytes) {
  final work = Directory.systemTemp.createTempSync('tiff.');
  try {
    final path = '${work.path}/in.tif';
    File(path).writeAsBytesSync(bytes);
    final out = '${work.path}/rgba.tif';
    final result = Process.runSync('tiff2rgba', ['-c', 'none', path, out]);
    if (result.exitCode != 0) return null;
    return _decode(out).toRgba8();
  } finally {
    work.deleteSync(recursive: true);
  }
}

/// The largest difference between the samples of [ours] and [theirs].
int _largest(Uint8List ours, Uint8List theirs) {
  expect(ours.length, theirs.length, reason: 'samples');
  var largest = 0;
  for (var i = 0; i < ours.length; i++) {
    final d = (ours[i] - theirs[i]).abs();
    if (d > largest) largest = d;
  }
  return largest;
}

void main() {
  final recorded = Oracle('tiff');
  final files = [
    for (final f in Directory(_dir).listSync().whereType<File>())
      if (f.path.endsWith('.tif')) f.uri.pathSegments.last,
  ]..sort();
  final expected = {
    for (final line in File('$_dir/expected.md5').readAsLinesSync())
      if (line.split(RegExp(r'\s+')) case [final sum, final name]) name: sum,
  };

  group('without loss, as the uncompressed image', () {
    for (final name in files) {
      if (!name.contains('-') ||
          expected.containsKey(name) ||
          name.contains('lzma') ||
          name.contains('zstd')) {
        continue;
      }
      final base = '${name.substring(0, name.indexOf('-'))}.tif';
      test(name, () {
        final ours = _decode('$_dir/$name');
        final reference = _decode('$_dir/$base');
        expect(ours.colorModel, reference.colorModel);
        expect(ours.bitDepth, reference.bitDepth);
        expect(ours.samples, reference.samples);
        expect(ours.palette, reference.palette);
        expect(ours.toRgba8(), reference.toRgba8());
      });
    }
  });

  group('JPEG and WebP compressed, as tiff2rgba decodes them', () {
    for (final MapEntry(key: name, value: sum) in expected.entries) {
      test(name, () {
        expect(md5.convert(_decode('$_dir/$name').toRgba8()).toString(), sum);
      });
    }
  });

  test('LZMA and Zstandard are named, not read', () {
    for (final (name, label) in [('lzma', 'LZMA'), ('zstd', 'Zstandard')]) {
      expect(
        () => ImageFile.read(File('$_dir/rgb8-$name.tif').readAsBytesSync()),
        throwsA(
          isA<ImageFormatException>().having(
            (e) => e.message,
            'message',
            'TIFF images compressed by $label are not supported',
          ),
        ),
      );
    }
  });

  test('what the headers say', () {
    TiffFile read(String name) =>
        ImageFile.read(File('$_dir/$name').readAsBytesSync()) as TiffFile;
    expect(read('rgb8-bigtiff.tif').compression, TiffCompression.deflate);
    expect(read('rgb8-big-endian.tif').littleEndian, isFalse);
    expect(read('rgb8-tiles.tif').tiled, isTrue);
    expect(read('rgb8-planar.tif').planar, isTrue);
    expect(read('bw-g4.tif').compression, TiffCompression.ccittGroup4);
    expect(read('bw-g4-lsb.tif').lsbFirst, isTrue);
    expect(read('float32-float-predictor.tif').predictor, 3);
    expect(read('pal4.tif').colorModel, ColorModel.indexed);
    expect(read('pal4.tif').bitDepth, 4);
    expect(read('bw.tif').bitDepth, 1);
    expect(read('cmyk8.tif').colorModel, ColorModel.cmyk);
    expect(read('rgb8.tif').pages, 1);
  });

  group('uncompressed, as ImageMagick decodes them', () {
    for (final name in files.where((n) => !n.contains('-'))) {
      test(name, () {
        final bytes = File('$_dir/$name').readAsBytesSync();
        final raster = ImageFile.read(bytes).decode();
        final (mean, max) = magickDifference(
          recorded,
          name,
          bytes,
          onWhite(raster.width, raster.height, raster.toRgba8()),
        );
        // (8-bit palettes: libtiff takes 16-bit entries' high byte,
        // ImageMagick rounds them.)
        expect(mean, lessThan(0.6), reason: 'mean difference');
        expect(max, lessThanOrEqualTo(1), reason: 'largest difference');
      });
    }
  });

  /// The largest difference between [ours] and tiff2rgba's RGBA of the
  /// TIFF [bytes] (null where libtiff can't make one), as recorded for
  /// [key].
  int? largestFromLibtiff(String key, Uint8List bytes, Uint8List ours) =>
      recorded.json<int?>(
        key,
        inputs: [_libtiff, bytes, ours],
        oracle: () => switch (tiff2rgba(bytes)) {
          final theirs? => _largest(ours, theirs),
          null => null,
        },
      );

  test('YCbCr samples (2 by 2 subsampling), as tiff2rgba converts them', () {
    final bytes = _ycbcrTiff();
    final ours = ImageFile.read(bytes).decode().toRgba8();
    expect(largestFromLibtiff('ycbcr', bytes, ours), 0);
  });

  test("libtiff's test images, as tiff2rgba decodes them", () {
    var checked = 0;
    for (final file
        in Directory('test/images/libtiff')
            .listSync()
            .whereType<File>()
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path))) {
      final name = file.uri.pathSegments.last;
      if (!name.endsWith('.tif') && !name.endsWith('.tiff')) continue;
      final bytes = file.readAsBytesSync();
      // (What libtiff itself can't turn into RGBA is left out.)
      final converts = recorded.json<bool>(
        'libtiff converts $name',
        inputs: [_libtiff, bytes],
        oracle: () => tiff2rgba(bytes) != null,
      );
      if (!converts) continue;
      final Raster raster;
      try {
        raster = ImageFile.read(bytes).decode();
      } on ImageFormatException catch (error) {
        // LogLuv and old-style JPEG: named, not read.
        expect(error.message, contains('not supported'), reason: name);
        continue;
      }
      // (16-bit gray: libtiff takes the high byte, toRgba8 rounds.)
      expect(
        largestFromLibtiff(name, bytes, raster.toRgba8()),
        lessThanOrEqualTo(1),
        reason: name,
      );
      checked++;
    }
    expect(checked, greaterThan(20));
  });
}

/// A little-endian TIFF of 5 by 3 YCbCr pixels, 2 by 2 subsampled, in one
/// strip of data units (four Y, then Cb and Cr).
Uint8List _ycbcrTiff() {
  const width = 5;
  const height = 3;
  final units = <int>[
    for (var uy = 0; uy < 2; uy++)
      for (var ux = 0; ux < 3; ux++) ...[
        for (var i = 0; i < 4; i++) (40 + 50 * ux + 30 * uy + 9 * i) & 0xff,
        60 + 40 * ux,
        200 - 50 * uy,
      ],
  ];
  final entries = <(int, int, int, List<int>)>[
    (256, 3, 1, [width]),
    (257, 3, 1, [height]),
    (258, 3, 3, [8, 8, 8]),
    (259, 3, 1, [1]),
    (262, 3, 1, [6]),
    (273, 4, 1, [0]), // the data's offset, set below
    (277, 3, 1, [3]),
    (278, 3, 1, [height]),
    (279, 4, 1, [units.length]),
    (284, 3, 1, [1]),
    (530, 3, 2, [2, 2]),
  ];
  final out = BytesBuilder();
  final header = ByteData(8)
    ..setUint8(0, 0x49)
    ..setUint8(1, 0x49)
    ..setUint16(2, 42, Endian.little)
    ..setUint32(4, 8, Endian.little);
  out.add(header.buffer.asUint8List());
  final ifdSize = 2 + entries.length * 12 + 4;
  // Values longer than four bytes after the directory, then the data.
  var extra = 8 + ifdSize;
  final extras = BytesBuilder();
  final ifd = ByteData(ifdSize)..setUint16(0, entries.length, Endian.little);
  final dataAt = extra + 6; // the one long value: BitsPerSample's 3 shorts
  for (var i = 0; i < entries.length; i++) {
    final (tag, type, count, values) = entries[i];
    final at = 2 + i * 12;
    ifd
      ..setUint16(at, tag, Endian.little)
      ..setUint16(at + 2, type, Endian.little)
      ..setUint32(at + 4, count, Endian.little);
    final size = (type == 3 ? 2 : 4) * count;
    final bytes = ByteData(size);
    for (var k = 0; k < count; k++) {
      final value = tag == 273 ? dataAt : values[k];
      if (type == 3) {
        bytes.setUint16(2 * k, value, Endian.little);
      } else {
        bytes.setUint32(4 * k, value, Endian.little);
      }
    }
    if (size <= 4) {
      for (var k = 0; k < size; k++) {
        ifd.setUint8(at + 8 + k, bytes.getUint8(k));
      }
    } else {
      ifd.setUint32(at + 8, extra, Endian.little);
      extras.add(bytes.buffer.asUint8List());
      extra += size;
    }
  }
  out
    ..add(ifd.buffer.asUint8List())
    ..add(extras.takeBytes())
    ..add(units);
  return out.takeBytes();
}
