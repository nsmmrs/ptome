// The index in HTML: an `[index]` section lists the document's index terms,
// linked to their uses (Asciidoctor renders the section empty).

import 'package:ptome/src/internal.dart';
import 'package:test/test.dart';

const _book = '''
= Book
:doctype: book

== Cats

The ((Tiger)) is big.(((Big cats, Lions)))
indexterm:[Sheep, see=Ewe]
indexterm:[Felines, see-also="Tiger"]

== Dogs

Wolves are ((wild)).(((Big cats, Tigers, Siberian)))
A ((Tiger)) again.(((Tiger)))

|===
a|In a cell: ((Ocelot)).
|===

[index]
== Index
''';

String _html(String source, {Map<String, String> attributes = const {}}) =>
    convert(
      source,
      AsciidoctorOptions(safe: SafeMode.safe, attributes: attributes),
    );

/// The headings and terms of [lang]'s index of [terms], in order (a
/// heading as `# X`).
List<String> _collated(
  String lang,
  String terms, {
  Map<String, String> attributes = const {},
}) => [
  for (final m
      in RegExp('<h3>([^<]+)</h3>|<span class="index-term">(.*?)</span>')
          .allMatches(
            _html(
              '= Doc\n:lang: $lang\n:doctype: book\n\n== One\n\n$terms\n\n'
              '[index]\n== Index\n',
              attributes: attributes,
            ),
          ))
    if (m[1] != null)
      '# ${m[1]}'
    else
      m[2]!.replaceAll(RegExp('<rp>.*?</rp>|<rt>.*?</rt>|<[^>]+>'), ''),
];

void main() {
  group("a document's language orders its index", () {
    test('Swedish: å, ä, ö after z', () {
      expect(_collated('sv', '((Zebra)) ((ål)) ((alla)) ((äpple)) ((öl))'), [
        '# A',
        'alla',
        '# Z',
        'Zebra',
        '# Å',
        'ål',
        '# Ä',
        'äpple',
        '# Ö',
        'öl',
      ]);
    });

    test('German: ä with a', () {
      expect(_collated('de', '((Zebra)) ((Äpfel)) ((Apfel)) ((Bär))'), [
        '# A',
        'Apfel',
        'Äpfel',
        '# B',
        'Bär',
        '# Z',
        'Zebra',
      ]);
    });

    test('Chinese by pinyin, Latin terms among them', () {
      expect(_collated('zh', '((中国)) ((北京)) ((上海)) ((爱)) ((apple))'), [
        '# A',
        '爱',
        'apple',
        '# B',
        '北京',
        '# S',
        '上海',
        '# Z',
        '中国',
      ]);
    });

    test('Traditional Chinese by stroke count', () {
      expect(_collated('zh-TW', '((中國)) ((人)) ((一))'), [
        '# 1劃',
        '一',
        '# 2劃',
        '人',
        '# 4劃',
        '中國',
      ]);
    });

    test("Japanese by reading: a term's ruby, its sort-as", () {
      expect(
        _collated(
          'ja',
          '((ruby:漢字[かんじ])) ((ruby:山[やま])) ((ruby:川[かわ])) '
              'indexterm:[東京,sort-as=とうきょう] ((さくら)) ((アメ))',
        ),
        ['# あ', 'アメ', '# か', '川', '漢字', '# さ', 'さくら', '# た', '東京', '# や', '山'],
      );
    });

    test('index-sort: asciidoctor, English and asciidoctor-compat keep '
        "Asciidoctor's order", () {
      const terms = '((Zebra)) ((ål)) ((alla))';
      const asciidoctor = ['# A', 'alla', '# Z', 'Zebra', '# Å', 'ål'];
      expect(
        _collated('sv', terms, attributes: {'index-sort': 'asciidoctor'}),
        asciidoctor,
      );
      expect(
        _collated('sv', terms, attributes: {'asciidoctor-compat': ''}),
        asciidoctor,
      );
      expect(_collated('en-GB', '((Ölmez)) ((Zoe))'), [
        '# Z',
        'Zoe',
        '# Ö',
        'Ölmez',
      ]);
      // (index-sort: collation without a language: the root order.)
      expect(
        _collated(
          'en',
          '((Ölmez)) ((Zoe))',
          attributes: {'index-sort': 'collation'},
        ),
        ['# O', 'Ölmez', '# Z', 'Zoe'],
      );
    });
  });

  test("index-sort: Chicago's letter-by-letter or word-by-word order", () {
    const source =
        '= Book\n:doctype: book\n\n== One\n\n'
        '((New York)) ((Newark)) ((news)) ((Élan)) ((eland))\n\n'
        '[index]\n== Index\n';
    List<String> order(String sort) => [
      for (final m in RegExp(
        '<span class="index-term">([^<]+)<',
      ).allMatches(_html(source, attributes: {'index-sort': sort})))
        m[1]!.trim(),
    ];
    expect(order('letter-by-letter'), [
      'Élan',
      'eland',
      'Newark',
      'news',
      'New York',
    ]);
    expect(order('word-by-word'), [
      'Élan',
      'eland',
      'New York',
      'Newark',
      'news',
    ]);
  });

  test('the index by letter, and index-category-headings!', () {
    const source =
        '= Book\n:doctype: book\n\n== One\n\n((htmx)) ((HTTP)) ((Alpine))\n\n'
        '[index]\n== Index\n';
    List<String> terms(String html) => [
      for (final m in RegExp(
        '<span class="index-term">([^<]*)</span>',
      ).allMatches(html))
        m[1]!,
    ];
    // The index's order: case-insensitive, by letter.
    final letter = _html(source);
    expect(terms(letter), ['Alpine', 'htmx', 'HTTP']);
    expect(letter, contains('<h3>A</h3>'));
    // One list, no letters above the groups.
    final flat = _html(source, attributes: {'index-category-headings!': ''});
    expect(terms(flat), ['Alpine', 'htmx', 'HTTP']);
    expect(flat, isNot(contains('<h3>')));
  });

  test('a term indexed in a section title is in the index', () {
    final html = _html(
      '= Book\n:doctype: book\n\n== Chapter ((Gadget))\n\nText.\n\n'
      '[index]\n== Index\n',
    );
    final index = html.substring(html.indexOf('<div class="index">'));
    expect(index, contains('<span class="index-term">Gadget</span>'));
    expect(index, contains('href="#_indexterm_1"'));
    expect(html, contains('Chapter <a id="_indexterm_1"></a>Gadget'));
  });

  test('each use gets an anchor and the index links to it', () {
    final html = _html(_book);
    expect(html, contains('The <a id="_indexterm_1"></a>Tiger is big.'));
    final index = html.substring(html.indexOf('<div class="index">'));
    // Letters in order, terms under them.
    expect(RegExp('<h3>(.)</h3>').allMatches(index).map((m) => m[1]), [
      'B',
      'F',
      'O',
      'S',
      'T',
      'W',
    ]);
    // A use links to the anchor, labeled by its section (once per
    // section).
    expect(
      index,
      contains(
        '<span class="index-term">Tiger</span>: '
        '<a href="#_indexterm_1">Cats</a>, <a href="#_indexterm_7">Dogs</a>',
      ),
    );
    // Subterms nest.
    expect(
      index,
      contains(
        '<li id="_index_entry_3"><span class="index-term">Tigers</span>\n'
        '<ul class="index-terms">\n'
        '<li id="_index_entry_4"><span class="index-term">Siberian</span>: '
        '<a href="#_indexterm_6">Dogs</a></li>',
      ),
    );
    expect(index, contains('Sheep</span>, <em>see</em> Ewe</li>'));
    expect(
      index,
      matches(
        RegExp(
          'Felines</span>: <a href="#_indexterm_4">Cats</a>; '
          r'<em>see also</em> <a href="#_index_entry_\d+">Tiger</a>',
        ),
      ),
    );
    // A term in an AsciiDoc table cell.
    expect(index, contains('Ocelot</span>: <a href="#'));
    expect(
      RegExp(r'<a id="(_indexterm_\d+)"></a>Ocelot').hasMatch(html),
      isTrue,
    );
  });

  test('a term with markup cut open is listed as text', () {
    final html = _html(
      'Some text.(((pass:[<em>]Kept)))\n\n[index]\n== Index\n',
    );
    expect(html, contains('<span class="index-term">Kept</span>'));
  });

  test('emphasis around a term stays whole', () {
    final html = _html('_Some (((emph_ term))) text._\n\n[index]\n== Index\n');
    expect(html, contains('<span class="index-term">emph_ term</span>'));
    expect(html, contains('<em>Some <a id="_indexterm_1"></a> text.</em>'));
  });

  test('is unchanged from Asciidoctor without an index section', () {
    final source = _book.substring(0, _book.indexOf('[index]'));
    final html = _html(source);
    expect(html, isNot(contains('_indexterm')));
    expect(html, contains('The Tiger is big.'));
  });

  test('is left out with index-html unset', () {
    final html = _html(_book, attributes: {'index-html!': ''});
    expect(html, isNot(contains('_indexterm')));
    expect(html, isNot(contains('class="index"')));
    expect(
      html,
      contains(
        '<h2 id="_index">Index</h2>\n<div class="sectionbody">\n\n</div>',
      ),
    );
  });

  test('converting twice gives the same HTML', () {
    final document = load(
      _book,
      options: const AsciidoctorOptions(safe: SafeMode.safe),
    );
    expect(document.convert(), document.convert());
  });
}
