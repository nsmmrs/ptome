// The footnotes in a margin column, lettered (`footnotes_column`,
// `footnotes_number_style`, FEAT-5qz4y9), and a list set as a tree of
// braces (the `braces` role, FEAT-6h74yn), as Burton's Anatomy of
// Melancholy prints its citations and its synopses; where the words
// land read back by Poppler, recorded in
// test/oracles/pdf_margin_notes_braces.json.gz (test/support/oracles.dart;
// ORACLES=record asks it again).
@TestOn('vm')
library;

import 'dart:io';

import 'package:ptome/ptome.dart';
import 'package:test/test.dart';

import '../support/oracles.dart';
import '../support/pdf_tools.dart';
import '../vendored_fonts.dart';

late final Oracle _recorded;

/// The words of [source] converted in [theme] over asciidoctor-pdf's,
/// with their left edges and tops, page by page (from 1).
List<({int page, String word, double x, double y})> _words(
  Directory dir,
  String source,
  String theme,
) {
  final themeFile = File('${dir.path}/theme.yml')
    ..writeAsStringSync('extends: default\n$theme');
  final pdf = File('${dir.path}/out.pdf')
    ..writeAsBytesSync(
      asciidoc.convertToBytes(
        source,
        backend: Backend.pdf,
        attributes: {'pdf-theme': themeFile.path, 'reproducible': ''},
      ),
    );
  final bbox =
      recordedRunSync(_recorded, 'pdftotext', ['-bbox', pdf.path, '-']).stdout
          as String;
  final words = <({int page, String word, double x, double y})>[];
  var page = 0;
  for (final line in bbox.split('\n')) {
    if (line.contains('<page ')) page++;
    final m = RegExp(r'xMin="([\d.]+)" yMin="([\d.]+)"[^>]*>([^<]*)<')
        .firstMatch(line);
    if (m != null) {
      words.add((
        page: page,
        word: m[3]!,
        x: double.parse(m[1]!),
        y: double.parse(m[2]!),
      ));
    }
  }
  return words;
}

void main() {
  _recorded = Oracle('pdf_margin_notes_braces', compressed: true);
  setUpAll(useVendoredFonts);
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('margin_notes.'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('the footnotes in the right margin, lettered, level with their '
      'references', () {
    final words = _words(
      dir,
      '= Notes\n\n'
          'The first claim.footnote:[Plin. lib. 7.] '
          '${'Words to fill the line and the next one. ' * 8}'
          'The second claim.footnote:[Galen, de loc. aff.]\n',
      'page:\n  margin: [0.8in, 2.2in, 0.8in, 0.8in]\n'
          'footnotes:\n  column: right\n  numbering: page\n'
          '  number_style: lower-alpha\n'
          "  reference_content: '{{number}}'\n"
          "  label_content: '{{number}} '\n",
    );
    final plin = words.firstWhere((w) => w.word == 'Plin.');
    final galen = words.firstWhere((w) => w.word == 'Galen,');
    final first = words.firstWhere((w) => w.word == 'first');
    final second = words.firstWhere((w) => w.word == 'second');
    // (Beside the text, which ends 2.2 in from the right edge.)
    final textRight = words
        .where((w) => w.y < galen.y && w.x < plin.x - 15)
        .map((w) => w.x)
        .reduce((a, b) => a > b ? a : b);
    expect(plin.x, greaterThan(textRight));
    expect(galen.x, closeTo(plin.x, 8));
    // (Level with their references' lines, not at the foot.)
    expect(plin.y, closeTo(first.y, 3));
    expect(galen.y, closeTo(second.y, 3));
    // (Lettered: a and b before the notes, in the margin.)
    final margin = [
      for (final w in words)
        if (w.x > textRight + 5 && w.y < galen.y + 20) w.word,
    ];
    expect(margin, containsAllInOrder(['a', 'Plin.', 'b', 'Galen,']));
  });

  test('a list of braces: each branch beyond its text, the text level '
      'with the middle of its branches', () {
    final words = _words(
      dir,
      '= Synopsis\n\n[.braces]\n'
          '* Melancholy\n** Causes\n*** General\n*** Particular\n'
          '** Symptoms\n** Cures\n',
      '',
    );
    double xOf(String word) => words.firstWhere((w) => w.word == word).x;
    double yOf(String word) => words.firstWhere((w) => w.word == word).y;
    // (No bullets.)
    expect(words.any((w) => w.word == '•'), isFalse);
    expect(xOf('Causes'), greaterThan(xOf('Melancholy') + 30));
    expect(xOf('Symptoms'), closeTo(xOf('Causes'), 0.5));
    expect(xOf('General'), greaterThan(xOf('Causes') + 20));
    // (A text in the middle of what it branches into.)
    expect(yOf('Causes'), closeTo((yOf('General') + yOf('Particular')) / 2, 1));
    expect(yOf('Melancholy'), closeTo((yOf('General') + yOf('Cures')) / 2, 1));
  });
}
