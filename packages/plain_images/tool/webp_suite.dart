/// libwebp's own test data (lossless and lossy files, the VP8 conformance
/// vectors) decoded as the MD5s it records for dwebp's output say, or,
/// for the files it has no MD5 for, as dwebp decodes them. The data has no
/// licence to redistribute it, so it is fetched, not committed, and this
/// is run by hand rather than as a test:
///
/// ```sh
/// tool/fetch_webp_tests.sh            # into ~/.cache/asciidart-work
/// dart run tool/webp_suite.dart [DIR]
/// ```
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:plain_images/plain_images.dart';

void main(List<String> arguments) {
  final suite = arguments.isNotEmpty
      ? arguments.first
      : '${Platform.environment['HOME']}/.cache/asciidart-work/'
            'libwebp-test-data';
  final sums = {
    for (final line in File('$suite/libwebp_tests.md5').readAsLinesSync())
      if (line.split(RegExp(r'\s+')) case [final sum, final name]) name: sum,
  };
  final files =
      Directory(suite)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.webp'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  var checked = 0;
  final differ = <String>[];
  for (final file in files) {
    final name = file.uri.pathSegments.last;
    final raster = ImageFile.read(file.readAsBytesSync()).decode();
    final rgba = raster.toRgba8();
    final ours = md5.convert(_pam(raster.width, raster.height, rgba));
    final theirs =
        sums['$name.pam'] ??
        '${md5.convert(_pam(raster.width, raster.height, _dwebp(file.path)))}';
    if ('$ours' != theirs) differ.add(name);
    checked++;
  }
  stdout.writeln(
    '$checked files of libwebp test data; ${differ.length} differ'
    '${differ.isEmpty ? '' : ': ${differ.join(', ')}'}',
  );
  exit(differ.isEmpty && checked >= 96 ? 0 : 1);
}

/// [rgba] (a [width] by [height] image) as dwebp writes a PAM file.
Uint8List _pam(int width, int height, Uint8List rgba) => Uint8List.fromList([
  ...ascii.encode(
    'P7\nWIDTH $width\nHEIGHT $height\nDEPTH 4\nMAXVAL 255\n'
    'TUPLTYPE RGB_ALPHA\nENDHDR\n',
  ),
  ...rgba,
]);

/// dwebp's RGBA decoding of the WebP file at [path].
Uint8List _dwebp(String path) {
  final result = Process.runSync('dwebp', [
    '-quiet',
    path,
    '-pam',
    '-o',
    '-',
  ], stdoutEncoding: null);
  if (result.exitCode != 0) throw StateError('dwebp: ${result.stderr}');
  final out = Uint8List.fromList(result.stdout as List<int>);
  final header = latin1.decode(out.sublist(0, math.min(100, out.length)));
  return Uint8List.sublistView(out, header.indexOf('ENDHDR\n') + 7);
}
