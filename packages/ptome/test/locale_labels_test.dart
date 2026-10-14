// The generated text in the document's language: Asciidoctor's locale
// files read from `lang`, the author's own labels kept; the index's
// cross-reference words; none of it under asciidoctor-compat.
import 'package:ptome/ptome.dart';
import 'package:ptome/src/locale_labels.dart';
import 'package:test/test.dart';

const String _source = '''
= Book
:toc:

== One

.Cat
image::cat.png[]

.Data
|===
|a
|===

NOTE: A note.

[appendix]
== Extra
''';

void main() {
  String html(String source, Map<String, String> attributes) =>
      asciidoc.convert(source, standalone: true, attributes: attributes);

  test("a Japanese document's labels in Japanese", () {
    final out = html(_source, {'lang': 'ja'});
    expect(out, contains('<div id="toctitle">目次</div>'));
    expect(out, contains('<div class="title">図 1. Cat</div>'));
    expect(out, contains('<caption class="title">表 1. Data</caption>'));
    expect(out, contains('<div class="title">注記</div>'));
    expect(out, contains('付録 A: Extra'));
  });

  test('the language set in the header', () {
    final out = html(_source.replaceFirst(':toc:', ':toc:\n:lang: de'), {});
    expect(out, contains('<div id="toctitle">Inhaltsverzeichnis</div>'));
    expect(out, contains('Abbildung 1. Cat'));
  });

  test("the author's labels win, in the header or from the API", () {
    final out = html(
      _source.replaceFirst(':toc:', ':toc:\n:figure-caption: Abb.'),
      {'lang': 'de', 'table-caption': 'Tab.'},
    );
    expect(out, contains('Abb. 1. Cat'));
    expect(out, contains('Tab. 1. Data'));
    expect(out, contains('Inhaltsverzeichnis'));
  });

  test('regions and scripts choose their file', () {
    expect(localeFileFor('zh'), 'locale/attributes-zh_CN.adoc');
    expect(localeFileFor('zh-Hans-CN'), 'locale/attributes-zh_CN.adoc');
    expect(localeFileFor('zh-Hant'), 'locale/attributes-zh_TW.adoc');
    expect(localeFileFor('zh-HK'), 'locale/attributes-zh_TW.adoc');
    expect(localeFileFor('sr-Latn-RS'), 'locale/attributes-sr_Latn.adoc');
    expect(localeFileFor('sr'), 'locale/attributes-sr.adoc');
    expect(localeFileFor('pt-BR'), 'locale/attributes-pt_BR.adoc');
    expect(localeFileFor('pt-PT'), 'locale/attributes-pt.adoc');
    expect(localeFileFor('no'), 'locale/attributes-nb.adoc');
    expect(localeFileFor('fr_CA'), 'locale/attributes-fr.adoc');
    expect(localeFileFor('en-GB'), isNull);
    expect(localeFileFor('he'), isNull);
    expect(html(_source, {'lang': 'zh-TW'}), contains('目錄'));
    expect(html(_source, {'lang': 'zh'}), contains('目录'));
  });

  test('a language without a locale file keeps the English labels', () {
    expect(html(_source, {'lang': 'he'}), contains('Table of Contents'));
  });

  test('an entry under ifdef applies only when its attribute is set', () {
    const listing = '= Doc\n\n.Code\n----\nx\n----\n';
    expect(html(listing, {'lang': 'fr'}), isNot(contains('Liste')));
    expect(
      html(listing, {'lang': 'fr', 'listing-caption': ''}),
      contains('Liste 1. Code'),
    );
  });

  test('asciidoctor-compat and locale-labels: false keep the English', () {
    for (final attributes in [
      {'lang': 'ja', 'asciidoctor-compat': ''},
      {'lang': 'ja', 'asciidoctor-compat': 'pdf'},
      {'lang': 'ja', 'locale-labels': 'false'},
    ]) {
      expect(html(_source, attributes), contains('Table of Contents'));
    }
    expect(
      html(_source, {
        'lang': 'ja',
        'asciidoctor-compat': '',
        'locale-labels': 'true',
      }),
      contains('目次'),
    );
  });

  test("the index's cross-references in the language", () {
    const index = '''
= Buch
:doctype: book

== Kapitel

Katze indexterm:[Katze, see=Tier] und Hund indexterm:[Hund, see-also="Tier"]. Tier(((Tier))).

[index]
== Register
''';
    final out = html(index, {'lang': 'de'});
    expect(out, contains('Katze</span>, <em>siehe</em> '));
    expect(out, contains('; <em>siehe auch</em> '));
    expect(
      html(index, {'lang': 'de', 'index-see-label': 's.'}),
      contains('<em>s.</em>'),
    );
    expect(html(index, {'lang': 'ja'}), contains('<em>see</em>'));
  });
}
