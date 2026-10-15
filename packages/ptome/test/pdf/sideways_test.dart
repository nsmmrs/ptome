// Ptome's `sideways` role (FEAT-wlw5wq), a block turned a quarter to the
// left on a page of its own as Herbert's Easter-wings is printed, and
// the theme's `base_font_variant_alternates` and `_ligatures`
// (FEAT-h9smyr), the long s and the ligatures of an early printed book;
// the pages' content read back by qpdf, recorded in
// test/oracles/pdf_sideways.json.gz (test/support/oracles.dart;
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

/// The test fonts of plain_typesetting: historical-test.ttf's `hist`
/// sets s as the long s before a letter, its `dlig` joins c and t.
final String _fonts = Directory('../plain_typesetting/test/fonts')
    .absolute
    .path;

late Directory _scratch;

/// [source] converted in asciidoctor-pdf's theme (its fonts vendored),
/// or in [theme] over it; the pages' content, uncompressed.
String _content(
  String source, {
  String? theme,
  Map<String, String> attributes = const {},
}) {
  final themeFile = theme == null
      ? null
      : (File('${_scratch.path}/t${_scratch.listSync().length}-theme.yml')
          ..writeAsStringSync('extends: default\n$theme'));
  final pdf = asciidoc.convertToBytes(
    source,
    backend: Backend.pdf,
    attributes: {
      'pdf-theme': themeFile?.path ?? 'default',
      if (themeFile != null) 'pdf-fontsdir': _fonts,
      'reproducible': '',
      ...attributes,
    },
  );
  return qpdfQdf(_recorded, pdf);
}

const String _wings = '''
= Sideways

Before.

[verse.sideways]
____
Lord, who createdst man in wealth and store,
Though foolishly he lost the same,
____

After.
''';

/// The transformation matrices [content] sets (`cm`).
List<String> _matrices(String content) => [
  for (final m in RegExp(
    r'(-?[\d.]+ -?[\d.]+ -?[\d.]+ -?[\d.]+ -?[\d.]+ -?[\d.]+) cm',
  ).allMatches(content))
    m[1]!,
];

/// How many pages [content] has.
int _pages(String content) =>
    RegExp(r'/Type /Page\b').allMatches(content).length;

/// The glyph codes [content] shows, in order (two bytes each).
List<String> _codes(String content) => [
  for (final array in RegExp(r'\[([^\]]*)\]\s*TJ').allMatches(content))
    for (final hex in RegExp('<([0-9a-fA-F]*)>').allMatches(array[1]!))
      for (var i = 0; i + 4 <= hex[1]!.length; i += 4)
        hex[1]!.substring(i, i + 4),
];

const String _historical = '''
font:
  catalog:
    Historical:
      normal: historical-test.ttf
      italic: historical-test.ttf
      bold: historical-test.ttf
      bold_italic: historical-test.ttf
base:
  font_family: Historical
''';

void main() {
  _recorded = Oracle('pdf_sideways', compressed: true);
  setUpAll(() {
    useVendoredFonts();
    _scratch = Directory.systemTemp.createTempSync('ptome-sideways.');
  });
  tearDownAll(() => _scratch.deleteSync(recursive: true));

  test('the block turned a quarter to the left, on a page of its own', () {
    final sideways = _content(_wings);
    final plain = _content(_wings.replaceFirst('.sideways', ''));
    final turns = _matrices(sideways).where((m) => m.startsWith('0 1 -1 0 '));
    expect(turns, hasLength(1), reason: '${_matrices(sideways)}');
    expect(_matrices(plain).where((m) => m.startsWith('0 1 -1 0 ')), isEmpty);
    // (Before, the verse, after: three pages; one without the role.)
    expect(_pages(sideways), 3);
    expect(_pages(plain), 1);
  });

  test('not under asciidoctor-compat', () {
    final compat = _content(
      _wings,
      attributes: const {'asciidoctor-compat': 'pdf'},
    );
    expect(_matrices(compat).where((m) => m.startsWith('0 1 -1 0 ')), isEmpty);
  });

  test("the long s and the ligatures by the font's own rules", () {
    const source = ':nofooter:\n\ncast as a tact';
    final plain = _codes(_content(source, theme: _historical));
    final historical = _codes(
      _content(
        source,
        theme:
            '$_historical'
            '  font_variant_alternates: historical-forms\n'
            '  font_variant_ligatures: discretionary-ligatures\n',
      ),
    );
    // (The c and t of "tact" joined: a glyph fewer; the s of "cast"
    // long before its t, the s of "as" not.)
    expect(historical, hasLength(plain.length - 1));
    expect(historical.sublist(0, 4), isNot(plain.sublist(0, 4)));
    expect(historical.sublist(4, 8), plain.sublist(4, 8));
  });
}
