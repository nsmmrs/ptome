// The modern engine (the default): what it does differently from the
// asciidoctor-pdf compatibility mode, read back from the PDFs it makes;
// part 2 of 4: the layout keys, from the contents to the study Bible (test/pdf/support/modern.dart).
@TestOn('vm')
library;

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
  modernRecorded = Oracle('pdf_modern_1', compressed: true);
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

    test('a toc macro that opens a section is its contents', () {
      final pdf = modernPdf(
        '= Book\n:doctype: book\n:toc: macro\n\n[preface]\n== Before\n\n'
        'Text.\n\n[#contents]\n== Contents\n\ntoc::[]\n\n== Chapter\n\n'
        'Text.\n',
      );
      final pages = modernPages(pdf);
      final page = pages.indexWhere((p) => p.contains('Contents'));
      // The heading, then the entries on its page: the section listed
      // too, no title of the toc's own.
      expect(pages[page].join(' '), contains('Before'));
      expect(pages[page].where((l) => l.startsWith('Contents')), hasLength(2));
      expect(pages.expand((p) => p).join(' '), isNot(contains('Table of')));
    });

    test('toc_entry_spacing: the space between entries', () {
      const source =
          '= Book\n:doctype: book\n:toc:\n\n== One\n\nA.\n\n== Two\n\nB.\n';
      double gap(String pdf) =>
          words(pdf).where((w) => w.$1 == 'Two').first.$4 -
          words(pdf).where((w) => w.$1 == 'One').first.$4;
      final plain = modernPdf(source, theme: 'base_leading: 0.6em\n');
      final spaced = modernPdf(
        source,
        theme: 'base_leading: 0.6em\ntoc_entry_spacing: 20\n',
      );
      expect(gap(spaced) - gap(plain), greaterThan(5));
    });

    test('heading_h1_vertical_align: a part title in the middle', () {
      final pdf = modernPdf(
        '= Book\n:doctype: book\n\n= Part\n\n== Chapter\n\nText.\n',
        theme: 'heading_h1_vertical_align: middle\n',
      );
      final part = word(pdf, 'Part');
      // A Letter or A4 page: the title near its middle.
      expect(part.$4, greaterThan(300));
      expect(part.$4, lessThan(500));
    });

    test("a section's heading margin collapses with the space above", () {
      const source = '= Doc\n\nText.\n\n== Section\n\nMore.\n';
      double gap(String pdf) => word(pdf, 'Section').$4 - word(pdf, 'Text.').$4;
      final a = modernPdf(source, theme: 'heading_margin_top: 4\n');
      final b = modernPdf(source, theme: 'heading_margin_top: 8\n');
      // Below the block's own space (12, the default): no difference.
      expect(gap(b) - gap(a), closeTo(0, 0.01));
      final c = modernPdf(source, theme: 'heading_margin_top: 30\n');
      expect(gap(c) - gap(a), closeTo(18, 0.01));
    });

    test('footnotes_indent and footnotes_label_gap', () {
      const source = '= Doc\n\nText.footnote:[A note here.]\n';
      final plain = word(modernPdf(source), 'note');
      final set = word(
        modernPdf(
          source,
          theme: 'footnotes_indent: 20\nfootnotes_label_gap: 5\n',
        ),
        'note',
      );
      expect(set.$3 - plain.$3, closeTo(25, 0.5));
    });

    test('base_typographic_scripts: superscripts in the superior figures', () {
      const fonts =
          'font:\n  catalog:\n    merge: true\n    Scripts:\n'
          '      normal: libertinus-scripts.otf\n'
          'base_font_family: Scripts\n';
      const source = 'Text^2^ and more.\n';
      final raised = modernContent(modernPdf(source, theme: fonts));
      final typographic = modernContent(
        modernPdf(source, theme: '${fonts}base_typographic_scripts: true\n'),
      );
      // Smaller and raised, or at the text's size on its baseline.
      expect(raised, contains('/F1 6.1215 Tf'));
      expect(typographic, isNot(contains('6.1215 Tf')));
      final baselines = {
        for (final m in RegExp(r'[\d.]+ ([\d.]+) Td').allMatches(typographic))
          m[1]!,
      };
      expect(baselines.where((y) => double.parse(y) > 700), hasLength(1));
    });

    test('description_list_term_gap: the space after a run-in term', () {
      const source = 'Term:: Description here.\n';
      const inline = 'description_list_term_display: inline\n';
      final en = word(modernPdf(source, theme: inline), 'Description').$3;
      final wide = word(
        modernPdf(source, theme: '${inline}description_list_term_gap: 30\n'),
        'Description',
      ).$3;
      expect(wide, greaterThan(en + 20));
    });

    test('a highlighted token that runs over lines keeps its indentation', () {
      final pdf = modernPdf(
        ':source-highlighter: highlight.js\n\n[source,html]\n----\n'
        '<button onclick="one\n                two\nthree">\n----\n',
      );
      // Sixteen spaces in: further in than the line after.
      expect(
        word(pdf, 'two').$3 - word(pdf, 'three&quot;&gt;').$3,
        greaterThan(50),
      );
    });

    test('a text file as an image: its text, preformatted', () {
      File('${modernDir.path}/art.txt')
          .writeAsStringSync('+--+\n|  |  X\n+--+\n');
      final pdf = modernPdf(
        '= Doc\n\n.Art\nimage::art.txt[]\n',
        theme: 'image_align: center\n',
      );
      final art = words(pdf);
      expect(art.map((w) => w.$1), containsAllInOrder(['+--+', '|', 'X']));
      // The block centered, its lines at its left: the X keeps its column.
      final top = art.firstWhere((w) => w.$1 == '+--+');
      final x = art.firstWhere((w) => w.$1 == 'X');
      expect(top.$3, greaterThan(200));
      expect(x.$3 - top.$3, greaterThan(20));
      expect(art.map((w) => w.$1), contains('Art'));
    });

    test('heading_min_height_after: auto keeps a heading with its text', () {
      // A heading near the bottom, a three-line paragraph after it (too
      // short to split): both on the next page.
      final filler = [for (var i = 0; i < 42; i++) 'Filler $i.\n'].join('\n');
      final source =
          '= Doc\n\n$filler\n== Heading\n\n${'Long words here. ' * 24}\n';
      final kept = modernPdf(source, theme: 'heading_min_height_after: auto\n');
      final heading = word(kept, 'Heading');
      final text = word(kept, 'Long');
      expect(heading.$2, text.$2);
    });

    test('a concealed index term keeps the space before it', () {
      final pdf = modernPdf('When (((HTML)))HTML was.\n');
      expect(modernPages(pdf).first.join(' '), contains('When HTML was.'));
    });

    test('a URL breaks as The Chicago Manual of Style has it', () {
      final pdf = modernPdf(
        '${'word ' * 12}https://example.org/2016/01/18/a-long-path-here.html\n',
      );
      final lines = modernPages(pdf).first;
      // Broken inside the address before a slash (the slash starts the
      // next line, as the rule has it, so the break can't be taken for
      // the URL's end), with no hyphen added.
      expect(lines.first, isNot(endsWith('/')));
      expect(lines.first, contains('example.org'));
      expect(lines[1], startsWith('/'));
      expect(lines.join(), isNot(contains('-\n')));
      expect(
        lines.take(2).join().replaceAll(RegExp(r'\s'), ''),
        contains('example.org/2016/01/18/a-long-path-here.html'),
      );
    });

    test('a run-in term: its gap breaks, an index term adds no space', () {
      const inline =
          'description_list_term_display: inline\n'
          'description_list_term_gap: 20\n';
      final plain = word(
        modernPdf('Term:: Description here.\n', theme: inline),
        'Description',
      ).$3;
      final indexed = word(
        modernPdf('Term::\n(((term)))\nDescription here.\n', theme: inline),
        'Description',
      ).$3;
      expect(indexed, closeTo(plain, 0.01));
    });

    test('<category>_caption_indent sets a caption in', () {
      const source = '= Doc\n\n.Code\n----\nx\n----\n';
      final plain = word(modernPdf(source), 'Code').$3;
      final set = word(
        modernPdf(source, theme: 'code_caption_indent: 12\n'),
        'Code',
      );
      expect(set.$3 - plain, closeTo(12, 0.01));
    });

    test("a look's measure sets the side margins", () {
      File('${modernDir.path}/narrow-look.yml').writeAsStringSync(
        'extends: ptome\ntokens:\n'
        '  size: { text: { print: 10pt } }\n'
        '  measure: { print: 30em }\n'
        '  page: { size: A4, margin: ~ }\n',
      );
      final pdf = modernPdf(
        '= Doc\n:nofooter:\n\nWords.\n',
        attributes: {
          'looksdir': modernDir.path,
          'look': 'narrow',
          'pdf-theme!': '',
        },
      );
      // 30em of 10pt is 300pt: centered on A4's 595.28pt.
      final x = double.parse(
        RegExp(r'xMin="([\d.]+)"[^>]*>Words').firstMatch(
          recordedRunSync(modernRecorded, 'pdftotext', [
                '-bbox',
                pdf,
                '-',
              ]).stdout
              as String,
        )![1]!,
      );
      expect(x, closeTo((595.28 - 300) / 2, 0.5));
    });

    test("a document's look is its PDF theme; a named theme replaces it", () {
      // A look that sets the text size; a theme that extends it.
      File('${modernDir.path}/big-look.yml').writeAsStringSync(
        'extends: ptome\ntokens:\n  size: { text: { print: 14pt } }\n',
      );
      File('${modernDir.path}/over-theme.yml')
          .writeAsStringSync('extends: look\nheading:\n  font_color: FF0000\n');
      // (No pdf-theme: the helper's default unset.)
      final looks = {
        'looksdir': modernDir.path,
        'look': 'big',
        'pdf-theme!': '',
      };
      String sizes(String pdf) =>
          RegExp(r'/F\d+ (\d+(?:\.\d+)?) Tf')
              .allMatches(modernContent(pdf))
              .map((m) => m[1])
              .toSet()
              .join(' ');
      final looked = modernPdf('= Doc\n\nText.\n', attributes: looks);
      expect(sizes(looked), contains('14'));
      // A theme the document names replaces the look...
      final named = modernPdf(
        '= Doc\n\nText.\n',
        attributes: {'looksdir': modernDir.path, 'look': 'big'},
      );
      expect(sizes(named), isNot(contains('14')));
      // ...unless it extends it.
      final extended = modernPdf(
        '= Doc\n\n== Heading\n\nText.\n',
        attributes: {
          'looksdir': modernDir.path,
          'look': 'big',
          'pdf-theme': 'over',
          'pdf-themesdir': modernDir.path,
        },
      );
      expect(sizes(extended), contains('14'));
      expect(modernContent(extended), contains('1 0 0 rg'));
    });

    test("a look's title page: its slots in order, a verso after it", () {
      File('${modernDir.path}/tp-look.yml').writeAsStringSync('''
extends: ptome
templates:
  title-page:
    recto:
      - { slot: authors, separator: ' & ' }
      - { slot: title, space-before: 2in }
      - subtitle
      - { attribute: publisher, space-before: 3in }
    verso:
      - { attribute: copyright }
      - { slot: revision, before: 'Edition: ' }
''');
      final pdf = modernPdf(
        '= The Art of Slots: Title Pages\n'
        'Ada Lovelace; Charles Babbage\n'
        'v2.1, 2026-10-11\n'
        ':doctype: book\n:publisher: Anticomplex\n'
        ':copyright: Copyright 2026\n\n== One\n\nText.\n',
        attributes: {
          'looksdir': modernDir.path,
          'look': 'tp',
          'pdf-theme!': '',
        },
      );
      final pages = modernPages(pdf);
      expect(pages[0], [
        'Ada Lovelace & Charles Babbage',
        'The Art of Slots',
        'Title Pages',
        'Anticomplex',
      ]);
      expect(pages[1], ['Copyright 2026', 'Edition: Version 2.1, 2026-10-11']);
      expect(pages[2].first, 'One');
      // (The slots placed by their space, not the theme's title_top.)
      expect(modernTop(pdf, 'Art')! - modernTop(pdf, 'Ada')!, greaterThan(144));
      expect(
        modernTop(pdf, 'Anticomplex')! - modernTop(pdf, 'Title')!,
        greaterThan(216),
      );
    });

    test("a theme's title_page_recto: its parts alone, margins as lengths", () {
      const source =
          '= Doc Title\nAn Author\nv1.0\n:doctype: book\n\n'
          '== One\n\nText.\n';
      final plain = modernPages(modernPdf(source))[0];
      expect(plain, ['Doc Title', 'An Author', 'Version 1.0']);
      final pdf = modernPdf(
        source,
        theme:
            'title_page:\n  recto:\n  - revision\n'
            '  - content: title\n    margin-top: 1in\n',
      );
      expect(modernPages(pdf)[0], ['Version 1.0', 'Doc Title']);
      expect(
        modernTop(pdf, 'Doc')! - modernTop(pdf, 'Version')!,
        greaterThan(72),
      );
    });

    test("a heading's number hung in the margin, or on a line of its own", () {
      double x(String pdf, String word) => double.parse(
        RegExp('xMin="([\\d.]+)"[^>]*>${RegExp.escape(word)}<').firstMatch(
          recordedRunSync(modernRecorded, 'pdftotext', [
                '-bbox',
                pdf,
                '-',
              ]).stdout
              as String,
        )![1]!,
      );
      const source =
          '= Act\n\n== [.number]#17# Offences\n\nWords at the margin.\n';
      final hung = modernPdf(
        source,
        theme: 'heading:\n  number_placement: hang\n  number_hang: 40\n',
      );
      // The title at the text's edge, its number 40 pt left of it.
      expect(x(hung, 'Offences'), closeTo(x(hung, 'Words'), 0.5));
      expect(x(hung, '17'), closeTo(x(hung, 'Words') - 40, 0.5));
      expect(modernTop(hung, '17'), closeTo(modernTop(hung, 'Offences')!, 0.5));
      final lined = modernPdf(
        source,
        theme: 'heading:\n  number_placement: line\n',
      );
      expect(
        modernTop(lined, 'Offences'),
        greaterThan(modernTop(lined, '17')! + 10),
      );
      expect(x(lined, 'Offences'), closeTo(x(lined, '17'), 0.5));
      // Without a placement, in its line.
      final inline = modernPdf(source);
      expect(
        modernTop(inline, '17'),
        closeTo(modernTop(inline, 'Offences')!, 0.5),
      );
      expect(x(inline, 'Offences'), greaterThan(x(inline, '17')));
    });

    test('[.columns]: a section or open block in balanced columns', () {
      const para =
          'Avalanches of this kind, called slab avalanches, form when a '
          'cohesive layer of snow rests on a weaker layer beneath it. ';
      final body = [
        for (final n in [2, 3, 1, 2, 3]) para * n,
      ].join('\n\n');
      final source =
          '= Doc\n\nIntro.\n\n[.columns]\n== Science\n\n$body\n\n'
          '== After\n\nAcross.\n\n[.columns,column-count=2]\n--\n$body\n--\n';
      List<int> counts(String pdf, String from, String to, int columns) {
        final out =
            recordedRunSync(modernRecorded, 'pdftotext', [
                  '-bbox',
                  '-f',
                  '1',
                  '-l',
                  '1',
                  pdf,
                  '-',
                ]).stdout
                as String;
        final words = [
          for (final m in RegExp(
            r'xMin="([\d.]+)" yMin="([\d.]+)"[^>]*>([^<]*)<',
          ).allMatches(out))
            (double.parse(m[1]!), double.parse(m[2]!), m[3]!),
        ];
        final top = words.firstWhere((w) => w.$3 == from).$2;
        final bottom = words.firstWhere((w) => w.$3 == to).$2;
        final width = 612 / columns;
        final lines = [for (var i = 0; i < columns; i++) <double>{}];
        for (final (x, y, _) in words) {
          if (y > top + 1 && y < bottom - 1) {
            lines[(x / width).floor().clamp(0, columns - 1)].add(y);
          }
        }
        return [for (final l in lines) l.length];
      }

      final pdf = modernPdf(source, theme: 'columns_count: 3\n');
      final three = counts(pdf, 'Science', 'After', 3);
      // Balanced: the last at most a line shorter than the first.
      expect(
        three.first - three.last,
        inInclusiveRange(0, 1),
        reason: '$three',
      );
      expect(three.every((n) => n > 5), isTrue, reason: '$three');
      // asciidoctor-pdf's: one column (no gutter in its lines).
      double widestGap(String pdf) {
        final out =
            recordedRunSync(modernRecorded, 'pdftotext', [
                  '-bbox',
                  '-f',
                  '1',
                  '-l',
                  '1',
                  pdf,
                  '-',
                ]).stdout
                as String;
        final byLine = <double, List<(double, double)>>{};
        for (final m in RegExp(
          r'xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)"[^>]*>(?:[^<]*)<',
        ).allMatches(out)) {
          (byLine[double.parse(m[2]!)] ??= []).add((
            double.parse(m[1]!),
            double.parse(m[3]!),
          ));
        }
        var widest = 0.0;
        for (final words in byLine.values) {
          words.sort((a, b) => a.$1.compareTo(b.$1));
          for (var k = 1; k < words.length; k++) {
            widest = math.max(widest, words[k].$1 - words[k - 1].$2);
          }
        }
        return widest;
      }

      expect(widestGap(pdf), greaterThan(10));
      expect(widestGap(modernPdf(source, compat: true)), lessThan(10));
    });

    test("a paragraph's initial: its own first letter, lines deep", () {
      const theme =
          'role:\n  dropcap:\n    drop_lines: 3\n    drop_lead_in: 2\n'
          '  lead-in:\n    text_transform: uppercase\n';
      final pdf = modernPdf(
        '= Doc\n\n[.dropcap]\nThe snow came in the night, the first big '
        'storm of the season, and by morning the ridge above the creek held '
        'more than two feet of new powder, and sixteen skiers gathered at '
        'the top of the lift to wait for the others.\n\n'
        '[.dropcap]\n"`It was long,`" she said.\n\nAfter.\n',
        theme: theme,
      );
      final bbox =
          recordedRunSync(modernRecorded, 'pdftotext', [
                '-bbox',
                pdf,
                '-',
              ]).stdout
              as String;
      ({double x, double top, double bottom}) box(String word) {
        final m = RegExp(
          r'xMin="([\d.]+)" yMin="([\d.]+)" xMax="[\d.]+" '
          'yMax="([\\d.]+)">${RegExp.escape(word)}<',
        ).firstMatch(bbox)!;
        return (
          x: double.parse(m[1]!),
          top: double.parse(m[2]!),
          bottom: double.parse(m[3]!),
        );
      }

      // The letter beside three lines, the text after it; its first two
      // words (what's left of the first) in the lead-in's role.
      final initial = box('T');
      final he = box('HE');
      expect(he.x, greaterThan(initial.x + 10));
      expect(initial.bottom - initial.top, greaterThan(25));
      expect(bbox, contains('>SNOW<'));
      expect(bbox, contains('>came<'));
      // Opening punctuation hung left of the text's edge.
      expect(box('“I').x, lessThan(box('After.').x));
      // A paragraph shorter than its initial: what follows clears it.
      expect(box('After.').top, greaterThan(box('“I').bottom));
      // asciidoctor-pdf's: no initial.
      final plain =
          recordedRunSync(modernRecorded, 'pdftotext', [
                modernPdf(
                  '[.dropcap]\nThe snow.\n',
                  compat: true,
                  theme: theme,
                ),
                '-',
              ]).stdout
              as String;
      expect(plain, contains('The snow.'));
    });

    test('a paragraph runs around a block floating to a side', () {
      const words =
          'The first skiers made it down without incident, stopping in a '
          'cluster of trees to wait for the others while the slope above '
          'them began to move. ';
      final pdf = modernPdf(
        '= Doc\n\n[.pull]\n____\nIt was the longest minute of my '
        'life.\n____\n\n${words * 6}\n',
        theme:
            'role:\n  pull:\n    float: right\n    float_width: 50%\n'
            '    float_gap: 12\n',
      );
      final out =
          recordedRunSync(modernRecorded, 'pdftotext', [
                '-bbox',
                pdf,
                '-',
              ]).stdout
              as String;
      // Each line's right end, top to bottom.
      final ends = <double, double>{};
      final quote = <double>{};
      for (final m in RegExp(
        r'yMin="([\d.]+)" xMax="([\d.]+)"[^>]*>([^<]*)<',
      ).allMatches(out.replaceAll(RegExp(r'xMin="[\d.]+" '), ''))) {
        final y = double.parse(m[1]!);
        final x = double.parse(m[2]!);
        if (const {'longest', 'minute', 'life.'}.contains(m[3])) {
          quote.add(y);
        } else if (m[3] != 'Doc') {
          ends[y] = math.max(ends[y] ?? 0, x);
        }
      }
      final rows = [
        for (final y in ends.keys)
          if (!quote.contains(y)) y,
      ]..sort();
      // The first lines beside the quote end short of it; those after it
      // run on across the page.
      expect(rows.take(2).map((y) => ends[y]!), everyElement(lessThan(300)));
      expect(
        rows.skip(2).map((y) => ends[y]!).reduce(math.max),
        greaterThan(450),
      );
      expect(quote, isNotEmpty);
    });

    test("a section role's page template: its pages, then the layout's", () {
      const theme =
          'section:\n  role:\n    feature:\n'
          '      page_margin: [72, 144, 72, 144]\n'
          '      page_background_color: F3EBDD\n'
          '      page_running_content: none\n';
      final words = 'Words of the piece run on across the page. ' * 10;
      final pdf = modernPdf(
        '= Issue\n\n== News\n\n$words\n\n[.feature]\n== Feature\n\n'
        '$words\n\n== Letters\n\n$words\n',
        theme: theme,
      );
      final pages = [
        for (final page in modernPages(pdf))
          if (page.isNotEmpty) page,
      ];
      expect(pages, hasLength(3));
      expect(pages[1].first, 'Feature');
      expect(pages[2].first, 'Letters');
      // Its margins: the text 144 pt in; its tint; no running content.
      final bbox =
          recordedRunSync(modernRecorded, 'pdftotext', [
                '-bbox',
                '-f',
                '2',
                '-l',
                '2',
                pdf,
                '-',
              ]).stdout
              as String;
      expect(
        RegExp(r'xMin="([\d.]+)"[^>]*>Words<')
            .allMatches(bbox)
            .map((m) => double.parse(m[1]!))
            .reduce(math.min),
        closeTo(144, 0.5),
      );
      final footers =
          recordedRunSync(modernRecorded, 'pdftotext', [
                '-layout',
                pdf,
                '-',
              ]).stdout
              as String;
      expect(
        footers.split('\f')[1],
        isNot(contains(RegExp(r'^\s*2\s*$', multiLine: true))),
      );
      expect(modernContent(pdf), contains('0.95294 0.92157 0.86667 rg'));
      // Its columns: two, the text starting at both.
      final columned = modernPdf(
        '= Issue\n\n[.feature]\n== Feature\n\n$words $words\n',
        theme: '$theme      page_columns: 2\n',
      );
      final starts = RegExp(r'<line xMin="([\d.]+)"')
          .allMatches(
            recordedRunSync(modernRecorded, 'pdftotext', [
                  '-bbox-layout',
                  columned,
                  '-',
                ]).stdout
                as String,
          )
          .map((m) => double.parse(m[1]!).round())
          .toSet();
      expect(starts, containsAll([144]));
      expect(starts.where((x) => x > 250), isNotEmpty, reason: '$starts');
      // Last in the document: no page after it.
      final last = modernPdf(
        '= Issue\n\n== News\n\n$words\n\n[.feature]\n== Feature\n\n$words\n',
        theme: theme,
      );
      expect(modernPages(last).where((p) => p.isNotEmpty), hasLength(2));
      // asciidoctor-pdf's: no page of its own.
      final compat = modernPdf(
        '= Issue\n\n== News\n\nText.\n\n[.feature]\n== Feature\n\nText.\n',
        theme: theme,
        compat: true,
      );
      expect(modernPages(compat).where((p) => p.isNotEmpty), hasLength(1));
    });

    test('pagination: optimal spreads the room a kept block leaves', () {
      final paragraph = List.filled(
        110,
        'The keepers logged the weather and painted the tower.',
      ).join(' ');
      final block = [for (var i = 1; i <= 40; i++) 'Line $i of the log.'];
      final source =
          '$paragraph\n\n[%unbreakable]\n....\n${block.join('\n')}\n....\n';
      List<int> perPage(String mode) => [
        for (final page in modernPages(
          modernPdf(source, theme: 'pagination: $mode\n'),
        ))
          if (page.isNotEmpty)
            page.where((l) => l.contains(RegExp('[a-z]'))).length,
      ];
      final firstFit = perPage('first_fit');
      final optimal = perPage('optimal');
      // One page at a time: a full page, then a few lines alone before the
      // block; together, the paragraph halved over two pages.
      expect(firstFit.length, 3);
      expect(firstFit[0] - firstFit[1], greaterThan(20));
      expect(optimal.length, 3);
      expect((optimal[0] - optimal[1]).abs(), lessThanOrEqualTo(1));
      expect(optimal.last, firstFit.last);
    });

    test(
      'no runt: a last line too short is set another way when it can be',
      () {
        const source =
            '[.text-justify]\nThe keepers logged the weather four times a day '
            'and painted the tower every third summer while the\n';
        List<String> lines(String theme) => [
          for (final line in modernPages(modernPdf(source, theme: theme)).first)
            if (RegExp('[a-z]').hasMatch(line)) line,
        ];
        // A last line of one word; with a least of 40%, none.
        expect(lines('').last, 'the');
        expect(
          lines('base:\n  last_line_min_width: 40%\n').last,
          endsWith('while the'),
        );
      },
    );

    test('protrusion the line breaker counts: a hanging comma fits', () {
      final text = List.filled(
        12,
        'Go on, then. Do it, now: run, fast. Yes, again.',
      );
      final source =
          '[cols="1,3"]\n|===\na|[.text-justify]\n${text.join(' ')}\n'
          '| \n|===\n';
      List<String> lines({required bool overhang}) => [
        for (final line in modernPages(
          modernPdf(source, theme: 'base:\n  overhang: $overhang\n'),
        ).expand((page) => page))
          line.replaceAll(RegExp(r'\s+'), ' '),
      ];
      // A line can end "now: run," only when its comma may hang.
      bool ends(String line) => line.endsWith('now: run,');
      expect(lines(overhang: false).where(ends), isEmpty);
      expect(lines(overhang: true).where(ends), isNotEmpty);
    });

    test('font expansion and protrusion at the left of justified lines', () {
      final words =
          'Words of the piece run on across the page, set justified. ' * 8;
      final source =
          '[.text-justify]\n$words\n\n[.text-justify]\n\u201cA quote opens '
          'this line, its mark hanging into the margin before the text.\u201d '
          '$words\n';
      // The horizontal scales the lines are set at.
      List<double> scales(String pdf) => [
        for (final m in RegExp(r'([\d.]+) Tz').allMatches(modernContent(pdf)))
          double.parse(m[1]!),
      ];
      final plain = modernPdf(source, theme: 'base:\n  overhang: true\n');
      expect(scales(plain).where((s) => s != 100), isEmpty);
      final expanded = modernPdf(
        source,
        theme: 'base:\n  font_expansion: true\n',
      );
      final set = scales(expanded).where((s) => s != 100).toList();
      expect(set, isNotEmpty);
      expect(set.every((s) => s >= 98 - 1e-6 && s <= 102 + 1e-6), isTrue);
      // The opening quote hangs left of the text's edge.
      final bbox =
          recordedRunSync(modernRecorded, 'pdftotext', [
                '-bbox',
                plain,
                '-',
              ]).stdout
              as String;
      final quote = double.parse(
        RegExp(r'xMin="([\d.]+)"[^>]*>\u201cA<').firstMatch(bbox)![1]!,
      );
      final edge = double.parse(
        RegExp(r'xMin="([\d.]+)"[^>]*>Words<').firstMatch(bbox)![1]!,
      );
      expect(quote, lessThan(edge - 0.5));
    });

    test('a page frame: rules around the text, from the outside in', () {
      const theme =
          'page_frame:\n  width: [3, 1]\n  gap: 2\n  offset: 10\n'
          "  color: 'FF0000'\n";
      final content = modernContent(modernPdf('Text.\n', theme: theme));
      expect(content, contains('1 0 0 RG'));
      // The thick rule outside, the thin one inside it.
      final rules = RegExp(r'([\d.]+) w\n([\d.-]+) ([\d.-]+) [\d.]+ [\d.]+ re')
          .allMatches(content)
          .map((m) => (double.parse(m[1]!), double.parse(m[2]!)))
          .toList();
      expect(rules.map((r) => r.$1), containsAllInOrder([3, 1]));
      expect(rules.first.$2, lessThan(rules.last.$2));
      expect(
        modernContent(modernPdf('Text.\n', theme: theme, compat: true)),
        isNot(contains('1 0 0 RG')),
      );
    });

    test('tracking: a role, a heading, and capitals by themselves', () {
      // Where the word [word] starts and ends on the first page of [pdf].
      (double, double) extent(String pdf, String word) {
        final m = RegExp('xMin="([\\d.]+)"[^>]*xMax="([\\d.]+)"[^>]*>$word<')
            .firstMatch(
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
            )!;
        return (double.parse(m[1]!), double.parse(m[2]!));
      }

      double width(String pdf, String word) {
        final (left, right) = extent(pdf, word);
        return right - left;
      }

      const source =
          '== Heading\n\nThe NASA probe [.spaced]#wide# and plain words.\n';
      final plain = modernPdf(source, theme: 'base:\n  font_size: 10\n');
      final tracked = modernPdf(
        source,
        theme:
            'base:\n  font_size: 10\ncaps_letter_spacing: 0.1em\n'
            'role:\n  spaced:\n    letter_spacing: 1.2\n'
            'heading:\n  h2_letter_spacing: 0.04em\n',
      );
      // Four capitals a tenth of an em further apart: three gaps, 3 pt
      // wider (the half spaces outside them aren't ink); lower case as it
      // was; the role's four letters 1.2 pt each: what follows them 4 +
      // 4.8 pt further on.
      expect(width(tracked, 'NASA') - width(plain, 'NASA'), closeTo(3, 0.3));
      expect(width(tracked, 'probe'), closeTo(width(plain, 'probe'), 0.05));
      expect(
        extent(tracked, 'and').$1 - extent(plain, 'and').$1,
        closeTo(8.8, 0.3),
      );
      expect(
        width(tracked, 'Heading'),
        greaterThan(width(plain, 'Heading') + 3),
      );
    });

    test('notes at the foot: run in, then study notes in columns', () {
      // A study Bible's page: the translators' notes run in under the
      // text, the study notes under them in three columns, a heading
      // over a run of them; study notes too long for a page go on in
      // their own place on the next (under the translators' notes there).
      final schemes = Directory('${modernDir.path}/schemes')..createSync();
      for (final f in Directory('test/units/fixtures/schemes').listSync()) {
        if (f is File) {
          f.copySync('${schemes.path}/${f.uri.pathSegments.last}');
        }
      }
      File('${schemes.path}/study.yml')
          .writeAsStringSync('stream:\n  sn:\n    placement: "footnote"\n');
      final study = [
        for (var k = 0; k < 4; k++)
          'Study$k the words of the verse read with the others, at length.',
      ].join(' ');
      String verse(int v) {
        final heading = v == 1 ? '[.heading]#The Days of Creation# ' : '';
        return '@ Verse $v ##text##note:tn[Heb. tn$v] goes '
            'on.note:sn[$heading*1:$v* Lemma$v $study]\n';
      }

      final verses = [for (var v = 1; v <= 8; v++) verse(v)].join('\n');
      final pdf = modernPdf(
        '= Notes\n:units: bible, kjv, study\n\n== @GEN\n\n=== @1\n\n$verses',
        theme:
            'page:\n  size: [360, 400]\n  margin: [36, 36, 36, 36]\n'
            'note_streams: [tn, sn]\n'
            'note_stream:\n'
            '  tn:\n    arrangement: run_in\n'
            '  sn:\n    columns: 3\n    column_gap: 8\n    font_size: 7\n',
      );
      final bbox =
          recordedRunSync(modernRecorded, 'pdftotext', [
                '-bbox',
                pdf,
                '-',
              ]).stdout
              as String;
      // Each word: its page, x and y.
      final words = <(int, String, double, double)>[];
      var page = -1;
      for (final line in bbox.split('\n')) {
        if (line.contains('<page ')) page++;
        if (RegExp(r'xMin="([\d.]+)" yMin="([\d.]+)"[^>]*>([^<]*)<')
                .firstMatch(line)
            case final m?) {
          words.add((page, m[3]!, double.parse(m[1]!), double.parse(m[2]!)));
        }
      }
      (int, double, double) at(String word) {
        final (p, _, x, y) = words.firstWhere((w) => w.$2 == word);
        return (p, x, y);
      }

      // The heading over the first study note, on a line of its own.
      final (hp, _, hy) = at('Creation');
      final (lp, _, ly) = at('Lemma1');
      expect(hp, lp);
      expect(ly, greaterThan(hy));
      // The translators' notes run in, one line; the study notes below.
      final (tp, _, ty) = at('tn1');
      expect((at('tn2').$1, at('tn2').$3), (tp, ty));
      expect(hy, greaterThan(ty));
      // Three columns of study notes.
      final columns = {
        for (final (p, w, x, _) in words)
          if (p == 0 && w.startsWith('Study')) (x / 50).floor(),
      };
      expect(columns.length, greaterThanOrEqualTo(3), reason: '$columns');
      // On each page, every study note's words below the translators'
      // notes there: a study note carried over goes on in its stream.
      for (var p = 0; p <= page; p++) {
        final tn = words.where((w) => w.$1 == p && w.$2.startsWith('tn'));
        final sn = words.where((w) => w.$1 == p && w.$2.startsWith('Study'));
        if (tn.isEmpty || sn.isEmpty) continue;
        final lowest = tn.map((w) => w.$4).reduce(math.max);
        expect(sn.every((w) => w.$4 > lowest), isTrue, reason: 'page $p');
      }
      expect(words.where((w) => w.$2.startsWith('Lemma')), hasLength(8));
    });

    test('study notes in step with their verses: least text, a lag', () {
      final schemes = Directory('${modernDir.path}/schemes')..createSync();
      for (final f in Directory('test/units/fixtures/schemes').listSync()) {
        if (f is File) {
          f.copySync('${schemes.path}/${f.uri.pathSegments.last}');
        }
      }
      File('${schemes.path}/study.yml')
          .writeAsStringSync('stream:\n  sn:\n    placement: "footnote"\n');
      final study = [
        for (var k = 0; k < 14; k++)
          'Study$k the words of the verse read with the others, at length.',
      ].join(' ');
      final verses = [
        for (var v = 1; v <= 8; v++)
          '@ Verse$v goes on.note:sn[*1:$v* Lemma$v $study]\n',
      ].join('\n');
      // Each verse's page, and its note's first.
      (List<int>, List<int>) pagesOf(String keys) {
        final pages = modernPages(
          modernPdf(
            '= Notes\n:units: bible, kjv, study\n\n== @GEN\n\n=== @1\n\n'
            '$verses',
            theme:
                'page:\n  size: [360, 400]\n  margin: [36, 36, 36, 36]\n'
                'note_streams: [sn]\n'
                'note_stream:\n  sn:\n    columns: 3\n    font_size: 7\n'
                '$keys',
          ),
        );
        int find(String word) =>
            pages.indexWhere((page) => page.any((l) => l.contains(word)));
        return (
          [for (var v = 1; v <= 8; v++) find('Verse$v ')],
          [for (var v = 1; v <= 8; v++) find('Lemma$v ')],
        );
      }

      // As the text goes: notes pages behind their verses.
      final (verse, note) = pagesOf('');
      expect(
        [for (var v = 0; v < 8; v++) note[v] - verse[v]].reduce(math.max),
        greaterThan(1),
      );
      // Three lines of text at least, no note more than a page late.

      final (heldVerse, heldNote) = pagesOf(
        'footnotes:\n  text_min_lines: 3\n  lag: 1\n',
      );
      expect([
        for (var v = 0; v < 8; v++) heldNote[v] - heldVerse[v],
      ], everyElement(inInclusiveRange(0, 1)));
    });

    test('the critical-edition look: labels in the margin, apparatus', () {
      final schemes = Directory('${modernDir.path}/schemes')..createSync();
      File('test/units/corpus/schemes/stephanus.yml')
          .copySync('${schemes.path}/stephanus.yml');
      File('${schemes.path}/app.yml').writeAsStringSync(
        'stream:\n  app:\n    placement: "footnote"\n'
        '    origin: "{{page}}{{section}}"\n    lemma-after: "] "\n',
      );
      final words = [for (var k = 0; k < 40; k++) 'verbum$k'].join(' ');
      final pdf = modernPdf(
        '= Dialogus\n:units: stephanus, app\n:look: critical-edition\n'
        ':line-numbers:\n\n'
        '@2a Primum ##dicit##note:app[dixit B] $words\n\n'
        '@ Secundum $words\n',
        // (The look as the theme: the helper names asciidoctor-pdf's.)
        attributes: {
          'pdf-theme': (File(
            '${modernDir.path}/look-theme.yml',
          )..writeAsStringSync('extends: look\n')).path,
        },
      );
      final text = modernPages(pdf).expand((page) => page).join('\n');
      // The Stephanus labels beside the lines only, not in the text; the
      // apparatus entry at the foot by its section, with no mark in the
      // text.
      expect(text, contains('Primum dicit verbum0'));
      expect(text, contains('Secundum verbum0'));
      expect(text, isNot(contains('2b Secundum')));
      expect(text, contains('2a dicit] dixit B'));
      expect(text, isNot(contains('[1]')));
      final bbox =
          recordedRunSync(modernRecorded, 'pdftotext', [
                '-bbox',
                pdf,
                '-',
              ]).stdout
              as String;
      final label = RegExp(r'xMin="([\d.]+)"[^>]*>2b<').firstMatch(bbox);
      final body = RegExp(r'xMax="([\d.]+)"[^>]*>Secundum<').firstMatch(bbox);
      expect(label, isNotNull);
      expect(
        double.parse(label![1]!),
        greaterThan(double.parse(body![1]!)),
        reason: 'the label in the outer margin',
      );
    });

    test('the trade-novel look: chapters on rectos, running heads', () {
      final words = [for (var k = 0; k < 900; k++) 'word$k'].join(' ');
      final pdf = modernPdf(
        '= The Harbour\n:doctype: book\n:look: trade-novel\n'
        ':media: prepress\n\n'
        '== One\n\nWhen the boat came in $words\n\n'
        "'''\n\nLater.\n\n== Two\n\nAfter all of it.\n",
        // (The look as the theme: the helper names asciidoctor-pdf's.)
        attributes: {
          'pdf-theme': (File(
            '${modernDir.path}/look-theme.yml',
          )..writeAsStringSync('extends: look\n')).path,
        },
      );
      final pages = modernPages(pdf);
      // Each chapter on a recto (an odd page), its first letter an
      // initial, the next words in small capitals (capitals, in a face
      // without them).
      int pageOf(String text) =>
          pages.indexWhere(
            (page) => page.any((l) => l.toLowerCase().contains(text)),
          ) +
          1;
      expect(pageOf('one').isOdd, isTrue);
      expect(pageOf('all of it').isOdd, isTrue);
      expect(pages.expand((p) => p), contains(matches(r'^W\s')));
      // The running heads in small capitals: the book's title on a verso,
      // the chapter's on a recto; none on an opener.
      final heads = [
        for (final page in pages)
          if (page.isNotEmpty) page.first,
      ];
      expect(
        heads,
        contains(matches(RegExp('^the harbour', caseSensitive: false))),
      );
      expect(heads, contains(matches(RegExp(r'^one$', caseSensitive: false))));
    });

    test('the scholarly-monograph look: margins, extracts, index', () {
      final words = [for (var k = 0; k < 500; k++) 'word$k'].join(' ');
      final quote = [for (var k = 0; k < 40; k++) 'quoted$k'].join(' ');
      final pdf = modernPdf(
        '= The State\n:doctype: book\n:look: scholarly-monograph\n'
        ':media: prepress\n\n'
        '== One\n\nOpening ((capital)) (((capital, labour))) $words\n\n'
        '[quote]\n____\n$quote\n____\n\n'
        'After (((capital, finance))).\n\n[index]\n== Index\n',
        // (The look as the theme: the helper names asciidoctor-pdf's.)
        attributes: {
          'pdf-theme': (File(
            '${modernDir.path}/look-theme.yml',
          )..writeAsStringSync('extends: look\n')).path,
        },
      );
      final bbox =
          recordedRunSync(modernRecorded, 'pdftotext', [
                '-bbox',
                pdf,
                '-',
              ]).stdout
              as String;
      double left(String word) => double.parse(
        RegExp('xMin="([\\d.]+)"[^>]*>${RegExp.escape(word)}<')
            .firstMatch(bbox)![1]!,
      );
      // The university press's margins, the inner one at the binding, in
      // place of the default theme's inner and outer (a recto's text at
      // 0.79 in).
      expect(left('Opening'), closeTo(0.79 * 72, 0.5));
      // The extract indented, 9 pt.
      expect(left('quoted0'), greaterThan(left('Opening') + 10));
      // The index run on.
      final text = modernPages(pdf).expand((page) => page).join('\n');
      expect(text, contains(RegExp(r'capital, 1; finance, \d+; labour, 1')));
    });

    group('the bill looks', () {
      setUpAll(() {
        final schemes = Directory('${modernDir.path}/schemes')..createSync();
        for (final name in ['usc', 'uk-act']) {
          File('test/units/corpus/schemes/$name.yml')
              .copySync('${schemes.path}/$name.yml');
        }
      });

      String bill(
        String look,
        String units,
        String body, {
        String header = '',
      }) => modernPdf(
        '= A Bill\n:units: $units\n:look: $look\n:line-numbers:\n$header\n'
        '$body',
        // (The look as the theme: the helper names asciidoctor-pdf's.)
        attributes: {
          'pdf-theme': (File(
            '${modernDir.path}/look-theme.yml',
          )..writeAsStringSync('extends: look\n')).path,
        },
      );

      /// The left edge of each word in [pdf], by its text (the first).
      Map<String, double> lefts(String pdf) {
        final bbox =
            recordedRunSync(modernRecorded, 'pdftotext', [
                  '-bbox',
                  pdf,
                  '-',
                ]).stdout
                as String;
        final lefts = <String, double>{};
        for (final m in RegExp(
          r'xMin="([\d.]+)"[^>]*>([^<]*)<',
        ).allMatches(bbox)) {
          lefts.putIfAbsent(m[2]!, () => double.parse(m[1]!));
        }
        return lefts;
      }

      final words = [for (var k = 0; k < 30; k++) 'word$k'].join(' ');

      test("a US bill's: every line numbered, levels 2 em in", () {
        final pdf = bill(
          'us-bill',
          'usc',
          '== @101 Definitions\n\n'
              '@(a) Subsection $words\n'
              '@(1) Paragraph $words\n'
              '@(A) Subparagraph $words\n',
        );
        final x = lefts(pdf);
        // (Each level's first line 2 em (28 pt) inside the one before.)
        expect(x['(1)']! - x['(a)']!, closeTo(28, 1));
        expect(x['(A)']! - x['(1)']!, closeTo(28, 1));
        // Every line numbered from 1, at the left of the text.
        final lines = modernPages(pdf).first;
        final numbers = [
          for (final line in lines)
            if (RegExp(r'^(\d+)\s').firstMatch(line) case final m?)
              int.parse(m[1]!),
        ];
        expect(numbers.take(5), [1, 2, 3, 4, 5]);
      });

      test("a US bill's slug at the foot, none without one", () {
        const body = '== @101 Definitions\n\n@(a) Subsection text.\n';
        final slugged = bill(
          'us-bill',
          'usc',
          body,
          header: ':bill-slug: HR 2 IH\n',
        );
        final x = lefts(slugged);
        // (12 pt in from the text, at 150.)
        expect(x['•HR'] ?? x['•HR2IH'], closeTo(162, 0.5));
        expect(
          modernPages(bill('us-bill', 'usc', body)).first.join('\n'),
          isNot(contains('bill-slug')),
        );
      });

      test("a UK bill's: every fifth line, the labels hung", () {
        final pdf = bill(
          'uk-bill',
          'uk-act',
          '=== @1 Offences\n\n'
              '@(1) Subsection $words\n'
              '@(a) Paragraph $words\n'
              '@(2) Second $words\n',
        );
        final x = lefts(pdf);
        // (The label hung left of the text, which lines up with the
        // lines after it.)
        expect(x['(1)'], lessThan(x['Subsection']! - 5));
        expect(x['(a)'], lessThan(x['Paragraph']! - 5));
        expect(x['Paragraph']! - x['Subsection']!, closeTo(36, 1));
        // Every fifth line numbered, at the right.
        final text = modernPages(pdf).first.join('\n');
        expect(text, contains(RegExp(r'\s5$', multiLine: true)));
        expect(text, isNot(contains(RegExp(r'\s4$', multiLine: true))));
        // (Flush right: 5 and 10 end at the same place.)
        final bbox =
            recordedRunSync(modernRecorded, 'pdftotext', [
                  '-bbox',
                  pdf,
                  '-',
                ]).stdout
                as String;
        final rights = {
          for (final m in RegExp(
            r'xMax="([\d.]+)"[^>]*>(5|10)<',
          ).allMatches(bbox))
            m[2]!: double.parse(m[1]!),
        };
        expect(rights['5'], closeTo(rights['10']!, 0.01));
      });
    });

    group('the federal-register look', () {
      final words = [for (var k = 0; k < 40; k++) 'word$k'].join(' ');
      String rule(String body) => modernPdf(
        '= Digital Certificate of Number\n:look: federal-register\n'
        ':notitle:\n'
        ':fr-issue: Vol. 89, No. 108 / Tuesday, June 4, 2024 / Rules\n'
        ':folio-start: 47855\n\n$body',
        // (The look as the theme: the helper names asciidoctor-pdf's.)
        attributes: {
          'pdf-theme': (File(
            '${modernDir.path}/look-theme.yml',
          )..writeAsStringSync('extends: look\n')).path,
        },
      );

      /// Each word of page [page] of [pdf] with its left and baseline-ish
      /// bottom.
      List<(String, double, double)> words0(String pdf, [int page = 1]) => [
        for (final m
            in RegExp(
              r'xMin="([\d.]+)" yMin="[\d.]+" xMax="[\d.]+" yMax="([\d.]+)">'
              '([^<]*)<',
            ).allMatches(
              recordedRunSync(modernRecorded, 'pdftotext', [
                    '-f',
                    '$page',
                    '-l',
                    '$page',
                    '-bbox',
                    pdf,
                    '-',
                  ]).stdout
                  as String,
            ))
          (m[3]!, double.parse(m[1]!), double.parse(m[2]!)),
      ];

      test('three columns, the head with the issue and the folio', () {
        final pdf = rule(
          '[.agency]\nDEPARTMENT OF HOMELAND SECURITY\n\n'
          'Agency:: Coast Guard, DHS.\n\n'
          '== I. Background\n\n'
          '${List.filled(30, '$words.').join('\n\n')}\n',
        );
        final page = words0(pdf);
        // The text from 45 pt in, in columns 14 pc wide 9 pt apart.
        final lefts = {
          for (final (_, x, y) in page)
            if (y > 60) x.round(),
        };
        expect(lefts, containsAll([45, 222, 399]));
        // The head: the folio from folio-start, the citation.
        final text = modernPages(pdf).first.join('\n');
        expect(text, contains('47855'));
        expect(text, contains('Federal Register'));
        expect(text, contains('Vol. 89, No. 108'));
        // The agency's name whole; the caption run in, with its colon.
        expect(text, isNot(contains('SECU-')));
        expect(text, contains(RegExp(r'AGENCY:\s*Coast Guard')));
      });

      test("a footnote at the foot of its reference's column", () {
        final pdf = rule(
          '$words\n\n[.column]\n<<<\n\n'
          '$words.footnote:[5 U.S.C. 553.]\n',
        );
        final page = words0(pdf);
        final (_, x, y) = page.firstWhere((w) => w.$1 == 'U.S.C.');
        // (In the second column, at the foot of the page.)
        expect(x, greaterThan(222));
        expect(x, lessThan(399));
        expect(y, greaterThan(700));
      });

      test("a heading of two lines on the text's pitch", () {
        final pdf = rule(
          '== II. Basis, Purpose, and Regulatory History of This Rule\n\n'
          '$words\n',
        );
        final page = words0(pdf);
        final first = page.firstWhere((w) => w.$1 == 'II.').$3;
        final next = page
            .where((w) => w.$2 < 100 && w.$3 > first + 1)
            .map((w) => w.$3)
            .reduce(math.min);
        expect(next - first, closeTo(10, 0.01));
      });
    });

    group('the quotation lint (quotation-lint)', () {
      String words(int n) => [
        for (var k = 0; k < n; k++) ['quoted', 'words', 'of', 'text'][k % 4],
      ].join(' ');
      List<String> warnings(String body, {bool lint = true}) {
        final logger = MemoryLogger();
        modernPdf(
          '= Doc\n${lint ? ':quotation-lint:\n' : ''}\n$body',
          logger: logger,
        );
        return [
          for (final m in logger.messages)
            if (m.severity == Severity.warn) '${m.message}',
        ];
      }

      test('a quotation of a hundred words or more run in', () {
        expect(warnings('He wrote "`${words(120)}`" and stopped.'), [
          contains('quotation of 120 words run in'),
        ]);
        expect(warnings('He wrote "`${words(20)}`" and stopped.'), isEmpty);
      });

      test('a block quotation shorter than five lines', () {
        expect(warnings('____\n${words(12)}\n____\n'), [
          contains('block quotation of 1 line'),
        ]);
        expect(warnings('____\n${words(150)}\n____\n'), isEmpty);
      });

      test('nothing without the attribute', () {
        expect(
          warnings(
            'He wrote "`${words(120)}`".\n\n____\n${words(12)}\n____\n',
            lint: false,
          ),
          isEmpty,
        );
      });
    });

    test('the pleading look: numbered lines, the court on line 8', () {
      final words = [for (var k = 0; k < 120; k++) 'Plaintiff alleges $k.']
          .join(' ');
      final pdf = modernPdf(
        '= Complaint\n:look: pleading\n:line-numbers: grid\n:notitle:\n\n'
        'Jane Q. Attorney (SBN 123456) +\n100 Main Street +\n'
        'Attorney for Plaintiff\n\n'
        '[.court]\nSUPERIOR COURT OF CALIFORNIA\n\n== Allegations\n\n$words\n',
        // (The look as the theme: the helper names asciidoctor-pdf's.)
        attributes: {
          'pdf-theme': (File(
            '${modernDir.path}/look-theme.yml',
          )..writeAsStringSync('extends: look\n')).path,
        },
      );
      final bbox =
          recordedRunSync(modernRecorded, 'pdftotext', [
                '-f',
                '1',
                '-l',
                '1',
                '-bbox',
                pdf,
                '-',
              ]).stdout
              as String;
      final words0 = [
        for (final m in RegExp(
          r'xMin="([\d.]+)" yMin="[\d.]+" xMax="[\d.]+" yMax="([\d.]+)">([^<]*)<',
        ).allMatches(bbox))
          (m[3]!, double.parse(m[1]!), double.parse(m[2]!)),
      ];
      // The numbers in the margin, 1 to 28, 24 pt apart.
      final numbers = {
        for (final (w, x, y) in words0)
          if (x < 100 && RegExp(r'^\d+$').hasMatch(w)) int.parse(w): y,
      };
      expect(numbers.keys, containsAll([1, 8, 28]));
      expect(numbers[2]! - numbers[1]!, closeTo(24, 0.01));
      // The attorney on line 1, the court's title on line 8 (the
      // attorney's three lines would have it on 4), each line of the
      // text beside a number.
      double yOf(String word) => words0.firstWhere((w) => w.$1 == word).$3;
      expect(yOf('Jane'), closeTo(numbers[1]!, 0.5));
      expect(yOf('SUPERIOR'), closeTo(numbers[8]!, 0.5));
      final text = {
        for (final (w, x, y) in words0)
          if (x > 100 && w == 'Plaintiff') y,
      };
      expect(text, hasLength(greaterThan(10)));
      for (final y in text) {
        expect(
          numbers.values.any((n) => (n - y).abs() < 0.5),
          isTrue,
          reason: 'a line at $y',
        );
      }
    });

    test("the Bible looks: a reference Bible's, a reader's edition", () {
      final schemes = Directory('${modernDir.path}/schemes')..createSync();
      for (final f in Directory('test/units/fixtures/schemes').listSync()) {
        if (f is File) {
          f.copySync('${schemes.path}/${f.uri.pathSegments.last}');
        }
      }
      String verse(int v) =>
          '@ Verse$v of the ##chapter##note:x[<<Gen 2:$v>>] goes on '
          'for a while, word upon word.\n';
      final verses = [for (var v = 1; v <= 30; v++) verse(v)].join();
      final themeFile = File('${modernDir.path}/look-theme.yml')
        ..writeAsStringSync('extends: look\n');
      String textOf(String look) {
        final source =
            '= Bible\n:units: bible, kjv\n:look: $look\n:doctype: book\n\n'
            '== @GEN\n\n=== @1\n\n$verses\n=== @2\n\n$verses';
        // (The look as the theme: the helper names asciidoctor-pdf's.)
        final pdf = modernPdf(
          source,
          attributes: {'pdf-theme': themeFile.path},
        );
        // (Without spaces: pdftotext joins words a narrow face's spaces
        // set close, as Crimson Pro's are at 6 pt.)
        return (recordedRunSync(modernRecorded, 'pdftotext', [
                  '-raw',
                  pdf,
                  '-',
                ]).stdout
                as String)
            .replaceAll(RegExp(r'\s'), '');
      }

      // The reference Bible: the verse numbers (not the first's) and the
      // cross-references in the centre column; the page's verses in its
      // running head.
      final reference = textOf('reference-bible');
      expect(reference, contains('Gen2:'));
      expect(reference, contains('17Verse17'));
      expect(reference, matches(RegExp(r'Genesis\d:\d+–\d+')));
      // The reader's edition: neither (nor the callers in the text).
      final reader = textOf('readers-bible');
      expect(reader, contains('Verse17ofthechaptergoeson'));
      expect(reader, isNot(contains('Gen2:')));
      expect(reader, isNot(contains('17Verse17')));
    });
  });
}
