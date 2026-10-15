// A paragraph's drop initial beside a floated image (BUG-qqz54w): the
// initial drawn and the first lines set in beside it, as without the
// image; read back by Poppler, recorded in
// test/oracles/pdf_float_initial.json.gz (test/support/oracles.dart;
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

late Directory _scratch;

const String _square =
    '<svg xmlns="http://www.w3.org/2000/svg" width="120" height="120" '
    'viewBox="0 0 120 120"><rect width="120" height="120"/></svg>';

const String _words =
    'On a given finite straight line to describe an equilateral '
    'triangle, a paragraph long enough to be three lines deep at the '
    'least beside the image, so that its initial has room.';

/// Each word of the document with the image floated to [side] and the
/// paragraph after it, with its box (left, top, right, bottom).
Map<String, List<double>> _wordsBeside(String side) {
  final dir = Directory('${_scratch.path}/$side')..createSync();
  File('${dir.path}/square.svg').writeAsStringSync(_square);
  final theme = File('${dir.path}/initial-theme.yml')
    ..writeAsStringSync(
      'extends: default\nrole:\n  dropcap:\n    drop_lines: 3\n',
    );
  final pdf = File('${dir.path}/doc.pdf')
    ..writeAsBytesSync(
      asciidoc.convertToBytes(
        '= Doc\n:nofooter:\n\nimage::square.svg[A square,float=$side]\n\n'
        '[.dropcap]\n$_words\n',
        backend: Backend.pdf,
        path: '${dir.path}/doc.adoc',
        attributes: {'pdf-theme': theme.path, 'reproducible': ''},
      ),
    );
  final xml =
      recordedRunSync(_recorded, 'pdftotext', ['-bbox', pdf.path, '-']).stdout
          as String;
  return {
    for (final m in RegExp(
      r'xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" yMax="([\d.]+)">'
      '([^<]*)<',
    ).allMatches(xml))
      m[5]!: [for (var i = 1; i <= 4; i++) double.parse(m[i]!)],
  };
}

void main() {
  _recorded = Oracle('pdf_float_initial', compressed: true);
  setUpAll(() {
    useVendoredFonts();
    _scratch = Directory.systemTemp.createTempSync('ptome-float-initial.');
  });
  tearDownAll(() => _scratch.deleteSync(recursive: true));

  for (final side in ['right', 'left']) {
    test('the initial beside the image floated $side', () {
      final words = _wordsBeside(side);
      final initial = words['O'];
      expect(initial, isNotNull, reason: 'the initial is drawn');
      // (Taller than a line, the first word set in after it.)
      expect(initial![3] - initial[1], greaterThan(20));
      expect(words['n']![0], greaterThan(initial[2]));
    });
  }
}
