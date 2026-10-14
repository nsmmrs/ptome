// Ruby (`ruby:漢字[かんじ]`, Ptome's syntax) in each format (the PDF's in
// test/pdf/ruby_test.dart).
import 'package:ptome/ptome.dart';
import 'package:test/test.dart';

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
}
