// `table_row_group_size` and `table_row_group_gap` (FEAT-kskwtx): a
// table's body rows in groups, space between them, as a table of
// logarithms sets its rows in fives; the rows' baselines read back by
// Poppler, recorded in test/oracles/pdf_table_groups.json.gz
// (test/support/oracles.dart; ORACLES=record asks it again).
@TestOn('vm')
library;

import 'dart:io';

import 'package:ptome/ptome.dart';
import 'package:test/test.dart';

import '../support/oracles.dart';
import '../support/pdf_tools.dart';
import '../vendored_fonts.dart';

late final Oracle _recorded;

/// The tops of the first cells of a six-row table's rows (the header's
/// first), in [theme] over asciidoctor-pdf's.
List<double> _rowTops(Directory dir, String theme) {
  final themeFile = File('${dir.path}/theme.yml')
    ..writeAsStringSync('extends: default\n$theme');
  final pdf = File('${dir.path}/rows.pdf')
    ..writeAsBytesSync(
      asciidoc.convertToBytes(
        '= Rows\n\n[.log,options=header]\n|===\n|N |Log\n'
        '${[for (var i = 1; i <= 6; i++) '|r$i |$i'].join('\n')}\n|===\n',
        backend: Backend.pdf,
        attributes: {'pdf-theme': themeFile.path, 'reproducible': ''},
      ),
    );
  final bbox =
      recordedRunSync(_recorded, 'pdftotext', ['-bbox', pdf.path, '-']).stdout
          as String;
  return [
    for (final m in RegExp(r'yMin="([\d.]+)"[^>]*>(N|r\d)<').allMatches(bbox))
      double.parse(m[1]!),
  ];
}

void main() {
  _recorded = Oracle('pdf_table_groups', compressed: true);
  setUpAll(useVendoredFonts);
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('table_groups.'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('the body rows in pairs, a space between each pair', () {
    final plain = _rowTops(dir, '');
    final grouped = _rowTops(
      dir,
      'table:\n  role:\n    log:\n      row_group_size: 2\n'
      '      row_group_gap: 10\n',
    );
    List<double> steps(List<double> tops) => [
      for (var i = 2; i < tops.length; i++) tops[i] - tops[i - 1],
    ];
    // (Row 1 to 2 the plain pitch; 2 to 3 ten points more; 3 to 4 the
    // plain again.)
    final pitch = steps(plain).first;
    expect(steps(grouped)[0], closeTo(pitch, 0.01));
    expect(steps(grouped)[1], closeTo(pitch + 10, 0.01));
    expect(steps(grouped)[2], closeTo(pitch, 0.01));
    expect(steps(grouped)[3], closeTo(pitch + 10, 0.01));
  });
}
