// The modern engine (the default): what it does differently from the
// asciidoctor-pdf compatibility mode, read back from the PDFs it makes.
@TestOn('vm')
@Tags(['slow'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ptome/src/internal.dart';
import 'package:ptome/src/pdf/pdf.dart';
import 'package:test/test.dart';

import '../vendored_fonts.dart';

bool _has(String tool) => Process.runSync('which', [tool]).exitCode == 0;

/// Poppler's pdftotext (Git for Windows ships xpdf's, whose text and
/// `-bbox` output differ).
final bool _tools =
    _has('pdftotext') &&
    '${Process.runSync('pdftotext', ['-v']).stderr}'.contains('Poppler');

late Directory _dir;
var _count = 0;

/// [source] converted to PDF (in the compatibility mode with [compat];
/// with the theme [theme], YAML extending the default theme, its fonts
/// in the test fonts), its messages logged to [logger].
String _pdf(
  String source, {
  bool compat = false,
  String? theme,
  Map<String, String> attributes = const {},
  LoggerBase? logger,
}) {
  final input = File('${_dir.path}/d${_count++}.adoc')
    ..writeAsStringSync(source);
  final out = '${input.path}.pdf';
  final themeFile = theme == null
      ? null
      : (File('${input.path}-theme.yml')
          ..writeAsStringSync('extends: default\n$theme'));
  convertFile(
    input.path,
    AsciidoctorOptions(
      safe: SafeMode.unsafe,
      backend: 'pdf',
      toFile: out,
      attributes: {
        if (compat) 'pdf-compat': '',
        if (themeFile != null) ...{
          'pdf-theme': themeFile.path,
          'pdf-fontsdir': '${Directory.current.path}/test/pdf/fixtures/fonts',
        } else
          // asciidoctor-pdf's theme, which these tests were written for
          // (the house theme has its own tests).
          'pdf-theme': 'default',
        ...attributes,
      },
      logger: logger,
    ),
  );
  return out;
}

/// The lines of text on each page of [pdf] (the footer's page number
/// left out).
List<List<String>> _pages(String pdf) => [
  for (final page
      in (Process.runSync('pdftotext', ['-layout', pdf, '-']).stdout as String)
          .split('\f'))
    [
      for (final line in page.split('\n'))
        if (line.trim().isNotEmpty && !RegExp(r'^\d+$').hasMatch(line.trim()))
          line.trim(),
    ],
];

/// The bottom of each line of [pdf]'s first page, by the line's first
/// word.
Map<String, double> _baselines(String pdf) {
  final xml =
      Process.runSync('pdftotext', [
            '-bbox-layout',
            '-f',
            '1',
            '-l',
            '1',
            pdf,
            '-',
          ]).stdout
          as String;
  return {
    for (final m in RegExp(
      r'<line [^>]*yMax="([\d.]+)">\s*<word [^>]*>([^<]*)<',
    ).allMatches(xml))
      m[2]!: double.parse(m[1]!),
  };
}

/// The content of [pdf], uncompressed (its drawing operators readable).
String _content(String pdf) {
  final out = '$pdf.qdf';
  Process.runSync('qpdf', ['--qdf', '--object-streams=disable', pdf, out]);
  return latin1.decode(File(out).readAsBytesSync());
}

/// The top (points from the page's top) of the first word [word] in
/// [pdf], or null.
double? _top(String pdf, String word) =>
    switch (RegExp('yMin="([\\d.]+)"[^>]*>${RegExp.escape(word)}<').firstMatch(
      Process.runSync('pdftotext', ['-bbox', pdf, '-']).stdout as String,
    )) {
      final match? => double.parse(match[1]!),
      null => null,
    };

/// The words of [lines], those hyphenated at a line end joined.
List<String> _words(List<String> lines) => lines
    .join('\n')
    .replaceAll(RegExp('[-\u00ad]\n'), '')
    .split(RegExp(r'\s+'));

const _paragraph =
    'Hypermedia is a concept extending the idea of hypertext by allowing '
    'for more complex interactions with the user and the network. The '
    'hypertext transfer protocol, used to transfer hypermedia documents, is '
    'the backbone of the modern web, and its architecture has been '
    'described at length by Roy Fielding in his dissertation, which '
    'introduced the term representational state transfer, or REST.';

void main() {
  setUpAll(useVendoredFonts);
  setUpAll(() {
    registerPdf();
    _dir = Directory.systemTemp.createTempSync('ptome-modern.');
  });
  tearDownAll(() => _dir.deleteSync(recursive: true));

  group('justified text', () {
    test('breaks where spacing is most even, not line by line', () {
      final greedy = _pages(_pdf(_paragraph, compat: true)).first;
      final optimal = _pages(_pdf(_paragraph)).first;
      // Prawn's wrap leaves "REST." alone on a fifth line; the whole
      // paragraph fits on four.
      expect(greedy, hasLength(5));
      expect(greedy.last, 'REST.');
      expect(optimal, hasLength(4));
      expect(_words(optimal), _words(greedy));
    });

    test('the theme may ask for line-by-line breaking', () {
      final greedy = _pages(
        _pdf(_paragraph, theme: 'base_line_breaking: greedy\n'),
      ).first;
      final optimal = _pages(_pdf(_paragraph)).first;
      // Each line as full as it goes, hyphenated where a word no longer
      // fits (here the optimal breaks too).
      expect(greedy, hasLength(4));
      expect(_words(greedy), _words(optimal));
    });

    test('a paragraph that starts with an index term starts at the margin', () {
      final pdf = _pdf(
        '(((hypermedia client)))\n(((web browser)))\nAnd, finally.\n\n'
        'Plain.\n\n[index]\n== Index\n',
      );
      final bbox =
          Process.runSync('pdftotext', ['-bbox', pdf, '-']).stdout as String;
      double left(String word) => double.parse(
        RegExp('xMin="([\\d.]+)"[^>]*>$word<').firstMatch(bbox)![1]!,
      );
      expect(left('And,'), left('Plain.'));
    });

    test("a book's chapters in columns, balanced, their headings across", () {
      final pdf = _pdf(
        '= Book\n:doctype: book\n\n== One\n\n'
        '${List.filled(6, 'Alpha beta gamma delta.').join('\n\n')}\n\n'
        '== Two\n\nOmega.\n',
        theme:
            'page:\n  columns: 2\nheading:\n  chapter:\n'
            '    break-before: auto\n',
      );
      final bbox =
          Process.runSync('pdftotext', ['-bbox', pdf, '-']).stdout as String;
      final words = [
        for (final m in RegExp(
          r'xMin="([\d.]+)" yMin="([\d.]+)"[^>]*>(\w+)<',
        ).allMatches(bbox))
          (m[3]!, double.parse(m[1]!), double.parse(m[2]!)),
      ];
      // A4 with the default theme's margins: the middle at 297.64.
      final alphas = [
        for (final w in words)
          if (w.$1 == 'Alpha') w,
      ];
      final right = alphas.where((w) => w.$2 > 297.64).toList();
      // Three paragraphs a column, the two columns' first lines level.
      expect(right, hasLength(3));
      expect(right.first.$3, alphas.first.$3);
      final one = words.firstWhere((w) => w.$1 == 'One');
      final two = words.firstWhere((w) => w.$1 == 'Two');
      // The headings at the margin, the second under the columns.
      expect(one.$2, two.$2);
      expect(one.$3, lessThan(alphas.first.$3));
      expect(two.$3, greaterThan(alphas.map((w) => w.$3).reduce(math.max)));
    });

    test("running content names a page's first and last mark", () {
      // Anchors whose ids start with `running_content_marks`: their
      // reference text, the first and last on each page (a page without
      // one has the last before it).
      final paragraphs = [
        for (var i = 1; i <= 60; i++) '[[m-$i,Mark $i]]Text of mark $i.',
      ];
      final pdf = _pdf(
        '= Marks\n\n${paragraphs.join('\n\n')}\n\n'
        '<<<\n\nNo mark here.\n',
        theme:
            'running-content:\n  marks: m-\nheader:\n  height: 0.5in\n'
            '  recto:\n    center:\n      content: '
            "'{page-first-mark} to {page-last-mark}'\n"
            '  verso:\n    center:\n      content: '
            "'{page-first-mark} to {page-last-mark}'\n",
      );
      final pages = _pages(pdf).where((p) => p.isNotEmpty).toList();
      expect(pages.length, greaterThan(2));
      String first(List<String> page) =>
          RegExp(r'Text of mark (\d+)').firstMatch(page.join('\n'))![1]!;
      String last(List<String> page) =>
          RegExp(r'Text of mark (\d+)').allMatches(page.join('\n')).last[1]!;
      for (final page in pages.take(pages.length - 1)) {
        expect(page.first, 'Mark ${first(page)} to Mark ${last(page)}');
      }
      // The page without one: the last mark before it, twice.
      expect(pages.last.first, 'Mark 60 to Mark 60');
    });

    test("running content cites a page's units (ADR-0020)", () {
      // A document in units: its schemes in the nearest `schemes/`.
      final schemes = Directory('${_dir.path}/schemes')..createSync();
      for (final f in Directory('test/units/fixtures/schemes').listSync()) {
        if (f is File) {
          f.copySync('${schemes.path}/${f.uri.pathSegments.last}');
        }
      }
      String chapter(int c) => [
        '=== @$c',
        for (var v = 1; v <= 40; v++) '@ Text of verse $c.$v.',
      ].join('\n\n');
      final pdf = _pdf(
        '= Units\n:units: bible, kjv\n\n== @GEN\n\n'
        '${chapter(1)}\n\n${chapter(2)}\n',
        theme:
            'running-content:\n  units: verse\nheader:\n  height: 0.5in\n'
            "  recto:\n    center:\n      content: '{page-units-long}'\n"
            "  verso:\n    center:\n      content: '{page-units-long}'\n",
      );
      final pages = _pages(pdf).where((p) => p.isNotEmpty).toList();
      expect(pages.length, greaterThan(2));
      for (final page in pages) {
        final verses = [
          for (final m in RegExp(
            r'Text of verse (\d+)\.(\d+)',
          ).allMatches(page.join('\n')))
            (m[1]!, m[2]!),
        ];
        if (verses.isEmpty) continue;
        final (c1, v1) = verses.first;
        final (c2, v2) = verses.last;
        // What the ends share is said once.
        final range = c1 == c2
            ? (v1 == v2 ? '$c1:$v1' : '$c1:$v1–$v2')
            : '$c1:$v1–$c2:$v2';
        expect(page.first, 'Genesis $range');
      }
      // Structured: the levels' labels at the page's first and last unit.
      const head =
          "'{page-first-chapter}.{page-first-verse} to "
          "{page-last-chapter}.{page-last-verse}'";
      final structured = _pdf(
        '= Units\n:units: bible, kjv\n\n== @GEN\n\n'
        '${chapter(1)}\n\n${chapter(2)}\n',
        theme:
            'running-content:\n  units: verse\nheader:\n  height: 0.5in\n'
            '  recto:\n    center:\n      content: $head\n'
            '  verso:\n    center:\n      content: $head\n',
      );
      final first = _pages(structured).firstWhere((p) => p.isNotEmpty);
      expect(first.first, matches(RegExp(r'^1\.1 to \d\.\d+$')));
    }, skip: _tools ? false : 'needs pdftotext');

    test('a heading set as a drop beside the first lines', () {
      final pdf = _pdf(
        '= Doc\n\n[number=34]\n== Chapter\n\n[.note]\nSkipped.\n\n'
        '$_paragraph\n',
        theme:
            'heading:\n  h2-drop-lines: 2\n'
            "  h2-drop-content: '{{attr-number}}'\n"
            '  h2-drop-skip-roles: [note]\n',
      );
      final bbox =
          Process.runSync('pdftotext', ['-bbox', pdf, '-']).stdout as String;
      final words = [
        for (final m in RegExp(
          r'xMin="([\d.]+)" yMin="([\d.]+)" xMax="[\d.]+" yMax="([\d.]+)">([^<]+)<',
        ).allMatches(bbox))
          (
            m[4]!,
            double.parse(m[1]!),
            double.parse(m[2]!),
            double.parse(m[3]!),
          ),
      ];
      // No heading; the number at the margin, two lines tall; the
      // paragraph's first two lines beside it, the third at the margin.
      expect(words.any((w) => w.$1 == 'Chapter'), isFalse);
      final drop = words.firstWhere((w) => w.$1 == '34');
      final skipped = words.firstWhere((w) => w.$1 == 'Skipped.');
      expect(drop.$2, skipped.$2);
      expect(drop.$3, greaterThan(skipped.$3));
      final lineStarts = <double, double>{};
      for (final w in words.skipWhile((w) => w.$1 != 'Hypermedia')) {
        lineStarts.putIfAbsent(w.$3, () => w.$2);
      }
      final starts = lineStarts.values.toList();
      expect(starts[0], greaterThan(drop.$2 + 10));
      expect(starts[1], starts[0]);
      expect(starts[2], drop.$2);
      expect(drop.$4 - drop.$3, greaterThan(20));
    });

    test('a sidebar floating beside the text, through the next banner', () {
      // The report fixture: each subject's sidebar floats to the right of
      // the text after it; Vitamin A's goes on at the top of the next
      // page, where the repeated banner and title are set beside it.
      const dir = 'test/pdf/fixtures/report';
      final out = '${_dir.path}/report.pdf';
      final messages = MemoryLogger();
      convertFile(
        '$dir/report.adoc',
        AsciidoctorOptions(
          safe: SafeMode.unsafe,
          backend: 'pdf',
          toFile: out,
          attributes: {
            'pdf-theme': '$dir/report-theme.yml',
            'pdf-fontsdir': 'vendor/asciidoctor-pdf/data/fonts',
          },
          logger: messages,
        ),
      );
      expect([
        for (final m in messages.messages)
          if (m.severity.index >= Severity.warn.index) '${m.message}',
      ], isEmpty);
      final pages =
          (Process.runSync('pdftotext', ['-bbox', out, '-']).stdout as String)
              .split('<page ')
              .skip(1)
              .toList();
      List<(String, double, double)> words(String page) => [
        for (final m in RegExp(
          r'xMin="([\d.]+)" yMin="([\d.]+)"[^>]*>([^<]+)<',
        ).allMatches(page))
          (m[3]!, double.parse(m[1]!), double.parse(m[2]!)),
      ];
      (String, double, double) find(
        List<(String, double, double)> all,
        String word,
      ) => all.firstWhere((w) => w.$1 == word);
      // The pages of Vitamin A: its first (with its genes), then the one it
      // goes on to.
      final at = pages.indexWhere(
        (page) => page.contains('>BCMO1<') && page.contains('>RELATED<'),
      );
      final (first, next) = (words(pages[at]), words(pages[at + 1]));
      // On the first page the sidebar is at the right, beside the text.
      final genes = find(first, 'RELATED');
      expect(genes.$2, greaterThan(306));
      // On the next: the banner and title again, at the left, the rest of
      // the sidebar at the right, its top level with the banner's.
      final banner = find(next, 'VITAMINS');
      final rest = next.firstWhere((w) => w.$2 > 306);
      expect(banner.$2, lessThan(100));
      expect(rest.$3, closeTo(banner.$3, 12));
      expect(find(next, 'TENDENCY').$2, lessThan(300));
    });

    test('phrases with a side role set beside their line', () {
      final pdf = _pdf(
        '= Doc\n\n[[v1]]Verse one. [.xref]##*1:1* see <<v2,Two>>## '
        'Alpha beta.\n\n${List.filled(3, _paragraph).join('\n\n')}\n\n'
        '[[v2]]Verse two. [.xref]##*1:2* see <<v1,One>>## Gamma.\n',
        theme:
            'page:\n  columns: 2\n  column-gap: 72\n'
            'role:\n  xref:\n    display: side\n',
      );
      final bbox =
          Process.runSync('pdftotext', ['-bbox', pdf, '-']).stdout as String;
      final words = [
        for (final m in RegExp(
          r'xMin="([\d.]+)" yMin="([\d.]+)"[^>]*>([^<]+)<',
        ).allMatches(bbox))
          (m[3]!, double.parse(m[1]!), double.parse(m[2]!)),
      ];
      (double, double) at(String word) {
        final w = words.firstWhere((w) => w.$1 == word);
        return (w.$2, w.$3);
      }

      // Each note in the gap between the columns (A4's middle at
      // 297.64), level with its verse's line, out of the text, its
      // reference a link.
      for (final (note, verse) in [('1:1', 'Verse'), ('1:2', 'Gamma.')]) {
        final (x, y) = at(note);
        expect(x, greaterThan(297.64 - 36));
        expect(x, lessThan(297.64));
        expect(y, closeTo(at(verse).$2, 2));
      }
      expect(at('Alpha').$2, at('Verse').$2);
      final links = {
        for (final m in RegExp(r'/Dest \(([^)]*)\)').allMatches(_content(pdf)))
          m[1]!,
      };
      expect(links, containsAll(['v1', 'v2']));
    });

    test('a figure that spans the columns floats across the page', () {
      final dir = Directory.current.path;
      final pdf = _pdf(
        '= Doc\n\n'
        '${List.filled(4, _paragraph).join('\n\n')}\n\n'
        '.A wide figure across both columns of the page\n'
        'image::$dir/test/pdf/fixtures/images/wide.svg[pdfwidth=100%,'
        'scope=parent]\n\n'
        '${List.filled(4, _paragraph).join('\n\n')}\n',
        theme: 'page:\n  columns: 2\n',
      );
      // On the first page: the text in both columns (past the middle of
      // the page, 297.64), the figure under all of it (at the bottom, the
      // nearer edge to where it is in the text).
      final args = ['-bbox', '-f', '1', '-l', '1', pdf, '-'];
      final first = Process.runSync('pdftotext', args).stdout as String;
      final caption = double.parse(
        RegExp(r'yMin="([\d.]+)"[^>]*>Figure<').firstMatch(first)![1]!,
      );
      final text = [
        for (final m in RegExp(
          r'xMin="([\d.]+)" yMin="([\d.]+)"[^>]*>Hypermedia<',
        ).allMatches(first))
          (double.parse(m[1]!), double.parse(m[2]!)),
      ];
      expect(text.any((w) => w.$1 > 297.64), isTrue);
      expect(text.every((w) => w.$2 < caption), isTrue);
    });

    test('lines stay within the column', () {
      final pdf = _pdf('$_paragraph\n\n$_paragraph $_paragraph');
      final bbox =
          Process.runSync('pdftotext', ['-bbox', pdf, '-']).stdout as String;
      // A4 with the default theme's margins (0.67in on each side).
      const right = 595.28 - 48.24;
      for (final m in RegExp(r'xMax="([\d.]+)"').allMatches(bbox)) {
        expect(double.parse(m[1]!), lessThanOrEqualTo(right + 0.5));
      }
    });
  }, skip: _tools && _has('qpdf') ? false : 'needs poppler and qpdf');

  test('a paragraph leaves neither a widow nor an orphan', () {
    // A filler paragraph of hard-broken lines pushes an eight-line
    // paragraph down the page a line at a time, across the page break
    // (in the compatibility mode, one of these leaves a line alone at
    // the bottom).
    for (var filler = 38; filler < 48; filler++) {
      final source = [
        for (var i = 0; i < filler; i++) 'Filler line $i. +\n',
        'Filler end.\n\nzz $_paragraph $_paragraph',
      ].join();
      final pages = _pages(_pdf(source));
      if (pages.length < 2) continue;
      bool ofParagraph(String line) =>
          !line.startsWith('Filler') && line.isNotEmpty;
      final before = pages[0].where(ofParagraph).length;
      final after = pages[1].where(ofParagraph).length;
      expect(
        before == 0 || before >= 2,
        isTrue,
        reason: 'filler $filler: $before line(s) at the bottom',
      );
      expect(
        after == 0 || after >= 2,
        isTrue,
        reason: 'filler $filler: $after line(s) at the top',
      );
    }
  }, skip: _tools ? false : 'needs poppler');

  group('hyphenation', () {
    // Long words in a narrow column (a quarter-width table cell),
    // justified.
    String narrow(String header) =>
        '$header\n[cols="1,3"]\n|===\na|[.text-justify]\n'
        '$_paragraph\n| \n|===\n';

    /// Whether a line of [pdf] ends with a hyphen that isn't in the
    /// source (the soft hyphen's glyph, as Prawn draws it).
    bool hyphenated(String pdf) => _pages(pdf).any(
      (page) => page.any(
        (line) => line
            .split(RegExp(r'\s+'))
            .any(
              (word) =>
                  word.endsWith('\u00ad') ||
                  word.endsWith('-') && !_paragraph.contains(word),
            ),
      ),
    );

    test('breaks justified words in the modern engine', () {
      final pdf = _pdf(narrow(''));
      expect(hyphenated(pdf), isTrue);
      // The words are whole again with the hyphens at line ends joined.
      expect(
        _words(_pages(pdf).expand((page) => page).toList()).join(' '),
        contains('representational state transfer'),
      );
    });

    test('leaves code spans whole', () {
      const code =
          '`representational` `characteristically` `internationalization` '
          '`disproportionately` `incomprehensibilities`';
      final pdf = _pdf(
        '[cols="1,3"]\n|===\na|[.text-justify]\n$code $code\n| \n|===\n',
      );
      expect(hyphenated(pdf), isFalse);
    });

    test('is off with hyphens unset', () {
      expect(hyphenated(_pdf(narrow(':hyphens!:\n'))), isFalse);
    });

    test('is asked for in the compatibility mode, as in the gem', () {
      expect(hyphenated(_pdf(narrow(''), compat: true)), isFalse);
      expect(hyphenated(_pdf(narrow(':hyphens:\n'), compat: true)), isTrue);
    });

    test('reports a language without patterns', () {
      final logger = MemoryLogger();
      expect(
        hyphenated(_pdf(narrow(':hyphens: tlh\n'), logger: logger)),
        isFalse,
      );
      expect(
        logger.messages.map((m) => m.message.text),
        contains('no hyphenation patterns for tlh; not hyphenating'),
      );
    });

    test('no more hyphenated lines in a row than the limit', () {
      // The longest run of lines ending in a hyphen the source hasn't.
      int longestRun(String pdf) {
        var most = 0;
        var run = 0;
        for (final line in _pages(pdf).expand((page) => page)) {
          final last = line.split(RegExp(r'\s+')).last;
          final hyphenated =
              last.endsWith('\u00ad') ||
              last.endsWith('-') && !_paragraph.contains(last);
          run = hyphenated ? run + 1 : 0;
          if (run > most) most = run;
        }
        return most;
      }

      // (TeX's costs rarely give a run; the line breaker's own tests show
      // the limit holding where they would.)
      final source = narrow('') * 3;
      expect(
        longestRun(_pdf(source, theme: 'base:\n  hyphenate_limit_lines: 1\n')),
        1,
      );
    });

    test('a hyphen where the font has no soft hyphen', () {
      final pdf = _pdf(
        narrow(''),
        theme:
            'font:\n  catalog:\n    merge: true\n    Yrsa:\n'
            '      normal: yrsa-regular-latin.ttf\n'
            '      italic: yrsa-italic-latin.ttf\n'
            '      bold: yrsa-regular-latin.ttf\n'
            '      bold_italic: yrsa-italic-latin.ttf\n'
            'base:\n  font_family: Yrsa\n',
      );
      final words = [
        for (final page in _pages(pdf))
          for (final line in page) ...line.split(RegExp(r'\s+')),
      ];
      expect(words.where((w) => w.endsWith('\u00ad')), isEmpty);
      expect(
        words.where((w) => w.endsWith('-') && !_paragraph.contains(w)),
        isNotEmpty,
      );
    });
  }, skip: _tools ? false : 'needs poppler');

  group(
    'typography',
    () {
      // Yrsa, which has standard ligatures (fi) and GPOS kerning.
      const yrsa = '''
font:
  catalog:
    Yrsa:
      normal: yrsa-regular-latin.ttf
      italic: yrsa-italic-latin.ttf
      bold: yrsa-regular-latin.ttf
      bold_italic: yrsa-italic-latin.ttf
base:
  font-family: Yrsa
''';

      /// The glyphs the pages of [pdf] show (2 bytes each in a CID font).
      int glyphs(String pdf) {
        final qdf =
            Process.runSync('qpdf', [
                  '--qdf',
                  '--object-streams=disable',
                  pdf,
                  '-',
                ], stdoutEncoding: latin1).stdout
                as String;
        var count = 0;
        for (final array in RegExp(r'\[([^\]]*)\]\s*TJ').allMatches(qdf)) {
          for (final hex in RegExp('<([0-9a-fA-F]*)>').allMatches(array[1]!)) {
            count += hex[1]!.length ~/ 4;
          }
        }
        return count;
      }

      test('standard ligatures, unless the theme turns them off', () {
        const text = 'The official office files.';
        final ligated = glyphs(_pdf(text, theme: yrsa));
        final plain = glyphs(
          _pdf(text, theme: '${yrsa}base_font_ligatures: none\n'),
        );
        expect(ligated, lessThan(plain));
        // The same text either way.
        expect(
          _pages(_pdf(text, theme: yrsa)).first,
          _pages(_pdf(text, theme: '${yrsa}base_font_ligatures: none\n')).first,
        );
      });

      /// The fonts [pdf] uses, by PostScript name (without the subset tag).
      Set<String> fonts(String pdf) => {
        for (final line
            in (Process.runSync('pdffonts', [pdf]).stdout as String)
                .split('\n')
                .skip(2))
          if (line.trim().isNotEmpty) line.split(' ').first.split('+').last,
      };

      test('emphasis inside italic text is upright', () {
        const source =
            ':nofooter:\n\npass:[<em>Outer <em>inner</em> outer.</em>]';
        expect(fonts(_pdf(source)), {'NotoSerif-Italic', 'NotoSerif'});
        // The compatibility mode sets it all in italic, as the gem does.
        expect(fonts(_pdf(source, compat: true)), {'NotoSerif-Italic'});
        expect(fonts(_pdf(source, theme: 'base_emphasis_inversion: false\n')), {
          'NotoSerif-Italic',
        });
      });

      test('emphasis in an italic block is upright', () {
        const source =
            ':nofooter:\n\n[verse]\n____\nAn _emphasized_ word.\n____\n';
        const theme = 'verse_font_style: italic\n';
        expect(fonts(_pdf(source, theme: theme)), {
          'NotoSerif-Italic',
          'NotoSerif',
        });
      });

      test('first-line indents skip the first paragraph after a heading or '
          'a block', () {
        const theme = 'prose_text_indent_inner: 24\nprose_margin_inner: 0\n';
        final pdf = _pdf(
          '== Heading\n\nFirst paragraph.\n\nSecond paragraph.\n\n'
          '* item\n\nAfter the list.\n\nAnd another.\n',
          theme: theme,
        );
        final bbox =
            Process.runSync('pdftotext', ['-bbox', pdf, '-']).stdout as String;
        double x(String word) => double.parse(
          RegExp('xMin="([\\d.]+)"[^>]*>$word<').firstMatch(bbox)![1]!,
        );
        const margin = 48.24;
        expect(x('First'), closeTo(margin, 0.01));
        expect(x('Second'), closeTo(margin + 24, 0.01));
        expect(x('After'), closeTo(margin, 0.01));
        expect(x('And'), closeTo(margin + 24, 0.01));
      });

      test('an indent may be given in ems', () {
        // The default theme's base font size is 10.5.
        final pdf = _pdf(
          'First paragraph.\n\nSecond paragraph.\n',
          theme: 'prose_text_indent_inner: 2em\n',
        );
        final bbox =
            Process.runSync('pdftotext', ['-bbox', pdf, '-']).stdout as String;
        final x = double.parse(
          RegExp(r'xMin="([\d.]+)"[^>]*>Second<').firstMatch(bbox)![1]!,
        );
        expect(x, closeTo(48.24 + 21, 0.01));
      });
    },
    skip: _tools && _has('qpdf') && _has('pdffonts')
        ? false
        : 'needs poppler and qpdf',
  );

  group('fragmentation', () {
    /// The text of [pdf], every page in order, without whitespace (in
    /// layout mode, which keeps hyphens at line ends).
    String compact(String pdf) =>
        (Process.runSync('pdftotext', ['-layout', pdf, '-']).stdout as String)
            .replaceAll(RegExp(r'\s+'), '');

    /// A listing of [lines] lines of distinct text, some indented, one
    /// in [long] lines far wider than the page.
    List<String> listing(int n, int lines, {int long = 0}) => [
      for (var i = 0; i < lines; i++)
        [
          '${'  ' * (i % 3)}listing$n line$i = call(argument$i);',
          if (long > 0 && i % long == long - 1) ' // ${'wide$n-$i ' * 24}',
        ].join(),
    ];

    test('every listing line appears once, in order, within the margin', () {
      final listings = [
        for (var n = 0; n < 16; n++)
          listing(n, 3 + (n * 7) % 37, long: n.isEven ? 5 : 0),
      ];
      final source = StringBuffer(':nofooter:\n\n');
      for (final (n, lines) in listings.indexed) {
        source
          ..write('Paragraph $n before the listing. ' * (1 + n % 4))
          ..write('\n\n');
        if (n % 3 == 0) source.write('.Listing $n\n');
        source.write('----\n${lines.join('\n')}\n----\n\n');
      }
      final pdf = _pdf(source.toString());
      final text = compact(pdf);
      for (final (n, lines) in listings.indexed) {
        final whole = lines.join().replaceAll(RegExp(r'\s+'), '');
        expect(whole.allMatches(text).length, 1, reason: 'listing $n');
      }
      final bbox =
          Process.runSync('pdftotext', ['-bbox', pdf, '-']).stdout as String;
      const right = 595.28 - 48.24;
      for (final m in RegExp(r'xMax="([\d.]+)"').allMatches(bbox)) {
        expect(double.parse(m[1]!), lessThanOrEqualTo(right + 0.5));
      }
    });

    test('a listing leaves neither a widow nor an orphan', () {
      final code = listing(0, 12).join('\n');
      for (var filler = 40; filler < 52; filler++) {
        final source = [
          ':nofooter:\n\n',
          for (var i = 0; i < filler; i++) 'Filler line $i. +\n',
          'Filler end.\n\n----\n$code\n----\n',
        ].join();
        final pages = _pages(_pdf(source));
        if (pages.length < 2) continue;
        bool ofListing(String line) => line.contains('listing0');
        final before = pages[0].where(ofListing).length;
        final after = pages[1].where(ofListing).length;
        expect(
          before == 0 || before >= 2,
          isTrue,
          reason: 'filler $filler: $before line(s) at the bottom',
        );
        expect(
          after == 0 || after >= 2,
          isTrue,
          reason: 'filler $filler: $after line(s) at the top',
        );
      }
    });

    test('a caption stays with its listing', () {
      final code = listing(0, 30).join('\n');
      for (var filler = 40; filler < 50; filler++) {
        final source = [
          ':nofooter:\n\n',
          for (var i = 0; i < filler; i++) 'Filler line $i. +\n',
          'Filler end.\n\n.The caption\n----\n$code\n----\n',
        ].join();
        for (final page in _pages(_pdf(source))) {
          final caption = page.indexWhere((l) => l.contains('The caption'));
          if (caption < 0) continue;
          expect(
            caption + 1 < page.length && page[caption + 1].contains('listing0'),
            isTrue,
            reason: 'filler $filler: the caption ends its page',
          );
        }
      }
    });

    test(
      'text in a column too narrow for a character is kept, with a warning',
      () {
        final logger = MemoryLogger();
        final pdf = _pdf(
          ':nofooter:\n\n[cols="1,400"]\n|===\n|Wxyz |\n|===\n',
          logger: logger,
        );
        expect(compact(pdf), contains('Wxyz'));
        final warnings = [
          for (final m in logger.messages)
            if (m.severity == Severity.warn) m.message,
        ];
        expect(warnings.map((m) => m.text), [
          'table column 1 is too narrow for its text; the text overflows it',
        ]);
        // The table's line (after the header attribute and a blank line,
        // its attribute list is line 3, its delimiter line 4).
        expect(warnings.single.sourceLocation?.lineno, 4);
      },
    );

    test('a wrapped line goes on with a hanging indent', () {
      final pdf = _pdf(
        ':nofooter:\n\n----\n    start ${'word ' * 40}end\nnext\n----\n',
      );
      final bbox =
          Process.runSync('pdftotext', ['-bbox', pdf, '-']).stdout as String;
      final words = [
        for (final m in RegExp(
          r'xMin="([\d.]+)" yMin="([\d.]+)"[^>]*>([^<]*)<',
        ).allMatches(bbox))
          (double.parse(m[1]!), double.parse(m[2]!), m[3]!),
      ];
      final start = words.firstWhere((w) => w.$3 == 'start');
      final next = words.firstWhere((w) => w.$3 == 'next');
      // The first word of each line after the first of the source line.
      final continued = <double>[];
      double? lastY;
      for (final w in words) {
        if (w.$2 <= start.$2 || w.$2 >= next.$2) continue;
        if (w.$2 != lastY) continued.add(w.$1);
        lastY = w.$2;
      }
      expect(continued, isNotEmpty);
      // The default theme's code font size is 10.5... at 0.8: 8.4; 1em.
      for (final x in continued) {
        expect(x, greaterThan(start.$1));
      }
      expect(next.$1, lessThan(start.$1));
    });
  }, skip: _tools ? false : 'needs poppler');

  group('callouts', () {
    const source =
        ':nofooter:\n\n----\nconst a = 1; // <1>\nconst b = 2; // <2>\n'
        'const c = 3; // <1>\n----\n<1> First.\n<2> Second.\n';

    String qdf(String pdf) =>
        Process.runSync('qpdf', [
              '--qdf',
              '--object-streams=disable',
              pdf,
              '-',
            ], stdoutEncoding: latin1).stdout
            as String;

    test('markers are left out of the copied code', () {
      final modern = _pages(_pdf(source)).first;
      expect(modern.take(3), ['const a = 1;', 'const b = 2;', 'const c = 3;']);
    });

    test('markers link to their items and items back', () {
      final pdf = qdf(_pdf(source));
      final names = {
        for (final m in RegExp(
          r'^\s*\((CO[^)]*)\)',
          multiLine: true,
        ).allMatches(pdf))
          m[1]!,
      };
      expect(names, {
        'CO1-1', 'CO1-2', 'CO1-3', //
        'CO1-1-item', 'CO1-2-item', 'CO1-3-item',
      });
      final links = [
        for (final m in RegExp(r'/Dest \(([^)]*)\)').allMatches(pdf)) m[1]!,
      ]..sort();
      expect(links, [
        'CO1-1', 'CO1-1-item', 'CO1-2', 'CO1-2-item', 'CO1-3-item', //
      ]);
    });
  }, skip: _tools && _has('qpdf') ? false : 'needs poppler and qpdf');

  group('running content numerals', () {
    // Parts and chapters numbered, a preface and the contents not.
    const book =
        '= Book\n:doctype: book\n:sectnums:\n:partnums:\n:toc:\n\n'
        '[preface]\n== Preface\n\nBefore.\n\n'
        '= Part One\n\n== Chapter One\n\nText.\n\n'
        '== Chapter Two\n\nText.\n';
    const theme =
        'footer:\n  recto: &both\n    right:\n'
        '      content: '
        "'P[{part-numeral}] C[{chapter-numeral}] {page-number}'\n"
        '  verso: *both\n'
        // Each chapter here is a page: its opener.
        'running_content_on_openers: true\n';

    /// The footer of each page that has one.
    List<String> footers(String pdf) => [
      for (final page
          in (Process.runSync('pdftotext', ['-layout', pdf, '-']).stdout
                  as String)
              .split('\f'))
        if (RegExp(r'P\[.*$').firstMatch(page.trim()) case final m?) m[0]!,
    ];

    for (final compat in [false, true]) {
      test("are the part's and the chapter's"
          '${compat ? ' (compatibility mode)' : ''}', () {
        final pages = footers(_pdf(book, theme: theme, compat: compat));
        // A line that refers to a numeral the page hasn't (the contents,
        // the preface, the part's own page) is left out, as in the gem.
        expect(pages, ['P[I] C[1] 3', 'P[I] C[2] 4']);
      });

      test('name a chapter whose title is hidden'
          '${compat ? ' (compatibility mode)' : ''}', () {
        final pages = footers(
          _pdf(
            '= Book\n:doctype: book\n\n[colophon%notitle]\n== Copy\n\nText.\n',
            theme: theme.replaceFirst(
              'P[{part-numeral}] C[{chapter-numeral}] {page-number}',
              'P[{chapter-title}]',
            ),
            compat: compat,
          ),
        );
        expect(pages, ['P[Copy]']);
      });

      if (!compat) {
        test('a Mustache template, its numeral part optional', () {
          final pdf = _pdf(
            book,
            theme:
                'footer:\n  title_style: basic\n  recto: &both\n    right:\n'
                "      content: '{{#chapter-numeral}}{{chapter-numeral}}. "
                "{{/chapter-numeral}}{{chapter-title}} · {page-number}'\n"
                '  verso: *both\n'
                'running_content_on_openers: true\n',
          );
          final lines = [
            for (final page in _pages(pdf))
              if (page.isNotEmpty) page.last,
          ];
          // The preface has no numeral: its title alone, the line kept.
          expect(lines, contains('Preface · 1'));
          expect(lines, contains('1. Chapter One · 3'));
        });
      }

      if (!compat) {
        test('top-title: the part or chapter in effect at the top', () {
          final pdf = _pdf(
            book,
            theme:
                'footer:\n  recto: &both\n    right:\n'
                "      content: '{{#top-numeral}}{{top-numeral}}. "
                "{{/top-numeral}}T[{{top-title}}] {page-number}'\n"
                '  verso: *both\n'
                'running_content_on_openers: true\n',
          );
          final lines = [
            for (final page in _pages(pdf))
              for (final line in page)
                if (line.contains('T[')) line.replaceAll(RegExp(r'\s+'), ' '),
          ];
          // An opener still shows what came before it.
          expect(lines, [
            'T[Book] 1',
            '2 T[Preface] 2',
            'T[Part I: Part One] 3',
            '4 1. T[Chapter 1. Chapter One] 4',
          ]);
        });

        test('a section role keeps running content on its opener', () {
          final pdf = _pdf(
            '= Book\n:doctype: book\n\n[preface.front]\n== Preface\n\n'
            'Before.\n\n== Chapter\n\nText.\n',
            theme:
                'footer:\n  recto: &both\n    right:\n'
                "      content: 'F {page-number}'\n"
                '  verso: *both\n'
                'section:\n  role:\n    front:\n'
                '      running_content_on_openers: true\n',
          );
          final pages = _pages(pdf);
          // (The title page first.)
          expect(pages[1].join(' '), contains(RegExp('F ?1')));
          expect(pages[2].join(' '), isNot(contains('F')));
        });
      }

      test('go with titles without numbers (title_style: basic)'
          '${compat ? ' (compatibility mode)' : ''}', () {
        final pages = footers(
          _pdf(
            book,
            theme: theme
                .replaceFirst('footer:\n', 'footer:\n  title_style: basic\n')
                .replaceFirst(
                  '{page-number}',
                  '{page-number} {part-title} / {chapter-title}',
                ),
            compat: compat,
          ),
        );
        expect(pages, [
          'P[I] C[1] 3 Part One / Chapter One',
          'P[I] C[2] 4 Part One / Chapter Two',
        ]);
      });
    }
  }, skip: _tools ? false : 'needs poppler');

  group('index', () {
    test("index-sort: Chicago's orders in the PDF's index too", () {
      const source =
          '= Book\n:doctype: book\n\n== One\n\n'
          '((New York)) ((Newark)) ((news))\n\n[index]\n== Index\n';
      List<String> order(String sort) => [
        for (final line in _pages(
          _pdf(source, attributes: {'index-sort': sort}),
        ).expand((page) => page))
          if (RegExp('^(New York|Newark|news),').hasMatch(line))
            line.split(',').first,
      ];
      expect(order('letter-by-letter'), ['Newark', 'news', 'New York']);
      expect(order('word-by-word'), ['New York', 'Newark', 'news']);
    });

    const book =
        '= Doc\n:doctype: book\n\n== Chap\n\n'
        '((alpha)) and ((alpha)) and ((hypermedia)).\n\n<<<\n\n'
        'More ((alpha)).\n\n[index]\n== Index\n';

    /// The index's lines (the last page's).
    List<String> index(String pdf) =>
        _pages(pdf).lastWhere((page) => page.isNotEmpty);

    test('lists each page once', () {
      expect(index(_pdf(book)), contains('alpha, 1, 2'));
    });

    test('runs subentries into their entry with index_layout: run-on', () {
      const nested =
          '= Doc\n:doctype: book\n\n== Chap\n\n'
          '((alpha)) (((alpha, beta))) (((alpha, gamma))) '
          '(((alpha, gamma, zeta))) '
          '(((delta, epsilon))).\n\n[index]\n== Index\n';
      final lines = index(_pdf(nested, theme: 'index_layout: run-on\n'));
      // ("Term, pages; subterm, pages": Chicago's run-in style; a term
      // without pages of its own before a colon.)
      expect(lines, contains('alpha, 1; beta, 1; gamma, 1 (zeta, 1)'));
      expect(lines, contains('delta: epsilon, 1'));
      expect(lines, isNot(contains('beta, 1')));
      // asciidoctor-pdf's: indented, one to a line.
      expect(
        index(_pdf(nested, compat: true, theme: 'index_layout: run-on\n')),
        contains('beta, 1'),
      );
    });

    test('is set in the index font', () {
      double height(String pdf) {
        final bbox =
            Process.runSync('pdftotext', ['-bbox', pdf, '-']).stdout as String;
        final m = RegExp(
          r'yMin="([\d.]+)" xMax="[\d.]+" yMax="([\d.]+)">hypermedia,<',
        ).firstMatch(bbox)!;
        return double.parse(m[2]!) - double.parse(m[1]!);
      }

      final small = _pdf(book, theme: 'index_font_size: 6\n');
      expect(height(small), lessThan(height(_pdf(book)) * 0.7));
    });

    test('may set the page numbers in a column, without letters', () {
      final pdf = _pdf(
        book,
        theme:
            'index_pagenum_text_align: right\n'
            'index_category_headings: false\n',
      );
      final lines = index(pdf);
      expect(lines, isNot(contains('A')));
      expect(lines, isNot(contains('H')));
      expect(
        lines.any((l) => RegExp(r'^alpha\s{4,}1, 2$').hasMatch(l)),
        isTrue,
      );
      final bbox =
          Process.runSync('pdftotext', ['-bbox', pdf, '-']).stdout as String;
      // The words of each line (by its top), and where the line ends.
      final lineWords = <String, List<String>>{};
      final lineEnds = <String, double>{};
      for (final m in RegExp(
        r'yMin="([\d.]+)" xMax="([\d.]+)"[^>]*>([^<]*)<',
      ).allMatches(bbox)) {
        (lineWords[m[1]!] ??= []).add(m[3]!);
        lineEnds[m[1]!] = double.parse(m[2]!);
      }
      double end(String term) =>
          lineEnds[lineWords.entries
              .lastWhere((e) => e.value.first == term)
              .key]!;
      // Both entries' numbers end at the column's right edge.
      expect(end('alpha'), closeTo(end('hypermedia'), 0.01));
    });
  }, skip: _tools ? false : 'needs poppler');

  group('openers', () {
    const book =
        '= Book\n:doctype: book\n:sectnums:\n:partnums:\n\n'
        '[colophon%notitle%nofooter]\n== Copy\n\nCopyright.\n\n'
        '= Part One\n\n== Chapter One\n\nText.\n\n<<<\n\nMore text.\n';
    const footer =
        'footer:\n  recto: &both\n    right:\n'
        "      content: 'F{page-number}'\n  verso: *both\n";

    /// The text of each page.
    List<String> pages(String pdf) =>
        (Process.runSync('pdftotext', ['-layout', pdf, '-']).stdout as String)
            .split('\f')
            .map((page) => page.trim())
            .where((page) => page.isNotEmpty)
            .toList();

    test('have no running content, nor pages with nofooter', () {
      final text = pages(_pdf(book, theme: footer));
      // The title page; the copyright page; the part; the chapter's
      // opening page; its second page, the only one with a footer.
      expect(text, hasLength(5));
      expect(text[1], 'Copyright.');
      expect(text[2], isNot(contains('F')));
      expect(text[3], isNot(contains('F')));
      expect(text[4], endsWith('F4'));
    });

    test('have it when the theme says so', () {
      final text = pages(
        _pdf(book, theme: '${footer}running_content_on_openers: true\n'),
      );
      expect(text[3], endsWith('F3'));
      // asciidoctor-pdf's look: on openers too (nofooter on a section
      // still honored).
      final compat = pages(_pdf(book, theme: footer, compat: true));
      expect(compat[3], endsWith('F3'));
    });

    test('may set the label on a line of its own (a template)', () {
      final text = pages(
        _pdf(
          book,
          theme:
              'heading_h1_content: "{{signifier}} {{numeral}}\\n{{title}}"\n'
              'heading_h2_content: "{{#numeral}}{{signifier}} {{numeral}}'
              '\\n{{/numeral}}{{title}}"\n',
        ),
      );
      expect(text[2], 'Part I\nPart One');
      expect(text[3], startsWith('Chapter 1\nChapter One'));
      expect(pages(_pdf(book))[3], startsWith('Chapter 1. Chapter One'));
    });
  }, skip: _tools ? false : 'needs poppler');

  group('footnotes', () {
    const book =
        '= Doc\n:doctype: book\n\n== One\n\n'
        'First page.footnote:[The first note.]\n\n<<<\n\n'
        'Second page.footnote:[The second note.]\n\nLast words.\n';

    test('are at the bottom of the page of their reference', () {
      final pages = _pages(_pdf(book));
      expect(pages[1], ['One', '[1]', 'First page.', '[1] The first note.']);
      // Below the text that follows the reference.
      expect(pages[2], [
        '[2]',
        'Second page.',
        'Last words.',
        '[2] The second note.',
      ]);
    });

    test('may go at the end of the chapter, as in the gem', () {
      final pages = _pages(_pdf(book, theme: 'footnotes_placement: end\n'));
      expect(pages[1], ['One', '[1]', 'First page.']);
      expect(pages[2].last, '[2] The second note.');
      expect(pages[2], contains('[1] The first note.'));
    });

    const twoChapters =
        '= Doc\n:doctype: book\n\n== One\n\n'
        'A.footnote:[First.] B.footnote:[Second.]\n\n<<<\n\n'
        'C.footnote:[Third.]\n\n== Two\n\nD.footnote:[Fourth.]\n';

    /// The footnote labels on each page with any, as their notes show them.
    List<List<String>> notes(String pdf) => [
      for (final page in _pages(pdf))
        if (page.any((l) => RegExp(r'^\[\d+\] \w').hasMatch(l)))
          [
            for (final l in page)
              if (RegExp(r'^\[\d+\] \w').hasMatch(l)) l,
          ],
    ];

    test('may be numbered on each page', () {
      final pdf = _pdf(twoChapters, theme: 'footnotes_numbering: page\n');
      expect(notes(pdf), [
        ['[1] First.', '[2] Second.'],
        ['[1] Third.'],
        ['[1] Fourth.'],
      ]);
      // The references have the same numbers.
      expect(_pages(pdf)[1][1], matches(RegExp(r'^\[1\]\s+\[2\]$')));
    });

    test('may be numbered through the document', () {
      final pdf = _pdf(twoChapters, theme: 'footnotes_numbering: document\n');
      expect(notes(pdf), [
        ['[1] First.', '[2] Second.'],
        ['[3] Third.'],
        ['[4] Fourth.'],
      ]);
      // From 1 in each chapter by default, as in the gem.
      expect(notes(_pdf(twoChapters)).last, ['[1] Fourth.']);
    });

    test('markers from templates', () {
      final pdf = _pdf(
        twoChapters,
        theme:
            "footnotes_reference_content: '{{number}}'\n"
            "footnotes_label_content: '{{number}}. '\n",
      );
      expect(notes(pdf), isEmpty);
      final text = _pages(pdf)[1].join('\n');
      expect(text, contains('1. First.'));
      expect(text, isNot(contains('[1]')));
    });

    test("markers from the document's templates, as in HTML", () {
      final pdf = _pdf(
        twoChapters.replaceFirst(
          '= Doc\n',
          '= Doc\n:footnote-reference-template: {{number}}\n'
              ':footnote-label-template: {{number}}.{sp}\n',
        ),
      );
      final text = _pages(pdf)[1].join('\n');
      expect(text, contains('1. First.'));
      expect(text, isNot(contains('[1]')));
    });

    test("may show links' URIs (show-link-uri=footnote)", () {
      const source =
          '= Doc\n:show-link-uri: footnote\n\n'
          'See https://htmx.org[htmx] and https://example.org.\n';
      final text = _pages(_pdf(source)).first.join('\n');
      expect(text, contains('[1] https://htmx.org'));
      // A bare link shows its URI already.
      expect(text, isNot(contains('[2]')));
      final compat = _pages(_pdf(source, compat: true)).first.join('\n');
      expect(compat, contains('htmx [https://htmx.org]'));
    });
  }, skip: _tools ? false : 'needs poppler');

  group('syntax highlighting', () {
    const source =
        '= Doc\n:source-highlighter: highlight.js\n\n'
        '[source,python]\n----\ndef index(): # <1>\n    return 1\n----\n'
        '<1> A function.\n';

    // GitHub's keyword color, #d73a49.
    const keyword = '0.84314 0.22745 0.28627 rg';

    test('colors the tokens as the highlight.js theme does', () {
      expect(_content(_pdf(source)), contains(keyword));
      final text = _pages(_pdf(source)).first.join('\n');
      expect(text, contains('def index():'));
      expect(text, contains('A function.'));
    });

    test('in the theme highlightjs-theme names', () {
      final monokai = _content(
        _pdf(source.replaceFirst('\n\n', '\n:highlightjs-theme: monokai\n\n')),
      );
      expect(monokai, isNot(contains(keyword)));
      // Monokai's keyword color, #f92672.
      expect(monokai, contains('0.97647 0.14902 0.44706 rg'));
    });
  }, skip: _tools && _has('qpdf') ? false : 'needs poppler and qpdf');

  group('a section with a styled role', () {
    const source =
        '= Doc\n:doctype: book\n\n== Chap\n\nText.\n\n'
        '[.html-note]\n=== Notes\n\nIn the box.\n';
    const theme =
        'section_role_html_note_background_color: F5F5FF\n'
        'section_role_html_note_padding: 12\n'
        'section_role_html_note_font_size: 7\n'
        'section_role_html_note_heading_font_size: 8\n';
    // The fill, #F5F5FF.
    const fill = '0.96078 0.96078 1 rg';

    double height(String pdf, String word) {
      final bbox =
          Process.runSync('pdftotext', ['-bbox', pdf, '-']).stdout as String;
      final m = RegExp(
        'yMin="([\\d.]+)" xMax="[\\d.]+" yMax="([\\d.]+)">$word<',
      ).firstMatch(bbox)!;
      return double.parse(m[2]!) - double.parse(m[1]!);
    }

    test('is set in a box, in its own fonts', () {
      final pdf = _pdf(source, theme: theme);
      expect(_content(pdf), contains(fill));
      expect(height(pdf, 'box.'), lessThan(height(pdf, 'Text.') * 0.8));
      expect(height(pdf, 'Notes'), lessThan(height(pdf, 'Chap') * 0.6));
    });

    test('sits in the middle of its page (vertical_align)', () {
      double top(String pdf, String word) => double.parse(
        RegExp(
          'yMin="([\\d.]+)" xMax="[\\d.]+" yMax="[\\d.]+">$word<',
        ).firstMatch(
          Process.runSync('pdftotext', ['-bbox', pdf, '-']).stdout as String,
        )![1]!,
      );
      const dedication =
          '= Doc\n:doctype: book\n\n'
          '[dedication.middle%notitle]\n== Dedication\n\nTo you.\n\n'
          '== Chap\n\nText.\n';
      final pdf = _pdf(
        dedication,
        theme: 'section_role_middle_vertical_align: middle\n',
      );
      // A Letter page (792 points high): the line near its middle.
      expect(top(pdf, 'To'), closeTo(396, 40));
      final plain = _pdf(dedication.replaceFirst('.middle', ''));
      expect(top(plain, 'To'), lessThan(100));
    });
  }, skip: _tools && _has('qpdf') ? false : 'needs poppler and qpdf');

  test("a paragraph role's indent and space below", () {
    double left(String pdf, String word) => double.parse(
      RegExp(
        'xMin="([\\d.]+)" yMin="[\\d.]+" xMax="[\\d.]+" yMax="[\\d.]+">$word<',
      ).firstMatch(
        Process.runSync('pdftotext', ['-bbox', pdf, '-']).stdout as String,
      )![1]!,
    );
    const source = '= Doc\n\nFirst.\n\n[.flat]\nSecond.\n\nThird.\n';
    const theme = 'prose_text_indent_inner: 20\nprose_margin_bottom: 0\n';
    final plain = _pdf(source, theme: theme);
    final flat = _pdf(
      source,
      theme: '${theme}role_flat_text_indent: 0\nrole_flat_margin_bottom: 30\n',
    );
    expect(left(plain, 'Second.'), closeTo(left(plain, 'First.') + 20, 1));
    expect(left(flat, 'Second.'), closeTo(left(flat, 'First.'), 1));
    // The space below it: 30 points more before the next.
    double top(String pdf, String word) => double.parse(
      RegExp('yMin="([\\d.]+)" xMax="[\\d.]+" yMax="[\\d.]+">$word<')
          .firstMatch(
            Process.runSync('pdftotext', ['-bbox', pdf, '-']).stdout as String,
          )![1]!,
    );
    expect(
      top(flat, 'Third.') - top(flat, 'Second.'),
      closeTo(top(plain, 'Third.') - top(plain, 'Second.') + 30, 1),
    );
  }, skip: _tools ? false : 'needs poppler');

  test("a sidebar title's own space below", () {
    double top(String pdf, String word) => double.parse(
      RegExp('yMin="([\\d.]+)" xMax="[\\d.]+" yMax="[\\d.]+">$word<')
          .firstMatch(
            Process.runSync('pdftotext', ['-bbox', pdf, '-']).stdout as String,
          )![1]!,
    );
    const source = '= Doc\n\n.Aside\n****\nInside.\n****\n';
    final plain = _pdf(source);
    final spaced = _pdf(source, theme: 'sidebar_title_margin_bottom: 30\n');
    expect(
      top(spaced, 'Inside.') - top(spaced, 'Aside'),
      greaterThan(top(plain, 'Inside.') - top(plain, 'Aside') + 15),
    );
  }, skip: _tools ? false : 'needs poppler');

  test('base_leading: lines from cap height, leading apart', () {
    List<double> tops(String pdf) => [
      for (final m in RegExp(r'<line xMin="[\d.]+" yMin="([\d.]+)"').allMatches(
        Process.runSync('pdftotext', ['-bbox-layout', pdf, '-']).stdout
            as String,
      ))
        double.parse(m[1]!),
    ];
    final source = '${'word ' * 60}\n';
    final a = tops(_pdf(source, theme: 'base_leading: 4\n'));
    final b = tops(_pdf(source, theme: 'base_leading: 10\n'));
    // Six points more leading: six points more between lines.
    expect((b[1] - b[0]) - (a[1] - a[0]), closeTo(6, 0.01));
    expect((b[2] - b[1]) - (a[2] - a[1]), closeTo(6, 0.01));
  }, skip: _tools ? false : 'needs poppler');

  test('title_page_title_skew: the title slanted as one block', () {
    final pdf = _pdf(
      '= Several Long Words Make Two Lines\n:doctype: book\n\n== One\n\n'
      'Text.\n',
      theme:
          'title_page_title_font_size: 60\ntitle_page_title_skew: 10\n'
          'title_page_text_align: left\n',
    );
    final words = {
      for (final m
          in RegExp(r'xMin="([\d.]+)" yMin="([\d.]+)"[^>]*>(Several|Words)<')
              .allMatches(
                Process.runSync('pdftotext', [
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
        m[3]!: (double.parse(m[1]!), double.parse(m[2]!)),
    };
    // On two lines, the upper one further right by tan(10°) times the
    // distance between them.
    final (x1, y1) = words['Several']!;
    final (x2, y2) = words['Words']!;
    expect(y2, greaterThan(y1));
    expect(x1 - x2, closeTo(0.17633 * (y2 - y1), 0.5));
  }, skip: _tools ? false : 'needs poppler');

  group('text keys', () {
    List<(double, double, double, String)> words(String pdf) => [
      for (final m
          in RegExp(
            r'xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" yMax="[\d.]+">([^<]*)<',
          ).allMatches(
            Process.runSync('pdftotext', ['-bbox', pdf, '-']).stdout as String,
          ))
        (double.parse(m[1]!), double.parse(m[2]!), double.parse(m[3]!), m[4]!),
    ];

    test('base_overhang: a line ending in a comma hangs into the margin', () {
      const source =
          'Lorem ipsum dolor sit amet consectetur adipiscing elit sed do, '
          'eiusmod tempor incididunt ut labore et dolore magna aliqua ut '
          'enim ad minim veniam quis nostrud exercitation ullamco laboris.\n';
      // The right edge of the line that ends in a comma, if one does.
      double? commaEdge(String pdf) {
        final all = words(pdf);
        for (final (i, w) in all.indexed) {
          final last = i + 1 == all.length || all[i + 1].$2 != w.$2;
          if (last && w.$4.endsWith(',')) return w.$3;
        }
        return null;
      }

      // A width at which a line ends with the comma.
      for (final width in [300, 310, 320, 330, 340, 350, 360]) {
        final theme =
            'page_size: [${width + 72}, 600]\npage_margin: 36\n'
            'base_text_align: justify\n';
        final plain = commaEdge(_pdf(source, theme: theme));
        if (plain == null) continue;
        final hung = commaEdge(
          _pdf(source, theme: '${theme}base_overhang: true\n'),
        )!;
        expect(hung, greaterThan(plain + 1));
        // An amount scales it: half as far.
        final half = commaEdge(
          _pdf(source, theme: '${theme}base_overhang: 0.5\n'),
        )!;
        expect(half - plain, closeTo((hung - plain) / 2, 0.05));
        return;
      }
      fail('no width put the comma at a line end');
    });

    test('list_body_indent: the marker at the indent, the text after it', () {
      final pdf = _pdf(
        '* one\n* two\n',
        theme: 'page_margin: 50\nlist_indent: 20\nlist_body_indent: 10\n',
      );
      final all = words(pdf);
      final bullet = all.firstWhere((w) => w.$4 == '•');
      final one = all.firstWhere((w) => w.$4 == 'one');
      expect(bullet.$1, closeTo(70, 0.01));
      expect(one.$1 - bullet.$3, closeTo(10, 0.01));
    });

    test("a section role's keys over the theme's inside the section", () {
      const source =
          '= Doc\n:doctype: book\n\n== A\n\nOne.\n\nTwo.\n\n'
          '[.airy]\n== B\n\nThree.\n\nFour.\n';
      final pdf = _pdf(
        source,
        theme:
            'prose_margin_bottom: 0\n'
            'section_role_airy_prose_margin_bottom: 30\n',
      );
      double top(String word) => words(pdf).firstWhere((w) => w.$4 == word).$2;
      final plain = top('Two.') - top('One.');
      final airy = top('Four.') - top('Three.');
      expect(airy - plain, closeTo(30, 0.5));
    });
  }, skip: _tools ? false : 'needs poppler');

  group('floating images', () {
    final svg = base64.encode(
      utf8.encode(
        '<svg xmlns="http://www.w3.org/2000/svg" width="400" height="300" '
        'viewBox="0 0 400 300"><rect width="400" height="300"/></svg>',
      ),
    );
    final book = [
      '= Doc\n:doctype: book\n\n== Chap\n',
      for (var i = 1; i <= 14; i++)
        'Paragraph $i with some words in it to fill a line or two.\n',
      '.The figure\nimage::data:image/svg+xml;base64,$svg[pdfwidth=100%]\n',
      'After the image.\n\n== Next\n\nNext chapter.\n',
    ].join('\n');

    /// The text of each page, its lines joined.
    List<String> pages(String pdf) =>
        _pages(pdf).map((lines) => lines.join('\n')).toList();

    test("go to the next page when they don't fit, the text filling in", () {
      final text = pages(_pdf(book, theme: 'image_placement: auto\n'));
      expect(text[1], contains('After the image.'));
      expect(text[2], startsWith('Figure 1. The figure'));
      // The next chapter after the figure, on its own page.
      expect(text[3], startsWith('Next'));
    });

    test('may go to the bottom or the top of the page they fit on', () {
      final short = [
        '= Doc\n:doctype: book\n\n== Chap\n',
        'Before the image.\n',
        '.The figure\nimage::data:image/svg+xml;base64,$svg[pdfwidth=50%]\n',
        'After the image.\n',
      ].join('\n');
      List<String> lines(String placement) =>
          _pages(_pdf(short, theme: 'image_placement: $placement\n'))[1];
      expect(lines('bottom'), [
        'Chap',
        'Before the image.',
        'After the image.',
        'Figure 1. The figure',
      ]);
      expect(lines('top'), [
        'Figure 1. The figure',
        'Chap',
        'Before the image.',
        'After the image.',
      ]);
      // In place where it fits.
      expect(lines('next'), [
        'Chap',
        'Before the image.',
        'Figure 1. The figure',
        'After the image.',
      ]);
    });

    test('stay in a sidebar', () {
      final inSidebar = [
        '= Doc\n:doctype: book\n\n== Chap\n',
        '****\nBefore the image.\n',
        '.The figure\nimage::data:image/svg+xml;base64,$svg[pdfwidth=50%]\n',
        'After the image.\n****\n',
      ].join('\n');
      expect(_pages(_pdf(inSidebar, theme: 'image_placement: bottom\n'))[1], [
        'Chap',
        'Before the image.',
        'Figure 1. The figure',
        'After the image.',
      ]);
    });

    test('stay in place without image_placement: auto', () {
      final text = pages(_pdf(book));
      expect(text[2], contains('After the image.'));
    });
  }, skip: _tools ? false : 'needs poppler');

  group('a family without an italic or bold face', () {
    const theme =
        'font:\n  catalog:\n    merge: true\n    Upright:\n'
        '      normal: yrsa-regular-latin.ttf\n'
        'base_font_family: Upright\n';
    const source = 'Plain, _slanted_ and *stroked*.\n';

    test('has them made from its regular face', () {
      final pdf = _pdf(source, theme: theme);
      final content = _content(pdf);
      expect(content, contains('1 0 0.2 1 '));
      expect(content, contains(' w\n2 Tr'));
      expect(
        _pages(pdf).first.join(' '),
        contains('Plain, slanted and stroked.'),
      );
    });
  }, skip: _tools && _has('qpdf') ? false : 'needs poppler and qpdf');

  group('space around blocks', () {
    const source =
        '= Doc\n:doctype: book\n\n== Chap\n\nBefore.\n\n'
        '----\ncode\n----\n\nAfter.\n\n____\nQuoted.\n____\n\nLast.\n';

    /// The top of [word] on the first page with text.
    double top(String pdf, String word) {
      final bbox =
          Process.runSync('pdftotext', ['-bbox', pdf, '-']).stdout as String;
      return double.parse(
        RegExp('yMin="([\\d.]+)"[^>]*>$word<').firstMatch(bbox)![1]!,
      );
    }

    // The default theme: 12 points below each block.
    test('each kind of block has its own space below', () {
      final plain = _pdf(source);
      final spaced = _pdf(source, theme: 'code_margin_bottom: 30\n');
      // After the code: 18 points further down; above it, as before.
      expect(top(spaced, 'code'), closeTo(top(plain, 'code'), 0.01));
      expect(top(spaced, 'After.') - top(plain, 'After.'), closeTo(18, 0.01));
    });

    test('space above collapses with the space below the block before', () {
      final plain = _pdf(source);
      // 20 above the code, after a paragraph's 12 below: 20, not 32.
      final spaced = _pdf(source, theme: 'code_margin_top: 20\n');
      expect(top(spaced, 'code') - top(plain, 'code'), closeTo(8, 0.01));
      // Less than the space below the block before: nothing changes.
      final less = _pdf(source, theme: 'quote_margin_top: 6\n');
      expect(top(less, 'Quoted.'), closeTo(top(plain, 'Quoted.'), 0.01));
    });

    test('after a heading, what its margin below leaves', () {
      const first = '= Doc\n:doctype: book\n\n== Chap\n\n----\ncode\n----\n';
      final plain = _pdf(first, theme: 'heading_margin_bottom: 6\n');
      final spaced = _pdf(
        first,
        theme: 'heading_margin_bottom: 6\ncode_margin_top: 20\n',
      );
      expect(top(spaced, 'code') - top(plain, 'code'), closeTo(14, 0.01));
    });

    test("a quote's attribution: its own space above, aligned right", () {
      const quote = '[quote, Ted Nelson]\n____\nQuoted.\n____\n';
      double left(String pdf, String word) {
        final bbox =
            Process.runSync('pdftotext', ['-bbox', pdf, '-']).stdout as String;
        return double.parse(
          RegExp('xMin="([\\d.]+)"[^>]*>$word<').firstMatch(bbox)![1]!,
        );
      }

      final plain = _pdf(quote);
      final styled = _pdf(
        quote,
        theme: 'quote_cite_margin_top: 2\nquote_cite_text_align: right\n',
      );
      // The default theme: 12 points above it.
      expect(top(plain, 'Nelson') - top(styled, 'Nelson'), closeTo(10, 0.01));
      expect(left(styled, 'Nelson'), greaterThan(left(plain, 'Nelson') + 200));
    });

    test("are the gem's in the compatibility mode", () {
      final plain = _pdf(source, compat: true);
      final spaced = _pdf(
        source,
        theme: 'code_margin_bottom: 30\ncode_margin_top: 20\n',
        compat: true,
      );
      expect(top(spaced, 'After.'), closeTo(top(plain, 'After.'), 0.01));
    });
  }, skip: _tools ? false : 'needs poppler');

  test("the title page's author delimiter keeps its spaces", () {
    const book = '= Book\nAda One; Bob Two\n:doctype: book\n\n== C\n\nText.\n';
    double gap(String pdf) {
      final bbox =
          Process.runSync('pdftotext', [
                '-f',
                '1',
                '-l',
                '1',
                '-bbox',
                pdf,
                '-',
              ]).stdout
              as String;
      double at(String word, String side) => double.parse(
        RegExp('$side="([\\d.]+)"[^>]*>$word<').firstMatch(bbox)![1]!,
      );
      return at('Bob', 'xMin') - at('One', 'xMax');
    }

    const theme = "title_page_authors_delimiter: '    '\n";
    final four = gap(_pdf(book, theme: theme));
    final one = gap(_pdf(book, theme: "title_page_authors_delimiter: ' '\n"));
    expect(four, greaterThan(one * 3));
  }, skip: _tools ? false : 'needs poppler');

  test('a section with notoc is left out of the contents', () {
    const book =
        '= Book\n:doctype: book\n:toc:\n\n'
        '[colophon%notoc]\n== Copyright\n\nText.\n\n== Chapter\n\nText.\n';
    final contents = _pages(_pdf(book))[1].join('\n');
    expect(contents, contains('Chapter'));
    expect(contents, isNot(contains('Copyright')));
  }, skip: _tools ? false : 'needs poppler');

  test('the contents may list titles without numbers', () {
    const book =
        '= Book\n:doctype: book\n:toc:\n:sectnums:\n\n== One\n\nText.\n';
    String contents(String pdf) => _pages(pdf)[1].join('\n');
    expect(contents(_pdf(book)), contains('1. One'));
    final plain = contents(
      _pdf(book, theme: "toc_entry_content: '{{title}}'\n"),
    );
    expect(plain, contains('One'));
    expect(plain, isNot(contains('1. One')));
  }, skip: _tools ? false : 'needs poppler');

  test('a definition term may run in before its description', () {
    const source =
        'Hypermedia Control:: A hypermedia control is an element in a '
        'hypermedia that describes (or controls) some sort of interaction, '
        'often with a remote server, by encoding information about that '
        'interaction directly and completely within itself.\n';
    final pdf = _pdf(
      source,
      theme:
          'description_list_term_display: inline\n'
          'description_list_description_indent: 20\n',
    );
    final lines = _pages(pdf).first;
    expect(lines.first, startsWith('Hypermedia Control A hypermedia control'));
    final bbox =
        Process.runSync('pdftotext', ['-bbox', pdf, '-']).stdout as String;
    final lefts = [
      for (final m in RegExp(r'<line xMin="([\d.]+)"').allMatches(
        Process.runSync('pdftotext', ['-bbox-layout', pdf, '-']).stdout
            as String,
      ))
        double.parse(m[1]!),
    ];
    // The lines after the first hang 20 points in.
    expect(lefts[1] - lefts[0], closeTo(20, 0.5));
    expect(bbox, contains('>Control<'));
  }, skip: _tools ? false : 'needs poppler');

  test('callout markers may be text', () {
    const source =
        '[source,ruby]\n----\nputs 1 # <1>\nputs 2 # <2>\n----\n'
        '<1> One.\n<2> Two.\n';
    const theme =
        "conum_glyphs: '[{{number}}]'\n"
        "callout_list_marker_content: '{{number}}.'\n"
        'conum_font_style: bold\n';
    final text = _pages(_pdf(source, theme: theme)).first.join('\n');
    expect(text, contains('1. One.'));
    expect(text, contains('2. Two.'));
    // The markers in the code are left out of its text: count the glyphs
    // drawn. Each `[1]` is three where a circled number is one; each
    // `1.` in the list two.
    int glyphs(String pdf) => [
      for (final array in RegExp(
        r'\[([^\]]*)\]\s*TJ',
      ).allMatches(_content(pdf)))
        for (final hex in RegExp('<([0-9a-fA-F]*)>').allMatches(array[1]!))
          hex[1]!.length ~/ 4,
    ].fold(0, (a, b) => a + b);
    expect(
      glyphs(_pdf(source, theme: theme)) - glyphs(_pdf(source)),
      2 * 2 + 2 * 1,
    );
  }, skip: _tools && _has('qpdf') ? false : 'needs poppler and qpdf');

  group('blank pages', () {
    // A prepress book: each chapter starts on a recto page, so a
    // one-page chapter leaves a blank verso page before the next.
    const book =
        '= Book\n:doctype: book\n:media: prepress\n\n'
        '== One\n\nFirst chapter.\n\n== Two\n\nSecond chapter.\n';

    /// The text of each page of [pdf], the page number included.
    List<String> pages(String pdf) =>
        (Process.runSync('pdftotext', ['-layout', pdf, '-']).stdout as String)
            .split('\f')
            .map((page) => page.trim())
            .toList();

    // Pages: the title page, a blank one before the body (never with
    // running content), chapter One, a blank verso, chapter Two.
    test('carry no running content', () {
      expect(pages(_pdf(book))[3], isEmpty);
      // asciidoctor-pdf's look numbers it, as the gem does.
      expect(pages(_pdf(book, compat: true))[3], '2');
    });

    test('carry it when the theme says so', () {
      final themed = pages(
        _pdf(book, theme: 'running_content_on_blank_pages: true\n'),
      );
      expect(themed[3], '2');
    });
  }, skip: _tools ? false : 'needs poppler');

  group('table styles', () {
    /// The box of [word] in [pdf] (y down from the top).
    ({double xMin, double xMax, double height}) box(String pdf, String word) {
      final bbox =
          Process.runSync('pdftotext', ['-bbox', pdf, '-']).stdout as String;
      final m = RegExp(
        r'xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" '
        'yMax="([\\d.]+)">$word<',
      ).firstMatch(bbox)!;
      return (
        xMin: double.parse(m[1]!),
        xMax: double.parse(m[3]!),
        height: double.parse(m[4]!) - double.parse(m[2]!),
      );
    }

    test('a table role takes its keys from the theme once', () {
      final pdf = _pdf(
        '|===\n|Plain\n|===\n\n[.big]\n|===\n|Styled\n|===\n',
        theme: 'table_role_big_font_size: 16\n',
      );
      expect(box(pdf, 'Styled').height, greaterThan(box(pdf, 'Plain').height));
    });

    test("a cell whose text has a role takes that role's cell keys", () {
      final pdf = _pdf(
        '[cols="1,1"]\n|===\n|[.paid]#Paid# |Open\n|===\n',
        theme: 'table_cell_role_paid_text_align: right\n',
      );
      final paid = box(pdf, 'Paid');
      final open = box(pdf, 'Open');
      // Right-aligned in the first column: it ends near the second's
      // start; the second starts at its left.
      expect(open.xMin - paid.xMax, lessThan(20));
    });
  }, skip: _tools ? false : 'needs poppler');

  group('print', () {
    /// An ICC header: an output (printer) profile for [space].
    String profile(String space) {
      final file = File('${_dir.path}/${space.trim()}.icc')
        ..writeAsBytesSync(Uint8List(132)..setAll(12, 'prtr$space'.codeUnits));
      return file.path;
    }

    String qdf(String pdf) =>
        Process.runSync('qpdf', [
              '--qdf',
              '--object-streams=disable',
              pdf,
              '-',
            ], stdoutEncoding: latin1).stdout
            as String;

    const book = '= Print\n:doctype: book\n\n== One\n\nText.\n';

    test('PDF/X-4: an output intent, the identification, print boxes', () {
      final logger = MemoryLogger();
      final pdf = _pdf(
        ':pdf-standard: PDF/X-4\n:pdf-output-intent: ${profile('RGB ')}\n'
        '$book',
        logger: logger,
      );
      final text = qdf(pdf);
      expect(text, startsWith('%PDF-1.6'));
      expect(text, contains('/S /GTS_PDFX'));
      expect(text, contains('/N 3'));
      expect(text, contains('/Trapped /False'));
      expect(text, contains('/TrimBox'));
      expect([
        for (final m in logger.messages)
          if (m.severity == Severity.warn) m,
      ], isEmpty);
    });

    test('PDF/X-4 with a CMYK condition warns of the RGB content', () {
      final logger = MemoryLogger();
      _pdf(
        ':pdf-standard: PDF/X-4\n:pdf-output-intent: ${profile('CMYK')}\n'
        '$book',
        logger: logger,
      );
      expect(
        logger.messages.map((m) => m.message.text),
        contains(startsWith('the text, lines and images are in RGB')),
      );
    });

    test('PDF/X-4 without a profile is a plain PDF, with an error', () {
      final logger = MemoryLogger();
      final pdf = _pdf(':pdf-standard: PDF/X-4\n$book', logger: logger);
      expect(qdf(pdf), isNot(contains('/OutputIntents')));
      expect(
        logger.messages.map((m) => m.message.text),
        contains(startsWith('PDF/X-4 needs the ICC profile')),
      );
    });

    test('a bleed grows the sheet past the trimmed page', () {
      final pdf = _pdf(book, theme: 'page_bleed: 9\n');
      final boxes = Process.runSync('pdfinfo', ['-box', pdf]).stdout as String;
      expect(boxes, matches(RegExp(r'MediaBox:\s+-9\.00\s+-9\.00')));
      expect(boxes, matches(RegExp(r'TrimBox:\s+0\.00\s+0\.00')));
    });

    test('the layout report lists the blocks that break across pages', () {
      final source = StringBuffer(':pdf-layout-report: report.txt\n\n');
      for (var i = 0; i < 40; i++) {
        source.write('Paragraph $i.\n\n');
      }
      source.write(
        '----\n${[for (var i = 0; i < 40; i++) 'line $i'].join('\n')}\n----\n',
      );
      final pdf = _pdf(source.toString());
      final report = File('${File(pdf).parent.path}/report.txt');
      expect(
        report.readAsStringSync(),
        matches(
          RegExp(r'^d\d+\.adoc: line 83: listing on pages (\d+)-(?!\1)\d+\n$'),
        ),
      );
    });
  }, skip: _tools && _has('qpdf') ? false : 'needs poppler and qpdf');

  group('numerals and small capitals', () {
    const noto = '''
font:
  catalog:
    Noto:
      normal: notoserif-features.ttf
      italic: notoserif-features.ttf
      bold: notoserif-features.ttf
      bold_italic: notoserif-features.ttf
base:
  font-family: Noto
''';

    /// The glyph codes the pages of [pdf] show, in order.
    List<String> codes(String pdf) {
      final qdf =
          Process.runSync('qpdf', [
                '--qdf',
                '--object-streams=disable',
                pdf,
                '-',
              ], stdoutEncoding: latin1).stdout
              as String;
      return [
        for (final array in RegExp(r'\[([^\]]*)\]\s*TJ').allMatches(qdf))
          for (final hex in RegExp('<([0-9a-fA-F]*)>').allMatches(array[1]!))
            hex[1]!,
      ];
    }

    test("an ordered list's numbers in old-style figures", () {
      const source = ':nofooter:\n\n. One\n. Two\n';
      final lining = codes(_pdf(source, theme: noto));
      final oldstyle = codes(
        _pdf(
          source,
          theme: '${noto}olist_marker_font_variant_numeric: oldstyle-nums\n',
        ),
      );
      // The numbers change, the items' text doesn't.
      expect(oldstyle, isNot(lining));
      expect(oldstyle.length, lining.length);
    });

    test('old-style numerals by the theme', () {
      const source = ':nofooter:\n\nIn 2026.';
      final lining = codes(_pdf(source, theme: noto));
      final oldstyle = codes(
        _pdf(
          source,
          theme: '${noto}base_font_variant_numeric: oldstyle-nums\n',
        ),
      );
      expect(oldstyle, isNot(lining));
      // The same text either way.
      expect(
        _pages(
          _pdf(
            source,
            theme: '${noto}base_font_variant_numeric: oldstyle-nums\n',
          ),
        ).first,
        ['In 2026.'],
      );
    });

    test('small capitals by a role', () {
      const source = ':nofooter:\n\nSome [.sc]#Small Caps# here.';
      const theme = '${noto}role_sc_font_variant: small-caps\n';
      expect(
        codes(_pdf(source, theme: theme)),
        isNot(codes(_pdf(source, theme: noto))),
      );
      expect(_pages(_pdf(source, theme: theme)).first, [
        'Some Small Caps here.',
      ]);
    });

    test('small capitals a font lacks are smaller capitals', () {
      // The default theme's Noto Serif subset has no smcp.
      final pdf = _pdf(
        ':nofooter:\n\nSome [.sc]#Small Caps# here.',
        theme: 'role_sc_font_variant: small-caps\n',
      );
      expect(_pages(pdf).first, ['Some SMALL CAPS here.']);
    });
  }, skip: _tools && _has('qpdf') ? false : 'needs poppler and qpdf');

  group('layout keys', () {
    /// Each word of [pdf] with its box: (page, left, top, right, bottom).
    List<(String, int, double, double, double, double)> words(String pdf) {
      final xml =
          Process.runSync('pdftotext', ['-bbox', pdf, '-']).stdout as String;
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
      final pdf = _pdf(
        '= Book\n:doctype: book\n:toc: macro\n\n[preface]\n== Before\n\n'
        'Text.\n\n[#contents]\n== Contents\n\ntoc::[]\n\n== Chapter\n\n'
        'Text.\n',
      );
      final pages = _pages(pdf);
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
      final plain = _pdf(source, theme: 'base_leading: 0.6em\n');
      final spaced = _pdf(
        source,
        theme: 'base_leading: 0.6em\ntoc_entry_spacing: 20\n',
      );
      expect(gap(spaced) - gap(plain), greaterThan(5));
    });

    test('heading_h1_vertical_align: a part title in the middle', () {
      final pdf = _pdf(
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
      final a = _pdf(source, theme: 'heading_margin_top: 4\n');
      final b = _pdf(source, theme: 'heading_margin_top: 8\n');
      // Below the block's own space (12, the default): no difference.
      expect(gap(b) - gap(a), closeTo(0, 0.01));
      final c = _pdf(source, theme: 'heading_margin_top: 30\n');
      expect(gap(c) - gap(a), closeTo(18, 0.01));
    });

    test('footnotes_indent and footnotes_label_gap', () {
      const source = '= Doc\n\nText.footnote:[A note here.]\n';
      final plain = word(_pdf(source), 'note');
      final set = word(
        _pdf(source, theme: 'footnotes_indent: 20\nfootnotes_label_gap: 5\n'),
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
      final raised = _content(_pdf(source, theme: fonts));
      final typographic = _content(
        _pdf(source, theme: '${fonts}base_typographic_scripts: true\n'),
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
      final en = word(_pdf(source, theme: inline), 'Description').$3;
      final wide = word(
        _pdf(source, theme: '${inline}description_list_term_gap: 30\n'),
        'Description',
      ).$3;
      expect(wide, greaterThan(en + 20));
    });

    test('a highlighted token that runs over lines keeps its indentation', () {
      final pdf = _pdf(
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
      File('${_dir.path}/art.txt').writeAsStringSync('+--+\n|  |  X\n+--+\n');
      final pdf = _pdf(
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
      final kept = _pdf(source, theme: 'heading_min_height_after: auto\n');
      final heading = word(kept, 'Heading');
      final text = word(kept, 'Long');
      expect(heading.$2, text.$2);
    });

    test('a concealed index term keeps the space before it', () {
      final pdf = _pdf('When (((HTML)))HTML was.\n');
      expect(_pages(pdf).first.join(' '), contains('When HTML was.'));
    });

    test('a URL breaks as The Chicago Manual of Style has it', () {
      final pdf = _pdf(
        '${'word ' * 12}https://example.org/2016/01/18/a-long-path-here.html\n',
      );
      final lines = _pages(pdf).first;
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
        _pdf('Term:: Description here.\n', theme: inline),
        'Description',
      ).$3;
      final indexed = word(
        _pdf('Term::\n(((term)))\nDescription here.\n', theme: inline),
        'Description',
      ).$3;
      expect(indexed, closeTo(plain, 0.01));
    });

    test('<category>_caption_indent sets a caption in', () {
      const source = '= Doc\n\n.Code\n----\nx\n----\n';
      final plain = word(_pdf(source), 'Code').$3;
      final set = word(
        _pdf(source, theme: 'code_caption_indent: 12\n'),
        'Code',
      );
      expect(set.$3 - plain, closeTo(12, 0.01));
    });

    test("a look's measure sets the side margins", () {
      File('${_dir.path}/narrow-look.yml').writeAsStringSync(
        'extends: ptome\ntokens:\n'
        '  size: { text: { print: 10pt } }\n'
        '  measure: { print: 30em }\n'
        '  page: { size: A4, margin: ~ }\n',
      );
      final pdf = _pdf(
        '= Doc\n:nofooter:\n\nWords.\n',
        attributes: {'looksdir': _dir.path, 'look': 'narrow', 'pdf-theme!': ''},
      );
      // 30em of 10pt is 300pt: centered on A4's 595.28pt.
      final x = double.parse(
        RegExp(r'xMin="([\d.]+)"[^>]*>Words').firstMatch(
          Process.runSync('pdftotext', ['-bbox', pdf, '-']).stdout as String,
        )![1]!,
      );
      expect(x, closeTo((595.28 - 300) / 2, 0.5));
    });

    test("a document's look is its PDF theme; a named theme replaces it", () {
      // A look that sets the text size; a theme that extends it.
      File('${_dir.path}/big-look.yml').writeAsStringSync(
        'extends: ptome\ntokens:\n  size: { text: { print: 14pt } }\n',
      );
      File('${_dir.path}/over-theme.yml')
          .writeAsStringSync('extends: look\nheading:\n  font_color: FF0000\n');
      // (No pdf-theme: the helper's default unset.)
      final looks = {'looksdir': _dir.path, 'look': 'big', 'pdf-theme!': ''};
      String sizes(String pdf) =>
          RegExp(r'/F\d+ (\d+(?:\.\d+)?) Tf')
              .allMatches(_content(pdf))
              .map((m) => m[1])
              .toSet()
              .join(' ');
      final looked = _pdf('= Doc\n\nText.\n', attributes: looks);
      expect(sizes(looked), contains('14'));
      // A theme the document names replaces the look...
      final named = _pdf(
        '= Doc\n\nText.\n',
        attributes: {'looksdir': _dir.path, 'look': 'big'},
      );
      expect(sizes(named), isNot(contains('14')));
      // ...unless it extends it.
      final extended = _pdf(
        '= Doc\n\n== Heading\n\nText.\n',
        attributes: {
          'looksdir': _dir.path,
          'look': 'big',
          'pdf-theme': 'over',
          'pdf-themesdir': _dir.path,
        },
      );
      expect(sizes(extended), contains('14'));
      expect(_content(extended), contains('1 0 0 rg'));
    });

    test("a look's title page: its slots in order, a verso after it", () {
      File('${_dir.path}/tp-look.yml').writeAsStringSync('''
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
      final pdf = _pdf(
        '= The Art of Slots: Title Pages\n'
        'Ada Lovelace; Charles Babbage\n'
        'v2.1, 2026-10-11\n'
        ':doctype: book\n:publisher: Anticomplex\n'
        ':copyright: Copyright 2026\n\n== One\n\nText.\n',
        attributes: {'looksdir': _dir.path, 'look': 'tp', 'pdf-theme!': ''},
      );
      final pages = _pages(pdf);
      expect(pages[0], [
        'Ada Lovelace & Charles Babbage',
        'The Art of Slots',
        'Title Pages',
        'Anticomplex',
      ]);
      expect(pages[1], ['Copyright 2026', 'Edition: Version 2.1, 2026-10-11']);
      expect(pages[2].first, 'One');
      // (The slots placed by their space, not the theme's title_top.)
      expect(_top(pdf, 'Art')! - _top(pdf, 'Ada')!, greaterThan(144));
      expect(_top(pdf, 'Anticomplex')! - _top(pdf, 'Title')!, greaterThan(216));
    });

    test("a theme's title_page_recto: its parts alone, margins as lengths", () {
      const source =
          '= Doc Title\nAn Author\nv1.0\n:doctype: book\n\n'
          '== One\n\nText.\n';
      final plain = _pages(_pdf(source))[0];
      expect(plain, ['Doc Title', 'An Author', 'Version 1.0']);
      final pdf = _pdf(
        source,
        theme:
            'title_page:\n  recto:\n  - revision\n'
            '  - content: title\n    margin-top: 1in\n',
      );
      expect(_pages(pdf)[0], ['Version 1.0', 'Doc Title']);
      expect(_top(pdf, 'Doc')! - _top(pdf, 'Version')!, greaterThan(72));
    });

    test("a heading's number hung in the margin, or on a line of its own", () {
      double x(String pdf, String word) => double.parse(
        RegExp('xMin="([\\d.]+)"[^>]*>${RegExp.escape(word)}<').firstMatch(
          Process.runSync('pdftotext', ['-bbox', pdf, '-']).stdout as String,
        )![1]!,
      );
      const source =
          '= Act\n\n== [.number]#17# Offences\n\nWords at the margin.\n';
      final hung = _pdf(
        source,
        theme: 'heading:\n  number_placement: hang\n  number_hang: 40\n',
      );
      // The title at the text's edge, its number 40 pt left of it.
      expect(x(hung, 'Offences'), closeTo(x(hung, 'Words'), 0.5));
      expect(x(hung, '17'), closeTo(x(hung, 'Words') - 40, 0.5));
      expect(_top(hung, '17'), closeTo(_top(hung, 'Offences')!, 0.5));
      final lined = _pdf(source, theme: 'heading:\n  number_placement: line\n');
      expect(_top(lined, 'Offences'), greaterThan(_top(lined, '17')! + 10));
      expect(x(lined, 'Offences'), closeTo(x(lined, '17'), 0.5));
      // Without a placement, in its line.
      final inline = _pdf(source);
      expect(_top(inline, '17'), closeTo(_top(inline, 'Offences')!, 0.5));
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
            Process.runSync('pdftotext', [
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

      final pdf = _pdf(source, theme: 'columns_count: 3\n');
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
            Process.runSync('pdftotext', [
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
      expect(widestGap(_pdf(source, compat: true)), lessThan(10));
    });

    test("a paragraph's initial: its own first letter, lines deep", () {
      const theme =
          'role:\n  dropcap:\n    drop_lines: 3\n    drop_lead_in: 2\n'
          '  lead-in:\n    text_transform: uppercase\n';
      final pdf = _pdf(
        '= Doc\n\n[.dropcap]\nThe snow came in the night, the first big '
        'storm of the season, and by morning the ridge above the creek held '
        'more than two feet of new powder, and sixteen skiers gathered at '
        'the top of the lift to wait for the others.\n\n'
        '[.dropcap]\n"`It was long,`" she said.\n\nAfter.\n',
        theme: theme,
      );
      final bbox =
          Process.runSync('pdftotext', ['-bbox', pdf, '-']).stdout as String;
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
          Process.runSync('pdftotext', [
                _pdf('[.dropcap]\nThe snow.\n', compat: true, theme: theme),
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
      final pdf = _pdf(
        '= Doc\n\n[.pull]\n____\nIt was the longest minute of my '
        'life.\n____\n\n${words * 6}\n',
        theme:
            'role:\n  pull:\n    float: right\n    float_width: 50%\n'
            '    float_gap: 12\n',
      );
      final out =
          Process.runSync('pdftotext', ['-bbox', pdf, '-']).stdout as String;
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
      final pdf = _pdf(
        '= Issue\n\n== News\n\n$words\n\n[.feature]\n== Feature\n\n'
        '$words\n\n== Letters\n\n$words\n',
        theme: theme,
      );
      final pages = [
        for (final page in _pages(pdf))
          if (page.isNotEmpty) page,
      ];
      expect(pages, hasLength(3));
      expect(pages[1].first, 'Feature');
      expect(pages[2].first, 'Letters');
      // Its margins: the text 144 pt in; its tint; no running content.
      final bbox =
          Process.runSync('pdftotext', [
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
          Process.runSync('pdftotext', ['-layout', pdf, '-']).stdout as String;
      expect(
        footers.split('\f')[1],
        isNot(contains(RegExp(r'^\s*2\s*$', multiLine: true))),
      );
      expect(_content(pdf), contains('0.95294 0.92157 0.86667 rg'));
      // Its columns: two, the text starting at both.
      final columned = _pdf(
        '= Issue\n\n[.feature]\n== Feature\n\n$words $words\n',
        theme: '$theme      page_columns: 2\n',
      );
      final starts = RegExp(r'<line xMin="([\d.]+)"')
          .allMatches(
            Process.runSync('pdftotext', ['-bbox-layout', columned, '-']).stdout
                as String,
          )
          .map((m) => double.parse(m[1]!).round())
          .toSet();
      expect(starts, containsAll([144]));
      expect(starts.where((x) => x > 250), isNotEmpty, reason: '$starts');
      // Last in the document: no page after it.
      final last = _pdf(
        '= Issue\n\n== News\n\n$words\n\n[.feature]\n== Feature\n\n$words\n',
        theme: theme,
      );
      expect(_pages(last).where((p) => p.isNotEmpty), hasLength(2));
      // asciidoctor-pdf's: no page of its own.
      final compat = _pdf(
        '= Issue\n\n== News\n\nText.\n\n[.feature]\n== Feature\n\nText.\n',
        theme: theme,
        compat: true,
      );
      expect(_pages(compat).where((p) => p.isNotEmpty), hasLength(1));
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
        for (final page in _pages(_pdf(source, theme: 'pagination: $mode\n')))
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
          for (final line in _pages(_pdf(source, theme: theme)).first)
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
        for (final line in _pages(
          _pdf(source, theme: 'base:\n  overhang: $overhang\n'),
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
        for (final m in RegExp(r'([\d.]+) Tz').allMatches(_content(pdf)))
          double.parse(m[1]!),
      ];
      final plain = _pdf(source, theme: 'base:\n  overhang: true\n');
      expect(scales(plain).where((s) => s != 100), isEmpty);
      final expanded = _pdf(source, theme: 'base:\n  font_expansion: true\n');
      final set = scales(expanded).where((s) => s != 100).toList();
      expect(set, isNotEmpty);
      expect(set.every((s) => s >= 98 - 1e-6 && s <= 102 + 1e-6), isTrue);
      // The opening quote hangs left of the text's edge.
      final bbox =
          Process.runSync('pdftotext', ['-bbox', plain, '-']).stdout as String;
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
      final content = _content(_pdf('Text.\n', theme: theme));
      expect(content, contains('1 0 0 RG'));
      // The thick rule outside, the thin one inside it.
      final rules = RegExp(r'([\d.]+) w\n([\d.-]+) ([\d.-]+) [\d.]+ [\d.]+ re')
          .allMatches(content)
          .map((m) => (double.parse(m[1]!), double.parse(m[2]!)))
          .toList();
      expect(rules.map((r) => r.$1), containsAllInOrder([3, 1]));
      expect(rules.first.$2, lessThan(rules.last.$2));
      expect(
        _content(_pdf('Text.\n', theme: theme, compat: true)),
        isNot(contains('1 0 0 RG')),
      );
    });

    test('tracking: a role, a heading, and capitals by themselves', () {
      // Where the word [word] starts and ends on the first page of [pdf].
      (double, double) extent(String pdf, String word) {
        final m = RegExp('xMin="([\\d.]+)"[^>]*xMax="([\\d.]+)"[^>]*>$word<')
            .firstMatch(
              Process.runSync('pdftotext', [
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
      final plain = _pdf(source, theme: 'base:\n  font_size: 10\n');
      final tracked = _pdf(
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
      final schemes = Directory('${_dir.path}/schemes')..createSync();
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
      final pdf = _pdf(
        '= Notes\n:units: bible, kjv, study\n\n== @GEN\n\n=== @1\n\n$verses',
        theme:
            'page:\n  size: [360, 400]\n  margin: [36, 36, 36, 36]\n'
            'note_streams: [tn, sn]\n'
            'note_stream:\n'
            '  tn:\n    arrangement: run_in\n'
            '  sn:\n    columns: 3\n    column_gap: 8\n    font_size: 7\n',
      );
      final bbox =
          Process.runSync('pdftotext', ['-bbox', pdf, '-']).stdout as String;
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
      final schemes = Directory('${_dir.path}/schemes')..createSync();
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
        final pages = _pages(
          _pdf(
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
      final schemes = Directory('${_dir.path}/schemes')..createSync();
      File('test/units/corpus/schemes/stephanus.yml')
          .copySync('${schemes.path}/stephanus.yml');
      File('${schemes.path}/app.yml').writeAsStringSync(
        'stream:\n  app:\n    placement: "footnote"\n'
        '    origin: "{{page}}{{section}}"\n    lemma-after: "] "\n',
      );
      final words = [for (var k = 0; k < 40; k++) 'verbum$k'].join(' ');
      final pdf = _pdf(
        '= Dialogus\n:units: stephanus, app\n:look: critical-edition\n'
        ':line-numbers:\n\n'
        '@2a Primum ##dicit##note:app[dixit B] $words\n\n'
        '@ Secundum $words\n',
        // (The look as the theme: the helper names asciidoctor-pdf's.)
        attributes: {
          'pdf-theme': (File(
            '${_dir.path}/look-theme.yml',
          )..writeAsStringSync('extends: look\n')).path,
        },
      );
      final text = _pages(pdf).expand((page) => page).join('\n');
      // The Stephanus labels beside the lines only, not in the text; the
      // apparatus entry at the foot by its section, with no mark in the
      // text.
      expect(text, contains('Primum dicit verbum0'));
      expect(text, contains('Secundum verbum0'));
      expect(text, isNot(contains('2b Secundum')));
      expect(text, contains('2a dicit] dixit B'));
      expect(text, isNot(contains('[1]')));
      final bbox =
          Process.runSync('pdftotext', ['-bbox', pdf, '-']).stdout as String;
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
      final pdf = _pdf(
        '= The Harbour\n:doctype: book\n:look: trade-novel\n'
        ':media: prepress\n\n'
        '== One\n\nWhen the boat came in $words\n\n'
        "'''\n\nLater.\n\n== Two\n\nAfter all of it.\n",
        // (The look as the theme: the helper names asciidoctor-pdf's.)
        attributes: {
          'pdf-theme': (File(
            '${_dir.path}/look-theme.yml',
          )..writeAsStringSync('extends: look\n')).path,
        },
      );
      final pages = _pages(pdf);
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
      final pdf = _pdf(
        '= The State\n:doctype: book\n:look: scholarly-monograph\n'
        ':media: prepress\n\n'
        '== One\n\nOpening ((capital)) (((capital, labour))) $words\n\n'
        '[quote]\n____\n$quote\n____\n\n'
        'After (((capital, finance))).\n\n[index]\n== Index\n',
        // (The look as the theme: the helper names asciidoctor-pdf's.)
        attributes: {
          'pdf-theme': (File(
            '${_dir.path}/look-theme.yml',
          )..writeAsStringSync('extends: look\n')).path,
        },
      );
      final bbox =
          Process.runSync('pdftotext', ['-bbox', pdf, '-']).stdout as String;
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
      final text = _pages(pdf).expand((page) => page).join('\n');
      expect(text, contains(RegExp(r'capital, 1; finance, \d+; labour, 1')));
    });

    group('the bill looks', () {
      setUpAll(() {
        final schemes = Directory('${_dir.path}/schemes')..createSync();
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
      }) => _pdf(
        '= A Bill\n:units: $units\n:look: $look\n:line-numbers:\n$header\n'
        '$body',
        // (The look as the theme: the helper names asciidoctor-pdf's.)
        attributes: {
          'pdf-theme': (File(
            '${_dir.path}/look-theme.yml',
          )..writeAsStringSync('extends: look\n')).path,
        },
      );

      /// The left edge of each word in [pdf], by its text (the first).
      Map<String, double> lefts(String pdf) {
        final bbox =
            Process.runSync('pdftotext', ['-bbox', pdf, '-']).stdout as String;
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
        final lines = _pages(pdf).first;
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
          _pages(bill('us-bill', 'usc', body)).first.join('\n'),
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
        final text = _pages(pdf).first.join('\n');
        expect(text, contains(RegExp(r'\s5$', multiLine: true)));
        expect(text, isNot(contains(RegExp(r'\s4$', multiLine: true))));
        // (Flush right: 5 and 10 end at the same place.)
        final bbox =
            Process.runSync('pdftotext', ['-bbox', pdf, '-']).stdout as String;
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
      String rule(String body) => _pdf(
        '= Digital Certificate of Number\n:look: federal-register\n'
        ':notitle:\n'
        ':fr-issue: Vol. 89, No. 108 / Tuesday, June 4, 2024 / Rules\n'
        ':folio-start: 47855\n\n$body',
        // (The look as the theme: the helper names asciidoctor-pdf's.)
        attributes: {
          'pdf-theme': (File(
            '${_dir.path}/look-theme.yml',
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
              Process.runSync('pdftotext', [
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
        final text = _pages(pdf).first.join('\n');
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
        _pdf(
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
      final pdf = _pdf(
        '= Complaint\n:look: pleading\n:line-numbers: grid\n:notitle:\n\n'
        'Jane Q. Attorney (SBN 123456) +\n100 Main Street +\n'
        'Attorney for Plaintiff\n\n'
        '[.court]\nSUPERIOR COURT OF CALIFORNIA\n\n== Allegations\n\n$words\n',
        // (The look as the theme: the helper names asciidoctor-pdf's.)
        attributes: {
          'pdf-theme': (File(
            '${_dir.path}/look-theme.yml',
          )..writeAsStringSync('extends: look\n')).path,
        },
      );
      final bbox =
          Process.runSync('pdftotext', [
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
      final schemes = Directory('${_dir.path}/schemes')..createSync();
      for (final f in Directory('test/units/fixtures/schemes').listSync()) {
        if (f is File) {
          f.copySync('${schemes.path}/${f.uri.pathSegments.last}');
        }
      }
      String verse(int v) =>
          '@ Verse$v of the ##chapter##note:x[<<Gen 2:$v>>] goes on '
          'for a while, word upon word.\n';
      final verses = [for (var v = 1; v <= 30; v++) verse(v)].join();
      final themeFile = File('${_dir.path}/look-theme.yml')
        ..writeAsStringSync('extends: look\n');
      String textOf(String look) {
        final source =
            '= Bible\n:units: bible, kjv\n:look: $look\n:doctype: book\n\n'
            '== @GEN\n\n=== @1\n\n$verses\n=== @2\n\n$verses';
        // (The look as the theme: the helper names asciidoctor-pdf's.)
        final pdf = _pdf(source, attributes: {'pdf-theme': themeFile.path});
        // (Without spaces: pdftotext joins words a narrow face's spaces
        // set close, as Crimson Pro's are at 6 pt.)
        return (Process.runSync('pdftotext', ['-raw', pdf, '-']).stdout
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

    test('a box across the columns at the foot, its body in columns', () {
      // A study Bible's feature article: in page columns, a sidebar with
      // the role floats to the bottom of the page across both columns,
      // above the notes, its own body in two balanced columns.
      final text = [for (var k = 0; k < 30; k++) 'Text sentence $k goes on.']
          .join(' ');
      final feature = [for (var k = 0; k < 60; k++) 'Feat$k word.'].join(' ');
      final pdf = _pdf(
        '= Doc\n\n$text footnote:[A note.]\n\n[.feature]\n.Article\n'
        '****\n$feature\n****\n\n$text\n',
        theme:
            'page:\n  columns: 2\n'
            'role:\n  feature: { float: bottom, float_scope: page }\n'
            'sidebar:\n  role:\n    feature:\n      columns: 2\n',
      );
      final bbox =
          Process.runSync('pdftotext', ['-bbox', pdf, '-']).stdout as String;
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
      final schemes = Directory('${_dir.path}/schemes')..createSync();
      for (final f in Directory('test/units/fixtures/schemes').listSync()) {
        if (f is File) {
          f.copySync('${schemes.path}/${f.uri.pathSegments.last}');
        }
      }
      final pdf = _pdf(
        '= Psalm\n:units: bible, kjv\n\n== @GEN\n\n=== @1\n\n'
        '@ Prose verse one.\n\n[.poetry%hardbreaks]\n'
        '@ Poem line two\n@ poem line three\n',
        theme:
            'units:\n  verse:\n    label_font_style: bold\n'
            '    label_hang: [poetry]\n',
      );
      final bbox =
          Process.runSync('pdftotext', ['-bbox', pdf, '-']).stdout as String;
      double x(String word, {String edge = 'xMin'}) => double.parse(
        RegExp('$edge="([\\d.]+)"[^>]*>$word<').firstMatch(bbox)![1]!,
      );
      // Each number left of its line's first word, ending before it.
      expect(x('2', edge: 'xMax'), lessThan(x('Poem')));
      expect(x('3', edge: 'xMax'), lessThan(x('poem')));
      expect(x('Poem'), closeTo(x('poem'), 0.5));
    });

    test('a heading in the margin: a chapter number left of its text', () {
      final schemes = Directory('${_dir.path}/schemes')..createSync();
      for (final f in Directory('test/units/fixtures/schemes').listSync()) {
        if (f is File) {
          f.copySync('${schemes.path}/${f.uri.pathSegments.last}');
        }
      }
      final pdf = _pdf(
        '= Bible\n:units: bible, kjv\n:doctype: book\n\n== @GEN\n\n'
        '=== @1\n\n@ Opening words of the chapter.\n@ More words.\n\n'
        '=== @2\n\n@ Second chapter words.\n',
        theme:
            'heading:\n  h3:\n    display: margin\n'
            '    margin_font_size: 16\n'
            "    margin_content: '{{attr-number}}'\n",
      );
      final bbox =
          Process.runSync('pdftotext', ['-bbox', pdf, '-']).stdout as String;
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
      final pdf = _pdf(
        'Text.footnote:[First note.] More.footnote:[Second note.]\n',
        theme:
            'base:\n  font_family: Times-Roman\n'
            'footnotes:\n  arrangement: run_in\n  font_family: Times-Roman\n',
      );
      final text = _pages(pdf).expand((page) => page).join('\n');
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
        final pdf = _pdf(source, theme: theme);
        return Process.runSync('pdftotext', [pdf, '-']).stdout as String;
      }

      List<String> words(String text) => text
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty && !RegExp(r'^\d+$').hasMatch(w))
          .toList();
      final box = text('base:\n  text_align: justify\n  text_engine: box\n');
      final engine = text('base:\n  text_align: justify\n');
      // (Set by the engine, at the places the text box sets it.)
      final messages = MemoryLogger();
      _pdf(source, theme: 'base:\n  text_align: justify\n', logger: messages);
      expect(
        messages.messages.map((m) => '${m.message}'),
        contains(matches(RegExp('^paragraphs set by the engine: [1-9]'))),
      );
      List<(double, double)> placesOf(String theme) {
        final bbox =
            Process.runSync('pdftotext', [
                  '-bbox',
                  _pdf(source, theme: theme),
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
            Process.runSync('pdftotext', [
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
      final canon = _pdf(
        '= Doc\n\n$words\n',
        theme: 'page:\n  size: [540, 720]\n  margin_canon: 9\n',
      );
      expect(firstLeft(canon), closeTo(60, 0.5));
      // DIV 10 and a 20 pt allowance: (540 - 20) / 10 = 52 pt a stripe,
      // the inner margin 72 pt.
      final div = _pdf(
        '= Doc\n\n$words\n',
        theme:
            'page:\n  size: [540, 720]\n  margin_div: 10\n'
            '  margin_bcor: 20\n',
      );
      expect(firstLeft(div), closeTo(72, 0.5));
      // A prepress book of more than 150 pages: KDP's inner margin of
      // half an inch on a recto, though the theme asks for less.
      final long = [for (var k = 0; k < 170; k++) 'Words $k.\n\n<<<\n'].join();
      final book = _pdf(
        '= Book\n:doctype: book\n:media: prepress\n\n== One\n\n$long',
        theme:
            'page:\n  size: [300, 400]\n  margin: [36, 18, 36, 18]\n'
            '  margin_inner: 18\n  margin_outer: 18\n'
            '  margin_gutter: kdp\n',
      );
      final pages = _pages(book).length;
      expect(pages, greaterThan(150));
      final recto = [
        for (var p = 5; p < 15; p++)
          if (p.isOdd) firstLeft(book, page: p),
      ];
      expect(recto, everyElement(closeTo(36, 0.5)));
    });

    test('a thematic break as a mark, shown at a page boundary', () {
      // As a dinkus wherever it is.
      final always = _pages(
        _pdf(
          "Before.\n\n'''\n\nAfter.\n",
          theme: "thematic_break:\n  content: '* * *'\n",
        ),
      ).expand((page) => page);
      expect(always, contains(matches(r'^\*\s*\*\s*\*$')));
      // As space mid-page, but as a mark where the text after it goes
      // on on the next page.
      final kept = List.filled(18, 'Kept line.').join(' +\n');
      final pages = _pages(
        _pdf(
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
      final pitch = _baselines(
        _pdf(
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
      final text = _pages(_pdf(source, theme: theme)).expand((p) => p);
      // (The letter apart, its next words in the lead-in's role.)
      expect(text, contains(matches(r'^W\s')));
      expect(text, contains(contains('HEN THE')));
      expect(text, isNot(contains(contains('HEN THE SNOW'))));
      expect(text.join(' '), isNot(contains('SECOND')));
      // asciidoctor-pdf's: no initial.
      final plain = _pages(_pdf(source, compat: true, theme: theme))
          .expand((p) => p);
      expect(plain, contains(contains('When the snow')));
    });

    test('a note stream run in, or in a margin column of its own', () {
      final schemes = Directory('${_dir.path}/schemes')..createSync();
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
      String pdf(String keys) =>
          _pdf(source, theme: 'note_streams: [tn]\nnote_stream:\n  tn:\n$keys');
      // Run in: the three notes on one line.
      final runIn = _pages(pdf('    arrangement: run_in\n'))
          .expand((page) => page)
          .where((line) => line.contains('Heb.'))
          .toList();
      expect(runIn, hasLength(1));
      expect(runIn.single, contains('Elohim'));
      expect(runIn.single, contains('erets'));
      // In the left margin, each beside its verse.
      final side = pdf('    column: left\n    font_size: 7\n');
      final bbox =
          Process.runSync('pdftotext', ['-bbox', side, '-']).stdout as String;
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
        final themeFile = File('${_dir.path}/stream-${_count++}-theme.yml')
          ..writeAsStringSync('extends: default\n$theme');
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
      expect(_content(apart), contains('1 0 0 rg'));
      expect(_pages(apart).expand((p) => p).join(' '), contains('Heb.'));
      // Not listed: a footnote as before.
      expect(
        _content(convert('note_stream:\n$red')),
        isNot(contains('1 0 0 rg')),
      );
      // In two columns: one note, whole.
      final columned = convert(
        'note_streams: [tn]\nnote_stream:\n  tn:\n    columns: 2\n',
      );
      expect(_pages(columned).expand((p) => p).join(' '), contains('Heb.'));
    });

    test('line numbers: typeset, logical and grid lines', () {
      const verse =
          '[verse]\n____\nShall I compare thee to a summer day, thou art '
          'more lovely and more temperate than any other day of the long '
          'and lovely year, and so on\nRough winds do shake the darling buds\n'
          '____\n';
      // The numbers in the left margin of the first page.
      List<String> numbers(String kind, {String theme = ''}) {
        final pdf = _pdf(
          '= Poem\n:line-numbers: $kind\n\n$verse',
          theme: theme.isEmpty ? 'line_numbers:\n  gap: 6\n' : theme,
        );
        return [
          for (final m in RegExp(r'xMax="([\d.]+)"[^>]*>(\d+)<').allMatches(
            Process.runSync('pdftotext', [
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
            Process.runSync('pdftotext', [
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
      final usual = numbers(_pdf(plain, theme: theme('first_line')));
      expect(numbers(_pdf(headed, theme: theme('first_line'))), usual + 1);
      // (On the page's own grid, no more.)
      expect(numbers(_pdf(headed, theme: theme('page'))), usual);
    });

    test('line numbers from each Stephanus section, its label beside it', () {
      final schemes = Directory('${_dir.path}/schemes')..createSync();
      for (final f in Directory('test/units/corpus/schemes').listSync()) {
        if (f is File) {
          f.copySync('${schemes.path}/${f.uri.pathSegments.last}');
        }
      }
      final words = 'Words of the dialogue go on here. ' * 30;
      final pdf = _pdf(
        '= Dialogue\n:units: stephanus\n:line-numbers:\n\n'
        '@2a $words @ $words @ $words\n',
        theme: 'line_numbers:\n  interval: 5\n  restart_units: section\n',
      );
      final margin = [
        for (final m in RegExp(r'xMax="([\d.]+)"[^>]*>([^<]+)<').allMatches(
          Process.runSync('pdftotext', ['-bbox', pdf, '-']).stdout as String,
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
              Process.runSync('pdftotext', [
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
      expect(onGrid(tops(_pdf(source, theme: theme))), isFalse);
      final gridded = tops(
        _pdf(source, theme: '${theme}page_baseline_grid: true\n'),
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
      expect(_pages(_pdf(source, theme: theme)).first, [
        'Coastlines',
        'The Head',
        'The dek under it',
        'Anne Author',
        'The text.',
      ]);
      // asciidoctor-pdf's: the document title alone.
      expect(
        _pages(_pdf(source, theme: theme, compat: true)).first.first,
        'The Head: The dek under it',
      );
    });

    test("a quote's role styles it by quote_role_<role>_* keys", () {
      const source = '[.pull]\n____\nQuoted.\n____\n';
      const theme = "quote:\n  role:\n    pull:\n      font_color: 'FF0000'\n";
      expect(_content(_pdf(source, theme: theme)), contains('1 0 0 rg'));
      expect(
        _content(_pdf('____\nQuoted.\n____\n', theme: theme)),
        isNot(contains('1 0 0 rg')),
      );
    });

    test('page columns: rules between them, balanced where they end', () {
      final words = 'Words of the piece run on across the page. ' * 20;
      const theme =
          'page_columns: 3\npage_columns_balance: true\n'
          "page_column_rule_width: 0.5\npage_column_rule_color: 'FF0000'\n";
      final pdf = _pdf('= Issue\n\n$words\n', theme: theme);
      expect(_content(pdf), contains('1 0 0 RG'));
      // A short text: in all three columns, not the first alone.
      final starts = RegExp(r'<line xMin="([\d.]+)"')
          .allMatches(
            Process.runSync('pdftotext', ['-bbox-layout', pdf, '-']).stdout
                as String,
          )
          .map((m) => double.parse(m[1]!).round())
          .toSet();
      expect(starts, hasLength(3), reason: '$starts');
      // asciidoctor-pdf's: no rules.
      expect(
        _content(_pdf('= Issue\n\n$words\n', theme: theme, compat: true)),
        isNot(contains('1 0 0 RG')),
      );
    });

    test('a block floating to a side in columns: a share of its column', () {
      final words = 'Words of the piece run on across the page. ' * 30;
      const theme = 'role:\n  aside:\n    float: right\n    float_width: 50%\n';
      final pdf = _pdf(
        '[.columns]\n== Piece\n\n[.aside]\n****\nAside\n****\n\n$words\n',
        theme: theme,
      );
      final bbox =
          Process.runSync('pdftotext', ['-bbox', pdf, '-']).stdout as String;
      final aside = double.parse(
        RegExp(r'xMin="([\d.]+)"[^>]*>Aside<').firstMatch(bbox)![1]!,
      );
      // Two columns of the A4 page's 498 pt: the aside in the right half
      // of the first (it ends at about 291).
      expect(aside, greaterThan(150));
      expect(aside, lessThan(291));
    });

    test('jump lines: continued on the page the piece goes on, and from', () {
      const source =
          '= Issue\n\n[#a]\n== A Piece\n\nIt starts.\n\n'
          '[.jump.text-right]\n<<a-more>>\n\n<<<\n\n== News\n\nOther.\n\n'
          '<<<\n\n[#a-more]\n== A Piece, Continued\n\n[.jump]\n<<a>>\n\n'
          'It ends.\n';
      final pages = _pages(_pdf(source));
      expect(pages[0], contains('Continued on page 3'));
      expect(pages[2], contains('Continued from page 1'));
      // Its wording, the document's.
      final worded = _pages(
        _pdf(
          source,
          attributes: {'jump-template': '{{^back}}See p. {{page}}{{/back}}'},
        ),
      );
      expect(worded[0], contains('See p. 3'));
      // asciidoctor-pdf's: the cross reference as it is.
      expect(
        _pages(_pdf(source, compat: true))[0],
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
            Process.runSync('pdftotext', ['-bbox', pdf, '-']).stdout as String;
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
      final boxed = ends(_pdf(source(''), theme: theme)).take(6).toList();
      expect(boxed.reduce(math.max) - boxed.reduce(math.min), lessThan(20));
      // Around its outline, a circle: the first lines reach past where
      // the middle ones end.
      final shaped = ends(_pdf(source(',shape=alpha'), theme: theme))
          .take(12)
          .toList();
      expect(shaped.first, greaterThan(shaped.reduce(math.min) + 40));
      // The image's own float and shape, as on the web.
      final own = ends(
        _pdf(
          '= Doc\n\nimage::$circle[Circle,pdfwidth=40%,float=right,'
          'shape=alpha]\n\n${words * 14}\n',
        ),
      ).take(12).toList();
      expect(own.first, greaterThan(own.reduce(math.min) + 40));
    });

    test('base_font_embedding: simple embeds simple TrueType fonts', () {
      final source = 'Words in a line that is set justified and wraps.\n' * 4;
      const theme = 'base_text_align: justify\n';
      final composite = _pdf(source, theme: theme);
      final simple = _pdf(
        source,
        theme: '${theme}base_font_embedding: simple\n',
      );
      String fonts(String pdf) =>
          '${Process.runSync('pdffonts', [pdf]).stdout}';
      expect(fonts(composite), contains('CID TrueType'));
      expect(fonts(simple), isNot(contains('CID')));
      expect(fonts(simple), contains('TrueType'));
      // The same text in the same places, the word spacing a Tw.
      expect(_pages(simple), _pages(composite));
      expect(_content(simple), contains(' Tw'));
    });

    test('example_collapsible: details sets a collapsible block open', () {
      const source = 'Before.\n\n.More\n[%collapsible]\n====\nInside.\n====\n';
      // A frame by default: the content inside its padding.
      final framed = _pdf(source, theme: 'example_padding: 12\n');
      expect(
        word(framed, 'Inside.').$3 - word(framed, 'Before.').$3,
        closeTo(12, 0.01),
      );
      // Details: the title after a marker, the content set in by it.
      final details = _pdf(
        source,
        theme: 'example_padding: 12\nexample_collapsible: details\n',
      );
      final title = word(details, 'More');
      final inside = word(details, 'Inside.');
      expect(title.$3, greaterThan(word(details, 'Before.').$3));
      expect(inside.$3, closeTo(title.$3, 0.01));
      expect(_pages(details).first, contains('▼ More'));
    });

    test('lines break after a slash, not next to a bracket (UAX #14)', () {
      // A narrow page: the words must break.
      const theme =
          'page_size: [200, 400]\npage_margin: 10\nbase_text_align: left\n';
      final slash = _pdf(
        'Here somewhereoverthe/rainbowwaywayuphigh.\n',
        theme: theme,
      );
      expect(
        _pages(slash).first.any((l) => l.endsWith('somewhereoverthe/')),
        isTrue,
        reason: '${_pages(slash).first}',
      );
      final braces = _pdf(
        'Words words words words words words {{ request.args }} more.\n',
        theme: theme,
      );
      final lines = _pages(braces).first;
      expect(lines.any((l) => l.endsWith('{{')), isFalse, reason: '$lines');
    });

    test('olist_marker_width and olist_body_indent: numbers in boxes', () {
      const source = '. One\n. Two\n';
      final pdf = _pdf(
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
      final pdf = _pdf(
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
      final open = _pdf(source, theme: 'sidebar_padding: 30\n');
      final cloned = _pdf(
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
      final left = _pdf(source, theme: justify);
      final centered = _pdf(
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
      final plain = _pdf(source, theme: justify);
      final cells = _pdf(
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
      final pdf = _pdf(
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
      String bullets(String pdf) => _pages(pdf).first.join('\n');
      expect(bullets(_pdf(source, theme: '')), contains('◦'));
      final own = _pdf(source, theme: 'ulist_marker_nesting: ulist\n');
      expect(bullets(own), contains('•'));
      expect(bullets(own), isNot(contains('◦')));
    });

    test('code_role_<role>_*: a code block with the role', () {
      const source =
          ':nofooter:\n\n----\nfirst\n----\n\n[.bare]\n----\nsecond\n----\n';
      final pdf = _pdf(
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
          _pages(pdf).expand((p) => p).lastWhere((l) => l.startsWith('Widget'));
      expect(entry(_pdf('= Doc\n:media: print\n\n$body')), 'Widget, 1-2');
      expect(
        entry(
          _pdf(
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
      final plain = _pdf('$before$after', theme: theme);
      final floated = _pdf(
        '$before.Fig\nimage::data:image/svg+xml;base64,$svg[pdfwidth=50%]\n\n'
        '$after',
        theme: theme,
      );
      // The paragraph's space before the heading, not before the image.
      expect(gap(floated), closeTo(gap(plain), 0.01));
    });

    test('an unknown value of a key with a set of values is reported', () {
      final logger = MemoryLogger();
      _pdf(
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
      final pdf = _pdf(
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
        final input = File('${_dir.path}/house${_count++}.adoc')
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
          Process.runSync('pdffonts', [pdf]).stdout as String;
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
      expect(_pages(house).first.join(' '), contains('SMALL CAPS'));
    });

    test('AsciiMath and LaTeX math are typeset', () {
      final logger = MemoryLogger();
      final pdf = _pdf(
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
      final fonts = Process.runSync('pdffonts', [pdf]).stdout as String;
      expect(fonts, contains('NotoSansMath'));
      final text = _pages(pdf).first.join(' ');
      expect(text, contains('x^2'));
      expect(text, contains('sum_(i=1)^n i'));
      expect(text, contains(r'\frac{a}{b}'));
      expect(text, contains(r'\sqrt{2}'));
    });

    test('an unknown LaTeX command is shown and reported', () {
      final logger = MemoryLogger();
      // (Each occurrence reported, though the formula is converted once.)
      _pdf(
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
        Process.runSync('pdftotext', ['-bbox', pdf, '-']).stdout as String,
      )) {
        final m? => double.parse(m[1]!),
        null => null,
      };
      final plain = _pdf(':stem:\n\nBefore after.\n');
      final math = _pdf(':stem:\n\nBefore stem:[a/b] after.\n');
      // The line's text where it was: a fraction no taller than the line
      // leaves the baseline alone.
      expect(bottom(math, 'Before'), closeTo(bottom(plain, 'Before')!, 0.5));
    });

    test('a display formula is centered, larger than inline', () {
      final pdf = _pdf(':stem:\n\n[stem]\n++++\nsum_(i=1)^n i\n++++\n');
      final content = _content(pdf);
      // The display sum (a larger variant than the text's) is drawn.
      expect(content, contains('Tf'));
      final info = Process.runSync('pdfinfo', [pdf]).stdout as String;
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
      _pdf(
        ':stem:\n\nstem:[x]\n',
        theme: 'math_font_family: Noto Serif\n',
        logger: logger,
      );
      expect(
        logger.messages.map((m) => m.message.text),
        contains(contains('is not a font with a MATH table')),
      );
    });
  }, skip: _tools && _has('qpdf') ? false : 'needs poppler and qpdf');

  group("asciidoctor-pdf's look (asciidoctor-compat, ADR-0015)", () {
    const images = 'test/pdf/fixtures/images';

    test('block_margin_collapse: false adds the spaces around a heading', () {
      const source = 'Para one.\n\n== Heading\n\nPara two.\n';
      final collapsed = _top(_pdf(source), 'Heading')!;
      final added = _top(
        _pdf(source, theme: 'block_margin_collapse: false\n'),
        'Heading',
      )!;
      expect(added, greaterThan(collapsed + 3));
      expect(
        _top(
          _pdf(source, attributes: {'asciidoctor-compat': 'pdf'}),
          'Heading',
        ),
        added,
      );
    });

    test('base_hyphens: false leaves justified text unhyphenated', () {
      const theme = 'page_size: A7\n';
      bool hyphenated(String pdf) => _pages(pdf).any(
        (lines) =>
            lines.any((line) => RegExp('[a-z][-\u00ad]\$').hasMatch(line)),
      );
      expect(hyphenated(_pdf(_paragraph, theme: theme)), isTrue);
      expect(
        hyphenated(_pdf(_paragraph, theme: '${theme}base_hyphens: false\n')),
        isFalse,
      );
    });

    test('toc_macro_in_section: false gives the contents their own page', () {
      const source =
          '= Book\n:doctype: book\n:toc: macro\n\n== Contents\n\n'
          'toc::[]\n\n== One\n\nText.\n';
      final inSection = _pages(_pdf(source));
      expect(inSection[1].first, 'Contents');
      expect(inSection[1].join(' '), contains('One'));
      final ownPage = _pages(
        _pdf(source, attributes: {'asciidoctor-compat': 'true'}),
      );
      expect(ownPage[1], ['Contents']);
      expect(ownPage[2].first, 'Table of Contents');
      // The theme's own value wins.
      expect(
        _pages(
          _pdf(
            source,
            theme: 'toc_macro_in_section: true\n',
            attributes: {'asciidoctor-compat': 'pdf'},
          ),
        )[1].first,
        'Contents',
      );
    });

    test('a title logo fits the page below its top', () {
      final pdf = _pdf(
        '= Doc\n:title-page:\n:imagesdir: ${Directory.current.path}/$images\n'
        ':title-logo-image: image:tall.png[pdfwidth=100%,top=70%]\n\nText.\n',
      );
      final bottom = RegExp(r'[\d.]+ 0 0 [\d.]+ [\d.]+ ([\d.]+) cm')
          .firstMatch(_content(pdf))!;
      // On the page: at or above the bottom margin (0.67in).
      expect(double.parse(bottom[1]!), greaterThanOrEqualTo(48.24 - 0.01));
    });

    test("an autowidth table's column is as wide as its image", () {
      final content = _content(
        _pdf(
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
      final pdf = _pdf(
        '((foo))((bar))((baz))((boom))((bang))((fee))((fi))((fo))((fum))'
        '((fan))((fool))((ying))((yang))((zed))',
        theme: 'page_size: A7\n',
      );
      expect(_pages(pdf).first.length, greaterThan(1));
    });

    test('a heading moves with an unbreakable block that would not fit', () {
      final filler = List.filled(36, 'Line.').join('\n\n');
      final pdf = _pdf(
        '$filler\n\n== Heading\n\n[%unbreakable]\n--\n'
        '${List.filled(8, 'Kept.').join('\n\n')}\n--\n',
        theme: 'heading_min_height_after: auto\n',
      );
      final pages = _pages(pdf);
      // The heading on the page of the whole block, not alone at the
      // bottom of the page before.
      final page = pages.firstWhere((lines) => lines.contains('Heading'));
      expect(page.where((line) => line == 'Kept.'), hasLength(8));
    });

    test('an image that is not one is reported, not a failure', () {
      File('${_dir.path}/corrupt.png').writeAsStringSync('not an image');
      final logger = MemoryLogger();
      final pdf = _pdf(
        '= Doc\n:page-background-image: image:corrupt.png[]\n\nText.\n',
        attributes: {'imagesdir': _dir.path},
        logger: logger,
      );
      expect(File(pdf).existsSync(), isTrue);
      expect(
        logger.messages.map((m) => m.message.text),
        contains(contains('could not embed page background image')),
      );
    });
  }, skip: _tools && _has('qpdf') ? false : 'needs poppler and qpdf');
}
