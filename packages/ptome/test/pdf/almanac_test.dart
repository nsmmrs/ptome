// What an almanac's pages take (Poor Richard's Almanack in the showcase):
// a fallback font's text counted as the text's own font for its line's
// height (`font_fallback_metrics: base`, FEAT-ml7z96), and a tagged book
// without a title page whose first heading is H1 (BUG-ljj0fk). Read back
// by Poppler and qpdf, recorded in test/oracles/pdf_almanac.json.gz
// (test/support/oracles.dart; ORACLES=record asks them again).
@TestOn('vm')
library;

import 'dart:io';

import 'package:ptome/ptome.dart';
import 'package:test/test.dart';

import '../support/oracles.dart';
import '../support/pdf_tools.dart';
import '../vendored_fonts.dart';

late final Oracle _recorded;

late Directory _scratch;

final String _fonts = Directory('../plain_typesetting/test/fonts')
    .absolute
    .path;

/// [source] as a PDF in asciidoctor-pdf's theme with [theme] over it.
File _pdf(String source, String theme) {
  final n = _scratch.listSync().length;
  final themeFile = File('${_scratch.path}/t$n-theme.yml')
    ..writeAsStringSync('extends: default\n$theme');
  return File('${_scratch.path}/d$n.pdf')..writeAsBytesSync(
    asciidoc.convertToBytes(
      source,
      backend: Backend.pdf,
      attributes: {
        'pdf-theme': themeFile.path,
        'pdf-fontsdir': '$_fonts,GEM_FONTS_DIR',
        'reproducible': '',
      },
    ),
  );
}

/// The tops of the lines of [pdf]'s first page that start with "line".
List<double> _lineTops(File pdf) {
  final xml =
      recordedRunSync(_recorded, 'pdftotext', ['-bbox', pdf.path, '-']).stdout
          as String;
  return [
    for (final m in RegExp(
      r'yMin="([\d.]+)" xMax="[\d.]+" yMax="[\d.]+">line<',
    ).allMatches(xml))
      double.parse(m[1]!),
  ];
}

const String _fallback = '''
font:
  catalog:
    Naskh:
      normal: notonaskharabic-subset.ttf
  fallbacks: [Naskh]
''';

const String _lines =
    ':nofooter:\n\n[%hardbreaks]\nline one\nline نص two\nline three\n'
    'line four\n';

void main() {
  _recorded = Oracle('pdf_almanac', compressed: true);
  setUpAll(() {
    useVendoredFonts();
    _scratch = Directory.systemTemp.createTempSync('ptome-almanac.');
  });
  tearDownAll(() => _scratch.deleteSync(recursive: true));

  test("a fallback font's text makes its line taller, unless counted as "
      "the text's font", () {
    List<double> steps(List<double> tops) => [
      for (var i = 1; i < tops.length; i++) tops[i] - tops[i - 1],
    ];
    final own = steps(_lineTops(_pdf(_lines, _fallback)));
    final base = steps(
      _lineTops(_pdf(_lines, '$_fallback  fallback_metrics: base\n')),
    );
    expect(own, hasLength(3));
    // (The Arabic's line deeper than the others by its font's metrics.)
    expect(own[1], greaterThan(own[2] + 0.5));
    // (Counted as Noto Serif: the lines evenly spaced.)
    expect(base[0], closeTo(base[2], 0.01));
    expect(base[1], closeTo(base[2], 0.01));
  });

  test('a tagged book without a title page, heading_tag_shift: its first '
      'heading H1', () {
    final content = qpdfQdf(
      _recorded,
      _pdf(
        '= Doc\n:doctype: book\n:notitle:\n:pdf-ua:\n\n== One\n\nText.\n\n'
            '=== One A\n\nText.\n\n== Two\n\nText.\n',
        'heading:\n  tag_shift: true\n',
      ).readAsBytesSync(),
    );
    final headings = [
      for (final m in RegExp(r'/S /(H\d)\b').allMatches(content)) m[1]!,
    ];
    expect(headings, ['H1', 'H2', 'H1']);
  });

  test('without heading_tag_shift, the tags as before', () {
    final content = qpdfQdf(
      _recorded,
      _pdf(
        '= Doc\n:doctype: book\n:notitle:\n:pdf-ua:\n\n== One\n\nText.\n\n'
            '=== One A\n\nText.\n\n== Two\n\nText.\n',
        '',
      ).readAsBytesSync(),
    );
    expect(
      [for (final m in RegExp(r'/S /(H\d)\b').allMatches(content)) m[1]!],
      ['H2', 'H3', 'H2'],
    );
  });
}
