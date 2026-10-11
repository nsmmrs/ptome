/// A book's features in every format (ADR-0012, doc/formats.md): each
/// test converts the same source with the backends that should agree.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:ptome/src/epub3/epub3.dart';
import 'package:ptome/src/internal.dart';
import 'package:ptome/src/multipage.dart';
import 'package:ptome/src/pdf/pdf.dart';
import 'package:test/test.dart';

import 'epub3_test.dart' show unzipText;

import 'vendored_fonts.dart';

void main() {
  setUpAll(useVendoredFonts);
  setUpAll(registerEpub3);
  setUpAll(MultipageHtml5Converter.register);
  setUpAll(registerPdf);
  late Directory dir;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('format_parity_test.');
    File('${dir.path}/art.txt').writeAsStringSync('+--+\n|<>|\n+--+\n');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  String convertWith(String backend, String source) {
    final input = File('${dir.path}/doc.adoc')..writeAsStringSync(source);
    convertFile(
      input.path,
      AsciidoctorOptions(
        safe: SafeMode.safe,
        backend: backend,
        attributes: const {'reproducible': ''},
      ),
    );
    final extension = switch (backend) {
      'html5' => 'html',
      'docbook5' => 'xml',
      _ => 'epub',
    };
    return '${dir.path}/doc.$extension';
  }

  group('a text file shown as an image', () {
    const source = '= Doc\n\n.Art\nimage::art.txt[Art]\n';

    test('HTML: its text, preformatted, in the image block', () {
      final html = File(convertWith('html5', source)).readAsStringSync();
      expect(
        html,
        contains(
          '<div class="imageblock text">\n<div class="content">\n'
          '<pre>+--+\n|&lt;&gt;|\n+--+</pre>\n</div>',
        ),
      );
      expect(html, isNot(contains('src="art.txt"')));
    });

    test('EPUB: its text, preformatted, the file not packed', () {
      final files = unzipText(
        File(convertWith('epub3', source)).readAsBytesSync(),
      );
      final content = files.entries
          .where((e) => e.key.endsWith('.xhtml') && e.value.contains('Art'))
          .map((e) => e.value)
          .join();
      expect(content, contains('<pre>+--+\n|&lt;&gt;|\n+--+</pre>'));
      expect(files.keys.where((k) => k.endsWith('.txt')), isEmpty);
    });

    test('DocBook: its text in the media object', () {
      final xml = File(convertWith('docbook5', source)).readAsStringSync();
      expect(
        xml,
        contains(
          '<textobject><literallayout class="monospaced">+--+\n|&lt;&gt;|\n'
          '+--+</literallayout></textobject>',
        ),
      );
      expect(xml, isNot(contains('fileref="art.txt"')));
    });
  });

  test("DocBook: a chapter of a toc macro alone is the book's toc", () {
    final xml = File(
      convertWith(
        'docbook5',
        '= Book\n:doctype: book\n\n[#contents]\n== Contents\n\ntoc::[]\n\n'
            '== One\n\nText.\n',
      ),
    ).readAsStringSync();
    expect(
      xml,
      contains(
        '<toc xml:id="contents">\n<title>Contents</title>\n'
        '</toc>',
      ),
    );
  });

  test("DocBook: an image's placement as floatstyle", () {
    final xml = File(
      convertWith(
        'docbook5',
        '= Doc\n\n.Top\nimage::a.png[placement=top]\n\n'
            'image::b.png[placement=none]\n',
      ),
    ).readAsStringSync();
    expect(xml, contains('<figure floatstyle="before">'));
    expect(xml, contains('<informalfigure floatstyle="none">'));
  });

  group('%unbreakable', () {
    const source =
        '= Doc\n\n[%unbreakable]\n----\ncode\n----\n\n'
        '[%unbreakable]\n.Side\n****\nText.\n****\n';

    test('HTML: the class unbreakable', () {
      final html = File(convertWith('html5', source)).readAsStringSync();
      expect(html, contains('<div class="listingblock unbreakable">'));
      expect(html, contains('<div class="sidebarblock unbreakable">'));
    });

    test('EPUB: the class unbreakable', () {
      final files = unzipText(
        File(convertWith('epub3', source)).readAsBytesSync(),
      );
      expect(files.values.join(), contains('unbreakable'));
    });

    test('DocBook: the keep-together instruction', () {
      final xml = File(convertWith('docbook5', source)).readAsStringSync();
      expect(
        RegExp(r'<\?dbfo keep-together="always"\?>').allMatches(xml),
        hasLength(2),
      );
    });
  });

  test(':hyphens: hyphenates the text in HTML and EPUB', () {
    const source = '= Doc\n:hyphens:\n\nText.\n';
    expect(
      File(convertWith('html5', source)).readAsStringSync(),
      contains('hyphens:auto'),
    );
    final files = unzipText(
      File(convertWith('epub3', source)).readAsBytesSync(),
    );
    expect(
      files.entries
          .where((e) => e.key.endsWith('.xhtml') && e.value.contains('Text.'))
          .single
          .value,
      contains('hyphens: auto'),
    );
    // Without it, the stylesheets' own.
    expect(
      File(convertWith('html5', '= Doc\n\nText.\n')).readAsStringSync(),
      isNot(contains('hyphens:auto')),
    );
  });

  test('DocBook: the ISBN and editors in the info', () {
    final xml = File(
      convertWith(
        'docbook5',
        '= Book\nAnn Author\n:isbn: 978-0-00-000000-0\n'
            ':editor: Ed One; Ed Two\n\nText.\n',
      ),
    ).readAsStringSync();
    expect(
      xml,
      contains('<biblioid class="isbn">978-0-00-000000-0</biblioid>'),
    );
    expect(xml, contains('<editor><personname>Ed One</personname></editor>'));
    expect(xml, contains('<editor><personname>Ed Two</personname></editor>'));
  });

  test("the cover on the HTML page and the website's home page only", () {
    const source =
        '= Book\n:doctype: book\n'
        ':front-cover-image: image:cover.png[A cover]\n\n== One\n\nText.\n';
    final html = File(convertWith('html5', source)).readAsStringSync();
    expect(
      html,
      contains(
        '<div id="cover" class="imageblock cover">\n<div class="content">\n'
        '<img src="cover.png" alt="A cover">',
      ),
    );
    expect(html.indexOf('id="cover"'), lessThan(html.indexOf('id="header"')));
    final input = File('${dir.path}/site.adoc')..writeAsStringSync(source);
    convertFile(
      input.path,
      const AsciidoctorOptions(
        safe: SafeMode.safe,
        backend: 'multipage_html5',
        attributes: {'reproducible': ''},
      ),
    );
    expect(
      File('${dir.path}/site.html').readAsStringSync(),
      contains('id="cover"'),
    );
    final pages = dir
        .listSync(recursive: true)
        .whereType<File>()
        .where(
          (f) =>
              f.path.endsWith('.html') &&
              !f.path.endsWith('site.html') &&
              !f.path.endsWith('doc.html'),
        )
        .toList();
    expect(pages, isNotEmpty);
    for (final page in pages) {
      expect(page.readAsStringSync(), isNot(contains('id="cover"')));
    }
  });

  test("HTML: the house stylesheet by default, Asciidoctor's by name", () {
    const house = 'look ptome (ADR-0023';
    expect(
      File(convertWith('html5', '= Doc\n\nText.\n')).readAsStringSync(),
      contains(house),
    );
    final classic = File(
      convertWith('html5', '= Doc\n:stylesheet: asciidoctor\n\nText.\n'),
    ).readAsStringSync();
    expect(classic, contains('Asciidoctor default stylesheet'));
    expect(classic, isNot(contains(house)));
  });

  test("EPUB: the house rules after asciidoctor-epub3's, or its alone", () {
    String css(String source) => unzipText(
      File(convertWith('epub3', source)).readAsBytesSync(),
    )['EPUB/styles/epub3.css']!;
    expect(css('= Doc\n\nText.\n'), contains('look ptome (ADR-0023'));
    expect(
      css('= Doc\n:epub3-stylesheet: asciidoctor-epub3\n\nText.\n'),
      isNot(contains('look ptome (ADR-0023')),
    );
  });

  test("a look's own CSS after the device rules, for the last word", () {
    File('${dir.path}/own-look.yml').writeAsStringSync('''
extends: ptome
css: '.own{color:red}'
epub-css: '.own{color:blue}'
''');
    const source = '= Doc\n:look: own\n:looksdir: {docdir}\n\nText.\n';
    final html = File(convertWith('html5', source)).readAsStringSync();
    expect(
      html.indexOf('.own{color:red}'),
      greaterThan(html.indexOf("ptome's device rules for HTML")),
    );
    final epub = unzipText(
      File(convertWith('epub3', source)).readAsBytesSync(),
    )['EPUB/styles/epub3.css']!;
    expect(
      epub.indexOf('.own{color:blue}'),
      greaterThan(epub.indexOf("ptome's device rules for EPUB")),
    );
    expect(epub, isNot(contains('.own{color:red}')));
  });

  group("a look's title page", () {
    const look = '''
extends: ptome
templates:
  title-page:
    recto:
      - { slot: authors, separator: ' & ', before: 'By ' }
      - title
      - subtitle
      - { attribute: publisher, style: .publisher }
    verso:
      - { attribute: copyright }
      - revision
''';
    const source =
        '= Slots: A Subtitle\nAda Lovelace; Charles Babbage\n'
        'v2.1, 2026-10-11: Reprinted\n'
        ':look: tp\n:looksdir: {docdir}\n:publisher: Anticomplex\n'
        ':copyright: Copyright 2026\n\n== One\n\nText.\n';
    setUp(() => File('${dir.path}/tp-look.yml').writeAsStringSync(look));

    test("HTML: the header's slots in order, the verso after them", () {
      final html = File(convertWith('html5', source)).readAsStringSync();
      final header = html.substring(
        html.indexOf('<div id="header">'),
        html.indexOf('<div id="content">'),
      );
      expect(
        header,
        '<div id="header">\n'
        '<div class="details title-page-authors">By&#160;<span id="author" '
        'class="author">Ada Lovelace</span>&#160;&amp;&#160;<span id="author2" '
        'class="author">Charles Babbage</span></div>\n'
        '<h1 class="title-page-title">Slots</h1>\n'
        '<div class="subtitle title-page-subtitle">A Subtitle</div>\n'
        '<div class="title-page-publisher publisher">Anticomplex</div>\n'
        '<div class="verso">\n'
        '<div class="title-page-copyright">Copyright 2026</div>\n'
        '<div class="details title-page-revision"><span id="revnumber">'
        'version 2.1,</span> <span id="revdate">2026-10-11</span><br>'
        '<span id="revremark">Reprinted</span></div>\n'
        '</div>\n'
        '</div>\n',
      );
      // asciidoctor-compat: Asciidoctor's header.
      final compat = File(
        convertWith(
          'html5',
          source.replaceFirst(':look:', ':asciidoctor-compat: html\n:look:'),
        ),
      ).readAsStringSync();
      expect(compat, isNot(contains('title-page-')));
    });

    test('EPUB: a title page after the cover, its verso a page of its own', () {
      final files = unzipText(
        File(convertWith('epub3', source)).readAsBytesSync(),
      );
      final page = files['EPUB/titlepage.xhtml']!;
      expect(
        page,
        contains(
          '<section class="titlepage" epub:type="titlepage">\n'
          '<div class="details title-page-authors">By&#160;',
        ),
      );
      expect(
        page,
        contains(
          '<section class="titlepage verso" epub:type="copyright-page">\n'
          '<div class="title-page-copyright">Copyright 2026</div>',
        ),
      );
      expect(page, contains('<br/><span id="revremark">'));
      expect(
        files['EPUB/package.opf'],
        contains('<itemref idref="titlepage"/>'),
      );
      expect(
        files['EPUB/nav.xhtml'],
        contains('<a epub:type="titlepage" href="titlepage.xhtml">'),
      );
      expect(
        files['EPUB/styles/epub3.css'],
        contains('.titlepage.verso{break-before:page'),
      );
      // None without slots.
      final plain = unzipText(
        File(convertWith('epub3', '= Doc\n\nText.\n')).readAsBytesSync(),
      );
      expect(plain.keys, isNot(contains('EPUB/titlepage.xhtml')));
    });
  });

  test("the magazine looks: the piece's parts in the header's order", () {
    for (final look in ['magazine', 'magazine-1970s', 'compact']) {
      final html = File(
        convertWith(
          'html5',
          '= Hed: The dek\nA Writer\n:look: $look\n:kicker: Mountains\n'
              ':credit: Photographed by A. Lens\n\n[.lede.dropcap]\nText.\n',
        ),
      ).readAsStringSync();
      final header = html.substring(
        html.indexOf('<div id="header">'),
        html.indexOf('<div id="content">'),
      );
      expect(
        RegExp('class="([a-z -]+)"')
            .allMatches(header)
            .map((m) => m[1])
            .where(
              (c) => c!.startsWith('title-page') || c.contains(' title-page'),
            )
            .toList(),
        [
          'title-page-kicker kicker',
          'title-page-title',
          'subtitle title-page-subtitle dek',
          'details title-page-authors byline',
          'title-page-credit credit',
        ],
        reason: look,
      );
      expect(html, contains('--mag-dropcap-lines'), reason: look);
    }
  });

  test("HTML: a floated image's outline as its shape-outside", () {
    File('test/pdf/fixtures/images/circle.png').copySync('${dir.path}/c.png');
    String html(String attrs) =>
        File(convertWith('html5', '= Doc\n\nimage::c.png[C,$attrs]\n\nText.\n'))
            .readAsStringSync();
    final shaped = html('float=right,shape=alpha');
    final style = RegExp(
      r'class="imageblock right" style="shape-outside:polygon\(([^)]*)\);'
      'shape-margin:0.75em"',
    ).firstMatch(shaped);
    expect(style, isNotNull, reason: shaped);
    // The circle's left edge comes in from the box's at its middle.
    final xs = [
      for (final point in style![1]!.split(','))
        double.parse(point.trim().split(' ').first.replaceAll('%', '')),
    ];
    expect(xs.reduce(math.min), lessThan(10));
    expect(xs.first, 100);
    // Not floated, or opaque: none.
    expect(html('shape=alpha'), isNot(contains('shape-outside')));
  });

  test('HTML jump lines: continued in the piece, and from', () {
    final html = File(
      convertWith(
        'html5',
        '= Issue\n\n[#a]\n== A Piece\n\n[.jump]\n<<a-more>>\n\n'
            '[#a-more]\n== More\n\n[.jump]\n<<a>>\n',
      ),
    ).readAsStringSync();
    expect(html, contains('<p><a href="#a-more">Continued in More</a></p>'));
    expect(html, contains('<p><a href="#a">Continued from A Piece</a></p>'));
  });

  test("a look's webfonts after Asciidoctor's; none with its stylesheet", () {
    File('${dir.path}/web-look.yml').writeAsStringSync(
      "webfonts: ['Crimson Pro:400,700', 'Ubuntu Mono:400']\n",
    );
    const source = '= Doc\n:look: web\n:looksdir: {docdir}\n\nText.\n';
    final html = File(convertWith('html5', source)).readAsStringSync();
    expect(
      html,
      contains(
        'Noto+Sans+Mono:400,700%7CCrimson+Pro:400,700%7CUbuntu+Mono:400"',
      ),
    );
    final classic = File(
      convertWith(
        'html5',
        source.replaceFirst(':look:', ':stylesheet: asciidoctor\n:look:'),
      ),
    ).readAsStringSync();
    expect(classic, isNot(contains('Crimson')));
  });

  test('asciidoctor-compat: the classic stylesheets of the formats named', () {
    const house = 'look ptome (ADR-0023';
    String html(String compat) => File(
      convertWith('html5', '= Doc\n:asciidoctor-compat: $compat\n\nText.\n'),
    ).readAsStringSync();
    String epubCss(String compat) => unzipText(
      File(
        convertWith('epub3', '= Doc\n:asciidoctor-compat: $compat\n\nText.\n'),
      ).readAsBytesSync(),
    )['EPUB/styles/epub3.css']!;
    expect(html('html'), isNot(contains(house)));
    expect(html('true'), isNot(contains(house)));
    expect(html(''), isNot(contains(house)));
    expect(html('pdf, epub'), contains(house));
    expect(html('false'), contains(house));
    expect(epubCss('epub3'), isNot(contains(house)));
    expect(epubCss('html,pdf'), contains(house));
    // Nor a cover, which Asciidoctor's HTML hasn't.
    expect(
      File(
        convertWith(
          'html5',
          '= Doc\n:front-cover-image: cover.png\n'
              ':asciidoctor-compat: html\n\nText.\n',
        ),
      ).readAsStringSync(),
      isNot(contains('id="cover"')),
    );
  });

  test("EPUB: the print edition's pages from the PDF's page map", () {
    final source = StringBuffer('= Book\n:doctype: book\n\n== One\n\n');
    for (var i = 0; i < 40; i++) {
      source
        ..write('Paragraph $i, long enough to take a few lines. ' * 4)
        ..write('\n\n');
    }
    final input = File('${dir.path}/book.adoc')
      ..writeAsStringSync(source.toString());
    convertFile(
      input.path,
      const AsciidoctorOptions(
        safe: SafeMode.safe,
        backend: 'pdf',
        attributes: {'pdf-page-map': 'book.pages.json'},
      ),
    );
    final map = jsonDecode(
      File('${dir.path}/book.pages.json').readAsStringSync(),
    ) as Map<String, Object?>;
    expect((map['labels']! as List).length, greaterThan(2));
    convertFile(
      input.path,
      const AsciidoctorOptions(
        safe: SafeMode.safe,
        backend: 'epub3',
        attributes: {'epub-page-map': 'book.pages.json', 'reproducible': ''},
      ),
    );
    final files = unzipText(File('${dir.path}/book.epub').readAsBytesSync());
    final chapter = files['EPUB/_one.xhtml']!;
    expect(
      chapter,
      contains('<span epub:type="pagebreak" role="doc-pagebreak" id="page-2"'),
    );
    expect(
      files['EPUB/nav.xhtml'],
      contains('<nav epub:type="page-list" id="page-list" hidden="hidden">'),
    );
    expect(files['EPUB/nav.xhtml'], contains('href="_one.xhtml#page-2">2</a>'));
  });
}
