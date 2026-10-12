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

  test('base_text_align_last: the unstretched lines aligned apart', () {
    for (final last in ['center', 'right']) {
      _same(
        '$_words40 +\n$_words40\n\n$_words40\n',
        theme: 'base:\n  text_align: justify\n  text_align_last: $last\n',
      );
    }
  });
}
