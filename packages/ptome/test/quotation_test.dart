// AsciiDoc's typographic quotes in the marks of the text's language
// (CLDR's), in every format but under asciidoctor-compat.
import 'package:ptome/ptome.dart';
import 'package:test/test.dart';

void main() {
  const source = '"`Hallo`" und \'`Welt`\'.';

  test("HTML: the document's and a block's language", () {
    expect(
      asciidoc.convert(source, attributes: {'lang': 'de'}),
      contains('„Hallo“ und ‚Welt‘.'),
    );
    expect(
      asciidoc.convert('[lang=ja]\n"`今日は`"', attributes: {'lang': 'de'}),
      contains('「今日は」'),
    );
    expect(
      asciidoc.convert(source, attributes: {'lang': 'fr-CA'}),
      contains('«&#160;Hallo&#160;» und ”Welt“.'),
    );
  });

  test("English, no language, or asciidoctor-compat: Asciidoctor's", () {
    for (final attributes in [
      <String, String>{},
      {'lang': 'en'},
      {'lang': 'de', 'asciidoctor-compat': ''},
    ]) {
      expect(
        asciidoc.convert(source, attributes: attributes),
        contains('&#8220;Hallo&#8221; und &#8216;Welt&#8217;.'),
      );
    }
  });

  test('a man page writes them as Unicode escapes', () {
    final roff = asciidoc.convert(
      '= cmd(1)\n:lang: de\n\n== NAME\n\ncmd - a command\n\n'
      '== SYNOPSIS\n\n$source\n',
      backend: Backend.manpage,
      doctype: Doctype.manpage,
    );
    expect(roff, contains(r'\[u201E]Hallo\[u201C] und \[u201A]Welt\[u2018].'));
  });
}
