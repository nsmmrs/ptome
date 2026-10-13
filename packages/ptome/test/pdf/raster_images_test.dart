// GIF, BMP, WebP and TIFF images in PDF, in the modern engine and the
// compatibility mode alike (asciidoctor-pdf warns that GIF isn't
// supported; ptome doesn't imitate that): embedded with their
// transparency, on other cores too, and a format plain_images doesn't
// read reported by name.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:ptome/src/internal.dart';
import 'package:ptome/src/pdf/pdf.dart';
import 'package:test/test.dart';

import '../vendored_fonts.dart';

bool _has(String tool) => Process.runSync('which', [tool]).exitCode == 0;

const String _images = '../plain_images/test/images';

void main() {
  setUpAll(useVendoredFonts);
  setUpAll(registerPdf);

  late Directory dir;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('ptome-raster.');
    for (final name in [
      'gif/transparent.gif',
      'gif/animated-offset.gif',
      'bmp/rle8.bmp',
      'bmp/rgba32-v5.bmp',
      'webp/lossy-alpha.webp',
      'tiff/bw-g4.tif',
    ]) {
      File('$_images/$name').copySync('${dir.path}/${name.split('/').last}');
    }
    // An AVIF file's signature: recognized, not read.
    File('${dir.path}/photo.avif').writeAsBytesSync(
      Uint8List.fromList('\u0000\u0000\u0000\u001cftypavif'.codeUnits),
    );
    File('${dir.path}/doc.adoc').writeAsStringSync('''
= Raster images

image::transparent.gif[Transparent]

An inline image:animated-offset.gif[Animated,20] in a line.

image::rle8.bmp[Run-length]

image::rgba32-v5.bmp[Alpha]

image::lossy-alpha.webp[Lossy with alpha]

image::bw-g4.tif[Fax]

image::photo.avif[Photo]
''');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  (String, List<String>) convert({required bool compat, String jobs = '1'}) {
    final out = '${dir.path}/${compat ? 'compat' : 'modern'}-$jobs.pdf';
    final logger = MemoryLogger();
    convertFile(
      '${dir.path}/doc.adoc',
      AsciidoctorOptions(
        safe: SafeMode.unsafe,
        backend: 'pdf',
        toFile: out,
        attributes: {
          if (compat) 'pdf-compat': '',
          'jobs': jobs,
          'localdatetime': '2020-01-01 00:00:00 +0000',
        },
        logger: logger,
      ),
    );
    return (
      out,
      [
        for (final m in logger.messages)
          if (m.severity.index >= Severity.warn.index) '${m.message}',
      ],
    );
  }

  for (final compat in [false, true]) {
    test('${compat ? 'compatibility mode' : 'modern engine'}: GIF, BMP and '
        'WebP are embedded, AVIF reported', () {
      final (pdf, warnings) = convert(compat: compat);
      expect(warnings, [
        'could not embed image: photo.avif; AVIF images are not supported',
      ]);
      if (!_has('pdfimages')) return;
      // Six images: the GIF with a color key (no soft mask), the inline
      // GIF, the RLE8 bitmap (indexed), the bitmap with alpha and the WebP
      // with alpha (each with its soft mask), the Group 4 fax (1-bit
      // gray).
      final list =
          (Process.runSync('pdfimages', ['-list', pdf]).stdout as String)
              .split('\n')
              .skip(2)
              .where((l) => l.trim().isNotEmpty)
              .map((l) => l.trim().split(RegExp(r'\s+')))
              .toList();
      expect(
        [for (final row in list) row[2]],
        [
          'image',
          'image',
          'image',
          'image',
          'smask',
          'image',
          'smask',
          'image',
        ],
      );
      expect(
        [for (final row in list) row[5]],
        ['index', 'index', 'index', 'rgb', 'gray', 'rgb', 'gray', 'gray'],
      );
    });
  }

  test('decoded on other cores, the same bytes', () async {
    final (serial, _) = convert(compat: false);
    final out = '${dir.path}/parallel.pdf';
    await convertFileFinishing(
      '${dir.path}/doc.adoc',
      AsciidoctorOptions(
        safe: SafeMode.unsafe,
        backend: 'pdf',
        toFile: out,
        attributes: {'jobs': '3', 'localdatetime': '2020-01-01 00:00:00 +0000'},
        logger: MemoryLogger(),
      ),
    );
    expect(File(out).readAsBytesSync(), File(serial).readAsBytesSync());
  });
}
