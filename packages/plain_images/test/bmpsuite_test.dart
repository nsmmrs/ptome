/// bmpsuite 2.8 (Jason Summers): each good and questionable BMP file
/// compared with the images its page shows it should look like (any of
/// them; decoded by plain_images' own PNG reader), composited on white;
/// the bad files are read or rejected, never failing otherwise.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:plain_images/plain_images.dart';
import 'package:test/test.dart';

import 'decode_test.dart' show onWhite;
import 'support.dart';

const String _suite = 'test/images/bmpsuite';

/// What isn't read yet: OS/2's Huffman code (with TIFF's fax codes).
const Map<String, String> _unsupported = {
  'q/pal1huffmsb.bmp': 'BMP Huffman compression (OS/2) is not supported',
};

(int, int, Uint8List) _rgb(Raster raster) =>
    onWhite(raster.width, raster.height, raster.toRgba8());

void main() {
  final lines = File('$_suite/references.txt')
      .readAsLinesSync()
      .where((l) => l.isNotEmpty && !l.startsWith('#'));
  for (final line in lines) {
    final [name, ...references] = line.split(' ');
    test('$name looks as its page shows', () {
      final bytes = File('$_suite/$name').readAsBytesSync();
      if (_unsupported[name] case final message?) {
        expect(
          () => ImageFile.read(bytes).decode(),
          throwsA(
            isA<ImageFormatException>().having(
              (e) => e.message,
              'message',
              message,
            ),
          ),
        );
        return;
      }
      final ours = _rgb(ImageFile.read(bytes).decode());
      final results = <String>[];
      for (final reference in references) {
        final expected = _rgb(
          ImageFile.read(File('$_suite/ref/$reference').readAsBytesSync())
              .decode(),
        );
        if (expected.$1 != ours.$1 || expected.$2 != ours.$2) {
          results.add('$reference: another size');
          continue;
        }
        final (mean, max) = difference(ours, expected);
        if (mean < 0.5 && max <= 2) return;
        results.add('$reference: mean $mean, largest $max');
      }
      fail('like none of its references: ${results.join('; ')}');
    });
  }

  test('bad files are read or rejected', () {
    for (final file in testImages('bmpsuite/b', '.bmp')) {
      try {
        ImageFile.read(file.readAsBytesSync()).decode().toRgba8();
      } on ImageFormatException {
        // Rejected, as it may be.
      }
    }
  });
}
