// French text's no-break spaces before high punctuation and inside
// guillemets (the Imprimerie nationale's Lexique; the OQLF for Canada).
import 'package:ptome/ptome.dart';
import 'package:test/test.dart';

void main() {
  String html(String source, Map<String, String> attributes) =>
      asciidoc.convert(source, attributes: attributes);

  test('France: before ; ! ? a narrow no-break space, before : a no-break '
      'space, and inside guillemets', () {
    expect(
      html('Vraiment ? Oui ! Note : voici; « ici ».', {'lang': 'fr'}),
      contains(
        'Vraiment&#8239;? Oui&#8239;! Note&#160;: voici&#8239;; '
        '«&#160;ici&#160;».',
      ),
    );
  });

  test("typographic quotes in French's guillemets, spaced", () {
    expect(html('"`ici`"', {'lang': 'fr'}), contains('«&#160;ici&#160;»'));
  });

  test('Canada: before : and inside guillemets alone', () {
    expect(
      html('Vraiment? Oui! Note : « ici ».', {'lang': 'fr-CA'}),
      contains('Vraiment? Oui! Note&#160;: «&#160;ici&#160;».'),
    );
  });

  test("a block's language", () {
    expect(
      html('[lang=fr]\nOui !\n\nYes!', {'lang': 'en'}),
      allOf(contains('Oui&#8239;!'), contains('Yes!')),
    );
  });

  test('URLs, times, scopes, entities and markup are left alone', () {
    final out = html(
      'Voir https://exemple.fr/page?x=1 à 10:30, std::vector, A & B ; '
      '*gras* !',
      {'lang': 'fr'},
    );
    expect(out, contains('href="https://exemple.fr/page?x=1"'));
    expect(out, contains('10:30, std::vector, A &amp; B&#8239;; '));
    expect(out, contains('<strong>gras</strong>&#8239;!'));
  });

  test('spaces already typed as no-break spaces stay single', () {
    expect(
      html('Oui\u202f! Note\u00a0: «\u00a0ici\u00a0» ‹ là › « ', {
        'lang': 'fr',
      }),
      allOf(
        contains('Oui\u202f! Note\u00a0: «\u00a0ici\u00a0»'),
        contains('‹&#160;là&#160;›'),
        isNot(contains('«&#160;\u00a0')),
      ),
    );
  });

  test('verbatim text is left alone', () {
    expect(
      html(' code ? : ;', {'lang': 'fr'}),
      contains('<pre>code ? : ;</pre>'),
    );
  });

  test('other languages, and asciidoctor-compat: none', () {
    for (final attributes in [
      {'lang': 'en'},
      <String, String>{},
      {'lang': 'fr', 'asciidoctor-compat': ''},
    ]) {
      expect(
        html('Vraiment ? Note : oui.', attributes),
        contains('Vraiment ? Note : oui.'),
      );
    }
  });

  test("a man page's are roff's unbreakable spaces", () {
    final roff = asciidoc.convert(
      '= cmd(1)\n:lang: fr\n\n== NAME\n\ncmd - essai\n\n'
      '== DESCRIPTION\n\nVraiment ? Note : « ici ».\n',
      backend: Backend.manpage,
      doctype: Doctype.manpage,
    );
    expect(roff, contains(r'Vraiment\~? Note\~: «\~ici\~».'));
  });
}
