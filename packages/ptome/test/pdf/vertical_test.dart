// Vertical writing (`page_writing_mode`): the body's lines run down the
// page, Han and kana upright, columns following to the left.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:ptome/ptome.dart';
import 'package:test/test.dart';

/// Poppler's pdftotext (another one, Windows CI's, reads the text
/// otherwise).
final bool _poppler =
    Process.runSync('which', ['pdftotext']).exitCode == 0 &&
    '${Process.runSync('pdftotext', ['-v']).stderr}'.contains('Poppler');

/// qpdf, which writes a PDF's objects uncompressed.
final bool _qpdf = Process.runSync('which', ['qpdf']).exitCode == 0;

final String _cjkFont = File(
  '../plain_typesetting/test/fonts/notosanscjk-jp-subset.otf',
).absolute.path;

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('vertical_test.'));
  tearDown(() => dir.deleteSync(recursive: true));

  /// [source] converted with the CJK font and [mode]; the PDF's path.
  String pdf(
    String source,
    String mode, {
    Map<String, String>? attributes,
    String theme = '',
  }) {
    final themeFile = File('${dir.path}/theme.yml')
      ..writeAsStringSync('''
extends: default
font:
  catalog:
    merge: true
    JP:
      normal: $_cjkFont
      bold: $_cjkFont
      italic: $_cjkFont
      bold_italic: $_cjkFont
  fallbacks: [JP]
base:
  font_family: JP
page:
  size: A6
  writing_mode: $mode
$theme
''');
    final out = File('${dir.path}/out.pdf')
      ..writeAsBytesSync(
        asciidoc.convertToBytes(
          source,
          backend: Backend.pdf,
          attributes: {
            'pdf-theme': themeFile.path,
            'imagesdir': dir.path,
            'reproducible': '',
            ...?attributes,
          },
        ),
      );
    return out.path;
  }

  /// The words of [path]'s first page, each with its box: left, top,
  /// width, height.
  List<(String, double, double, double, double)> lines(String path) {
    final xml =
        Process.runSync('pdftotext', [
              '-bbox',
              '-f',
              '1',
              '-l',
              '1',
              path,
              '-',
            ], stdoutEncoding: utf8).stdout
            as String;
    return [
      for (final m in RegExp(
        r'<word xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" '
        r'yMax="([\d.]+)">([^<]*)</word>',
      ).allMatches(xml))
        (
          m[5]!,
          double.parse(m[1]!),
          double.parse(m[2]!),
          double.parse(m[3]!) - double.parse(m[1]!),
          double.parse(m[4]!) - double.parse(m[2]!),
        ),
    ];
  }

  final text = '日本語の文章は、単語の間に空白を入れずに書きます。' * 4;

  test('vertical-rl: down a column, the next column to the left', () {
    // (Each upright character its own word to pdftotext, read across.)
    final words = [
      for (final w in lines(pdf(text, 'vertical-rl')))
        if (RegExp('[\u3040-\u30ff\u4e00-\u9fff]').hasMatch(w.$1)) w,
    ];
    final right = words.map((w) => w.$2).reduce((a, b) => a > b ? a : b);
    final column = [
      for (final w in words)
        if ((w.$2 - right).abs() < 1) w,
    ]..sort((a, b) => a.$3.compareTo(b.$3));
    // (The first column the rightmost, read down.)
    expect(column.take(4).map((w) => w.$1).join(), '日本語の');
    final columns = {for (final w in words) w.$2.round()};
    expect(columns.length, greaterThan(3));
  }, skip: _poppler ? false : 'needs pdftotext');

  test('two digits set across the column, an em long (tate-chu-yoko)', () {
    /// How far down the column 日 starts after 月, in ems.
    double gap(String theme) {
      final words = lines(pdf('月10日', 'vertical-rl', theme: theme));
      final month = words.firstWhere((w) => w.$1 == '月');
      final day = words.firstWhere((w) => w.$1 == '日');
      return (day.$3 - month.$3) / month.$5;
    }

    // (月, then 10 an em long, then 日; on its side, a quarter em each
    // side of it and its own length.)
    expect(gap(''), closeTo(2, 0.01));
    expect(gap('base_text_combine_upright: none'), greaterThan(2.2));
    // (Three digits only with `digits 3`; the tcy role any short text.)
    double after(String source, String theme) {
      final words = lines(pdf(source, 'vertical-rl', theme: theme));
      final month = words.firstWhere((w) => w.$1 == '月');
      final day = words.firstWhere((w) => w.$1 == '日');
      return (day.$3 - month.$3) / month.$5;
    }

    expect(
      after('月[.tcy]##10##日', 'base_text_combine_upright: none'),
      closeTo(2, 0.01),
    );
    // (Across only where the font has third-width forms: else on its
    // side, as with `none`.)
    expect(
      after('月151日', 'base_text_combine_upright: digits 3'),
      lessThanOrEqualTo(after('月151日', 'base_text_combine_upright: none')),
    );
  }, skip: _poppler ? false : 'needs pdftotext');

  test("decorations on their languages' sides in the box's own lines", () {
    String content(String lang) {
      final path = pdf(
        '[.underline]#語の# [.line-through]#文章#',
        'vertical-rl',
        attributes: {'lang': lang},
        theme: 'base_text_engine: box',
      );
      return File(path).readAsStringSync(encoding: latin1);
    }

    // (Japanese underlines on the right, Chinese on the left.)
    expect(content('ja'), isNot(content('zh')));
  });

  test('tables and listings stand upright, their text across', () {
    const source =
        '本文です。\n\n|===\n|中央区 |二五\n|===\n\n'
        '----\ncode here\n----\n';
    (String, double, double, double, double) word(
      String text, {
      String theme = '',
    }) =>
        lines(pdf(source, 'vertical-rl', theme: theme))
            .firstWhere((w) => w.$1.contains(text));
    // (Read across: wider than tall.)
    final cell = word('中央区');
    expect(cell.$4, greaterThan(cell.$5 * 2));
    final code = word('code');
    expect(code.$4, greaterThan(code.$5));
    // (`table_writing_mode: vertical`: down the columns, a character a
    // word.)
    final down = word('中', theme: 'table_writing_mode: vertical');
    expect(down.$1, '中');
  }, skip: _poppler ? false : 'needs pdftotext');

  test("a block's own writing mode: vertical-rl in a horizontal page, "
      'horizontal-tb in a vertical one', () {
    final across = lines(
      pdf(
        '横書き。\n\n[verse.vertical-rl]\n____\n古池や\n蛙飛び込む\n____\n\n'
            '終わり。',
        'horizontal-tb',
      ),
    );
    // (The poem's characters each a word, its first column at the right.)
    final ko = across.firstWhere((w) => w.$1 == '古');
    final kawazu = across.firstWhere((w) => w.$1 == '蛙');
    expect(ko.$2, greaterThan(kawazu.$2));
    expect(across.any((w) => w.$1.startsWith('横書き')), isTrue);
    final down = lines(pdf('縦書き。\n\n[.horizontal-tb]\n横の段落です。', 'vertical-rl'));
    expect(down.any((w) => w.$1.contains('横の段落')), isTrue);
  }, skip: _poppler ? false : 'needs pdftotext');

  test('under asciidoctor-compat the lines run across', () {
    final words = lines(
      pdf(text, 'vertical-rl', attributes: {'asciidoctor-compat': 'pdf'}),
    );
    // (A line a word, wider than tall.)
    expect(words.first.$1, startsWith('日本語の'));
    expect(words.first.$4, greaterThan(words.first.$5 * 5));
  }, skip: _poppler ? false : 'needs pdftotext');

  test('vertical-lr: the first column at the left, the next to its right', () {
    final words = [
      for (final w in lines(pdf(text, 'vertical-lr')))
        if (RegExp('[\u3040-\u30ff\u4e00-\u9fff]').hasMatch(w.$1)) w,
    ];
    final left = words.map((w) => w.$2).reduce((a, b) => a < b ? a : b);
    final column = [
      for (final w in words)
        if ((w.$2 - left).abs() < 1) w,
    ]..sort((a, b) => a.$3.compareTo(b.$3));
    expect(column.take(4).map((w) => w.$1).join(), '日本語の');
  }, skip: _poppler ? false : 'needs pdftotext');

  test('an image stands upright on a vertical page, its link around it', () {
    // (A red image four times as wide as tall, framed and linked.)
    File('${dir.path}/wide.png').writeAsBytesSync(
      base64.decode(
        'iVBORw0KGgoAAAANSUhEUgAAACgAAAAKCAIAAABJ+IsHAAAAHUlEQVR42mM8'
        'ISfHMBCAiWGAwKjFoxaPWjz0LQYA/8QBGFYg0fUAAAAASUVORK5CYII=',
      ),
    );
    for (final mode in const ['vertical-rl', 'vertical-lr']) {
      final path = pdf(
        '日本語\n\nimage::wide.png[wide,120,link=https://example.org]\n',
        mode,
        theme: 'image:\n  border_width: 1\n  border_color: 000000',
      );
      final qdf = Process.runSync('qpdf', [
        '--qdf',
        '--object-streams=disable',
        path,
        '-',
      ], stdoutEncoding: latin1);
      final rect = RegExp(
        r'/Rect \[\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)\s+\]',
      ).firstMatch('${qdf.stdout}')!;
      final [x0, y0, x1, y1] = [
        for (var i = 1; i <= 4; i++) double.parse(rect[i]!),
      ];
      // (Upright: as wide as asked across the page, 120 px of 0.75 pt, a
      // quarter as tall.)
      expect(x1 - x0, closeTo(90, 0.5), reason: mode);
      expect(y1 - y0, closeTo(22.5, 0.5), reason: mode);
    }
  }, skip: _qpdf ? false : 'needs qpdf');
}
