// `heading_h<n>_initial_skip_roles`: a paragraph with one of the roles
// passes a section's initial on to the next, as a prayer book's rubric
// does to the prayer after it; the words read back by Poppler, recorded
// in test/oracles/pdf_initial_skip.json.gz (test/support/oracles.dart;
// ORACLES=record asks it again).
@TestOn('vm')
library;

import 'dart:io';

import 'package:ptome/ptome.dart';
import 'package:test/test.dart';

import '../support/oracles.dart';
import '../support/pdf_tools.dart';
import '../vendored_fonts.dart';

late final Oracle _recorded;

/// The words of the first page, with the theme's [skip] line.
List<String> _words(Directory dir, String skip) {
  final theme = File('${dir.path}/theme.yml')
    ..writeAsStringSync(
      'extends: default\nheading:\n  h2:\n    initial_lines: 2\n$skip',
    );
  final pdf = File('${dir.path}/office.pdf')
    ..writeAsBytesSync(
      asciidoc.convertToBytes(
        '= Book\n:doctype: book\n\n== The Litany\n\n[.rubric]\n'
        'Here followeth the Litany.\n\nOGOD the Father, of heaven.\n',
        backend: Backend.pdf,
        attributes: {'pdf-theme': theme.path, 'reproducible': ''},
      ),
    );
  final text =
      recordedRunSync(_recorded, 'pdftotext', ['-f', '2', pdf.path, '-']).stdout
          as String;
  return text.split(RegExp(r'\s+'));
}

void main() {
  _recorded = Oracle('pdf_initial_skip', compressed: true);
  setUpAll(useVendoredFonts);
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('initial_skip.'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('the rubric passes the initial on to the prayer', () {
    final plain = _words(dir, '');
    expect(plain, contains('ere'), reason: 'the rubric takes the initial');
    final skipped = _words(dir, '    initial_skip_roles: [rubric]\n');
    expect(skipped, contains('Here'));
    expect(skipped, contains('GOD'), reason: 'the prayer takes it');
  });
}
