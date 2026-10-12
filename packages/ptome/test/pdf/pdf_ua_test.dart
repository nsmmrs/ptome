// `:pdf-ua:`: a tagged PDF (FEAT-cs3j22), its structure tree read back
// with Poppler's pdfinfo and checked against PDF/UA-1 by veraPDF where
// they are installed (VERAPDF, else veraPDF in the work folder or on the
// path).
@TestOn('vm')
@Tags(['slow'])
library;

import 'dart:io';

import 'package:ptome/src/internal.dart';
import 'package:ptome/src/pdf/pdf.dart';
import 'package:test/test.dart';

import '../vendored_fonts.dart';

late Directory _dir;

/// The first of the commands named that runs (asked its version with
/// [flag]), or null.
String? _tool(List<String> candidates, {String flag = '--version'}) {
  for (final command in candidates) {
    try {
      if (Process.runSync(command, [flag]).exitCode == 0) return command;
    } on ProcessException {
      continue;
    }
  }
  return null;
}

final String? _pdfinfo = _tool(['pdfinfo'], flag: '-v');

final String? _verapdf = _tool([
  ?Platform.environment['VERAPDF'],
  '${Platform.environment['HOME']}/.cache/asciidart-work/verapdf/verapdf',
  'verapdf',
]);

const String _source = '''
= A Tagged Document
:pdf-ua:

The first paragraph, with a https://example.com[link] in it.

== A Section

A paragraph in the section.

* An item
* Another item

[cols="1,2",options=header]
|===
|Name |Value
|alpha |one
|===

.A figure
image::IMAGE[A red square,width=50]

=== A Subsection

Last words.
''';

String _convert() {
  final input = File('${_dir.path}/ua.adoc')
    ..writeAsStringSync(
      _source.replaceFirst(
        'IMAGE',
        '${Directory.current.path}/test/pdf/fixtures/images/red.png',
      ),
    );
  final out = '${input.path}.pdf';
  convertFile(
    input.path,
    AsciidoctorOptions(
      safe: SafeMode.unsafe,
      backend: 'pdf',
      toFile: out,
      // (asciidoctor-pdf's theme, its fonts vendored: the same lines
      // wherever the looks' fonts are installed or not.)
      attributes: const {'reproducible': '', 'pdf-theme': 'default'},
    ),
  );
  return out;
}

void main() {
  setUpAll(useVendoredFonts);
  setUpAll(() {
    registerPdf();
    _dir = Directory.systemTemp.createTempSync('ptome-ua.');
  });
  tearDownAll(() => _dir.deleteSync(recursive: true));

  test(
    'the structure tree: headings, paragraphs, lists, a table, a figure',
    () {
      final pdfinfo = _pdfinfo;
      if (pdfinfo == null) {
        markTestSkipped('needs pdfinfo');
        return;
      }
      final tree =
          Process.runSync(pdfinfo, ['-struct-text', _convert()]).stdout
              as String;
      // (An older Poppler's pdfinfo prints no structure tree.)
      if (!tree.trimLeft().startsWith('Document')) {
        markTestSkipped("needs a pdfinfo that prints a PDF's structure tree");
        return;
      }
      final roles = [
        for (final line in tree.split('\n'))
          if (RegExp(r'^\s*([A-Z][A-Za-z0-9]*)').firstMatch(line) case final m?)
            m[1]!,
      ];
      expect(roles.first, 'Document');
      expect(
        roles,
        containsAllInOrder([
          'H1', 'P', 'Link', 'H2', 'P', 'L', 'LI', 'LBody', 'P', //
          'Table', 'TR', 'TH', 'TD', 'Figure', 'H3', 'P',
        ]),
      );
      // (The figure's alternate text, however pdfinfo shows it.)
      expect(tree, contains('A red square'));
      expect(tree, contains('"A paragraph in the section."'));
    },
  );

  test('PDF/UA-1, as veraPDF checks it', () {
    final verapdf = _verapdf;
    if (verapdf == null) {
      markTestSkipped('needs veraPDF');
      return;
    }
    final report =
        Process.runSync(verapdf, [
              '--flavour',
              'ua1',
              '--format',
              'text',
              _convert(),
            ]).stdout
            as String;
    expect(report.trim(), startsWith('PASS'));
  });
}
