/// resvg's reference renders as the oracle of SVG drawn in a PDF: each of
/// its test cases (`tool/fetch_resvg_tests.sh`, at a pinned commit) drawn
/// on a page of one PDF, the pages rasterized by pdftoppm and compared
/// with resvg's PNGs (flattened on white by ImageMagick).
///
/// The cases drawn alike are recorded in `test/resvg_baseline.txt`: one
/// that stops being drawn alike fails the test; one that starts is
/// reported, and `RESVG_UPDATE=1` records it. Skipped without the cases
/// (`RESVG_TESTS`, by default where the script puts them) or the tools.
@Tags(['nightly', 'pdf-tools'])
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:plain_pdf/plain_pdf.dart';
import 'package:plain_svg/plain_svg.dart';
import 'package:plain_typesetting/plain_typesetting.dart';
import 'package:test/test.dart';

final String _cases =
    Platform.environment['RESVG_TESTS'] ??
    '${Platform.environment['HOME']}/.cache/asciidart-work/resvg/repo/'
        'crates/resvg/tests/tests';

bool _has(String tool) =>
    Process.runSync('sh', ['-c', 'command -v $tool']).exitCode == 0;

/// The width, height and RGB samples of the binary PPM [bytes].
(int, int, Uint8List) _ppm(Uint8List bytes) {
  var at = 0;
  String token() {
    while (bytes[at] == 0x20 ||
        bytes[at] == 0x0a ||
        bytes[at] == 0x0d ||
        bytes[at] == 0x09) {
      at++;
    }
    final start = at;
    while (!(bytes[at] == 0x20 ||
        bytes[at] == 0x0a ||
        bytes[at] == 0x0d ||
        bytes[at] == 0x09)) {
      at++;
    }
    return latin1.decode(bytes.sublist(start, at));
  }

  if (token() != 'P6') throw const FormatException('not a binary PPM');
  final width = int.parse(token());
  final height = int.parse(token());
  if (token() != '255') throw const FormatException('not 8 bits a sample');
  at++;
  return (width, height, Uint8List.sublistView(bytes, at));
}

/// Whether [a] and [b] are drawn alike: the same size, and at most 1% of
/// the pixels apart by more than a quarter of a channel's range (edges
/// are smoothed differently).
bool _alike((int, int, Uint8List) a, (int, int, Uint8List) b) {
  final (aw, ah, asamples) = a;
  final (bw, bh, bsamples) = b;
  if (aw != bw || ah != bh || asamples.length < aw * ah * 3) return false;
  if (bsamples.length < aw * ah * 3) return false;
  var apart = 0;
  for (var i = 0; i < aw * ah * 3; i += 3) {
    for (var c = 0; c < 3; c++) {
      if ((asamples[i + c] - bsamples[i + c]).abs() > 64) {
        apart++;
        break;
      }
    }
  }
  return apart <= aw * ah / 100;
}

void main() {
  // (ImageMagick 7's `magick mogrify`, or 6's `mogrify`.)
  final mogrify = _has('magick')
      ? ['magick', 'mogrify']
      : _has('mogrify')
      ? ['mogrify']
      : null;
  final available =
      Directory(_cases).existsSync() && _has('pdftoppm') && mogrify != null;
  test(
    'SVG drawn as resvg draws it',
    skip: available ? false : 'no resvg cases, pdftoppm or ImageMagick',
    timeout: const Timeout(Duration(minutes: 20)),
    () {
      final svgs = [
        for (final entity in Directory(_cases).listSync(recursive: true))
          if (entity is File &&
              entity.path.endsWith('.svg') &&
              File(
                '${entity.path.substring(0, entity.path.length - 4)}'
                '.png',
              ).existsSync())
            entity,
      ]..sort((a, b) => a.path.compareTo(b.path));
      String name(File file) =>
          file.path.substring(_cases.length + 1, file.path.length - 4);
      final work = Directory.systemTemp.createTempSync('resvg');
      try {
        // Every case on a page of one document, in order; one that can't
        // be read has no page.
        final document = PdfDocument();
        final pages = <String, int>{};
        for (final file in svgs) {
          final SvgImage svg;
          try {
            svg = SvgImage.parse(
              utf8.decode(file.readAsBytesSync(), allowMalformed: true),
              fonts: standardSvgFont,
              rasters: readSvgRaster,
              pixelSize: 1,
              images: (href) {
                final uri = file.parent.uri.resolve(href);
                if (uri.scheme != 'file') return null;
                final image = File.fromUri(uri);
                return image.existsSync() ? image.readAsBytesSync() : null;
              },
            );
          } on FormatException {
            continue;
          }
          // The page the reference's size (resvg draws its cases 300
          // pixels wide), the image fitted in it.
          final png = File(
            '${file.path.substring(0, file.path.length - 4)}.png',
          ).readAsBytesSync();
          final header = ByteData.sublistView(png, 16, 24);
          final width = header.getUint32(0).toDouble();
          final height = header.getUint32(4).toDouble();
          final page = document.addPage(Rect(0, 0, width, height));
          try {
            svg.paint(page.canvas, Rect(0, 0, width, height));
          } on Object {
            // (A page left as it is: a case drawn wrong.)
          }
          pages[name(file)] = pages.length + 1;
        }
        final pdf = File('${work.path}/all.pdf')
          ..writeAsBytesSync(document.save());
        final raster = Process.runSync('pdftoppm', [
          '-r',
          '72',
          pdf.path,
          '${work.path}/page',
        ]);
        expect(raster.exitCode, 0, reason: '${raster.stderr}');
        // The references, flattened on white.
        Directory('${work.path}/ref').createSync();
        for (final file in svgs) {
          final key = name(file).replaceAll('/', '__');
          File('${file.path.substring(0, file.path.length - 4)}.png')
              .copySync('${work.path}/ref/$key.png');
        }
        final flatten = Process.runSync(mogrify!.first, [
          ...mogrify.skip(1),
          '-background',
          'white',
          '-alpha',
          'remove',
          '-depth',
          '8',
          '-format',
          'ppm',
          '${work.path}/ref/*.png',
        ]);
        expect(flatten.exitCode, 0, reason: '${flatten.stderr}');
        final digits = '${pages.length}'.length;
        final alike = <String>{
          for (final MapEntry(key: name, value: number) in pages.entries)
            if (File('${work.path}/page-${'$number'.padLeft(digits, '0')}.ppm')
                    .readAsBytesSync()
                case final page
                when _alike(
                  _ppm(page),
                  _ppm(
                    File('${work.path}/ref/${name.replaceAll('/', '__')}.ppm')
                        .readAsBytesSync(),
                  ),
                ))
              name,
        };
        final baselineFile = File('test/resvg_baseline.txt');
        final baseline = baselineFile
            .readAsLinesSync()
            .where((l) => l.isNotEmpty && !l.startsWith('#'))
            .toSet();
        final lost = baseline.difference(alike).toList()..sort();
        final gained = alike.difference(baseline).toList()..sort();
        if (Platform.environment['RESVG_UPDATE'] == '1') {
          baselineFile.writeAsStringSync(
            '# resvg reference-render cases drawn alike '
            '(test/resvg_test.dart): ${alike.length} of ${svgs.length}.\n'
            '${(alike.toList()..sort()).join('\n')}\n',
          );
        } else if (gained.isNotEmpty) {
          // A report: RESVG_UPDATE=1 records them.
          // ignore: avoid_print
          print(
            'Drawn alike now (${gained.length}):\n  ${gained.join('\n  ')}',
          );
        }
        expect(lost, isEmpty, reason: 'drawn alike no longer');
      } finally {
        work.deleteSync(recursive: true);
      }
    },
  );
}
