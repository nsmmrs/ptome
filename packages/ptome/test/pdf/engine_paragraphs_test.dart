// The modern engine's paragraphs set by plain_typesetting's paragraphs
// (FEAT-n1bkgf, FEAT-thzbh8) against the same paragraphs set by ptome's
// text box (`base_text_engine: box`): every word where the box puts it,
// within 0.01 pt, and the engine setting them (not the box again).
@TestOn('vm')
@Tags(['slow'])
library;

import 'dart:io';

import 'package:ptome/src/internal.dart';
import 'package:ptome/src/pdf/pdf.dart';
import 'package:test/test.dart';

import '../vendored_fonts.dart';

/// Poppler's pdftotext, which reads the words' boxes.
final bool _poppler =
    Process.runSync('which', ['pdftotext']).exitCode == 0 &&
    '${Process.runSync('pdftotext', ['-v']).stderr}'.contains('Poppler');

late Directory _dir;
var _count = 0;

/// [source] converted to PDF with the default theme and [theme] over it,
/// its paragraphs set by [engine] (`box` or `paragraph`); the number of
/// paragraphs the engine set, and the PDF's path.
(int, String) _pdf(String source, String theme, String engine) {
  final input = File('${_dir.path}/d${_count++}.adoc')
    ..writeAsStringSync(source);
  final out = '${input.path}.pdf';
  final themeFile = File('${input.path}-theme.yml')
    ..writeAsStringSync('extends: default\nbase_text_engine: $engine\n$theme');
  final logger = MemoryLogger()..level = Severity.debug;
  final previous = LoggerManager.logger;
  LoggerManager.logger = logger;
  try {
    convertFile(
      input.path,
      AsciidoctorOptions(
        safe: SafeMode.unsafe,
        backend: 'pdf',
        toFile: out,
        attributes: {'pdf-theme': themeFile.path, 'reproducible': ''},
      ),
    );
  } finally {
    LoggerManager.logger = previous;
  }
  final set = [
    for (final m in logger.messages)
      if (RegExp(r'paragraphs set by the engine: (\d+)')
              .firstMatch('${m.message}')
          case final found?)
        int.parse(found[1]!),
  ].fold(0, (a, b) => a + b);
  return (set, out);
}

/// Each word of [pdf] with its page and box.
List<(int, String, List<double>)> _words(String pdf) {
  final xml =
      Process.runSync('pdftotext', ['-bbox', pdf, '-']).stdout as String;
  final out = <(int, String, List<double>)>[];
  var page = 0;
  for (final line in xml.split('\n')) {
    if (line.contains('<page ')) page++;
    final m = RegExp(
      r'xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" yMax="([\d.]+)">'
      '([^<]*)<',
    ).firstMatch(line);
    if (m == null) continue;
    out.add((page, m[5]!, [for (var i = 1; i <= 4; i++) double.parse(m[i]!)]));
  }
  return out;
}

/// Expects [source] under [theme] set by the engine as the box sets it.
void _same(String source, {String theme = ''}) {
  if (!_poppler) {
    markTestSkipped('needs poppler');
    return;
  }
  final (boxSet, box) = _pdf(source, theme, 'box');
  final (set, engine) = _pdf(source, theme, 'paragraph');
  expect(boxSet, 0, reason: "the engine set some of the box's");
  expect(set, greaterThan(0), reason: 'the engine set none of it');
  final expected = _words(box);
  final actual = _words(engine);
  expect(
    [for (final (page, word, _) in actual) '$page $word'],
    [for (final (page, word, _) in expected) '$page $word'],
  );
  for (final (i, (page, word, at)) in expected.indexed) {
    for (var k = 0; k < 4; k++) {
      expect(
        actual[i].$3[k],
        closeTo(at[k], 0.01),
        reason:
            '"$word" on page $page (word $i, '
            "${const ['xMin', 'yMin', 'xMax', 'yMax'][k]})",
      );
    }
  }
}

final String _words40 = [
  for (var k = 0; k < 40; k++) ['quick', 'brown', 'fox', 'jumps'][k % 4],
].join(' ');

void main() {
  setUpAll(useVendoredFonts);
  setUpAll(() {
    registerPdf();
    _dir = Directory.systemTemp.createTempSync('ptome-engine.');
  });
  tearDownAll(() => _dir.deleteSync(recursive: true));

  test('plain paragraphs, justified and not', () {
    _same('$_words40\n\n[.text-left]\n$_words40\n');
  });

  test('a breaker per paragraph: ragged, centered, justified, any size', () {
    final varied = [
      for (var k = 0; k < 90; k++)
        [
          'a',
          'typographical',
          'of',
          'incomprehensibilities',
          'the',
          'line',
          'breaking',
          'is',
        ][(k * 7) % 8],
    ].join(' ');
    _same(
      '[.text-left]\n$varied\n\n[.text-center]\n$varied\n\n'
      '[.big]\n$varied\n\n$varied\n',
      theme: 'role:\n  big:\n    font_size: 15\n',
    );
  });

  test('font expansion: the letters of a justified line take a share', () {
    final varied = [
      for (var k = 0; k < 90; k++)
        ['a', 'typographical', 'of', 'incomprehensibilities', 'the'][(k * 3) %
            5],
    ].join(' ');
    _same(
      '$varied\n\n$varied\n',
      theme: 'base:\n  text_align: justify\n  font_expansion: true\n',
    );
  });

  test('protrusion: punctuation and hyphens hung into the margin', () {
    final punctuated = [
      for (var k = 0; k < 120; k++)
        [
          'Typography,',
          'said',
          'the',
          'reader.',
          '"Yes,"',
          'Anne-Marie',
          'answered;',
          'Victor:',
          'a',
          'line.',
        ][(k * 3) % 10],
    ].join(' ');
    for (final align in ['justify', 'left']) {
      _same(
        '$punctuated\n\n$punctuated\n',
        theme: 'base:\n  text_align: $align\n  overhang: true\n',
      );
    }
  });

  test('line-by-line breaking (base_line_breaking: greedy)', () {
    const paragraph =
        'Hypermedia is a concept extending the idea of hypertext by allowing '
        'for more complex interactions with the user and the network. The '
        'hypertext transfer protocol, used to transfer hypermedia documents, '
        'is the backbone of the modern web, and its architecture has been '
        'described at length by Roy Fielding in his dissertation, which '
        'introduced the term representational state transfer, or REST.';
    _same(paragraph, theme: 'base_line_breaking: greedy\n');
  });

  test('on a baseline grid: headings and paragraphs back on its lines', () {
    final long = List.filled(6, _words40).join(' ');
    _same(
      '= Doc\n\n== A heading\n\n$long\n\n$_words40\n\n'
      '=== A smaller heading\n\n$long\n\n[.big]\n$_words40\n\n$long\n',
      theme:
          'page_baseline_grid: true\nbase_line_pitch: 14\n'
          'role:\n  big:\n    font_size: 13\n',
    );
    // (Each page's grid from its first line.)
    _same(
      '= Doc\n\n== A heading\n\n$long\n\n$long\n\n$long\n',
      theme:
          'page_baseline_grid: true\n'
          'page_baseline_grid_anchor: first_line\n',
    );
  });

  test("a page ends at its last line's text, not the space under it", () {
    final lines = [for (var i = 0; i < 60; i++) 'Line $i of the bill.'];
    _same(
      ':line-numbers:\n\n== SEC. 2. DEFINITIONS.\n\n${lines.join('\n\n')}\n',
      theme:
          'page:\n  size: [612, 690]\n  margin: [40, 72, 40, 72]\n'
          'base:\n  font_size: 14\n  line_height: 1.857\n'
          'prose:\n  margin_bottom: 0\n'
          'heading:\n  h2_font_size: 10\n  margin_top: 0\n'
          '  margin_bottom: 0\n'
          'page_baseline_grid: true\npage_baseline_grid_anchor: first_line\n',
    );
  });

  test('labels hung left of their lines, units and margin headings', () {
    final schemes = Directory('${_dir.path}/schemes')..createSync();
    File('test/units/corpus/schemes/uk-act.yml')
        .copySync('${schemes.path}/uk-act.yml');
    _same(
      '= An Act\n:units: uk-act\n\n=== @1 Offences\n\n'
      '@(1) Subsection $_words40\n'
      '@(a) Paragraph $_words40\n'
      '@(2) Second $_words40\n',
      theme:
          'units:\n  subsection: { margin_left: 36, label_hang: true }\n'
          '  paragraph: { margin_left: 36, label_hang: true }\n',
    );
    // (A section's heading in the margin beside its first line.)
    _same(
      '= Doc\n\n== A heading\n\n$_words40\n\n== Another\n\n$_words40\n',
      theme: 'heading:\n  h2_display: margin\n',
    );
  });

  test('lines from their cap heights (base_leading), across pages', () {
    final long = List.filled(8, _words40).join(' ');
    for (final align in ['justify', 'left']) {
      _same(
        '= Doc\n\n== A heading\n\n$long\n\n$_words40 +\n$_words40\n\n'
        '[.big]\n$_words40\n\n$long\n\n$long\n',
        theme:
            'base:\n  text_align: $align\n  leading: 5\n'
            'role:\n  big:\n    font_size: 14\n',
      );
    }
  });

  test('hyphenated (:hyphens:), justified, punctuation hung', () {
    const intro =
        'To explain what a hypermedia-driven application looks like, and to '
        'contrast it with the popular SPA approach of today, we need to first '
        'explore the entire _hypermedia system_ of the web, beyond just '
        'discussing HTML. We need to look at the _network architecture_ of '
        'the web, including how a web server delivers a hypermedia API, and '
        'how to effectively use the hypermedia features available in the '
        'hypermedia _client_ (e.g., the browser).\n\n'
        'Each of these are important aspects of building an effective '
        'hypermedia-driven application, and it is the entire _hypermedia '
        'system_ that comes together to make hypermedia such a powerful '
        'architecture.\n\n'
        // (Ligatures across hyphenation points: effective, official.)
        'The effective official offered sufficient affluent efficiency, '
        'the officers effectively affirming difficult effervescent '
        'offerings, sufficiently efficient for the affluent officials.\n';
    for (final leading in ['', '  leading: 0.6em\n']) {
      _same(
        '= Doc\n:hyphens:\n\n$intro\n$intro\n$intro',
        theme:
            'page:\n  margin: [72, 126, 72, 72]\n'
            'base:\n  text_align: justify\n  overhang: true\n$leading'
            'prose:\n  text_indent_inner: 1em\n',
      );
    }
  });

  test('base_justify_width: justified to the widest line', () {
    _same(
      '[.big]\n$_words40 -- the author\n\n$_words40\n',
      theme:
          'base:\n  text_align: justify\n  justify_width: widest\n'
          'role:\n  big:\n    font_size: 15\n',
    );
  });

  test('running around a block floating to a side, and an outline', () {
    final long = List.filled(3, _words40).join(' ');
    // (A sidebar floated right: lines beside it, then below it, broken
    // again; on the next page beside what goes on of it.)
    _same(
      '= Doc\n\n$_words40\n\n[.aside]\n****\n$long\n****\n\n'
      '$long\n\n$long\n\n$long\n',
      theme:
          'base:\n  text_align: justify\n'
          'role:\n  aside:\n    float: right\n    float_width: 45%\n',
    );
    // (An image's outline, its alpha: each line in the room it leaves.)
    final circle =
        '${Directory.current.path}/test/pdf/fixtures/images/circle.png';
    _same(
      '= Doc\n\nimage::$circle[Circle,pdfwidth=40%,float=right,'
      'shape=alpha]\n\n$long\n\n$long\n',
    );
  });

  test('side notes beside their lines', () {
    final long = List.filled(3, _words40).join(' ');
    _same(
      '= Doc\n\n[[v1]]Verse one. [.xref]##*1:1* see <<v2,Two>>## '
      '$_words40\n\n$long\n\n'
      '[[v2]]Verse two. [.xref]##*1:2* see <<v1,One>>## $long\n',
      theme:
          'page:\n  columns: 2\n  column-gap: 72\n'
          'role:\n  xref:\n    display: side\n',
    );
  });

  test('drop initials beside their first lines', () {
    final long = List.filled(3, _words40).join(' ');
    // (A role's: the paragraph's own first letter, three lines deep, its
    // next words a lead-in; and one shorter than its initial.)
    _same(
      '= Doc\n\n[.dropcap]\nThe $long\n\n$long\n\n'
      '[.dropcap]\nShort one.\n\n$long\n',
      theme:
          'base:\n  text_align: justify\n'
          'role:\n  dropcap:\n    drop_lines: 3\n    drop_lead_in: 2\n'
          '  lead-in:\n    text_transform: uppercase\n',
    );
    // (A section's first paragraph, a book's chapter.)
    _same(
      '= Doc\n:doctype: book\n\n== One\n\nWhen $long\n\n$long\n',
      theme: 'heading_h2_initial_lines: 2\nheading_h2_initial_lead_in: 2\n',
    );
  });

  test("an abstract's first line in its own style", () {
    final long = List.filled(3, _words40).join(' ');
    _same(
      '= Doc\n\n[abstract]\n.Abstract\n--\n$long\n\n$long\n--\n',
      theme:
          'base:\n  text_align: justify\n'
          'abstract:\n  first_line_font_style: bold\n',
    );
    _same(
      '= Doc\n\n[abstract]\n.Abstract\n--\n$long\n\n$long\n--\n',
      theme: 'abstract:\n  first_line_font_color: "FF0000"\n',
    );
  });

  test('inline images, formulas, decorated code and faked small capitals', () {
    final images = '${Directory.current.path}/test/pdf/fixtures/images';
    final words = List.filled(2, _words40).join(' ');
    // (Images at the size they ask for, beside text and on their own
    // line; one taller than a line raising it.)
    _same(
      '= Doc\n\n$words image:$images/red.png[width=10] $words '
      'image:$images/box.svg[width=14] $words\n\n'
      '$words image:$images/tall.png[width=20] $words\n',
    );
    // (Formulas, standing on their depth. One taller than the text makes
    // its line taller, where the box lets it reach into the line above.)
    _same(
      '= Doc\n:stem:\n\n$words stem:[x+y] $words stem:[a b] and '
      'stem:[n] $words\n',
    );
    // (Text on a background with a border, none of its own room.)
    _same(
      '$words [.hl]#marked text here# $words [.hl]#more# $words\n',
      theme:
          'role:\n  hl:\n    background_color: EEEEEE\n'
          '    border_color: CCCCCC\n    border_width: 0.5\n'
          '    border_radius: 2\n',
    );
    // (Small capitals the font lacks, made from its capitals.)
    _same(
      '$words [.sc]#small capitals here# $words\n',
      theme: 'role:\n  sc:\n    font_variant: small-caps\n',
    );
  });

  test('captions: a titled paragraph, an example, a listing', () {
    final long = List.filled(2, _words40).join(' ');
    _same(
      '.A paragraph titled at some length, its caption over two lines when '
      'it runs on as this one does across the page\n$long\n\n'
      '.An example\n====\n$long\n====\n\n'
      '.A listing\n----\ncode\n----\n\n$long\n',
      theme: 'caption:\n  font_style: italic\n  font_size: 9\n',
    );
  });

  test('table cells', () {
    String row(int r) =>
        '|${_words40.substring(0, 60 + r * 20)} |cell $r '
        '|${_words40.substring(r * 10, 100 + r * 10)}';
    final rows = [for (var r = 0; r < 6; r++) row(r)].join('\n');
    _same('[cols="2,1,3"]\n|===\n$rows\n|===\n\n$_words40\n');
    _same(
      '[cols="a,a",options=header]\n|===\n|Head one |Head two\n'
      '|${_words40.substring(0, 90)} |short\n|===\n',
    );
    _same('|===\n|auto width |${_words40.substring(0, 140)}\n|===\n');
  });

  test('headings', () {
    final long = List.filled(3, _words40).join(' ');
    String section(int i) =>
        '== Section $i, a title long enough to run over two lines when it '
        'is set this large\n\n$long\n\n=== A smaller one\n\n$long\n';
    final sections = [for (var i = 0; i < 6; i++) section(i)].join('\n');
    _same('= Doc\n\n$sections');
    _same(
      '= Doc\n:doctype: book\n\n$sections',
      theme: 'heading:\n  h2_text_align: center\n  h3_font_style: italic\n',
    );
  });

  test('list items, admonitions, a table of contents', () {
    final long = List.filled(2, _words40).join(' ');
    _same(
      '= Doc\n:toc:\n\n== One, a section whose title runs on long enough to '
      'wrap in the table of contents\n\n$long\n\n'
      '* $_words40\n* short\n** $_words40\n\n'
      '. $_words40\n. two\n\n'
      'term:: $_words40\n\n'
      'NOTE: $long\n\n== Two\n\n$long\n',
    );
  });

  test('buttons and callouts', () {
    // (Not kbd chips: a line with monospace text sits apart, BUG-kd9h5p.)
    _same(
      '= Doc\n:experimental:\n\n$_words40 btn:[Save] and '
      'btn:[Open File] $_words40\n\n'
      '----\nputs "hello" # <1>\nexit # <2>\n----\n'
      '<1> $_words40\n<2> Exits.\n',
    );
  });

  test('source listings wrapped, with their indent kept', () {
    const words =
        'call one two three four five six seven eight nine ten eleven '
        'twelve thirteen fourteen fifteen sixteen';
    final code = [for (var i = 0; i < 40; i++) '${'  ' * (i % 4)}$words $i']
        .join('\n');
    _same('$_words40\n\n----\n$code\n----\n\n$_words40\n');
    _same(
      '$_words40\n\n.Titled\n----\n$code\n----\n',
      theme: 'code:\n  font_size: 12\n',
    );
  });

  test('a listing shrunk to fit (%autofit)', () {
    const words = 'a line of code much too long for the column at its own size';
    final wide = [
      for (var i = 0; i < 6; i++) '$words $i and then some more of it',
    ].join('\n');
    _same('$_words40\n\n[%autofit]\n----\n$wide\n----\n');
  });

  test('base_text_align_last: the unstretched lines aligned apart', () {
    for (final last in ['center', 'right']) {
      _same(
        '$_words40 +\n$_words40\n\n$_words40\n',
        theme: 'base:\n  text_align: justify\n  text_align_last: $last\n',
      );
    }
  });
}
