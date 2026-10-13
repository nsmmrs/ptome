/// JPEG decoded as libjpeg-turbo's djpeg decodes it, to the byte: the
/// test images (`tool/make_test_images.sh`: each sampling layout,
/// restarts, progressive, arithmetic coding, 12 bits, lossless; djpeg's
/// output recorded as MD5s), and seeded random images through cjpeg with
/// random settings (when cjpeg and djpeg are installed).
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:plain_images/plain_images.dart';
import 'package:plain_images/src/jpeg_decode.dart';
import 'package:test/test.dart';

import 'support.dart';

/// [pixels] as djpeg writes them: a PGM or PPM file, its samples 16 bits
/// (big-endian) when they are more than 8.
Uint8List pnm(JpegPixels pixels) {
  final max = (1 << pixels.precision) - 1;
  final out = BytesBuilder(copy: false)
    ..add(
      ascii.encode(
        '${pixels.channels == 1 ? 'P5' : 'P6'}\n'
        '${pixels.width} ${pixels.height}\n$max\n',
      ),
    );
  if (max > 255) {
    for (final v in pixels.samples) {
      out
        ..addByte(v >> 8)
        ..addByte(v & 0xff);
    }
  } else {
    out.add(Uint8List.fromList(pixels.samples));
  }
  return out.takeBytes();
}

bool _has(String tool) =>
    Process.runSync('sh', ['-c', 'command -v $tool']).exitCode == 0;

void main() {
  group('test images', () {
    final expected = {
      for (final line in File(
        'test/images/jpeg-suite/expected.md5',
      ).readAsLinesSync())
        if (line.split(RegExp(r'\s+')) case [final sum, final name]) name: sum,
    };
    for (final MapEntry(key: name, value: sum) in expected.entries) {
      test('$name decodes as djpeg decodes it', () {
        final bytes = File('test/images/jpeg-suite/$name').readAsBytesSync();
        expect(md5.convert(pnm(decodeJpeg(bytes))).toString(), sum);
        // And as a raster.
        final raster = ImageFile.read(bytes).decode();
        expect(raster.width * raster.height, greaterThan(0));
      });
    }
  });

  test('what the headers say', () {
    JpegFile read(String name) =>
        ImageFile.read(File('test/images/jpeg-suite/$name').readAsBytesSync())
            as JpegFile;
    expect(read('arithmetic.jpg').arithmetic, isTrue);
    expect(read('lossless-12.jpg').lossless, isTrue);
    expect(read('lossless-12.jpg').bitDepth, 16);
    expect(read('precision-12.jpg').precision, 12);
    expect(read('gray.jpg').colorModel, ColorModel.gray);
    expect(read('sample-2x2.jpg').arithmetic, isFalse);
  });

  test('12-bit and lossless samples fill 16 bits; 4-bit ones 8', () {
    Raster decode(String name) =>
        ImageFile.read(File('test/images/jpeg-suite/$name').readAsBytesSync())
            .decode();
    final twelve = decode('precision-12.jpg');
    expect(twelve.bitDepth, 16);
    final four = decode('lossless-4-gray.jpg');
    expect(four.bitDepth, 8);
    // 4-bit samples: multiples of 17.
    expect(four.samples.every((v) => v % 17 == 0), isTrue);
  });

  test('Adobe CMYK is turned back from its inverted samples', () {
    final magick = magickCommand();
    if (magick == null) return;
    final bytes = File('test/images/jpeg/cmyk.jpg').readAsBytesSync();
    final raster = ImageFile.read(bytes).decode();
    expect(raster.colorModel, ColorModel.cmyk);
    // ImageMagick's CMYK samples of the file.
    final result = Process.runSync(magick, [
      'test/images/jpeg/cmyk.jpg',
      '-depth',
      '8',
      'cmyk:-',
    ], stdoutEncoding: null);
    final theirs = result.stdout as List<int>;
    var largest = 0;
    for (var i = 0; i < raster.samples.length; i++) {
      final d = (raster.samples[i] - theirs[i]).abs();
      if (d > largest) largest = d;
    }
    // (ImageMagick's own IDCT and upsampling: a little apart.)
    expect(largest, lessThanOrEqualTo(4));
  }, tags: ['tools']);

  final tools = _has('cjpeg') && _has('djpeg');
  test(
    'random images through cjpeg, with random settings, as djpeg decodes '
    'them',
    () {
      final random = math.Random(10918);
      final dir = Directory.systemTemp.createTempSync('jpeg.');
      addTearDown(() => dir.deleteSync(recursive: true));
      var checked = 0;
      for (var trial = 0; trial < 120; trial++) {
        final w = 1 + random.nextInt(90);
        final h = 1 + random.nextInt(70);
        final gray = random.nextInt(5) == 0;
        final channels = gray ? 1 : 3;
        final input = BytesBuilder()
          ..add(ascii.encode('${gray ? 'P5' : 'P6'}\n$w $h\n255\n'));
        for (var y = 0; y < h; y++) {
          for (var x = 0; x < w; x++) {
            for (var c = 0; c < channels; c++) {
              input.addByte(
                random.nextInt(4) == 0
                    ? random.nextInt(256)
                    : ((x * (c + 3) + y * (5 - c)) * 7) & 0xff,
              );
            }
          }
        }
        File('${dir.path}/in.pnm').writeAsBytesSync(input.takeBytes());
        final mode = random.nextInt(4);
        final options = [
          '-quality',
          '${1 + random.nextInt(100)}',
          if (!gray && random.nextBool()) ...[
            '-sample',
            [
              '2x2',
              '2x1',
              '1x2',
              '1x1',
              '4x1',
              '4x2',
              '1x4',
              '2x4',
              '3x1',
            ][random.nextInt(9)],
          ],
          if (random.nextInt(4) == 0) ...[
            '-restart',
            '${1 + random.nextInt(5)}${random.nextBool() ? 'B' : ''}',
          ],
          if (random.nextInt(3) == 0 && mode != 2) '-progressive',
          if (random.nextInt(3) == 0 && mode != 2) '-optimize',
          if (!gray && random.nextInt(6) == 0) '-rgb',
          if (gray) '-grayscale',
          if (mode == 1) '-arithmetic',
          if (mode == 2) ...[
            '-lossless',
            '${1 + random.nextInt(7)},${random.nextInt(3)}',
            '-precision',
            '${[8, 12, 16, 10, 6][random.nextInt(5)]}',
          ],
          if (mode == 3) ...['-precision', '12'],
        ];
        final jpeg = '${dir.path}/out.jpg';
        final encoded = Process.runSync('cjpeg', [
          ...options,
          '-outfile',
          jpeg,
          '${dir.path}/in.pnm',
        ]);
        // (Settings cjpeg refuses together are skipped.)
        if (encoded.exitCode != 0) continue;
        final decoded = Process.runSync('djpeg', [
          '-pnm',
          jpeg,
        ], stdoutEncoding: null);
        if (decoded.exitCode != 0) continue;
        expect(
          pnm(decodeJpeg(File(jpeg).readAsBytesSync())),
          decoded.stdout,
          reason: 'trial $trial: ${w}x$h ${options.join(' ')}',
        );
        checked++;
      }
      expect(checked, greaterThan(80));
    },
    skip: tools ? false : 'needs cjpeg and djpeg',
    tags: ['tools'],
  );
}
