// Look studies (TASK-66c2mr): publishers' recipes, measured from their
// own PDFs, as fixtures. Each renders a sample in the look that follows
// the recipe and checks its geometry against what was measured, within
// a stated tolerance: the page, the measure, the leading, the first and
// last baselines, line numbers and running heads. The looks name no
// publisher, and the tests use whatever fonts are installed (the PDF's
// own Times, Helvetica and Courier stand in for the looks' faces), so
// only what doesn't depend on the face is checked.
//
// The measurements: research_notes/Print typography traditions complete
// picture 2/document_measurements.md, with the baselines taken again
// from the glyphs' origins (pdfminer.six) of S. 4 (118th Congress,
// introduced), Regulation (EU) No 326/2014 (OJ L 98, 1.4.2014) and
// Designing Distributed Systems (O'Reilly, 2018); the troff books from
// research_notes/Print typography traditions complete picture/
// unix_troff_tex_era.md; the Supreme Court's booklet from its Rule 33.1.
// The Madina mushaf's page rule (each page ends on an ayah's end, none
// across a page) waits for its layout, FEAT-ytfd13.
@TestOn('vm')
@Tags(['slow'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:plain_pdf/plain_pdf.dart';
import 'package:ptome/src/internal.dart';
import 'package:ptome/src/pdf/pdf.dart';
import 'package:test/test.dart';

import '../support/oracles.dart';
import '../support/pdf_tools.dart';

import '../vendored_fonts.dart';

late Directory _dir;
var _count = 0;

/// A piece of text the page shows: where its baseline starts, its font
/// (the resource's name) and size.
typedef _Text = ({double x, double y, String font, double size});

/// A word poppler finds, its edges (x from the left, y from the top).
typedef _Word = ({String text, double xMin, double xMax});

/// A page of a PDF: its size, its texts and its words.
typedef _Page = ({
  double width,
  double height,
  List<_Text> texts,
  List<_Word> words,
});

/// Words of English, for samples that break like text.
const List<String> _vocabulary = [
  'the', 'of', 'and', 'to', 'in', 'a', 'is', 'that', 'for', 'it', 'as', //
  'was', 'with', 'be', 'by', 'on', 'not', 'this', 'are', 'or', 'from',
  'at', 'which', 'but', 'have', 'an', 'they', 'were', 'there', 'one',
  'all', 'their', 'been', 'has', 'would', 'when', 'more', 'other', 'some',
  'could', 'time', 'these', 'first', 'then', 'any', 'such', 'state',
  'between', 'within', 'section', 'provision', 'subsection', 'paragraph',
  'regulation', 'commission', 'member', 'application', 'registered',
  'accordance', 'publication', 'procedure', 'practice', 'standard',
  'political', 'process', 'protected', 'class', 'subdivision', 'election',
];

/// [count] paragraphs of [words] words or so each, the same each run.
List<String> _paragraphs(int count, {int words = 70, int seed = 7}) {
  final random = math.Random(seed);
  return [
    for (var p = 0; p < count; p++)
      () {
        final n = words ~/ 2 + random.nextInt(words);
        final text = [
          for (var i = 0; i < n; i++)
            _vocabulary[random.nextInt(_vocabulary.length)],
        ].join(' ');
        return '${text[0].toUpperCase()}${text.substring(1)}.';
      }(),
  ];
}

/// A sample: [sections] sections of paragraphs (and, with [code], a
/// listing in each), with the header [attributes].
String _sample(String attributes, {int sections = 5, bool code = false}) {
  final out = StringBuffer('= A Study\n$attributes\n\n');
  for (var s = 1; s <= sections; s++) {
    out.write('== Section $s\n\n');
    for (final paragraph in _paragraphs(6, seed: s)) {
      out.write('$paragraph\n\n');
    }
    if (code) {
      out.write('[source]\n----\nint main(void) {\n    return 0;\n}\n----\n\n');
    }
  }
  return '$out';
}

/// [source] converted to PDF (with the theme [theme], YAML, when given),
/// read back page by page.
List<_Page> _pdf(String source, {String? theme}) {
  final input = File('${_dir.path}/d${_count++}.adoc')
    ..writeAsStringSync(source);
  final out = '${input.path}.pdf';
  final themeFile = theme == null
      ? null
      : (File('${input.path}-theme.yml')..writeAsStringSync(theme));
  convertFile(
    input.path,
    AsciidoctorOptions(
      safe: SafeMode.unsafe,
      backend: 'pdf',
      toFile: out,
      attributes: {if (themeFile != null) 'pdf-theme': themeFile.path},
      logger: MemoryLogger(),
    ),
  );
  final file = PdfFile.parse(File(out).readAsBytesSync());
  final words = _words(out);
  return [
    for (final (i, page) in file.pages.indexed)
      (
        width: page.box.width,
        height: page.box.height,
        texts: _texts(latin1.decode(page.content)),
        words: i < words.length ? words[i] : const [],
      ),
  ];
}

/// The texts of a page's [content]: each text object's first position
/// (`Td`, or `Tm`'s translation) and its font size.
List<_Text> _texts(String content) => [
  for (final object in RegExp(r'BT\s(.*?)ET', dotAll: true).allMatches(content))
    if (RegExp(r'/(\S+) ([\d.]+) Tf').firstMatch(object[1]!) case final font?)
      if (RegExp(
            r'(-?[\d.]+) (-?[\d.]+) Td|'
            r'-?[\d.]+ -?[\d.]+ -?[\d.]+ -?[\d.]+ (-?[\d.]+) (-?[\d.]+) Tm',
          ).firstMatch(object[1]!)
          case final at?)
        (
          x: double.parse(at[1] ?? at[3]!),
          y: double.parse(at[2] ?? at[4]!),
          font: font[1]!,
          size: double.parse(font[2]!),
        ),
];

/// The words of each page of [pdf], from pdftotext.
List<List<_Word>> _words(String pdf) {
  final xml =
      recordedRunSync(_recorded, 'pdftotext', ['-bbox', pdf, '-']).stdout
          as String;
  return [
    for (final page in xml.split('<page ').skip(1))
      [
        for (final m in RegExp(
          r'<word xMin="([\d.]+)" yMin="[\d.]+" xMax="([\d.]+)" '
          r'yMax="[\d.]+">([^<]*)</word>',
        ).allMatches(page))
          (text: m[3]!, xMin: double.parse(m[1]!), xMax: double.parse(m[2]!)),
      ],
  ];
}

/// The baselines of the texts of [size] on [page], top first, each once.
List<double> _baselines(_Page page, double size, {double? x}) => {
  for (final text in page.texts)
    if ((text.size - size).abs() < 1e-3 &&
        (x == null || (text.x - x).abs() < 0.01))
      text.y,
}.toList()..sort((a, b) => b.compareTo(a));

/// The distance between consecutive baselines of [size], the most common
/// one (the leading, which space between paragraphs interrupts).
double _pitch(List<_Page> pages, double size) {
  final counts = <int, int>{};
  for (final page in pages) {
    final lines = _baselines(page, size);
    for (var i = 1; i < lines.length; i++) {
      final step = ((lines[i - 1] - lines[i]) * 100).round();
      counts[step] = (counts[step] ?? 0) + 1;
    }
  }
  final (step, _) = counts.entries.fold<(int, int)>((
    0,
    0,
  ), (best, e) => e.value > best.$2 ? (e.key, e.value) : best);
  return step / 100;
}

/// The right edge of the text's justified lines: the furthest right a
/// word of [pages] ends, short of [above] across.
double _rightEdge(List<_Page> pages, {double above = double.infinity}) => [
  for (final page in pages)
    for (final word in page.words)
      if (word.xMax < above) word.xMax,
].reduce(math.max);

/// The tools' runs, recorded (test/oracles/look_studies.json.gz,
/// test/support/oracles.dart; ORACLES=record asks them again).
late final Oracle _recorded;

void main() {
  _recorded = Oracle('look_studies', compressed: true);
  setUpAll(useVendoredFonts);
  setUpAll(() {
    registerPdf();
    _dir = Directory.systemTemp.createTempSync('ptome-studies.');
  });
  tearDownAll(() => _dir.deleteSync(recursive: true));

  group('a US bill (S. 4 and H.R. 2, 118th Congress)', () {
    late List<_Page> pages;
    setUpAll(() {
      pages = _pdf(
        _sample(':look: us-bill\n:line-numbers:\n:bill-slug: S 4 IS'),
      );
    });

    test('Letter, the text 14 on a 26 pt grid from 707 down to 83', () {
      expect((pages.first.width, pages.first.height), (612, 792));
      final body = [
        for (final page in pages.skip(1)) ..._baselines(page, 14, x: 150),
      ];
      expect(body, isNotEmpty);
      for (final y in body) {
        expect((707 - y) % 26, anyOf(closeTo(0, 0.01), closeTo(26, 0.01)));
      }
      expect(body.reduce(math.max), closeTo(707, 0.01));
      expect(body.reduce(math.min), greaterThanOrEqualTo(83 - 0.01));
    });

    test('the text from 150 to 489.7 pt, paragraphs 2 em in', () {
      final starts = {
        for (final page in pages)
          for (final text in page.texts)
            if (text.size == 14 && text.x >= 149) text.x,
      };
      expect(starts, containsAll(<double>[150, 178]));
      expect(_rightEdge(pages, above: 600), closeTo(489.7, 0.3));
    });

    test('every line numbered, flush right at 140 pt, 25 to a page', () {
      final perPage = [
        for (final page in pages)
          [
            for (final word in page.words)
              if ((word.xMax - 140).abs() < 0.05) ?int.tryParse(word.text),
          ],
      ];
      // (The last page, short, aside.)
      for (final numbers in perPage.sublist(0, perPage.length - 1)) {
        expect(numbers, isNotEmpty);
        expect(numbers.reduce(math.max), inInclusiveRange(22, 25));
      }
      expect(
        perPage.any((n) => n.isNotEmpty && n.reduce(math.max) == 25),
        isTrue,
      );
    });

    test('the page number 14 point at the head, its baseline at 731', () {
      for (final page in pages.skip(1)) {
        final folio = page.texts.where((t) => t.size == 14 && t.y > 720);
        expect(folio, hasLength(1));
        // (Within the faces' difference: running content is set by its
        // face's line, whose depth a stand-in changes by a few points.)
        expect(folio.single.y, closeTo(731, 4.5));
      }
    });
  });

  group('EU legislation (OJ L, Reg. 326/2014)', () {
    late List<_Page> pages;
    setUpAll(() => pages = _pdf(_sample(':look: eu-journal', sections: 4)));

    test('A4, one column from 67.4 to 529.8 pt, the text 9.6 on 10.55', () {
      expect(pages.first.width, closeTo(595.28, 0.01));
      expect(pages.first.height, closeTo(841.89, 0.01));
      expect({
        for (final page in pages)
          for (final text in page.texts)
            if (text.size == 9.6 && text.y < 770) text.x,
      }, contains(67.4));
      expect(_rightEdge(pages), closeTo(529.8, 0.3));
      expect(_pitch(pages, 9.6), closeTo(10.55, 0.02));
    });

    test('the running head 9.6 point, its baseline at 784.4', () {
      for (final page in pages.skip(1)) {
        final head = _baselines(page, 9.6).first;
        // (As the bill's page number, within the faces' difference.)
        expect(head, closeTo(784.4, 2.5));
      }
    });
  });

  group("O'Reilly's animal books (Designing Distributed Systems, 2018)", () {
    late List<_Page> pages;
    setUpAll(
      () => pages = _pdf(_sample(':look: tech-book', sections: 4, code: true)),
    );

    test('7 × 9.1875 in, a 30 pc text block, the text 10.5 on 12.6', () {
      expect((pages.first.width, pages.first.height), (504, 661.5));
      expect({
        for (final page in pages)
          for (final text in page.texts)
            if (text.size == 10.5) text.x,
      }, contains(72));
      expect(_rightEdge(pages), closeTo(432, 0.3));
      expect(_pitch(pages, 10.5), closeTo(12.6, 0.02));
    });

    test('code 8.5 on 10.2, 17 pt in', () {
      final code = [
        for (final page in pages)
          for (final text in page.texts)
            if (text.size == 8.5 && text.y > 60) text,
      ];
      expect(code.map((t) => t.x), contains(89));
      expect(_pitch(pages, 8.5), closeTo(10.2, 0.02));
    });

    test('a running foot 9 point at 42.75, no running head', () {
      for (final page in pages.skip(1)) {
        // (Nothing above the text block, which starts 0.875 in down.)
        expect(page.texts.where((t) => t.y > 661.5 - 0.875 * 72), isEmpty);
        final foot = page.texts.where((t) => t.size == 9);
        expect(foot, isNotEmpty);
        for (final text in foot) {
          // (As the bill's page number, within the faces' difference.)
          expect(text.y, closeTo(42.75, 2.5));
        }
      }
    });
  });

  group('the Bell Labs troff books (K&R, UPE, AWK)', () {
    late List<_Page> pages;
    setUpAll(() => pages = _pdf(_sample(':look: troff', code: true)));

    test('6.25 × 9.25 in, the text 11 on 12 on a 4.8 in measure', () {
      expect((pages.first.width, pages.first.height), (450, 666));
      final left = [
        for (final page in pages)
          for (final text in page.texts)
            if (text.size == 11) text.x,
      ].reduce(math.min);
      expect(_rightEdge(pages) - left, closeTo(4.8 * 72, 1));
      expect(_pitch(pages, 11), closeTo(12, 0.02));
    });

    test('code half an inch in; the running head 32 pt above', () {
      final left = [
        for (final page in pages)
          for (final text in page.texts)
            if (text.size == 11) text.x,
      ].reduce(math.min);
      final code = [
        for (final page in pages)
          for (final text in page.texts)
            if (text.size == 9 && text.x > left + 1) text.x,
      ];
      expect(code.reduce(math.min) - left, closeTo(36, 0.5));
      // (On the pages whose first line is the text's.)
      var checked = 0;
      for (final page in pages.skip(1)) {
        final lines = [...page.texts]..sort((a, b) => b.y.compareTo(a.y));
        final head = lines.first;
        final first = lines.firstWhere((t) => t.y < head.y - 0.01);
        if (first.size != 11) continue;
        expect(head.y - first.y, closeTo(32, 1));
        checked++;
      }
      expect(checked, greaterThan(0));
    });
  });

  group("a brief in the Supreme Court's booklet format (Rule 33.1)", () {
    late List<_Page> pages;
    setUpAll(() => pages = _pdf(_sample(':look: scotus-booklet')));

    test('6⅛ × 9¼ in, a text field 4⅛ in wide, the text 12 on 14', () {
      expect((pages.first.width, pages.first.height), (441, 666));
      final left = [
        for (final page in pages)
          for (final text in page.texts)
            if (text.size == 12) text.x,
      ].reduce(math.min);
      expect(_rightEdge(pages) - left, closeTo(4.125 * 72, 0.5));
      expect(_pitch(pages, 12), closeTo(14, 0.02));
    });
  });

  group('a trade paperback, B format (Penguin)', () {
    test('129 × 198 mm, the text 10.25 on 12.25 on a grid', () {
      final pages = _pdf(_sample(':look: trade-novel'));
      expect(pages.first.width, closeTo(129 / 25.4 * 72, 0.05));
      expect(pages.first.height, closeTo(198 / 25.4 * 72, 0.05));
      expect(_pitch(pages, 10.25), closeTo(12.25, 0.02));
      // (Every line of the text on the page's grid.)
      for (final page in pages) {
        final lines = _baselines(page, 10.25);
        for (final y in lines) {
          final steps = (lines.first - y) / 12.25;
          expect(steps - steps.round(), closeTo(0, 0.01));
        }
      }
    });
  });

  group('a UK Act (since 2001)', () {
    test('A4, the text 11 on 12', () {
      final pages = _pdf(_sample(':look: uk-act', sections: 3));
      expect(pages.first.width, closeTo(595.28, 0.01));
      expect(_pitch(pages, 11), closeTo(12, 0.02));
    });
  });

  group('a dictionary (Collins)', () {
    test('three columns, the spaces between words 72% of the face’s', () {
      final entries = [
        for (final (i, text) in _paragraphs(60, words: 18).indexed)
          '*${_vocabulary[i % _vocabulary.length]}* $text',
      ];
      const theme = '''
extends: default
base:
  font_size: 8
  text_align: left
  word_spacing: 72%
  hyphens: false
''';
      final source =
          '= Words\n\n[.columns,column-count=3]\n--\n'
          '${entries.join('\n\n')}\n--\n';
      final close = _pdf(source, theme: theme);
      final open = _pdf(source, theme: theme.replaceFirst('72%', '100%'));
      // (Three columns: the entries' words, in bold, start at three
      // places across, under the title.)
      final texts = close[0].texts;
      final title = texts.map((t) => t.y).reduce(math.max);
      final starts = {
        for (final font in {for (final t in texts) t.font})
          font: {
            for (final text in texts)
              if (text.font == font && text.y < title - 1) text.x.round(),
          },
      };
      expect(starts.values.map((s) => s.length), contains(3));
      // The gaps between the words of a ragged line: 72% of the face's.
      double gap(List<_Page> pages) {
        final gaps = <double>[];
        final words = pages.first.words;
        for (var i = 1; i < words.length; i++) {
          final g = words[i].xMin - words[i - 1].xMax;
          if (g > 0.5 && g < 4) gaps.add(g);
        }
        gaps.sort();
        return gaps[gaps.length ~/ 2];
      }

      expect(gap(close) / gap(open), closeTo(0.72, 0.02));
    });
  });
}
