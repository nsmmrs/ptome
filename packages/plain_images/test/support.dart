/// What the tests share: the test images, and ImageMagick as an oracle.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';

/// The files of `test/images/<folder>` ending in [extension], by name.
List<File> testImages(String folder, String extension) =>
    Directory('test/images/$folder')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith(extension))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

/// ImageMagick's command: `magick` (version 7), else `convert` (6), else
/// null.
String? magickCommand() {
  bool has(String tool) =>
      Process.runSync('sh', ['-c', 'command -v $tool']).exitCode == 0;
  return has('magick')
      ? 'magick'
      : has('convert')
      ? 'convert'
      : null;
}

/// The first frame of the image file at [path] as ImageMagick decodes
/// it, on its canvas, composited on white: width, height, RGB samples.
(int, int, Uint8List) magickOnWhite(String magick, String path) {
  final result = Process.runSync(magick, [
    '$path[0]',
    '-background',
    'white',
    '-flatten',
    '-alpha',
    'off',
    '-depth',
    '8',
    'ppm:-',
  ], stdoutEncoding: null);
  expect(result.exitCode, 0, reason: '${result.stderr}');
  return parsePpm(Uint8List.fromList(result.stdout as List<int>));
}

/// The raster of a binary PPM (P6, maximum 255).
(int, int, Uint8List) parsePpm(Uint8List bytes) {
  final fields = <String>[];
  var at = 0;
  bool space(int b) => b == 0x20 || b == 0x0a || b == 0x0d || b == 0x09;
  while (fields.length < 4) {
    while (bytes[at] == 0x23 || space(bytes[at])) {
      if (bytes[at] == 0x23) {
        while (bytes[at] != 0x0a) {
          at++;
        }
      }
      at++;
    }
    final start = at;
    while (!space(bytes[at])) {
      at++;
    }
    fields.add(ascii.decode(bytes.sublist(start, at)));
  }
  expect(fields[0], 'P6');
  expect(fields[3], '255');
  return (
    int.parse(fields[1]),
    int.parse(fields[2]),
    Uint8List.sublistView(bytes, at + 1),
  );
}

/// The mean and the largest absolute difference between the samples of
/// two rasters of the same size.
(double, int) difference((int, int, Uint8List) a, (int, int, Uint8List) b) {
  expect((a.$1, a.$2), (b.$1, b.$2), reason: 'dimensions');
  var sum = 0;
  var max = 0;
  final n = a.$1 * a.$2 * 3;
  for (var i = 0; i < n; i++) {
    final d = (a.$3[i] - b.$3[i]).abs();
    sum += d;
    if (d > max) max = d;
  }
  return (sum / n, max);
}
