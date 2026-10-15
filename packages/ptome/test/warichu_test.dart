// Warichu (`warichu:[注]`, Ptome's syntax): an inline cutting note, in the
// PDF two lines of half the text's size within the line (JLREQ 3.4), as
// near the same length as the line's breaks allow, the second never the
// longer, between the line's parentheses; in HTML and EPUB a span, in
// DocBook and man pages the note in parentheses; text under
// asciidoctor-compat. On a vertical page it and ruby stand upright.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:plain_pdf/plain_pdf.dart';
import 'package:ptome/ptome.dart';
import 'package:ptome/src/pdf/fonts.dart';
import 'package:ptome/src/pdf/warichu.dart';
import 'package:test/test.dart';

import 'support/oracles.dart';
import 'support/pdf_tools.dart';

final String _cjkPath = File(
  '../plain_typesetting/test/fonts/notosanscjk-jp-subset.otf',
).absolute.path;

/// Noto Sans CJK, subset: every character a full em wide.
final TrueTypeFont _face = TrueTypeFont(
  'JP',
  'normal',
  EmbeddedFont.parse(File(_cjkPath).readAsBytesSync()),
);

/// The tools' runs, recorded (test/oracles/warichu.json.gz,
/// test/support/oracles.dart; ORACLES=record asks them again).
late final Oracle _recorded;

void main() {
  _recorded = Oracle('warichu', compressed: true);
  test('HTML, EPUB, DocBook and man pages', () {
    expect(
      asciidoc.convert('本文warichu:[注の文]です。'),
      contains('本文<span class="warichu">（注の文）</span>です。'),
    );
    expect(
      asciidoc.convert('本文warichu:[注の文]です。', backend: Backend.docbook5),
      contains('本文（注の文）です。'),
    );
    expect(
      asciidoc.convert(r'本文\warichu:[注]です。'),
      contains('本文warichu:[注]です。'),
    );
    expect(
      asciidoc.convert(
        '本文warichu:[注]です。',
        attributes: {'asciidoctor-compat': ''},
      ),
      contains('warichu:[注]'),
    );
  });

  test('cut into cells of two characters, the parentheses on the ends', () {
    final cells = InlineWarichu.cells('いのいのい');
    expect([for (final c in cells) c.text], ['いの', 'いの', 'い']);
    expect([for (final c in cells) c.opens], [true, false, false]);
    expect([for (final c in cells) c.closes], [false, false, true]);
    // (Each half the size along the line, the parentheses' ink halves on
    // the ends: the note's two lines, three and two characters, take
    // 10 + 30 + 10 points.)
    expect(
      cells.map((c) => c.at(_face, 20).width).reduce((a, b) => a + b),
      10 + 30 + 10,
    );
    // (No break inside a cell's segment: before the full stop.)
    expect(
      [for (final c in InlineWarichu.cells('いの。いの')) c.text],
      ['いの。', 'いの'],
    );
  });

  test('PDF: a note longer than the rest of its line fills it and goes on at '
      "the next line's start", () {
    final dir = Directory.systemTemp.createTempSync('warichu.');
    addTearDown(() => dir.deleteSync(recursive: true));
    final theme = File('${dir.path}/theme.yml')
      ..writeAsStringSync('''
extends: default
page:
  size: [200, 200]
  margin: [10, 20, 10, 20]
base:
  font_family: JP
  font_size: 10
  text_align: left
font:
  catalog:
    merge: true
    JP:
      normal: $_cjkPath
      bold: $_cjkPath
      italic: $_cjkPath
      bold_italic: $_cjkPath
''');
    final path = '${dir.path}/out.pdf';
    File(path).writeAsBytesSync(
      asciidoc.convertToBytes(
        'のののwarichu:[${'い' * 80}]のの。\n',
        backend: Backend.pdf,
        attributes: {
          'pdf-theme': theme.path,
          'reproducible': '',
          'nofooter': '',
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
    final words = [
      for (final m in RegExp(
        'xMin="([0-9.]+)" yMin="([0-9.]+)" xMax="([0-9.]+)"[^>]*>([^<]*)<',
      ).allMatches(bbox))
        (double.parse(m[1]!), double.parse(m[2]!), double.parse(m[3]!), m[4]!),
    ];
    // (The note's first part, copied in its opening parenthesis, ends at
    // the line's end, 180 points; the rest starts the next line at 20.)
    final first = words.firstWhere((w) => w.$4.contains('（'));
    final rest = words.firstWhere((w) => w.$4.contains('）'));
    expect(first.$3, closeTo(180, 1));
    expect(rest.$1, closeTo(20, 1));
    expect(rest.$2, greaterThan(first.$2));
    expect('${first.$4}${rest.$4}'.replaceAll(RegExp('[^い]'), ''), 'い' * 80);
  });

  test('PDF: copied as the note in parentheses', () {
    final dir = Directory.systemTemp.createTempSync('warichu.');
    addTearDown(() => dir.deleteSync(recursive: true));
    final theme = File('${dir.path}/theme.yml')
      ..writeAsStringSync('''
extends: default
base:
  font_family: JP
font:
  catalog:
    merge: true
    JP:
      normal: $_cjkPath
      bold: $_cjkPath
      italic: $_cjkPath
      bold_italic: $_cjkPath
''');
    final path = '${dir.path}/out.pdf';
    File(path).writeAsBytesSync(
      asciidoc.convertToBytes(
        '本文warichu:[注の文]です。',
        backend: Backend.pdf,
        attributes: {'pdf-theme': theme.path, 'reproducible': ''},
      ),
    );
    final text =
        recordedRunSync(_recorded, 'pdftotext', [
              path,
              '-',
            ], stdoutEncoding: utf8).stdout
            as String;
    expect(text.replaceAll('\n', ''), contains('（注の文）'));
  });

  test('on a vertical page, ruby and warichu stand upright', () {
    final dir = Directory.systemTemp.createTempSync('warichu.');
    addTearDown(() => dir.deleteSync(recursive: true));
    final theme = File('${dir.path}/theme.yml')
      ..writeAsStringSync('''
extends: default
page:
  writing_mode: vertical-rl
base:
  font_family: JP
font:
  catalog:
    merge: true
    JP:
      normal: $_cjkPath
      bold: $_cjkPath
      italic: $_cjkPath
      bold_italic: $_cjkPath
''');
    int quarterTurns(String source) {
      final path = '${dir.path}/out.pdf';
      File(path).writeAsBytesSync(
        asciidoc.convertToBytes(
          source,
          backend: Backend.pdf,
          attributes: {
            'pdf-theme': theme.path,
            'reproducible': '',
            'nofooter': '',
          },
        ),
      );
      recordedRunSync(_recorded, 'qpdf', [
        '--qdf',
        '--object-streams=disable',
        path,
        '${dir.path}/plain.pdf',
      ]);
      final plain = latin1.decode(
        File('${dir.path}/plain.pdf').readAsBytesSync(),
      );
      // (Each upright character is drawn turned a quarter turn back.)
      return RegExp(r'0 1 -1 0 [-\d.]+ [-\d.]+ cm').allMatches(plain).length;
    }

    // (The base and its reading; the note and its parentheses.)
    expect(quarterTurns('ruby:字[じ]'), greaterThanOrEqualTo(2));
    expect(quarterTurns('warichu:[あい]'), greaterThanOrEqualTo(2));
  });
}
