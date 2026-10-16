// `:pdf-ua:`: a tagged PDF (FEAT-cs3j22), its structure tree read back
// with Poppler's pdfinfo and checked against PDF/UA-1 by veraPDF, their
// answers recorded in test/oracles/pdf_pdf_ua.json.gz
// (test/support/oracles.dart; ORACLES=record asks them again, veraPDF
// from VERAPDF, else the work folder, else the path).
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:ptome/src/internal.dart';
import 'package:ptome/src/pdf/pdf.dart';
import 'package:test/test.dart';

import '../support/oracles.dart';
import '../support/pdf_tools.dart';

import '../vendored_fonts.dart';

late Directory _dir;

late final Oracle _recorded;

/// veraPDF, which its answers depend on.
const String _veraPdfVersion = 'veraPDF 1.30.3';

/// veraPDF's command: VERAPDF, else the work folder's, else the path's.
String get _verapdf =>
    Platform.environment['VERAPDF'] ??
    ['${Platform.environment['HOME']}/.cache/asciidart-work/verapdf/verapdf']
        .firstWhere((path) => File(path).existsSync(), orElse: () => 'verapdf');

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

Last words, and [lang=fr]#quelques mots# in French.

[lang=de]
Ein Absatz auf Deutsch.
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
  _recorded = Oracle('pdf_pdf_ua', compressed: true);
  setUpAll(useVendoredFonts);
  setUpAll(() {
    registerPdf();
    _dir = Directory.systemTemp.createTempSync('ptome-ua.');
  });
  tearDownAll(() => _dir.deleteSync(recursive: true));

  test(
    'the structure tree: headings, paragraphs, lists, a table, a figure',
    () {
      final tree =
          recordedRunSync(_recorded, 'pdfinfo', [
                '-struct-text',
                _convert(),
              ]).stdout
              as String;
      final roles = [
        for (final line in tree.split('\n'))
          if (RegExp(r'^\s*([A-Z][A-Za-z0-9]*)').firstMatch(line) case final m?)
            m[1]!,
      ];
      expect(roles.first, 'Document', reason: tree);
      expect(
        roles,
        containsAllInOrder([
          'H1', 'P', 'Link', 'H2', 'P', 'L', 'LI', 'LBody', 'P', //
          'Table', 'TR', 'TH', 'TD', 'Figure', 'H3', 'P',
        ]),
        reason: tree,
      );
      expect(tree, contains('"A paragraph in the section."'));
    },
  );

  test('an image with an empty alternate text is decorative: an artifact, '
      "not a figure (PDF/UA-1 7.3; a printing's spacers)", () {
    final input = File('${_dir.path}/decorative.adoc')
      ..writeAsStringSync(
        '= Decorative\n:pdf-ua:\n:lang: en\n\nA paragraph.\n\n'
        'image::${Directory.current.path}/test/pdf/fixtures/images/red.png'
        '[""]\n\nAnother.\n',
      );
    final out = '${input.path}.pdf';
    convertFile(
      input.path,
      AsciidoctorOptions(
        safe: SafeMode.unsafe,
        backend: 'pdf',
        toFile: out,
        attributes: const {'reproducible': '', 'pdf-theme': 'default'},
      ),
    );
    final tree =
        recordedRunSync(_recorded, 'pdfinfo', ['-struct-text', out]).stdout
            as String;
    expect(tree, isNot(contains('Figure')), reason: tree);
    expect(tree, contains('"Another."'));
  });

  test("a block's and a span's own language marked (PDF/UA-1 7.2)", () {
    final out = '${_dir.path}/lang.pdf';
    recordedRunSync(_recorded, 'qpdf', [
      '--qdf',
      '--object-streams=disable',
      _convert(),
      out,
    ]);
    final pdf = latin1.decode(File(out).readAsBytesSync());
    expect(pdf, contains('/Span << /Lang (fr) >> BDC'));
    expect(
      RegExp(r'/Lang \(de\)[^>]*/S /P|/S /P[^>]*/Lang \(de\)').hasMatch(pdf),
      isTrue,
    );
  });

  test('a cell spanning rows or columns says so (PDF/UA-1 7.2)', () {
    final input = File('${_dir.path}/spans.adoc')
      ..writeAsStringSync(
        '= Spans\n:pdf-ua:\n\n[cols="1,1,1"]\n|===\n|A\n.2+|brace\n|B\n\n'
        '|C\n|D\n\n3+|across\n|===\n',
      );
    final out = '${input.path}.pdf';
    convertFile(
      input.path,
      AsciidoctorOptions(
        safe: SafeMode.unsafe,
        backend: 'pdf',
        toFile: out,
        attributes: const {'reproducible': '', 'pdf-theme': 'default'},
      ),
    );
    final pdf = File(out).readAsBytesSync();
    final qdf = qpdfQdf(_recorded, pdf);
    expect(qdf, contains('/RowSpan 2'));
    expect(qdf, contains('/ColSpan 3'));
    final report = _recorded.answer(
      'PDF/UA-1 spans',
      inputs: [_veraPdfVersion, pdf],
      oracle: () =>
          Process.runSync(_verapdf, [
                '--flavour',
                'ua1',
                '--format',
                'text',
                out,
              ]).stdout
              as String,
    );
    expect(report.trim(), startsWith('PASS'));
  });

  test('a row taller than a page, its cells split, goes on in its row '
      '(BUG-l91thh)', () {
    // (A row whose cells are taller than an A6 page, and one spanning it
    // and the next: every piece carried to the next page.)
    final long = 'Words to fill the page and more. ' * 120;
    final input = File('${_dir.path}/split-row.adoc')
      ..writeAsStringSync(
        '= Split\n:pdf-ua:\n\n[%noheader,cols="1,1"]\n|===\n'
        '|$long\n.2+|$long\n\n|The next row.\n|===\n',
      );
    final out = '${input.path}.pdf';
    convertFile(
      input.path,
      AsciidoctorOptions(
        safe: SafeMode.unsafe,
        backend: 'pdf',
        toFile: out,
        attributes: const {
          'reproducible': '',
          'pdf-theme': 'default',
          'pdf-page-size': 'A6',
        },
      ),
    );
    final pdf = File(out).readAsBytesSync();
    final qdf = qpdfQdf(_recorded, pdf);
    expect(RegExp(r'/S /TR\b').allMatches(qdf), hasLength(2));
    final report = _recorded.answer(
      'PDF/UA-1 split row',
      inputs: [_veraPdfVersion, pdf],
      oracle: () =>
          Process.runSync(_verapdf, [
                '--flavour',
                'ua1',
                '--format',
                'text',
                out,
              ]).stdout
              as String,
    );
    expect(report.trim(), startsWith('PASS'));
  });

  test("a character the math font lacks set from the theme's base font "
      '(BUG-rvh0f1)', () {
    // (The first formula in a chapter's title, laid out before the body's
    // font is set; the degree sign the math font lacks in the text's.)
    final input = File('${_dir.path}/math-fallback.adoc')
      ..writeAsStringSync(
        '= Math\n:pdf-ua:\n:doctype: book\n:stem: asciimath\n\n'
        '== One stem:[x]\n\nA temperature stem:["20°C"].\n',
      );
    final out = '${input.path}.pdf';
    convertFile(
      input.path,
      AsciidoctorOptions(
        safe: SafeMode.unsafe,
        backend: 'pdf',
        toFile: out,
        attributes: const {'reproducible': '', 'pdf-theme': 'default'},
      ),
    );
    final pdf = File(out).readAsBytesSync();
    final report = _recorded.answer(
      'PDF/UA-1 math fallback',
      inputs: [_veraPdfVersion, pdf],
      oracle: () =>
          Process.runSync(_verapdf, [
                '--flavour',
                'ua1',
                '--format',
                'text',
                out,
              ]).stdout
              as String,
    );
    expect(report.trim(), startsWith('PASS'), reason: report);
  });

  test('PDF/UA-1, as veraPDF checks it', () {
    final pdf = File(_convert()).readAsBytesSync();
    final report = _recorded.answer(
      'PDF/UA-1',
      inputs: [_veraPdfVersion, pdf],
      oracle: () {
        final dir = Directory.systemTemp.createTempSync('verapdf.');
        try {
          final file = File('${dir.path}/ua.pdf')..writeAsBytesSync(pdf);
          return Process.runSync(_verapdf, [
                '--flavour',
                'ua1',
                '--format',
                'text',
                file.path,
              ]).stdout
              as String;
        } finally {
          dir.deleteSync(recursive: true);
        }
      },
    );
    // (veraPDF names the file it checked: the verdict comes first.)
    expect(report.trim(), startsWith('PASS'));
  });
}
