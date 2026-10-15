// The modern engine (the default): what it does differently from the
// asciidoctor-pdf compatibility mode, read back from the PDFs it makes;
// part 3 of 4: the layout keys, from boxes across columns on (test/pdf/support/modern.dart).
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:ptome/src/internal.dart';
import 'package:ptome/src/pdf/pdf.dart';
import 'package:test/test.dart';

import '../support/oracles.dart';
import '../support/pdf_tools.dart';
import '../vendored_fonts.dart';
import 'support/modern.dart';

void main() {
  // (Set as the file's tests start: files may share a program.)
  final recorded = Oracle('pdf_modern_2', compressed: true);
  setUpAll(() => modernRecorded = recorded);
  setUpAll(useVendoredFonts);
  setUpAll(() {
    registerPdf();
    modernDir = Directory.systemTemp.createTempSync('ptome-modern.');
  });
  tearDownAll(() => modernDir.deleteSync(recursive: true));

  group('layout keys', () {
    /// Each word of [pdf] with its box: (page, left, top, right, bottom).
    List<(String, int, double, double, double, double)> words(String pdf) {
      final xml =
          recordedRunSync(modernRecorded, 'pdftotext', [
                '-bbox',
                pdf,
                '-',
              ]).stdout
              as String;
      final out = <(String, int, double, double, double, double)>[];
      var page = -1;
      for (final m in RegExp(
        r'<page |<word xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" '
        r'yMax="([\d.]+)">([^<]*)</word>',
      ).allMatches(xml)) {
        if (m[0] == '<page ') {
          page++;
          continue;
        }
        out.add((
          m[5]!,
          page,
          double.parse(m[1]!),
          double.parse(m[2]!),
          double.parse(m[3]!),
          double.parse(m[4]!),
        ));
      }
      return out;
    }

    (String, int, double, double, double, double) word(String pdf, String w) =>
        words(pdf).firstWhere((x) => x.$1 == w);

    test('a box across the columns at the foot, its body in columns', () {
      // A study Bible's feature article: in page columns, a sidebar with
      // the role floats to the bottom of the page across both columns,
      // above the notes, its own body in two balanced columns.
      final text = [for (var k = 0; k < 30; k++) 'Text sentence $k goes on.']
          .join(' ');
      final feature = [for (var k = 0; k < 60; k++) 'Feat$k word.'].join(' ');
      final pdf = modernPdf(
        '= Doc\n\n$text footnote:[A note.]\n\n[.feature]\n.Article\n'
        '****\n$feature\n****\n\n$text\n',
        theme:
            'page:\n  columns: 2\n'
            'role:\n  feature: { float: bottom, float_scope: page }\n'
            'sidebar:\n  role:\n    feature:\n      columns: 2\n',
      );
      final bbox =
          recordedRunSync(modernRecorded, 'pdftotext', [
                '-bbox',
                pdf,
                '-',
              ]).stdout
              as String;
      final words = [
        for (final m in RegExp(
          r'xMin="([\d.]+)" yMin="([\d.]+)"[^>]*>([^<]*)<',
        ).allMatches(bbox))
          (m[3]!, double.parse(m[1]!), double.parse(m[2]!)),
      ];
      final feat = words.where((w) => w.$1.startsWith('Feat')).toList();
      final body = words.where((w) => w.$1 == 'Text').toList();
      final (_, _, noteY) = words.firstWhere((w) => w.$1 == 'note.');
      final xs = feat.map((w) => w.$2).toList();
      final mid = (xs.reduce(math.min) + xs.reduce(math.max)) / 2;
      // Its body in two columns, the second's first word level with the
      // first's.
      final first = feat.first;
      final second = feat.firstWhere((w) => w.$2 > mid);
      expect(second.$3, closeTo(first.$3, 1));
      // Under the text of both page columns (each half of the Letter
      // page), above the note.
      final topOfFeature = feat.map((w) => w.$3).reduce(math.min);
      expect({
        for (final w in body)
          if (w.$3 < topOfFeature) w.$2 < 306,
      }, hasLength(2));
      expect(feat.every((w) => w.$3 < noteY), isTrue);
    });

    test('verse numbers: bold, and hung left of the lines of a poem', () {
      final schemes = Directory('${modernDir.path}/schemes')..createSync();
      for (final f in Directory('test/units/fixtures/schemes').listSync()) {
        if (f is File) {
          f.copySync('${schemes.path}/${f.uri.pathSegments.last}');
        }
      }
      final pdf = modernPdf(
        '= Psalm\n:units: bible, kjv\n\n== @GEN\n\n=== @1\n\n'
        '@ Prose verse one.\n\n[.poetry%hardbreaks]\n'
        '@ Poem line two\n@ poem line three\n',
        theme:
            'units:\n  verse:\n    label_font_style: bold\n'
            '    label_hang: [poetry]\n',
      );
      final bbox =
          recordedRunSync(modernRecorded, 'pdftotext', [
                '-bbox',
                pdf,
                '-',
              ]).stdout
              as String;
      double x(String word, {String edge = 'xMin'}) => double.parse(
        RegExp('$edge="([\\d.]+)"[^>]*>$word<').firstMatch(bbox)![1]!,
      );
      // Each number left of its line's first word, ending before it.
      expect(x('2', edge: 'xMax'), lessThan(x('Poem')));
      expect(x('3', edge: 'xMax'), lessThan(x('poem')));
      expect(x('Poem'), closeTo(x('poem'), 0.5));
    });

    test('a heading in the margin: a chapter number left of its text', () {
      final schemes = Directory('${modernDir.path}/schemes')..createSync();
      for (final f in Directory('test/units/fixtures/schemes').listSync()) {
        if (f is File) {
          f.copySync('${schemes.path}/${f.uri.pathSegments.last}');
        }
      }
      final pdf = modernPdf(
        '= Bible\n:units: bible, kjv\n:doctype: book\n\n== @GEN\n\n'
        '=== @1\n\n@ Opening words of the chapter.\n@ More words.\n\n'
        '=== @2\n\n@ Second chapter words.\n',
        theme:
            'heading:\n  h3:\n    display: margin\n'
            '    margin_font_size: 16\n'
            "    margin_content: '{{attr-number}}'\n",
      );
      final bbox =
          recordedRunSync(modernRecorded, 'pdftotext', [
                '-bbox',
                pdf,
                '-',
              ]).stdout
              as String;
      (double, double) at(String word, {String edge = 'xMin'}) {
        final m = RegExp('$edge="([\\d.]+)"[^>]*yMax="([\\d.]+)">$word<')
            .firstMatch(bbox)!;
        return (double.parse(m[1]!), double.parse(m[2]!));
      }

      // No heading line: the numeral left of the first line, about on its
      // baseline (set larger), the chapter's words where they were.
      expect(bbox, isNot(contains('>Chapter<')));
      // (The chapter's numeral, set larger than verse 2's number.)
      final twos = [
        for (final m in RegExp(
          r'yMin="([\d.]+)" xMax="([\d.]+)" yMax="([\d.]+)">2<',
        ).allMatches(bbox))
          (
            double.parse(m[3]!) - double.parse(m[1]!),
            double.parse(m[2]!),
            double.parse(m[3]!),
          ),
      ]..sort((a, b) => b.$1.compareTo(a.$1));
      final (_, numeral, numeralBottom) = twos.first;
      final (text, textBottom) = at('Second');
      expect(numeral, lessThan(text));
      expect(numeralBottom, closeTo(textBottom, 3));
    });

    test('run-in notes in a face without an em space: spaces, no ?', () {
      final pdf = modernPdf(
        'Text.footnote:[First note.] More.footnote:[Second note.]\n',
        theme:
            'base:\n  font_family: Times-Roman\n'
            'footnotes:\n  arrangement: run_in\n  font_family: Times-Roman\n',
      );
      final text = modernPages(pdf).expand((page) => page).join('\n');
      expect(text, contains('note.'));
      expect(text, isNot(contains('?')));
    });

    test("the engine's paragraphs set the text as the text box", () {
      String sentence(int k) {
        final note = k % 10 == 0 ? 'footnote:[Note $k.]' : '';
        return 'Sentence $k has *bold* and _italic_ words, x^2^ and H~2~O, '
            'a https://example.com/path[link] and a footnote.$note';
      }

      // Paragraphs set by the engine's paragraphs (FEAT-n1bkgf, first
      // stage): the same words in the same order, links and footnotes,
      // the lines where the text box sets them.
      final body = [for (var k = 0; k < 40; k++) sentence(k)].join(' ');
      final source = '= Doc\n\n$body\n\n$body\n';
      String text(String theme) {
        final pdf = modernPdf(source, theme: theme);
        return recordedRunSync(modernRecorded, 'pdftotext', [pdf, '-']).stdout
            as String;
      }

      List<String> words(String text) => text
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty && !RegExp(r'^\d+$').hasMatch(w))
          .toList();
      final box = text('base:\n  text_align: justify\n  text_engine: box\n');
      final engine = text('base:\n  text_align: justify\n');
      // (Set by the engine, at the places the text box sets it.)
      final messages = MemoryLogger();
      modernPdf(
        source,
        theme: 'base:\n  text_align: justify\n',
        logger: messages,
      );
      expect(
        messages.messages.map((m) => '${m.message}'),
        contains(matches(RegExp('^paragraphs set by the engine: [1-9]'))),
      );
      List<(double, double)> placesOf(String theme) {
        final bbox =
            recordedRunSync(modernRecorded, 'pdftotext', [
                  '-bbox',
                  modernPdf(source, theme: theme),
                  '-',
                ]).stdout
                as String;
        return [
          for (final m in RegExp(
            r'xMin="([\d.]+)" yMin="([\d.]+)"[^>]*>Sentence<',
          ).allMatches(bbox))
            (double.parse(m[1]!), double.parse(m[2]!)),
        ];
      }

      final engineAt = placesOf('base:\n  text_align: justify\n');
      final boxAt = placesOf(
        'base:\n  text_align: justify\n  text_engine: box\n',
      );
      expect(engineAt, hasLength(boxAt.length));
      for (final (i, (x, y)) in engineAt.indexed) {
        expect(x, closeTo(boxAt[i].$1, 0.05), reason: 'word $i');
        expect(y, closeTo(boxAt[i].$2, 0.05), reason: 'word $i');
      }
      // (Hyphens at line ends may fall elsewhere: words compared joined.)
      // (And figures and spaces left out: a raised or lowered figure may
      // come apart from its word in the extracted text.)
      String joined(String t) =>
          words(t)
              .join(' ')
              .replaceAll('- ', '')
              .replaceAll(RegExp(r'[\d\s]'), '');
      expect(joined(engine), joined(box));
      final boxLines = box.split('\n').where((l) => l.trim().isNotEmpty);
      final engineLines = engine.split('\n').where((l) => l.trim().isNotEmpty);
      expect(
        engineLines.length,
        inInclusiveRange(boxLines.length * 0.9, boxLines.length * 1.1),
      );
    });

    test('margins from a rule: the canon, DIV and BCOR, a gutter', () {
      final words = [for (var k = 0; k < 40; k++) 'Words $k go on.'].join(' ');
      double firstLeft(String pdf, {int page = 1}) {
        final bbox =
            recordedRunSync(modernRecorded, 'pdftotext', [
                  '-f',
                  '$page',
                  '-l',
                  '$page',
                  '-bbox',
                  pdf,
                  '-',
                ]).stdout
                as String;
        return RegExp(r'xMin="([\d.]+)"[^>]*>Words<')
            .allMatches(bbox)
            .map((m) => double.parse(m[1]!))
            .reduce(math.min);
      }

      // The canon of 9 on a 540 pt wide page: the text 60 pt in.
      final canon = modernPdf(
        '= Doc\n\n$words\n',
        theme: 'page:\n  size: [540, 720]\n  margin_canon: 9\n',
      );
      expect(firstLeft(canon), closeTo(60, 0.5));
      // DIV 10 and a 20 pt allowance: (540 - 20) / 10 = 52 pt a stripe,
      // the inner margin 72 pt.
      final div = modernPdf(
        '= Doc\n\n$words\n',
        theme:
            'page:\n  size: [540, 720]\n  margin_div: 10\n'
            '  margin_bcor: 20\n',
      );
      expect(firstLeft(div), closeTo(72, 0.5));
      // A prepress book of more than 150 pages: KDP's inner margin of
      // half an inch on a recto, though the theme asks for less.
      final long = [for (var k = 0; k < 170; k++) 'Words $k.\n\n<<<\n'].join();
      final book = modernPdf(
        '= Book\n:doctype: book\n:media: prepress\n\n== One\n\n$long',
        theme:
            'page:\n  size: [300, 400]\n  margin: [36, 18, 36, 18]\n'
            '  margin_inner: 18\n  margin_outer: 18\n'
            '  margin_gutter: kdp\n',
      );
      final pages = modernPages(book).length;
      expect(pages, greaterThan(150));
      final recto = [
        for (var p = 5; p < 15; p++)
          if (p.isOdd) firstLeft(book, page: p),
      ];
      expect(recto, everyElement(closeTo(36, 0.5)));
    });

    test('a thematic break as a mark, shown at a page boundary', () {
      // As a dinkus wherever it is.
      final always = modernPages(
        modernPdf(
          "Before.\n\n'''\n\nAfter.\n",
          theme: "thematic_break:\n  content: '* * *'\n",
        ),
      ).expand((page) => page);
      expect(always, contains(matches(r'^\*\s*\*\s*\*$')));
      // As space mid-page, but as a mark where the text after it goes
      // on on the next page.
      final kept = List.filled(18, 'Kept line.').join(' +\n');
      final pages = modernPages(
        modernPdf(
          "Before.\n\n'''\n\nMiddle.\n\n'''\n\n"
          '[%unbreakable]\n--\n$kept\n--\n',
          theme:
              'page:\n  size: [300, 400]\n'
              'thematic_break:\n  content_display: boundary\n',
        ),
      );
      final marks = pages
          .expand((page) => page)
          .where((line) => line.contains('*'));
      // (The first break mid-page: no mark; the second before the kept
      // block, which goes on the next page: a mark.)
      expect(marks, hasLength(1));
      expect(pages.first.last, contains('*'));
    });

    test('a scene break one line deep on a baseline grid', () {
      final pitch = modernBaselines(
        modernPdf(
          "One.\n\nTwo.\n\n'''\n\nThree.\n",
          theme:
              'base_line_pitch: 14\npage_baseline_grid: true\n'
              'prose_margin_bottom: 0\nprose_margin_inner: 0\n'
              "thematic_break_content: '*'\n"
              'thematic_break_content_display: boundary\n'
              'thematic_break_padding: 0\nthematic_break_margin_bottom: 0\n',
        ),
      );
      // (One blank line where the break is: two pitches.)
      expect(pitch['Two.']! - pitch['One.']!, closeTo(14, 0.1));
      expect(pitch['Three.']! - pitch['Two.']!, closeTo(28, 0.1));
    });

    test("a section's first paragraph opens with an initial", () {
      const source =
          '= Doc\n:doctype: book\n\n== One\n\nWhen the snow came in the '
          'night the ridge above the creek held more than two feet of new '
          'powder by morning, and the skiers waited at the lift.\n\n'
          'Second paragraph.\n';
      const theme =
          'heading_h2_initial_lines: 2\nheading_h2_initial_lead_in: 2\n'
          'role:\n  lead-in:\n    text_transform: uppercase\n';
      final text = modernPages(modernPdf(source, theme: theme))
          .expand((p) => p);
      // (The letter apart, its next words in the lead-in's role.)
      expect(text, contains(matches(r'^W\s')));
      expect(text, contains(contains('HEN THE')));
      expect(text, isNot(contains(contains('HEN THE SNOW'))));
      expect(text.join(' '), isNot(contains('SECOND')));
      // asciidoctor-pdf's: no initial.
      final plain = modernPages(modernPdf(source, compat: true, theme: theme))
          .expand((p) => p);
      expect(plain, contains(contains('When the snow')));
    });

    test('a note stream run in, or in a margin column of its own', () {
      final schemes = Directory('${modernDir.path}/schemes')..createSync();
      for (final f in Directory('test/units/fixtures/schemes').listSync()) {
        if (f is File) {
          f.copySync('${schemes.path}/${f.uri.pathSegments.last}');
        }
      }
      const source =
          '= Notes\n:units: bible, kjv\n\n== @GEN\n\n=== @1\n\n'
          '@ In the beginning ##God##note:tn[Heb. Elohim] created.\n\n'
          '@ And the ##earth##note:tn[Heb. erets] was without form.\n\n'
          '@ And ##God##note:tn[Heb. said] said.\n';
      String pdf(String keys) => modernPdf(
        source,
        theme: 'note_streams: [tn]\nnote_stream:\n  tn:\n$keys',
      );
      // Run in: the three notes on one line.
      final runIn = modernPages(pdf('    arrangement: run_in\n'))
          .expand((page) => page)
          .where((line) => line.contains('Heb.'))
          .toList();
      expect(runIn, hasLength(1));
      expect(runIn.single, contains('Elohim'));
      expect(runIn.single, contains('erets'));
      // In the left margin, each beside its verse.
      final side = pdf('    column: left\n    font_size: 7\n');
      final bbox =
          recordedRunSync(modernRecorded, 'pdftotext', [
                '-bbox',
                side,
                '-',
              ]).stdout
              as String;
      final notes = RegExp(r'xMax="([\d.]+)"[^>]*>Heb\.<')
          .allMatches(bbox)
          .map((m) => double.parse(m[1]!))
          .toList();
      expect(notes, hasLength(3));
      expect(notes.every((x) => x < 48), isTrue, reason: '$notes');
    });

    test('a note stream at the foot of the page, apart, by its own keys', () {
      // The sample's translators' notes (the `tn` stream), set apart from
      // the footnotes, red by their own keys.
      String convert(String theme) {
        final themeFile = File(
          '${modernDir.path}/stream-${modernCount++}-theme.yml',
        )..writeAsStringSync('extends: default\n$theme');
        final out = '${themeFile.path}.pdf';
        convertFile(
          'test/units/fixtures/bible/sample.adoc',
          AsciidoctorOptions(
            safe: SafeMode.unsafe,
            backend: 'pdf',
            toFile: out,
            attributes: {'pdf-theme': themeFile.path},
          ),
        );
        return out;
      }

      const red = "  tn:\n    font_color: 'FF0000'\n";
      final apart = convert('note_streams: [tn]\nnote_stream:\n$red');
      expect(modernContent(apart), contains('1 0 0 rg'));
      expect(modernPages(apart).expand((p) => p).join(' '), contains('Heb.'));
      // Not listed: a footnote as before.
      expect(
        modernContent(convert('note_stream:\n$red')),
        isNot(contains('1 0 0 rg')),
      );
      // In two columns: one note, whole.
      final columned = convert(
        'note_streams: [tn]\nnote_stream:\n  tn:\n    columns: 2\n',
      );
      expect(
        modernPages(columned).expand((p) => p).join(' '),
        contains('Heb.'),
      );
    });

    test('line numbers: typeset, logical and grid lines', () {
      const verse =
          '[verse]\n____\nShall I compare thee to a summer day, thou art '
          'more lovely and more temperate than any other day of the long '
          'and lovely year, and so on\nRough winds do shake the darling buds\n'
          '____\n';
      // The numbers in the left margin of the first page.
      List<String> numbers(String kind, {String theme = ''}) {
        final pdf = modernPdf(
          '= Poem\n:line-numbers: $kind\n\n$verse',
          theme: theme.isEmpty ? 'line_numbers:\n  gap: 6\n' : theme,
        );
        return [
          for (final m in RegExp(r'xMax="([\d.]+)"[^>]*>(\d+)<').allMatches(
            recordedRunSync(modernRecorded, 'pdftotext', [
                  '-f',
                  '1',
                  '-l',
                  '1',
                  '-bbox',
                  pdf,
                  '-',
                ]).stdout
                as String,
          ))
            if (double.parse(m[1]!) < 48) m[2]!,
        ];
      }

      // The first source line wraps: three typeset lines, two logical.
      expect(numbers('typeset'), ['1', '2', '3']);
      expect(numbers('logical'), ['1', '2']);
      // Every 2nd line on a grid down the whole page.
      final grid = numbers(
        'grid',
        theme: 'line_numbers:\n  interval: 2\n  gap: 6\n',
      );
      expect(grid.length, greaterThan(20));
      expect(grid.take(3), ['2', '4', '6']);
    });

    test("a bill's page that opens with a heading has a line more", () {
      // A bill: 14 pt text on a 26 pt grid from each page's first line,
      // section headings in 10 pt (so their baseline is higher), every
      // line numbered. A page opening with a heading holds a line more.
      final lines = [for (var i = 0; i < 60; i++) 'Line $i of the bill.'];
      String theme(String anchor) =>
          'page:\n  size: [612, 690]\n  margin: [40, 72, 40, 72]\n'
          'base:\n  font_size: 14\n  line_height: 1.857\n'
          'prose:\n  margin_bottom: 0\n'
          'heading:\n  h2_font_size: 10\n  margin_top: 0\n'
          '  margin_bottom: 0\n'
          'page_baseline_grid: true\npage_baseline_grid_anchor: $anchor\n';
      int numbers(String pdf) => RegExp(r'xMax="([\d.]+)"[^>]*>\d+<')
          .allMatches(
            recordedRunSync(modernRecorded, 'pdftotext', [
                  '-f',
                  '1',
                  '-l',
                  '1',
                  '-bbox',
                  pdf,
                  '-',
                ]).stdout
                as String,
          )
          .where((m) => double.parse(m[1]!) < 70)
          .length;
      final plain = ':line-numbers:\n\n${lines.join('\n\n')}\n';
      final headed =
          ':line-numbers:\n\n== SEC. 2. DEFINITIONS.\n\n'
          '${lines.join('\n\n')}\n';
      final usual = numbers(modernPdf(plain, theme: theme('first_line')));
      expect(numbers(modernPdf(headed, theme: theme('first_line'))), usual + 1);
      // (On the page's own grid, no more.)
      expect(numbers(modernPdf(headed, theme: theme('page'))), usual);
    });

    test('line numbers from each Stephanus section, its label beside it', () {
      final schemes = Directory('${modernDir.path}/schemes')..createSync();
      for (final f in Directory('test/units/corpus/schemes').listSync()) {
        if (f is File) {
          f.copySync('${schemes.path}/${f.uri.pathSegments.last}');
        }
      }
      final words = 'Words of the dialogue go on here. ' * 30;
      final pdf = modernPdf(
        '= Dialogue\n:units: stephanus\n:line-numbers:\n\n'
        '@2a $words @ $words @ $words\n',
        theme: 'line_numbers:\n  interval: 5\n  restart_units: section\n',
      );
      final margin = [
        for (final m in RegExp(r'xMax="([\d.]+)"[^>]*>([^<]+)<').allMatches(
          recordedRunSync(modernRecorded, 'pdftotext', [
                '-bbox',
                pdf,
                '-',
              ]).stdout
              as String,
        ))
          if (double.parse(m[1]!) < 45) m[2]!,
      ];
      // Each section's label where it starts, then every fifth line of it.
      expect(margin, containsAllInOrder(['2a', '5', '2b', '5', '2c']));
    });

    test('a baseline grid: body lines a whole number of lines apart', () {
      final words = 'Body words run on across the column here. ' * 6;
      final source = [
        '= Grid',
        '',
        for (var i = 1; i <= 4; i++) ...[
          '== Head $i',
          '',
          'Lead$i $words',
          '',
          'More$i $words',
          '',
        ],
      ].join('\n');

      // Each body line's top (but the title's, the heads' and the folio's).
      List<double> tops(String pdf) => [
        for (final m
            in RegExp(
              r'<line xMin="[\d.]+" yMin="([\d.]+)"[^>]*>\s*<word[^>]*>([^<]+)<',
            ).allMatches(
              recordedRunSync(modernRecorded, 'pdftotext', [
                    '-f',
                    '1',
                    '-l',
                    '1',
                    '-bbox-layout',
                    pdf,
                    '-',
                  ]).stdout
                  as String,
            ))
          if (!m[2]!.startsWith('Head') &&
              m[2] != 'Grid' &&
              int.tryParse(m[2]!) == null)
            double.parse(m[1]!),
      ];
      bool onGrid(List<double> ys) {
        // The step: the least distance between two lines.
        final sorted = {...ys}.toList()..sort();
        var step = double.infinity;
        for (var i = 1; i < sorted.length; i++) {
          final d = sorted[i] - sorted[i - 1];
          if (d > 1) step = math.min(step, d);
        }
        return ys.every((y) {
          final lines = (y - sorted.first) / step;
          return (lines - lines.round()).abs() < 0.02;
        });
      }

      const theme = 'page_columns: 2\nheading:\n  h2_font_size: 17\n';
      expect(onGrid(tops(modernPdf(source, theme: theme))), isFalse);
      final gridded = tops(
        modernPdf(source, theme: '${theme}page_baseline_grid: true\n'),
      );
      expect(gridded.length, greaterThan(20));
      expect(onGrid(gridded), isTrue);
    });

    test("an article's title page set inline, at the top of its page", () {
      const source =
          '= The Head: The dek under it\nAnne Author\n:kicker: Coastlines\n\n'
          'The text.\n';
      const theme =
          'title_page_inline: true\ntitle_page_recto:\n'
          '- attribute: kicker\n- title\n- subtitle\n- authors\n';
      expect(modernPages(modernPdf(source, theme: theme)).first, [
        'Coastlines',
        'The Head',
        'The dek under it',
        'Anne Author',
        'The text.',
      ]);
      // asciidoctor-pdf's: the document title alone.
      expect(
        modernPages(modernPdf(source, theme: theme, compat: true)).first.first,
        'The Head: The dek under it',
      );
    });

    test("a quote's role styles it by quote_role_<role>_* keys", () {
      const source = '[.pull]\n____\nQuoted.\n____\n';
      const theme = "quote:\n  role:\n    pull:\n      font_color: 'FF0000'\n";
      expect(
        modernContent(modernPdf(source, theme: theme)),
        contains('1 0 0 rg'),
      );
      expect(
        modernContent(modernPdf('____\nQuoted.\n____\n', theme: theme)),
        isNot(contains('1 0 0 rg')),
      );
    });

    test('page columns: rules between them, balanced where they end', () {
      final words = 'Words of the piece run on across the page. ' * 20;
      const theme =
          'page_columns: 3\npage_columns_balance: true\n'
          "page_column_rule_width: 0.5\npage_column_rule_color: 'FF0000'\n";
      final pdf = modernPdf('= Issue\n\n$words\n', theme: theme);
      expect(modernContent(pdf), contains('1 0 0 RG'));
      // A short text: in all three columns, not the first alone.
      final starts = RegExp(r'<line xMin="([\d.]+)"')
          .allMatches(
            recordedRunSync(modernRecorded, 'pdftotext', [
                  '-bbox-layout',
                  pdf,
                  '-',
                ]).stdout
                as String,
          )
          .map((m) => double.parse(m[1]!).round())
          .toSet();
      expect(starts, hasLength(3), reason: '$starts');
      // asciidoctor-pdf's: no rules.
      expect(
        modernContent(
          modernPdf('= Issue\n\n$words\n', theme: theme, compat: true),
        ),
        isNot(contains('1 0 0 RG')),
      );
    });

    test('a block floating to a side in columns: a share of its column', () {
      final words = 'Words of the piece run on across the page. ' * 30;
      const theme = 'role:\n  aside:\n    float: right\n    float_width: 50%\n';
      final pdf = modernPdf(
        '[.columns]\n== Piece\n\n[.aside]\n****\nAside\n****\n\n$words\n',
        theme: theme,
      );
      final bbox =
          recordedRunSync(modernRecorded, 'pdftotext', [
                '-bbox',
                pdf,
                '-',
              ]).stdout
              as String;
      final aside = double.parse(
        RegExp(r'xMin="([\d.]+)"[^>]*>Aside<').firstMatch(bbox)![1]!,
      );
      // Two columns of the A4 page's 498 pt: the aside in the right half
      // of the first (it ends at about 291).
      expect(aside, greaterThan(150));
      expect(aside, lessThan(291));
    });

    test('a role with a hyphen floats as its theme keys name it '
        '(BUG-x7zh01)', () {
      final words = 'Words of the piece run on across the page. ' * 12;
      const theme =
          'role:\n  side-note:\n    float: right\n    float_width: 40%\n';
      final pdf = modernPdf(
        '= Doc\n\n[.side-note]\n****\nAside\n****\n\n$words\n',
        theme: theme,
      );
      final bbox =
          recordedRunSync(modernRecorded, 'pdftotext', [
                '-bbox',
                pdf,
                '-',
              ]).stdout
              as String;
      final aside = double.parse(
        RegExp(r'xMin="([\d.]+)"[^>]*>Aside<').firstMatch(bbox)![1]!,
      );
      // (In the right 40% of the A4 page's text, which starts at about
      // 48: beside the words, not above them.)
      expect(aside, greaterThan(340));
    });

    test('jump lines: continued on the page the piece goes on, and from', () {
      const source =
          '= Issue\n\n[#a]\n== A Piece\n\nIt starts.\n\n'
          '[.jump.text-right]\n<<a-more>>\n\n<<<\n\n== News\n\nOther.\n\n'
          '<<<\n\n[#a-more]\n== A Piece, Continued\n\n[.jump]\n<<a>>\n\n'
          'It ends.\n';
      final pages = modernPages(modernPdf(source));
      expect(pages[0], contains('Continued on page 3'));
      expect(pages[2], contains('Continued from page 1'));
      // Its wording, the document's.
      final worded = modernPages(
        modernPdf(
          source,
          attributes: {'jump-template': '{{^back}}See p. {{page}}{{/back}}'},
        ),
      );
      expect(worded[0], contains('See p. 3'));
      // asciidoctor-pdf's: the cross reference as it is.
      expect(
        modernPages(modernPdf(source, compat: true))[0],
        contains('A Piece, Continued'),
      );
    });

    test("a paragraph runs around an image's outline (its alpha)", () {
      final circle =
          '${Directory.current.path}/test/pdf/fixtures/images/circle.png';
      const words =
          'The first skiers made it down without incident, stopping in a '
          'cluster of trees to wait for the others. ';
      String source(String shape) =>
          '= Doc\n\n[.cutout]\nimage::$circle[Circle$shape]\n\n'
          '${words * 14}\n';
      const theme =
          'role:\n  cutout:\n    float: right\n    float_width: 40%\n'
          '    float_gap: 4\n';
      // Each line's right end, top to bottom, beside the image.
      List<double> ends(String pdf) {
        final out =
            recordedRunSync(modernRecorded, 'pdftotext', [
                  '-bbox',
                  pdf,
                  '-',
                ]).stdout
                as String;
        final byLine = <double, double>{};
        for (final m in RegExp(
          r'yMin="([\d.]+)" xMax="([\d.]+)"[^>]*>(?:[^<]*)<',
        ).allMatches(out.replaceAll(RegExp(r'xMin="[\d.]+" '), ''))) {
          final y = double.parse(m[1]!);
          byLine[y] = math.max(byLine[y] ?? 0, double.parse(m[2]!));
        }
        final rows = byLine.keys.toList()..sort();
        return [for (final y in rows.skip(1)) byLine[y]!];
      }

      // Around its box: the lines beside it end alike.
      final boxed = ends(modernPdf(source(''), theme: theme)).take(6).toList();
      expect(boxed.reduce(math.max) - boxed.reduce(math.min), lessThan(20));
      // Around its outline, a circle: the first lines reach past where
      // the middle ones end.
      final shaped = ends(modernPdf(source(',shape=alpha'), theme: theme))
          .take(12)
          .toList();
      expect(shaped.first, greaterThan(shaped.reduce(math.min) + 40));
      // The image's own float and shape, as on the web.
      final own = ends(
        modernPdf(
          '= Doc\n\nimage::$circle[Circle,pdfwidth=40%,float=right,'
          'shape=alpha]\n\n${words * 14}\n',
        ),
      ).take(12).toList();
      expect(own.first, greaterThan(own.reduce(math.min) + 40));
    });

    test('base_font_embedding: simple embeds simple TrueType fonts', () {
      final source = 'Words in a line that is set justified and wraps.\n' * 4;
      const theme = 'base_text_align: justify\n';
      final composite = modernPdf(source, theme: theme);
      final simple = modernPdf(
        source,
        theme: '${theme}base_font_embedding: simple\n',
      );
      String fonts(String pdf) =>
          '${recordedRunSync(modernRecorded, 'pdffonts', [pdf]).stdout}';
      expect(fonts(composite), contains('CID TrueType'));
      expect(fonts(simple), isNot(contains('CID')));
      expect(fonts(simple), contains('TrueType'));
      // The same text in the same places, the word spacing a Tw.
      expect(modernPages(simple), modernPages(composite));
      expect(modernContent(simple), contains(' Tw'));
    });

    test('example_collapsible: details sets a collapsible block open', () {
      const source = 'Before.\n\n.More\n[%collapsible]\n====\nInside.\n====\n';
      // A frame by default: the content inside its padding.
      final framed = modernPdf(source, theme: 'example_padding: 12\n');
      expect(
        word(framed, 'Inside.').$3 - word(framed, 'Before.').$3,
        closeTo(12, 0.01),
      );
      // Details: the title after a marker, the content set in by it.
      final details = modernPdf(
        source,
        theme: 'example_padding: 12\nexample_collapsible: details\n',
      );
      final title = word(details, 'More');
      final inside = word(details, 'Inside.');
      expect(title.$3, greaterThan(word(details, 'Before.').$3));
      expect(inside.$3, closeTo(title.$3, 0.01));
      expect(modernPages(details).first, contains('▼ More'));
    });

    test('lines break after a slash, not next to a bracket (UAX #14)', () {
      // A narrow page: the words must break.
      const theme =
          'page_size: [200, 400]\npage_margin: 10\nbase_text_align: left\n';
      final slash = modernPdf(
        'Here somewhereoverthe/rainbowwaywayuphigh.\n',
        theme: theme,
      );
      expect(
        modernPages(slash).first.any((l) => l.endsWith('somewhereoverthe/')),
        isTrue,
        reason: '${modernPages(slash).first}',
      );
      final braces = modernPdf(
        'Words words words words words words {{ request.args }} more.\n',
        theme: theme,
      );
      final lines = modernPages(braces).first;
      expect(lines.any((l) => l.endsWith('{{')), isFalse, reason: '$lines');
    });

    test('olist_marker_width and olist_body_indent: numbers in boxes', () {
      const source = '. One\n. Two\n';
      final pdf = modernPdf(
        source,
        theme: 'list_indent: 0\nolist_marker_width: 30\nolist_body_indent: 0\n',
      );
      final one = word(pdf, 'One');
      final number = word(pdf, '1.');
      // The number at the left of its box, the text 30 points on.
      expect(one.$3 - number.$3, closeTo(30, 0.5));
    });

    test('callout_list_indent and _marker_width', () {
      const source = '----\ncode <1>\n----\n<1> Explained.\n';
      final pdf = modernPdf(
        source,
        theme:
            'callout_list_indent: 20\ncallout_list_marker_width: 30\n'
            'callout_list_marker_text_align: left\n',
      );
      final text = word(pdf, 'Explained.');
      expect(text.$3 - 48.24, closeTo(50, 0.5));
    });

    test('<category>_box_decoration_break: clone', () {
      final source = '= Doc\n\n****\n${'Line of text.\n\n' * 80}****\n';
      final open = modernPdf(source, theme: 'sidebar_padding: 30\n');
      final cloned = modernPdf(
        source,
        theme: 'sidebar_padding: 30\nsidebar_box_decoration_break: clone\n',
      );
      double secondPageTop(String pdf) =>
          words(pdf).where((w) => w.$2 == 1).first.$4;
      // The second page's piece starts below its own padding.
      expect(secondPageTop(cloned) - secondPageTop(open), closeTo(30, 0.5));
    });

    test('base_text_align_last: a justified paragraph ends centered', () {
      const source =
          ':nofooter:\n\nWords enough to fill the first line of this paragraph '
          'and to go on to a second line, then words enough to go on to a '
          'third line as well, which ends short.\n';
      const justify = 'base_text_align: justify\n';
      final left = modernPdf(source, theme: justify);
      final centered = modernPdf(
        source,
        theme: '${justify}base_text_align_last: center\n',
      );
      // The first line as it was; the last one moved right.
      expect(word(centered, 'Words').$3, word(left, 'Words').$3);
      expect(
        word(centered, 'short.').$3 - word(left, 'short.').$3,
        greaterThan(50),
      );
    });

    test('table_base_*: the base keys of an AsciiDoc cell', () {
      const cell =
          'Words enough to fill the first line of this cell and to go on to '
          'a second line, which ends short.';
      const source =
          ':nofooter:\n\n[cols="a,1"]\n|===\n|$cell |x\n|===\n\n'
          'Body words enough to fill the first line of this paragraph and '
          'to go on to a second line, which ends.\n';
      const justify = 'base_text_align: justify\n';
      final plain = modernPdf(source, theme: justify);
      final cells = modernPdf(
        source,
        theme: '${justify}table_base_text_align_last: center\n',
      );
      expect(
        word(cells, 'short.').$3 - word(plain, 'short.').$3,
        greaterThan(5),
      );
      // Outside the table, the base keys as they are.
      expect(word(cells, 'ends.').$3, word(plain, 'ends.').$3);
    });

    test('olist_role_<role>_*: an ordered list with the role', () {
      const source = ':nofooter:\n\n. One\n\n[.plain]\n. Two\n';
      final pdf = modernPdf(
        source,
        theme:
            'list_body_indent: 0\nolist_marker_width: 40\n'
            'olist_role_plain_marker_width: auto\n',
      );
      // The plain list's text right after its number.
      double right(String w) =>
          words(pdf).firstWhere((x) => x.$1.endsWith(w)).$5;
      expect(right('One') - right('Two'), greaterThan(20));
    });

    test('ulist_marker_nesting: ulist counts bullet lists alone', () {
      const source = ':nofooter:\n\n. One\n* Inner\n';
      String bullets(String pdf) => modernPages(pdf).first.join('\n');
      expect(bullets(modernPdf(source, theme: '')), contains('◦'));
      final own = modernPdf(source, theme: 'ulist_marker_nesting: ulist\n');
      expect(bullets(own), contains('•'));
      expect(bullets(own), isNot(contains('◦')));
    });

    test('code_role_<role>_*: a code block with the role', () {
      const source =
          ':nofooter:\n\n----\nfirst\n----\n\n[.bare]\n----\nsecond\n----\n';
      final pdf = modernPdf(
        source,
        theme:
            'code_padding: [0, 20]\ncode_border_width: 0\n'
            'code_role_bare_padding: 0\n',
      );
      expect(word(pdf, 'first').$3 - word(pdf, 'second').$3, closeTo(20, 0.5));
    });

    test('in print, index-pagenum-sequence-style: page lists each page', () {
      const body =
          '(((Widget)))\nOne.\n\n<<<\n\n(((Widget)))\nTwo.\n\n'
          '[index]\n== Index\n';
      String entry(String pdf) =>
          modernPages(pdf)
              .expand((p) => p)
              .lastWhere((l) => l.startsWith('Widget'));
      expect(entry(modernPdf('= Doc\n:media: print\n\n$body')), 'Widget, 1-2');
      expect(
        entry(
          modernPdf(
            '= Doc\n:media: print\n:index-pagenum-sequence-style: page\n\n'
            '$body',
          ),
        ),
        'Widget, 1, 2',
      );
    });

    test('a floating image leaves the spaces around it as they were', () {
      final svg = base64.encode(
        utf8.encode(
          '<svg xmlns="http://www.w3.org/2000/svg" width="400" height="100" '
          'viewBox="0 0 400 100"><rect width="400" height="100"/></svg>',
        ),
      );
      const before = '= Doc\n:doctype: book\n\n== Chap\n\nBefore.\n\n';
      const after = '=== Section\n\nAfter.\n';
      double gap(String pdf) =>
          word(pdf, 'Section').$4 - word(pdf, 'Before.').$4;
      const theme = 'image_placement: top\n';
      final plain = modernPdf('$before$after', theme: theme);
      final floated = modernPdf(
        '$before.Fig\nimage::data:image/svg+xml;base64,$svg[pdfwidth=50%]\n\n'
        '$after',
        theme: theme,
      );
      // The paragraph's space before the heading, not before the image.
      expect(gap(floated), closeTo(gap(plain), 0.01));
    });

    test('an unknown value of a key with a set of values is reported', () {
      final logger = MemoryLogger();
      modernPdf(
        ':nofooter:\n\nText.\n',
        theme: 'base_line_breaking: optimum\nimage_placement: here\n',
        logger: logger,
      );
      final messages = logger.messages.map((m) => m.message.text).toList();
      expect(
        messages,
        contains(
          'theme key base_line_breaking: unknown value optimum; expected '
          'one of auto, optimal, greedy, segments',
        ),
      );
      // A value in the set is not.
      expect(messages.where((m) => m.contains('image_placement')), isEmpty);
    });

    test("the book's ISBN, editors and copyright in the XMP metadata", () {
      final pdf = modernPdf(
        '= Book\nAnn Author\n:isbn: 978-0-00-000000-0\n'
        ':editor: Ed One; Ed Two\n'
        ':copyright: 2026 Ann Author\n\nText.\n',
      );
      final bytes = latin1.decode(File(pdf).readAsBytesSync());
      expect(
        bytes,
        contains('<dc:identifier>urn:isbn:9780000000000</dc:identifier>'),
      );
      expect(bytes, contains('<rdf:li>Ed One</rdf:li><rdf:li>Ed Two</rdf:li>'));
      expect(bytes, contains('2026 Ann Author</rdf:li></rdf:Alt></dc:rights>'));
    });

    test("the house theme by default, asciidoctor-pdf's by name", () {
      String convert(Map<String, String> attributes) {
        final input = File('${modernDir.path}/house${modernCount++}.adoc')
          ..writeAsStringSync(
            '= Doc\n\n== Section\n\nText with [.small-caps]#Small Caps#.\n',
          );
        convertFile(
          input.path,
          AsciidoctorOptions(
            safe: SafeMode.unsafe,
            backend: 'pdf',
            toFile: '${input.path}.pdf',
            attributes: attributes,
          ),
        );
        return '${input.path}.pdf';
      }

      String fonts(String pdf) =>
          recordedRunSync(modernRecorded, 'pdffonts', [pdf]).stdout as String;
      final house = convert(const {});
      // Headings in the sans (doc/style.md).
      expect(fonts(house), contains('NotoSans'));
      expect(
        fonts(convert(const {'pdf-theme': 'default'})),
        isNot(contains('NotoSans')),
      );
      // asciidoctor-compat names asciidoctor-pdf's theme (ADR-0015).
      expect(
        fonts(convert(const {'asciidoctor-compat': 'pdf'})),
        isNot(contains('NotoSans')),
      );
      expect(
        fonts(convert(const {'asciidoctor-compat': 'html'})),
        contains('NotoSans'),
      );
      // The small-caps role (Noto Serif's subset has no smcp: smaller
      // capitals).
      expect(modernPages(house).first.join(' '), contains('SMALL CAPS'));
    });

    test('AsciiMath and LaTeX math are typeset', () {
      final logger = MemoryLogger();
      final pdf = modernPdf(
        ':stem:\n\nInline stem:[x^2] and stem:[y].\n\n[stem]\n++++\n'
        'sum_(i=1)^n i\n++++\n\nAnd latexmath:[\\frac{a}{b}].\n\n'
        '[latexmath]\n++++\n\\sqrt{2}\n++++\n',
        logger: logger,
      );
      expect(
        logger.messages.where((m) => m.severity.index >= Severity.warn.index),
        isEmpty,
      );
      // Set in the math font, copied as their source.
      final fonts =
          recordedRunSync(modernRecorded, 'pdffonts', [pdf]).stdout as String;
      expect(fonts, contains('NotoSansMath'));
      final text = modernPages(pdf).first.join(' ');
      expect(text, contains('x^2'));
      expect(text, contains('sum_(i=1)^n i'));
      expect(text, contains(r'\frac{a}{b}'));
      expect(text, contains(r'\sqrt{2}'));
    });

    test('an unknown LaTeX command is shown and reported', () {
      final logger = MemoryLogger();
      // (Each occurrence reported, though the formula is converted once.)
      modernPdf(
        ':stem: latexmath\n\nstem:[\\foo x] and stem:[\\foo x]\n',
        logger: logger,
      );
      expect(
        logger.messages
            .where((m) => m.severity == Severity.warn)
            .map((m) => m.message.text),
        [
          for (var i = 0; i < 2; i++)
            r'unknown LaTeX math command \foo, shown as written: \foo x',
        ],
      );
    });

    test('inline math stands on the baseline, its depth below', () {
      double? bottom(String pdf, String word) => switch (RegExp(
        'yMax="([\\d.]+)"[^>]*>${RegExp.escape(word)}<',
      ).firstMatch(
        recordedRunSync(modernRecorded, 'pdftotext', ['-bbox', pdf, '-']).stdout
            as String,
      )) {
        final m? => double.parse(m[1]!),
        null => null,
      };
      final plain = modernPdf(':stem:\n\nBefore after.\n');
      final math = modernPdf(':stem:\n\nBefore stem:[a/b] after.\n');
      // The line's text where it was: a fraction no taller than the line
      // leaves the baseline alone.
      expect(bottom(math, 'Before'), closeTo(bottom(plain, 'Before')!, 0.5));
    });

    test('a display formula is centered, larger than inline', () {
      final pdf = modernPdf(':stem:\n\n[stem]\n++++\nsum_(i=1)^n i\n++++\n');
      final content = modernContent(pdf);
      // The display sum (a larger variant than the text's) is drawn.
      expect(content, contains('Tf'));
      final info =
          recordedRunSync(modernRecorded, 'pdfinfo', [pdf]).stdout as String;
      final width = double.parse(
        RegExp(r'Page size:\s+([\d.]+)').firstMatch(info)![1]!,
      );
      final xs = [
        for (final m in RegExp(r'([\d.]+) ([\d.]+) Td').allMatches(content))
          double.parse(m[1]!),
      ];
      expect(xs, isNotEmpty);
      // Not at the left margin.
      expect(xs.reduce(math.min), greaterThan(width / 4));
    });

    test('math_font_family must name a font with a MATH table', () {
      final logger = MemoryLogger();
      modernPdf(
        ':stem:\n\nstem:[x]\n',
        theme: 'math_font_family: Noto Serif\n',
        logger: logger,
      );
      expect(
        logger.messages.map((m) => m.message.text),
        contains(contains('is not a font with a MATH table')),
      );
    });
  });

  group("asciidoctor-pdf's look (asciidoctor-compat, ADR-0015)", () {
    const images = 'test/pdf/fixtures/images';

    test('block_margin_collapse: false adds the spaces around a heading', () {
      const source = 'Para one.\n\n== Heading\n\nPara two.\n';
      final collapsed = modernTop(modernPdf(source), 'Heading')!;
      final added = modernTop(
        modernPdf(source, theme: 'block_margin_collapse: false\n'),
        'Heading',
      )!;
      expect(added, greaterThan(collapsed + 3));
      expect(
        modernTop(
          modernPdf(source, attributes: {'asciidoctor-compat': 'pdf'}),
          'Heading',
        ),
        added,
      );
    });

    test('base_hyphens: false leaves justified text unhyphenated', () {
      const theme = 'page_size: A7\n';
      bool hyphenated(String pdf) => modernPages(pdf).any(
        (lines) =>
            lines.any((line) => RegExp('[a-z][-\u00ad]\$').hasMatch(line)),
      );
      expect(hyphenated(modernPdf(modernParagraph, theme: theme)), isTrue);
      expect(
        hyphenated(
          modernPdf(modernParagraph, theme: '${theme}base_hyphens: false\n'),
        ),
        isFalse,
      );
    });

    test('toc_macro_in_section: false gives the contents their own page', () {
      const source =
          '= Book\n:doctype: book\n:toc: macro\n\n== Contents\n\n'
          'toc::[]\n\n== One\n\nText.\n';
      final inSection = modernPages(modernPdf(source));
      expect(inSection[1].first, 'Contents');
      expect(inSection[1].join(' '), contains('One'));
      final ownPage = modernPages(
        modernPdf(source, attributes: {'asciidoctor-compat': 'true'}),
      );
      expect(ownPage[1], ['Contents']);
      expect(ownPage[2].first, 'Table of Contents');
      // The theme's own value wins.
      expect(
        modernPages(
          modernPdf(
            source,
            theme: 'toc_macro_in_section: true\n',
            attributes: {'asciidoctor-compat': 'pdf'},
          ),
        )[1].first,
        'Contents',
      );
    });

    test('a title logo fits the page below its top', () {
      final pdf = modernPdf(
        '= Doc\n:title-page:\n:imagesdir: ${Directory.current.path}/$images\n'
        ':title-logo-image: image:tall.png[pdfwidth=100%,top=70%]\n\nText.\n',
      );
      final bottom = RegExp(r'[\d.]+ 0 0 [\d.]+ [\d.]+ ([\d.]+) cm')
          .firstMatch(modernContent(pdf))!;
      // On the page: at or above the bottom margin (0.67in).
      expect(double.parse(bottom[1]!), greaterThanOrEqualTo(48.24 - 0.01));
    });

    test("an autowidth table's column is as wide as its image", () {
      final content = modernContent(
        modernPdf(
          ':imagesdir: ${Directory.current.path}/$images\n\n'
          '[%autowidth]\n|===\n'
          '|image:red.png[] |image:red.png[width=50%]\n|===\n',
        ),
      );
      final widths = [
        for (final m in RegExp(
          r'([\d.]+) 0 0 ([\d.]+) [\d.]+ [\d.]+ cm',
        ).allMatches(content))
          double.parse(m[1]!),
      ];
      // Natural (32px at 0.75) and half of that column.
      expect(widths, [24, 12]);
    });

    test('a word longer than a line across index terms breaks', () {
      final pdf = modernPdf(
        '((foo))((bar))((baz))((boom))((bang))((fee))((fi))((fo))((fum))'
        '((fan))((fool))((ying))((yang))((zed))',
        theme: 'page_size: A7\n',
      );
      expect(modernPages(pdf).first.length, greaterThan(1));
    });

    test('a heading moves with an unbreakable block that would not fit', () {
      final filler = List.filled(36, 'Line.').join('\n\n');
      final pdf = modernPdf(
        '$filler\n\n== Heading\n\n[%unbreakable]\n--\n'
        '${List.filled(8, 'Kept.').join('\n\n')}\n--\n',
        theme: 'heading_min_height_after: auto\n',
      );
      final pages = modernPages(pdf);
      // The heading on the page of the whole block, not alone at the
      // bottom of the page before.
      final page = pages.firstWhere((lines) => lines.contains('Heading'));
      expect(page.where((line) => line == 'Kept.'), hasLength(8));
    });

    test('an image that is not one is reported, not a failure', () {
      File('${modernDir.path}/corrupt.png').writeAsStringSync('not an image');
      final logger = MemoryLogger();
      final pdf = modernPdf(
        '= Doc\n:page-background-image: image:corrupt.png[]\n\nText.\n',
        attributes: {'imagesdir': modernDir.path},
        logger: logger,
      );
      expect(File(pdf).existsSync(), isTrue);
      expect(
        logger.messages.map((m) => m.message.text),
        contains(contains('could not embed page background image')),
      );
    });
  });
}
