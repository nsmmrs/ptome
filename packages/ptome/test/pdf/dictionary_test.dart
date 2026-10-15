// What a dictionary's pages take (Johnson's Dictionary in the showcase):
// a paragraph hung by a negative indent or set in (FEAT-43wrgt), an
// author set flush right at the end of a quotation's line (FEAT-tc5vgk),
// guide words over each column (FEAT-0ks2ly), a catchword at the foot
// (FEAT-mm205k), and small capitals a font lacks made from the lowercase
// letters alone (BUG-mpp8wr). The pages read back by Poppler and qpdf,
// recorded in test/oracles/pdf_dictionary.json.gz
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
  return File('${_scratch.path}/d$n.pdf')..writeAsBytesSync(
    asciidoc.convertToBytes(
      source,
      backend: Backend.pdf,
      attributes: {'pdf-theme': themeFile.path, 'reproducible': ''},
    ),
  );
}

/// Each page's words with their boxes (left, top, right, bottom).
List<List<(String, List<double>)>> _words(File pdf) {
  final xml =
      recordedRunSync(_recorded, 'pdftotext', ['-bbox', pdf.path, '-']).stdout
          as String;
  final pages = <List<(String, List<double>)>>[];
  for (final line in xml.split('\n')) {
    if (line.contains('<page ')) pages.add([]);
    final m = RegExp(
      r'xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" yMax="([\d.]+)">'
      '([^<]*)<',
    ).firstMatch(line);
    if (m == null) continue;
    pages.last.add((m[5]!, [for (var i = 1; i <= 4; i++) double.parse(m[i]!)]));
  }
  return pages;
}

List<double> _at(List<(String, List<double>)> words, String word) =>
    words.firstWhere((w) => w.$1 == word).$2;

/// Where the line after [word]'s on [page] starts.
double _nextLineStart(List<(String, List<double>)> page, String word) {
  final top = _at(page, word)[1];
  final below = [
    for (final (_, box) in page)
      if (box[1] > top + 2) box[1],
  ];
  final next = below.reduce((a, b) => a < b ? a : b);
  return [
    for (final (_, box) in page)
      if ((box[1] - next).abs() < 1) box[0],
  ].reduce((a, b) => a < b ? a : b);
}

/// A long entry for [word], anchored with its first three letters.
String _entry(String word) =>
    '[[w-$word,${word.substring(0, 3).toUpperCase()}]]\n'
    '${word[0].toUpperCase()}${word.substring(1)}. '
    '${List.filled(40, _long).join(' ')}.';

const String _long =
    'a paragraph long enough to run on to a second line and a third, so '
    'that where its lines start can be seen against the first';

void main() {
  _recorded = Oracle('pdf_dictionary', compressed: true);
  setUpAll(() {
    useVendoredFonts();
    _scratch = Directory.systemTemp.createTempSync('ptome-dictionary.');
  });
  tearDownAll(() => _scratch.deleteSync(recursive: true));

  test('a negative indent hangs; margin_left sets a paragraph in', () {
    final page = _words(
      _pdf(
        ':nofooter:\n\n[.entry]\nHung $_long.\n\n[.cite]\nSetin $_long.\n',
        'role:\n  entry:\n    text_indent: -1em\n'
            '  cite:\n    margin_left: 2em\n    text_indent: 1em\n',
      ),
    ).first;
    final hung = _at(page, 'Hung')[0];
    final setIn = _at(page, 'Setin')[0];
    // (Each paragraph's second line.)
    expect(_nextLineStart(page, 'Hung') - hung, closeTo(10.5, 0.5));
    expect(setIn - hung, closeTo(31.5, 1));
    expect(setIn - _nextLineStart(page, 'Setin'), closeTo(10.5, 0.5));
  });

  test('an author flush right: at the end of the line, else on its own', () {
    final page = _words(
      _pdf(
        ':nofooter:\n\nShort. [.author]#Dryden.#\n\n'
            '$_long. [.author]#Bacon’s Natural History.#\n\nEnd.\n',
        'role:\n  author:\n    flush: right\n',
      ),
    ).first;
    final right = _at(page, 'Dryden.')[2];
    final short = _at(page, 'Short.');
    expect(_at(page, 'Dryden.')[1], closeTo(short[1], 0.5));
    final history = _at(page, 'History.');
    expect(history[2], closeTo(right, 0.5));
    // (On the text's last line two spaces from it at the least, or on a
    // line of its own below it.)
    final first = _at(page, 'first.');
    final bacon = _at(page, 'Bacon’s');
    expect(
      (bacon[1] - first[1]).abs() < 1
          ? bacon[0] - first[2] > 5
          : bacon[1] > first[1],
      isTrue,
    );
  });

  test('guide words over each column, a catchword at the foot', () {
    final entries = [
      for (final word in ['apple', 'banana', 'cherry', 'damson', 'elder'])
        _entry(word),
    ].join('\n\n');
    final pages = _words(
      _pdf(
        '= Doc\n\n$entries\n',
        'page:\n  columns: 2\nrunning_content:\n  marks: w-\n'
            'header:\n  height: 0.6in\n  columns: "<50% =0% >50%"\n'
            '  recto: { left: { content: "{column-1-last-mark}" }, '
            'right: { content: "{column-2-last-mark}" } }\n'
            '  verso: { left: { content: "{column-1-last-mark}" }, '
            'right: { content: "{column-2-last-mark}" } }\n'
            'footer:\n  recto: { right: { content: "{page-catchword}" } }\n'
            '  verso: { right: { content: "{page-catchword}" } }\n',
      ),
    );
    expect(pages.length, greaterThan(1));
    // (The first page's head: its columns' last entries' guides.)
    final heads = [for (final (word, _) in pages.first.take(2)) word];
    expect(heads, everyElement(matches(RegExp(r'^[A-E][A-Z]{2}$'))));
    expect(heads.first.compareTo(heads.last), lessThanOrEqualTo(0));
    // (Its catchword, the last word on it: the next page's first word
    // after the head.)
    final catchword = pages.first.last.$1;
    final next = pages[1].skip(2).first.$1;
    expect(catchword, next);
  });

  test('small capitals a font lacks: the capitals kept at full size', () {
    final content = qpdfQdf(
      _recorded,
      _pdf(
        ':nofooter:\n\n[.sc]#Lewdly#\n',
        'role:\n  sc:\n    font_variant: small-caps\n',
      ).readAsBytesSync(),
    );
    final sizes = {
      for (final m in RegExp(
        r'/F\d+(?:\.\d+)? ([\d.]+) Tf',
      ).allMatches(content))
        m[1]!,
    };
    expect(sizes, hasLength(2), reason: '$sizes');
  });
}
