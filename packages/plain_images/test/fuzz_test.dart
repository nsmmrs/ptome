// Damaged input: every test image with bytes flipped, cut short, inserted
// or zeroed is decoded or rejected with an ImageFormatException, and
// never fails otherwise (a RangeError, a TypeError, a hang). The damage
// is random but seeded, so a failure is reproducible.

@Tags(['nightly'])
@TestOn('vm')
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:plain_images/plain_images.dart';
import 'package:test/test.dart';

import 'support.dart';

/// [count] damaged copies of [bytes]: bytes flipped, the end cut off, bytes
/// inserted, a run zeroed.
Iterable<Uint8List> damaged(Uint8List bytes, Random random, int count) sync* {
  for (var i = 0; i < count; i++) {
    final copy = Uint8List.fromList(bytes);
    switch (i % 4) {
      case 0:
        for (var k = 0; k < 1 + random.nextInt(8); k++) {
          copy[random.nextInt(copy.length)] = random.nextInt(256);
        }
        yield copy;
      case 1:
        yield Uint8List.sublistView(copy, 0, random.nextInt(copy.length));
      case 2:
        final at = random.nextInt(copy.length);
        yield Uint8List.fromList([
          ...copy.sublist(0, at),
          for (var k = 0; k < 1 + random.nextInt(16); k++) random.nextInt(256),
          ...copy.sublist(at),
        ]);
      default:
        final at = random.nextInt(copy.length);
        final end = min(copy.length, at + 1 + random.nextInt(64));
        copy.fillRange(at, end, 0);
        yield copy;
    }
  }
}

void main() {
  for (final (folder, extension, limit) in [
    ('pngsuite', '.png', 40),
    ('jpeg', '.jpg', 10),
    ('gif', '.gif', 20),
    ('bmp', '.bmp', 20),
  ]) {
    test('$folder: damaged files are decoded or rejected', () {
      final random = Random(20261013);
      for (final file in testImages(folder, extension).take(limit)) {
        final bytes = file.readAsBytesSync();
        var i = 0;
        for (final input in damaged(bytes, random, 300)) {
          try {
            final image = ImageFile.read(input);
            // (JPEG isn't decoded yet.)
            if (image is! JpegFile) image.decode().toRgba8();
          } on ImageFormatException {
            // Rejected, as it may be.
          } on Object catch (error, stack) {
            final where = stack.toString().split('\n').take(6).join('\n');
            fail('${file.path}, damaged copy $i: $error\n$where');
          }
          i++;
        }
      }
    }, timeout: const Timeout(Duration(minutes: 10)));
  }
}
