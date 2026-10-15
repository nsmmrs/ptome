// The kihon-hanmen (JLREQ 2.3, 2.4): `page_hanmen_characters` and
// `page_hanmen_lines` make the text area that many characters long and
// lines deep, centered on the page, the body's lines a character and a
// line gap apart on its grid; on a vertical page the characters run down
// the column and the lines across.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:ptome/ptome.dart';
import 'package:test/test.dart';

import '../support/oracles.dart';
import '../support/pdf_tools.dart';

final String _cjk = File(
  '../plain_typesetting/test/fonts/notosanscjk-jp-subset.otf',
).absolute.path;

/// The tools' runs, recorded (test/oracles/pdf_hanmen.json.gz,
/// test/support/oracles.dart; ORACLES=record asks them again).
late final Oracle _recorded;

void main() {
  _recorded = Oracle('pdf_hanmen', compressed: true);
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('hanmen.'));
  tearDown(() => dir.deleteSync(recursive: true));

  /// The word boxes (left, top, right, bottom) of the source as a PDF in
  /// a kihon-hanmen of 30 characters by 20 lines of 10 points, A5.
  List<(double, double, double, double)> boxes({bool vertical = false}) {
    final theme = File('${dir.path}/theme.yml')
      ..writeAsStringSync('''
extends: default
page:
  size: A5
  hanmen_characters: 30
  hanmen_lines: 20
${vertical ? '  writing_mode: vertical-rl\n' : ''}base:
  font_family: JP
  font_size: 10
font:
  catalog:
    merge: true
    JP:
      normal: $_cjk
      bold: $_cjk
      italic: $_cjk
      bold_italic: $_cjk
''');
    final path = '${dir.path}/out.pdf';
    File(path).writeAsBytesSync(
      asciidoc.convertToBytes(
        '${'日本語の文章を書きます。' * 20}\n\n${'本日は書物の版を読みます。' * 10}\n',
        backend: Backend.pdf,
        attributes: {
          'pdf-theme': theme.path,
          'reproducible': '',
          'nofooter': '',
          'lang': 'ja',
        },
      ),
    );
    final bbox =
        recordedRunSync(_recorded, 'pdftotext', [
              '-bbox',
              path,
              '-',
            ], stdoutEncoding: utf8).stdout
            as String;
    return [
      for (final m in RegExp(
        'xMin="([0-9.]+)" yMin="([0-9.]+)" xMax="([0-9.]+)" yMax="([0-9.]+)"',
      ).allMatches(bbox))
        (
          double.parse(m[1]!),
          double.parse(m[2]!),
          double.parse(m[3]!),
          double.parse(m[4]!),
        ),
    ];
  }

  test('horizontal: 300 points wide, centered, lines 17.5 points apart on '
      'the grid', () {
    final words = boxes();
    // (A5 is 419.53 points wide.)
    final left = words.map((b) => b.$1).reduce((a, b) => a < b ? a : b);
    final right = words.map((b) => b.$3).reduce((a, b) => a > b ? a : b);
    expect(left, closeTo((419.53 - 300) / 2, 0.5));
    expect(right - left, closeTo(300, 0.5));
    final bottoms = {for (final b in words) (b.$4 * 100).round() / 100}.toList()
      ..sort();
    for (final y in bottoms) {
      final steps = (y - bottoms.first) / 17.5;
      expect(steps, closeTo(steps.roundToDouble(), 0.01), reason: '$y');
    }
  });

  test('vertical: 300 points tall, centered, columns 17.5 points apart', () {
    final words = boxes(vertical: true);
    // (A5 is 595.28 points tall.)
    final top = words.map((b) => b.$2).reduce((a, b) => a < b ? a : b);
    final bottom = words.map((b) => b.$4).reduce((a, b) => a > b ? a : b);
    expect(top, closeTo((595.28 - 300) / 2, 0.5));
    expect(bottom - top, closeTo(300, 0.5));
    final columns = {for (final b in words) (b.$3 * 100).round() / 100}.toList()
      ..sort();
    for (final x in columns) {
      final steps = (columns.last - x) / 17.5;
      expect(steps, closeTo(steps.roundToDouble(), 0.01), reason: '$x');
    }
  });
}
