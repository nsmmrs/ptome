/// WebP decoded as libwebp's dwebp decodes it, to the byte: the test
/// images (`tool/make_test_images.sh`; dwebp's output recorded as MD5s),
/// and seeded random images through cwebp with random settings (cwebp's
/// files and dwebp's MD5s recorded in test/oracles/webp.json.gz by
/// test/support/oracles.dart; ORACLES=record asks them again). libwebp's
/// own test data, which has no licence to redistribute it, is checked by
/// hand: `dart run tool/webp_suite.dart` (tool/fetch_webp_tests.sh).
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;
import 'package:plain_images/plain_images.dart';
import 'package:test/test.dart';

import 'support/oracles.dart';

/// [rgba] (a [width] by [height] image) as dwebp writes a PAM file.
Uint8List pam(int width, int height, Uint8List rgba) => Uint8List.fromList([
  ...ascii.encode(
    'P7\nWIDTH $width\nHEIGHT $height\nDEPTH 4\nMAXVAL 255\n'
    'TUPLTYPE RGB_ALPHA\nENDHDR\n',
  ),
  ...rgba,
]);

String md5Of(List<int> bytes) => md5.convert(bytes).toString();

/// The MD5s of an `md5sum` listing, by file name.
Map<String, String> md5s(File file) => {
  for (final line in file.readAsLinesSync())
    if (line.split(RegExp(r'\s+')) case [final sum, final name]) name: sum,
};

/// libwebp, which its answers depend on.
const String _libwebp = 'libwebp 1.6.0';

/// What cwebp makes of the PNG [png] with [options], and the MD5 of
/// dwebp's RGBA decoding of it.
Map<String, Object?> _cwebpDwebp(Uint8List png, List<String> options) {
  final dir = Directory.systemTemp.createTempSync('webp.');
  try {
    final input = File('${dir.path}/in.png')..writeAsBytesSync(png);
    final webp = '${dir.path}/out.webp';
    final result = Process.runSync('cwebp', [
      '-quiet',
      ...options,
      input.path,
      '-o',
      webp,
    ]);
    if (result.exitCode != 0) throw StateError('${result.stderr}');
    return {
      'webp': base64Encode(File(webp).readAsBytesSync()),
      'md5': md5Of(dwebp(webp)),
    };
  } finally {
    dir.deleteSync(recursive: true);
  }
}

/// dwebp's RGBA decoding of the WebP file at [path].
Uint8List dwebp(String path) {
  final result = Process.runSync('dwebp', [
    '-quiet',
    path,
    '-pam',
    '-o',
    '-',
  ], stdoutEncoding: null);
  expect(result.exitCode, 0, reason: '${result.stderr}');
  final out = Uint8List.fromList(result.stdout as List<int>);
  final header = latin1.decode(out.sublist(0, math.min(100, out.length)));
  return Uint8List.sublistView(out, header.indexOf('ENDHDR\n') + 7);
}

void main() {
  final recorded = Oracle('webp', compressed: true);
  group('test images', () {
    final expected = md5s(File('test/images/webp/expected.md5'));
    for (final MapEntry(key: name, value: sum) in expected.entries) {
      test('$name decodes as dwebp decodes it', () {
        final file = ImageFile.read(
          File('test/images/webp/$name').readAsBytesSync(),
        ) as WebPFile;
        final raster = file.decode();
        final rgba = raster.toRgba8();
        if (file.frames == 1) {
          expect(md5Of(pam(raster.width, raster.height, rgba)), sum);
          return;
        }
        // An animation: its first frame where it goes, nothing around it.
        final frame = Uint8List(file.frameWidth * file.frameHeight * 4);
        for (var y = 0; y < raster.height; y++) {
          for (var x = 0; x < raster.width; x++) {
            final i = (y * raster.width + x) * 4;
            final fx = x - file.frameLeft;
            final fy = y - file.frameTop;
            if (fx >= 0 &&
                fy >= 0 &&
                fx < file.frameWidth &&
                fy < file.frameHeight) {
              frame.setRange(
                (fy * file.frameWidth + fx) * 4,
                (fy * file.frameWidth + fx + 1) * 4,
                rgba,
                i,
              );
            } else {
              expect(rgba[i + 3], 0, reason: 'outside the frame at $x, $y');
            }
          }
        }
        expect(md5Of(pam(file.frameWidth, file.frameHeight, frame)), sum);
      });
    }

    test('what the headers say', () {
      WebPFile read(String name) =>
          ImageFile.read(File('test/images/webp/$name').readAsBytesSync())
              as WebPFile;
      final animated = read('animated.webp');
      expect((animated.width, animated.height), (40, 30));
      expect((animated.frameLeft, animated.frameTop), (6, 4));
      expect(animated.frames, 2);
      expect(animated.lossless, isTrue);
      final extended = read('extended.webp');
      expect(extended.orientation, 6);
      expect(ascii.decode(extended.iccProfile!), 'not really an ICC profile');
      expect(extended.decode().orientation, 6);
      expect(read('lossy.webp').lossless, isFalse);
      expect(read('lossy-alpha.webp').alpha, isTrue);
      expect(read('lossy.webp').alpha, isFalse);
    });
  });

  test('random images through cwebp, with random settings, as dwebp decodes '
      'them', () {
    final random = math.Random(9649);
    for (var trial = 0; trial < 60; trial++) {
      final w = 1 + random.nextInt(70);
      final h = 1 + random.nextInt(50);
      final alpha = random.nextBool();
      final image = img.Image(width: w, height: h, numChannels: alpha ? 4 : 3);
      // Smooth areas and noise, so both prediction and residuals count.
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final noise = random.nextInt(4) == 0;
          final p = image.getPixel(x, y)
            ..r = noise ? random.nextInt(256) : (x * 255 ~/ w)
            ..g = noise ? random.nextInt(256) : (y * 255 ~/ h)
            ..b = (x ^ y) * 7 & 0xff;
          if (alpha) p.a = (x * y) % 3 == 0 ? 0 : random.nextInt(256);
        }
      }
      final png = img.encodePng(image);
      final options = random.nextInt(3) == 0
          ? ['-lossless', '-z', '${random.nextInt(10)}', '-exact']
          : [
              '-q',
              '${random.nextInt(101)}',
              '-sns',
              '${random.nextInt(101)}',
              '-f',
              '${random.nextInt(101)}',
              '-sharpness',
              '${random.nextInt(8)}',
              '-segments',
              '${1 + random.nextInt(4)}',
              '-partition_limit',
              '${random.nextInt(101)}',
              if (random.nextBool()) '-sharp_yuv',
              if (random.nextBool()) ...['-af'],
              if (alpha) ...[
                '-alpha_q',
                '${random.nextInt(101)}',
                '-alpha_filter',
                ['none', 'fast', 'best'][random.nextInt(3)],
                '-alpha_method',
                '${random.nextInt(2)}',
              ],
            ];
      final theirs = recorded.json<Map<String, Object?>>(
        'trial $trial',
        inputs: [_libwebp, png, ...options],
        oracle: () => _cwebpDwebp(png, options),
      );
      final webp = base64Decode(theirs['webp']! as String);
      final ours = ImageFile.read(webp).decode().toRgba8();
      expect(
        md5Of(ours),
        theirs['md5'],
        reason: 'trial $trial: ${w}x$h ${options.join(' ')}',
      );
    }
  });
}
