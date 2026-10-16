// What following a printing page for page takes (Alice in the showcase,
// set after Macmillan's 1867 printing; the Second Reader, after its 1920
// one): paragraphs on their source's lines (`:source-lines:`), a
// chapter's running title divided across the spread, the printer's
// signatures, a cut's box and place from its own attributes (`pdfheight`,
// `fit-top`, `fit=none`, `float-width`, `float-gap`), a block's own
// margins (kept at a page's top, `base_margin_break: keep`), a cut set
// before its chapter's heading, a block with no room beside a float set
// below it; a schoolbook's numbered paragraphs (`olist_marker_position:
// inside`) and its poems' own indents and type, a contents' columns and
// dot leaders, a folio at the foot of the opening pages alone; a
// duodecimo's signed leaves, its catchwords, its shaped and sideways
// poems, an index's columns (The Temple, after its 1633 printing). The pages
// read back by Poppler, recorded in test/oracles/pdf_printing.json.gz
// (test/support/oracles.dart; ORACLES=record asks them again).
@TestOn('vm')
library;

import 'dart:io';

import 'package:ptome/ptome.dart';
import 'package:test/test.dart';

import '../support/oracles.dart';
import '../support/pdf_tools.dart';
import '../vendored_fonts.dart';

late final Oracle _recorded;

late Directory _scratch;

/// [source] as a PDF in asciidoctor-pdf's theme with [theme] over it.
File _pdf(String source, String theme) {
  final n = _scratch.listSync().length;
  final themeFile = File('${_scratch.path}/t$n-theme.yml')
    ..writeAsStringSync('extends: default\n$theme');
  File('${_scratch.path}/box.svg').writeAsStringSync(
    '<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" '
    'viewBox="0 0 100 100"><rect width="100" height="100"/></svg>',
  );
  return File('${_scratch.path}/p$n.pdf')..writeAsBytesSync(
    asciidoc.convertToBytes(
      source,
      backend: Backend.pdf,
      attributes: {
        'pdf-theme': themeFile.path,
        'reproducible': '',
        'imagesdir': _scratch.path,
      },
    ),
  );
}

/// Each page's lines (Poppler's): their text and box (left, top, right,
/// bottom).
List<List<(String, List<double>)>> _lines(File pdf) {
  final xml =
      recordedRunSync(_recorded, 'pdftotext', [
            '-bbox-layout',
            pdf.path,
            '-',
          ]).stdout
          as String;
  final pages = <List<(String, List<double>)>>[];
  for (final page in xml.split('<page ').skip(1)) {
    final found =
        [
          for (final m in RegExp(
            r'<line xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" '
            r'yMax="([\d.]+)">(.*?)</line>',
            dotAll: true,
          ).allMatches(page))
            (
              [
                for (final w in RegExp('>([^<]*)</word>').allMatches(m[5]!))
                  w[1],
              ].join(' '),
              [for (var i = 1; i <= 4; i++) double.parse(m[i]!)],
            ),
        ]..sort((a, b) {
          final dy = a.$2[3] - b.$2[3];
          return dy.abs() < 1 ? a.$2[0].compareTo(b.$2[0]) : dy.sign.toInt();
        });
    // (Poppler's lines on one baseline, a justified line's words far
    // apart: one line, left to right.)
    final merged = <(String, List<double>)>[];
    for (final line in found) {
      if (merged.isNotEmpty && (merged.last.$2[3] - line.$2[3]).abs() < 1) {
        final (text, box) = merged.removeLast();
        merged.add(('$text ${line.$1}', [box[0], box[1], line.$2[2], box[3]]));
      } else {
        merged.add(line);
      }
    }
    pages.add(merged);
  }
  return pages;
}

/// The line on [page] that starts with [text].
List<double> _line(List<(String, List<double>)> page, String text) =>
    page.firstWhere((l) => l.$1.startsWith(text)).$2;

void main() {
  _recorded = Oracle('pdf_printing', compressed: true);
  setUpAll(() {
    useVendoredFonts();
    _scratch = Directory.systemTemp.createTempSync('ptome-printing.');
  });
  tearDownAll(() => _scratch.deleteSync(recursive: true));

  test(":source-lines: keeps a paragraph's lines, justified, a soft hyphen "
      'shown where a word is divided; without it the text flows', () {
    const text =
        'so suddenly that Alice had\n'
        'not a moment to think about stop&#173;ping\n'
        'herself before she found herself falling\n'
        'down a very deep well.';
    final page = _lines(
      _pdf(
        ':nofooter:\n:source-lines:\n\n$text\n\n:source-lines!:\n\n'
            '[.flow]\n$text\n',
        '',
      ),
    ).first;
    expect(page.take(5).map((l) => l.$1.replaceAll('\u00ad', '-')), [
      'so suddenly that Alice had',
      'not a moment to think about stop-',
      'ping herself before she found herself falling',
      'down a very deep well.',
      // (The same text flowing, its own lines.)
      startsWith('so suddenly that Alice had not a moment'),
    ]);
    // (Justified: the first two reach the same right edge, the last not.)
    final right = _line(page, 'ping')[2];
    expect(_line(page, 'so suddenly')[2], closeTo(right, 0.5));
    expect(_line(page, 'down a very')[2], lessThan(right - 50));
  });

  test(':source-lines:, a line separator ending the text justifies its last '
      'line', () {
    final page = _lines(
      _pdf(
        ':nofooter:\n:source-lines:\n:ls: &#8232;\n\n'
            'one two three four five six seven eight nine ten eleven\n'
            'twelve thirteen{ls}\n',
        '',
      ),
    ).first;
    expect(_line(page, 'twelve')[2], closeTo(_line(page, 'one two')[2], 0.5));
  });

  test('{chapter-title-spread}: a running-title divided across the spread, '
      'whole where the facing page opens a chapter', () {
    final paras = List.filled(
      60,
      'A paragraph to fill the pages. ' * 6,
    ).join('\n\n');
    final pages = _lines(
      _pdf(
        '= Book\n:doctype: book\n:notitle:\n\n'
            '[running-title="Down the|Rabbit-Hole."]\n'
            '== Down the Rabbit-Hole\n\n'
            '$paras\n',
        'header:\n  height: 0.5in\n'
            '  recto: { center: { content: "{chapter-title-spread}" } }\n'
            '  verso: { center: { content: "{chapter-title-spread}" } }\n',
      ),
    );
    final heads = [for (final page in pages.skip(1)) page.first.$1];
    expect(heads.take(2), ['Down the', 'Rabbit-Hole.']);
    // (The last page, a verso with no recto facing it: whole.)
    if (pages.length.isEven) expect(heads.last, 'Down the Rabbit-Hole.');
  });

  test("{page-signature}: the printers' letters every interval pages, no "
      'J, V or W, doubled after Z; a footer on an opening page with '
      'footer_on_openers', () {
    final paras = List.filled(16, '<<<\n\nA page.').join('\n\n');
    final pages = _lines(
      _pdf(
        '= Book\n:doctype: book\n:notitle:\n\n== One\n\nA page.\n\n$paras\n',
        'running_content:\n  signature:\n    interval: 2\n    start: Y\n'
            'footer:\n  height: 0.5in\n  on_openers: true\n'
            '  recto: { center: { content: "{page-signature}" } }\n'
            '  verso: { center: { content: "{page-signature}" } }\n',
      ),
    );
    final marks = [
      // (In the foot, the page's last line, beside the theme's page
      // number.)
      for (final page in pages)
        [
          for (final word in page.last.$1.split(' '))
            if (RegExp(r'^[A-Z]{1,2}$').hasMatch(word)) word,
        ].firstOrNull,
    ];
    expect(marks.take(7), ['Y', null, 'Z', null, 'AA', null, 'BB']);
  });

  test("an image's pdfheight is the room it takes, the drawing fit and "
      'centered in it or at fit-top; fit=none draws it at its pdfwidth '
      'past the box', () {
    double gap(int height) {
      final page = _lines(
        _pdf(
          ':nofooter:\n\nBefore.\n\n'
              'image::box.svg[pdfwidth=40pt,pdfheight=${height}pt,'
              'fit-top=0]\n\nAfter.\n',
          'image:\n  margin_bottom: 0\nprose:\n  margin_bottom: 0\n',
        ),
      ).first;
      return _line(page, 'After')[1] - _line(page, 'Before')[3];
    }

    // (The box the room, whatever the drawing's own height, 40 pt.)
    expect(gap(150) - gap(100), closeTo(50, 0.01));
  });

  test("a float's own float-width and float-gap: the text beside it that "
      'far from it', () {
    final page = _lines(
      _pdf(
        ':nofooter:\n\n'
            'image::box.svg[role=side,pdfwidth=100pt,float-width=100pt,'
            'float-gap=20pt]\n\n'
            '${'Words beside the float. ' * 12}\n',
        'role:\n  side:\n    float: left\n    float_width: 50pt\n',
      ),
    ).first;
    final left = _line(page, 'Words')[0];
    expect(left - 48.24, closeTo(120, 1));
  });

  test('a float as wide as the region leaves no room beside it: the block '
      'after it below it', () {
    final page = _lines(
      _pdf(
        ':nofooter:\n\n'
            'image::box.svg[role=side,pdfwidth=60pt,pdfheight=60pt,'
            'float-width=1000pt]\n\n'
            'Below the float.\n',
        'role:\n  side:\n    float: left\n',
      ),
    ).first;
    expect(_line(page, 'Below')[0], closeTo(48.24, 1));
    expect(_line(page, 'Below')[1], greaterThan(60 + 36));
  });

  test("a block's own margin-top and margin-bottom, before the space "
      'between paragraphs; negative, the block drawn up', () {
    final page = _lines(
      _pdf(
        ':nofooter:\n\nOne.\n\n[margin-top=40pt]\nTwo.\n\n'
            '[margin-top=-10pt]\nThree.\n',
        'prose:\n  margin_bottom: 0\n  margin_inner: 0\n',
      ),
    ).first;
    final one = _line(page, 'One');
    final two = _line(page, 'Two');
    final three = _line(page, 'Three');
    final pitch = one[3] - one[1];
    expect(two[1] - one[1], closeTo(pitch + 40, 2));
    expect(three[1] - two[1], closeTo(pitch - 10, 2));
  });

  test("role_<role>_before_heading: a chapter's first image set above its "
      'heading', () {
    final pages = _lines(
      _pdf(
        '= Book\n:doctype: book\n:notitle:\n\n== Chapter\n\n'
            'image::box.svg[role=opener,pdfwidth=60pt,pdfheight=200pt]\n\n'
            'The text.\n',
        'role:\n  opener:\n    before_heading: true\n',
      ),
    );
    final page = pages.firstWhere((p) => p.any((l) => l.$1 == 'Chapter'));
    expect(_line(page, 'Chapter')[1], greaterThan(200));
  });

  test('olist_marker_position: inside: each item a paragraph, its number '
      "its first word, its lines its source's", () {
    final page = _lines(
      _pdf(
        ':nofooter:\n:source-lines:\n:shy: &#173;\n\n'
            '. It is winter. The cold wind whis{shy}tles\n'
            'through the branches of the trees.\n'
            '. Mr. Brown has done his day’s\n'
            'work.\n',
        'prose: { text_indent: 18 }\nolist: { marker_position: inside }\n',
      ),
    ).first;
    expect(page.map((l) => l.$1.replaceAll('­', '-')), [
      '1. It is winter. The cold wind whis-',
      'tles through the branches of the trees.',
      '2. Mr. Brown has done his day’s',
      'work.',
    ]);
    // (The number at the paragraph's indent, the lines after it at the
    // margin.)
    expect(_line(page, '1.')[0], closeTo(48.24 + 18, 0.5));
    expect(_line(page, 'tles')[0], closeTo(48.24, 0.5));
  });

  test("a list's own indent, type and pitch (olist_role_<role>_indent, "
      '_font_size, _line_pitch)', () {
    final page = _lines(
      _pdf(
        ':nofooter:\n\n[.poem]\n. One line +\nanother line\n',
        'olist:\n  role:\n    poem: { indent: 40, font_size: 9, '
            'line_pitch: 20pt }\n',
      ),
    ).first;
    final one = _line(page, '1.');
    expect(_line(page, 'another')[0], closeTo(48.24 + 40, 0.5));
    final another = _line(page, 'another');
    expect(another[3] - one[3], closeTo(20, 0.1));
    // (Its type 9 pt: a line Poppler measures 9 × the font's height.)
    expect(one[3] - one[1], lessThan(14));
  });

  test('role_<role>_width, _width_align: a phrase in a width of its own; '
      '_leader: the room before a run flush right filled with its dots', () {
    final pdf = _pdf(
      ':nofooter:\n\n[.n]#1.# Evening at Home [.pg]#11#\n\n'
          '[.n]#12.# Susie Sunbeam [.pg]#30#\n',
      'role:\n  n: { width: 20pt, width_align: right }\n'
          '  pg: { flush: right, leader: ". " }\n',
    );
    final page = _lines(pdf).first;
    // (The leaders decoration, read as nothing: the line's text its own.)
    expect(page.first.$1, '1. Evening at Home 11');
    // (The numerals' right edges, and so the titles' left, one above the
    // other.)
    final xml =
        recordedRunSync(_recorded, 'pdftotext', ['-bbox', pdf.path, '-']).stdout
            as String;
    double word(String text, int side) => double.parse(
      RegExp(
        'xMin="([\\d.]+)"[^>]*xMax="([\\d.]+)"[^>]*>${RegExp.escape(text)}<',
      ).firstMatch(xml)![side]!,
    );
    expect(word('1.', 2), closeTo(48.24 + 20, 0.5));
    expect(word('12.', 2), closeTo(48.24 + 20, 0.5));
    expect(word('Evening', 1), closeTo(word('Susie', 1), 0.1));
  });

  test('<periphery>_opener: a page that opens a chapter its own running '
      'content (a folio at its foot); the signatures numbered, worded by '
      "_signature_template; a running title the document's, divided on every "
      'page (running_content_spread_whole: false)', () {
    final paras = List.filled(6, '<<<\n\nA page.').join('\n\n');
    final pages = _lines(
      _pdf(
        '= Book\n:doctype: book\n:notitle:\n'
            ':running-title: Eclectic Series.|Second Reader.\n\n'
            '== One\n\nA page.\n\n$paras\n',
        'running_content:\n  spread_whole: false\n  signature:\n'
            '    interval: 2\n    first: 2\n    start: 2\n'
            '    numbering: decimal\n    template: "2, {{signature}}."\n'
            'header:\n  height: 0.5in\n'
            '  recto: { center: { content: "{chapter-title-spread}" } }\n'
            '  verso: { center: { content: "{chapter-title-spread}" } }\n'
            'footer:\n  height: 0.5in\n  on_openers: true\n'
            '  recto: { left: { content: "{page-signature}" } }\n'
            '  verso: { left: { content: "{page-signature}" } }\n'
            '  opener: { right: { content: "({page-number})" } }\n',
      ),
    );
    // (The opening page: no head, its folio in brackets at the foot.)
    expect(pages.first.map((l) => l.$1), ['One', 'A page.', '(1)']);
    expect(pages[1].first.$1, 'Eclectic Series.');
    expect(pages[2].first.$1, 'Second Reader.');
    expect(pages[1].last.$1, '2, 2.');
    expect(pages[3].last.$1, '2, 3.');
    expect(pages[2].last.$1, isNot(contains('2,')));
  });

  test("base_margin_break: keep: a block's own margin-top kept at the top "
      "of a page, negative too, and a section's at its heading", () {
    double topOf(String source) => _line(
      _lines(_pdf(source, 'base_margin_break: keep\n')).last,
      'Line',
    )[1];
    final plain = topOf(':nofooter:\n\nFirst.\n\n<<<\n\nLine.\n');
    expect(
      topOf(':nofooter:\n\nFirst.\n\n<<<\n\n[margin-top=30pt]\nLine.\n'),
      closeTo(plain + 30, 0.1),
    );
    expect(
      topOf(':nofooter:\n\nFirst.\n\n<<<\n\n[margin-top=-12pt]\nLine.\n'),
      closeTo(plain - 12, 0.1),
    );
    final heading = _lines(
      _pdf(
        ':nofooter:\n\nFirst.\n\n[margin-top=50pt]\n== Line\n\nText.\n',
        'base_margin_break: keep\nheading: { margin_top: 0 }\n',
      ),
    ).first;
    expect(
      _line(heading, 'Line')[1] - _line(heading, 'First')[3],
      closeTo(50, 2),
    );
  });

  test(':source-lines:, a line its own hard break ends broken there once', () {
    final page = _lines(
      _pdf(':nofooter:\n:source-lines:\n\nYour little boy +\nWillie.\n', ''),
    ).first;
    final pitch = _line(page, 'Willie')[3] - _line(page, 'Your')[3];
    expect(pitch, lessThan(20));
  });

  test("{page-signature} with _signature_signed: a gathering's first leaves "
      'signed on their rectos, the first by its letter, the others by '
      "_signature_leaf_template's letter and number (A, A 2, A 3)", () {
    final paras = List.filled(7, '<<<\n\nA page.').join('\n\n');
    final pages = _lines(
      _pdf(
        '= Book\n:doctype: book\n:notitle:\n\n== One\n\nA page.\n\n$paras\n',
        'running_content:\n  signature:\n'
            '    interval: 8\n    first: 1\n    start: A\n    signed: 3\n'
            'footer:\n  height: 0.5in\n  on_openers: true\n'
            '  recto: { left: { content: "x{page-signature}" }, '
            'right: { content: "" } }\n'
            '  verso: { left: { content: "x{page-signature}" }, '
            'right: { content: "" } }\n',
      ),
    );
    final feet = [for (final p in pages) p.last.$1];
    expect(feet.take(8), [
      'xA',
      'A page.',
      'xA 2',
      'A page.',
      'xA 3',
      'A page.',
      'A page.',
      'A page.',
    ]);
  });

  test('section_role_<role>_opener: a section of any level whose first page '
      "is an opener's, its running content the openers'", () {
    final pages = _lines(
      _pdf(
        '= Book\n:doctype: book\n:notitle:\n\n== One\n\nA page.\n\n<<<\n\n'
            '[.opener]\n=== Two\n\nText.\n',
        'section:\n  role:\n    opener: { opener: true }\n'
            'header:\n  height: 0.5in\n'
            '  recto: { center: { content: "Head" } }\n'
            '  verso: { center: { content: "Head" } }\n'
            '  opener: { center: { content: "Opening" } }\n'
            'running_content: { on_openers: true }\n',
      ),
    );
    expect(pages[1].first.$1, 'Opening');
  });

  test("base_margin_break: keep: a heading's own negative margin-top in the "
      'middle of a page draws it up past the space above it', () {
    double gap(String margin) {
      final page = _lines(
        _pdf(
          ':nofooter:\n\nFirst.\n\n[margin-top=${margin}pt]\n'
              '== Line\n\nText.\n',
          'base_margin_break: keep\nheading: { margin_top: 0 }\n',
        ),
      ).first;
      return _line(page, 'Line')[1] - _line(page, 'First')[3];
    }

    expect(gap('-10') - gap('0'), closeTo(-10, 0.5));
  });

  test("catchwords: the next page's first word, a title's (its pilcrow and "
      "its first word) and a drop's whole, in the word's own case", () {
    final pages = _lines(
      _pdf(
        'One.\n\n<<<\n\n== ¶ Prayer.\n\nText.\n\n<<<\n\n'
            '[.dropcap]\nLOrd, how I am all ague\nwhen I seek.\n',
        'role:\n  dropcap: { drop_lines: 2 }\n'
            'footer:\n  height: 0.5in\n'
            '  recto: { left: { content: "" }, '
            'right: { content: "{page-catchword}" } }\n'
            '  verso: { left: { content: "" }, '
            'right: { content: "{page-catchword}" } }\n',
      ),
    );
    expect(pages[0].last.$1, '¶ Prayer.');
    expect(pages[1].last.$1, 'Lord,');
  });

  test('role_<role>_text_align_last: justify fills each line broken by '
      'hand; role_<role>_margin_right narrows the paragraph', () {
    final page = _lines(
      _pdf(
        ':nofooter:\n:source-lines:\n\n'
            '[.shape]\nA broken altar\nmade of a heart\n',
        'role:\n  shape: { text_align: justify, text_align_last: justify, '
            'margin_left: 40, margin_right: 60 }\n',
      ),
    ).first;
    final a = _line(page, 'A broken');
    final b = _line(page, 'made');
    expect(b[2], closeTo(a[2], 0.5));
    expect(b[0], closeTo(a[0], 0.5));
    final full = _line(
      _lines(_pdf(':nofooter:\n\nA broken altar made of a heart.\n', '')).first,
      'A broken',
    );
    expect(a[0] - full[0], closeTo(40, 0.5));
  });

  test("a drop at its paragraph's own left, past role_<role>_margin_left", () {
    final page = _lines(
      _pdf(
        ':nofooter:\n\n[.col.dropcap]\nTHe Call\nCharms and knots\n',
        'role:\n  dropcap: { drop_lines: 2 }\n  col: { margin_left: 100 }\n',
      ),
    ).first;
    // (The drop past the paragraph's margin, the text past the drop.)
    final drop = _line(page, 'T');
    expect(drop[0], greaterThan(_line(page, 'He Call')[0] - 30));
    expect(drop[0], greaterThan(140));
  });

  test('a sideways block in the flow (roles sideways clockwise in-flow): as '
      'far down the page as its longest line, what follows it below', () {
    final page = _lines(
      _pdf(
        ':nofooter:\n\nTitle.\n\n[verse.sideways.clockwise.in-flow]\n____\n'
            'Lord, who createdst man\nMost poore\n____\n\nAfter.\n',
        '',
      ),
    ).first;
    final lord = _line(page, 'Lord');
    final after = _line(page, 'After');
    expect(lord[3] - lord[1], greaterThan(lord[2] - lord[0]));
    expect(after[1], greaterThan(lord[3]));
    expect(after[1] - lord[3], lessThan(30));
  });
}
