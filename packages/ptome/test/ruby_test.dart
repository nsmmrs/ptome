// Ruby (`ruby:漢字[かんじ]`, Ptome's syntax) in each format, and the
// emphasis marks a role's `text_emphasis` sets in the PDF.
import 'dart:io';

import 'package:ptome/ptome.dart';
import 'package:test/test.dart';

/// Poppler's pdftotext.
final bool _poppler = Process.runSync('which', ['pdftotext']).exitCode == 0;

/// A Noto Sans CJK subset with kana and the Han characters used here.
final String _cjkFont = File(
  '../plain_typesetting/test/fonts/notosanscjk-jp-subset.otf',
).absolute.path;

void main() {
  test('group ruby: the reading of the whole base', () {
    expect(
      asciidoc.convert('ruby:漢字[かんじ]'),
      contains('<p><ruby>漢字<rp>(</rp><rt>かんじ</rt><rp>)</rp></ruby></p>'),
    );
  });

  test('mono ruby: a reading a character, separated by spaces', () {
    expect(
      asciidoc.convert('ruby:東京[とう きょう]'),
      contains(
        '<ruby>東<rp>(</rp><rt>とう</rt><rp>)</rp>'
        '京<rp>(</rp><rt>きょう</rt><rp>)</rp></ruby>',
      ),
    );
  });

  test('as many readings as characters or not: group ruby', () {
    expect(
      asciidoc.convert('ruby:東京都[とう きょう]'),
      contains('<ruby>東京都<rp>(</rp><rt>とう きょう</rt><rp>)</rp></ruby>'),
    );
  });

  test('DocBook and man pages: the reading after the base', () {
    expect(
      asciidoc.convert('ruby:漢字[かんじ]', backend: Backend.docbook5),
      contains('漢字(かんじ)'),
    );
  });

  test('escaped, or under asciidoctor-compat, it is text', () {
    expect(asciidoc.convert(r'\ruby:漢字[かんじ]'), contains('ruby:漢字[かんじ]'));
    expect(
      asciidoc.convert(
        'ruby:漢字[かんじ]',
        attributes: {'asciidoctor-compat': 'html'},
      ),
      contains('ruby:漢字[かんじ]'),
    );
  });

  test('the API gives its base and reading', () {
    final doc = asciidoc.parse('ruby:漢字[かんじ]');
    final ruby = (doc.blocks.single as Paragraph).inlines
        .whereType<Ruby>()
        .single;
    expect((ruby.base, ruby.reading, ruby.plainText), ('漢字', 'かんじ', '漢字'));
  });

  group('PDF', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('ruby_test.'));
    tearDown(() => dir.deleteSync(recursive: true));

    String pdfText(String source) {
      final theme = File('${dir.path}/theme.yml')
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
role:
  bouten:
    text_emphasis: sesame
''');
      final bytes = asciidoc.convertToBytes(
        source,
        backend: Backend.pdf,
        attributes: {'pdf-theme': theme.path, 'reproducible': ''},
      );
      final pdf = File('${dir.path}/out.pdf')..writeAsBytesSync(bytes);
      if (!_poppler) return '';
      return Process.runSync('pdftotext', [pdf.path, '-']).stdout as String;
    }

    test('ruby is set above its base and copied as the base', () {
      final text = pdfText('の読み方と ruby:東京[とう きょう]、それに ruby:明日[あした]。');
      if (!_poppler) return;
      expect(text, contains('東京'));
      expect(text, contains('明日'));
      expect(text, isNot(contains('きょう')));
    }, skip: _poppler ? false : 'needs pdftotext');

    test('emphasis marks read as nothing', () {
      final text = pdfText('日本語の[.bouten]##文章##は、書きます。');
      if (!_poppler) return;
      expect(text, contains('日本語の文章は、書きます。'));
    }, skip: _poppler ? false : 'needs pdftotext');
  });
}
