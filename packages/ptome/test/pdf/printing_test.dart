// What following a printing page for page takes (Alice in the showcase,
// set after Macmillan's 1867 printing): paragraphs on their source's lines
// (`:source-lines:`), a chapter's running title divided across the spread,
// the printer's signatures, a cut's box and place from its own attributes
// (`pdfheight`, `fit-top`, `fit=none`, `float-width`, `float-gap`), a
// block's own margins, a cut set before its chapter's heading, and a block
// with no room beside a float set below it. The pages read back by
// Poppler, recorded in test/oracles/pdf_printing.json.gz
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
}
